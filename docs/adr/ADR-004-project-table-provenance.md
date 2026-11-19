# ADR-004: Store project-table membership and report re-links

**Date:** 2026-11-19
**Status:** Accepted

## Context

A project comes from one of two sources: discovery under a scan root, or a row in the optional project table (`CLAUDE.md` in the first root). The store did not record which, so the UI could not tell a listed project from a discovered one, and a later rule about table projects (for example whether one outside every root may go missing) had nothing to read. Separately, when a moved repository was matched to its existing project through `projectPath` (a re-link), the scan said nothing about it: the owner saw the new path without knowing a move had been recognised.

## Decision

- Migration `v6-project-table` adds one nullable column, `project.projectTablePath`: the resolved path of the table that lists the project, or NULL when only discovery found it.
- After a scan that could read the table, membership is rewritten for that table only: rows pointing at the scanned table are cleared, then the listed projects are set. Rows that belong to another table path are left alone, so a CLI scan of a different root does not erase the app's membership.
- `ProjectRow.isTableProject` exposes it to the UI.
- `ScanReport.relinks` lists every re-link the scan stored (`projectId`, `fromPath`, `toPath`); a re-link that failed to store is not reported.

## Consequences

### Positive
- The UI can label table projects, and later rules can depend on table membership.
- A recognised move is visible in the scan report instead of silent.

### Negative
- One more column and one more write per scan.
- Membership is per table path; renaming the table file clears it until the next scan reads the new path.

### Alternatives Considered
- A separate `projectTable` join table: more flexible (several tables per project), but no current need; one nullable column is enough.
- Deriving membership at read time by parsing the table: couples every read to the file system and fails when the table is unreadable.

## Files Changed

| File | Change |
|------|--------|
| `Sources/ZeigarnikCore/Store/Schema.swift` | Migration `v6-project-table` |
| `Sources/ZeigarnikCore/Store/Store.swift` | `updateTableMembership`, `ProjectRow.isTableProject` |
| `Sources/ZeigarnikCore/Scan/Scanner.swift` | Membership update after the table is read; `ScanReport.relinks` |
| `Sources/ZeigarnikUI/Inspector/ProjectInspector.swift` | Shows the project's source |
