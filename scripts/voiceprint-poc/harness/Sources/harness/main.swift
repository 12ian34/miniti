import AVFoundation
import FluidAudio
import Foundation

// Usage: harness <session.rttm> <audio.16k.wav> <out.json> [windowSeconds=6] [minSeconds=3]
// For every reference speaker: concatenate that speaker's non-overlapping speech, cut it into
// windows, embed each window with CAM++ (192-d, L2-normalised), and write the embeddings.

struct Window: Codable { let speaker: String; let index: Int; let seconds: Double; let embedding: [Float]; let ms: Double }
struct Output: Codable { let session: String; let mic: String; let windows: [Window]; let speakers: [String] }

struct Turn { let speaker: String; let start: Double; let end: Double }

func loadRTTM(_ path: String) throws -> [Turn] {
    try String(contentsOfFile: path).split(separator: "\n").compactMap { line in
        let f = line.split(separator: " ")
        guard f.count >= 8, f[0] == "SPEAKER", let s = Double(f[3]), let d = Double(f[4]) else { return nil }
        return Turn(speaker: String(f[7]), start: s, end: s + d)
    }
}

/// Parts of each turn that no other speaker overlaps.
func exclusiveTurns(_ turns: [Turn]) -> [Turn] {
    var out: [Turn] = []
    for t in turns {
        var pieces = [(t.start, t.end)]
        for o in turns where o.speaker != t.speaker && o.end > t.start && o.start < t.end {
            pieces = pieces.flatMap { (a, b) -> [(Double, Double)] in
                var r: [(Double, Double)] = []
                if o.start > a { r.append((a, min(b, o.start))) }
                if o.end < b { r.append((max(a, o.end), b)) }
                return r.filter { $0.1 - $0.0 > 0.05 }
            }
        }
        out += pieces.map { Turn(speaker: t.speaker, start: $0.0, end: $0.1) }
    }
    return out
}

func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    precondition(file.fileFormat.sampleRate == 16_000, "need 16 kHz input")
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: harness <rttm> <wav> <out.json> [windowSeconds] [minSeconds]"); exit(2) }
let windowSeconds = args.count > 4 ? Double(args[4])! : 6
let minSeconds = args.count > 5 ? Double(args[5])! : 3
let sessionName = URL(fileURLWithPath: args[1]).deletingPathExtension().lastPathComponent
let micName = URL(fileURLWithPath: args[2]).lastPathComponent.replacingOccurrences(of: ".16k.wav", with: "").replacingOccurrences(of: sessionName + ".", with: "")

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        let embedder = try await CampPlusEmbedder.load()
        let samples = try loadSamples(args[2])
        let turns = exclusiveTurns(try loadRTTM(args[1]))
        let speakers = Array(Set(turns.map(\.speaker))).sorted()
        var windows: [Window] = []
        for speaker in speakers {
            var pool: [Float] = []
            var index = 0
            let need = Int(windowSeconds * 16_000)
            for t in turns.filter({ $0.speaker == speaker }).sorted(by: { $0.start < $1.start }) {
                let a = max(0, Int(t.start * 16_000)), b = min(samples.count, Int(t.end * 16_000))
                guard b > a else { continue }
                pool.append(contentsOf: samples[a..<b])
                while pool.count >= need {
                    let chunk = Array(pool.prefix(need)); pool.removeFirst(need)
                    let t0 = Date()
                    let e = try await embedder.embed(audio: chunk)
                    windows.append(Window(speaker: speaker, index: index, seconds: windowSeconds, embedding: e, ms: Date().timeIntervalSince(t0) * 1000))
                    index += 1
                }
            }
            if Double(pool.count) / 16_000 >= minSeconds {
                let t0 = Date()
                let e = try await embedder.embed(audio: pool)
                windows.append(Window(speaker: speaker, index: index, seconds: Double(pool.count) / 16_000, embedding: e, ms: Date().timeIntervalSince(t0) * 1000))
            }
        }
        let enc = JSONEncoder()
        try enc.encode(Output(session: sessionName, mic: micName, windows: windows, speakers: speakers)).write(to: URL(fileURLWithPath: args[3]))
        let ms = windows.map(\.ms)
        print("\(sessionName) \(micName): \(windows.count) windows, \(speakers.count) speakers, mean \(Int(ms.reduce(0, +) / Double(max(1, ms.count)))) ms per window")
    } catch {
        print("error: \(error)"); exit(1)
    }
    semaphore.signal()
}
semaphore.wait()
