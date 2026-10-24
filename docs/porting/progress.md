# Windows port execution ledger

Plan: `docs/superpowers/plans/2026-10-24-windows-port.md`.

The user delegated platform adaptation and has a PC for testing. Mac keeps its native controls. Both applications share TowerCore, TowerSession, TowerArt, and TowerPresentation. The Windows frontend uses a small SDL adapter and platform-appropriate desktop controls.

No Git metadata exists. Work stayed in the current project, with a pre-port source backup at `/tmp/lofty-before-windows-20261024.tgz`. No repository, remote, commit, or hosted CI run was fabricated.

## Completed locally — 2026-10-24

- Shared typed commands, atomic failures, pause/speeds, confirmation boundaries, safe switching, recovery, replay, and canonical snapshots.
- Shared scene generation for city, rooms, furniture occupants, elevators, people, Grand Lobby, coverage, mood signals, and emergency effects. The real fire-engine sprite is shared with the marketing previews.
- Native Mac command/render integration and portable controls for construction, transport, progression, policies, coverage, incidents, save/open/recovery, search, help, focus, and keyboard/pointer input.
- SDL C bridge with bounded texture/text caches, native asynchronous file dialogs, alpha-correct generated clouds, and disposable PNG capture.
- Windows build/package script, pinned dependencies and notices, recursive runtime import collection, GUI executable staging, isolated-path checks, diagnostics, replay parity, and future two-OS CI workflow.
- 223 tests passed: 194 core, 12 session, 9 scene, and 8 portable interaction tests. Native Mac interface checks and local SDL smoke checks passed.
- Universal Mac application rebuilt as development version 0.13.0; arm64/x86_64 and strict signature verification passed.
- Shared replay equals the checked-in baseline byte-for-byte. Report: `verification/replay-parity.json`. The baseline was not changed to absorb port differences.
- Final static re-review confirmed the two elevator hit/range fixes with no remaining P1/P2 in those changes. `verification/portable-on-mac.png` is a local portable-render reference, not Windows evidence.

Fresh reviews covered shared simulation, presentation, UI integration, and Windows packaging. The review findings about elevator selection, recovery Save As, stale quit autosaves, modal defaults, single-click bank ranges, and paused ambition persistence were fixed with failing-then-passing regression checks.

## Cleanup and appearance

The user explicitly allowed legacy cleanup because there has been no public release. Removed dead native drawing stubs, renamed the obsolete “Classic” test label, made shared package targets unconditional, moved the transport example into `Examples`, and replaced historical release claims with current validation documentation. Existing development towers and original artwork remain usable.

The shared sky uses fine pixel bands; the former native-only facade haze blend is omitted. Native mood/coverage interaction remains overlaid through AppKit; the portable frontend draws and hits its shared scene metadata. These rendering decisions do not change game state.

## Required PC work

Windows compilation, real Windows graphics/input/dialogs, high-DPI behavior, 50-floor performance, Mac/Windows save exchange, and a package on a Windows machine without developer tools remain unverified. The source kit and `WINDOWS-START-HERE.txt` provide the first PC build command and diagnostics handoff. The generated ZIP is a source test kit, not a tested Windows executable.
