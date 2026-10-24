import Foundation

extension Elevator {
    /// Shaft body plus its one-cell landing; adjacent rooms may touch this edge.
    public var footprintWidth:Int { kind.width + 1 }
}

extension TowerState {
    /// Older saves inserted elevator banks at the core rather than consuming room cells.
    public var legacyShaftWidth:Int { elevators.filter { $0.column == nil }.reduce(0) { $0 + $1.footprintWidth } }
    public func boardingColumn(for lift:Elevator) -> Double {
        lift.column.map { Double($0 + lift.kind.width) + 0.5 } ?? Double(core)
    }
    func crossesLegacyCore(column:Int,width:Int) -> Bool {
        legacyShaftWidth > 0 && column < core && column+width > core
    }
    func shaftOverlapsRoom(floor:Int,column:Int,width:Int) -> Bool {
        elevators.contains { lift in
            guard let x=lift.column else { return false }
            return floor >= lift.bottom && floor <= lift.topFloor && column < x+lift.footprintWidth && column+width > x
        }
    }

    public func validateElevatorPlacement(_ kind:ElevatorKind,at column:Int,from:Int,to:Int,excludingID:Int? = nil) throws {
        let bottom=min(from,to),top=max(from,to),width=kind.width+1
        guard bottom >= bottomFloor,top <= topFloor,top > bottom else { throw TowerError("Drag over at least two built or excavated floors.") }
        guard top <= elevatorTopLimit(kind, from: bottom) else { throw TowerError("\(kind.title)s span at most \(kind.range) floors. Start another bank at a transfer floor.") }
        guard bottom <= 0 || bottom >= lobbyHeight else { throw TowerError("Start elevators underground, at G, or above the four-floor Grand Lobby.") }
        guard top <= 0 || top >= lobbyHeight else { throw TowerError("End elevators underground, at G, or on a room floor above the lobby.") }
        guard column >= -128,column <= 256-width else { throw TowerError("Keep the full shaft inside the building site.") }
        if kind == .express && (bottom < 0 || bottom != 0 && (bottom-lobbyRise)%15 != 0) { throw TowerError("Express service starts at the ground lobby or a 15-floor transfer floor. Use standard or wide elevators underground.") }
        guard !crossesLegacyCore(column:column,width:width) else { throw TowerError("This shaft would cross the existing central elevator banks.") }
        for floor in bottom...top {
            guard span(floor).contains(column,width:width) else { throw TowerError("Widen floor \(floor) to support the full shaft and landing.") }
            if let room=rooms.first(where: { $0.kind != .lobby && $0.floor == floor && column < $0.slot+$0.kind.width && column+width > $0.slot }) {
                throw TowerError("Demolish \(room.kind.title.lowercased()) unit \(room.id) on floor \(floor) to clear the shaft path.")
            }
        }
        for lift in elevators where lift.id != excludingID {
            guard let x=lift.column else { continue }
            if bottom <= lift.topFloor && top >= lift.bottom && column < x+lift.footprintWidth && column+width > x {
                throw TowerError("The shaft overlaps elevator \(lift.id). Choose a clear path.")
            }
        }
    }

    public mutating func addElevator(_ kind:ElevatorKind,at column:Int,from:Int,to:Int) throws {
        guard elevators.count < 12 else { throw TowerError("The tower supports up to 12 shafts.") }
        try validateElevatorPlacement(kind,at:column,from:from,to:to)
        guard cash >= kind.cost else { throw TowerError("\(kind.title) costs $\(kind.cost.formatted()).") }
        let bottom=min(from,to),top=max(from,to)
        var elevator=Elevator(id:(elevators.map(\.id).max() ?? 0)+1,topFloor:top,position:Double(bottom),direction:1,passengers:0)
        elevator.lobbyRise=lobbyRise;elevator.type=kind;elevator.bottomFloor=bottom;elevator.doorTime=0;elevator.column=column
        elevators.append(elevator);cash -= kind.cost
        reconcileTransit()
    }

