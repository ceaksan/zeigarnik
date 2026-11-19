# ADR-001: GRDB.swift for the SQLite store

**Date:** 2026-11-18
**Status:** Accepted
**Spec:** [zeigarnik-design](../superpowers/specs/2026-11-18-zeigarnik-design.md)

## Context

Zeigarnik keeps owner data (notes, pins, schedules), daily snapshots and ingested agent activity. The spec requires one SQLite database in `~/Library/Application Support/Zeigarnik/` that other tools and agents can read without the app, durable owner data, and transactional ingest (records and file cursor in one transaction).

## Decision

Use GRDB.swift (`from: "7.12.0"`) with a `DatabaseQueue` in WAL mode and a `DatabaseMigrator`. Schema is plain SQL tables with readable column names; Codable values that need structure are stored as JSON text.

## Consequences

### Positive
- SQL-first: the schema stays readable by `sqlite3`, Python or an agent.
- Migrations, transactions and Codable records without hand-written binding code.
- Maintained, widely used, Swift 6 concurrency compatible.

### Negative
- One third-party dependency to keep current.
- Compile time increases, noticeably on machines with little memory.

### Alternatives Considered
- SwiftData: schema is generated and opaque, hard for other tools to read; tied to the app process model.
- Raw `sqlite3` C API: no dependency, but much more binding and migration code to maintain.

## Files Changed

| File | Change |
|------|--------|
| `Package.swift` | GRDB dependency |
| `Sources/ZeigarnikCore/Store/` | Store, schema, identity (Task 11) |
