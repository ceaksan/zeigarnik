# ADR-009: Apply spec marks when reading inspector evidence

**Date:** 2026-11-28
**Status:** Accepted

## Context

Mark Done persisted an override and requested a scan, but the inspector read the previous scan's JSON and displayed every spec, including completed specs. The owner requested that completed items leave the open list. Cached override states also made Reset depend on another scan. Owner-data failures reached a banner but had no unified log output.

## Decision

Store unmarked evidence during scans. Apply the current override by project id and spec path in the inspector's single joined database read. The scan headline still includes the overrides captured for that scan. Ordinary Markdown stages are recomputed from their cached evidence and declared status, which also handles older caches containing an applied override. Shared task notes retain checkbox counts in the existing evidence payload.

The inspector hides Done specs by default. Show Completed exposes the full list, including Reset and Mark Not Done. No records are deleted. Mark writes still request a scan without fetch to refresh project headlines.

Use the existing owner-data failure boundary to emit unified log errors under subsystem `com.ceaksan.zeigarnik`, category `owner-data`. Emit only the operation, NSError domain and numeric code. Do not log SQL, bound arguments, note text or raw exception descriptions. Corrupt spec JSON now throws into that boundary instead of silently disappearing. Override read failures during scans use the existing scan report and logger.

## Consequences

### Positive

Saved marks affect the inspector without waiting for git or activity scanning. Completed items remain recoverable. Existing SQLite transactions, schema, dependencies and local logging provide the implementation.

### Negative

Project headline refresh still waits for the requested scan. Legacy shared-note and OpenSpec caches can require one scan to recover unmarked evidence, because their previous JSON did not retain it. Error logs intentionally omit raw error descriptions to avoid persisting owner content.

### Alternatives Considered

Deleting completed evidence would lose access to Reset. Filtering only after scans would retain the delayed feedback. Rewriting evidence on each mark would mix owner state with observed evidence and could race a scan.

## Files Changed

| File | Change |
|------|--------|
| `Sources/ZeigarnikCore/Specs/SpecCatalog.swift` | Shared override application and checkbox counts |
| `Sources/ZeigarnikCore/Scan/Scanner.swift` | Persist unmarked evidence and report override-read failures |
| `Sources/ZeigarnikCore/Store/StoreReads.swift` | Join current overrides, throw on corrupt evidence |
| `Sources/ZeigarnikKit/Model/AppModel.swift` | Open-spec projection and content-free error log |
| `Sources/ZeigarnikUI/Inspector/ProjectInspector.swift` | Show Completed and default open list |
| `Tests/ZeigarnikKitTests/SpecOverrideTests.swift` | Model entry-point persistence, filtering and failure tests |
| `Tests/ZeigarnikCoreTests/ScannerTests.swift` | Scan followed by Reset preserves original evidence |
| `architecture.md`, `DESIGN.md` | Read semantics, diagnostic effects and inspector behavior |
