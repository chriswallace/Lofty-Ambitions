# Elevator placement and collision checks

Approved user scope: elevators can be placed anywhere along the tower, but rooms must be demolished by the player before placing a shaft through them. Block construction until its complete path is clear.

## Approach

New elevators carry an optional `column:Int?`. Non-nil means the shaft occupies real buildable cells; nil preserves older saved elevators in their existing inserted central gap. New towers have no reserved central gap. Standard shafts reserve 3 cells (2 shaft + 1 landing), wide/express 5. Full floor spans, all rooms except ground lobby, and other placed shafts participate in collision checks, including floors where express cars do not stop. Legacy central gap cannot be crossed by a new placed shaft or room. Valid adjacent edges may touch. Existing saves remain compatible without moving their rooms.

## Shared interfaces

- Elevator.column:Int?; Elevator.footprintWidth:Int
- TowerState.legacyShaftWidth:Int
- TowerState.validateElevatorPlacement(_ kind:ElevatorKind,at column:Int,from:Int,to:Int,excludingID:Int?=nil) throws (geometry only plus shaft limit handled on new add)
- TowerState.addElevator(_ kind:ElevatorKind,at column:Int,from:Int,to:Int) throws
- TowerState.upgradeElevator(_ id:Int) throws
- TowerState.boardingColumn(for:Elevator)->Double
- Old addElevator(kind,from,to) chooses a valid free column for scripted scenarios; UI always supplies user column.
- Existing extendElevators validates every full proposed shaft before charging or changing any bank.

## Tasks

- [x] Core tests: rejection through rooms on any floor, no partial changes/charge, adjacency, shaft collisions, placement at multiple columns, room-vs-shaft blocking, no central reservation for new towers, extension and upgrade collisions, saved columns, legacy compatibility.
- [x] Core: implement geometry in ElevatorPlacement.swift; add optional column; update room validation, extensions and build rows. Preserve legacy nil geometry and old saves.
- [x] Transit: walk to the chosen bank and between separate banks; board only at that bank's position. Test trips and transfers at separated locations.
- [x] UI: user drag start sets shaft column; accurate ghost footprint and red/green status; blockers named in tooltip/banner; render/hit actual column and reserve width only for legacy gaps. Upgrade action uses core API. Update instructions.
- [x] Verification: all tests, independent review, native screenshot, universal app and signature check. Existing user towers remain untouched.

No git repository is present; edit this workspace directly and do not commit.

## Result

All 62 tests pass. Independent review completed; cap rendering finding fixed. Red/green native previews inspected. Universal app 0.4.0 and local signature verified. Populated legacy saves keep their central gap; new player-selected shafts occupy the chosen column.
