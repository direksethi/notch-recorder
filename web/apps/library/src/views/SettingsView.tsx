import type { CopyFormat, ExportFormat, Settings, SettingsPatch } from "@nr/core"
import clsx from "clsx"
import type { ReactNode } from "react"
import { FolderChip, Select, Spinner, Switch } from "../components/ui.tsx"
import { useQuery, useRun } from "../hooks/effect.tsx"
import { useLibrary } from "../library.tsx"
import { call } from "../services/Api.ts"

const Section = ({ title, children }: { title: string; children: ReactNode }) => (
  <section className="mb-7">
    <h2 className="mb-2 px-1 text-[12px] font-semibold text-muted">{title}</h2>
    <div className="divide-y divide-border/50 rounded-[10px] border border-border/60 bg-surface/50">{children}</div>
  </section>
)

const Row = ({ label, help, children }: { label: string; help?: ReactNode; children: ReactNode }) => (
  <div className="flex min-h-[46px] items-center gap-6 px-4 py-2.5">
    <div className="min-w-0 flex-1">
      <div className="text-[13px]">{label}</div>
      {help && <div className="mt-0.5 text-[11.5px] leading-snug text-muted">{help}</div>}
    </div>
    <div className="flex shrink-0 items-center gap-2">{children}</div>
  </div>
)

const even = (v: number) => Math.max(2, Math.floor(v / 2) * 2)

/** Output size for a display, matching RecordingSettings.outputSize in Swift. */
export const outputSize = (s: Settings, w: number, h: number, retina: boolean) => {
  const f = retina ? Math.min(1, s.retinaPointScale / 2) : s.scale
  return `${even(w * f)} × ${even(h * f)}`
}

