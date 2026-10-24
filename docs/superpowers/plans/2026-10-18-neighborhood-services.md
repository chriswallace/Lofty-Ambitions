# Neighborhood Services Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make food and retail serve finite nearby demand and make shortages actionable.
**Architecture:** Derive a deterministic service snapshot in TowerCore; consume it in tenant updates and cache it in GameController for all native feedback.
**Tech Stack:** Swift, Foundation, AppKit, XCTest; no dependencies.
**Spec:** ../specs/2026-10-18-neighborhood-services-design.md

## Global constraints
- Preserve saves, earned levels, existing corridors, macOS 13, and universal binaries.
- Food: ±4 floors; shops: ±6; horizontal center distance ≤48 cells.
- Restaurant/café/ramen/shop/bookshop capacity: 240/120/180/320/140.
- No revenue, travel generation, or incident-system redesign.

## Review focus
- Shared capacity cannot be consumed twice by overlapping catchments.
- Empty and disconnected consumers must not invent active demand.
- Incident and access changes must update both simulation and UI.
- UI rendering must not recompute allocation per room/frame.
- Native shortages must identify floors and provide working construction actions.

### Task 1: Derive and apply coverage
- [x] Add failing ServiceCoverageTests for the specified capacity, geometry, exclusion, conservation, and determinism contracts.
- [x] Create Sources/TowerCore/ServiceCoverage.swift: NeighborhoodService, ServiceAmount, VenueServiceLoad, NeighborhoodCoverage, and TowerState.neighborhoodCoverage.
- [x] Replace global food/retail comfort in Simulation.swift with this snapshot; add ordered service warnings in Incidents.swift.
- [x] Run targeted tests, then the full Swift suite; retain existing balance assertions where still applicable.

### Task 2: Make shortages actionable
- [x] Cache NeighborhoodCoverage on GameController during updateUI; pass it to all app signal calls.
- [x] Create ServiceCoverageUI.swift with consumer/provider details and grouped floor summaries; wire inspectors, Issues and Tower.
- [x] Show capacity and range in the room catalog; keep severity text accessible and actionable.
- [x] Add native checks for shortage copy, floor navigation, construction action, and recovery after adding capacity.

### Task 3: Verify and package
- [x] Inspect native previews of undersupplied and improved towers.
- [x] Review source, run full tests and native checks, document results and rules.
- [x] Build the next local app/ZIP version; verify signatures, architectures, macOS target, and disposable launch.

The user has requested implementation of the previously proposed coverage step. Routine numeric and implementation choices are recorded above; proceed in this chat. This checkout has no Git metadata, so commits are unavailable.

## Execution ledger
- Initial four simulation tests observed failing against global services, then passing with local finite coverage.
- Design review required residual reassignment for asymmetric overlapping catchments; added and verified a case where all 240 neighbors can be served only by reassignment.
- Ruling: vacant estimates divide reachable spare capacity by the room's full occupancy, independently, without reservations. This keeps empty rooms from inventing active demand.
- Ruling: preserve sad mood for already deeply unhappy tenants while showing an actionable shortage reason; existing incident regression caught the initial mood change.
- Full core suite: 194 tests passed. Native harness passed including grouped shortages, both build actions, room/provider inspectors, and immediate construction/demolition updates. Before/after previews inspected.
- No save schema change; real player saves untouched. Initial capacity and range values remain tuning choices.
- Independent fresh-context source review: no actionable defects. Final manual UI inspection found a shortcut overwriting the insufficient-funds message; native regression observed failing before adding a selected-tool guard.
- Final native regression passed, including insufficient funds. Universal v0.12.0/build 26 app and ZIP built; strict signature, ZIP integrity, both macOS 13 slices, and disposable packaged launch verified.
