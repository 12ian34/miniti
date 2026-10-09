import Foundation
import FluidAudio

// MARK: - Language support

/// Which miniti languages the on-device recogniser (NVIDIA Nemotron 3.5 ASR Streaming
/// Multilingual 0.6B through FluidAudio) handles, from the offline comparison on
/// 2026-10-09 (`scripts/transcription-poc/RESULTS.md`). Tiers decide copy and routing, not
/// just a label: a cloud-only language keeps Deepgram even with the setting on, and the
/// setting says so.
enum OnDeviceTranscriptionSupport {
    enum Tier: Equatable, Sendable {
        /// Measured within a few WER points of Deepgram on meeting audio.
        case tested
        /// Runs locally but measured clearly behind Deepgram; labelled as such.
        case experimental
        /// Measured too far behind to offer; Deepgram transcribes this language.
        case cloudOnly
    }

    /// The chunk tier the offline comparison used. 560 ms gains no accuracy and the package
    /// warns it loses punctuation on long sessions; 2240 ms lags a second more.
    static let chunkMs = 1120

    /// Approximate download size per model family, for the notice before the download.
    static func approximateDownloadMB(family: String) -> Int {
        family == "latin" ? 590 : 640
    }

    /// The model's language code for a miniti language code, nil for cloud-only languages.
    static func nemotronLanguage(forCode code: String) -> String? {
        guard tier(forCode: code) != .cloudOnly else { return nil }
        switch code {
        case "en": return "en-US"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "pt": return "pt-PT"
        case "it": return "it-IT"
        case "nl": return "nl-NL"
        case "ru": return "ru-RU"
        default: return nil
        }
    }

    /// FluidAudio's model family for a language: `latin` (vocabulary pruned to en, es, fr, it,
    /// pt, de) or the full-vocabulary `multilingual` build.
    static func family(forCode code: String) -> String {
        StreamingNemotronMultilingualAsrManager.languageDirectory(for: nemotronLanguage(forCode: code) ?? "auto")
    }

    static func tier(forCode code: String) -> Tier {
        switch code {
        case "en", "es", "fr", "de", "pt", "it": return .tested
        case "nl", "ru": return .experimental
        default: return .cloudOnly
        }
    }

    static func tier(for language: TranscriptionLanguage) -> Tier {
        tier(forCode: language.rawValue)
    }

    static var testedLanguageNames: [String] {
        TranscriptionLanguage.allCases.filter { tier(for: $0) == .tested }.map(\.englishName)
    }

    static var experimentalLanguageNames: [String] {
        TranscriptionLanguage.allCases.filter { tier(for: $0) == .experimental }.map(\.englishName)
    }

    static var cloudOnlyLanguageNames: [String] {
        TranscriptionLanguage.allCases.filter { tier(for: $0) == .cloudOnly }.map(\.englishName)
    }
}

/// Setting copy shared by the platforms. Built from the tiers so the language lists cannot
/// drift from what the code routes.
enum OnDeviceTranscriptionCopy {
    static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    static var description: String {
        let tested = joined(OnDeviceTranscriptionSupport.testedLanguageNames)
        let experimental = joined(OnDeviceTranscriptionSupport.experimentalLanguageNames)
        let cloud = joined(OnDeviceTranscriptionSupport.cloudOnlyLanguageNames)
        let latinMB = OnDeviceTranscriptionSupport.approximateDownloadMB(family: "latin")
        let multiMB = OnDeviceTranscriptionSupport.approximateDownloadMB(family: "multilingual")
        return "Runs NVIDIA's Nemotron speech model on this Mac, so audio never leaves it for transcription. Downloads a \(latinMB) MB model for \(tested), or a \(multiMB) MB model for \(experimental), which made more errors than Deepgram in our tests. \(cloud) still use Deepgram. Live text arrives about a second later than with Deepgram, and the transcript still goes to the AI service, or your own OpenAI account, for summaries. Set Speakers to This Mac as well to tell remote speakers apart. Applies to new recordings."
    }
}

