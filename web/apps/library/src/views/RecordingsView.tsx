import { clock, shortClock, type RecordingSummary } from "@nr/core"
import clsx from "clsx"
import { Film, Search } from "lucide-react"
import { useMemo, useState } from "react"
import { RecordingActions } from "../components/RecordingActions.tsx"
import { StatusBadges } from "../components/StatusBadges.tsx"
import { Thumb } from "../components/Thumb.tsx"
import { EmptyState, Segmented, Spinner } from "../components/ui.tsx"
import { useQuery } from "../hooks/effect.tsx"
import { fileSize, groupByDay, resolution, shortDate, speaker, speakerClass, timeOfDay } from "../lib/format.ts"
import { go } from "../lib/route.ts"
import { useLibrary } from "../library.tsx"
import { call } from "../services/Api.ts"
import { Effect } from "effect"

const Card = ({ r }: { r: RecordingSummary }) => (
  <div
    role="link"
    tabIndex={0}
    onClick={() => go({ view: "recording", id: r.id })}
    onKeyDown={(e) => e.key === "Enter" && go({ view: "recording", id: r.id })}
    className="group relative cursor-pointer rounded-[11px] p-1.5 -m-1.5 transition-colors hover:bg-surface/60 outline-none focus-visible:bg-surface/60"
  >
    <div className="relative">
      <Thumb recording={r} aspect={2} className="w-full transition-[border-color] group-hover:border-input" />
      <div className="absolute top-2 left-2">
        <StatusBadges recording={r} />
      </div>
      <div className="absolute top-2 right-2 opacity-0 transition-opacity group-hover:opacity-100">
        <RecordingActions recording={r} compact />
      </div>
      <span className="tabular absolute right-2 bottom-2 rounded-[5px] bg-black/70 px-1.5 py-px text-[11px]">{shortClock(r.durationMs)}</span>
    </div>
    <div className="px-0.5 pt-2">
      <div className="truncate text-[13px] font-semibold">{r.title}</div>
      <div className="tabular text-[11.5px] text-muted">
        {timeOfDay(r.startedAt)} · {fileSize(r.sizeBytes)} · {resolution(r.width, r.height)}
      </div>
      {r.preview ? (
        <div className="mt-1 truncate text-[12px] text-muted">
          {r.previewSource && <span className={clsx("mr-1.5 text-[11px] font-semibold", speakerClass(r.previewSource))}>{speaker(r.previewSource)}</span>}
          {r.preview}
        </div>
      ) : (
        <div className="mt-1 text-[12px] text-faint">{r.transcriptStatus === "none" ? "No transcript" : "No speech detected"}</div>
      )}
    </div>
  </div>
)

const ListRow = ({ r }: { r: RecordingSummary }) => (
  <tr
    onClick={() => go({ view: "recording", id: r.id })}
    className="group cursor-pointer border-b border-border/40 hover:bg-surface/70"
  >
    <td className="py-1.5 pr-3 pl-4">
      <Thumb recording={r} aspect={2} className="w-[92px]" scrub={false} />
    </td>
    <td className="max-w-0 py-1.5 pr-3">
      <div className="truncate font-medium">{r.title}</div>
      <div className="mt-0.5"><StatusBadges recording={r} /></div>
    </td>
    <td className="tabular py-1.5 pr-3 whitespace-nowrap text-muted">{shortDate(r.startedAt)}</td>
    <td className="tabular py-1.5 pr-3 text-muted">{shortClock(r.durationMs)}</td>
    <td className="tabular py-1.5 pr-3 text-muted">{fileSize(r.sizeBytes)}</td>
    <td className="py-1.5 pr-3" onClick={(e) => e.stopPropagation()}>
      <div className="opacity-0 group-hover:opacity-100"><RecordingActions recording={r} /></div>
    </td>
  </tr>
)

type SortKey = "date" | "duration" | "size"

