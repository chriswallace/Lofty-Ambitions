# Windows port execution ledger

Plan: `docs/superpowers/plans/2026-10-24-windows-port.md`.

The user delegated platform adaptation and has a PC for testing. Mac keeps its native controls. Both applications share TowerCore, TowerSession, TowerArt, and TowerPresentation. The Windows frontend uses a small SDL adapter and platform-appropriate desktop controls.

The original Mac port was prepared before Git metadata existed, with a pre-port source backup at `/tmp/lofty-before-windows-20261024.tgz`. It was subsequently published to `chriswallace/Lofty-Ambitions` and cloned to the PC. The first Windows verification below uses commit `ab11929` plus local Windows fixes.

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

Windows compilation, 215 tests, replay parity, source/packaged graphics smoke, title/keyboard pause, Unicode native save, Mac example loading, dialog cancellation, and a clean application exit have passed locally. A runnable Windows package and diagnostics were produced. Full manual acceptance, the display-scaling matrix, measured 50-floor performance, reopening a Windows save on Mac, and a separate Windows PC without developer tools remain pending. Details: `verification/windows-2026-10-24.txt`.


Windows maximize follow-up (2026-10-24): isolated procedural and sprite texture caches, bounded cloud generation, and cached sprite-sheet paths fix the reproduced resize freeze. The packaged paused 50-floor render check now covers maximize, minimum zoom, restore, and maximize again, with zero steady PNG decodes. See verification/windows-2026-10-24.txt for timings and limits. Running-simulation performance and separate clean-PC delivery still need acceptance.


Readable Windows UI follow-up (2026-10-24): 218 tests pass. Auto UI now starts at 125% where space permits, follows Windows display scaling, and uses 200% in a maximized 4K window. The toolbar UI control saves size preferences. Drawing, font rasterization, mouse coordinates, and drags use the same logical viewport. The paused 50-floor resize check covers default scaling and an unscaled 4K view; see verification/windows-2026-10-24.txt for timings. The separate display-scaling acceptance matrix remains pending.
