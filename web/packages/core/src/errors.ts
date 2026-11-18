import { Data } from "effect"
import type { NativeErrorCode } from "./contract.ts"

/** The native bridge is not there (running outside the app) or the call itself failed. */
export class BridgeError extends Data.TaggedError("BridgeError")<{
  readonly method: string
  readonly message: string
}> {}

/** A value from the native side did not match the contract. */
export class DecodeError extends Data.TaggedError("DecodeError")<{
  readonly method: string
  readonly message: string
}> {}

/** The native side ran the call and reported a failure. */
export class NativeError extends Data.TaggedError("NativeError")<{
  readonly method: string
  readonly code: NativeErrorCode
  readonly message: string
  readonly detail?: string
}> {}

export type AppError = BridgeError | DecodeError | NativeError

/** Copy shown to the user for any error. */
export const userMessage = (error: AppError): string => {
  switch (error._tag) {
    case "NativeError":
      return error.message
    case "DecodeError":
      return "Couldn't read the response from Notch Recorder. Reopen the window to try again."
    case "BridgeError":
      return "Couldn't reach Notch Recorder. Reopen the window to try again."
  }
}
