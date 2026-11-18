import {
  clock,
  type CopyFormat,
  type ExportFormat,
  formatCopy,
  type Paragraph,
  type RecordingDetail,
  type Segment,
  toParagraphs,
} from "@nr/core"
import clsx from "clsx"
import { ChevronDown, ChevronUp, Copy, Link2, Search, X } from "lucide-react"
import { type KeyboardEvent as ReactKeyboardEvent, useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRun, useToast } from "../hooks/effect.tsx"
import { speaker, speakerClass } from "../lib/format.ts"
import { useLibrary } from "../library.tsx"
import { call, copySegments, copyTranscript, exportTranscript } from "../services/Api.ts"
import { Button, IconButton, Menu, MenuItem, MenuLabel, MenuSeparator, Segmented } from "./ui.tsx"

type Filter = "all" | "me" | "others"

const COPY_FORMATS: ReadonlyArray<{ value: CopyFormat; label: string; sample: string }> = [
  { value: "clean", label: "Clean text with speakers", sample: "Others: So the main thing…" },
  { value: "timestamps", label: "With timestamps", sample: "[00:02:14] Others: So the main…" },
  { value: "plain", label: "Plain text only", sample: "So the main thing we need…" },
  { value: "markdown", label: "Markdown", sample: "**Others** `00:02:14`" },
]

const EXPORT_FORMATS: ReadonlyArray<{ value: ExportFormat; label: string; hint: string }> = [
  { value: "md", label: "Markdown", hint: ".md" },
  { value: "txt", label: "Plain text", hint: ".txt" },
  { value: "srt", label: "Subtitles (SubRip)", hint: ".srt" },
  { value: "vtt", label: "Subtitles (WebVTT)", hint: ".vtt" },
  { value: "json", label: "JSON", hint: ".json" },
]

/** Splits text around case-insensitive matches of `q`. */
const highlight = (text: string, q: string) => {
  if (!q) return [text]
  const out: Array<string | { m: string }> = []
  const lower = text.toLowerCase()
  const needle = q.toLowerCase()
  let i = 0
  for (;;) {
    const j = lower.indexOf(needle, i)
    if (j < 0) break
    if (j > i) out.push(text.slice(i, j))
    out.push({ m: text.slice(j, j + q.length) })
    i = j + q.length
  }
  if (i < text.length) out.push(text.slice(i))
  return out
}

const EditBox = ({ segment, onDone }: { segment: Segment; onDone: (text: string | null) => void }) => {
  const [value, setValue] = useState(segment.text)
  const ref = useRef<HTMLTextAreaElement>(null)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    el.focus()
    el.select()
  }, [])
  useEffect(() => {
    const el = ref.current
    if (el) {
      el.style.height = "auto"
      el.style.height = `${el.scrollHeight}px`
    }
  }, [value])
  const onKey = (e: ReactKeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      onDone(value)
    }
    if (e.key === "Escape") onDone(null)
  }
  return (
    <textarea
      ref={ref}
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onKeyDown={onKey}
      onBlur={() => onDone(value)}
      rows={1}
      className="selectable my-0.5 block w-full resize-none rounded-[6px] border border-action bg-surface px-1.5 py-0.5 text-[13.5px] leading-relaxed outline-none"
    />
  )
}

