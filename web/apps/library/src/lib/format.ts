import type { AudioSource, RecordingSummary } from "@nr/core"

export const fileSize = (bytes: number): string => {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`
  if (bytes >= 1e6) return `${Math.round(bytes / 1e6)} MB`
  return `${Math.max(1, Math.round(bytes / 1e3))} KB`
}

export const timeOfDay = (ms: number): string =>
  new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms))

const dayKey = (ms: number) => {
  const d = new Date(ms)
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
}

/** "Today", "Yesterday", "Sunday 19 October", "Monday 1 September 2025". */
export const dayLabel = (ms: number, now = Date.now()): string => {
  if (dayKey(ms) === dayKey(now)) return "Today"
  if (dayKey(ms) === dayKey(now - 86_400_000)) return "Yesterday"
  const d = new Date(ms)
  const sameYear = d.getFullYear() === new Date(now).getFullYear()
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    ...(sameYear ? {} : { year: "numeric" }),
  })
    .format(d)
    .replace(",", "")
}

export const shortDate = (ms: number, now = Date.now()): string => {
  const label = dayLabel(ms, now)
  return label === "Today" || label === "Yesterday"
    ? `${label} ${timeOfDay(ms)}`
    : `${new Intl.DateTimeFormat("en-GB", { weekday: "short", day: "numeric", month: "short" }).format(new Date(ms)).replace(",", "")} ${timeOfDay(ms)}`
}

/** Groups newest first by calendar day. */
export const groupByDay = <A extends { readonly startedAt: number }>(items: ReadonlyArray<A>, now = Date.now()) => {
  const groups: Array<{ label: string; items: Array<A> }> = []
  for (const item of [...items].sort((a, b) => b.startedAt - a.startedAt)) {
    const label = dayLabel(item.startedAt, now)
    const last = groups[groups.length - 1]
    if (last && last.label === label) last.items.push(item)
    else groups.push({ label, items: [item] })
  }
  return groups
}

export const speaker = (s: AudioSource) => (s === "me" ? "Me" : s === "others" ? "Others" : "Speaker")

export const speakerClass = (s: AudioSource) => (s === "me" ? "text-me" : s === "others" ? "text-others" : "text-muted")

export const videoSrc = (id: string) => `nr-media://video/${encodeURIComponent(id)}`
export const thumbSrc = (id: string, n: number) => `nr-media://thumb/${encodeURIComponent(id)}/${n}.jpg`

export const isUnsaved = (r: RecordingSummary) => r.status === "unsaved"

/** Pretty folder: "iCloud Drive / Recordings". */
export const prettyFolder = (path: string): string => {
  const icloud = "/Library/Mobile Documents/com~apple~CloudDocs"
  const i = path.indexOf(icloud)
  let p = path
  if (i >= 0) p = `iCloud Drive${path.slice(i + icloud.length)}`
  else p = path.replace(/^\/Users\/[^/]+/, "~")
  return p.split("/").filter(Boolean).slice(-2).join(" / ")
}

/** "iCloud Drive / Recordings / Call.mp4" or "~/Movies/Call.mp4". */
export const prettyPath = (path: string): string => {
  const icloud = "/Library/Mobile Documents/com~apple~CloudDocs"
  const i = path.indexOf(icloud)
  if (i >= 0) return `iCloud Drive${path.slice(i + icloud.length)}`.split("/").join(" / ")
  return path.replace(/^\/Users\/[^/]+/, "~")
}

export const resolution = (w: number, h: number) => `${w} × ${h}`
