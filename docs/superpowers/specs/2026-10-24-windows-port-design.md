# Lofty Ambitions: Windows port and shared development

Status: proposed design; implementation has not started.

## Intent

Deliver a complete Windows edition of the existing game and keep future Mac and Windows behavior synchronized through shared source code, shared artwork, compatible saves, and checks on both operating systems. A second implementation of the simulation is unacceptable.

The user requested a full Windows port after completion of the Steam promotional kit, with a concrete way to keep the codebases in sync. The kit is complete. The user has not selected a UI strategy. The proposed default is to retain the current native Mac interface and use a portable desktop game interface on Windows; the user can instead choose a shared interface on both platforms before implementation.

## Current state

- `Sources/TowerCore/` contains the Swift simulation and persistence. It uses Foundation and does not import AppKit or CoreGraphics.
- `Sources/TowerApp/` combines AppKit controls, input handling, drawing, and session management.
- `Assets/Tokyo/Runtime/` contains shared artwork and animation/layout code, but `Atlas.swift`, cloud image creation, and several geometry imports currently depend on Apple graphics APIs.
- `Package.swift` builds the Mac application, artwork resources, and one test target. Some tests import AppKit and cannot compile on Windows as written.
- `scripts/build-app.sh` produces the universal Mac bundle. No Windows build or CI workflow exists in this directory, and this working directory has no Git metadata or configured remote.
- This task runs on an Apple Silicon Mac. No Windows execution environment has been established. SDL3 is already installed locally and can support development of the portable frontend on this Mac; that does not constitute Windows verification.

## Proposed architecture

Maintain one source tree and release version. Keep Swift for the simulation and shared presentation. Add an SDL3 desktop frontend for Windows that can also run on Mac as a development/test target. The existing AppKit application remains the normal Mac edition.

Split responsibilities into the following modules:

1. **TowerCore**: existing game rules, catalog, progression, deterministic simulation, validation, save encoding and migrations. Both applications compile these exact files. No OS-specific game rules.
2. **TowerSession**: shared game commands, selection/tool state, pause and speed handling, save/recovery policy, confirmation requests, issue actions, and feature availability. Both interfaces invoke the same commands. No rent, construction, progression, or incident logic in frontend event handlers.
3. **TowerResources**: one atlas manifest, original PNG sheets, title screen, and portable metadata. No duplicate Windows art directory. Resource discovery uses package/application resource locations, not checkout paths or the current working directory.
4. **TowerPresentation**: platform-independent camera and hit testing, visible scene generation, room nine-slicing, building layout, cloud pixel generation, sprite/occupant placement, elevator cutaways, incident presentation, coverage, and celebration timing. It produces drawing commands with portable numeric geometry and stable asset keys. No AppKit, CoreGraphics, Win32, or SDL imports in this module. Animation time and deterministic fixtures are injected.
5. **Mac adapters**: existing native controls invoke TowerSession. An AppKit drawing backend consumes TowerPresentation commands and supplies OS dialogs, accessibility settings, and text rendering. Preserve the current Mac appearance, behavior, controls, and shortcuts.
6. **Portable desktop adapters**: Swift interface and SDL drawing/input backend. Use SDL3 for windowing, renderer selection, input, clipboard, and native file dialogs. Image decoding and text shaping/rasterization dependencies are explicit and pinned. The builder may select the smallest maintained SDL-compatible libraries after validating their Windows packaging. Interface panels use shared models and commands. Windows uses familiar Ctrl shortcuts and platform-appropriate save locations.

The Mac renderer is migrated incrementally to shared scene generation. Do not leave a second long-term implementation of room layout, camera math, transit drawing, or incident presentation in the Windows frontend. Platform-specific code may translate drawing commands and OS events; it may not contain an alternate scene generator or simulation.

Use portable geometry structs in shared presentation, with adapters at platform boundaries. Do not create a partial imitation of the AppKit API. Keep UI strings and action availability shared where their meaning is the same. Preserve original PNGs and atlas coordinates, including the completed `vehicle.fireEngine` artwork.

