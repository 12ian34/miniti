import Database from 'better-sqlite3'
import { app } from 'electron'
import { join } from 'path'
import { v4 as uuidv4 } from 'uuid'

// --- Types ---

export interface Meeting {
  id: string
  title: string
  startTime: string // ISO
  endTime?: string // ISO
  summaryText?: string
  actionItems: string[]
  keyDecisions: string[]
  topics: string[]
  discussionFlow: string[]
  notes: string
  // MEDDPICC
  meddpiccMetrics?: string
  meddpiccEconomicBuyer?: string
  meddpiccDecisionCriteria?: string
  meddpiccDecisionProcess?: string
  meddpiccPaperProcess?: string
  meddpiccIdentifiedPain?: string
  meddpiccChampion?: string
  meddpiccCompetition?: string
}

export interface TranscriptSegment {
  id: string
  meetingId: string
  text: string
  speaker: number
  timestamp: number
  isFinal: boolean
  confidence: number
}

// --- Service ---

export class StorageService {
  private db: Database.Database

  constructor() {
    const dbPath = join(app.getPath('userData'), 'miniti.db')
    this.db = new Database(dbPath)
    this.db.pragma('journal_mode = WAL')
    this.migrate()
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS meetings (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        summary_text TEXT,
        action_items TEXT DEFAULT '[]',
        key_decisions TEXT DEFAULT '[]',
        topics TEXT DEFAULT '[]',
        discussion_flow TEXT DEFAULT '[]',
        notes TEXT DEFAULT '',
        meddpicc_metrics TEXT,
        meddpicc_economic_buyer TEXT,
        meddpicc_decision_criteria TEXT,
        meddpicc_decision_process TEXT,
        meddpicc_paper_process TEXT,
        meddpicc_identified_pain TEXT,
        meddpicc_champion TEXT,
        meddpicc_competition TEXT
      );

      CREATE TABLE IF NOT EXISTS transcript_segments (
        id TEXT PRIMARY KEY,
        meeting_id TEXT NOT NULL,
        text TEXT NOT NULL,
        speaker INTEGER DEFAULT 0,
        timestamp REAL DEFAULT 0,
        is_final INTEGER DEFAULT 1,
        confidence REAL DEFAULT 1.0,
        FOREIGN KEY (meeting_id) REFERENCES meetings(id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_segments_meeting ON transcript_segments(meeting_id);
    `)
  }

  // --- Meetings ---

  saveMeeting(meeting: Meeting, segments: TranscriptSegment[]): void {
    const upsert = this.db.prepare(`
      INSERT OR REPLACE INTO meetings (
        id, title, start_time, end_time, summary_text,
        action_items, key_decisions, topics, discussion_flow, notes,
        meddpicc_metrics, meddpicc_economic_buyer, meddpicc_decision_criteria,
        meddpicc_decision_process, meddpicc_paper_process, meddpicc_identified_pain,
        meddpicc_champion, meddpicc_competition
      ) VALUES (
        @id, @title, @startTime, @endTime, @summaryText,
        @actionItems, @keyDecisions, @topics, @discussionFlow, @notes,
        @meddpiccMetrics, @meddpiccEconomicBuyer, @meddpiccDecisionCriteria,
        @meddpiccDecisionProcess, @meddpiccPaperProcess, @meddpiccIdentifiedPain,
        @meddpiccChampion, @meddpiccCompetition
      )
    `)

    const deleteSegments = this.db.prepare('DELETE FROM transcript_segments WHERE meeting_id = ?')
    const insertSegment = this.db.prepare(`
      INSERT INTO transcript_segments (id, meeting_id, text, speaker, timestamp, is_final, confidence)
      VALUES (@id, @meetingId, @text, @speaker, @timestamp, @isFinal, @confidence)
    `)

    const tx = this.db.transaction(() => {
      upsert.run({
        id: meeting.id,
        title: meeting.title,
        startTime: meeting.startTime,
        endTime: meeting.endTime || null,
        summaryText: meeting.summaryText || null,
        actionItems: JSON.stringify(meeting.actionItems),
        keyDecisions: JSON.stringify(meeting.keyDecisions),
        topics: JSON.stringify(meeting.topics),
        discussionFlow: JSON.stringify(meeting.discussionFlow),
        notes: meeting.notes,
        meddpiccMetrics: meeting.meddpiccMetrics || null,
        meddpiccEconomicBuyer: meeting.meddpiccEconomicBuyer || null,
        meddpiccDecisionCriteria: meeting.meddpiccDecisionCriteria || null,
        meddpiccDecisionProcess: meeting.meddpiccDecisionProcess || null,
        meddpiccPaperProcess: meeting.meddpiccPaperProcess || null,
        meddpiccIdentifiedPain: meeting.meddpiccIdentifiedPain || null,
        meddpiccChampion: meeting.meddpiccChampion || null,
        meddpiccCompetition: meeting.meddpiccCompetition || null
      })

      deleteSegments.run(meeting.id)
      for (const seg of segments) {
        insertSegment.run({
          id: seg.id || uuidv4(),
          meetingId: meeting.id,
          text: seg.text,
          speaker: seg.speaker,
          timestamp: seg.timestamp,
          isFinal: seg.isFinal ? 1 : 0,
          confidence: seg.confidence
        })
      }
    })

    tx()
  }

  getMeetings(): Meeting[] {
    const rows = this.db
      .prepare('SELECT * FROM meetings ORDER BY start_time DESC')
      .all() as Record<string, unknown>[]

    return rows.map((r) => this.rowToMeeting(r))
  }

  getMeeting(id: string): (Meeting & { segments: TranscriptSegment[] }) | null {
    const row = this.db.prepare('SELECT * FROM meetings WHERE id = ?').get(id) as
      | Record<string, unknown>
      | undefined
    if (!row) return null

    const meeting = this.rowToMeeting(row)
    const segRows = this.db
      .prepare(
        'SELECT * FROM transcript_segments WHERE meeting_id = ? ORDER BY timestamp ASC'
      )
      .all(id) as Record<string, unknown>[]

    const segments: TranscriptSegment[] = segRows.map((s) => ({
      id: s.id as string,
      meetingId: s.meeting_id as string,
      text: s.text as string,
      speaker: s.speaker as number,
      timestamp: s.timestamp as number,
      isFinal: (s.is_final as number) === 1,
      confidence: s.confidence as number
    }))

    return { ...meeting, segments }
  }

  deleteMeeting(id: string): void {
    this.db.prepare('DELETE FROM meetings WHERE id = ?').run(id)
  }

  private rowToMeeting(r: Record<string, unknown>): Meeting {
    return {
      id: r.id as string,
      title: r.title as string,
      startTime: r.start_time as string,
      endTime: (r.end_time as string) || undefined,
      summaryText: (r.summary_text as string) || undefined,
      actionItems: this.parseJsonArray(r.action_items as string),
      keyDecisions: this.parseJsonArray(r.key_decisions as string),
      topics: this.parseJsonArray(r.topics as string),
      discussionFlow: this.parseJsonArray(r.discussion_flow as string),
      notes: (r.notes as string) || '',
      meddpiccMetrics: (r.meddpicc_metrics as string) || undefined,
      meddpiccEconomicBuyer: (r.meddpicc_economic_buyer as string) || undefined,
      meddpiccDecisionCriteria: (r.meddpicc_decision_criteria as string) || undefined,
      meddpiccDecisionProcess: (r.meddpicc_decision_process as string) || undefined,
      meddpiccPaperProcess: (r.meddpicc_paper_process as string) || undefined,
      meddpiccIdentifiedPain: (r.meddpicc_identified_pain as string) || undefined,
      meddpiccChampion: (r.meddpicc_champion as string) || undefined,
      meddpiccCompetition: (r.meddpicc_competition as string) || undefined
    }
  }

  private parseJsonArray(val: string | null): string[] {
    if (!val) return []
    try {
      return JSON.parse(val)
    } catch {
      return []
    }
  }
}
