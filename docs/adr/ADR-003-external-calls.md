# ADR-003: External tools and network access

**Date:** 2026-11-19
**Status:** Accepted

## Context

Zeigarnik is a local, read-mostly observer of the user's repositories. Several features need something outside the app: refreshing remote state, telling public from private repositories, knowing which projects are open in a terminal multiplexer, and opening a project in another app. Each outside call is a place where the app could hang, leak data, change the user's repositories or send something over the network the user did not expect. The rules for these calls are recorded here so new features follow them.

## Decision

- **Processes, never a shell.** Every external program runs through `ProcessRunner` with an absolute path, an argument array, the app's environment plus the variables each call sets, and a timeout. No `sh -c`, no user-provided strings in a command line.
- **git.** `/usr/bin/git` only, `GIT_TERMINAL_PROMPT=0`, `GIT_SSH_COMMAND=ssh -o BatchMode=yes -o ConnectTimeout=10`. `git fetch` is the only command that changes refs; everything else reads.
- **Repository visibility.** Parsed from `origin` (scp, ssh and https forms, GitLab subgroups; local and `file:` remotes are skipped).
  - github.com: `gh repo view <owner/name> --json visibility` first (5 s, prompts and update checks disabled), because it sees the user's own private repositories; when `gh` is missing or fails, an unauthenticated `GET https://api.github.com/repos/<owner/name>`.
  - gitlab.com: `GET https://gitlab.com/api/v4/projects/<encoded path>`; `gh` is never used.
  - 200 means public, 404 private, anything else (rate limit, error, timeout) unknown. Other hosts are unknown without a request.
  - Definite answers are cached for 24 hours; unknown is asked again on the next scan. At most 4 requests at a time, `User-Agent: Zeigarnik`, nothing else sent.
  - A Settings toggle (Checks > Repository visibility) turns the requests off. The CLI never makes them.
  - `gh` is looked up at `/opt/homebrew/bin/gh` and `/usr/local/bin/gh`, since an app launched from Finder has no shell `PATH`.
- **herdr.** `hc ls --json` (open-now state) and `hc run --bg --no-parent --cwd <path>` (open action), only when `hc` is executable at the configured path.
- **Open in other apps.** Through `NSWorkspace` with a bundle identifier from a fixed catalog of terminals and editors that declare folder support; only installed ones are offered.
- **No telemetry, no update checks, no other network access.**

## Consequences

### Positive
- The user can list every outside call from one document; the README privacy section and the welcome screen state the same.
- Hanging tools cannot stall a scan; a failed call becomes an unknown value or a per-project error in the scan report.

### Negative
- Without `gh`, private GitHub repositories show as private only because the API answers 404, which also happens for deleted or renamed repositories.
- Unauthenticated GitHub API calls share a 60-requests-per-hour limit per IP; large collections fill in over several scans.
- Hosts other than GitHub and GitLab never get a visibility value.

### Alternatives Considered
- Asking the user for a GitHub token: rejected, the app would store a credential, and `gh` already holds one securely.
- `git ls-remote` without credentials to test public access: rejected, it can trigger credential helpers and prompts, and SSH remotes say nothing about visibility.
- Running tools through the login shell to inherit `PATH`: rejected, slower and runs the user's shell startup files.

## Files Changed

| File | Change |
|------|--------|
| `Sources/ZeigarnikCore/Support/ProcessRunner.swift` | Process execution with timeouts, no shell |
| `Sources/ZeigarnikCore/Git/RepoVisibility.swift` | Remote parsing, `gh` and API probe |
| `Sources/ZeigarnikCore/Scan/Scanner.swift` | Visibility step with cache and concurrency limit |
| `Sources/ZeigarnikKit/Model/HerdrOpen.swift` | herdr open action |
| `Sources/ZeigarnikKit/Model/OpenTarget.swift` | Terminal and editor catalog |
| `Sources/ZeigarnikUI/AppEnvironment.swift` | `gh` lookup, probe wiring |
