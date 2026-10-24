# Windows build and PC verification

Status: **First local Windows verification passed on 2026-10-24.** All 215
Windows tests, replay parity, source smoke, and packaged smoke passed on Windows
11 x64, including checks with developer directories removed from PATH. Native
save/open, Unicode filenames, Mac example loading, and dialog cancellation were
exercised. Clean-machine delivery and full manual acceptance remain pending.

The first PC run fixed recovery-folder URL comparison, touching-edge lobby
geometry, and a Mac-only artwork test call. SDL is pinned to 3.4.16 because
3.4.0's Windows modern-dialog fallback could invoke the result callback twice
and crash the application after file selection. The failing save interaction
was reproduced under LLDB and passed with 3.4.16.

The project is now connected to `chriswallace/Lofty-Ambitions` on GitHub.
The workflow in `.github/workflows/cross-platform.yml` runs after publication.
A local PC run has passed; updated hosted CI and separate clean-PC results are still required.

## First PC build

Use Windows 11 x64 and 64-bit PowerShell. Unzip the complete source archive to a
writable folder, such as `C:\Projects\Lofty Ambitions`. Keep `Assets`, `Vendor`,
`Sources`, `Tests`, `Package.swift`, and `VERSION` together. Do not install or
build into a game-save folder or `Program Files`.