    /// Convenience for scripted scenarios. Interactive construction always supplies a column.
    public mutating func addElevator(_ kind:ElevatorKind,from:Int,to:Int) throws {
        let candidates = [core] + Array(leftEdge...rightEdge).filter { $0 != core }
        for column in candidates where (try? validateElevatorPlacement(kind,at:column,from:from,to:to)) != nil {
            try addElevator(kind,at:column,from:from,to:to)
            return
        }
        // Report invalid floor/range requests precisely before a general blocked-path message.
        let bottom=min(from,to),top=max(from,to)
        if bottom < bottomFloor || top > topFloor || top <= bottom || top > elevatorTopLimit(kind, from: bottom) || (kind == .express && (bottom < 0 || bottom != 0 && (bottom-lobbyRise)%15 != 0)) {
            try validateElevatorPlacement(kind,at:core,from:from,to:to)
        }
        throw TowerError("No clear shaft path. Demolish blocking rooms or choose another column.")
    }

    public mutating func upgradeElevator(_ id:Int) throws {
        guard let index=elevators.firstIndex(where: { $0.id == id }) else { throw TowerError("Select an elevator first.") }
        let lift=elevators[index]
        guard lift.kind == .standard else { throw TowerError("Only standard cars can be upgraded to wide cars.") }
        if let column=lift.column {
            try validateElevatorPlacement(.wide,at:column,from:lift.bottom,to:lift.topFloor,excludingID:id)
        }
        guard cash >= 14000 else { throw TowerError("The upgrade costs $14,000.") }
        elevators[index].type = .wide;cash -= 14000
    }

    func validatePlacedElevators() throws {
        guard Set(elevators.map(\.id)).count == elevators.count else { throw TowerError("Invalid elevator identifiers.") }
        for lift in elevators {
            if let column=lift.column {
                try validateElevatorPlacement(lift.kind,at:column,from:lift.bottom,to:lift.topFloor,excludingID:lift.id)
            }
        }
    }
}

extension TowerState {
    public func validateElevatorRelocation(_ id: Int, at column: Int, from: Int, to: Int) throws {
        guard let lift = elevators.first(where: { $0.id == id }) else { throw TowerError("Select an elevator first.") }
        var proposed = self
        proposed.elevators.removeAll { $0.id == id }
        try proposed.validateElevatorPlacement(lift.kind, at: column, from: from, to: to)
        // Removing a legacy center shaft closes its visual gap. Rooms keep their cells.
        for room in rooms where room.kind != .lobby {
            guard !proposed.crossesLegacyCore(column: room.slot, width: room.kind.width) else {
                throw TowerError("This move would cross another central shaft.")
            }
        }
    }

    public mutating func relocateElevator(_ id: Int, at column: Int, from: Int, to: Int) throws {
        try validateElevatorRelocation(id, at: column, from: from, to: to)
        guard let index = elevators.firstIndex(where: { $0.id == id }) else { return }
        let old = elevators[index]
        elevators[index].column = column
        elevators[index].bottomFloor = min(from, to)
        elevators[index].topFloor = max(from, to)
        elevators[index].position = Double(min(from, to))
        elevators[index].targetFloor = nil
        elevators[index].doorTime = 0
        elevators[index].direction = 1
        reconcileTransit(afterChanging: old)
        releaseUnavailableCleaners()
        event("Elevator \(id) relocated.")
    }

    public mutating func removeElevator(_ id: Int) throws {
        guard let lift = elevators.first(where: { $0.id == id }) else { throw TowerError("Select an elevator first.") }
        elevators.removeAll { $0.id == id }
        cash += lift.kind.cost / 2
        reconcileTransit(afterChanging: lift)
        releaseUnavailableCleaners()
        event("Elevator \(id) removed. $\((lift.kind.cost / 2).formatted()) refunded.")
    }

    /// Disembark riders of the edited car at its nearest old landing, then
    /// plan fresh journeys. A disconnected sampled journey is safely cancelled.
    mutating func reconcileTransit(afterChanging old: Elevator? = nil) {
        var updated: [Traveler] = []
        for var person in activeTravelers {
            if let old, person.elevatorID == old.id {
                guard let landing = old.stops.min(by: { abs(Double($0)-old.position) < abs(Double($1)-old.position) }) else { continue }
                person.floor = landing
                person.x = boardingColumn(for: old)
                person.elevatorID = nil
                person.phase = .walkingToLift
            }
            person.boardingElevatorID = nil
            if person.phase != .riding {
                guard let path = route(from: person.floor, to: person.destination) else { continue }
                person.route = path
                person.phase = path.isEmpty ? .walkingToRoom : .walkingToLift
            }
            updated.append(person)
        }
        travelers = updated
        recountElevatorPassengers()
    }
}
