# Zeigarnik

Zeigarnik is a macOS app that shows, day by day, what is going on across your git repositories: when you last worked on each one with Claude Code, Codex or a commit, what is uncommitted or unpushed, whether the README or architecture document has fallen behind the code, how far each spec or plan really got, roughly how much time each project took, and whether the repository is public or private. You can pin projects, write notes against a project or a day, and schedule follow-ups that also land in macOS Calendar.

Named after the Zeigarnik effect: unfinished tasks are remembered better than finished ones.

## Features

- **Project list** with last activity (agent or commit), last commit, dirty files, push state, README drift, visibility, estimated total time and spec progress. Columns can be hidden or shown from the header's context menu.
- **Sidebar filters**: pinned, open now, uncommitted, push or upstream problems, README or architecture behind, public, quiet for 30+ days, folders, missing.
- **Calendar view**: a month grid of activity, notes and scheduled items per day.
- **Project and day inspectors**: facts, 14-day activity, spec tasks with evidence, notes and schedules. Notes can be edited or deleted from the icons under each note.
- **Note drafts**: a README or architecture document behind, unpushed commits or uncommitted changes show up as a draft above the project's notes. Accept opens it in the editor and adds it as today's note; dismiss hides that kind of draft for the project until the state is resolved.
- **Notes for agents**: the `zeigarnik` command and its MCP server let Claude Code, Codex or another agent list, read, add and edit your notes. Agents cannot delete notes.
- **Menubar extra**: today's attention items and quick actions.
- **Open in**: Finder, your terminal or editor, and herdr when installed.

## Install

Download `Zeigarnik-<version>-macos.zip` from [Releases](https://github.com/ceaksan/zeigarnik/releases/latest), unzip it and move `Zeigarnik.app` to `/Applications`. It needs macOS 14 or later, runs on Apple Silicon and Intel, and carries the `zeigarnik` command-line tool inside.

The app is signed but not notarized, so macOS blocks the first launch. Open it once, then choose Open Anyway in System Settings > Privacy & Security. Or clear the download flag before opening it:

```bash
xattr -dr com.apple.quarantine /Applications/Zeigarnik.app
```

On first launch a welcome window asks for the folders that hold your repositories. Zeigarnik reads only git repositories inside the folders you choose.

macOS asks for access to your Documents folder, to iCloud Drive if your folders or vault live there, and to Calendars when you turn on scheduling. Each feature degrades visibly when access is denied. Every release is signed with the same certificate, so macOS keeps these answers across updates.

## Build from source

Requirements: macOS 14 or later, Xcode 16 or later (Swift 6), and [xcodegen](https://github.com/yonaskolb/XcodeGen) to regenerate the project after adding or removing files.

```bash
git clone https://github.com/ceaksan/zeigarnik.git
cd zeigarnik
open Zeigarnik.xcodeproj   # choose the Zeigarnik scheme, then Run
```

Or from the command line:

```bash
xcodebuild -project Zeigarnik.xcodeproj -scheme Zeigarnik -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Zeigarnik.app
```

If you sign the build with your own development certificate, macOS remembers its permission answers across rebuilds; an unsigned or ad-hoc signed build asks again after each rebuild.

`scripts/release.sh` builds the release zip: a universal app with the command-line tool in `Contents/Helpers`, signed with the identity in `ZEIGARNIK_SIGN_IDENTITY` (default `Zeigarnik Release`, a self-signed code-signing certificate).

## Tests

```bash
swift test
```

The scanner, store, parsers and app logic live in Swift packages (`ZeigarnikCore`, `ZeigarnikKit`) and are tested without building the app. See `architecture.md` for the module map.

## Optional integrations

None of these are required; Zeigarnik uses what it finds.

- **Claude Code and Codex**: activity and time come from `~/.claude` and `~/.codex`. If you do not use one of them, nothing is shown for it.
- **Project table**: a Markdown table in `CLAUDE.md` at the top of your first folder can name projects and point to directories outside your folders.
- **Numbered folders**: subfolders named like `01_Core`, `02_Products` become sidebar folder groups.
- **Specs and plans**: design specs and implementation plans (for example under `docs/superpowers/` or OpenSpec) are read for task progress, with evidence from paths and commits.
- **Obsidian vault**: point Settings at a vault to show open Active Tasks counts per project.
- **herdr**: with `hc` installed, projects open in a herdr pane are marked live and can be opened in herdr.
- **gh**: with the GitHub CLI installed and signed in, repository visibility also works for your private repositories.

## Privacy

- Everything stays on your Mac, in `~/Library/Application Support/Zeigarnik/`.
- From agent logs only the agent, session id, timestamp, working directory and source are stored, never prompt or message text.
- Credentials in remote URLs are stripped before anything is stored.
- Network access: `git fetch`, and, while the visibility check is on, one question per repository to GitHub or GitLab (through `gh` when installed): once a day after a clear answer, and again on each scan while the answer is unknown, for example after a rate limit. No telemetry. Turn the visibility check off in Settings > Checks.

## Command-line scanner

The same scanner runs without the app and writes to the same database:

```bash
swift run zeigarnik-scan --root ~/Projects --no-fetch
swift run zeigarnik-scan --root ~/Projects --vault ~/Vault --json
```

`--root` is required and may be repeated. `--db` points at another database file.

## Notes from the command line and from agents

`zeigarnik` reads and writes the app's notes in the same database. The app ships it; put it on your PATH once:

```bash
ln -s /Applications/Zeigarnik.app/Contents/Helpers/zeigarnik ~/.local/bin/zeigarnik
```

Built from source instead:

```bash
swift build -c release --product zeigarnik
cp .build/release/zeigarnik ~/.local/bin/
```

```bash
zeigarnik projects                          # projects with push state, uncommitted files, README, notes, drafts
zeigarnik status <project>                  # one project: state, recent notes, open drafts
zeigarnik notes list --project <project> --since 2026-11-01
zeigarnik notes add --project <project> "Release after the review"
zeigarnik notes edit <id> "New text"        # <id>: a note id or a unique prefix of 4+ characters
zeigarnik notes delete <id>
zeigarnik drafts
```

A project is named by its id, display name or path. Every read command takes `--json`.

`zeigarnik mcp` runs an MCP server on standard input and output with the tools `list_projects`, `project_status`, `list_notes`, `get_note`, `add_note`, `update_note` and `list_note_drafts`. There is no delete tool. To add it to Claude Code:

```bash
claude mcp add zeigarnik -- ~/.local/bin/zeigarnik mcp
```

The app notices changes made this way within two seconds.

## License

MIT, see `LICENSE`.
