import { NativeError, userMessage } from "@nr/core"
import { Effect, Exit, Layer, ManagedRuntime } from "effect"
import { describe, expect, it } from "vitest"
import { groupByDay, prettyFolder, prettyPath } from "../src/lib/format.ts"
import { parseRoute, href } from "../src/lib/route.ts"
import { call, copySegments, copyTranscript, exportTranscript } from "../src/services/Api.ts"
import { Bridge, makeBridge } from "../src/services/Bridge.ts"
import { makeFakeTransport } from "../src/services/FakeBridge.ts"

const setup = () => {
  const fake = makeFakeTransport()
  const runtime = ManagedRuntime.make(Layer.succeed(Bridge, makeBridge(fake.transport, fake.listen)))
  return { fake, runtime }
}

describe("bridge services", () => {
  it("copy uses the chosen format and remembers it", async () => {
    const { fake, runtime } = setup()
    const detail = await runtime.runPromise(call("recordings.get", { id: "r2" }))
    await runtime.runPromise(copyTranscript(detail, "timestamps"))
    expect(fake.clipboard[0]!.startsWith("[00:00:02] Others: So the main thing")).toBe(true)
    const settings = await runtime.runPromise(call("settings.get", {}))
    expect(settings.copyFormat).toBe("timestamps")
  })

  it("selection copy formats only the selected lines", async () => {
    const { fake, runtime } = setup()
    const detail = await runtime.runPromise(call("recordings.get", { id: "r2" }))
    const n = await runtime.runPromise(copySegments(detail, detail.segments.slice(1, 2), "clean"))
    expect(n).toBe(1)
    expect(fake.clipboard[0]).toBe("Me: Got it. Is the pricing page the one with the three tiers, or the new one from the design review?")
  })

  it("export formats then writes through the native side", async () => {
    const { runtime } = setup()
    const detail = await runtime.runPromise(call("recordings.get", { id: "r2" }))
    const path = await runtime.runPromise(exportTranscript(detail, "srt"))
    expect(path).toBe("/Users/example/Downloads/Release walkthrough.srt")
  })

  it("missing file comes back as a NativeError with a readable message", async () => {
    const { runtime } = setup()
    const exit = await runtime.runPromiseExit(call("recordings.reveal", { id: "r5" }))
    expect(Exit.isFailure(exit)).toBe(true)
    const error = await runtime.runPromise(Effect.flip(call("recordings.reveal", { id: "r5" })))
    expect(error).toBeInstanceOf(NativeError)
    expect(error._tag === "NativeError" && error.code).toBe("FileMissing")
    expect(userMessage(error)).toContain("Locate")
  })

  it("a reply that breaks the contract is a DecodeError", async () => {
    const bridge = makeBridge(async () => ({ ok: true, value: [{ id: 1 }] }), () => {})
    const runtime = ManagedRuntime.make(Layer.succeed(Bridge, bridge))
    const error = await runtime.runPromise(Effect.flip(call("recordings.list", {})))
    expect(error._tag).toBe("DecodeError")
  })

  it("a transport failure is a BridgeError", async () => {
    const bridge = makeBridge(async () => {
      throw new Error("gone")
    }, () => {})
    const runtime = ManagedRuntime.make(Layer.succeed(Bridge, bridge))
    const error = await runtime.runPromise(Effect.flip(call("recordings.list", {})))
    expect(error._tag).toBe("BridgeError")
  })

  it("events are decoded and delivered", async () => {
    const { fake, runtime } = setup()
    const seen: Array<string> = []
    await runtime.runPromise(Effect.gen(function* () {
      const b = yield* Bridge
      return yield* b.subscribe((e) => seen.push(e._tag))
    }))
    fake.emit({ _tag: "RetranscribeProgress", recordingId: "r1", fraction: 0.5 })
    expect(seen).toEqual(["RetranscribeProgress"])
  })
})

describe("helpers", () => {
  it("search groups days newest first", () => {
    const day = 86_400_000
    const now = Date.UTC(2026, 9, 21, 12)
    const groups = groupByDay([{ startedAt: now - 2 * day }, { startedAt: now }, { startedAt: now - 60_000 }], now)
    expect(groups.map((g) => g.label)).toEqual(["Today", "Monday 19 October"])
    expect(groups[0]!.items).toHaveLength(2)
  })
  it("routes round trip", () => {
    const r = parseRoute(href({ view: "recording", id: "a b", at: 1500 }))
    expect(r).toEqual({ view: "recording", id: "a b", at: 1500 })
    expect(parseRoute("#/nonsense")).toEqual({ view: "recordings" })
  })
  it("paths read nicely", () => {
    const p = "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/Recordings/Call.mp4"
    expect(prettyPath(p)).toBe("iCloud Drive / Recordings / Call.mp4")
    expect(prettyFolder("/Users/example/Movies/Calls")).toBe("Movies / Calls")
  })
})