/// Private mode copy, shared by Settings and the insights pane.
enum PrivateModeCopy {
    static let title = "Private mode"
    static let description = "Your meeting stays on this Mac. Transcription and speakers run here, and nothing is sent to miniti, Deepgram, OpenAI or TypeSafe. You lose summaries, questions, Sales, templates, catch-up, speaker names, Playbook and investigations. Coaching, history, search, export and calendar still work."
    static let languagesNote = "Needs the model for your language on this Mac. " + OnDeviceTranscriptionCopy.joined(OnDeviceTranscriptionSupport.cloudOnlyLanguageNames) + " cannot be recorded in private mode yet."
    static let insightsNotice = "Private mode is on. This meeting stays on your Mac, so there are no summaries, questions or specialist views. Coaching still runs here."
    static let unavailable = "Private mode needs a Mac with Apple silicon."
}

// MARK: - Utterance assembly

/// Groups the recogniser's token timings into words and utterances shaped like Deepgram
/// responses: an interim after every chunk with the pending words, a final when the current
/// word ends a sentence, when the decoded horizon is `silenceSeconds` past the last token, or
/// when the pending utterance reaches `maxUtteranceSeconds`. Pure value type so it is testable
/// without a model.
struct LocalUtteranceAssembler: Sendable, Equatable {
    struct Word: Sendable, Equatable {
        /// Punctuated word as the model wrote it.
        let text: String
        let start: Double
        let end: Double
    }

    enum Event: Sendable, Equatable {
        case interim([Word])
        case final([Word])

        var words: [Word] {
            switch self {
            case .interim(let words), .final(let words): return words
            }
        }

        var isFinal: Bool {
            if case .final = self { return true }
            return false
        }
    }

    /// Mirrors Deepgram's `utterance_end_ms=1000`.
    static let silenceSeconds: Double = 1.0
    /// Longest utterance before a final is forced at the next word boundary.
    static let maxUtteranceSeconds: Double = 12.0
    static let wordBoundaryMarker: Character = "\u{2581}"  // "▁"
    private static let sentenceEnders: Set<Character> = [".", "?", "!", "。", "？", "！"]
    private static let trailingClosers: Set<Character> = ["\"", "'", ")", "”", "’", "»"]

    private(set) var pendingWords: [Word] = []
    private var partialText = ""
    private var partialStart: Double = 0
    private var partialEnd: Double = 0
    private var hasPartial = false
    private(set) var lastTokenEnd: Double = 0
    /// Bumped on every token so an unchanged chunk does not re-emit the same interim.
    private var changedSinceLastEvent = false
    /// Number of pending words up to and including the last one that closed with sentence
    /// punctuation; those become a final at the next decision even if a new word has started.
    private var sentenceBoundary: Int? = nil

    /// Consume the tokens decoded by one chunk. `horizon` is the end, in session seconds, of the
    /// audio the recogniser has decoded so far (not the audio fed: a word split across two
    /// chunks continues in the next chunk, so silence is measured against decoded audio).
    mutating func consume(tokens: [TokenTiming], horizon: Double) -> [Event] {
        for token in tokens {
            var piece = token.token
            guard !piece.isEmpty else { continue }
            let startsWord = piece.first == Self.wordBoundaryMarker
            if startsWord {
                piece.removeFirst()
                closePartial()
                if piece.isEmpty { continue }  // standalone boundary token after punctuation
                partialText = piece
                partialStart = token.startTime
                partialEnd = max(token.endTime, token.startTime)
                hasPartial = true
            } else if hasPartial {
                partialText += piece
                partialEnd = max(partialEnd, token.endTime)
            } else {
                // Continuation piece with nothing to attach to (first token of a session or
                // right after a flush): treat it as a word of its own.
                partialText = piece
                partialStart = token.startTime
                partialEnd = max(token.endTime, token.startTime)
                hasPartial = true
            }
            lastTokenEnd = max(lastTokenEnd, token.endTime)
            changedSinceLastEvent = true
        }

        var events: [Event] = []
        if hasPartial, Self.endsSentence(partialText) { closePartial() }
        if let boundary = sentenceBoundary {
            events.append(.final(Array(pendingWords[..<boundary])))
            pendingWords.removeFirst(boundary)
            sentenceBoundary = nil
            var rest = pendingWords
            if hasPartial { rest.append(currentPartialWord()) }
            if !rest.isEmpty { events.append(.interim(rest)) }
            changedSinceLastEvent = false
        } else if (hasPartial || !pendingWords.isEmpty), horizon - lastTokenEnd >= Self.silenceSeconds {
            closePartial()
            events.append(.final(pendingWords))
            pendingWords = []
            changedSinceLastEvent = false
        } else if let first = pendingWords.first, lastTokenEnd - first.start >= Self.maxUtteranceSeconds {
            // Force a final at the last complete word; the partial word stays pending.
            events.append(.final(pendingWords))
            pendingWords = []
            if hasPartial { events.append(.interim([currentPartialWord()])) }
            changedSinceLastEvent = false
        } else if changedSinceLastEvent {
            var words = pendingWords
            if hasPartial { words.append(currentPartialWord()) }
            if !words.isEmpty { events.append(.interim(words)) }
            changedSinceLastEvent = false
        }
        return events
    }

