# Notes for coding agents

- The Swift package builds and tests on macOS 15 or later only. The web
  workspace under `web/` builds and tests on any OS.
- Before finishing a change, run `npm run typecheck` and `npm test` in `web/`,
  and `scripts/test.sh` on a Mac when Swift code or the bridge contract changed.
- The bridge contract lives in `web/packages/core/src/contract.ts` and is
  mirrored by the DTOs in `Sources/BridgeKit/BridgeDTO.swift`. Change both
  together and regenerate the fixtures with `npm run fixtures -w @nr/core`.
- Do not edit generated files by hand: `Sources/LiveUI/Theme.generated.swift`
  and `web/apps/library/src/theme.css` come from `theme/notch-dark.json`
  through `npm run theme`.
- Interface text is plain and professional. No emojis and no em dashes in
  code, comments, documentation or commit messages.
- Never commit recordings, databases, model files or credentials.
