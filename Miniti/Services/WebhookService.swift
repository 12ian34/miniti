import Foundation

enum WebhookService {

    struct MeetingPayload: Encodable {
        let event: String
        let meeting: MeetingData

        struct MeetingData: Encodable {
            let id: String
            let title: String
            let date: String
            let endTime: String?
            let durationSeconds: Int
            let language: String
            let summary: String?
            let actionItems: [String]
            let keyDecisions: [String]
            let topics: [String]
            let discussionFlow: [String]
            let notes: String
            let meddpicc: MEDDPICCData?
            let training: TrainingData?
            let questions: [QuestionEntry]?
            let speakerCount: Int
            let speakerNames: [String: String]?
            let transcript: [TranscriptEntry]
            let calendarEventId: String?
            let attendees: [AttendeeEntry]?

            enum CodingKeys: String, CodingKey {
                case id, title, date, summary, notes, topics, meddpicc, training, questions, transcript, language, attendees
                case endTime = "end_time"
                case durationSeconds = "duration_seconds"
                case actionItems = "action_items"
                case keyDecisions = "key_decisions"
                case discussionFlow = "discussion_flow"
                case speakerCount = "speaker_count"
                case speakerNames = "speaker_names"
                case calendarEventId = "calendar_event_id"
            }
        }

        struct AttendeeEntry: Encodable {
            let email: String
            let name: String?
            let domain: String
        }

        struct TranscriptEntry: Encodable {
            let speaker: String
            let text: String
            let timestamp: Double

            enum CodingKeys: String, CodingKey {
                case speaker, text, timestamp
            }
        }

        struct QuestionEntry: Encodable {
            let question: String
            let type: String
            let context: String
        }

        struct MEDDPICCData: Encodable {
            let metrics: String?
            let economicBuyer: String?
            let decisionCriteria: String?
            let decisionProcess: String?
            let paperProcess: String?
            let identifiedPain: String?
            let champion: String?
            let competition: String?

            var isEmpty: Bool {
                [metrics, economicBuyer, decisionCriteria, decisionProcess,
                 paperProcess, identifiedPain, champion, competition]
                    .allSatisfy { $0 == nil || $0!.isEmpty }
            }

            enum CodingKeys: String, CodingKey {
                case metrics, champion, competition
                case economicBuyer = "economic_buyer"
                case decisionCriteria = "decision_criteria"
                case decisionProcess = "decision_process"
                case paperProcess = "paper_process"
                case identifiedPain = "identified_pain"
            }
        }

        struct TrainingData: Encodable {
            let talkRatioYou: Double
            let durationMinutes: Double
            let speakers: [SpeakerData]

            struct SpeakerData: Encodable {
                let speaker: String
                let isYou: Bool
                let wordCount: Int
                let wordsPerMinute: Double
                let fillersPerMinute: Double
                let totalFillers: Int
                let fillers: [String: Int]
                let longestMonologueWords: Int
                let questionsAsked: Int
                let avgWordsPerTurn: Double

                enum CodingKeys: String, CodingKey {
                    case speaker, fillers
                    case isYou = "is_you"
                    case wordCount = "word_count"
                    case wordsPerMinute = "words_per_minute"
                    case fillersPerMinute = "fillers_per_minute"
                    case totalFillers = "total_fillers"
                    case longestMonologueWords = "longest_monologue_words"
                    case questionsAsked = "questions_asked"
                    case avgWordsPerTurn = "avg_words_per_turn"
                }
            }

            enum CodingKeys: String, CodingKey {
                case speakers
                case talkRatioYou = "talk_ratio_you"
                case durationMinutes = "duration_minutes"
            }
        }
    }

    // MARK: - Training metrics conversion

    static func trainingData(from metrics: TrainingMetrics?) -> MeetingPayload.TrainingData? {
        guard let metrics else { return nil }
        let speakers = metrics.speakers.map { s in
            var fillerMap: [String: Int] = [:]
            for f in s.fillers { fillerMap[f.word] = f.count }
            return MeetingPayload.TrainingData.SpeakerData(
                speaker: s.speakerLabel,
                isYou: s.isLocalMic,
                wordCount: s.wordCount,
                wordsPerMinute: s.wordsPerMinute,
                fillersPerMinute: s.fillersPerMinute,
                totalFillers: s.totalFillers,
                fillers: fillerMap,
                longestMonologueWords: s.longestMonologueWords,
                questionsAsked: s.questionsAsked,
                avgWordsPerTurn: s.avgWordsPerTurn
            )
        }
        return MeetingPayload.TrainingData(
            talkRatioYou: metrics.talkRatioYou,
            durationMinutes: metrics.durationMinutes,
            speakers: speakers
        )
    }

    // MARK: - Payload from live AppState (used by goHome)

