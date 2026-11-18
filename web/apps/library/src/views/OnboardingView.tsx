import { CheckCircle2, Mic, MonitorUp } from "lucide-react"
import { type ReactNode, useEffect } from "react"
import { Button } from "../components/ui.tsx"
import { useQuery, useRun } from "../hooks/effect.tsx"
import { go } from "../lib/route.ts"
import { call } from "../services/Api.ts"

const Card = ({ icon, title, body, granted, onGrant }: { icon: ReactNode; title: string; body: string; granted: boolean; onGrant: () => void }) => (
  <div className="flex items-start gap-4 rounded-[12px] border border-border/60 bg-surface/50 p-4">
    <div className="mt-0.5 text-muted">{icon}</div>
    <div className="flex-1">
      <div className="text-[13.5px] font-semibold">{title}</div>
      <div className="mt-0.5 text-[12.5px] leading-snug text-muted">{body}</div>
    </div>
    {granted ? (
      <span className="inline-flex items-center gap-1.5 text-[12.5px] text-me"><CheckCircle2 size={15} /> Allowed</span>
    ) : (
      <Button variant="primary" onClick={onGrant}>Open System Settings</Button>
    )}
  </div>
)

export const OnboardingView = () => {
  const run = useRun()
  const [perms, refresh] = useQuery(() => call("system.permissions", {}), [])
  // Recheck while this screen is open; permission changes happen in System Settings.
  useEffect(() => {
    const t = setInterval(refresh, 2000)
    window.addEventListener("focus", refresh)
    return () => {
      clearInterval(t)
      window.removeEventListener("focus", refresh)
    }
  }, [refresh])
  const p = perms._tag === "Success" ? perms.value : { screen: false, microphone: false }

  return (
    <div className="scroll h-full">
      <div className="mx-auto flex max-w-[560px] flex-col gap-3 px-6 pt-16 pb-10">
        <h1 className="text-[22px] font-semibold tracking-tight">Set up Notch Recorder</h1>
        <p className="mb-4 text-[13px] text-muted">
          Notch Recorder needs two permissions. After setup, start and stop recording with Control-Option-Command-R, and hover the indicator at the top of the screen to view the live transcript.
        </p>
        <Card
          icon={<MonitorUp size={22} />}
          title="Screen and system audio"
          body="Required to record the screen and the audio this Mac plays. macOS asks you to confirm this periodically."
          granted={p.screen}
          onGrant={() => run(call("system.openPermissionSettings", { kind: "screen" }))}
        />
        <Card
          icon={<Mic size={22} />}
          title="Microphone"
          body="Required to record and transcribe your voice. Without it, only system audio is recorded."
          granted={p.microphone}
          onGrant={() => run(call("system.openPermissionSettings", { kind: "microphone" }))}
        />
        {p.screen && (
          <div className="mt-4 flex justify-end">
            <Button variant="primary" onClick={() => go({ view: "recordings" })}>Continue</Button>
          </div>
        )}
        {!p.screen && (
          <p className="mt-2 text-[11.5px] text-muted">After you allow screen recording, macOS may ask you to quit and reopen Notch Recorder.</p>
        )}
      </div>
    </div>
  )
}
