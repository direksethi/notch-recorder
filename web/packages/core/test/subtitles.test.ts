import { describe, expect, it } from "vitest"
import type { Segment } from "../src/contract.ts"
import { formatExport } from "../src/format.ts"
import { CAPTION_LINE, toCues, wrapCaption } from "../src/subtitles.ts"
import { detail, recording, segments } from "./fixtures.ts"

const long: Segment = {
  id: 1,
  source: "me",
  startMs: 0,
  endMs: 16_000,
  text: "So I'm just testing this out and like what do you think about this recording service and stuff and yeah, it's pretty good. I'm recording my screen and stuff like that and let's see how it is and blah blah blah.",
  confidence: 0.9,
}

describe("toCues", () => {
  const cues = toCues([long])

  it("splits a long segment into cues of at most two short lines", () => {
    expect(cues.length).toBeGreaterThanOrEqual(3)
    for (const c of cues) {
      expect(c.lines.length).toBeLessThanOrEqual(2)
      for (const line of c.lines) expect(line.length).toBeLessThanOrEqual(CAPTION_LINE + 4)
    }
  })

  it("keeps every word in order", () => {
    expect(cues.map((c) => c.text).join(" ")).toBe(long.text)
  })

  it("shares the segment's time without gaps", () => {
    expect(cues[0]!.startMs).toBe(0)
    expect(cues.at(-1)!.endMs).toBe(16_000)
    for (let i = 1; i < cues.length; i++) expect(cues[i]!.startMs).toBe(cues[i - 1]!.endMs)
  })

  it("labels the speaker only when it changes", () => {
    expect(cues[0]!.lines[0]!.startsWith("Me: ")).toBe(true)
    expect(cues.slice(1).every((c) => !c.lines[0]!.startsWith("Me: "))).toBe(true)
    const labelled = toCues(segments).map((c) => c.lines[0]!.split(":")[0])
    expect(labelled).toEqual(["Others", "is the pricing page.", "Me", "Others"])
  })

  it("does not leave a lone word on its own cue", () => {
    for (const c of cues) expect(c.text.split(" ").length).toBeGreaterThan(2)
  })
})

describe("wrapCaption", () => {
  it("keeps short text on one line", () => {
    expect(wrapCaption("Got it.")).toEqual(["Got it."])
  })
  it("balances two lines", () => {
    const [a, b] = wrapCaption("I'm recording my screen and stuff like that and let's see how it is")
    expect(Math.abs(a!.length - b!.length)).toBeLessThan(12)
  })
})

describe("subtitle exports", () => {
  it("srt uses the cues", () => {
    const srt = formatExport({ recording, segments: [long] }, "srt")
    expect(srt.startsWith("1\n00:00:00,000 --> ")).toBe(true)
    expect(srt).toContain("\n2\n")
  })
  it("vtt tags every cue with its speaker and no inline label", () => {
    const vtt = formatExport(detail, "vtt")
    expect(vtt).toContain("<v Others>is the pricing page.\n")
  })
})
