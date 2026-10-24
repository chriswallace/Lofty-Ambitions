# Lofty Ambitions — game design

A native tower management game with a cutaway view, flexible construction, and simulated passenger journeys.

## Presentation

Native AppKit window with compact gray controls, an optional room/elevator inspector, and most of the window devoted to the tower. Original Tokyo-inspired pixel-art room interiors render with nearest-neighbor scaling. World dimensions are eight pixels per construction cell and 24 pixels per floor. Rooms have different widths.

## Construction

Each floor stores independent left/right extents. Players can drag to construct/extend floors, widen the whole tower to either side, and drag to build rows of rooms. Upper floors require support below. Room placement checks footprint, room/shaft overlap, legacy bank gaps, availability and funds. Row construction and whole-tower widening are atomic when funds or geometry are invalid.

## Transit

Travelers walk from their origin toward the lift bank, wait, board open cars subject to capacity, ride to requested stops, transfer where needed, and walk from the last stop to their destination. Actual queue pressure influences happiness. A deterministic traffic generator creates representative journeys rather than assigning one persistent traveler to every occupant in the population total.

Standard and wide banks span up to 30 served floors. They carry 12 and 24 passengers respectively. Express cars carry 32, move faster, and stop at the ground lobby and 15-floor intervals. Breadth-first routing finds transfer paths through supported floors. Cars dispatch to pickups/drop-offs rather than continuously bouncing between endpoints. They dwell at stops with visible doors and passengers.

New shafts occupy a player-selected column and consume 3 cells for standard or 5 for wide/express, including the landing. Their full vertical footprint must fit every floor and clear all rooms and shafts, including express pass-through floors. Extensions and upgrades validate before applying any charges or mutations. Old nil-column shafts keep the inserted central gap so older saves load unchanged. Passengers walk to their chosen bank and between transfer banks. Express stop customization, service elevators, and a dedicated sky-lobby room remain future work.

## Persistence and verification

The deterministic Codable simulation is shared by both platforms. `TowerSession` provides atomic commands, speed control, recovery policy, and replay. `TowerPresentation` emits scene commands from the same atlas and geometry; AppKit and SDL draw those commands. Native Mac and portable desktop controls adapt to each platform. Saves include room occupancy, rent, floors, elevators, and active journeys. Autosave and manual save/open remain available. Tests cover construction geometry/costs, funds, traffic capacity, stop behavior, transfers, progression, migration, and persistence. The Mac app targets Apple Silicon and Intel on macOS 13+. The Windows frontend targets Windows 11 x64; its first PC build and clean-machine validation remain pending. One `VERSION`, shared replay snapshots, and a two-OS CI workflow keep builds synchronized.

## Artwork and simulation

Runtime artwork is original to this project. The simulation is implemented in Swift, with documented game rules and JSON save files.

## Room incidents

Each room optionally stores a Codable incident. Older saves omit this field and load normally. Incidents advance through explicit minute-based stages in `Incidents.swift`; one shared signal supplies the renderer and native inspector. Party damage and fires close the room to visitors and income; rent arrears freeze tenancy and accrue unpaid rent through a timed notice, court, and eviction process. Active fire rooms are evacuated, and burned service facilities stop contributing amenities and star requirements.

Housekeeping is assigned by service access, distance, and team availability. FD response selects ladder access through floor 7 and an interior stair response above it. Fire severity sets repair cost; this first implementation models room-local fires without spread. Every incident has a visible expression bubble. Selection/hover expands text; the inspector and room issue list offer accessible native controls. Pixel effects use game time and freeze when paused, with reduced-motion rendering supported.

## New tower starting state

New Tower begins with a ground-floor lobby, $180,000, and no upper floors, tenants, or elevators. A blank tower is a valid save. The populated layout is exposed only by `demoTower()` for explicit scenario launches and existing simulation test fixtures. Existing saved towers retain their contents.

## Apartment leasing policies

Each apartment saves optional background-check and deposit requirements. Defaults (including old saves) are Standard checks and no deposit, preserving original move-in speed and default behavior. Thorough/Strict checks multiply move-ins by 0.7/0.4 and incoming default risk by 0.6/0.3. One-/two-month deposits multiply move-ins by 0.85/0.65 and incoming default risk by 0.8/0.6. The two choices multiply together; they do not change happiness, equilibrium demand, or move-out speed. Deposits are modeled as an admission requirement and do not credit the treasury.

A saved occupancy-weighted risk tracks actual admitted tenants. Changing a policy affects future admissions without retroactively rescreening occupants or resolving arrears. Proportional departures retain the cohort's average risk, while an empty unit's next admission starts with its new policy risk. Natural default opportunities use a stable room/day draw against that tenant risk; screening skips defaults instead of redirecting them to another apartment. Sandbox incident triggers remain explicit overrides.
