import { ManagedRuntime } from "effect"
import { BridgeLive, hasNativeBridge } from "./services/Bridge.ts"
import { BridgeFake } from "./services/FakeBridge.ts"

/** One runtime for the page: the real bridge inside the app, a fake in a browser. */
export const runtime = ManagedRuntime.make(hasNativeBridge() ? BridgeLive : BridgeFake)
export type AppRuntime = typeof runtime
