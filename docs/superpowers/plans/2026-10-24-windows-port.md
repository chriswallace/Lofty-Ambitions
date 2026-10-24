# Windows Port Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent subsystems and review their integration.

**Goal:** Deliver the shared Windows frontend and packaging path without forking game rules or changing player saves.

**Architecture:** Compile one TowerCore into both applications. Share session commands, resources, and presentation; preserve the native Mac controls and use an SDL desktop adapter for Windows. Test the portable frontend on this Mac and provide a PC build/verification handoff.

**Tech Stack:** Swift, SDL3, small C rendering/input bridge, shared original PNG assets, XCTest, PowerShell packaging.

**Spec:** docs/superpowers/specs/2026-10-24-windows-port-design.md

## Global Constraints

- Preserve macOS 13+ support, Apple Silicon and Intel, and the existing Mac controls.
- Preserve the JSON save format and every current game rule.
- One artwork source including vehicle.fireEngine; no copied Windows art tree.
- Never write player saves in development or smoke checks.
- Full Windows completion requires an actual PC run; the user has a PC but it is not connected to this executor.
- This directory has no Git metadata. Work in place with /tmp/lofty-before-windows-20261024.tgz as a source backup; do not invent commits or configure a remote.

## Review Focus

- Windows geometry, Foundation, paths, and runtime DLL packaging must actually compile on PC.
- Save dialogs and failed writes must not replace a current tower or recovery original.
- Every listed feature must have a usable interface, including confirmations and incident resolution.
- All original room states, shared walls, actor registration, lifts, and truck artwork must render correctly.
- A Mac SDL run does not validate Windows packaging or clean-machine behavior.

### Task 1: Shared session and parity runner

Files: Sources/TowerSession/, Tests/TowerSessionTests/, Sources/TowerReplay/.
Interfaces: TowerSession owns TowerState and executes a typed Codable TowerCommand. Snapshot replay is available as a CLI for both platforms.
- [x] Write and run failing tests for command validation, undo-safe confirmation boundaries, save round-trips, and deterministic replays.
- [x] Implement shared commands and registry without duplicating TowerCore rules.
- [x] Run session tests and replay fixtures; preserve existing core tests.

### Task 2: Shared portable presentation and Mac adapter

Files: Assets/Tokyo/Runtime/, Sources/TowerPresentation/, platform-independent presentation tests, Mac drawing integration.
Interfaces: TowerScene emits pixel-coordinate drawing commands with stable atlas keys; public scene rectangle/color and camera types have no OS graphics dependency. Reuse production room, elevator, actor, lobby, coverage, city, and incident logic. Keep AppKit graphics conditional and usable.
- [x] Add failing tests for scene asset selection, actor/camera geometry, emergency artwork, and hit testing.
- [x] Extract portable resources/presentation and implement a shared scene generator.
- [x] Integrate the Mac rendering adapter and verify artwork/visual regression checks.

### Task 3: SDL desktop bridge

Files: Sources/CDesktop/, Vendor/stb/, scripts/bootstrap-desktop.*.
Interfaces: CDesktop exposes window/input, drawing, text, PNG textures, clipping, dialogs, and capture through a small plain-C API. SDL headers remain private to the C implementation.
- [x] Pin upstream SDL/STB dependencies and license notices.
- [x] Implement and compile the bridge with local SDL3; exercise input/drawing/capture.
- [x] Document Windows include/lib/runtime requirements and safe asynchronous file events.

### Task 4: Complete portable interface and package wiring

Files: Sources/TowerDesktop/, Package.swift, scripts/run-desktop.sh, desktop checks.
Interfaces: Uses TowerSession, TowerPresentation, and CDesktop. Shared commands drive all game mutations. File services preserve recovery and save semantics.
- [x] Wire conditional targets so normal Mac builds do not require SDL and portable tests exclude Apple-only APIs on Windows.
- [x] Implement title screen, catalog/search, toolbar, inspection, progression, issues, policies, confirmations, and input parity.
- [x] Exercise a disposable scripted scenario with captured frames and save round-trip.

### Task 5: Windows packaging, synchronization, and review

Files: scripts/build-windows.ps1, scripts/check-parity.*, .github/workflows/cross-platform.yml, docs/porting/.
- [x] Provide pinned Windows bootstrap/build scripts that collect needed runtimes, resources and licenses into a standalone ZIP.
- [x] Add shared version/feature/asset verification and cross-OS replay workflow.
- [x] Run local full tests, native UI checks, SDL smoke checks and a fresh integration review.
- [x] Prepare a concrete, checksum-verified PC source/build/test bundle.
- [ ] Run on the user’s Windows PC, inspect diagnostics, resolve Windows-specific failures, and verify a clean-machine package before claiming Windows completion.
