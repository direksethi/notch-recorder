import type { RecordingSummary } from "@nr/core"
import clsx from "clsx"
import { MonitorPlay } from "lucide-react"
import { useState } from "react"
import { thumbSrc } from "../lib/format.ts"

/** The recording's frame; moving the pointer across it scrubs through the video. */
export const Thumb = ({ recording, className, scrub = true, aspect: fixed }: { recording: RecordingSummary; className?: string; scrub?: boolean; aspect?: number }) => {
  const [index, setIndex] = useState(0)
  const [hovering, setHovering] = useState(false)
  const [broken, setBroken] = useState(false)
  const count = recording.thumbnailCount
  const aspect = fixed ?? (recording.width > 0 && recording.height > 0 ? recording.width / recording.height : 2.37)
  return (
    <div
      className={clsx("relative overflow-hidden rounded-[9px] border border-border/60 bg-surface", className)}
      style={{ aspectRatio: String(Math.max(1.4, Math.min(2.6, aspect))) }}
      onMouseMove={(e) => {
        if (!scrub || count < 2) return
        const r = e.currentTarget.getBoundingClientRect()
        setIndex(Math.min(count - 1, Math.max(0, Math.floor(((e.clientX - r.left) / r.width) * count))))
      }}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => {
        setHovering(false)
        setIndex(0)
      }}
    >
      {count > 0 && !broken ? (
        <img
          src={thumbSrc(recording.id, index)}
          alt=""
          draggable={false}
          onError={() => setBroken(true)}
          className="absolute inset-0 size-full object-cover"
        />
      ) : (
        <div className="absolute inset-0 flex items-center justify-center text-muted/60">
          <MonitorPlay size={26} strokeWidth={1.4} />
        </div>
      )}
      {scrub && hovering && count > 1 && (
        <div className="absolute inset-x-0 bottom-0 h-[3px] bg-white/15">
          <div className="h-full bg-white" style={{ width: `${((index + 1) / count) * 100}%` }} />
        </div>
      )}
    </div>
  )
}
