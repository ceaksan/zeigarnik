# ADR-002: App structure, SwiftPM libraries plus a thin xcodegen app

**Date:** 2026-11-19
**Status:** Accepted
**Spec:** [zeigarnik-design](../superpowers/specs/2026-11-18-zeigarnik-design.md)

## Context

The core (`ZeigarnikCore`, `zeigarnik-scan`) is a Swift package tested with `swift test`. The app adds a window, a menubar extra, owner data, EventKit sync and settings. The spec asks for an xcodegen `project.yml` with the generated project committed. Keeping all app code inside the xcodegen app target, the usual layout, would mean app logic is tested only through `xcodebuild test`.

## Decision

- Two new SwiftPM library targets: `ZeigarnikKit` (app logic without SwiftUI: owner-data use cases, filters, formatting, scan coordinator, calendar sync engine, observable app model) and `ZeigarnikUI` (SwiftUI views, theme, scenes, composition root).
- A thin xcodegen application target `Zeigarnik` (`App/`) holds only `@main`, Info.plist keys and bundle settings, and depends on the local package product `ZeigarnikUI`.
- Owner-data schema and queries stay in `ZeigarnikCore`'s `Store`, which owns the migrator, so the CLI and the app share one schema.
- EventKit (calendar sync) and ServiceManagement (`SMAppService`, launch at login) are system frameworks; no new third-party dependency.

## Consequences

### Positive
- `swift test` covers app logic without `xcodebuild`, which keeps the test loop light on a small development machine.
- Views cannot reach the database directly; they go through `AppModel` in `ZeigarnikKit`.

### Negative
- Two build entry points: `swift build` for the package, `xcodebuild` for the app bundle.
- Views in `ZeigarnikUI` are verified by building and running, not by unit tests.

### Alternatives Considered
- All app code in the xcodegen app target: rejected, app logic would need `xcodebuild test` and an app host.
- A SwiftPM executable as the app: rejected, no Info.plist usage strings, no bundle identity for TCC and EventKit, no login item.

## Files Changed

| File | Change |
|------|--------|
| `Package.swift` | Adds `ZeigarnikKit`, `ZeigarnikUI` and `ZeigarnikKitTests` |
| `project.yml`, `Zeigarnik.xcodeproj` | xcodegen app target `Zeigarnik` |
| `App/ZeigarnikApp.swift` | `@main` entry point |
| `Sources/ZeigarnikUI/ZeigarnikScenes.swift` | Window and menubar scenes |
| `Sources/ZeigarnikCore/Support/AppPaths.swift` | Shared database path for app and CLI |
