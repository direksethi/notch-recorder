import clsx from "clsx"
import { Check, ChevronsUpDown, Folder } from "lucide-react"
import { type ButtonHTMLAttributes, type ReactNode, useEffect, useRef, useState } from "react"
import { prettyFolder } from "../lib/format.ts"

type Variant = "default" | "primary" | "ghost" | "danger"

export const Button = ({
  variant = "default",
  size = "md",
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: "sm" | "md" }) => (
  <button
    type="button"
    {...props}
    className={clsx(
      "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-[7px] font-medium whitespace-nowrap transition-colors duration-100 disabled:pointer-events-none disabled:opacity-45",
      size === "sm" ? "h-6 px-2 text-[11.5px]" : "h-7 px-2.5 text-[12.5px]",
      variant === "primary" && "bg-action text-white hover:bg-action-hover",
      variant === "default" && "border border-border/70 bg-control text-text hover:bg-control-hover",
      variant === "ghost" && "text-muted hover:bg-control-hover hover:text-text",
      variant === "danger" && "border border-error/40 bg-error-surface text-error-foreground hover:bg-error/25",
      className,
    )}
  />
)

export const IconButton = ({ label, className, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) => (
  <button
    type="button"
    aria-label={label}
    title={label}
    {...props}
    className={clsx(
      "inline-flex size-7 shrink-0 items-center justify-center rounded-[7px] text-muted transition-colors hover:bg-control-hover hover:text-text",
      className,
    )}
  />
)

export const Segmented = <T extends string>({
  value,
  options,
  onChange,
  size = "md",
}: {
  value: T
  options: ReadonlyArray<{ value: T; label: string }>
  onChange: (v: T) => void
  size?: "sm" | "md"
}) => (
  <div role="radiogroup" className="inline-flex rounded-[8px] bg-control p-0.5">
    {options.map((o) => (
      <button
        key={o.value}
        type="button"
        role="radio"
        aria-checked={value === o.value}
        onClick={() => onChange(o.value)}
        className={clsx(
          "rounded-[6px] px-2.5 transition-colors",
          size === "sm" ? "h-5 text-[11px]" : "h-6 text-[12px]",
          value === o.value ? "bg-surface-raised text-text shadow-sm" : "text-muted hover:text-text",
        )}
      >
        {o.label}
      </button>
    ))}
  </div>
)

export const Badge = ({ tone = "neutral", children }: { tone?: "neutral" | "warning" | "error" | "action"; children: ReactNode }) => (
  <span
    className={clsx(
      "inline-flex h-[18px] items-center gap-1 rounded-[5px] px-1.5 text-[10.5px] font-semibold",
      tone === "neutral" && "bg-black/55 text-text",
      tone === "warning" && "bg-warning-surface text-warning-foreground",
      tone === "error" && "bg-error-surface text-error-foreground",
      tone === "action" && "bg-action/25 text-text",
    )}
  >
    {children}
  </span>
)

export const Spinner = ({ className }: { className?: string }) => (
  <span className={clsx("inline-block size-3.5 animate-spin rounded-full border-[1.5px] border-muted/40 border-t-text", className)} />
)

/** A dropdown menu anchored to its trigger. */
export const Menu = ({
  trigger,
  children,
  align = "end",
  width = 260,
}: {
  trigger: (props: { open: boolean; toggle: () => void }) => ReactNode
  children: (close: () => void) => ReactNode
  align?: "start" | "end"
  width?: number
}) => {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false)
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false)
    }
    document.addEventListener("mousedown", onDown)
    document.addEventListener("keydown", onKey)
    return () => {
      document.removeEventListener("mousedown", onDown)
      document.removeEventListener("keydown", onKey)
    }
  }, [open])
  return (
    <div ref={ref} className="relative">
      {trigger({ open, toggle: () => setOpen((o) => !o) })}
      {open && (
        <div
          role="menu"
          style={{ width }}
          className={clsx(
            "pop-in absolute top-[calc(100%+6px)] z-40 rounded-[10px] border border-border bg-surface-overlay p-1 shadow-[0_18px_50px_rgba(0,0,0,0.55)]",
            align === "end" ? "right-0" : "left-0",
          )}
        >
          {children(() => setOpen(false))}
        </div>
      )}
    </div>
  )
}

