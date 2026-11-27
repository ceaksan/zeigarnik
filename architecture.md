# Zeigarnik - Architecture

Native macOS app (window plus menubar extra) that shows, day by day, what is going on across a developer's git repositories: last activity by Claude Code, Codex or commit, uncommitted and unpushed work, README and architecture document drift, evidence-based spec progress, estimated time per project, repository visibility, and the owner's own notes, pins and scheduled follow-ups. A command-line scanner (`zeigarnik-scan`) shares the same core and database, and `zeigarnik` gives agents and the shell access to notes, with an MCP server (ADR-006).

<!--
Living Architecture Template v1.0
Source: https://github.com/ceaksan/living-architecture
Depth: L2
Last verified: 2026-11-19
-->

## Stack & Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Swift | 6 | Language (strict concurrency) |
| SwiftUI | macOS 14+ | Window, table, month grid, settings, menubar extra; `@Observable` state |
| AppKit | macOS 14+ | Search field focus, folder chooser, opening folders in other apps |
| GRDB.swift | 7.12+ | SQLite access and migrations (ADR-001) |
| EventKit | macOS 14+ | Scheduled items mirrored to macOS Calendar |
| ServiceManagement | macOS 14+ | Launch at login (`SMAppService`) |
| git | system, `/usr/bin/git` | Status, history, `git fetch` (the only ref-changing call) |
| gh | runtime, optional | Repository visibility for GitHub, including the user's private repositories |
| hc (herdr-core) | runtime, optional | "Open now" panes and the herdr open action |

### Infrastructure

| Layer | Technology | Detail |
|-------|-----------|--------|
| Build | SwiftPM + xcodegen | `swift build`/`swift test` for the package; `project.yml` generates `Zeigarnik.xcodeproj` (committed) for the app bundle (ADR-002) |
| Testing | Swift Testing | `@Test`, `#expect`; `ZeigarnikCoreTests`, `ZeigarnikKitTests` |
| Storage | SQLite (WAL) | `~/Library/Application Support/Zeigarnik/zeigarnik.sqlite`, shared by app and CLI |
| Settings | UserDefaults | `zeigarnik.settings` (JSON); table column layout in `projectTableColumns` |
| Distribution | GitHub Releases zip | `scripts/release.sh`: universal, signed with one self-signed `Zeigarnik Release` certificate, not notarized, not sandboxed; CLI in `Contents/Helpers` (ADR-007) |

## Module Map

```
zeigarnik/
├── Package.swift              # ZeigarnikCore, ZeigarnikKit, ZeigarnikUI, ZeigarnikAgent, zeigarnik-scan, zeigarnik
├── project.yml                # xcodegen app target (thin: @main + Info.plist keys)
├── App/ZeigarnikApp.swift     # @main, hands off to ZeigarnikScenes
├── Sources/
│   ├── ZeigarnikCore/         # No UI. Scanner, parsers, store; used by the app and the CLI
│   │   ├── Discovery/         # Repositories under roots; optional project table (CLAUDE.md in the first root)
│   │   ├── Git/               # Porcelain v2, history, README drift, architecture doc drift, remote URL sanitizing, visibility probe
│   │   ├── Activity/          # Claude/Codex history and transcript records, project mapping, time estimate, activity index
│   │   ├── Specs/             # Spec and plan discovery, task parsing, evidence, Active Tasks counts
│   │   ├── Live/              # "Open now" from hc
│   │   ├── Scan/              # ScanConfig, ProjectScanner (one scan), ScanLog (local unified log), RowFormatter for the CLI
│   │   ├── Store/             # Schema (migrations v1 to v7), Store reads and writes, identity, owner data, note drafts
│   │   └── Support/           # ProcessRunner (own process group, timeouts, no shell), AppPaths
│   ├── ZeigarnikKit/          # App logic without SwiftUI, tested with swift test
│   │   ├── Model/             # AppModel (@Observable), AppSettings, settings effects, open targets, herdr open, menubar summary
│   │   ├── Scan/              # ScanCoordinator (one scan at a time, timer), source health
│   │   ├── List/              # Filters, search, sort, folder labels
│   │   ├── Calendar/          # CalendarSync (pending operations), EventKit gateway, month grid
│   │   └── Format/            # Display strings, cached date formatters
│   ├── ZeigarnikUI/           # SwiftUI views; AppEnvironment is the composition root
│   │   ├── Window/, List/, Calendar/, Inspector/, Sheets/, Menubar/, Settings/, Welcome/
│   │   ├── Support/           # About links, folder chooser, open buttons, search focus
│   │   └── Theme/             # Colors, components
│   ├── ZeigarnikAgent/        # Notes, projects and drafts for the shell and agents; hand-written stdio MCP server
│   ├── ZeigarnikScan/main.swift  # CLI: --root (required), --vault, --db, --no-fetch, --json
│   └── ZeigarnikCLI/main.swift   # `zeigarnik`: projects, status, notes list|show|add|edit|delete, drafts, mcp
├── Tests/ZeigarnikCoreTests/  # Parsers, store, scanner end to end (fake runner), synthetic fixtures
├── Tests/ZeigarnikKitTests/   # Model, filters, settings, coordinator, calendar sync, formatting
├── Tests/ZeigarnikAgentTests/ # Notes service, project and note resolution, MCP protocol
└── docs/adr/                  # Architecture decision records
```

