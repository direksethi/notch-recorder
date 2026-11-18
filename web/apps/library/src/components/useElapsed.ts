import { clock } from "@nr/core"
import { useEffect, useState } from "react"

/** "00:12:04" since `startedAt`, ticking once a second while active. */
export const useElapsed = (startedAt: number | undefined, active: boolean): string => {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    if (!active) return
    const t = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(t)
  }, [active])
  return active && startedAt ? clock(now - startedAt) : ""
}
