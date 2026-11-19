# Zeigarnik - Project Instructions

## Stack
- Swift 6 (strict concurrency), Swift Package Manager, Swift Testing (`@Test`, `#expect`)
- GRDB.swift 7.12+ (ADR-001), macOS 14+
- App: SwiftPM libraries plus a thin xcodegen app target (ADR-002); module map in `architecture.md`

## Commands
- Test: `swift test` (filter: `swift test --filter <Suite>`)
- CLI: `swift run zeigarnik-scan --root <folder> --no-fetch` (`--root` is required, repeatable; `--vault`, `--db`, `--json`)
- Notes CLI and MCP: `swift run zeigarnik --db <copy> notes list` (`projects`, `status`, `notes list|show|add|edit|delete`, `drafts`, `mcp`). Try it on a copy of a database, never on the owner's.
- Release: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in project.yml and `zeigarnikVersion` in `Sources/ZeigarnikAgent/AgentService.swift` together.
- App: `xcodegen generate` after adding or removing files, then `xcodebuild -project Zeigarnik.xcodeproj -scheme Zeigarnik -configuration Release -derivedDataPath build build`
- Debug app on a separate data set (screenshots, trials): build Debug with its own `PRODUCT_BUNDLE_IDENTIFIER`, launch with `--home <absolute dir>` (database, `.claude`, `.codex` come from there) and `--settings-json '<AppSettings JSON>'` for roots.
- Builds run one at a time and only with the owner's approval.

## Rules
- Architecture: `architecture.md`; decisions: `docs/adr/`. Design specs and plans, when present, live in `docs/superpowers/` (kept out of the public repository).
- Git: the only ref-changing command is `git fetch`. Every git call uses `/usr/bin/git`, `GIT_TERMINAL_PROMPT=0`, `GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=10`, and a timeout.
- Never persist message text, prompt text or pasted content from agent logs; only agent, session id, timestamp, cwd, source.
- Never persist credentials: remote URLs pass through `sanitizeRemoteURL`.
- Network access is `git fetch` and the optional visibility check only (ADR-003); no telemetry.
- Fixtures are synthetic, shaped like real records; no real prompt text, names or paths of real people or projects.
- Product rules must hold for any user on a fresh install; nothing may depend on the owner's folders, tools or data.
