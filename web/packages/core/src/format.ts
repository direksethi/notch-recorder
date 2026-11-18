import type { CopyFormat, ExportFormat, ExportInput, Segment } from "./contract.ts"
import { speakerLabel, toParagraphs } from "./paragraphs.ts"
import { toCues, wrapCaption } from "./subtitles.ts"
import { clock, humanDuration, longDate, subtitleTime } from "./time.ts"

type Meta = ExportInput["recording"]

/** Text placed on the clipboard for the given segments. */
export const formatCopy = (segments: ReadonlyArray<Segment>, format: CopyFormat, meta?: Meta): string => {
  const paragraphs = toParagraphs(segments)
  switch (format) {
    case "clean":
      return paragraphs.map((p) => `${speakerLabel(p.source)}: ${p.text}`).join("\n\n")
    case "timestamps":
      return paragraphs.map((p) => `[${clock(p.startMs)}] ${speakerLabel(p.source)}: ${p.text}`).join("\n\n")
    case "plain":
      return paragraphs.map((p) => p.text).join("\n\n")
    case "markdown":
      return markdownBody(segments, meta)
  }
}

const markdownBody = (segments: ReadonlyArray<Segment>, meta?: Meta): string => {
  const head = meta ? `${markdownHeader(meta)}\n\n` : ""
  const body = toParagraphs(segments)
    .map((p) => `**${speakerLabel(p.source)}** \`${clock(p.startMs)}\`  \n${p.text}`)
    .join("\n\n")
  return head + body
}

const fileName = (path: string | undefined) => (path ? path.split("/").pop() ?? path : undefined)

const markdownHeader = (meta: Meta): string => {
  const lines = [
    `# ${meta.title}`,
    "",
    `- Date: ${longDate(meta.startedAt)}`,
    `- Duration: ${humanDuration(meta.durationMs)}`,
  ]
  const video = fileName(meta.videoPath)
  if (video) lines.push(`- Video: ${video}`)
  return lines.join("\n")
}

/** Full file contents for an export. */
export const formatExport = (input: ExportInput, format: ExportFormat): string => {
  const { recording, segments } = input
  switch (format) {
    case "md":
      return `${markdownBody(segments, recording)}\n`
    case "txt": {
      const head = [recording.title, longDate(recording.startedAt), humanDuration(recording.durationMs)].join("\n")
      return `${head}\n\n${formatCopy(segments, "timestamps")}\n`
    }
    case "srt":
      return toCues(segments)
        .map((c, i) => `${i + 1}\n${subtitleTime(c.startMs, ",")} --> ${subtitleTime(c.endMs, ",")}\n${c.lines.join("\n")}\n`)
        .join("\n")
    case "vtt":
      return `WEBVTT\n\n${toCues(segments)
        .map(
          (c) =>
            `${subtitleTime(c.startMs, ".")} --> ${subtitleTime(c.endMs, ".")}\n<v ${speakerLabel(c.source)}>${wrapCaption(c.text).join("\n")}\n`,
        )
        .join("\n")}`
    case "json":
      return `${JSON.stringify(
        {
          title: recording.title,
          startedAt: new Date(recording.startedAt).toISOString(),
          durationMs: recording.durationMs,
          video: fileName(recording.videoPath) ?? null,
          segments: segments.map((s) => ({
            speaker: speakerLabel(s.source),
            source: s.source,
            startMs: s.startMs,
            endMs: s.endMs,
            text: s.text,
          })),
        },
        null,
        2,
      )}\n`
  }
}

/** "Office walkthrough.srt"; never contains a slash or colon. */
export const exportFilename = (title: string, format: ExportFormat): string => {
  const safe = title.replace(/[/:\\]/g, "-").trim() || "Transcript"
  return `${safe}.${format}`
}
