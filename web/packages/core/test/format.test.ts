import { Schema } from "effect"
import { describe, expect, it } from "vitest"
import { ExportInput, RecordingStatus } from "../src/contract.ts"
import { exportFilename, formatCopy, formatExport } from "../src/format.ts"
import { toParagraphs } from "../src/paragraphs.ts"
import { splitHighlight } from "../src/search.ts"
import { clock, humanDuration } from "../src/time.ts"
import { detail, recording, segments } from "./fixtures.ts"

describe("formatCopy", () => {
  it("clean merges consecutive lines from the same speaker", () => {
    expect(formatCopy(segments, "clean")).toBe(
      "Others: So the main thing is the pricing page.\n\nMe: Got it.\n\nOthers: Great.",
    )
  })
  it("timestamps uses [hh:mm:ss] at paragraph start", () => {
    expect(formatCopy(segments, "timestamps").split("\n\n")[0]).toBe(
      "[00:00:01] Others: So the main thing is the pricing page.",
    )
  })
  it("plain drops speakers", () => {
    expect(formatCopy(segments, "plain")).toBe("So the main thing is the pricing page.\n\nGot it.\n\nGreat.")
  })
  it("markdown bolds speakers", () => {
    expect(formatCopy(segments, "markdown")).toContain("**Me** `00:00:06`  \nGot it.")
  })
})

describe("formatExport", () => {
  it("srt numbering and comma millis", () => {
    const srt = formatExport(detail, "srt")
    expect(srt.startsWith("1\n00:00:01,250 --> 00:00:03,000\nOthers: So the main thing\n")).toBe(true)
    expect(srt).toContain("\n2\n00:00:03,500 --> 00:00:05,000\nis the pricing page.\n")
    expect(srt).toContain("\n4\n00:00:20,000 --> 00:00:21,000\nOthers: Great.\n")
  })
  it("vtt header and dot millis", () => {
    const vtt = formatExport(detail, "vtt")
    expect(vtt.startsWith("WEBVTT\n\n00:00:01.250 --> 00:00:03.000\n<v Others>So the main thing\n")).toBe(true)
  })
  it("markdown export has a header with the video file name", () => {
    const md = formatExport(detail, "md")
    expect(md.startsWith("# Pricing call\n")).toBe(true)
    expect(md).toContain("- Duration: 2 h 24 min")
    expect(md).toContain("- Video: Pricing call.mp4")
  })
  it("json round-trips segments", () => {
    const parsed = JSON.parse(formatExport(detail, "json"))
    expect(parsed.segments).toHaveLength(4)
    expect(parsed.segments[2]).toEqual({ speaker: "Me", source: "me", startMs: 6000, endMs: 8000, text: "Got it." })
    expect(parsed.video).toBe("Pricing call.mp4")
  })
})

describe("helpers", () => {
  it("exportFilename strips slashes and colons", () => {
    expect(exportFilename("a/b: c", "srt")).toBe("a-b- c.srt")
    expect(exportFilename("  ", "md")).toBe("Transcript.md")
  })
  it("toParagraphs splits on gap over 2000 ms", () => {
    const ps = toParagraphs([
      { id: 1, source: "me", startMs: 0, endMs: 1000, text: "a", confidence: 1 },
      { id: 2, source: "me", startMs: 3001, endMs: 4000, text: "b", confidence: 1 },
    ])
    expect(ps.map((p) => p.text)).toEqual(["a", "b"])
  })
  it("clock and durations", () => {
    expect(clock(8_645_100)).toBe("02:24:05")
    expect(humanDuration(45_000)).toBe("45 s")
    expect(humanDuration(38 * 60_000)).toBe("38 min")
  })
  it("splitHighlight marks matches", () => {
    expect(splitHighlight("the \u0001pricing\u0002 page")).toEqual([
      { text: "the ", match: false },
      { text: "pricing", match: true },
      { text: " page", match: false },
    ])
  })
})

describe("contract", () => {
  it("decode rejects unknown status", () => {
    expect(() => Schema.decodeUnknownSync(RecordingStatus)("archived")).toThrow()
  })
  it("decodes a full export input", () => {
    expect(Schema.decodeUnknownSync(ExportInput)(JSON.parse(JSON.stringify(detail))).recording.id).toBe(recording.id)
  })
})