## Full-port scope

Windows must expose all currently implemented gameplay and management actions, with equivalent outcomes:

- Title screen; new game; restored autosave; pause; 1×, 4×, 12× speed; focus mode.
- Room catalog with all 18 room kinds including the lobby, search, categories, costs, capacity, operating details, and locked/unaffordable explanations.
- Room placement and row dragging; floor construction and extensions; adding floors; whole-tower widening; site limits and invalid-placement feedback.
- Standard, wide, and express elevators; vertical placement; extension; upgrade; relocation; transfer behavior; inspection; queues and cabin animation.
- Room and elevator inspection; rent adjustment; office/apartment interior choices; apartment screening and deposit choices.
- Demolition confirmations with refunds, lost-access consequences, safe default, and simulation pause/resume.
- Food and shopping coverage overlays, reach guides, percentages, issues list, and nearby-service shortcuts.
- All tower levels, room unlocks, grants, ambitions, reward claiming, Open House, Night Market, celebrations, and the milestone roadmap.
- B1–B4 excavation, basement placement rules, underground districts and bonuses, Grand Lobby upgrade and supported migration.
- Hotel parties and housekeeping cleanup; rent notice/court/eviction flow; fires, dispatch, repair, mood signals, animated truck, ladder/interior response, firefighters and water. Expose the existing incident sandbox as a development menu/action.
- Manual save/open, autosave, unsaved-change handling, distinct recovery copies, recovery UI, and legacy save migration. Files can move between operating systems without conversion.
- Drag/scroll pan, cursor-centered zoom, fit, keyboard tool commands, text input, Escape/cancel, focus navigation, tooltips or equivalent detail help.
- Original city variation and day/night transitions, transparent room windows, room states, independent residents, furniture activities, moving travelers and elevators, and reduced-motion handling.

The scope is parity with the existing game. Sound, service elevators, fire spread, and VIP events are currently unimplemented and are not added as part of the port. Steam Cloud, achievements, multiplayer, localization, and a new visual redesign are separate work.

## Persistence and platform behavior

- Keep `.loftyambitions` JSON, migration rules, and validation shared. Do not fork the file format or derive it from UI serialization.
- Mac retains its current Application Support locations. Windows stores user saves/recovery under a per-user local application-data directory, obtained through the OS/SDL platform service; never beside the executable or in Program Files.
- Saving remains atomic. Read a candidate save and validate it before changing the current session. A failed or canceled operation must not alter the current tower. Preserve recovery originals and safe-switch behavior.
- Background file-dialog callbacks enter a main-thread queue; they cannot mutate a session off the simulation thread.
- Do not read, migrate, overwrite, or delete the user's actual saves while developing/testing. Tests use isolated directories and disposable towers.
- Normalize command semantics across Cmd/Ctrl, wheel direction, pixel density, window resizing, and file-path encodings. Include Unicode paths, canceled dialogs, read-only destinations, and interrupted/failed saves in acceptance checks.

## Windows deliverable

Initial required platform: Windows 11 x86-64. Mac support stays macOS 13+, Apple Silicon and Intel. Windows ARM64 and older Windows versions are optional follow-ups, not implicit support claims.

Produce a versioned release ZIP with the game executable, required Swift runtime files, SDL and text/image runtime dependencies, artwork, application icon/manifest, and third-party license notices. It must launch on a clean machine without a Swift toolchain, Python, Homebrew, Xcode, or a source checkout. Avoid a console window for ordinary launch. Build and smoke-test packaging on Windows; do not guess which DLLs are needed.

A signed Windows installer and Microsoft code-signing certificate are outside the initial deliverable. Do not silently publish, create a repository, upload the game to Steam, or buy certificates/services. Packaging source and local builds are authorized by the port request; hosted infrastructure/account changes need separate authorization when necessary.

## Keeping development in sync

One repository is the eventual source of truth. Prepare repository-independent build/test scripts in this directory, plus a CI workflow that can run once the user places the project in a Git repository. Do not pretend CI has run or a remote has been configured. The user can choose a host/runner during implementation; that choice does not block local architectural extraction.