export const RecordingsView = ({ unsavedOnly }: { unsavedOnly?: boolean }) => {
  const { recordings, version } = useLibrary()
  const [mode, setMode] = useState<"gallery" | "list">(() => (localStorage.getItem("nr.mode") as "list") ?? "gallery")
  const [query, setQuery] = useState("")
  const [sort, setSort] = useState<SortKey>("date")
  const q = query.trim()
  const [hits] = useQuery(
    () => (q.length > 1 ? call("transcripts.search", { query: q }) : Effect.succeed([])),
    [q, version],
  )

  const visible = useMemo(() => {
    if (recordings._tag !== "Success") return []
    let list = recordings.value.filter((r) => !unsavedOnly || r.status === "unsaved")
    if (q) {
      const ids = new Set(hits._tag === "Success" ? hits.value.map((h) => h.recordingId) : [])
      const lower = q.toLowerCase()
      list = list.filter((r) => r.title.toLowerCase().includes(lower) || ids.has(r.id))
    }
    const by: Record<SortKey, (a: RecordingSummary, b: RecordingSummary) => number> = {
      date: (a, b) => b.startedAt - a.startedAt,
      duration: (a, b) => b.durationMs - a.durationMs,
      size: (a, b) => b.sizeBytes - a.sizeBytes,
    }
    return [...list].sort(by[sort])
  }, [recordings, hits, q, unsavedOnly, sort])

  const setModeSaved = (m: "gallery" | "list") => {
    setMode(m)
    localStorage.setItem("nr.mode", m)
  }

  return (
    <div className="flex h-full flex-col">
      <header data-titlebar className="flex h-[52px] shrink-0 items-center gap-3 border-b border-toolbar-border px-5">
        <h1 className="text-[14px] font-semibold">{unsavedOnly ? "Unsaved" : "Recordings"}</h1>
        <Segmented
          value={mode}
          onChange={setModeSaved}
          options={[
            { value: "gallery", label: "Gallery" },
            { value: "list", label: "List" },
          ]}
        />
        <div className="ml-auto flex h-7 w-[300px] items-center gap-2 rounded-[7px] border border-border/70 bg-surface px-2.5 focus-within:border-action">
          <Search size={13} className="text-muted" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search"
            className="selectable h-full flex-1 bg-transparent text-[12.5px] outline-none placeholder:text-faint"
          />
        </div>
      </header>
      <div className="scroll flex-1 px-5 pt-4 pb-8">
        {recordings._tag === "Loading" && (
          <div className="flex h-40 items-center justify-center"><Spinner /></div>
        )}
        {recordings._tag === "Failure" && (
          <EmptyState icon={<Film size={28} />} title="Couldn't load the Library">{recordings.error.message}</EmptyState>
        )}
        {recordings._tag === "Success" && visible.length === 0 && (
          <EmptyState icon={<Film size={28} strokeWidth={1.5} />} title={q ? "No results" : unsavedOnly ? "No unsaved recordings" : "No recordings yet"}>
            {q ? "Try a different search." : "Recordings and their transcripts appear here. Start one with Record or Control-Option-Command-R."}
          </EmptyState>
        )}
        {visible.length > 0 && mode === "gallery" &&
          groupByDay(visible).map((g) => (
            <section key={g.label} className="mb-6">
              <h2 className="mb-2.5 text-[12px] font-semibold text-muted">{g.label}</h2>
              <div className="grid grid-cols-[repeat(auto-fill,minmax(260px,1fr))] gap-x-5 gap-y-5">
                {g.items.map((r) => <Card key={r.id} r={r} />)}
              </div>
            </section>
          ))}
        {visible.length > 0 && mode === "list" && (
          <table className="w-full table-fixed border-collapse text-[12.5px]">
            <colgroup>
              <col className="w-[116px]" />
              <col />
              <col className="w-[150px]" />
              <col className="w-[90px]" />
              <col className="w-[80px]" />
              <col className="w-[44px]" />
            </colgroup>
            <thead>
              <tr className="border-b border-border/60 text-left text-[11.5px] text-muted">
                <th />
                <th className="pb-1.5 font-medium">Title</th>
                {(["date", "duration", "size"] as const).map((k) => (
                  <th key={k} className="pb-1.5 font-medium">
                    <button type="button" onClick={() => setSort(k)} className={clsx("capitalize hover:text-text", sort === k && "text-text")}>
                      {k}
                    </button>
                  </th>
                ))}
                <th />
              </tr>
            </thead>
            <tbody>{visible.map((r) => <ListRow key={r.id} r={r} />)}</tbody>
          </table>
        )}
      </div>
    </div>
  )
}
