import { type AudioSource, clock, shortClock, groupBy, splitHighlight } from "@nr/core"
import clsx from "clsx"
import { Effect } from "effect"
import { FileText, Search } from "lucide-react"
import { useEffect, useMemo, useState } from "react"
import { EmptyState, Segmented, Spinner } from "../components/ui.tsx"
import { useQuery } from "../hooks/effect.tsx"
import { shortDate, speaker, speakerClass } from "../lib/format.ts"
import { go } from "../lib/route.ts"
import { useLibrary } from "../library.tsx"
import { call } from "../services/Api.ts"

type Filter = "all" | AudioSource

export const TranscriptsView = ({ initialQuery }: { initialQuery?: string }) => {
  const { recordings, version } = useLibrary()
  const [query, setQuery] = useState(initialQuery ?? "")
  const [debounced, setDebounced] = useState(query)
  const [filter, setFilter] = useState<Filter>("all")
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 160)
    return () => clearTimeout(t)
  }, [query])

  const [hits] = useQuery(
    () =>
      debounced.length > 0
        ? call("transcripts.search", filter === "all" ? { query: debounced } : { query: debounced, source: filter })
        : Effect.succeed([]),
    [debounced, filter, version],
  )

  const grouped = useMemo(
    () => (hits._tag === "Success" ? [...groupBy(hits.value, (h) => h.recordingId).values()] : []),
    [hits],
  )
  const withTranscripts =
    recordings._tag === "Success" ? recordings.value.filter((r) => r.segmentCount > 0 || r.transcriptStatus === "retranscribing") : []
  const matchCount = hits._tag === "Success" ? hits.value.length : 0

  return (
    <div className="flex h-full flex-col">
      <header data-titlebar className="flex h-[52px] shrink-0 items-center gap-3 border-b border-toolbar-border px-5">
        <h1 className="text-[14px] font-semibold">Transcripts</h1>
        <div className="ml-3 flex h-7 max-w-[460px] flex-1 items-center gap-2 rounded-[7px] border border-border/70 bg-surface px-2.5 focus-within:border-action">
          <Search size={13} className="text-muted" />
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search transcripts"
            className="selectable h-full flex-1 bg-transparent text-[12.5px] outline-none placeholder:text-faint"
          />
          {debounced && (
            <span className="tabular text-[11px] whitespace-nowrap text-muted">
              {matchCount} match{matchCount === 1 ? "" : "es"} in {grouped.length}
            </span>
          )}
        </div>
        <Segmented
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "Everyone" },
            { value: "me", label: "Me" },
            { value: "others", label: "Others" },
          ]}
        />
      </header>
      <div className="scroll flex-1 px-5 pt-3 pb-8">
        {debounced ? (
          hits._tag === "Loading" ? (
            <div className="flex h-40 items-center justify-center"><Spinner /></div>
          ) : grouped.length === 0 ? (
            <EmptyState icon={<Search size={26} strokeWidth={1.5} />} title={`No results for "${debounced}"`}>
              Searches match the beginning of words.
            </EmptyState>
          ) : (
            <div className="flex flex-col gap-1.5">
              {grouped.map((group) => {
                const first = group[0]!
                return (
                  <section key={first.recordingId} className="rounded-[10px] border border-border/50 bg-surface/40 px-3.5 py-2.5">
                    <button
                      type="button"
                      onClick={() => go({ view: "recording", id: first.recordingId })}
                      className="mb-1.5 flex w-full items-baseline gap-3 text-left"
                    >
                      <span className="truncate font-semibold hover:underline">{first.recordingTitle}</span>
                      <span className="tabular ml-auto shrink-0 text-[11.5px] text-muted">
                        {shortDate(first.startedAt)} · {shortClock(first.durationMs)}
                      </span>
                    </button>
                    <div className="flex flex-col">
                      {group.slice(0, 6).map((h) => (
                        <button
                          key={h.segmentId}
                          type="button"
                          onClick={() => go({ view: "recording", id: h.recordingId, at: h.startMs })}
                          className="flex items-baseline gap-2.5 rounded-[6px] px-1.5 py-1 text-left text-[12.5px] hover:bg-control-hover"
                        >
                          <span className="tabular w-[58px] shrink-0 text-[11px] text-muted">{clock(h.startMs)}</span>
                          <span className={clsx("w-[44px] shrink-0 text-[11px] font-semibold", speakerClass(h.source))}>{speaker(h.source)}</span>
                          <span className="text-text/90">
                            {splitHighlight(h.highlighted).map((p, i) => (p.match ? <mark key={i}>{p.text}</mark> : <span key={i}>{p.text}</span>))}
                          </span>
                        </button>
                      ))}
                      {group.length > 6 && (
                        <button
                          type="button"
                          onClick={() => go({ view: "recording", id: first.recordingId, at: group[6]!.startMs })}
                          className="px-1.5 pt-1 text-left text-[11.5px] text-muted hover:text-text"
                        >
                          {group.length - 6} more match{group.length - 6 === 1 ? "" : "es"}
                        </button>
                      )}
                    </div>
                  </section>
                )
              })}
            </div>
          )
        ) : withTranscripts.length === 0 ? (
          <EmptyState icon={<FileText size={26} strokeWidth={1.5} />} title="No transcripts yet">
            Speech from your microphone and your Mac's audio is transcribed during each recording and stored here.
          </EmptyState>
        ) : (
          <div className="flex flex-col">
            {withTranscripts.map((r) => (
              <button
                key={r.id}
                type="button"
                onClick={() => go({ view: "recording", id: r.id })}
                className="grid grid-cols-[1fr_auto] gap-x-4 rounded-[8px] border-b border-border/40 px-3 py-2.5 text-left hover:bg-surface/60"
              >
                <span className="truncate font-semibold">{r.title}</span>
                <span className="tabular text-[11.5px] text-muted">{shortDate(r.startedAt)} · {shortClock(r.durationMs)}</span>
                <span className="col-span-2 mt-0.5 truncate text-[12.5px] text-muted">
                  {r.previewSource && <span className={clsx("mr-1.5 text-[11px] font-semibold", speakerClass(r.previewSource))}>{speaker(r.previewSource)}</span>}
                  {r.preview ?? (r.transcriptStatus === "retranscribing" ? "Transcribing…" : "")}
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