- One shared release version and asset inventory, checked into the source tree.
- A documented feature matrix and command registry listing every current action and its Mac/Windows interface entry point. Tests require each frontend to register a handler for every applicable user action; manual parity checks still confirm discoverability and usefulness.
- Pull-request checks build both frontends, run portable simulation/session/presentation tests on Mac and Windows, and run platform-specific smoke checks. Once hosted CI is active, require both platform jobs before merging/releasing.
- Replay identical versioned fixture saves and command timelines on both OSes. Export canonical snapshots at defined simulation minutes; compare game state, progression, services, transit, incidents, treasury, and saves after normalizing serialization order and explicitly documented floating-point tolerances. Never mask behavioral mismatches with broad exclusions.
- Share presentation command fixtures and deterministic camera/animation parameters. Verify sprite identity, bounds, ordering, scaling, clipping, and hit testing. Screenshot checks tolerate platform text antialiasing, but must catch missing assets, wrong geometry, or missing controls.
- Build release artifacts for both platforms from the same source revision and record that revision and resource hashes in each artifact. If either fails, do not mark the combined release ready.
- New gameplay belongs in TowerCore; application behavior belongs in TowerSession; scene logic belongs in TowerPresentation. New actions update the registry, both UI integrations, and the relevant parity fixture in the same change.

## Incremental delivery and verification

1. Establish portable Core-only builds/tests and shared save/replay fixtures. Separate AppKit-dependent tests without weakening Mac artwork tests.
2. Extract shared session commands and resource metadata while retaining the working Mac UI. Verify that existing behavior and saves still work.
3. Extract the portable renderer/camera and migrate the Mac drawing adapter, checked against existing visual fixtures. Bring up the SDL frontend on Mac for repeatable local input/render testing.
4. Complete the portable interface and all parity-matrix actions, with shared progression, incidents, inspection, confirmation, and save/recovery behavior.
5. Compile and run the Windows build on a real Windows runner. Resolve Windows toolchain, path, input, scaling, dialog, and runtime-package issues.
6. Run cross-OS replays, interface scenarios, and clean-machine package launch. Produce the Windows ZIP, refreshed Mac build if needed, parity report, and maintainer instructions.

Every stage must leave the Mac edition usable. Do not replace the existing distributable with a broken intermediate build. Preserve the completed promotional kit and its original source assets.

## Completion criteria and limits of this environment

The port is complete only when a packaged Windows executable is built and run on Windows, all listed gameplay features are accessible, saves round-trip in both directions, the complete regression suite passes on its applicable platforms, and synchronized build/parity checks have actually run on both OSes. A Mac run of the SDL frontend or an unexecuted workflow file is insufficient.

If no Windows runner or repository access is available, complete all locally testable work and report the exact remaining Windows validation and artifact steps. Mark the Windows port incomplete until those steps execute. Do not label cross-compilation, source changes, or a design document as a delivered Windows game.

## Implementation discretion

The builder chooses focused file boundaries, dependency pins with verified upstream checksums/licenses, the minimal SDL C interop shim, texture caching and batching, text/image backends, deterministic fixture naming, and workflow layout. Performance should remain responsive with the existing 50-floor transport example and at the current site limits; measure before adding optimization complexity. Target a stable 30 fps at 1920×1080 on the Windows test machine and report its hardware and the representative workload. UI actions and saves must remain functional when frame rate falls.

## Reference sources

Reviewed 2026-10-24:

- [Swift on Windows installation and toolchains](https://www.swift.org/install/windows/)
- [SDL Windows build and runtime deployment](https://github.com/libsdl-org/SDL/blob/main/docs/README-windows.md)
- [SDL3 renderer](https://wiki.libsdl.org/SDL3/SDL_CreateRenderer)
- [SDL3 texture drawing](https://wiki.libsdl.org/SDL3/SDL_RenderTexture)
- [SDL3 asynchronous native open dialogs](https://wiki.libsdl.org/SDL3/SDL_ShowOpenFileDialog)