export const SettingsView = () => {
  const { settings, updateSettings } = useLibrary()
  const run = useRun()
  const [devices] = useQuery(() => call("system.devices", {}), [])
  if (!settings) return <div className="flex h-full items-center justify-center"><Spinner /></div>

  const d = devices._tag === "Success" ? devices.value : { displays: [], microphones: [] }
  // A display is Retina when its pixel width is over 2x a typical point width; the
  // built-in MacBook screen is always Retina.
  const isRetina = (name: string) => /built-in|retina|color lcd/i.test(name)
  const external = d.displays.find((x) => !isRetina(x.name))
  const builtIn = d.displays.find((x) => isRetina(x.name))
  const set = (patch: SettingsPatch) => void updateSettings(patch)
  const chooseFolder = async (current: string, key: "videoFolder" | "exportFolder") => {
    const p = await run(call("dialogs.chooseFolder", { initial: current, prompt: "Choose" }))
    if (p) set(key === "videoFolder" ? { videoFolder: p } : { exportFolder: p })
  }
  const toggleFormat = (f: ExportFormat) => {
    const has = settings.exportFormats.includes(f)
    const next = has ? settings.exportFormats.filter((x) => x !== f) : [...settings.exportFormats, f]
    if (next.length) set({ exportFormats: next })
  }

  return (
    <div className="flex h-full flex-col">
      <header data-titlebar className="flex h-[52px] shrink-0 items-center border-b border-toolbar-border px-5">
        <h1 className="text-[14px] font-semibold">Settings</h1>
      </header>
      <div className="scroll flex-1">
        <div className="mx-auto max-w-[720px] px-6 pt-6 pb-10">
          <Section title="Recording">
            <Row label="Display" help="Main display records the screen with the menu bar: the external monitor when connected, otherwise the built-in display.">
              <Select
                label="Display"
                value={settings.displayId ?? 0}
                onChange={(v) => set({ displayId: v === 0 ? null : v })}
                options={[{ value: 0, label: "Main display" }, ...d.displays.map((x) => ({ value: x.id, label: x.name }))]}
              />
            </Row>
            <Row label="Microphone">
              <Select
                label="Microphone"
                value={settings.micDeviceId ?? ""}
                onChange={(v) => set({ micDeviceId: v === "" ? null : v })}
                options={[{ value: "", label: "System default" }, ...d.microphones.map((m) => ({ value: m.id, label: m.name }))]}
              />
            </Row>
            <Row
              label="External displays"
              help={external ? `${external.name}: ${external.width} × ${external.height} records at ${outputSize(settings, external.width, external.height, false)}` : "Scale for regular (non-Retina) displays."}
            >
              <Select
                label="External display scale"
                value={settings.scale}
                onChange={(v) => set({ scale: v })}
                options={[
                  { value: 1, label: "Full size" },
                  { value: 0.8, label: "80% (OBS)" },
                  { value: 0.75, label: "75%" },
                  { value: 2 / 3, label: "67%" },
                  { value: 0.5, label: "50%" },
                ]}
              />
            </Row>
            <Row
              label="Built-in display"
              help={builtIn ? `${builtIn.name}: ${builtIn.width} × ${builtIn.height} records at ${outputSize(settings, builtIn.width, builtIn.height, true)}` : "Retina displays record at a reduced size that keeps text sharp."}
            >
              <Select
                label="Retina display scale"
                value={Math.round(settings.retinaPointScale * 100) / 100}
                onChange={(v) => set({ retinaPointScale: v })}
                options={[
                  { value: 2, label: "Full resolution" },
                  { value: 1.5, label: "High" },
                  { value: 1.33, label: "Balanced (recommended)" },
                  { value: 1, label: "Low" },
                ]}
              />
            </Row>
            <Row label="Frame rate">
              <Select label="Frame rate" value={settings.fps} onChange={(v) => set({ fps: v })} options={[{ value: 30, label: "30 fps (OBS)" }, { value: 60, label: "60 fps" }]} />
            </Row>
            <Row label="Quality" help="HEVC constant quality. 60 matches OBS. Higher values produce larger files.">
              <input
                type="range"
                min={40}
                max={80}
                step={5}
                value={Math.round(settings.quality * 100)}
                onChange={(e) => set({ quality: Number(e.target.value) / 100 })}
                className="w-40 accent-[var(--message-action)]"
                aria-label="Quality"
              />
              <span className="tabular w-6 text-right text-[12px] text-muted">{Math.round(settings.quality * 100)}</span>
            </Row>
            <Row label="Show cursor">
              <Switch label="Show cursor" checked={settings.showCursor} onChange={(v) => set({ showCursor: v })} />
            </Row>
          </Section>

          <Section title="Saving">
            <Row label="Video folder" help="Recordings are saved here automatically when they stop, named by date and time.">
              <FolderChip path={settings.videoFolder} onClick={() => chooseFolder(settings.videoFolder, "videoFolder")} />
            </Row>
            <Row label="Export transcript on save" help="Transcripts are always stored in the Library. This also writes them to a folder.">
              <Switch label="Export transcript on save" checked={settings.exportOnSave} onChange={(v) => set({ exportOnSave: v })} />
            </Row>
            {settings.exportOnSave && (
              <Row label="Export formats">
                <div className="flex gap-1">
                  {(["md", "txt", "srt", "vtt", "json"] as const).map((f) => (
                    <button
                      key={f}
                      type="button"
                      onClick={() => toggleFormat(f)}
                      className={clsx(
                        "h-6 rounded-[6px] border px-2 text-[11.5px]",
                        settings.exportFormats.includes(f) ? "border-action bg-action/20 text-text" : "border-border text-muted hover:text-text",
                      )}
                    >
                      .{f}
                    </button>
                  ))}
                </div>
                <FolderChip
                  path={settings.exportFolder ?? settings.videoFolder}
                  onClick={() => chooseFolder(settings.exportFolder ?? settings.videoFolder, "exportFolder")}
                />
              </Row>
            )}
          </Section>

          <Section title="Transcription">
            <Row label="Transcribe while recording" help="Runs on-device with Parakeet on the Neural Engine. Audio never leaves this Mac.">
              <Switch label="Transcribe while recording" checked={settings.transcription} onChange={(v) => set({ transcription: v })} />
            </Row>
            <Row label="Show partial results" help="Shows provisional text in the live transcript window before each phrase is final.">
              <Switch label="Show partial results" checked={settings.showPartials} onChange={(v) => set({ showPartials: v })} />
            </Row>
            <Row label="Copy format" help="Format used by the Copy button.">
              <Select<CopyFormat>
                label="Copy format"
                value={settings.copyFormat}
                onChange={(v) => set({ copyFormat: v })}
                options={[
                  { value: "clean", label: "Clean text with speakers" },
                  { value: "timestamps", label: "With timestamps" },
                  { value: "plain", label: "Plain text only" },
                  { value: "markdown", label: "Markdown" },
                ]}
              />
            </Row>
          </Section>

          <Section title="General">
            <Row label="Recording shortcut" help="Starts and stops recording from any app.">
              <span className="rounded-[6px] border border-border bg-surface px-2 py-0.5 text-[12px]">⌃ ⌥ ⌘ R</span>
            </Row>
            <Row label="Open at login">
              <Switch label="Open at login" checked={settings.launchAtLogin} onChange={(v) => set({ launchAtLogin: v })} />
            </Row>
          </Section>
        </div>
      </div>
    </div>
  )
}
