# AGENTS.md

## Cursor Cloud specific instructions

AI Usage Pace is a **macOS-only menu bar app** built with Xcode (`AIUsagePace.xcodeproj`).
It uses AppKit, SwiftUI, Combine, and CryptoKit, and it is built/tested with
`xcodebuild`. See `README.md` (실행 section) for the canonical build/test commands.

### Platform reality on the Linux cloud agent

- The Cursor Cloud agent runs on **Linux x86_64**, so the full app **cannot be
  built, run, or unit-tested here**: `xcodebuild` is macOS-only, and
  AppKit/SwiftUI/Combine/CryptoKit are unavailable on Linux.
- The XCTest suite in `AIUsagePaceTests/` uses `@testable import AIUsagePace`,
  which compiles the whole app module (including the Apple-only frameworks
  above). It therefore cannot run on Linux either. Run it on macOS with Xcode 16+
  using the command in `README.md`.
- There are **no external Swift Package Manager dependencies**, so there is
  nothing to `install` on Linux for this repository. The update script is a
  no-op by design.

### What can be exercised on Linux

Only the **platform-independent core** compiles with `swift` for Linux — i.e.
files that import Foundation only:

- `AIUsagePace/Models/*` (except nothing Apple-only)
- `AIUsagePace/Utilities/ISO8601Timestamp.swift`
- `AIUsagePace/Providers/{Cursor,Grok,Codex}/{*Models,*UsageMapper}.swift`

Files that are **not** Linux-compilable: everything under `App/`, `Views/`,
`Services/RefreshService.swift` (AppKit + Combine), and
`Utilities/JWTAccessToken.swift` (CryptoKit). The auth readers
(`Providers/*/…AuthReader.swift`) transitively depend on `JWTAccessToken`.

Non-obvious gotcha: on Linux Swift 6.1.2 the string-concatenation expression in
`ISO8601Timestamp.trimmedFractionalSeconds` hits a type-checker complexity limit
that Xcode/macOS does not. Splitting the single 3-way `String`/`Substring`
concat into separate `let` bindings (semantically identical) lets it compile on
Linux. Do this only in a throwaway build copy — do not change the repo source.

To exercise the core logic on Linux you must first install a Swift toolchain
(not part of the codebase; not installed by the update script), e.g. the
`swift-6.1.2-RELEASE-ubuntu24.04` tarball from `download.swift.org`. Then compile
the Foundation-only files together with a small driver and decode the real
fixtures in `AIUsagePaceTests/Fixtures/` to validate the Cursor/Grok usage
mappers.
