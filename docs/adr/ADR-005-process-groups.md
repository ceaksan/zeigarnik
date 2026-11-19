# ADR-005: Spawn commands in their own process group

**Date:** 2026-11-19
**Status:** Accepted

## Context

`ProcessRunner` started commands with Foundation's `Process` and, on a timeout, sent SIGTERM and then SIGKILL to that one process. A hung `git fetch` is mostly its helpers (`git-remote-https`, `ssh`), which kept running after `git` itself was killed. Git could also inherit `GIT_ASKPASS` or `SSH_ASKPASS` from the app's environment and wait on a password dialog that the timeout then had to break.

## Decision

- Commands start through `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, so each runs in a new process group created atomically with the process (a parent-side `setpgid` races with `exec`). Standard input is `/dev/null`; descriptors other than the two output pipes close on exec.
- The runner detects the command's exit with `waitid(..., WNOWAIT)`, leaving it unreaped. While it is unreaped its pid cannot be reused, so signalling the group is safe:
  - On a timeout: SIGTERM to the group, then SIGKILL; the result is `timedOut` with no exit code.
  - After a normal exit: SIGKILL to the group, since helpers left in it are orphans; the output wait is then bounded (5 seconds), because a helper in another session (for example an ssh ControlPersist master) can keep a pipe open. The command's own exit code is kept.
- Every git call clears `GIT_ASKPASS` and `SSH_ASKPASS`, next to the existing `GIT_TERMINAL_PROMPT=0` and BatchMode SSH command.

## Consequences

### Positive
- A timeout ends the whole command tree, not just its first process.
- A finished command keeps its exit code even when a helper outlives it.
- No password prompt can appear from a background scan.

### Negative
- More low-level code than `Process` (spawn attributes, file actions, wait status decoding).
- The runner polls for exit every 10 ms on its own thread instead of using a termination handler.

### Alternatives Considered
- `Process` plus `setpgid` from the parent: races with the child's `exec`.
- Killing only known helper names: incomplete and platform-dependent.

## Files Changed

| File | Change |
|------|--------|
| `Sources/ZeigarnikCore/Support/ProcessRunner.swift` | `posix_spawn` with a new process group; exit detection without reaping; group signals |
| `Sources/ZeigarnikCore/Git/GitInspector.swift` | `GIT_ASKPASS` and `SSH_ASKPASS` cleared |
| `Tests/ZeigarnikCoreTests/ProcessRunnerTests.swift` | Helpers outliving the command keep the exit code |
| `Tests/ZeigarnikCoreTests/GitProcessSafetyTests.swift` | Askpass cleared on every git operation; fetch timeout ends helpers |