**Key responsibilities per module:**

- `ZeigarnikCore/Scan/Scanner.swift`: one scan, in order: project table, discovery, identity, per-project facts (bounded concurrency, optional fetch), activity ingest, open now, repository visibility. Errors are collected per project into the `ScanReport`, never thrown away.
- `ZeigarnikCore/Scan/ScanLog.swift`: at scanner completion, emits each report error once and one info summary (projects, errors, duration) to macOS unified logging. One logger uses subsystem `com.ceaksan.zeigarnik`, category `scan`, for both app and CLI scans. Folder names and scrubbed messages are public, full paths private. Logging is local only; macOS controls retention, with no database error history or custom log files (ADR-008).
- `ZeigarnikCore/Git/FetchFailure.swift`: scrubs URL userinfo in diagnostic prose and classifies known HTTPS/SSH authentication failures. The scanner stores friendly messages with scrubbed git details; `; ` inside an individual fetch error becomes `, ` so the inspector's message delimiter remains unambiguous.
- `ZeigarnikCore/Store`: the only place that talks SQL. Owns migrations, so the app and the CLI always share one schema.
- `ZeigarnikKit/Model/AppModel.swift`: everything a view reads or changes goes through it. Store reads run off the main actor; a failed reload keeps the last rows and sets `loadError`.
- `ZeigarnikKit/Scan/ScanCoordinator.swift`: scans on launch, every `scanInterval`, and on request; requests during a scan collapse into one follow-up.
- `ZeigarnikUI/AppEnvironment.swift`: builds store, scanner, coordinator, calendar sync and model; applies settings changes (rescan, reload, timer, calendar, login item); polls for writes from other connections every 2 seconds.
- `ZeigarnikAgent`: the only way outside the app to change notes. The MCP server exposes no delete (ADR-006).

## Data Flow

**Flow 1 - Scan:**

```
ScanCoordinator (launch, timer, ⌘R, settings change)
  --> ProjectScanner.scan(fetch:)
      --> roots + optional project table --> repositories
      --> identity: stable project id across moves (root commits, remotes, path)
      --> per project (bounded): git status, git fetch (optional), history, README / architecture drift, specs, Active Tasks
      --> agent logs: ~/.claude, ~/.codex (append-only reads with file cursors; only agent, session id, timestamp, cwd, source)
      --> hc ls --json: panes open now
      --> visibility: gh repo view, else GitHub/GitLab public API (once a day per repo after a clear answer; unknown is asked again next scan)
      --> Store (one transaction per batch)
  <-- ScanReport (counts, per-project errors, open now)
      --> AppModel.reload(): rows, activity index, source problems
```

**Flow 2 - Owner data:**

```
Note / pin / schedule / spec override in the UI
  --> AppModel (validates: empty text, project required)
    --> Store (owner tables)
    --> scheduled items: calendarOp queue --> CalendarSync.reconcile --> EventKit
        (event carries the item UUID; reconcile reads changes made in Calendar back)
```

## Data Model

| Table | Purpose |
|-------|---------|
| project, projectIdentity, projectPath | Stable project ids, identity evidence, known paths, project-table source (ADR-004) |
| snapshot | Latest per-project facts: git status, README, architecture doc, summary, error |
| ownerMessage, session, codexSession, fileCursor | Agent activity: timestamps only, never message text |
| commitDay | Commits per project per day |
| specEvidence, specOverride | Spec progress evidence and the owner's manual overrides |
| note, scheduledItem, calendarOp | Owner notes, scheduled follow-ups, pending calendar operations |
| noteDraftDismissal | Dismissed or accepted draft kinds per project, held until the kind clears; drafts themselves are computed (ADR-006) |
| repoVisibility | public / private / unknown with check time |

