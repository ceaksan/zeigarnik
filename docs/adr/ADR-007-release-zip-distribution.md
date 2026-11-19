# ADR-007: Distribute a signed, not notarized zip on GitHub Releases

**Date:** 2026-11-20
**Status:** Accepted

## Context

The design spec settled on source-only distribution: build with Xcode, not sandboxed, not notarized. That limits the app to people with Xcode 16 and xcodegen. Clause, a sibling project, already ships a not notarized zip on GitHub Releases, so the cost of the step is known.

Notarization needs a Developer ID Application certificate, which needs a paid Apple Developer Program membership. The release machine has only an Apple Development certificate, and that certificate's common name carries the owner's Apple ID email; anyone can read it from a published app with `codesign -dvv`.

Zeigarnik asks for more TCC access than Clause: the Documents folder, iCloud Drive and Calendars. macOS ties these grants to the app's designated requirement. An ad-hoc signature has no certificate, so the requirement changes with every build and each update would ask for every permission again.

## Decision

- Each release is a `Zeigarnik-<version>-macos.zip` asset on GitHub Releases, a universal build (arm64 and x86_64), produced by `scripts/release.sh`.
- Every release is signed with one self-signed code-signing certificate named `Zeigarnik Release`, so the designated requirement stays the same and TCC grants survive updates. The certificate carries no personal name or email. The script reads the identity from `ZEIGARNIK_SIGN_IDENTITY` (default `Zeigarnik Release`).
- The certificate lives in the release machine's login keychain with a validity of ten years, and a `.p12` export is kept outside the machine as a backup.
- Not notarized, not sandboxed, no hardened runtime. The README tells users how to open it the first time (Privacy & Security, Open Anyway, or `xattr -dr com.apple.quarantine`).
- The `zeigarnik` CLI ships inside the app at `Contents/Helpers/zeigarnik`. It cannot go in `Contents/MacOS`: APFS is case-insensitive by default and `zeigarnik` would collide with the app binary `Zeigarnik`.
- Building from source stays supported and documented.

## Consequences

### Positive
- Users install without Xcode; agents get the CLI and MCP server from the same download.
- Permission prompts appear once per machine, not once per update.
- The published signature names the project, not a person.

### Negative
- Gatekeeper blocks the first launch until the user approves it; the README has to carry that step.
- Losing the certificate, or replacing it when it expires, changes the designated requirement; users are asked for permissions once more.
- Survival of TCC grants across releases is expected from the stable requirement but is confirmed only once a second release is installed over the first.
- No automatic updates; users download each release.

### Alternatives Considered
- Source only (previous state): rejected, it keeps the app away from anyone without Xcode.
- Ad-hoc signed zip, as Clause does: rejected, every update would reset Documents, iCloud Drive and Calendars access.
- Apple Development certificate: rejected, its common name publishes the owner's Apple ID email in every release.
- Developer ID signing and notarization: deferred, it needs the paid membership. Revisit with a Homebrew cask and Sparkle updates when the app is promoted publicly.
- CLI embedded by an xcodegen tool target, as Clause does: rejected, the CLI is a SwiftPM product (ADR-002); the release script builds and copies it.

## Files Changed

| File | Change |
|------|--------|
| `scripts/release.sh` | Universal Release build, CLI copied to `Contents/Helpers`, signing, zip |
| `README.md` | Download and first-launch steps; CLI path inside the app |
| `architecture.md` | Distribution row |
| `CLAUDE.md` | Release command |
