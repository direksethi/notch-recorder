import { Schema } from "effect"

// The single source of truth for every value that crosses the Swift and
// TypeScript boundary. Swift mirrors these shapes in BridgeKit/BridgeDTO.swift
// and a fixture test keeps the two in step.

export const AudioSource = Schema.Literals(["me", "others", "speaker"])
export type AudioSource = typeof AudioSource.Type

export const RecordingStatus = Schema.Literals(["recording", "unsaved", "saved", "discarded", "failed"])
export type RecordingStatus = typeof RecordingStatus.Type

export const TranscriptStatus = Schema.Literals(["none", "live", "complete", "partial", "failed", "retranscribing"])
export type TranscriptStatus = typeof TranscriptStatus.Type

export const CopyFormat = Schema.Literals(["clean", "timestamps", "plain", "markdown"])
export type CopyFormat = typeof CopyFormat.Type

export const ExportFormat = Schema.Literals(["md", "txt", "srt", "vtt", "json"])
export type ExportFormat = typeof ExportFormat.Type

export const RecordingSummary = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  /** Milliseconds since 1970. */
  startedAt: Schema.Number,
  durationMs: Schema.Number,
  sizeBytes: Schema.Number,
  width: Schema.Number,
  height: Schema.Number,
  displayName: Schema.String,
  status: RecordingStatus,
  transcriptStatus: TranscriptStatus,
  transcribedUntilMs: Schema.Number,
  thumbnailCount: Schema.Number,
  segmentCount: Schema.Number,
  fileMissing: Schema.Boolean,
  hasSourceAudio: Schema.Boolean,
  preview: Schema.optionalKey(Schema.String),
  previewSource: Schema.optionalKey(AudioSource),
  videoPath: Schema.optionalKey(Schema.String),
  errorMessage: Schema.optionalKey(Schema.String),
})
export type RecordingSummary = typeof RecordingSummary.Type

export const Segment = Schema.Struct({
  id: Schema.Number,
  source: AudioSource,
  startMs: Schema.Number,
  endMs: Schema.Number,
  text: Schema.String,
  originalText: Schema.optionalKey(Schema.String),
  confidence: Schema.Number,
})
export type Segment = typeof Segment.Type

export const RecordingDetail = Schema.Struct({
  recording: RecordingSummary,
  segments: Schema.Array(Segment),
})
export type RecordingDetail = typeof RecordingDetail.Type

export const SearchHit = Schema.Struct({
  recordingId: Schema.String,
  recordingTitle: Schema.String,
  startedAt: Schema.Number,
  durationMs: Schema.Number,
  segmentId: Schema.Number,
  source: AudioSource,
  startMs: Schema.Number,
  /** Segment text with matches wrapped in U+0001 and U+0002. */
  highlighted: Schema.String,
})
export type SearchHit = typeof SearchHit.Type

export const Settings = Schema.Struct({
  videoFolder: Schema.String,
  exportOnSave: Schema.Boolean,
  exportFolder: Schema.optionalKey(Schema.String),
  exportFormats: Schema.Array(ExportFormat),
  copyFormat: CopyFormat,
  displayId: Schema.optionalKey(Schema.Number),
  micDeviceId: Schema.optionalKey(Schema.String),
  showCursor: Schema.Boolean,
  scale: Schema.Number,
  /** Output pixels per screen point on Retina displays (a MacBook's built-in screen). */
  retinaPointScale: Schema.Number,
  fps: Schema.Number,
  quality: Schema.Number,
  transcription: Schema.Boolean,
  showPartials: Schema.Boolean,
  launchAtLogin: Schema.Boolean,
})
export type Settings = typeof Settings.Type

export const SettingsPatch = Schema.Struct({
  videoFolder: Schema.optionalKey(Schema.String),
  exportOnSave: Schema.optionalKey(Schema.Boolean),
  exportFolder: Schema.optionalKey(Schema.String),
  exportFormats: Schema.optionalKey(Schema.Array(ExportFormat)),
  copyFormat: Schema.optionalKey(CopyFormat),
  /** null clears the choice (back to the main display / default mic). */
  displayId: Schema.optionalKey(Schema.NullOr(Schema.Number)),
  micDeviceId: Schema.optionalKey(Schema.NullOr(Schema.String)),
  showCursor: Schema.optionalKey(Schema.Boolean),
  scale: Schema.optionalKey(Schema.Number),
  retinaPointScale: Schema.optionalKey(Schema.Number),
  fps: Schema.optionalKey(Schema.Number),
  quality: Schema.optionalKey(Schema.Number),
  transcription: Schema.optionalKey(Schema.Boolean),
  showPartials: Schema.optionalKey(Schema.Boolean),
  launchAtLogin: Schema.optionalKey(Schema.Boolean),
})
export type SettingsPatch = typeof SettingsPatch.Type

export const Permissions = Schema.Struct({
  screen: Schema.Boolean,
  microphone: Schema.Boolean,
})
export type Permissions = typeof Permissions.Type

export const RecorderPhase = Schema.Literals(["idle", "starting", "recording", "paused", "stopping"])
export type RecorderPhase = typeof RecorderPhase.Type

