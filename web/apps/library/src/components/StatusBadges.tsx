import type { RecordingSummary } from "@nr/core"
import { useLibrary } from "../library.tsx"
import { Badge } from "./ui.tsx"

export const StatusBadges = ({ recording }: { recording: RecordingSummary }) => {
  const { progress } = useLibrary()
  const p = progress.get(recording.id)
  return (
    <div className="flex flex-wrap gap-1">
      {recording.status === "recording" && <Badge tone="error">Recording</Badge>}
      {recording.status === "unsaved" && <Badge tone="warning">Unsaved</Badge>}
      {recording.fileMissing && <Badge tone="error">File missing</Badge>}
      {recording.transcriptStatus === "retranscribing" && (
        <Badge tone="action">Transcribing{p !== undefined ? ` ${Math.round(p * 100)}%` : ""}</Badge>
      )}
      {recording.transcriptStatus === "failed" && <Badge tone="error">No transcript</Badge>}
    </div>
  )
}
