import { type ReactNode, useEffect } from "react"

/** A small centred modal. Escape cancels, Return confirms. */
export const Dialog = ({
  title,
  children,
  onCancel,
  onConfirm,
}: {
  title: string
  children: ReactNode
  onCancel: () => void
  onConfirm?: () => void
}) => {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel()
      if (e.key === "Enter" && onConfirm && !(e.target instanceof HTMLTextAreaElement)) onConfirm()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [onCancel, onConfirm])
  return (
    <div className="fade-in fixed inset-0 z-50 flex items-center justify-center bg-black/45" onMouseDown={onCancel}>
      <div
        role="dialog"
        aria-label={title}
        className="pop-in w-[400px] rounded-[12px] border border-border bg-surface-raised p-4 shadow-[0_24px_70px_rgba(0,0,0,0.6)]"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="mb-2 text-[14px] font-semibold">{title}</div>
        {children}
      </div>
    </div>
  )
}
