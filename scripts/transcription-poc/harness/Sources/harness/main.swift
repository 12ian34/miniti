import Foundation
import AVFoundation
import FluidAudio
import Speech
import Darwin

// Usage:
//   harness nemotron <lang e.g. en-US|sv-SE|auto> <chunkMs> <out.json> <wav...>
//   harness apple <locale e.g. en-US> <out.json> <wav...>
//   harness parakeet <out.json> <wav...>
// Output: JSON array of {file, text, seconds, wallSeconds, rtf, peakRSSMB, firstPartialLag, meanChunkMs, p95ChunkMs, tokens:[{t,s,e}]}

struct Row: Codable {
    var file: String; var text: String; var seconds: Double; var wallSeconds: Double; var rtf: Double
    var peakRSSMB: Double; var meanChunkMs: Double?; var p95ChunkMs: Double?; var detectedLanguage: String?
    var tokens: [[Double]]?  // [start, end]
    var error: String?
}

func peakRSSMB() -> Double {
    var info = rusage_info_current(); 
    let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0) } }
    return r == 0 ? Double(info.ri_lifetime_max_phys_footprint) / 1_048_576 : -1
}

func loadSamples(_ path: String) throws -> [Float] {
    let c = AudioConverter()
    return try c.resampleAudioFile(path: path)
}

func pct(_ xs: [Double], _ p: Double) -> Double { guard !xs.isEmpty else { return 0 }; let s = xs.sorted(); return s[min(s.count - 1, Int(Double(s.count - 1) * p))] }

func write(_ rows: [Row], _ out: String) throws {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
    try enc.encode(rows).write(to: URL(fileURLWithPath: out))
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: see source"); exit(2) }
let mode = args[1]

func runNemotron() async throws {
    let lang = args[2]; let chunkMs = Int(args[3])!; let out = args[4]; let files = Array(args[5...])
    let dir = try await StreamingNemotronMultilingualAsrManager.downloadVariant(languageCode: lang, chunkMs: chunkMs)
    FileHandle.standardError.write("model dir: \(dir.path)\n".data(using: .utf8)!)
    var rows: [Row] = []
    for f in files {
        do {
            let samples = try loadSamples(f)
            let seconds = Double(samples.count) / 16000
            let mgr = StreamingNemotronMultilingualAsrManager()
            try await mgr.loadModels(from: dir)
            if lang != "auto" { await mgr.setLanguage(lang) }
            // Feed in chunk-sized blocks and time each, as a live session would.
            let step = chunkMs * 16
            var chunkTimes: [Double] = []
            let t0 = Date()
            var i = 0
            while i < samples.count {
                let end = min(i + step, samples.count)
                let c0 = Date()
                _ = try await mgr.process(samples: Array(samples[i..<end]))
                chunkTimes.append(Date().timeIntervalSince(c0) * 1000)
                i = end
            }
            let (text, timings) = try await mgr.finishWithTokenTimings()
            let wall = Date().timeIntervalSince(t0)
            let detected = await mgr.detectedLanguage()
            rows.append(Row(file: f, text: text, seconds: seconds, wallSeconds: wall, rtf: wall / seconds, peakRSSMB: peakRSSMB(),
                            meanChunkMs: chunkTimes.reduce(0, +) / Double(max(chunkTimes.count, 1)), p95ChunkMs: pct(chunkTimes, 0.95),
                            detectedLanguage: detected, tokens: timings.map { [$0.startTime, $0.endTime] }, error: nil))
            await mgr.cleanup()
        } catch {
            rows.append(Row(file: f, text: "", seconds: 0, wallSeconds: 0, rtf: 0, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: nil, error: "\(error)"))
        }
        FileHandle.standardError.write("done \(f)\n".data(using: .utf8)!)
        try write(rows, out)
    }
}

func runParakeet() async throws {
    let out = args[2]; let files = Array(args[3...])
    let models = try await AsrModels.downloadAndLoad(version: .v3)
    let mgr = AsrManager(config: .default, models: models)
    var rows: [Row] = []
    for f in files {
        do {
            let samples = try loadSamples(f)
            let seconds = Double(samples.count) / 16000
            var state = try TdtDecoderState()
            let t0 = Date()
            let r = try await mgr.transcribe(samples, decoderState: &state)
            let wall = Date().timeIntervalSince(t0)
            rows.append(Row(file: f, text: r.text, seconds: seconds, wallSeconds: wall, rtf: wall / seconds, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil,
                            tokens: r.tokenTimings?.map { [$0.startTime, $0.endTime] }, error: nil))
        } catch {
            rows.append(Row(file: f, text: "", seconds: 0, wallSeconds: 0, rtf: 0, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: nil, error: "\(error)"))
        }
        try write(rows, out)
    }
}


func runParakeetLive() async throws {
    let out = args[2]; let files = Array(args[3...])
    let models = try await AsrModels.downloadAndLoad(version: .v3)
    var rows: [Row] = []
    for f in files {
        do {
            let samples = try loadSamples(f)
            let seconds = Double(samples.count) / 16000
            let mgr = SlidingWindowAsrManager(config: .streaming)
            try await mgr.loadModels(models)
            try await mgr.startStreaming(source: .microphone)
            var nUpdates = 0; var nConfirmed = 0
            let updates = await mgr.transcriptionUpdates
            let collector = Task { for await u in updates { nUpdates += 1; if u.isConfirmed { nConfirmed += 1 } } }
            let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            let step = 1600  // 100 ms packets, like the app's capture callback
            let t0 = Date()
            var i = 0
            while i < samples.count {
                let end = min(i + step, samples.count)
                let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(end - i))!
                buf.frameLength = AVAudioFrameCount(end - i)
                samples[i..<end].withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: end - i) }
                await mgr.streamAudio(buf)
                i = end
                await Task.yield()
            }
            let text = try await mgr.finish()
            let wall = Date().timeIntervalSince(t0)
            collector.cancel()
            rows.append(Row(file: f, text: text, seconds: seconds, wallSeconds: wall, rtf: wall / seconds, peakRSSMB: peakRSSMB(), meanChunkMs: Double(nUpdates), p95ChunkMs: Double(nConfirmed), detectedLanguage: nil, tokens: nil, error: nil))
            await mgr.cleanup()
        } catch {
            rows.append(Row(file: f, text: "", seconds: 0, wallSeconds: 0, rtf: 0, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: nil, error: "\(error)"))
        }
        FileHandle.standardError.write("done \(f)\n".data(using: .utf8)!)
        try write(rows, out)
    }
}


