import "./jsc-polyfills.ts"
import { Schema } from "effect"
import { ExportFormat, ExportInput } from "./contract.ts"
import { formatExport } from "./format.ts"

// Loaded into a JavaScriptCore context by the native app so transcript files
// written on save are formatted by exactly the same code as the Library.
const decodeInput = Schema.decodeUnknownSync(ExportInput)
const decodeFormat = Schema.decodeUnknownSync(ExportFormat)

;(globalThis as Record<string, unknown>).NotchCore = {
  formatExport: (json: string, format: string): string =>
    formatExport(decodeInput(JSON.parse(json)), decodeFormat(format)),
}
