const pad = (n: number, w = 2) => String(Math.floor(n)).padStart(w, "0")

/** 00:02:14 */
export const clock = (ms: number): string => {
  const total = Math.max(0, Math.floor(ms / 1000))
  return `${pad(total / 3600)}:${pad((total % 3600) / 60)}:${pad(total % 60)}`
}

/** "38:12" under an hour, "2:24:05" above. */
export const shortClock = (ms: number): string => {
  const total = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

/** 00:00:01,250 (SubRip) or 00:00:01.250 (WebVTT) */
export const subtitleTime = (ms: number, sep: "," | "."): string => {
  const m = Math.max(0, Math.round(ms))
  return `${clock(m)}${sep}${pad(m % 1000, 3)}`
}

/** "2 h 24 min", "38 min", "45 s" */
export const humanDuration = (ms: number): string => {
  const s = Math.round(ms / 1000)
  if (s < 60) return `${s} s`
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  return h > 0 ? (m > 0 ? `${h} h ${m} min` : `${h} h`) : `${m} min`
}

/** "Tuesday 21 October 2026, 14:24" in the local time zone. */
export const longDate = (epochMs: number): string => {
  const d = new Date(epochMs)
  const date = new Intl.DateTimeFormat("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" })
    .format(d)
    .replace(",", "")
  const time = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false }).format(d)
  return `${date}, ${time}`
}