// Real-time paced feed of one file; prints lag of each update = wall time since start - end time of the last timed token.
func runPaced() async throws {
    let engine = args[2]; let f = args[3]
    let samples = try loadSamples(f)
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let step = 1600
    let t0 = Date()
    func elapsed() -> Double { Date().timeIntervalSince(t0) }
    var lags: [Double] = []
    var confirmedLags: [Double] = []
    if engine == "parakeetlive" {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let mgr = SlidingWindowAsrManager(config: .streaming)
        try await mgr.loadModels(models)
        try await mgr.startStreaming(source: .microphone)
        let updates = await mgr.transcriptionUpdates
        let start = Date()
        let collector = Task {
            for await u in updates {
                print(String(format: "upd t=%.1f confirmed=%d timings=%d chars=%d", Date().timeIntervalSince(start), u.isConfirmed ? 1 : 0, u.tokenTimings.count, u.text.count))
                guard let last = u.tokenTimings.last else { continue }
                let lag = Date().timeIntervalSince(start) - last.endTime
                print(String(format: "t=%.1f confirmed=%d lastTokenEnd=%.1f lag=%.2f text=%@", Date().timeIntervalSince(start), u.isConfirmed ? 1 : 0, last.endTime, lag, String(u.text.suffix(40))))
                if u.isConfirmed { confirmedLags.append(lag) } else { lags.append(lag) }
            }
        }
        var i = 0
        while i < samples.count {
            let end = min(i + step, samples.count)
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(end - i))!
            buf.frameLength = AVAudioFrameCount(end - i)
            samples[i..<end].withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: end - i) }
            await mgr.streamAudio(buf)
            i = end
            let target = Double(i) / 16000
            let wait = target - Date().timeIntervalSince(start)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        }
        _ = try await mgr.finish()
        collector.cancel()
    } else {
        let chunkMs = Int(args[4]) ?? 1120
        let dir = try await StreamingNemotronMultilingualAsrManager.downloadVariant(languageCode: "en-US", chunkMs: chunkMs)
        let mgr = StreamingNemotronMultilingualAsrManager()
        try await mgr.loadModels(from: dir)
        await mgr.setLanguage("en-US")
        let start = Date()
        var i = 0
        var lastCount = 0
        while i < samples.count {
            let end = min(i + step, samples.count)
            _ = try await mgr.process(samples: Array(samples[i..<end]))
            i = end
            let timings = await mgr.getTokenTimings()
            if timings.count > lastCount, let last = timings.last {
                lastCount = timings.count
                let lag = Date().timeIntervalSince(start) - last.endTime
                lags.append(lag)
                let text = await mgr.getPartialTranscript()
                print(String(format: "t=%.1f lastTokenEnd=%.1f lag=%.2f text=%@", Date().timeIntervalSince(start), last.endTime, lag, String(text.suffix(40))))
            }
            let target = Double(i) / 16000
            let wait = target - Date().timeIntervalSince(start)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        }
        _ = try await mgr.finish()
    }
    func stats(_ xs: [Double]) -> String { xs.isEmpty ? "n/a" : String(format: "n=%d median=%.2f p90=%.2f max=%.2f", xs.count, pct(xs, 0.5), pct(xs, 0.9), xs.max()!) }
    print("SUMMARY \(engine) hypothesis/partial lag: \(stats(lags))")
    if engine == "parakeetlive" { print("SUMMARY \(engine) confirmed lag: \(stats(confirmedLags))") }
    _ = elapsed()
}