    /// End of session: everything pending becomes one final.
    mutating func flush() -> [Event] {
        closePartial()
        defer { pendingWords = []; changedSinceLastEvent = false; sentenceBoundary = nil }
        return pendingWords.isEmpty ? [] : [.final(pendingWords)]
    }

    private mutating func closePartial() {
        guard hasPartial else { return }
        let text = partialText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            pendingWords.append(Word(text: text, start: partialStart, end: max(partialEnd, partialStart)))
            if Self.endsSentence(text) { sentenceBoundary = pendingWords.count }
        }
        partialText = ""
        hasPartial = false
    }

    private func currentPartialWord() -> Word {
        Word(text: partialText.trimmingCharacters(in: .whitespaces), start: partialStart, end: max(partialEnd, partialStart))
    }

    static func endsSentence(_ text: String) -> Bool {
        var scalars = Substring(text)
        while let last = scalars.last, Self.trailingClosers.contains(last) { scalars = scalars.dropLast() }
        guard let last = scalars.last else { return false }
        return Self.sentenceEnders.contains(last)
    }

    /// Deepgram's plain `word` field: the punctuated word without surrounding punctuation.
    static func plainWord(_ punctuated: String) -> String {
        let trimmed = punctuated.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        return trimmed.isEmpty ? punctuated : trimmed
    }
}

// MARK: - Service

/// On-device live transcription (NVIDIA Nemotron 3.5 ASR Streaming Multilingual via
/// FluidAudio). Owns the downloaded model families and hands `Session`s to
/// `DeepgramService.connectLocal`, which feeds them the same PCM16 it would send to Deepgram
/// and runs their words through the shared transcript pipeline. Mirrors
/// `OnDeviceDiarizationService`: default off, Apple silicon only, every failure visible.
@MainActor
final class OnDeviceTranscriptionService: ObservableObject {
    enum Status: Equatable {
        /// Not Apple silicon; the setting is shown as unavailable.
        case unsupported
        /// Supported, nothing loaded.
        case idle
        /// Downloading or compiling; fraction in `0…1`.
        case preparing(Double)
        /// A model family is loaded; sessions for its languages can start.
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status
    /// Model family currently loaded (`latin` or `multilingual`), nil when nothing is loaded.
    @Published private(set) var loadedFamily: String?
    /// Bytes of downloaded model files in the app container, for the remove button.
    @Published private(set) var downloadedBytes: Int64 = 0

    private var shared: [String: SharedNemotronMultilingualModels] = [:]
    private var prepareTask: Task<Void, Never>?
    private var preparingFamily: String?
    private(set) var activeSession: Session?

    nonisolated static var isHardwareSupported: Bool { OnDeviceDiarizationService.isHardwareSupported }

    /// Where FluidAudio caches the multilingual variants (inside the sandbox container).
    nonisolated static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
    }

