import type { AudioSource, Segment } from "./contract.ts"

export interface Paragraph {
  readonly source: AudioSource
  readonly startMs: number
  readonly endMs: number
  readonly segments: ReadonlyArray<Segment>
  readonly text: string
}

/** Merges consecutive segments from the same speaker that are close in time. */
export const toParagraphs = (segments: ReadonlyArray<Segment>, maxGapMs = 2000): Array<Paragraph> => {
  const out: Array<Paragraph> = []
  for (const s of segments) {
    const last = out[out.length - 1]
    if (last && last.source === s.source && s.startMs - last.endMs <= maxGapMs) {
      out[out.length - 1] = {
        ...last,
        endMs: Math.max(last.endMs, s.endMs),
        segments: [...last.segments, s],
        text: `${last.text} ${s.text}`.trim(),
      }
    } else {
      out.push({ source: s.source, startMs: s.startMs, endMs: s.endMs, segments: [s], text: s.text.trim() })
    }
  }
  return out
}

export const speakerLabel = (source: AudioSource): string =>
  source === "me" ? "Me" : source === "others" ? "Others" : "Speaker"
