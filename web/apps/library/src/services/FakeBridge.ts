import type { BridgeEvent, RecordingSummary, SearchHit, Segment, Settings } from "@nr/core"

type Mutable<T> = { -readonly [K in keyof T]: T[K] }
import { Layer } from "effect"
import { Bridge, makeBridge } from "./Bridge.ts"

// An in-memory stand-in for the native app, used by `npm run dev` in a
// browser and by the tests. Data is made up.

const day = 86_400_000
const now = Date.UTC(2026, 9, 21, 18, 40)

const lines: Array<[Segment["source"], string]> = [
  ["others", "So the main thing we need from you this week is the pricing page, the rest can wait until after the launch."],
  ["me", "Got it. Is the pricing page the one with the three tiers, or the new one from the design review?"],
  ["others", "The new one. I'll send you the Figma link after this."],
  ["others", "Mostly it's copy changes and the annual toggle."],
  ["me", "Okay, that's quick then. I can have it on staging tomorrow and you can click through it before we push."],
  ["others", "Perfect. And can you record the walkthrough like this one so I can share it with the team?"],
  ["me", "Yes, I'll send it over with the transcript."],
]

const makeSegments = (offset: number): Array<Mutable<Segment>> => {
  let t = 2000 + offset
  return lines.map(([source, text], i) => {
    const startMs = t
    const endMs = t + 1800 + text.length * 45
    t = endMs + (i % 2 ? 900 : 300)
    return { id: offset + i + 1, source, startMs, endMs, text, confidence: 0.92 }
  })
}

const rec = (id: string, title: string, startedAt: number, durationMs: number, extra: Partial<RecordingSummary> = {}): Mutable<RecordingSummary> => ({
  id,
  title,
  startedAt,
  durationMs,
  sizeBytes: Math.round(durationMs * 186),
  width: 4096,
  height: 1728,
  displayName: "External Display",
  status: "saved",
  transcriptStatus: "complete",
  transcribedUntilMs: durationMs,
  thumbnailCount: 0,
  segmentCount: lines.length,
  fileMissing: false,
  hasSourceAudio: true,
  preview: lines[0]![1],
  previewSource: "others",
  videoPath: `/Users/example/Movies/Notch Recorder/${title}.mp4`,
  ...extra,
})

export const fakeData = () => {
  const recordings: Array<Mutable<RecordingSummary>> = [
    rec("r1", "2026-10-21 18-02-44", now - 40 * 60_000, 38 * 60_000, { status: "unsaved", videoPath: "/staging/r1.mp4" }),
    rec("r2", "Release walkthrough", now - 4 * 3600_000, 2 * 3600_000 + 24 * 60_000, {
      preview: lines[4]![1],
      previewSource: "me",
    }),
    rec("r3", "Login bug reproduction", now - 7 * 3600_000, 5 * 60_000, { width: 2016, height: 1308, displayName: "Built-in Retina Display" }),
    rec("r4", "2026-10-19 11-29-38", now - 2 * day, 82 * 60_000, { transcriptStatus: "retranscribing" }),
    rec("r5", "Landing page review", now - 9 * day, 45 * 60_000, { fileMissing: true }),
    rec("r6", "Quarterly planning call", now - 20 * day, 99 * 60_000),
  ]
  const segments = new Map(recordings.map((r, i) => [r.id, makeSegments(i * 100)]))
  const settings: Settings = {
    videoFolder: "/Users/example/Movies/Notch Recorder",
    exportOnSave: false,
    exportFormats: ["md", "srt"],
    copyFormat: "clean",
    showCursor: true,
    scale: 0.8,
    retinaPointScale: 4 / 3,
    fps: 30,
    quality: 0.6,
    transcription: true,
    showPartials: true,
    launchAtLogin: false,
  }
  return { recordings, segments, settings }
}

const ok = (value: unknown) => ({ ok: true, value })
const fail = (code: string, message: string) => ({ ok: false, error: { code, message } })

