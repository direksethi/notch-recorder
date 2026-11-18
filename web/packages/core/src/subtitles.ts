import type { AudioSource, Segment } from "./contract.ts"
import { speakerLabel } from "./paragraphs.ts"

/** Broadcast caption limits: two lines of at most 42 characters each. */
export const CAPTION_LINE = 42
export const CAPTION_MAX = CAPTION_LINE * 2

export interface Cue {
  readonly startMs: number
  readonly endMs: number
  readonly source: AudioSource
  /** One or two lines, already wrapped. Includes the speaker label when shown. */
  readonly lines: ReadonlyArray<string>
  /** Text without the label, for formats that tag the speaker separately. */
  readonly text: string
}

const words = (text: string) => text.split(/\s+/).filter(Boolean)

/** Sentences, keeping their end punctuation. */
const sentences = (text: string): Array<string> =>
  text
    .trim()
    .split(/(?<=[.?!…])\s+/)
    .map((s) => s.trim())
    .filter(Boolean)

/**
 * Splits a long sentence into `ceil(length / max)` even pieces, breaking
 * at the word nearest each target length and preferring a comma, semicolon
 * or colon close by, so no piece is a lone trailing word.
 */
const splitLong = (sentence: string, max: number): Array<string> => {
  if (sentence.length <= max) return [sentence]
  const all = words(sentence)
  const pieces = Math.ceil(sentence.length / max)
  const out: Array<string> = []
  let rest = all
  for (let p = pieces; p > 1; p--) {
    const remaining = rest.join(" ").length
    const target = remaining / p
    let best = 1
    let bestScore = Number.POSITIVE_INFINITY
    let length = 0
    for (let i = 0; i < rest.length - 1; i++) {
      length += (i > 0 ? 1 : 0) + rest[i]!.length
      if (length > max) break
      const clause = /[,;:]$/.test(rest[i]!) ? 0.6 : 1
      const score = Math.abs(length - target) * clause
      if (score < bestScore) {
        bestScore = score
        best = i + 1
      }
    }
    out.push(rest.slice(0, best).join(" "))
    rest = rest.slice(best)
  }
  out.push(rest.join(" "))
  return out
}

/** Leaves room for an "Others: " label so labelled cues still fit. */
const PIECE_MAX = CAPTION_MAX - "Others: ".length

/** Short sentences share a cue when together they still fit one line. */
const pieces = (text: string): Array<string> => {
  const out: Array<string> = []
  for (const sentence of sentences(text)) {
    for (const piece of splitLong(sentence, PIECE_MAX)) {
      const last = out[out.length - 1]
      if (last !== undefined && last.length + 1 + piece.length <= CAPTION_LINE) {
        out[out.length - 1] = `${last} ${piece}`
      } else {
        out.push(piece)
      }
    }
  }
  return out
}

/** One line when it fits, otherwise two lines balanced around the middle. */
export const wrapCaption = (text: string): Array<string> => {
  if (text.length <= CAPTION_LINE) return [text]
  const all = words(text)
  let best = 1
  let bestScore = Number.POSITIVE_INFINITY
  for (let i = 1; i < all.length; i++) {
    const top = all.slice(0, i).join(" ").length
    const bottom = all.slice(i).join(" ").length
    const overflow = Math.max(0, top - CAPTION_LINE) + Math.max(0, bottom - CAPTION_LINE)
    const clause = /[,;:.?!]$/.test(all[i - 1]!) ? -4 : 0
    const score = overflow * 100 + Math.abs(top - bottom) + clause
    if (score < bestScore) {
      bestScore = score
      best = i
    }
  }
  return [all.slice(0, best).join(" "), all.slice(best).join(" ")]
}

/**
 * Turns transcript segments into caption-sized cues. Each segment's time is
 * shared between its cues by length, since segments carry no word timings.
 * The speaker label appears when the speaker changes.
 */
export const toCues = (segments: ReadonlyArray<Segment>): Array<Cue> => {
  const cues: Array<Cue> = []
  let lastSource: AudioSource | undefined
  for (const s of segments) {
    const parts = pieces(s.text)
    if (parts.length === 0) continue
    const total = parts.reduce((n, p) => n + p.length, 0)
    const span = Math.max(0, s.endMs - s.startMs)
    let at = s.startMs
    let used = 0
    parts.forEach((part, i) => {
      used += part.length
      const end = i === parts.length - 1 ? s.endMs : Math.round(s.startMs + (span * used) / total)
      const labelled = s.source !== lastSource ? `${speakerLabel(s.source)}: ${part}` : part
      cues.push({ startMs: at, endMs: end, source: s.source, lines: wrapCaption(labelled), text: part })
      lastSource = s.source
      at = end
    })
  }
  return cues
}
