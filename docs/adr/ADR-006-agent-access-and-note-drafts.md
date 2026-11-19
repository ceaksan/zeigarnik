# ADR-006: Agent access to notes (CLI and MCP) and note drafts from project state

**Date:** 2026-11-19
**Status:** Accepted

## Context

Notes live only inside the app. The owner wants to talk about them with a coding agent ("bring my notes and let's discuss them"), which needs a way for the agent to list, read, add and edit notes outside the app. Separately, several project columns already describe follow-up work (README behind, architecture document behind, unpushed commits, uncommitted changes); the owner wants these offered as note drafts that become notes only when approved.

## Decision

### Command-line tool and MCP server

- A new executable `zeigarnik` (target `ZeigarnikCLI`) on top of a new library `ZeigarnikAgent`, which depends on `ZeigarnikCore` only. `zeigarnik-scan` is unchanged.
- Commands: `projects`, `notes list | show | add | edit | delete`, `drafts`, `mcp`. Every read command takes `--json`; `--db` selects the database. Projects are named by id, display name or path; notes by id or a unique id prefix of at least 4 characters.
- `zeigarnik mcp` is a stdio MCP server: newline-delimited JSON-RPC 2.0 with `initialize`, `ping`, `tools/list` and `tools/call`. Tools: `list_projects`, `project_status`, `list_notes`, `get_note`, `add_note`, `update_note`, `list_note_drafts`. There is no delete tool: an agent may read, add and edit notes, never remove them; deletion stays in the app and the CLI.
- The protocol is written by hand (about 200 lines), not taken from the Swift MCP SDK. Three methods and one transport do not justify a new dependency tree; this can be revisited if the server needs resources, prompts or another transport.
- The tool opens the same SQLite database as the app (WAL, busy timeout 5 seconds) and refuses to create one: without the app's database it exits with an error.

### Note drafts

- A draft is computed, never stored: `noteDrafts(for:checks:)` turns a project row into at most one draft per kind (`readme`, `architecture`, `push`, `uncommitted`). Missing projects have none. README and architecture drafts follow the app's check settings.
- Migration `v7-note-draft` adds `noteDraftDismissal (projectId, kind, fingerprint, dismissedAt)`, one row per project and kind. The fingerprint (for example `behind:6` for a README six commits behind) records the state at dismissal for reference only.
- A dismissal holds for the kind, not the exact state: a README that goes from 6 to 9 commits behind, or an uncommitted-changes count that moves, does not bring the draft back. When a kind has no draft for a project any more (the state cleared), its dismissal is removed, so the state coming back later shows the draft again. Every reload (one follows each scan) does this for all projects, not only the one on screen. The card names its kind (README, Architecture, Push, Uncommitted).
- Changed in 0.2.1: 0.2.0 compared fingerprints, so every count change brought a dismissed draft back and accepting the same uncommitted-changes draft twice produced duplicate notes.
- Accepting a draft opens it in the note editor; saving adds a note dated today and dismisses the draft in one transaction, so the accepted state does not offer the same draft again.

### External changes

- The app polls `PRAGMA data_version` every 2 seconds off the main actor. The value changes only when another connection commits, so writes by the CLI, an agent or `zeigarnik-scan` reload the rows and open details, while the app's own writes do not trigger a second reload.

## Consequences

### Positive
- An agent can work with the owner's notes directly, without the app in front.
- Follow-up work visible in the columns turns into notes with one confirmation, and declined drafts stay out of the way until something changes.
- Changes made outside the app appear within seconds without a restart.

### Negative
- A second executable to build and install (`~/.local/bin/zeigarnik`), and a hand-written protocol to keep in step with MCP revisions.
- A dismissed draft stays hidden while its kind lasts, even when the state gets worse (more commits behind, more files changed); the column still shows the current numbers.
- A 2-second timer runs for the life of the app (one pragma read per tick).

### Alternatives Considered
- Swift MCP SDK: protocol upkeep for free, but a new dependency and its transitive packages for three methods.
- An MCP delete tool: rejected by the owner; agents must not remove notes.
- Storing drafts as rows: would need a sync step on every scan and leaves stale drafts behind when a state clears.
- Watching the WAL file instead of polling: the app's own writes trigger it too, and checkpoints rewrite the file.

## Files Changed

| File | Change |
|------|--------|
| `Package.swift` | `ZeigarnikAgent` library, `zeigarnik` executable, `ZeigarnikAgentTests` |
| `Sources/ZeigarnikCore/Store/Schema.swift` | Migration `v7-note-draft` |
| `Sources/ZeigarnikCore/Store/NoteDrafts.swift` | Draft computation, dismissal, acceptance |
| `Sources/ZeigarnikCore/Store/OwnerData.swift` | Shared note insert for drafts |
| `Sources/ZeigarnikCore/Store/StoreReads.swift` | Project refs, note lookups by filter and id prefix, note counts, `dataVersion` |
| `Sources/ZeigarnikAgent/` | Notes service, project resolution, MCP server |
| `Sources/ZeigarnikCLI/main.swift` | `zeigarnik` command |
| `Sources/ZeigarnikKit/Model/AppModel.swift` | Drafts in project detail, accept and dismiss, external change poll |
| `Sources/ZeigarnikUI/Inspector/ProjectInspector.swift` | Draft cards above the notes |
| `Sources/ZeigarnikUI/AppEnvironment.swift` | Poll loop |