export const TranscriptPanel = ({
  detail,
  currentMs,
  playing,
  onSeek,
  onSegmentEdited,
}: {
  detail: RecordingDetail
  currentMs: number
  playing: boolean
  onSeek: (ms: number) => void
  onSegmentEdited: (s: Segment) => void
}) => {
  const { settings, updateSettings } = useLibrary()
  const run = useRun()
  const toast = useToast()
  const [filter, setFilter] = useState<Filter>("all")
  const [selected, setSelected] = useState<ReadonlySet<number>>(new Set())
  const anchor = useRef<number | null>(null)
  const [editing, setEditing] = useState<number | null>(null)
  const [finding, setFinding] = useState(false)
  const [find, setFind] = useState("")
  const [findIndex, setFindIndex] = useState(0)
  const listRef = useRef<HTMLDivElement>(null)
  const userScrolledAt = useRef(0)
  const copyFormat: CopyFormat = settings?.copyFormat ?? "clean"

  const paragraphs = useMemo<Array<Paragraph>>(
    () => toParagraphs(filter === "all" ? detail.segments : detail.segments.filter((s) => s.source === filter)),
    [detail.segments, filter],
  )
  useEffect(() => setSelected(new Set()), [filter, detail.recording.id])

  const current = useMemo(() => {
    let found = -1
    paragraphs.forEach((p, i) => {
      if (p.startMs <= currentMs + 150) found = i
    })
    return found
  }, [paragraphs, currentMs])

  // Follow playback unless the user scrolled in the last few seconds.
  useEffect(() => {
    if (!playing || current < 0 || Date.now() - userScrolledAt.current < 4000) return
    listRef.current?.querySelector(`[data-p="${current}"]`)?.scrollIntoView({ block: "center", behavior: "smooth" })
  }, [current, playing])

  const matches = useMemo(() => {
    const q = find.trim().toLowerCase()
    if (!q) return []
    return paragraphs.flatMap((p, i) => (p.text.toLowerCase().includes(q) ? [i] : []))
  }, [paragraphs, find])
  useEffect(() => setFindIndex(0), [find])
  useEffect(() => {
    const i = matches[findIndex]
    if (i !== undefined) listRef.current?.querySelector(`[data-p="${i}"]`)?.scrollIntoView({ block: "center" })
  }, [matches, findIndex])

  const selectedSegments = useCallback(
    () => [...selected].sort((a, b) => a - b).flatMap((i) => paragraphs[i]?.segments ?? []),
    [selected, paragraphs],
  )

  const copySelected = useCallback(async () => {
    const segments = selectedSegments()
    if (segments.length === 0) return
    const n = await run(copySegments(detail, segments, copyFormat))
    if (n !== undefined) toast.info(`${selected.size} line${selected.size === 1 ? "" : "s"} copied.`)
  }, [selectedSegments, run, detail, copyFormat, toast, selected.size])

  // Command-C copies selected lines (unless text is selected, which copies normally).
  // Command-F opens find. Command-A selects every line.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement
      if (e.metaKey && e.key === "f") {
        e.preventDefault()
        setFinding(true)
        return
      }
      if (typing) return
      if (e.metaKey && e.key === "c" && selected.size > 0 && (window.getSelection()?.isCollapsed ?? true)) {
        e.preventDefault()
        void copySelected()
      }
      if (e.metaKey && e.key === "a") {
        e.preventDefault()
        setSelected(new Set(paragraphs.map((_, i) => i)))
      }
      if (e.key === "Escape") setSelected(new Set())
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [selected, copySelected, paragraphs])

  const clickParagraph = (i: number, e: React.MouseEvent) => {
    if (e.shiftKey && anchor.current !== null) {
      const [a, b] = [Math.min(anchor.current, i), Math.max(anchor.current, i)]
      setSelected(new Set(Array.from({ length: b - a + 1 }, (_, k) => a + k)))
      return
    }
    if (e.metaKey) {
      setSelected((s) => {
        const next = new Set(s)
        if (next.has(i)) next.delete(i)
        else next.add(i)
        return next
      })
      anchor.current = i
      return
    }
    anchor.current = i
    setSelected(new Set([i]))
    onSeek(paragraphs[i]!.startMs)
  }

  const saveEdit = async (segment: Segment, text: string | null) => {
    setEditing(null)
    if (text === null || text.trim() === segment.text) return
    const updated = await run(call("transcripts.editSegment", { id: segment.id, text }))
    if (updated) onSegmentEdited(updated)
  }

  const copyOne = async (p: Paragraph) => {
    const n = await run(copySegments(detail, p.segments, copyFormat))
    if (n !== undefined) toast.info("Line copied.")
  }

  const copyLink = async (p: Paragraph) => {
    const text = `${detail.recording.title} @ ${clock(p.startMs)}`
    if ((await run(call("clipboard.write", { text }))) !== undefined) toast.info("Link copied.")
  }

  const copyAll = async (format: CopyFormat) => {
    if ((await run(copyTranscript(detail, format))) !== undefined) {
      toast.info("Transcript copied.")
      void updateSettings({ copyFormat: format })
    }
  }

  const doExport = async (format: ExportFormat) => {
    const path = await run(exportTranscript(detail, format))
    if (path) toast.info(`Exported ${path.split("/").pop()}.`)
  }

  const empty = detail.segments.length === 0

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex h-11 shrink-0 items-center gap-2 border-b border-toolbar-border px-3.5">
        <Segmented
          size="sm"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "Everyone" },
            { value: "me", label: "Me" },
            { value: "others", label: "Others" },
          ]}
        />
        <IconButton label="Find" onClick={() => setFinding((f) => !f)} className={finding ? "text-text" : ""}>
          <Search size={14} />
        </IconButton>
        <div className="flex-1" />
        {selected.size > 0 && (
          <Button size="sm" variant="ghost" onClick={copySelected}>
            Copy {selected.size} line{selected.size === 1 ? "" : "s"} <span className="text-faint">⌘C</span>
          </Button>
        )}
        <Menu
          width={200}
          trigger={({ toggle }) => (
            <Button size="sm" onClick={toggle} disabled={empty}>
              Export <ChevronDown size={12} />
            </Button>
          )}
        >
          {(close) => (
            <>
              <MenuLabel>Export as</MenuLabel>
              {EXPORT_FORMATS.map((f) => (
                <MenuItem key={f.value} hint={f.hint} onSelect={() => { close(); void doExport(f.value) }}>
                  {f.label}
                </MenuItem>
              ))}
            </>
          )}
        </Menu>
        <Menu
          width={290}
          trigger={({ toggle }) => (
            <div className="flex">
              <Button size="sm" variant="primary" className="rounded-r-none" disabled={empty} onClick={() => copyAll(copyFormat)}>
                <Copy size={12} /> Copy
              </Button>
              <Button size="sm" variant="primary" className="rounded-l-none border-l border-white/20 px-1.5" disabled={empty} onClick={toggle} aria-label="Copy options">
                <ChevronDown size={12} />
              </Button>
            </div>
          )}
        >
          {(close) => (
            <>
              <MenuLabel>Copy transcript as</MenuLabel>
              {COPY_FORMATS.map((f) => (
                <MenuItem
                  key={f.value}
                  checked={copyFormat === f.value}
                  detail={f.sample}
                  hint={copyFormat === f.value ? "default" : undefined}
                  onSelect={() => { close(); void copyAll(f.value) }}
                >
                  {f.label}
                </MenuItem>
              ))}
              <MenuSeparator />
              <MenuItem hint="⌘C" onSelect={() => { close(); void copySelected() }}>
                Copy selected lines
              </MenuItem>
            </>
          )}
        </Menu>
      </div>

      {finding && (
        <div className="flex h-10 shrink-0 items-center gap-2 border-b border-toolbar-border bg-surface/50 px-3.5">
          <Search size={13} className="text-muted" />
          <input
            autoFocus
            value={find}
            onChange={(e) => setFind(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") setFindIndex((i) => (matches.length ? (i + (e.shiftKey ? matches.length - 1 : 1)) % matches.length : 0))
              if (e.key === "Escape") {
                setFinding(false)
                setFind("")
              }
            }}
            placeholder="Find in transcript"
            className="selectable h-full flex-1 bg-transparent text-[12.5px] outline-none placeholder:text-faint"
          />
          <span className="tabular text-[11px] text-muted">{find ? `${matches.length ? findIndex + 1 : 0} of ${matches.length}` : ""}</span>
          <IconButton label="Previous" className="size-6" onClick={() => setFindIndex((i) => (matches.length ? (i - 1 + matches.length) % matches.length : 0))}>
            <ChevronUp size={14} />
          </IconButton>
          <IconButton label="Next" className="size-6" onClick={() => setFindIndex((i) => (matches.length ? (i + 1) % matches.length : 0))}>
            <ChevronDown size={14} />
          </IconButton>
          <IconButton label="Close find" className="size-6" onClick={() => { setFinding(false); setFind("") }}>
            <X size={13} />
          </IconButton>
        </div>
      )}

      <div
        ref={listRef}
        className="scroll flex-1 px-2 py-2"
        onWheel={() => {
          userScrolledAt.current = Date.now()
        }}
      >
        {paragraphs.map((p, i) => {
          const isCurrent = i === current
          const isSelected = selected.has(i)
          const isMatch = matches[findIndex] === i
          return (
            <div
              key={`${p.startMs}-${p.source}`}
              data-p={i}
              onClick={(e) => clickParagraph(i, e)}
              className={clsx(
                "group relative grid grid-cols-[76px_1fr] gap-3 rounded-[8px] px-2.5 py-2 transition-colors duration-100",
                isSelected ? "bg-action/22" : isCurrent ? "bg-surface-raised/70" : "hover:bg-surface/70",
                isMatch && "ring-1 ring-match-active/70",
              )}
            >
              <div className="pt-px text-right">
                <div className={clsx("text-[11px] font-semibold", speakerClass(p.source))}>{speaker(p.source)}</div>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation()
                    onSeek(p.startMs)
                  }}
                  className="tabular text-[11px] text-muted hover:text-text hover:underline"
                >
                  {clock(p.startMs)}
                </button>
              </div>
              <div className={clsx("selectable text-[13.5px] leading-relaxed", isCurrent ? "text-text" : "text-text/88")}>
                {p.segments.map((s, k) => (
                  editing === s.id ? (
                    <EditBox key={s.id} segment={s} onDone={(text) => saveEdit(s, text)} />
                  ) : (
                    <span
                      key={s.id}
                      onDoubleClick={(e) => {
                        e.stopPropagation()
                        setEditing(s.id)
                      }}
                      title={s.originalText ? `Edited. Original: "${s.originalText}"` : "Double-click to edit"}
                      className={clsx(s.originalText && "underline decoration-action/50 decoration-dotted underline-offset-4")}
                    >
                      {highlight(s.text, find.trim()).map((part, n) =>
                        typeof part === "string" ? <span key={n}>{part}</span> : <mark key={n}>{part.m}</mark>,
                      )}
                      {k < p.segments.length - 1 ? " " : ""}
                    </span>
                  )
                ))}
              </div>
              <div className="absolute top-1.5 right-1.5 flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                <IconButton label="Copy line" className="size-6 bg-surface-raised" onClick={(e) => { e.stopPropagation(); void copyOne(p) }}>
                  <Copy size={12} />
                </IconButton>
                <IconButton label="Copy link to timestamp" className="size-6 bg-surface-raised" onClick={(e) => { e.stopPropagation(); void copyLink(p) }}>
                  <Link2 size={12} />
                </IconButton>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
