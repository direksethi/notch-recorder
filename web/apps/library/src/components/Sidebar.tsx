import clsx from "clsx"
import { CircleDot, FileText, Film, Settings as Gear, Square } from "lucide-react"
import type { ReactNode } from "react"
import { useRun } from "../hooks/effect.tsx"
import { fileSize } from "../lib/format.ts"
import { go, type Route } from "../lib/route.ts"
import { useLibrary } from "../library.tsx"
import { call } from "../services/Api.ts"
import { useElapsed } from "./useElapsed.ts"

const Row = ({ active, icon, label, count, onClick, tone }: {
  active: boolean
  icon: ReactNode
  label: string
  count?: number
  onClick: () => void
  tone?: "warning"
}) => (
  <button
    type="button"
    onClick={onClick}
    aria-current={active ? "page" : undefined}
    className={clsx(
      "flex h-7 w-full items-center gap-2 rounded-[7px] px-2 text-left text-[13px] transition-colors",
      active ? "bg-sidebar-row-selected text-text" : "text-sidebar-muted hover:bg-sidebar-row-hover hover:text-text",
    )}
  >
    <span className={clsx("flex w-4 justify-center", tone === "warning" ? "text-warning" : "")}>{icon}</span>
    <span className="flex-1 truncate">{label}</span>
    {count !== undefined && <span className="tabular text-[11.5px] text-muted">{count}</span>}
  </button>
)

export const Sidebar = ({ route }: { route: Route }) => {
  const { recordings, recorder } = useLibrary()
  const run = useRun()
  const list = recordings._tag === "Success" ? recordings.value : []
  const unsaved = list.filter((r) => r.status === "unsaved").length
  const withTranscripts = list.filter((r) => r.segmentCount > 0).length
  const total = list.reduce((s, r) => s + r.sizeBytes, 0)
  const recording = recorder.phase !== "idle"
  const elapsed = useElapsed(recorder.startedAt, recording)
  const view = route.view === "recording" ? undefined : route.view

  return (
    <aside className="flex w-[216px] shrink-0 flex-col border-r border-sidebar-border bg-sidebar px-2.5 pb-2.5">
      {/* The window controls sit in this band, level with the content header. */}
      <div data-titlebar className="-mx-2.5 h-[52px] shrink-0" />
      <button
        type="button"
        onClick={() => run(call(recording ? "recorder.stop" : "recorder.start", {}))}
        disabled={recorder.phase === "starting" || recorder.phase === "stopping"}
        className={clsx(
          "mb-4 flex h-8 w-full items-center justify-center gap-2 rounded-[8px] text-[12.5px] font-medium transition-colors disabled:opacity-60",
          recording ? "bg-recording/90 text-white hover:bg-recording" : "bg-control text-text hover:bg-control-hover",
        )}
      >
        {recording ? (
          <>
            <Square size={11} fill="currentColor" /> Stop <span className="tabular opacity-85">{elapsed}</span>
          </>
        ) : (
          <>
            <CircleDot size={13} className="text-recording" /> Record
            <span className="ml-1 text-[11px] text-muted">⌃⌥⌘R</span>
          </>
        )}
      </button>
      <nav className="flex flex-col gap-0.5">
        {unsaved > 0 && (
          <Row
            active={view === "unsaved"}
            icon={<span className="size-[7px] rounded-full bg-warning" />}
            label="Unsaved"
            count={unsaved}
            tone="warning"
            onClick={() => go({ view: "unsaved" })}
          />
        )}
        <Row active={view === "recordings"} icon={<Film size={14} />} label="Recordings" count={list.length} onClick={() => go({ view: "recordings" })} />
        <Row active={view === "transcripts"} icon={<FileText size={14} />} label="Transcripts" count={withTranscripts} onClick={() => go({ view: "transcripts" })} />
      </nav>
      <div className="mt-auto flex flex-col gap-1.5">
        <Row active={view === "settings"} icon={<Gear size={14} />} label="Settings" onClick={() => go({ view: "settings" })} />
        <div className="px-2 text-[11px] leading-snug text-muted">
          {list.length} recording{list.length === 1 ? "" : "s"} · {fileSize(total)}
        </div>
      </div>
    </aside>
  )
}
