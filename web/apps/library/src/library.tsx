import type { BridgeEvent, RecorderState, RecordingSummary, Settings, SettingsPatch } from "@nr/core"
import { createContext, type ReactNode, useCallback, useContext, useState } from "react"
import { type Query, useBridgeEvents, useQuery, useRun, useToast } from "./hooks/effect.tsx"
import { call } from "./services/Api.ts"

interface Library {
  readonly recordings: Query<ReadonlyArray<RecordingSummary>>
  readonly refresh: () => void
  readonly settings: Settings | undefined
  readonly updateSettings: (patch: SettingsPatch) => Promise<void>
  readonly recorder: RecorderState
  readonly progress: ReadonlyMap<string, number>
  /** Bumped whenever the native side says the library changed. */
  readonly version: number
  readonly lastEvent: BridgeEvent | undefined
}

const LibraryContext = createContext<Library | null>(null)

export const useLibrary = (): Library => {
  const l = useContext(LibraryContext)
  if (!l) throw new Error("LibraryProvider missing")
  return l
}

/** Lists, settings and recorder state shared by every view, kept fresh by native events. */
export const LibraryProvider = ({ children }: { children: ReactNode }) => {
  const run = useRun()
  const toast = useToast()
  const [version, setVersion] = useState(0)
  const [recordings, refresh] = useQuery(() => call("recordings.list", {}), [version])
  const [settingsQuery, refreshSettings] = useQuery(() => call("settings.get", {}), [])
  const [recorderQuery] = useQuery(() => call("recorder.state", {}), [])
  const [recorder, setRecorder] = useState<RecorderState | undefined>()
  const [progress, setProgress] = useState<ReadonlyMap<string, number>>(new Map())
  const [lastEvent, setLastEvent] = useState<BridgeEvent | undefined>()

  useBridgeEvents((event) => {
    setLastEvent(event)
    switch (event._tag) {
      case "LibraryChanged":
        setVersion((v) => v + 1)
        if (event.recordingId) {
          const id = event.recordingId
          setProgress((p) => {
            if (!p.has(id)) return p
            const next = new Map(p)
            next.delete(id)
            return next
          })
        }
        break
      case "RecorderStateChanged":
        setRecorder(event.state)
        break
      case "RetranscribeProgress":
        setProgress((p) => new Map(p).set(event.recordingId, event.fraction))
        break
      case "Notice":
        if (event.level === "error") toast.error(event.message)
        else toast.info(event.message)
        break
      case "SegmentAdded":
        break
    }
  })

  const updateSettings = useCallback(
    async (patch: SettingsPatch) => {
      await run(call("settings.update", patch))
      refreshSettings()
    },
    [run, refreshSettings],
  )

  const value: Library = {
    recordings,
    refresh,
    settings: settingsQuery._tag === "Success" ? settingsQuery.value : undefined,
    updateSettings,
    recorder: recorder ?? (recorderQuery._tag === "Success" ? recorderQuery.value : { phase: "idle" }),
    progress,
    version,
    lastEvent,
  }
  return <LibraryContext.Provider value={value}>{children}</LibraryContext.Provider>
}
