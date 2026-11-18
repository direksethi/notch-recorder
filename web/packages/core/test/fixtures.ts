import type { RecordingDetail, RecordingSummary, Segment } from "../src/contract.ts"

export const recording: RecordingSummary = {
  id: "rec-1",
  title: "Pricing call",
  startedAt: Date.UTC(2026, 9, 21, 14, 24, 18),
  durationMs: 8_645_100,
  sizeBytes: 1_615_965_673,
  width: 4096,
  height: 1728,
  displayName: "External Display",
  status: "saved",
  transcriptStatus: "complete",
  transcribedUntilMs: 8_645_100,
  thumbnailCount: 8,
  segmentCount: 4,
  fileMissing: false,
  hasSourceAudio: true,
  preview: "So the main thing",
  previewSource: "others",
  videoPath: "/Users/example/Movies/Notch Recorder/Pricing call.mp4",
}

export const segments: Array<Segment> = [
  { id: 1, source: "others", startMs: 1250, endMs: 3000, text: "So the main thing", confidence: 0.9 },
  { id: 2, source: "others", startMs: 3500, endMs: 5000, text: "is the pricing page.", confidence: 0.9 },
  { id: 3, source: "me", startMs: 6000, endMs: 8000, text: "Got it.", confidence: 0.95 },
  { id: 4, source: "others", startMs: 20000, endMs: 21000, text: "Great.", confidence: 0.9, originalText: "Grate." },
]

export const detail: RecordingDetail = { recording, segments }