export const RecorderState = Schema.Struct({
  phase: RecorderPhase,
  recordingId: Schema.optionalKey(Schema.String),
  startedAt: Schema.optionalKey(Schema.Number),
})
export type RecorderState = typeof RecorderState.Type

export const Display = Schema.Struct({
  id: Schema.Number,
  name: Schema.String,
  width: Schema.Number,
  height: Schema.Number,
  isMain: Schema.Boolean,
})
export const Microphone = Schema.Struct({
  id: Schema.String,
  name: Schema.String,
  isDefault: Schema.Boolean,
})
export const Devices = Schema.Struct({
  displays: Schema.Array(Display),
  microphones: Schema.Array(Microphone),
})
export type Devices = typeof Devices.Type

export const NoticeLevel = Schema.Literals(["info", "warning", "error"])

export const BridgeEvent = Schema.Union([
  Schema.TaggedStruct("RecorderStateChanged", { state: RecorderState }),
  Schema.TaggedStruct("LibraryChanged", { recordingId: Schema.optionalKey(Schema.String) }),
  Schema.TaggedStruct("RetranscribeProgress", { recordingId: Schema.String, fraction: Schema.Number }),
  Schema.TaggedStruct("SegmentAdded", { recordingId: Schema.String, segment: Segment }),
  Schema.TaggedStruct("Notice", { level: NoticeLevel, message: Schema.String }),
])
export type BridgeEvent = typeof BridgeEvent.Type

/** Error codes the native side can return. */
export const NativeErrorCode = Schema.Literals([
  "NotFound",
  "FileMissing",
  "PermissionDenied",
  "InvalidParams",
  "Busy",
  "Cancelled",
  "Failed",
])
export type NativeErrorCode = typeof NativeErrorCode.Type

export const NativeErrorPayload = Schema.Struct({
  code: NativeErrorCode,
  message: Schema.String,
  detail: Schema.optionalKey(Schema.String),
})

export const BridgeReply = Schema.Union([
  Schema.Struct({ ok: Schema.Literal(true), value: Schema.Unknown }),
  Schema.Struct({ ok: Schema.Literal(false), error: NativeErrorPayload }),
])

const Id = Schema.Struct({ id: Schema.String })
const Empty = Schema.Struct({})
const Void = Schema.Null

export const ExportFile = Schema.Struct({
  id: Schema.String,
  format: ExportFormat,
  /** Ask for a folder when absent. */
  folder: Schema.optionalKey(Schema.String),
  filename: Schema.String,
  content: Schema.String,
})

/** Every bridge method, its params and its result. */
export const Methods = {
  "recordings.list": { params: Empty, result: Schema.Array(RecordingSummary) },
  "recordings.get": { params: Id, result: RecordingDetail },
  "recordings.rename": { params: Schema.Struct({ id: Schema.String, title: Schema.String }), result: RecordingSummary },
  "recordings.delete": { params: Schema.Struct({ id: Schema.String, deleteFiles: Schema.Boolean }), result: Void },
  "recordings.reveal": { params: Id, result: Void },
  "recordings.openExternal": { params: Id, result: Void },
  "recordings.save": {
    params: Schema.Struct({ id: Schema.String, title: Schema.String, videoFolder: Schema.String }),
    result: RecordingSummary,
  },
  "recordings.discard": { params: Id, result: Void },
  "recordings.locate": { params: Id, result: Schema.NullOr(RecordingSummary) },
  "transcripts.search": {
    params: Schema.Struct({ query: Schema.String, source: Schema.optionalKey(AudioSource) }),
    result: Schema.Array(SearchHit),
  },
  "transcripts.editSegment": { params: Schema.Struct({ id: Schema.Number, text: Schema.String }), result: Segment },
  "transcripts.retranscribe": { params: Id, result: Void },
  "transcripts.cancelRetranscribe": { params: Id, result: Void },
  "transcripts.exportFile": { params: ExportFile, result: Schema.NullOr(Schema.String) },
  "clipboard.write": { params: Schema.Struct({ text: Schema.String }), result: Void },
  "settings.get": { params: Empty, result: Settings },
  "settings.update": { params: SettingsPatch, result: Settings },
  "dialogs.chooseFolder": {
    params: Schema.Struct({ initial: Schema.optionalKey(Schema.String), prompt: Schema.optionalKey(Schema.String) }),
    result: Schema.NullOr(Schema.String),
  },
  "recorder.state": { params: Empty, result: RecorderState },
  "recorder.start": { params: Empty, result: RecorderState },
  "recorder.stop": { params: Empty, result: RecorderState },
  "system.devices": { params: Empty, result: Devices },
  "system.permissions": { params: Empty, result: Permissions },
  "system.openPermissionSettings": {
    params: Schema.Struct({ kind: Schema.Literals(["screen", "microphone"]) }),
    result: Void,
  },
} as const

export type Methods = typeof Methods
export type MethodName = keyof Methods
export type Params<M extends MethodName> = Methods[M]["params"]["Type"]
export type Result<M extends MethodName> = Methods[M]["result"]["Type"]

/** Input to the export formatter (also used by the native save path). */
export const ExportInput = Schema.Struct({
  recording: RecordingSummary,
  segments: Schema.Array(Segment),
})
export type ExportInput = typeof ExportInput.Type
