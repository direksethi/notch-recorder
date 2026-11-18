import {
  type CopyFormat,
  type ExportFormat,
  exportFilename,
  formatCopy,
  formatExport,
  type MethodName,
  type Params,
  type RecordingDetail,
  type Segment,
} from "@nr/core"
import { Effect } from "effect"
import { Bridge } from "./Bridge.ts"

/** Calls a native method through the Bridge service. */
export const call = <M extends MethodName>(method: M, params: Params<M>) =>
  Effect.gen(function* () {
    const bridge = yield* Bridge
    return yield* bridge.call(method, params)
  })

/** Copies segments in `format`; returns how many lines went to the clipboard. */
export const copySegments = Effect.fn("copySegments")(function* (
  detail: RecordingDetail,
  segments: ReadonlyArray<Segment>,
  format: CopyFormat,
) {
  const text = formatCopy(segments, format, detail.recording)
  yield* call("clipboard.write", { text })
  return segments.length
})

/** Copies the whole transcript and remembers the format for next time. */
export const copyTranscript = Effect.fn("copyTranscript")(function* (detail: RecordingDetail, format: CopyFormat) {
  yield* copySegments(detail, detail.segments, format)
  yield* call("settings.update", { copyFormat: format })
})

/** Formats and writes a transcript file; null when the user cancels the save panel. */
export const exportTranscript = Effect.fn("exportTranscript")(function* (detail: RecordingDetail, format: ExportFormat) {
  const content = formatExport(detail, format)
  return yield* call("transcripts.exportFile", {
    id: detail.recording.id,
    format,
    filename: exportFilename(detail.recording.title, format),
    content,
  })
})