    static func payloadFromLiveState(
        meetingID: UUID,
        title: String,
        startTime: Date,
        endTime: Date?,
        durationSeconds: Int,
        language: String = "en",
        summary: String,
        actionItems: [String],
        keyDecisions: [String],
        topics: [String],
        discussionFlow: [String],
        notes: String,
        metrics: String?,
        economicBuyer: String?,
        decisionCriteria: String?,
        decisionProcess: String?,
        paperProcess: String?,
        identifiedPain: String?,
        champion: String?,
        competition: String?,
        speakerCount: Int,
        speakerNames: [String: String] = [:],
        transcript: [MeetingPayload.TranscriptEntry],
        training: MeetingPayload.TrainingData?,
        questions: [SuggestedQuestion] = [],
        calendarEventId: String? = nil,
        attendees: [MeetingAttendee] = []
    ) -> MeetingPayload {
        let fmt = ISO8601DateFormatter()
        let meddpicc = MeetingPayload.MEDDPICCData(
            metrics: metrics, economicBuyer: economicBuyer,
            decisionCriteria: decisionCriteria, decisionProcess: decisionProcess,
            paperProcess: paperProcess, identifiedPain: identifiedPain,
            champion: champion, competition: competition
        )
        let attendeeEntries = attendees.isEmpty ? nil : attendees.map {
            MeetingPayload.AttendeeEntry(email: $0.email, name: $0.displayName, domain: $0.domain)
        }
        return MeetingPayload(
            event: "meeting.saved",
            meeting: .init(
                id: meetingID.uuidString,
                title: title,
                date: fmt.string(from: startTime),
                endTime: endTime.map { fmt.string(from: $0) },
                durationSeconds: durationSeconds,
                language: language,
                summary: summary.isEmpty ? nil : summary,
                actionItems: actionItems,
                keyDecisions: keyDecisions,
                topics: topics,
                discussionFlow: discussionFlow,
                notes: notes,
                meddpicc: meddpicc.isEmpty ? nil : meddpicc,
                training: training,
                questions: questions.isEmpty ? nil : questions.map {
                    MeetingPayload.QuestionEntry(question: $0.question, type: $0.type, context: $0.context)
                },
                speakerCount: speakerCount,
                speakerNames: speakerNames.isEmpty ? nil : speakerNames,
                transcript: transcript,
                calendarEventId: calendarEventId,
                attendees: attendeeEntries
            )
        )
    }

    // MARK: - Payload from persisted Meeting (used by generateInsightsForMeeting)

    static func payloadFromMeeting(_ meeting: Meeting) -> MeetingPayload {
        let fmt = ISO8601DateFormatter()
        let duration = meeting.endTime.map { Int($0.timeIntervalSince(meeting.startTime)) } ?? 0
        let finalSegments = meeting.segments.filter(\.isFinal).sorted { $0.timestamp < $1.timestamp }
        let speakers = Set(finalSegments.map(\.speaker))
        let meddpicc = MeetingPayload.MEDDPICCData(
            metrics: meeting.meddpiccMetrics, economicBuyer: meeting.meddpiccEconomicBuyer,
            decisionCriteria: meeting.meddpiccDecisionCriteria,
            decisionProcess: meeting.meddpiccDecisionProcess,
            paperProcess: meeting.meddpiccPaperProcess,
            identifiedPain: meeting.meddpiccIdentifiedPain,
            champion: meeting.meddpiccChampion, competition: meeting.meddpiccCompetition
        )
        let speakerNames = meeting.speakerNames
        let selfIDs = meeting.selfSpeakerIDs
        let transcript = finalSegments.map { seg in
            MeetingPayload.TranscriptEntry(
                speaker: resolvedSpeakerLabel(for: seg.speaker, names: speakerNames, selfIDs: selfIDs),
                text: seg.text,
                timestamp: seg.timestamp
            )
        }
        let trainingSegments = meeting.segments.map {
            TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal, timestamp: $0.timestamp)
        }
        let durationSec = meeting.endTime?.timeIntervalSince(meeting.startTime) ?? 0
        let training = trainingData(from: TrainingMetrics.compute(from: trainingSegments, duration: durationSec, language: meeting.language, names: speakerNames, selfIDs: selfIDs))
        let meetingAttendees = meeting.attendees
        let attendeeEntries = meetingAttendees.isEmpty ? nil : meetingAttendees.map {
            MeetingPayload.AttendeeEntry(email: $0.email, name: $0.displayName, domain: $0.domain)
        }
        return MeetingPayload(
            event: "meeting.updated",
            meeting: .init(
                id: meeting.id.uuidString,
                title: meeting.displayTitle,
                date: fmt.string(from: meeting.startTime),
                endTime: meeting.endTime.map { fmt.string(from: $0) },
                durationSeconds: duration,
                language: meeting.language,
                summary: meeting.summaryText,
                actionItems: meeting.actionItems,
                keyDecisions: meeting.keyDecisions,
                topics: meeting.topics,
                discussionFlow: meeting.discussionFlow,
                notes: meeting.notes,
                meddpicc: meddpicc.isEmpty ? nil : meddpicc,
                training: training,
                questions: meeting.suggestedQuestions.isEmpty ? nil : meeting.suggestedQuestions.map {
                    MeetingPayload.QuestionEntry(question: $0.question, type: $0.type, context: $0.context)
                },
                speakerCount: speakers.count,
                speakerNames: speakerNames.isEmpty ? nil : speakerNames,
                transcript: transcript,
                calendarEventId: meeting.calendarEventId,
                attendees: attendeeEntries
            )
        )
    }

    // MARK: - Send

    static func send(payload: MeetingPayload, to webhookURL: String) {
        guard !webhookURL.isEmpty, let url = URL(string: webhookURL) else { return }

        Task.detached(priority: .utility) {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 10

                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                request.httpBody = try encoder.encode(payload)

                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    DebugLogger.shared.log(.app, "Webhook sent (\(status)): \(payload.event)")
                } else {
                    DebugLogger.shared.log(.app, "Webhook non-2xx (\(status)): \(payload.event) → \(webhookURL)")
                }
            } catch {
                DebugLogger.shared.log(.app, "Webhook FAILED: \(error.localizedDescription) → \(webhookURL)")
            }
        }
    }
}