Install the official [Swift 6.4.1 Windows toolchain](https://www.swift.org/install/windows/)
and its [platform prerequisites](https://www.swift.org/install/windows/manual/):
Visual Studio 2022 C++ x64 tools, a Windows 11 SDK, Python, and Git. These are build
requirements; players of the finished ZIP do not need them. Follow the official
Swift instructions for Developer Mode. Reopen PowerShell after installation.

From the extracted source folder run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

The execution-policy override applies only to this invocation. The script does
not install developer tools or change persistent execution policy. It initializes
an installed Visual Studio x64 developer environment when needed. Swift is pinned
to 6.4.1 so runtime files, notices, and CI use the same release.

The script performs these checks and writes a separate staging folder under
`dist\windows`; it never clears an installed game or existing player saves:

1. Download the pinned official SDL 3.4.16 development archive, verify SHA-256, and
   set the include/library paths. Its archive remains cached under `Vendor\SDL3`.
2. Run release tests, build `LoftyDesktop.exe` and `TowerReplay.exe`, and replay
   the checked-in construction/transit/fire timeline. Compare every saved field
   against the checked-in snapshot.
3. Run `LoftyDesktop --smoke` against a disposable directory. Capture gameplay,
   progression, and building panels; verify assets and the save/recovery round-trip.
4. Copy the actual SwiftPM resource folder, installed Swift runtime DLLs, SDL,
   and recursively resolved non-system DLL imports into a new package. Verify
   that each packaged executable/DLL is x64. MSVC files come from its installed
   redistributable directory; Windows system files are not copied.
5. Set the packaged game's Windows GUI subsystem while retaining its existing
   entry point. Run packaged replay and GUI smoke checks from an unrelated
   working folder with Swift/SDL developer directories removed from `PATH`.
   Every application smoke process has a 120-second timeout.
6. Include third-party notices, a per-file SHA-256 manifest (including resources),
   and a version from `VERSION`; create a versioned ZIP and its SHA-256 sidecar.

The source archive's revision is recorded as `unversioned-source-archive`.
A hosted build records `GITHUB_SHA`. The package manifest records automated checks
and explicitly leaves clean-machine validation pending.

## Send back diagnostics

Whether the script passes or fails, return the newest
`dist\windows\Lofty-Windows-Diagnostics-*.zip`. It contains the transcript,
individual build/test/import logs, toolchain information, graphics/Windows
versions, replay comparison reports, disposable saves, and screenshots when
those stages succeeded. A failure before a stage means its outputs will be absent.
The transcript can contain local source/toolchain path names.

Also report whether a normal double-click of the packaged `LoftyDesktop.exe`
opens the game without a console window. Do not send an ordinary player save
unless you deliberately want it examined. The automated smoke run uses its own
folder and does not open the user's autosave.

A passing builder run is the first Windows result. It is still necessary to
extract the generated game ZIP on a separate Windows 11 x64 computer without
Swift, Visual Studio, Python, or SDL installed and repeat the launch checks.
Keep all DLLs and the resource folder beside the executable. Move the extracted
folder to a different location containing spaces and Unicode characters and
launch it from a different working directory as well.

## Manual PC acceptance

Use disposable towers for these checks. Record failures and screenshots in the
returned diagnostics rather than changing the checked-in baseline to match them.

- Verify title/new game, restore, pause/speeds, focus mode, keyboard shortcuts,
  text input, cancellation, tab focus, mouse dragging, wheel pan, zoom, and fit.
- Try 100%, 150%, and 200% Windows display scaling, window resizing, and moving
  between displays. Text, hit targets, atlas images, and pointer coordinates
  should remain aligned. The minimum portable window is 1080×650 logical units.
- Exercise all room kinds, locked/unaffordable feedback, row placement, floors,
  widening/site limits, basement excavation, and Grand Lobby upgrade.
- Exercise all elevator types, placement, extension, upgrade, relocation,
  transfers/queues, inspection, rent/interior/apartment policies, and demolition
  confirmations with a safe default.
- Check coverage overlays, issues/shortcuts, ambition claims, tower levels,
  rewards, Open House/Night Market, celebrations, and the milestone roadmap.
- Check hotel housekeeping, notices/court/eviction, fire dispatch/repair and its
  visible truck/firefighters/water, plus the incident sandbox.
- Save/open with spaces and Unicode paths; cancel native dialogs; try a read-only
  destination and an invalid save. Failures must leave the current tower intact.
  Check autosave, unsaved-change prompts, recovery copies, and recovery UI.
- Open a disposable Mac save on Windows, change and save it, and reopen the
  Windows-produced file on Mac. Compare the shared replay reports as well.
- Test the representative 50-floor transport tower at 1920×1080. Record CPU/GPU,
  resolution/scaling, measured frame rate, and responsiveness while interacting.
  The target is stable 30 fps on the test PC; this has not yet been measured.

The automated replay is intentionally narrower than full interface parity.
Passing it cannot establish discoverability, visual fidelity, native-dialog
behavior, accessibility, or the complete manual feature checklist.

## Replay comparisons and keeping platforms synchronized

Both platforms run the same `Tests/Fixtures/construction-transit-fire-v1.json`.
The expected state is `construction-transit-fire-v1.snapshot.json`. Use:

```text
python scripts/check-parity.py --replay PATH_TO_TowerReplay --write-actual replay.snapshot.json --report parity.json
python scripts/check-parity.py --actual replay.snapshot.json --report parity.json
```

The comparison ignores object-key ordering only. It preserves ordered arrays,
requires every field, compares integers/strings/booleans/null exactly, and allows
only an absolute difference of `1e-9` for floating-point values. There is no
relative tolerance, rounding, broad field exclusion, or NaN acceptance. Reports
include the version, fixture/baseline hashes, and shared source/artwork hashes.
A meaningful simulation change needs a reviewed fixture/baseline update on both
platforms; a platform mismatch should be fixed rather than hidden.

The prepared matrix installs official Swift 6.4.1 on macOS and Windows and pins
all directly invoked actions to verified upstream commit IDs. macOS builds SDL
3.4.16 from its checksum-verified source release; Windows uses the checksum-verified
VC development release. Both compare against the same baseline. The Mac job also
builds the native application; the Windows job produces a package and diagnostics.
Logs/captures are retained even after a failed build. The repository has now
been created; inspect actual workflow results rather than assuming a green build.

Relevant upstream references:

- [Swift on Windows](https://www.swift.org/install/windows/)
- [Swift Windows toolchain/runtime layout](https://github.com/swiftlang/swift/blob/main/docs/WindowsToolchain.md)
- [SDL 3.4.16 release](https://github.com/libsdl-org/SDL/releases/tag/release-3.4.16)
- [Microsoft DLL import inspection](https://learn.microsoft.com/en-us/cpp/build/reference/dependents)


Windows maximize follow-up (2026-10-24): isolated procedural and sprite texture caches, bounded cloud generation, and cached sprite-sheet paths fix the reproduced resize freeze. The packaged paused 50-floor render check now covers maximize, minimum zoom, restore, and maximize again, with zero steady PNG decodes. See verification/windows-2026-10-24.txt for timings and limits. Running-simulation performance and separate clean-PC delivery still need acceptance.


Readable Windows UI follow-up (2026-10-24): 218 tests pass. Auto UI now starts at 125% where space permits, follows Windows display scaling, and uses 200% in a maximized 4K window. The toolbar UI control saves size preferences. Drawing, font rasterization, mouse coordinates, and drags use the same logical viewport. The paused 50-floor resize check covers default scaling and an unscaled 4K view; see verification/windows-2026-10-24.txt for timings. The separate display-scaling acceptance matrix remains pending.