export const MenuItem = ({
  children,
  hint,
  checked,
  danger,
  onSelect,
  detail,
}: {
  children: ReactNode
  hint?: string | undefined
  checked?: boolean | undefined
  danger?: boolean | undefined
  detail?: string | undefined
  onSelect: () => void
}) => (
  <button
    type="button"
    role="menuitem"
    onClick={onSelect}
    className={clsx(
      "group flex w-full flex-col rounded-[6px] px-2 py-1.5 text-left text-[12.5px] hover:bg-action hover:text-white",
      danger ? "text-error-foreground" : "text-text",
    )}
  >
    <span className="flex w-full items-center gap-2">
      <span className="w-3.5 shrink-0">{checked && <Check size={13} />}</span>
      <span className="flex-1">{children}</span>
      {hint && <span className="text-[11px] text-muted group-hover:text-white/80">{hint}</span>}
    </span>
    {detail && (
      <span className="truncate pl-[22px] text-[11px] text-muted group-hover:text-white/75">{detail}</span>
    )}
  </button>
)

export const MenuLabel = ({ children }: { children: ReactNode }) => (
  <div className="px-2 pt-1.5 pb-1 text-[10.5px] font-semibold tracking-[0.04em] text-muted uppercase">{children}</div>
)

export const MenuSeparator = () => <div className="mx-1 my-1 h-px bg-border/70" />

export const FolderChip = ({ path, onClick }: { path: string; onClick: () => void }) => (
  <button
    type="button"
    onClick={onClick}
    className="inline-flex h-7 max-w-[340px] items-center gap-1.5 rounded-[7px] border border-border/70 bg-control px-2.5 text-[12.5px] text-text hover:bg-control-hover"
  >
    <Folder size={13} className="shrink-0 text-muted" />
    <span className="truncate">{prettyFolder(path)}</span>
    <ChevronsUpDown size={11} className="shrink-0 text-muted" />
  </button>
)

export const Switch = ({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) => (
  <button
    type="button"
    role="switch"
    aria-checked={checked}
    aria-label={label}
    onClick={() => onChange(!checked)}
    className={clsx(
      "relative inline-flex h-[18px] w-8 shrink-0 items-center rounded-full transition-colors duration-150",
      checked ? "bg-action" : "bg-input",
    )}
  >
    <span
      className={clsx(
        "inline-block size-[14px] rounded-full bg-white shadow transition-transform duration-150",
        checked ? "translate-x-[16px]" : "translate-x-[2px]",
      )}
    />
  </button>
)

export const Select = <T extends string | number>({
  value,
  options,
  onChange,
  label,
}: {
  value: T
  options: ReadonlyArray<{ value: T; label: string }>
  onChange: (v: T) => void
  label: string
}) => (
  <div className="relative">
    <select
      aria-label={label}
      value={String(value)}
      onChange={(e) => {
        const o = options.find((x) => String(x.value) === e.target.value)
        if (o) onChange(o.value)
      }}
      className="h-7 min-w-[220px] appearance-none rounded-[7px] border border-border/70 bg-control pr-7 pl-2.5 text-[12.5px] text-text outline-none hover:bg-control-hover"
    >
      {options.map((o) => (
        <option key={String(o.value)} value={String(o.value)}>
          {o.label}
        </option>
      ))}
    </select>
    <ChevronsUpDown size={11} className="pointer-events-none absolute top-1/2 right-2.5 -translate-y-1/2 text-muted" />
  </div>
)

export const EmptyState = ({ icon, title, children }: { icon: ReactNode; title: string; children?: ReactNode }) => (
  <div className="fade-in flex h-full min-h-[300px] flex-col items-center justify-center gap-2 px-8 text-center">
    <div className="mb-1 text-muted">{icon}</div>
    <div className="text-[14px] font-semibold">{title}</div>
    {children && <div className="max-w-sm text-[12.5px] text-muted">{children}</div>}
  </div>
)

export const Kbd = ({ children }: { children: ReactNode }) => (
  <kbd className="rounded-[4px] border border-border bg-surface px-1 font-sans text-[10.5px] text-muted">{children}</kbd>
)