export const makeFakeTransport = (data = fakeData()) => {
  let emit: (e: BridgeEvent) => void = () => {}
  const clipboard: Array<string> = []
  const find = (id: string) => data.recordings.find((r) => r.id === id)
  const transport = async (method: string, p: any): Promise<unknown> => {
    switch (method) {
      case "recordings.list":
        return ok(data.recordings)
      case "recordings.get": {
        const r = find(p.id)
        return r ? ok({ recording: r, segments: data.segments.get(p.id) ?? [] }) : fail("NotFound", "This recording no longer exists.")
      }
      case "recordings.rename": {
        const r = find(p.id)
        if (!r) return fail("NotFound", "This recording no longer exists.")
        r.title = p.title
        emit({ _tag: "LibraryChanged", recordingId: p.id })
        return ok(r)
      }
      case "recordings.delete":
      case "recordings.discard":
        data.recordings = data.recordings.filter((r) => r.id !== p.id)
        emit({ _tag: "LibraryChanged" })
        return ok(null)
      case "recordings.save": {
        const r = find(p.id)
        if (!r) return fail("NotFound", "This recording no longer exists.")
        r.status = "saved"
        r.title = p.title
        emit({ _tag: "LibraryChanged", recordingId: p.id })
        return ok(r)
      }
      case "recordings.reveal":
      case "recordings.openExternal": {
        const r = find(p.id)
        return r?.fileMissing ? fail("FileMissing", "The video file can't be found. Use Locate to find it.") : ok(null)
      }
      case "recordings.locate":
        return ok(null)
      case "transcripts.search": {
        const q = String(p.query).toLowerCase()
        const hits: Array<SearchHit> = []
        for (const r of data.recordings) {
          for (const s of data.segments.get(r.id) ?? []) {
            if (p.source && s.source !== p.source) continue
            const i = s.text.toLowerCase().indexOf(q)
            if (q && i >= 0) {
              hits.push({
                recordingId: r.id,
                recordingTitle: r.title,
                startedAt: r.startedAt,
                durationMs: r.durationMs,
                segmentId: s.id,
                source: s.source,
                startMs: s.startMs,
                highlighted: `${s.text.slice(0, i)}\u0001${s.text.slice(i, i + q.length)}\u0002${s.text.slice(i + q.length)}`,
              })
            }
          }
        }
        return ok(hits)
      }
      case "transcripts.editSegment": {
        for (const list of data.segments.values()) {
          const s = list.find((x) => x.id === p.id)
          if (s) {
            if (s.originalText === undefined && s.text !== p.text) s.originalText = s.text
            s.text = p.text
            return ok(s)
          }
        }
        return fail("NotFound", "That line no longer exists.")
      }
      case "transcripts.retranscribe": {
        const r = find(p.id)
        if (r) r.transcriptStatus = "retranscribing"
        emit({ _tag: "LibraryChanged", recordingId: p.id })
        return ok(null)
      }
      case "transcripts.cancelRetranscribe":
        return ok(null)
      case "transcripts.exportFile":
        return ok(`/Users/example/Downloads/${p.filename}`)
      case "clipboard.write":
        clipboard.push(p.text)
        return ok(null)
      case "settings.get":
        return ok(data.settings)
      case "settings.update":
        data.settings = { ...data.settings, ...p }
        return ok(data.settings)
      case "dialogs.chooseFolder":
        return ok("/Users/example/Movies")
      case "recorder.state":
      case "recorder.start":
      case "recorder.stop":
        return ok({ phase: "idle" })
      case "system.devices":
        return ok({
          displays: [
            { id: 1, name: "External Display", width: 5120, height: 2160, isMain: true },
            { id: 2, name: "Built-in Retina Display", width: 3024, height: 1964, isMain: false },
          ],
          microphones: [
            { id: "usb", name: "USB Conference Microphone", isDefault: true },
            { id: "builtin", name: "MacBook Pro Microphone", isDefault: false },
          ],
        })
      case "system.permissions":
        return ok({ screen: true, microphone: true })
      case "system.openPermissionSettings":
        return ok(null)
      default:
        return fail("InvalidParams", `Unknown request ${method}.`)
    }
  }
  return {
    transport,
    clipboard,
    data,
    listen: (e: (raw: unknown) => void) => {
      emit = e as (e: BridgeEvent) => void
    },
    emit: (e: BridgeEvent) => emit(e),
  }
}

export const BridgeFake = Layer.sync(Bridge, () => {
  const fake = makeFakeTransport()
  return makeBridge(fake.transport, fake.listen)
})