@available(macOS 26.0, *)
func runApple() async throws {
    let localeId = args[2]; let out = args[3]; let files = Array(args[4...])
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeId)) else {
        try write([Row(file: "-", text: "", seconds: 0, wallSeconds: 0, rtf: 0, peakRSSMB: 0, meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: nil, error: "locale unsupported: \(localeId)")], out); return
    }
    let probe = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    if let req = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
        FileHandle.standardError.write("installing assets for \(locale.identifier)\n".data(using: .utf8)!)
        try await req.downloadAndInstall()
    }
    var rows: [Row] = []
    for f in files {
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: f))
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            // A transcriber module's results stream ends when its analyzer finishes, so make a fresh one per file.
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            var text = ""; var toks: [[Double]] = []
            let t0 = Date()
            let collector = Task {
                for try await result in transcriber.results where result.isFinal {
                    let s = result.text
                    text += String(s.characters) + " "
                    for run in s.runs { if let r = run.audioTimeRange { toks.append([r.start.seconds, r.end.seconds]) } }
                }
            }
            if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) } else { await analyzer.cancelAndFinishNow() }
            try await collector.value
            let wall = Date().timeIntervalSince(t0)
            rows.append(Row(file: f, text: text, seconds: seconds, wallSeconds: wall, rtf: wall / seconds, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: toks, error: nil))
        } catch {
            rows.append(Row(file: f, text: "", seconds: 0, wallSeconds: 0, rtf: 0, peakRSSMB: peakRSSMB(), meanChunkMs: nil, p95ChunkMs: nil, detectedLanguage: nil, tokens: nil, error: "\(error)"))
        }
        try write(rows, out)
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        switch mode {
        case "nemotron": try await runNemotron()
        case "parakeet": try await runParakeet()
        case "parakeetlive": try await runParakeetLive()
        case "paced": try await runPaced()
        case "apple": if #available(macOS 26.0, *) { try await runApple() } else { print("needs macOS 26") }
        default: print("unknown mode")
        }
    } catch { FileHandle.standardError.write("fatal: \(error)\n".data(using: .utf8)!) }
    sem.signal()
}
sem.wait()
