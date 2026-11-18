// Writes contract fixtures for the Swift BridgeKit tests, which decode them
// with the Swift DTO types to keep both sides of the bridge in step.
import { copyFileSync, writeFileSync } from "node:fs"
import { formatExport } from "../src/format.ts"
import { detail } from "./fixtures.ts"

const out = new URL("../../../../Tests/BridgeKitTests/Fixtures/", import.meta.url)
writeFileSync(new URL("detail.json", out), JSON.stringify(detail, null, 2))
writeFileSync(new URL("detail.srt", out), formatExport(detail, "srt"))
copyFileSync(new URL("../dist/core.jsc.js", import.meta.url), new URL("core.jsc.js", out))
console.log("fixtures written")
