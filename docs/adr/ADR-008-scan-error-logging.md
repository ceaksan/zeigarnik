# ADR-008: Local scan diagnostics and fetch authentication errors

**Date:** 2026-11-27
**Status:** Accepted

## Context

Scan errors are visible in the project inspector but there is no diagnostic record of completed scans. Raw git authentication failures do not explain how to resolve the problem and can include credentials in URL userinfo. The owner chose macOS unified logging without database error history.

## Decision

- Log at the single completion point in `ProjectScanner.scan`, covering app scans and `zeigarnik-scan`. Each completed invocation emits each report error once, followed by one info summary containing project count, error count and duration in seconds. A later scan emits its own diagnostics even if the errors are unchanged.
- Use one `os.Logger`, subsystem `com.ceaksan.zeigarnik` from `project.yml`, category `scan`. Error records expose the project folder name and scrubbed message publicly; the full project path is private. Errors without a project use the public label `scan` and an empty private path.
- Redact URL userinfo in diagnostic prose before public logging. The existing `sanitizeRemoteURL` handles standalone remotes, not URLs embedded in prose, so a separate pure helper replaces userinfo with `<redacted>`. Scrub failed fetch text before storing its outcome too.
- Classify known HTTPS and SSH authentication failures in ZeigarnikCore. Append scrubbed git text to recognized messages. Preserve other errors except credential scrubbing and replacing `; ` with `, `, because `; ` separates distinct errors in the inspector.
- Keep logging local, with no telemetry or new network access, consistent with [ADR-003](ADR-003-external-calls.md). Do not add a history table, migration or custom log files. macOS controls unified log retention and visibility.
- Keep the log output boundary injectable for tests. Exercise logging through the real scanner with synthetic command failures and a recording sink, without reading or changing system logs.

## Consequences

### Positive
- App and CLI scans share diagnostic output and authentication guidance.
- URL credentials are removed before public logging and failed-fetch persistence.
- No new dependencies, database schema or background services are required.

### Negative
- Unified logs are not a durable error history; info visibility and retention depend on macOS logging settings.
- Folder names and scrubbed diagnostic messages are public in local logs by owner choice.
- Classification recognizes specific git phrases; unfamiliar failures keep their original text.

### Alternatives Considered
- Error history in the database: rejected by the owner, adds persistence and retention management for diagnostic data.
- Logging in `ScanCoordinator.finish`: rejected because the scanner CLI does not use the coordinator.
- Reusing `sanitizeRemoteURL` directly on stderr: rejected because stderr can contain surrounding prose and multiple URLs.

## Files Changed

| File | Change |
|------|--------|
| `Sources/ZeigarnikCore/Scan/ScanLog.swift` | Unified logging and injectable output boundary |
| `Sources/ZeigarnikCore/Scan/Scanner.swift` | Log completed reports and classify fetch failures |
| `Sources/ZeigarnikCore/Git/FetchFailure.swift` | Pure credential scrubber and authentication classifier |
| `Sources/ZeigarnikCore/Git/GitInspector.swift` | Scrub failed fetch outcomes before persistence |
| `Tests/ZeigarnikCoreTests/FetchFailureTests.swift` | Synthetic credential and classifier cases |
| `Tests/ZeigarnikCoreTests/ScannerTests.swift` | Real scanner entry-point diagnostic and fetch coverage |
| `architecture.md` | Local logging effects and credential handling |
