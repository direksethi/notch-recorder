import { clock, shortClock, type RecordingDetail, type Segment } from "@nr/core"
import clsx from "clsx"
import { AlertTriangle, ArrowLeft, FileText, FolderOpen, Loader2, PanelLeftClose, PanelLeftOpen, Play } from "lucide-react"
import { useCallback, useEffect, useRef, useState } from "react"
import { RecordingActions } from "../components/RecordingActions.tsx"
import { TranscriptPanel } from "../components/TranscriptPanel.tsx"
import { Button, EmptyState, FolderChip, Spinner } from "../components/ui.tsx"
import { useQuery, useRun, useToast } from "../hooks/effect.tsx"
import { fileSize, prettyPath, resolution, shortDate, videoSrc } from "../lib/format.ts"
import { go } from "../lib/route.ts"
import { useLibrary } from "../library.tsx"
import { call } from "../services/Api.ts"

const SaveBar = ({ detail, onDone }: { detail: RecordingDetail; onDone: () => void }) => {
  const { settings } = useLibrary()
  const run = useRun()
  const toast = useToast()
  const [title, setTitle] = useState(detail.recording.title)
  const [folder, setFolder] = useState<string | undefined>(undefined)
  const videoFolder = folder ?? settings?.videoFolder ?? ""
  const [confirmDiscard, setConfirmDiscard] = useState(false)

  const save = async () => {
    const r = await run(call("recordings.save", { id: detail.recording.id, title: title.trim() || detail.recording.title, videoFolder }))
    if (r) {
      toast.info(`Saved to ${videoFolder.split("/").pop()}.`)
      onDone()
    }
  }
  const discard = async () => {
    if (!confirmDiscard) {
      setConfirmDiscard(true)
      return
    }
    if ((await run(call("recordings.discard", { id: detail.recording.id }))) !== undefined) go({ view: "recordings" })
  }
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2.5 border-b border-warning/25 bg-warning-surface/60 px-5 py-2.5">
      <span className="text-[12.5px] font-medium text-warning-foreground">Unsaved</span>
      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && save()}
        aria-label="Title"
        className="selectable h-7 w-[260px] rounded-[7px] border border-input bg-surface px-2.5 text-[12.5px] outline-none focus:border-action"
      />
      <FolderChip
        path={videoFolder}
        onClick={async () => {
          const p = await run(call("dialogs.chooseFolder", { initial: videoFolder, prompt: "Save Here" }))
          if (p) setFolder(p)
        }}
      />
      <div className="ml-auto flex gap-2">
        <Button variant={confirmDiscard ? "danger" : "ghost"} onClick={discard} onBlur={() => setConfirmDiscard(false)}>
          {confirmDiscard ? "Confirm discard" : "Discard"}
        </Button>
        <Button variant="primary" onClick={save}>Save</Button>
      </div>
    </div>
  )
}

const TranscriptState = ({ detail }: { detail: RecordingDetail }) => {
  const { progress } = useLibrary()
  const run = useRun()
  const r = detail.recording
  if (r.transcriptStatus === "retranscribing") {
    const p = progress.get(r.id)
    return (
      <div className="flex shrink-0 items-center gap-3 border-b border-toolbar-border px-3.5 py-2 text-[12px] text-muted">
        <Loader2 size={13} className="animate-spin" />
        <span>Transcribing{p !== undefined ? ` ${Math.round(p * 100)}%` : "…"}</span>
        <div className="h-1 flex-1 overflow-hidden rounded-full bg-control">
          <div className="h-full bg-action transition-[width] duration-500" style={{ width: `${Math.round((p ?? 0.02) * 100)}%` }} />
        </div>
        <Button size="sm" variant="ghost" onClick={() => run(call("transcripts.cancelRetranscribe", { id: r.id }))}>Cancel</Button>
      </div>
    )
  }
  if (r.transcriptStatus === "failed") {
    return (
      <div className="flex shrink-0 items-center gap-3 border-b border-error/25 bg-error-surface/50 px-3.5 py-2 text-[12px] text-error-foreground">
        <AlertTriangle size={13} />
        <span className="flex-1">Live transcription stopped before the recording ended. Transcribe again to complete it.</span>
        <Button size="sm" onClick={() => run(call("transcripts.retranscribe", { id: r.id }))}>Transcribe again</Button>
      </div>
    )
  }
  return null
}

