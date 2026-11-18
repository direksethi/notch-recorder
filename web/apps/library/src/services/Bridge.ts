import {
  type AppError,
  BridgeError,
  BridgeEvent,
  BridgeReply,
  DecodeError,
  type MethodName,
  Methods,
  NativeError,
  type Params,
  type Result,
} from "@nr/core"
import { Context, Effect, Layer, Schema } from "effect"

/** Talks to the native app. Every call is decoded against the contract. */
export class Bridge extends Context.Service<
  Bridge,
  {
    readonly call: <M extends MethodName>(method: M, params: Params<M>) => Effect.Effect<Result<M>, AppError>
    /** Registers a listener for native events; returns an unsubscribe function. */
    readonly subscribe: (listener: (event: BridgeEvent) => void) => Effect.Effect<() => void>
  }
>()("Bridge") {}

type Transport = (method: string, params: unknown) => Promise<unknown>

interface WebKitWindow {
  webkit?: { messageHandlers?: { bridge?: { postMessage: (body: unknown) => Promise<unknown> } } }
  __nrEvent?: (event: unknown) => void
}

const decodeReply = Schema.decodeUnknownEffect(BridgeReply)

/** Builds a Bridge from any transport (WebKit in the app, a fake elsewhere). */
export const makeBridge = (
  transport: Transport,
  listen: (emit: (raw: unknown) => void) => void,
): Bridge["Service"] => {
  const listeners = new Set<(event: BridgeEvent) => void>()
  const decodeEvent = Schema.decodeUnknownSync(BridgeEvent)
  listen((raw) => {
    let event: BridgeEvent
    try {
      event = decodeEvent(raw)
    } catch (e) {
      console.error("bad event", raw, e)
      return
    }
    for (const l of listeners) l(event)
  })

  const call = <M extends MethodName>(method: M, params: Params<M>): Effect.Effect<Result<M>, AppError> =>
    Effect.gen(function* () {
      const raw = yield* Effect.tryPromise({
        try: () => transport(method, params),
        catch: (e) => new BridgeError({ method, message: String(e) }),
      })
      const reply = yield* decodeReply(raw).pipe(
        Effect.mapError((e) => new DecodeError({ method, message: String(e) })),
      )
      if (!reply.ok) {
        return yield* new NativeError({
          method,
          code: reply.error.code,
          message: reply.error.message,
          ...(reply.error.detail === undefined ? {} : { detail: reply.error.detail }),
        })
      }
      const resultSchema = Methods[method].result as unknown as Schema.Codec<Result<M>, unknown>
      return yield* Schema.decodeUnknownEffect(resultSchema)(reply.value).pipe(
        Effect.mapError((e) => new DecodeError({ method, message: String(e) })),
      )
    })

  return {
    call,
    subscribe: (listener) =>
      Effect.sync(() => {
        listeners.add(listener)
        return () => {
          listeners.delete(listener)
        }
      }),
  }
}

const webkitWindow = (): WebKitWindow => window as unknown as WebKitWindow

export const hasNativeBridge = (): boolean => webkitWindow().webkit?.messageHandlers?.bridge !== undefined

/** The real bridge inside the app's WKWebView. */
export const BridgeLive = Layer.sync(Bridge, () =>
  makeBridge(
    (method, params) => {
      const handler = webkitWindow().webkit?.messageHandlers?.bridge
      if (!handler) return Promise.reject(new Error("The native bridge is not available."))
      return handler.postMessage({ method, params })
    },
    (emit) => {
      webkitWindow().__nrEvent = emit
    },
  ),
)
