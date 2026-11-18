// A bare JavaScriptCore context has none of the web or Node globals Effect
// touches while loading. These minimal versions are enough for formatting.
const g = globalThis as Record<string, unknown>

if (typeof g.TextEncoder === "undefined") {
  g.TextEncoder = class {
    readonly encoding = "utf-8"
    encode(input = ""): Uint8Array {
      const utf8 = unescape(encodeURIComponent(input))
      const out = new Uint8Array(utf8.length)
      for (let i = 0; i < utf8.length; i++) out[i] = utf8.charCodeAt(i)
      return out
    }
  }
}

if (typeof g.TextDecoder === "undefined") {
  g.TextDecoder = class {
    readonly encoding = "utf-8"
    decode(input?: Uint8Array): string {
      if (!input) return ""
      let s = ""
      for (let i = 0; i < input.length; i++) s += String.fromCharCode(input[i]!)
      return decodeURIComponent(escape(s))
    }
  }
}

if (typeof g.console === "undefined") {
  const noop = () => {}
  g.console = { log: noop, warn: noop, error: noop, info: noop, debug: noop, trace: noop }
}

if (typeof g.queueMicrotask === "undefined") {
  g.queueMicrotask = (fn: () => void) => Promise.resolve().then(fn)
}

if (typeof g.setTimeout === "undefined") {
  g.setTimeout = (fn: () => void) => {
    Promise.resolve().then(fn)
    return 0
  }
  g.clearTimeout = () => {}
}