Time estimate: messages of one session closer together than the activity gap (default 15 minutes) form an interval; per project, intervals are unioned, so parallel sessions count once. Totals are computed when rows load, so a gap change needs no rescan.

## Configuration & Environment

| Setting | Default | Effect |
|---------|---------|--------|
| Folders (roots) | none | Repositories scanned; first root may hold an optional project table (`CLAUDE.md`) |
| Vault | none | Optional Obsidian vault for Active Tasks counts |
| Target calendar | none | Calendar for scheduled items |
| Terminal, Editor | first installed | Open actions |
| Checks | README, architecture, visibility on | Hide the column, filter and inspector line; visibility off stops its network calls |
| Scan Every | 2 hours | 1, 2, 4 or 8 |
| Activity Gap | 15 minutes | 5, 10, 15, 20 or 30 |

The CLI takes the same paths as flags and runs without the visibility probe. `zeigarnik` reads the app's README and architecture switches and activity gap from the app's preferences, so its drafts match the app's.

## Security

- Read-only toward repositories: `git fetch` is the only ref-changing git command; every git call uses `/usr/bin/git`, `GIT_TERMINAL_PROMPT=0`, a non-interactive SSH command and a timeout.
- Agent logs: only agent, session id, timestamp, cwd and source are stored; never prompt or message text.
- Remote URLs pass through `sanitizeRemoteURL` before storage, so embedded credentials are never persisted.
- Failed fetch outcomes pass through `scrubDiagnosticCredentials` before snapshot storage; all unified-log error messages pass through it before public emission. Other stored scan errors retain their existing handling. No new network effects are introduced by diagnostics (ADR-008).
- Network: `git fetch`, and with the visibility check on, one request per repository per day to `gh` or the GitHub/GitLab public API (unauthenticated, `User-Agent: Zeigarnik`). No telemetry.
- `zeigarnik mcp` speaks only over standard input and output, opens no port, and offers no delete tool.
- Processes run without a shell (`ProcessRunner`), each in its own process group with a timeout, so a timeout also ends helpers such as `git-remote-https` (ADR-005). Git runs with `GIT_ASKPASS` and `SSH_ASKPASS` cleared.

## Constraints & Trade-offs

- Not sandboxed: the app reads arbitrary repository folders and the agents' log folders. TCC still asks for Documents, iCloud Drive and Calendars; each degrades visibly when denied.
- Unsigned or ad-hoc signed local builds change identity on every rebuild, so macOS asks for permissions again; signing with a development certificate keeps them.
- `searchFocused` needs macOS 15; on macOS 14 the Find command focuses the toolbar search field through AppKit.
- SwiftUI `Table` allows 10 columns; the table is at 10.
- A first scan reads every agent log once. Parsing goes through Foundation, so each 16 MB batch drains its own autorelease pool; without it memory grew with the total log size (several GB on a busy machine), with it a first scan stays under 0.5 GB.

## Known Tech Debt

- A manifest change that is only a version bump still counts as architecture drift. README drift compares dependency lists for `Package.swift`, `package.json`, `pyproject.toml` and `Cargo.toml`; other formats keep the whole-file rule.
- Owner-data writes (notes, pins, schedules) run on the main actor; they are single-row SQLite writes. `displayName` falls back to the project id when the read fails.
- Views are verified by running the app, not by UI tests.

## Code Hotspots

| File | Why |
|------|-----|
| `Sources/ZeigarnikCore/Scan/Scanner.swift` | Orchestrates every scan step; most integration defects show up here |
| `Sources/ZeigarnikCore/Store/Store.swift` | All SQL, migrations meet queries here |
| `Sources/ZeigarnikKit/Model/AppModel.swift` | Every view's state and action |
| `Sources/ZeigarnikKit/Calendar/CalendarSync.swift` | Two-way reconciliation with EventKit |

### Dependency Graph

```
App --> ZeigarnikUI --> ZeigarnikKit --> ZeigarnikCore --> GRDB
zeigarnik-scan -------------------------> ZeigarnikCore
zeigarnik --> ZeigarnikAgent -----------> ZeigarnikCore
```