export const DetailView = ({ id, at }: { id: string; at?: number }) => {
  const { version, lastEvent, recorder } = useLibrary()
  const run = useRun()
  const [query, refresh] = useQuery(() => call("recordings.get", { id }), [id, version])
  const [detail, setDetail] = useState<RecordingDetail | undefined>()
  const videoRef = useRef<HTMLVideoElement>(null)
  const [currentMs, setCurrentMs] = useState(0)
  const [playing, setPlaying] = useState(false)
  const [reading, setReading] = useState(() => localStorage.getItem("nr.reading") === "1")
  const [videoError, setVideoError] = useState(false)
  const pendingSeek = useRef<number | undefined>(at)

  useEffect(() => {
    if (query._tag === "Success") setDetail(query.value)
  }, [query])
  useEffect(() => {
    pendingSeek.current = at
    setVideoError(false)
  }, [id, at])

  // Lines arriving live while this recording is still running.
  useEffect(() => {
    if (lastEvent?._tag === "SegmentAdded" && lastEvent.recordingId === id) {
      setDetail((d) => (d && !d.segments.some((s) => s.id === lastEvent.segment.id) ? { ...d, segments: [...d.segments, lastEvent.segment] } : d))
    }
  }, [lastEvent, id])

  const seek = useCallback((ms: number) => {
    const v = videoRef.current
    if (!v) {
      setCurrentMs(ms)
      return
    }
    v.currentTime = ms / 1000
    setCurrentMs(ms)
  }, [])

  // Space plays and pauses when not typing.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== " " || e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      const v = videoRef.current
      if (!v) return
      e.preventDefault()
      if (v.paused) void v.play()
      else v.pause()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  if (!detail) {
    if (query._tag === "Failure") {
      return (
        <EmptyState icon={<FileText size={26} />} title="Couldn't open this recording">
          {query.error.message}{" "}
          <button type="button" className="text-action underline" onClick={() => go({ view: "recordings" })}>Back to Recordings</button>
        </EmptyState>
      )
    }
    return <div className="flex h-full items-center justify-center"><Spinner /></div>
  }

  const r = detail.recording
  const live = recorder.phase !== "idle" && recorder.recordingId === r.id
  const canPlay = !live && !r.fileMissing && r.status !== "recording"
  const toggleReading = () => {
    setReading((x) => {
      localStorage.setItem("nr.reading", x ? "0" : "1")
      return !x
    })
  }

  return (
    <div className="flex h-full flex-col">
      <header data-titlebar className="flex h-[52px] shrink-0 items-center gap-2.5 border-b border-toolbar-border px-4">
        <button
          type="button"
          aria-label="Back"
          onClick={() => (history.length > 1 ? history.back() : go({ view: "recordings" }))}
          className="inline-flex size-7 items-center justify-center rounded-[7px] text-muted hover:bg-control-hover hover:text-text"
        >
          <ArrowLeft size={16} />
        </button>
        <div className="min-w-0">
          <h1 className="truncate text-[14px] font-semibold">{r.title}</h1>
          <div className="tabular truncate text-[11.5px] text-muted">
            {shortDate(r.startedAt)} · {shortClock(r.durationMs)} · {fileSize(r.sizeBytes)}
            {r.width > 0 && ` · ${resolution(r.width, r.height)}`}
          </div>
        </div>
        <div className="ml-auto flex items-center gap-1.5">
          <Button variant="ghost" onClick={toggleReading} title={reading ? "Show video" : "Reading mode"}>
            {reading ? <PanelLeftOpen size={14} /> : <PanelLeftClose size={14} />} {reading ? "Show video" : "Reading mode"}
          </Button>
          {r.fileMissing ? (
            <Button onClick={() => run(call("recordings.locate", { id: r.id })).then(() => refresh())}>
              <FolderOpen size={13} /> Locate…
            </Button>
          ) : (
            <Button onClick={() => run(call("recordings.reveal", { id: r.id }))} disabled={live}>
              <FolderOpen size={13} /> Show in Finder
            </Button>
          )}
          <RecordingActions recording={r} onRenamed={refresh} />
        </div>
      </header>

      {r.status === "unsaved" && !live && <SaveBar detail={detail} onDone={refresh} />}
      {r.errorMessage && r.status !== "saved" && (
        <div className="shrink-0 border-b border-toolbar-border px-5 py-1.5 text-[12px] text-muted">{r.errorMessage}</div>
      )}

      <div className={clsx("grid min-h-0 flex-1", reading ? "grid-cols-1" : "grid-cols-[minmax(0,1.15fr)_minmax(380px,1fr)]")}>
        {!reading && (
          <div className="flex min-h-0 flex-col gap-3 border-r border-toolbar-border p-4">
            <div className="relative overflow-hidden rounded-[10px] border border-border/60 bg-black" style={{ aspectRatio: r.width && r.height ? `${r.width} / ${r.height}` : "2.37" }}>
              {canPlay && !videoError ? (
                <video
                  ref={videoRef}
                  src={videoSrc(r.id)}
                  controls
                  preload="metadata"
                  className="absolute inset-0 size-full"
                  onLoadedMetadata={() => {
                    if (pendingSeek.current !== undefined && videoRef.current) {
                      videoRef.current.currentTime = pendingSeek.current / 1000
                      setCurrentMs(pendingSeek.current)
                      pendingSeek.current = undefined
                    }
                  }}
                  onTimeUpdate={(e) => setCurrentMs(e.currentTarget.currentTime * 1000)}
                  onPlay={() => setPlaying(true)}
                  onPause={() => setPlaying(false)}
                  onError={() => setVideoError(true)}
                />
              ) : (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-center text-[12.5px] text-muted">
                  {live ? (
                    <>
                      <span className="size-2.5 animate-pulse rounded-full bg-recording" />
                      Recording in progress. The transcript updates as people speak.
                    </>
                  ) : r.fileMissing ? (
                    <>
                      <AlertTriangle size={20} />
                      The video file was moved or deleted.
                      <Button size="sm" onClick={() => run(call("recordings.locate", { id: r.id })).then(() => refresh())}>Locate…</Button>
                    </>
                  ) : (
                    <>
                      <Play size={20} />
                      This video can't be played here.
                      <Button size="sm" onClick={() => run(call("recordings.openExternal", { id: r.id }))}>Open in QuickTime</Button>
                    </>
                  )}
                </div>
              )}
            </div>
            <div className="text-[11.5px] leading-relaxed text-muted">
              {r.displayName && <div>{r.displayName}</div>}
              {r.videoPath && <div className="selectable truncate" title={r.videoPath}>{prettyPath(r.videoPath)}</div>}
            </div>
          </div>
        )}
        <div className={clsx("flex min-h-0 flex-col", reading && "mx-auto w-full max-w-[860px]")}>
          <TranscriptState detail={detail} />
          {detail.segments.length === 0 && r.transcriptStatus !== "retranscribing" ? (
            <EmptyState icon={<FileText size={24} strokeWidth={1.5} />} title={live ? "Listening for speech" : "No transcript"}>
              {live ? (
                "The transcript appears here as people speak."
              ) : r.transcriptStatus === "none" || r.transcriptStatus === "failed" || r.transcriptStatus === "partial" ? (
                <Button className="mt-2" onClick={() => run(call("transcripts.retranscribe", { id: r.id }))}>Transcribe now</Button>
              ) : (
                "No speech was detected in this recording."
              )}
            </EmptyState>
          ) : (
            <TranscriptPanel
              detail={detail}
              currentMs={currentMs}
              playing={playing}
              onSeek={seek}
              onSegmentEdited={(s: Segment) =>
                setDetail((d) => (d ? { ...d, segments: d.segments.map((x) => (x.id === s.id ? s : x)) } : d))
              }
            />
          )}
        </div>
      </div>
    </div>
  )
}