    init() {
        status = Self.isHardwareSupported ? .idle : .unsupported
        refreshDownloadedSize()
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// True when the family for this language is already on disk, so loading it is a matter of
    /// seconds rather than a download: a start can wait for it instead of being refused.
    nonisolated static func isDownloaded(languageCode code: String) -> Bool {
        guard OnDeviceTranscriptionSupport.tier(forCode: code) != .cloudOnly else { return false }
        let family = OnDeviceTranscriptionSupport.family(forCode: code)
        let metadata = modelsDirectory
            .appendingPathComponent(family, isDirectory: true)
            .appendingPathComponent("\(OnDeviceTranscriptionSupport.chunkMs)ms", isDirectory: true)
            .appendingPathComponent(ModelNames.NemotronMultilingualStreaming.metadata)
        return FileManager.default.fileExists(atPath: metadata.path)
    }

    /// True while the family for this language is being loaded or downloaded.
    func isPreparing(forLanguageCode code: String) -> Bool {
        guard case .preparing = status else { return false }
        return preparingFamily == OnDeviceTranscriptionSupport.family(forCode: code)
    }

    /// Wait for a load already in flight. Returns false on timeout or failure.
    func waitUntilReady(forLanguageCode code: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isReady(forLanguageCode: code) { return true }
            if case .failed = status { return false }
            if !isPreparing(forLanguageCode: code) { return isReady(forLanguageCode: code) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isReady(forLanguageCode: code)
    }

    /// True when the loaded family covers this language right now.
    func isReady(forLanguageCode code: String) -> Bool {
        guard isReady, OnDeviceTranscriptionSupport.tier(forCode: code) != .cloudOnly else { return false }
        return shared[OnDeviceTranscriptionSupport.family(forCode: code)] != nil
    }

    /// One-line status for Settings.
    var statusDescription: String {
        switch status {
        case .unsupported:
            return "Needs a Mac with Apple silicon. Deepgram transcribes on this device."
        case .idle:
            return "Off. Turn the setting on to download the model."
        case .preparing(let fraction):
            let family = preparingFamily ?? "latin"
            let size = OnDeviceTranscriptionSupport.approximateDownloadMB(family: family)
            return fraction > 0
                ? "Downloading the \(size) MB model, \(Int((fraction * 100).rounded()))%."
                : "Preparing the \(size) MB model."
        case .ready:
            return "Ready. New recordings are transcribed on this device."
        case .failed(let message):
            return "Could not load the model (\(message)). Recording is refused until it loads, unless Deepgram fallback is on."
        }
    }

    /// Download (first time) and load the model family for `languageCode`. Safe to call
    /// repeatedly; a second family downloads alongside the first.
    func prepare(languageCode: String) {
        guard Self.isHardwareSupported else { status = .unsupported; return }
        let family = OnDeviceTranscriptionSupport.family(forCode: languageCode)
        if shared[family] != nil { status = .ready; loadedFamily = family; return }
        if prepareTask != nil, preparingFamily == family { return }
        prepareTask?.cancel()
        preparingFamily = family
        status = .preparing(0)
        let chunkMs = OnDeviceTranscriptionSupport.chunkMs
        let languageHint = OnDeviceTranscriptionSupport.nemotronLanguage(forCode: languageCode) ?? "auto"
        prepareTask = Task { [weak self] in
            do {
                let directory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                    languageCode: languageHint,
                    chunkMs: chunkMs,
                    progressHandler: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            guard let self, case .preparing = self.status, self.preparingFamily == family else { return }
                            self.status = .preparing(fraction)
                        }
                    }
                )
                try Task.checkCancellation()
                let models = try await StreamingNemotronMultilingualAsrManager.preloadShared(from: directory)
                try Task.checkCancellation()
                guard let self else { return }
                self.shared[family] = models
                self.loadedFamily = family
                self.status = .ready
                self.preparingFamily = nil
                self.prepareTask = nil
                self.refreshDownloadedSize()
                DebugLogger.shared.log(.audio, "On-device transcription model ready: family=\(family), chunk=\(chunkMs)ms")
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.status = .failed(error.localizedDescription)
                self.preparingFamily = nil
                self.prepareTask = nil
                DebugLogger.shared.log(.audio, "On-device transcription model load failed: \(error.localizedDescription)")
            }
        }
    }

    /// Drop loaded models (setting switched off). An active session keeps its managers.
    func unload() {
        prepareTask?.cancel()
        prepareTask = nil
        preparingFamily = nil
        shared = [:]
        loadedFamily = nil
        if status != .unsupported { status = .idle }
    }

    /// Unload and delete every downloaded variant from the app container.
    func removeDownloadedModels() {
        unload()
        try? FileManager.default.removeItem(at: Self.modelsDirectory)
        refreshDownloadedSize()
        DebugLogger.shared.log(.audio, "On-device transcription models removed")
    }

    func refreshDownloadedSize() {
        downloadedBytes = Self.directorySize(Self.modelsDirectory)
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Start a local session for `sources` in `languageCode`, or nil when the family is not
    /// loaded. The managers are created here from the shared weights and warmed by the first
    /// chunk; `DeepgramService.connectLocal` activates the session with its event sink.
    func beginSession(sources: Set<TranscriptSource>, languageCode: String, vocabulary: [String]) async -> Session? {
        guard activeSession == nil, isReady(forLanguageCode: languageCode) else { return nil }
        let family = OnDeviceTranscriptionSupport.family(forCode: languageCode)
        guard let models = shared[family], let language = OnDeviceTranscriptionSupport.nemotronLanguage(forCode: languageCode) else { return nil }
        var managers: [TranscriptSource: StreamingNemotronMultilingualAsrManager] = [:]
        let terms = vocabulary.map { CustomVocabularyTerm(text: $0) }
        for source in sources.sorted(by: { $0.rawValue < $1.rawValue }) {
            let manager = StreamingNemotronMultilingualAsrManager()
            do {
                try await manager.loadFromShared(models)
                await manager.setLanguage(language)
                if !terms.isEmpty { await manager.setCustomVocabulary(terms) }
                managers[source] = manager
            } catch {
                DebugLogger.shared.log(.audio, "On-device transcription could not start for \(source.rawValue): \(error.localizedDescription)")
                return nil
            }
        }
        let session = Session(managers: managers, chunkMs: OnDeviceTranscriptionSupport.chunkMs)
        activeSession = session
        DebugLogger.shared.log(.audio, "On-device transcription session started: sources=\(sources.map(\.rawValue).sorted()), language=\(language), family=\(family), vocabulary=\(terms.count)")
        return session
    }

    /// The session has been finished or abandoned by `DeepgramService`.
    func noteSessionEnded() {
        activeSession = nil
    }

    // MARK: Session

    /// One recording's recognisers: a worker per capture source draining 16 kHz samples
    /// through its manager and the utterance assembler. Audio enters on the capture thread
    /// (`ingest`); events leave on whatever thread the worker runs and are hopped to the main
    /// actor by the sink.
    final class Session: @unchecked Sendable {
        struct Event: Sendable {
            let source: TranscriptSource
            let words: [LocalUtteranceAssembler.Word]
            let isFinal: Bool
        }

        let id = UUID()
        let sources: Set<TranscriptSource>
        private let chunkSeconds: Double
        private let lock = NSLock()
        private var continuations: [TranscriptSource: AsyncStream<[Float]>.Continuation] = [:]
        private var workers: [TranscriptSource: Task<Void, Never>] = [:]
        private var managers: [TranscriptSource: StreamingNemotronMultilingualAsrManager]
        private var sink: (@Sendable (Event) -> Void)?
        private var active = false
        private var finished = false
        nonisolated(unsafe) private(set) var failedSources: Set<TranscriptSource> = []
        /// Words emitted per source, for the end-of-session log.
        nonisolated(unsafe) private(set) var wordCounts: [TranscriptSource: Int] = [:]

        init(managers: [TranscriptSource: StreamingNemotronMultilingualAsrManager], chunkMs: Int) {
            self.managers = managers
            self.sources = Set(managers.keys)
            self.chunkSeconds = Double(chunkMs) / 1000
        }

        /// Start the workers. Called once by `DeepgramService.connectLocal`.
        func activate(sink: @escaping @Sendable (Event) -> Void) {
            lock.lock()
            guard !active else { lock.unlock(); return }
            active = true
            self.sink = sink
            lock.unlock()
            for (source, manager) in managers {
                let (stream, continuation) = AsyncStream<[Float]>.makeStream()
                lock.lock(); continuations[source] = continuation; lock.unlock()
                let worker = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    await self.run(source: source, manager: manager, stream: stream)
                }
                lock.lock(); workers[source] = worker; lock.unlock()
            }
        }

        /// Feed the PCM16 the app would send to Deepgram. Cheap: converts and enqueues.
        nonisolated func ingest(_ data: Data, multichannel: Bool, monoSource: TranscriptSource) {
            let split = OnDeviceDiarizationService.splitPCM16(data, multichannel: multichannel, monoSource: monoSource)
            lock.lock()
            let targets = continuations
            lock.unlock()
            for (source, samples) in split {
                targets[source]?.yield(samples)
            }
        }

        private func run(source: TranscriptSource, manager: StreamingNemotronMultilingualAsrManager, stream: AsyncStream<[Float]>) async {
            var assembler = LocalUtteranceAssembler()
            var emittedTokens = 0
            var failed = false
            for await samples in stream {
                guard !failed else { continue }
                do {
                    _ = try await manager.process(samples: samples)
                } catch {
                    failed = true
                    lock.lock(); failedSources.insert(source); lock.unlock()
                    DebugLogger.shared.log(.audio, "On-device transcription stopped for \(source.rawValue): \(error.localizedDescription)")
                    continue
                }
                let timings = await manager.getTokenTimings()
                let horizon = Double(await manager.lastDecodeStats().processedChunks) * chunkSeconds
                let fresh = timings.count > emittedTokens ? Array(timings[emittedTokens...]) : []
                emittedTokens = max(emittedTokens, timings.count)
                emit(assembler.consume(tokens: fresh, horizon: horizon), source: source)
            }
            if Task.isCancelled {
                // Abandoned mid-meeting: nothing listens any more, skip the tail decode.
                await manager.cleanup()
                return
            }
            if !failed {
                do {
                    let (_, timings) = try await manager.finishWithTokenTimings()
                    let fresh = timings.count > emittedTokens ? Array(timings[emittedTokens...]) : []
                    emit(assembler.consume(tokens: fresh, horizon: .infinity), source: source)
                } catch {
                    DebugLogger.shared.log(.audio, "On-device transcription finish failed for \(source.rawValue): \(error.localizedDescription)")
                }
            }
            emit(assembler.flush(), source: source)
            await manager.cleanup()
        }

        private func emit(_ events: [LocalUtteranceAssembler.Event], source: TranscriptSource) {
            guard !events.isEmpty else { return }
            lock.lock()
            let sink = self.sink
            for event in events where event.isFinal { wordCounts[source, default: 0] += event.words.count }
            lock.unlock()
            guard let sink else { return }
            for event in events {
                sink(Event(source: source, words: event.words, isFinal: event.isFinal))
            }
        }

        /// Stop accepting audio, let every worker decode its tail, and flush the last words
        /// through the sink. Returns when the workers are done.
        func finish() async {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let continuations = self.continuations
            let workers = self.workers
            self.continuations = [:]
            lock.unlock()
            for continuation in continuations.values { continuation.finish() }
            for worker in workers.values { await worker.value }
        }

        /// Drop the session without flushing (a restart mid-meeting).
        func abandon() {
            lock.lock()
            finished = true
            let continuations = self.continuations
            let workers = self.workers
            self.continuations = [:]
            self.sink = nil
            lock.unlock()
            for continuation in continuations.values { continuation.finish() }
            for worker in workers.values { worker.cancel() }
        }

        var summary: String {
            lock.lock(); defer { lock.unlock() }
            return "words=\(wordCounts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue):\($0.value)" }) failed=\(failedSources.map(\.rawValue).sorted())"
        }
    }
}
