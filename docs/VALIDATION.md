# Current validation — 2026-10-24

This game has never been publicly released. Version numbers identify development builds.

## Shared code and Mac checks

- **223 tests pass:** 194 simulation/artwork tests, 12 session/recovery/replay tests, 9 scene tests, and 8 portable interaction tests.
- **Replay parity passes:** every saved field matches the checked-in construction/transit/fire/rent-dispute baseline; the actual canonical output is byte-identical. Floating-point comparison permits at most 1e-9 absolute difference. See `porting/verification/replay-parity.json`.
- **Native Mac interface checks pass:** title screen, catalog/search, locks, placement, inspections, menus, progression, interiors, safe demolition, focus, camera geometry, basements, Grand Lobby, transport movement, service shortages, and coverage overlays.
- **Portable SDL smoke check passes locally on Mac:** the shared replay renders with real atlas artwork, including the finished fire-engine asset; gameplay/build/progression panels capture successfully; save/open and recovery round-trip preserve canonical state. Smoke checks use disposable folders.
- **C bridge:** warning-clean compilation and address/undefined-behavior sanitizer checks covered drawing, input, capture, alpha conversion, texture caching, and asynchronous dialog callback lifetime during implementation.

- **Mac package rebuilt:** development version 0.13.0 contains both arm64 and x86_64; strict signature verification passes. A disposable emergency-scene launch from the packaged application also passes; both slices declare macOS 13.0 as their minimum.

## Windows status

Windows execution is pending. Static packaging review and PowerShell parsing cannot establish Windows compatibility. The first PC run must build and test the same source, return diagnostics, and then verify the generated player ZIP on a computer without development tools. The detailed manual checklist includes high DPI, window resizing, native dialogs, Unicode paths, all gameplay controls, 50-floor performance, and two-way save exchange.

See `porting/WINDOWS.md` and `porting/progress.md`. The prepared GitHub workflow has not run because this project has no configured repository or remote.
