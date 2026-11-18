import type { RecordingSummary } from "@nr/core"
import { MoreHorizontal } from "lucide-react"
import { useState } from "react"
import { useRun, useToast } from "../hooks/effect.tsx"
import { go } from "../lib/route.ts"
import { call } from "../services/Api.ts"
import { Dialog } from "./Dialog.tsx"
import { Button, IconButton, Menu, MenuItem, MenuSeparator } from "./ui.tsx"

/** Reveal, open, rename, transcribe again, delete: used on cards and in the detail view. */
export const RecordingActions = ({ recording, onRenamed, compact }: {
  recording: RecordingSummary
  onRenamed?: () => void
  compact?: boolean
}) => {
  const run = useRun()
  const toast = useToast()
  const [renaming, setRenaming] = useState(false)
  const [title, setTitle] = useState(recording.title)
  const [deleting, setDeleting] = useState(false)
  const saved = recording.status === "saved"

  const rename = async () => {
    const next = title.trim()
    setRenaming(false)
    if (!next || next === recording.title) return
    if (await run(call("recordings.rename", { id: recording.id, title: next }))) onRenamed?.()
  }

  const remove = async (deleteFiles: boolean) => {
    setDeleting(false)
    const done = await run(call("recordings.delete", { id: recording.id, deleteFiles }))
    if (done !== undefined) {
      toast.info(deleteFiles ? "Video moved to Trash." : "Recording removed.")
      if (window.location.hash.includes(recording.id)) go({ view: "recordings" })
    }
  }

  return (
    <>
      <Menu
        width={230}
        trigger={({ toggle }) =>
          compact ? (
            <IconButton
              label="More"
              onClick={(e) => {
                e.stopPropagation()
                toggle()
              }}
              className="size-6 bg-black/55 text-text hover:bg-black/75"
            >
              <MoreHorizontal size={14} />
            </IconButton>
          ) : (
            <IconButton label="More" onClick={toggle}>
              <MoreHorizontal size={16} />
            </IconButton>
          )
        }
      >
        {(close) => (
          <div onClick={(e) => e.stopPropagation()}>
            <MenuItem onSelect={() => { close(); run(call("recordings.reveal", { id: recording.id })) }}>Show in Finder</MenuItem>
            <MenuItem onSelect={() => { close(); run(call("recordings.openExternal", { id: recording.id })) }}>Open in QuickTime</MenuItem>
            <MenuItem onSelect={() => { close(); setTitle(recording.title); setRenaming(true) }}>Rename…</MenuItem>
            <MenuSeparator />
            <MenuItem
              onSelect={() => {
                close()
                run(call("transcripts.retranscribe", { id: recording.id })).then((r) => r !== undefined && toast.info("Transcription started."))
              }}
            >
              Transcribe again
            </MenuItem>
            <MenuSeparator />
            <MenuItem danger onSelect={() => { close(); setDeleting(true) }}>
              Delete…
            </MenuItem>
          </div>
        )}
      </Menu>
      {renaming && (
        <Dialog title="Rename recording" onCancel={() => setRenaming(false)} onConfirm={rename}>
          <input
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="selectable mb-3 h-8 w-full rounded-[7px] border border-input bg-surface px-2.5 text-[13px] outline-none focus:border-action"
          />
          {saved && <p className="mb-3 text-[12px] text-muted">The video file is also renamed.</p>}
          <div className="flex justify-end gap-2">
            <Button onClick={() => setRenaming(false)}>Cancel</Button>
            <Button variant="primary" onClick={rename}>Rename</Button>
          </div>
        </Dialog>
      )}
      {deleting && (
        <Dialog title={`Delete "${recording.title}"?`} onCancel={() => setDeleting(false)}>
          <p className="mb-4 text-[12.5px] text-muted">
            {saved
              ? "Remove the recording from the Library, or also move its video to Trash. The transcript is deleted in both cases."
              : "This recording hasn't been saved. Its video and transcript will be deleted."}
          </p>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setDeleting(false)}>Cancel</Button>
            {saved && <Button onClick={() => remove(false)}>Remove from Library</Button>}
            <Button variant="danger" onClick={() => remove(true)}>
              {saved ? "Move video to Trash" : "Delete recording"}
            </Button>
          </div>
        </Dialog>
      )}
    </>
  )
}
