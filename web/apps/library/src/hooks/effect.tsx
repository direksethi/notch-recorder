import type { AppError, BridgeEvent } from "@nr/core"
import { userMessage } from "@nr/core"
import { Cause, Effect, Exit } from "effect"
import { createContext, type ReactNode, useCallback, useContext, useEffect, useRef, useState } from "react"
import type { AppRuntime } from "../runtime.ts"
import { Bridge } from "../services/Bridge.ts"

const RuntimeContext = createContext<AppRuntime | null>(null)

export const RuntimeProvider = ({ runtime, children }: { runtime: AppRuntime; children: ReactNode }) => (
  <RuntimeContext.Provider value={runtime}>{children}</RuntimeContext.Provider>
)

export const useRuntime = (): AppRuntime => {
  const r = useContext(RuntimeContext)
  if (!r) throw new Error("RuntimeProvider missing")
  return r
}

export type Query<A> =
  | { readonly _tag: "Loading" }
  | { readonly _tag: "Success"; readonly value: A }
  | { readonly _tag: "Failure"; readonly error: AppError }

export const failureOf = (exit: Exit.Exit<unknown, AppError>): AppError | undefined => {
  if (Exit.isSuccess(exit)) return undefined
  return Cause.squash(exit.cause) as AppError
}

/**
 * Runs an Effect and keeps its latest result. Re-runs when `deps` change.
 * Keeps showing the previous value while refreshing so lists never flash.
 */
export const useQuery = <A,>(make: () => Effect.Effect<A, AppError, Bridge>, deps: ReadonlyArray<unknown>) => {
  const runtime = useRuntime()
  const [state, setState] = useState<Query<A>>({ _tag: "Loading" })
  const [tick, setTick] = useState(0)
  const makeRef = useRef(make)
  makeRef.current = make
  useEffect(() => {
    let live = true
    runtime.runPromiseExit(makeRef.current()).then((exit) => {
      if (!live) return
      if (Exit.isSuccess(exit)) setState({ _tag: "Success", value: exit.value })
      else setState({ _tag: "Failure", error: failureOf(exit)! })
    })
    return () => {
      live = false
    }
  }, [runtime, tick, ...deps])
  const refresh = useCallback(() => setTick((t) => t + 1), [])
  return [state, refresh] as const
}

/** Runs one-off commands; failures become a toast. */
export const useRun = () => {
  const runtime = useRuntime()
  const toast = useToast()
  return useCallback(
    async <A,>(effect: Effect.Effect<A, AppError, Bridge>): Promise<A | undefined> => {
      const exit = await runtime.runPromiseExit(effect)
      if (Exit.isSuccess(exit)) return exit.value
      const error = failureOf(exit)
      if (error && !(error._tag === "NativeError" && error.code === "Cancelled")) toast.error(userMessage(error))
      return undefined
    },
    [runtime, toast],
  )
}

/** Listens to native events while mounted. */
export const useBridgeEvents = (listener: (event: BridgeEvent) => void) => {
  const runtime = useRuntime()
  const ref = useRef(listener)
  ref.current = listener
  useEffect(() => {
    let unsubscribe: (() => void) | undefined
    runtime
      .runPromise(
        Effect.gen(function* () {
          const bridge = yield* Bridge
          return yield* bridge.subscribe((e) => ref.current(e))
        }),
      )
      .then((u) => {
        unsubscribe = u
      })
    return () => unsubscribe?.()
  }, [runtime])
}

// Toasts

export interface Toast {
  readonly id: number
  readonly kind: "info" | "error"
  readonly text: string
}

interface ToastApi {
  readonly info: (text: string) => void
  readonly error: (text: string) => void
}

const ToastContext = createContext<ToastApi>({ info: () => {}, error: () => {} })
export const useToast = () => useContext(ToastContext)

export const ToastProvider = ({ children }: { children: ReactNode }) => {
  const [toasts, setToasts] = useState<Array<Toast>>([])
  const next = useRef(1)
  const push = useCallback((kind: Toast["kind"], text: string) => {
    const id = next.current++
    setToasts((t) => [...t.slice(-2), { id, kind, text }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), kind === "error" ? 6000 : 2400)
  }, [])
  const api = useRef<ToastApi>({ info: (t) => push("info", t), error: (t) => push("error", t) })
  api.current = { info: (t) => push("info", t), error: (t) => push("error", t) }
  const stable = useRef<ToastApi>({ info: (t) => api.current.info(t), error: (t) => api.current.error(t) })
  return (
    <ToastContext.Provider value={stable.current}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 bottom-5 z-50 flex flex-col items-center gap-2">
        {toasts.map((t) => (
          <div
            key={t.id}
            role="status"
            className={`toast-in pointer-events-auto max-w-md rounded-full border px-4 py-1.5 text-[12.5px] shadow-xl ${
              t.kind === "error"
                ? "border-error/40 bg-error-surface text-error-foreground"
                : "border-border bg-surface-raised text-text"
            }`}
          >
            {t.text}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  )
}
