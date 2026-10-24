# Room Incidents Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Track completion here; this directory has no git repository, so work directly and do not commit.

**Goal:** Playable room incidents with persistent emotional signals and visible service responses.
**Architecture:** Optional per-room incident state, a focused TowerCore incident state machine, native inspector actions, and a separate AppKit drawing extension.
**Tech Stack:** Swift 5.9, AppKit, XCTest; macOS 13+.
**Spec:** docs/superpowers/specs/2026-09-15-room-incidents-design.md

## Global constraints

- Native Swift/AppKit, macOS 13+, no external dependencies.
- Preserve existing saves and deterministic minute-by-minute behavior.
- No autosave writes in screenshot verification.

## Tasks

- [x] Core: write failing IncidentTests.swift for party/cleanup, rent/court/eviction, fire/repair, income, staffing, bubbles, migration, and validation. Run `swift test --disable-sandbox --filter IncidentTests`; implement Incidents.swift plus Simulation.swift/Transit.swift hooks; rerun all tests.
- [x] Drawing: add IncidentDrawing.swift; consume room.incident, game.signal(for:), incident.stage/remainingMinutes/durationMinutes/severity/responseRoute. Add room effects, FD scene, pixel expression bubbles, shared bubble hit regions, and expanded hover/selection copy. Compile and visually inspect.
- [x] Controls: extend GameController inspector with incident progress/actions and a tower-wide issue list; add explicit Game menu sandbox triggers. Run full build, exercise UI and capture screenshot.
- [x] Review: independently inspect completed behavior and persistence; fix findings with regression tests. Build universal application and update README/DESIGN/VALIDATION.

## API contract

`IncidentKind`: party, rentArrears, fire.
`IncidentStage`: partying, awaitingCleaning, cleaning, rentOverdue, noticeServed, courtPending, evictionApproved, evicting, burning, dispatched, extinguishing, awaitingRepairs, repairing, resolved.
`FireResponseRoute`: ladder, interior.
`RoomIncident`: kind, stage, remainingMinutes:Int, durationMinutes:Int, severity:Double, arrears:Double, responderRoomID:Int?, responseRoute:FireResponseRoute?. `isActive:Bool`, `progress:Double`, `title:String`.
`RoomSignal`: mood:RoomMood, text:String, symbol:String. `RoomMood`: angry, annoyed, worried, alarmed, sad, relieved, busy.
`TowerState.signal(for:Room)->RoomSignal?`, `triggerIncident(_:IncidentKind,roomID:Int) throws`, `respond(to:Int,action:IncidentAction) throws`, `incidentActions(for:Room)->[IncidentAction]`, `responseBlocker(for:Room,action:IncidentAction)->String?`, `income(for:Room)->Int`.
`IncidentAction`: sendHousekeeping, serveNotice, fileCourtCase, evict, dispatchFireDepartment, repair. `title:String`.

## Completion record

- Core: implemented and verified with 17 new tests, 42 total passing.
- Drawing: independently implemented and reviewed; native screenshot checked.
- Controls: implemented and built, housekeeping action exercised in native app.
- Review findings resolved: active amenities, occupied fire saves, closed hotel visitor journeys, reduced motion, and demo autosave/fit safeguards.
- Packaging: universal 0.3.0, signature validated. Existing directory is not a git repository, so no commits or worktree were created.
