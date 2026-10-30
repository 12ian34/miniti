# Local on-device AI research

> Research note captured 2026-08-12. This is not an active implementation plan. Revalidate OS, framework, model, language, and pricing details before starting work.

## Executive summary

Miniti can offer local AI insights on Apple silicon Macs, but no local path works for every currently supported Mac. The strongest first option is Apple's Foundation Models framework on macOS 26 and later, with managed cloud inference retained as the universal fallback. Downloadable MLX models are a useful later option for more capable machines or older macOS versions, but they add model distribution, memory, quality, licensing, and support costs.

Local insights remove OpenAI insight calls and improve privacy, but they do not remove Miniti's larger Deepgram transcription cost. macOS mic-and-system recording uses two independently billed channels. A fully local meeting pipeline would also require local transcription and remote-speaker diarization, which is a distinct and substantially harder project.

Recommended sequence:

1. Build an evaluation harness using representative Miniti transcripts.
2. Prototype standard insights with Apple's system model.
3. Add an insight-provider abstraction independent of managed/BYOK transcription mode.
4. Ship on-device summary, title, action items, and topics first if quality passes.
5. Evaluate embedded MLX models only after measuring the Apple path.
6. Investigate local transcription separately because it carries greater savings and greater regression risk.

## Compatibility

| Mac | Apple system model | Custom MLX model | Practical position |
|---|---:|---:|---|
| Intel Mac | No | No | Cloud only |
| M1 or later, 8 GB, macOS 26+ | Yes, when Apple Intelligence is available | Technically possible but constrained | Prefer Apple model; avoid heavy custom inference during recording |
| Apple silicon, 16 GB | Yes | Suitable for roughly 3B-8B quantized models, subject to testing | Viable local live and final insights |
| Apple silicon, 24 GB+ | Yes | Suitable for larger local models | Best local experience |
| Apple silicon on macOS 14/15 | No Apple system model | MLX is possible | Custom MLX or cloud |
| Apple Intelligence disabled, downloading, or language-ineligible | No Apple system model | MLX may still work | MLX or cloud |

Miniti currently targets macOS 14.2 and does not explicitly exclude Intel. MLX is designed for Apple silicon, while Apple's system model requires a device that supports Apple Intelligence. Availability must therefore be checked dynamically rather than inferred only from the marketing model name.

Relevant sources:

- [Apple Intelligence device compatibility](https://www.apple.com/apple-intelligence/)
- [SystemLanguageModel availability](https://developer.apple.com/documentation/FoundationModels/SystemLanguageModel)
- [MLX](https://github.com/ml-explore/mlx)
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm)

## Option 1: Apple Foundation Models

Apple's Foundation Models framework exposes the on-device model that powers Apple Intelligence through a native Swift API. It is the best first option because Miniti does not need to host model weights, add a multi-gigabyte download, manage a separate runtime, or pay per request. The framework supports guided generation into Swift data structures, which is preferable to asking a smaller model to emit hand-written JSON.

Apple explicitly positions the system model for summarization, entity extraction, tagging, classification, and text understanding. These map well to Miniti's standard summary, title, action-item, topic, speaker-name, and Playbook-topic workloads.

### Constraints

- It requires macOS 26 or later and an Apple Intelligence-capable Mac.
- Apple Intelligence must be enabled and the model must have finished downloading.
- The model has a 4,096-token context window shared by instructions, input, session history, and output.
- Model behavior can change with OS updates, so prompts and evaluations need version-aware regression testing.
- Guardrails may reject some otherwise valid meeting content.
- Unsupported languages must fall back to another provider.

The context limit is the central engineering issue. Miniti's current live incremental path can include a 10,000-character recent transcript plus instructions, rolling state, and output. That is already close to or beyond a safe 4K-token request. Full meeting transcripts will regularly exceed it.

The local pipeline therefore needs hierarchical processing:

1. Split transcripts at speaker-turn boundaries using measured token counts.
2. Extract grounded facts, decisions, actions, topics, and open questions from each chunk.
3. Merge those structured partial states in one or more bounded passes.
4. Generate the final user-facing summary from the merged state.
5. Use a smaller recent window for live updates, likely 6,000-8,000 characters as an initial hypothesis, then tune from token measurements.

Relevant sources:

- [Foundation Models overview](https://developer.apple.com/documentation/FoundationModels)
- [Generating content and handling the 4K context](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Guided generation introduction](https://developer.apple.com/videos/play/wwdc2025/286/)

### Languages

The system model supports the languages supported by Apple Intelligence and exposes `supportsLocale(_:)` and `supportedLanguages` for runtime checks. Miniti currently supports English, Spanish, Swedish, Greek, French, German, Portuguese, Italian, Dutch, Polish, and Russian. Apple's currently published Apple Intelligence language list covers most of these but not Greek, Polish, or Russian. This must be checked dynamically because support changes with OS releases.

Source: [Supporting languages and locales with Foundation Models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)

## Option 2: downloadable MLX models

MLX is Apple's open-source array framework optimized for Apple silicon and unified memory. `mlx-swift-lm` provides native Swift model loading and generation and currently supports macOS 14 at the package level. This could cover Apple silicon Macs that cannot or do not use Apple's system model.

macOS 27 adds a common `LanguageModel` abstraction and an `MLXLanguageModel` adapter, allowing Apple, MLX, and server models to use the same `LanguageModelSession` surface. This is strategically attractive, but as of this note macOS 27 is prerelease and Miniti's supported toolchain is Xcode 26. It should inform the design without becoming a current production dependency.

Source: [Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)

### Approximate hardware tiers to test

These are test hypotheses, not support guarantees:

- **8 GB:** 1B-3B, 4-bit models. Likely suitable only for titles and basic summaries. Run after recording rather than continuously.
- **16 GB:** 3B-8B, 4-bit models. Plausible for summaries, questions, and structured extraction.
- **24 GB+:** 7B-14B, 4-bit models. Best candidate for broader local feature coverage.
- **Intel:** unsupported.

Model weights are only part of the footprint. The KV cache, prompt length, Metal buffers, audio capture, UI, and SwiftData all compete for unified memory. A model that loads successfully may still produce an unacceptable meeting experience.

Eligibility should use:

- architecture and physical memory;
- `MTLDevice.recommendedMaxWorkingSetSize`;
- free disk space;
- current thermal state and Low Power Mode;
- a short first-run benchmark for prompt processing and generation speed;
- whether a recording is active;
- runtime memory-pressure handling and cancellation.

### Product and operational costs

An embedded MLX path also requires:

- a licensed and version-pinned model;
- an on-demand download rather than bundling weights in the DMG;
- resumable downloads, integrity verification, disk-space checks, deletion, and upgrade handling;
- hosted model bandwidth or a carefully controlled third-party download source;
- model-specific prompt and structured-output evaluations;
- an idle unload policy and bounded Metal cache behavior;
- protection against model or tokenizer supply-chain changes.

Requiring Ollama, LM Studio, Python, or a separately managed local server is useful for an internal prototype but is not an appropriate default consumer experience. A localhost OpenAI-compatible endpoint could remain an advanced power-user integration.

## Proposed Miniti architecture

Do not add `local` as a third `AppMode`. The current managed/BYOK mode controls both Deepgram credentials and insight routing. A user may still use managed Deepgram while generating insights locally, so the choices need to be independent.

Add an insight-provider preference such as:

- Automatic
- On-device
- Managed cloud
- OpenAI with my key
- Later: Downloaded local model

Introduce an app-level provider protocol whose implementations return Miniti's existing `LiveInsights`/meeting insight structures:

- managed API provider;
- BYOK OpenAI provider;
- Apple Foundation Models provider;
- later, MLX provider.

The orchestration in `AppState` should retain the existing meeting-ID, transcript-revision, request-sequence, cancellation, stale-response, background-finalization, and save-queue protections regardless of provider.

For Apple and macOS 27 language-model providers, define guided output structures for:

- summary, title, action items, topics, and discussion flow;
- suggested questions;
- speaker-name mappings;
- MEDDPICC fields;
- Playbook topics and grounded answers.

### Privacy semantics

Expose two unambiguous behaviors:

- **Local only:** never upload the transcript for insight generation, even when local inference fails.
- **Prefer local, allow cloud fallback:** use managed inference when the selected local provider is unavailable or fails.

Never silently upload after a user chooses local-only. Also avoid describing local insights as a fully local meeting: audio still goes to Deepgram for transcription unless a separate local transcription provider is selected.

Telemetry for local mode should be content-free and opt-in where required: provider, hardware bucket, duration, token counts, latency, peak memory, thermal state, success/failure category, and fallback occurrence. Do not transmit transcript or generated insight content merely to evaluate local performance.

## Feature rollout order

Suggested order from lowest to highest quality risk:

1. Final summary, title, action items, and topics.
2. Live rolling summary.
3. Speaker naming and Playbook topic extraction.
4. Suggested questions.
5. Grounded Playbook answers.
6. MEDDPICC.

MEDDPICC should come last because it relies on accurate evidence aggregation across a long conversation. Coaching metrics are already computed locally and gain nothing from switching LLM providers.

## Cost impact

The current managed router uses pinned `gpt-5-mini-2025-08-07` for incremental updates, speaker naming, catch-up, and Playbook topic extraction, and pinned `gpt-5.4-mini-2026-03-17` for full summary, MEDDPICC, questions, and grounded Playbook answers.

Using the existing planning assumption of approximately five calls per 30-minute meeting, each with about 8,500 input and 2,000 output tokens:

- all GPT-5 mini would cost roughly $0.03 per meeting;
- all GPT-5.4 mini would cost roughly $0.08 per meeting;
- the current mixed router should land between those values, depending on call mix, retries, caching, reasoning tokens, and actual output length.

Current official prices at the time of this note:

- [GPT-5 mini: $0.25 input / $2.00 output per million tokens](https://developers.openai.com/api/docs/models/gpt-5-mini)
- [GPT-5.4 mini: $0.75 input / $4.50 output per million tokens](https://developers.openai.com/api/docs/models/gpt-5.4-mini)

Deepgram remains the larger cost. A 30-minute macOS mic-and-system meeting produces approximately 60 billed channel-minutes. At the published $0.0077/minute non-promotional Nova-3 streaming price, this is about $0.46 before diarization add-ons or contracted discounts. The current Deepgram pricing page also advertises promotional rates, so recheck the applicable account price before financial modeling.

Source: [Deepgram pricing](https://deepgram.com/pricing)

Local insights therefore remove a meaningful but minority share of direct inference cost for a typical dual-channel Mac meeting. They do not justify materially increasing managed minute allowances without also changing transcription economics. Managed users do not personally pay per insight request; the saving accrues to Miniti. BYOK users would avoid their OpenAI insight bill but would still pay Deepgram.

## Local transcription: separate investigation

> Superseded 2026-10-09 by [local-transcription-research.md](local-transcription-research.md), which evaluates Nemotron 3.5 streaming via FluidAudio, Apple SpeechTranscriber, WhisperKit, Parakeet, Voxtral, and Gemma 4. The paragraphs below are kept for history.

Apple's `SpeechAnalyzer` and `SpeechTranscriber` provide live, downloadable, entirely on-device transcription on supported systems. This may eventually offer greater savings than local insights.

The documented Speech framework exposes transcription and voice-activity analysis but not an equivalent to Miniti's current multi-speaker diarization. On macOS, separate mic and system channels could preserve `You` versus remote attribution, but distinguishing multiple remote speakers would require another local diarization model or a feature regression. iOS mic-only recording makes this even harder.

Before considering a switch, evaluate:

- word error rate across all supported languages;
- interim/final latency and timestamp stability;
- punctuation, filler words, key terms, and custom vocabulary;
- remote-speaker diarization;
- overlap and echo handling;
- background behavior and asset availability;
- CPU/GPU/ANE contention with local insight generation.

Relevant sources:

- [Speech framework](https://developer.apple.com/documentation/speech/)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)

## Evaluation plan

Use 30-50 representative, anonymized or synthetic Miniti transcripts covering:

- short, 30-minute, and 60-90-minute meetings;
- all supported languages;
- single and multiple speakers;
- standard, Questions, Sales/MEDDPICC, speaker naming, catch-up, and Playbook workloads;
- ambiguous actions, corrections, contradictory statements, and sensitive content.

Compare the current cloud baseline with Apple's system model and at least one small and one medium MLX model. Measure:

- factual grounding and hallucination rate;
- action-item and decision precision/recall;
- summary usefulness;
- question specificity and usefulness;
- MEDDPICC evidence quality;
- schema/structured-output reliability;
- unsupported-language and guardrail failures;
- time to first output and total latency;
- peak process and Metal memory;
- energy and thermal behavior;
- impact on audio capture and UI responsiveness;
- cancellation, retry, and fallback behavior.

Test at minimum on an 8 GB M1, a 16 GB Apple silicon Mac, and a 24 GB or larger machine. The current development machine is an M5 Pro with 24 GB and is suitable for the high-end prototype, not the compatibility floor.

## Decision recommendation

When this work resumes:

1. Start with a Foundation Models spike for standard final insights on macOS 26+.
2. Build chunking and guided structured generation before attempting feature parity.
3. Keep managed cloud as the default/fallback until real transcript evaluations pass.
4. Preserve a strict local-only option with no silent upload.
5. Do not promise MLX support based only on whether weights load; support it from measured quality and performance tiers.
6. Defer model downloads and macOS 27 `MLXLanguageModel` integration until the Apple system-model evaluation shows a concrete need.
7. Treat local transcription as a separate roadmap item because it is the larger cost lever and the larger technical risk.
