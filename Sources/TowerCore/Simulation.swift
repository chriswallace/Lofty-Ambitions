import Foundation

public enum RoomKind: String, Codable, CaseIterable, Sendable {
    case lobby, office, apartment, restaurant, shop, hotel, housekeeping, security, garden, cafe, arcade, fitness, observatory, ramen, bookshop, coworking, spa, luxuryApartment
    public var definition: RoomDefinition { RoomCatalog.definition(for: self) }
    public var title: String { definition.title }
    public var symbol: String { definition.symbol }
    public var cost: Int { definition.cost }
    public var width: Int { definition.width }
    public var capacity: Int { definition.capacity }
    public var dailyRent: Int { definition.dailyRent }
    public var upkeep: Int { definition.upkeep }
    public var requiredStars: Int { definition.requiredStars }
    public var detail: String { definition.detail }
    public var providesFood: Bool { self == .restaurant || self == .cafe || self == .ramen }
    public var providesRetail: Bool { self == .shop || self == .bookshop }
    public var happinessBonus: Double {
        switch self {
        case .arcade: return 0.02
        case .fitness, .spa: return 0.03
        case .observatory: return 0.04
        default: return 0
        }
    }

}
public struct Room: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: RoomKind
    public var floor: Int
    public var slot: Int
    public var occupancy: Double
    public var rent: Double
    public var happiness: Double
    public var style: RoomStyle? = nil
    public var incident: RoomIncident? = nil
    public var screening: TenantScreening? = nil
    public var depositRequirement: ApartmentDeposit? = nil
    public var tenantDefaultRisk: Double? = nil
    public var people: Int { Int((Double(kind.capacity) * occupancy).rounded()) }
}
public struct Elevator: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var topFloor: Int
    public var position: Double
    public var direction: Int
    public var passengers: Int
    public var column: Int? = nil
    public var type: ElevatorKind? = nil
    public var bottomFloor: Int? = nil
    public var lobbyRise: Int? = nil
    public var targetFloor: Int? = nil
    public var doorTime: Int? = nil
}
public struct DailyReport: Codable, Equatable, Sendable {
    public var day: Int
    public var income: Int
    public var expenses: Int
    public var population: Int
    public var profit: Int { income - expenses }
}
public struct TowerError: Error, LocalizedError {
    public var message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public struct TowerState: Codable, Sendable {
    public static let floorCost = 8000
    public static let elevatorCost = 18000
    public static let maxFloor = 100
    public var version = 2
    /// Optional only for backward-compatible decoding of earlier saves.
    public var scenerySeed: UInt64? = nil
    public var lobbyStyle: LobbyStyle? = nil
    public var lobbyFloorCount: Int? = nil
    public var citySeed: UInt64 { scenerySeed ?? 0x544F4B594F }
    public var floorSpans: [Int:FloorSpan]? = nil
    public var coreColumn: Int? = nil
    public var travelers: [Traveler]? = nil
    public var nextTravelerID: Int? = nil
    public var tripsCompleted: Int? = nil
    public var progression: TowerProgressionState? = nil
    public var name = "New Horizon"
    public var cash: Int = 180000
    public var day = 1
    public var minute = 480
    public var topFloor = 0
    /// Optional so towers saved before underground construction still decode.
    public var basementFloorCount: Int? = nil
    public var rooms: [Room] = []
    public var elevators: [Elevator] = []
    public var history: [DailyReport] = []
    public var earnedStars = 1
    public var nextID = 1
    public var dailyIncome = 0.0
    public var dailyExpenses = 0.0
    public var events: [String] = ["Welcome to New Horizon. Build your first floor, add rooms, then connect an elevator."]

    public static func newGame(scenerySeed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> TowerState {
        var s = TowerState()
        s.scenerySeed = scenerySeed
        s.floorSpans = [0:FloorSpan(0,64)]
        s.coreColumn = 32; s.travelers = []; s.nextTravelerID = 1; s.tripsCompleted = 0
        s.rooms = [Room(id:1,kind:.lobby,floor:0,slot:0,occupancy:0,rent:1,happiness:0.8)]
        s.nextID = 2
        return s
    }

    /// A populated scenario for the explicitly requested incident/transport demos.
    public static func demoTower() -> TowerState {
        var s = TowerState()
        s.scenerySeed = 20260920
        s.topFloor = 4
        s.events = ["Demo tower. Inspect rooms to explore the simulation."]
        s.floorSpans = Dictionary(uniqueKeysWithValues:(0...s.topFloor).map { ($0,FloorSpan(0,64)) })
        s.coreColumn = 32; s.travelers = []; s.nextTravelerID = 1; s.tripsCompleted = 0
        let starter: [(RoomKind, Int, Int)] = [(.lobby,0,0),(.shop,1,0),(.restaurant,1,32),(.office,2,0),(.office,2,9),(.office,2,18),(.office,2,32),(.office,2,41),(.apartment,3,0),(.apartment,3,4),(.apartment,3,8),(.apartment,3,12),(.apartment,3,32),(.apartment,3,36),(.office,4,0),(.office,4,9),(.office,4,32)]
        s.rooms = starter.map { kind, floor, slot in
            defer { s.nextID += 1 }
            return Room(id:s.nextID, kind:kind, floor:floor, slot:slot, occupancy:kind.capacity > 0 ? 0.55 : 0, rent:1, happiness:0.8)
        }
        s.elevators = [Elevator(id:1, topFloor:4, position:0, direction:1, passengers:0)]
        return s
    }
    public var population: Int { rooms.reduce(0) { $0 + $1.people } }
    public var capacity: Int { rooms.reduce(0) { $0 + $1.kind.capacity } }
    public var happiness: Double {
        let tenants = rooms.filter { $0.kind.capacity > 0 }
        return tenants.isEmpty ? 0 : tenants.reduce(0) { $0 + $1.happiness } / Double(tenants.count)
    }
    public var stars: Int { earnedStars }
    public var nextPopulation: Int { nextLevel?.population ?? level.population }
    public var transportLoad: Double {
        Double(queueCount) / Double(max(1,elevators.reduce(0) { $0+$1.capacity }))
    }
    public var waitSeconds: Int {
        let waiting=activeTravelers.filter { $0.phase == .waiting }
        return waiting.isEmpty ? 0 : waiting.reduce(0) { $0+$1.waited }*60/waiting.count
    }
    public var projectedIncome: Int {
        let bonuses = progressionIncomeBonuses
        return rooms.reduce(0) { $0 + income(for: $1, bonus: bonuses[$1.id, default: 0]) }
    }
    public var projectedExpenses: Int { rooms.reduce(0) { $0 + $1.kind.upkeep } + lobbyExtraUpkeep + elevators.count * 200 + (max(0, topFloor-lobbyRise) + basementDepth) * 60 }
    public var clock: String { String(format:"%02d:%02d", minute / 60, minute % 60) }
    public var nextGoal: String {
        if topFloor == 0 { return "Build your first floor, add rooms, and connect an elevator to welcome tenants." }
        guard let next = nextLevel else { return "Level 5: Skyline icon. Every room is unlocked. Keep your city thriving." }
        let facility = next.facility.map { ", and operational \($0.title.lowercased())" } ?? ""
        return "Level \(next.number): reach \(next.population.formatted()) people, \(Int(next.happiness * 100))% happiness\(facility). Unlocks \(next.unlockTitles.joined(separator: ", "))."
    }

    public func isConnected(_ floor: Int) -> Bool { reachableFloors.contains(floor) }
    public func room(at floor: Int, slot: Int) -> Room? {
        if floor >= 0 && floor < lobbyHeight { return span(0).contains(slot) ? rooms.first { $0.kind == .lobby } : nil }
        return rooms.first { $0.floor == floor && slot >= $0.slot && slot < $0.slot + $0.kind.width }
    }
    public func issue(for room: Room) -> String? {
        if let incident = room.incident, incident.isActive { return incident.title }
        if !isConnected(room.floor) { return "No elevator access. Extend the lifts to this floor." }
        if room.kind == .hotel && !hasHotelService(room) { return "Needs available housekeeping within 5 floors; one team supports 6 suites." }
        if room.rent > 1.3 { return "High rent is reducing demand." }
        if transportLoad > 1.1 && room.kind.capacity > 0 { return "Long elevator waits. Add another lift." }
        return nil
    }
    public func validateBuild(_ kind: RoomKind, floor: Int, slot: Int) throws {
        guard kind != .lobby else { throw TowerError("Your tower already has a lobby.") }
        guard stars >= kind.requiredStars else { throw TowerError("Unlocks at level \(kind.requiredStars).") }
        guard floor >= bottomFloor && floor <= topFloor && floor != 0 else { throw TowerError("Build or excavate a floor here first.") }
        guard floor < 0 || floor >= lobbyHeight else { throw TowerError("Floors G–3 belong to the Grand Lobby. Build rooms on floor 4 or above.") }
        guard floor >= 0 || kind.canBuildUnderground else { throw TowerError("\(kind.title) needs an above-ground floor. Basements welcome shops, dining, services, and indoor leisure.") }
        guard span(floor).contains(slot,width:kind.width) else { throw TowerError("Keep the whole room inside the building.") }
        guard !crossesLegacyCore(column:slot,width:kind.width) else { throw TowerError("Rooms cannot cross the existing central elevator banks.") }
        guard !shaftOverlapsRoom(floor:floor,column:slot,width:kind.width) else { throw TowerError("This room overlaps an elevator shaft or landing.") }
        if rooms.contains(where: { $0.floor == floor && slot < $0.slot + $0.kind.width && slot + kind.width > $0.slot }) {
            let occupied = rooms.filter { $0.floor == floor }.reduce(0) { $0 + $1.kind.width }
                + elevators.filter { $0.column != nil && floor >= $0.bottom && floor <= $0.topFloor }.reduce(0) { $0 + $1.footprintWidth }
            if occupied >= span(floor).width {
                throw TowerError("Floor \(floor) is full (\(span(floor).width) cells). \(Self.buildingLimitsDescription)")
            }
            throw TowerError("This space is already occupied.")
        }
        guard cash >= kind.cost else { throw TowerError("You need $\(kind.cost.formatted()) to build this room.") }
    }
    @discardableResult public mutating func build(_ kind: RoomKind, floor: Int, slot: Int) throws -> Int {
        try validateBuild(kind, floor:floor, slot:slot)
        let style = nextRoomStyle(kind, floor: floor, slot: slot)
        let id = nextID; nextID += 1
        rooms.append(Room(id:id,kind:kind,floor:floor,slot:slot,occupancy:0,rent:1,happiness:0.75,style:style))
        cash -= kind.cost
        return id
    }
    public mutating func addFloor() throws {
        guard topFloor < Self.maxFloor else { throw TowerError("Maximum height reached: \(Self.maxFloor) floors above ground. Widen existing floors up to \(Self.maxFloorWidth) cells for more room space.") }
        guard cash >= Self.floorCost else { throw TowerError("A new floor costs $8,000.") }
        let newSpan = span(topFloor)
        if floorSpans == nil { floorSpans = Dictionary(uniqueKeysWithValues:(0...topFloor).map { ($0,span($0)) }) }
        cash -= Self.floorCost; topFloor += 1; floorSpans?[topFloor] = newSpan
    }
    public var extensionCost: Int { elevators.reduce(0) { $0 + max(0, min(topFloor,elevatorTopLimit($1.kind, from: $1.bottom)) - $1.topFloor) * 1200 } }
    public mutating func extendElevators() throws {
        let cost = extensionCost
        guard cost > 0 else { throw TowerError("All elevators already reach the top floor.") }
        guard cash >= cost else { throw TowerError("Extending the lifts costs $\(cost.formatted()).") }
        var proposed = self
        for i in proposed.elevators.indices {
            let lift = proposed.elevators[i]
            let top = min(topFloor,elevatorTopLimit(lift.kind, from: lift.bottom))
            if let column = lift.column {
                try proposed.validateElevatorPlacement(lift.kind,at:column,from:lift.bottom,to:top,excludingID:lift.id)
            }
            proposed.elevators[i].topFloor = top
        }
        proposed.cash -= cost
        self = proposed
    }
    public mutating func addElevator() throws {
        try addElevator(.standard,from:0,to:min(topFloor,elevatorTopLimit(.standard, from: 0)))
    }
    public mutating func demolish(_ id: Int) throws {
        let quote = try demolitionQuote(for: .room(id))
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { throw TowerError("Select a room first.") }
        cash += quote.refund
        rooms.remove(at:index)
        releaseUnavailableCleaners()
        travelers?.removeAll { $0.roomID == id }
        for i in elevators.indices { elevators[i].passengers = activeTravelers.filter { $0.elevatorID == elevators[i].id }.count }
    }
    public mutating func setRent(_ id: Int, value: Double) {
        guard value.isFinite, let i = rooms.firstIndex(where: { $0.id == id }) else { return }
        rooms[i].rent = min(1.6,max(0.6,value))
    }
    public mutating func advance(minutes: Int) {
        guard minutes > 0 else { return }
        for _ in 0..<minutes { tick() }
    }
    private mutating func tick() {
        minute += 1
        if minute % 30 == 0 { updateTenants() }
        updateIncidents()
        dailyIncome += Double(projectedIncome) / 1440
        dailyExpenses += Double(projectedExpenses) / 1440
        updateTransit()
        if minute >= 1440 {
            let report = DailyReport(day:day,income:Int(dailyIncome),expenses:Int(dailyExpenses),population:population)
            history.append(report); if history.count > 30 { history.removeFirst() }
            cash += report.profit
            dailyIncome = 0; dailyExpenses = 0; minute = 0; day += 1
            event("Day \(report.day): \(report.profit >= 0 ? "+" : "−")$\(abs(report.profit).formatted()) operating profit.")
        }
        evaluateLevel()
        evaluateAmbitions()
    }
    private mutating func updateTenants() {
        let coverage = neighborhoodCoverage
        let garden = rooms.contains { $0.kind == .garden && $0.incident?.isActive != true && isConnected($0.floor) }
        let security = rooms.contains { $0.kind == .security && $0.incident?.isActive != true && isConnected($0.floor) }
        let leisureBonus = RoomKind.allCases.filter { $0.happinessBonus > 0 }.reduce(0.0) { bonus, kind in
            bonus + (rooms.contains { $0.kind == kind && $0.incident?.isActive != true && isConnected($0.floor) } ? kind.happinessBonus : 0)
        }
        let servicedHotels = hotelServiceAssignments
        let connectedFloors = reachableFloors
        let congestion = min(0.4,max(0, transportLoad - 0.7) * 0.12)
        for i in rooms.indices where rooms[i].kind.capacity > 0 {
            let room = rooms[i]
            let connected = connectedFloors.contains(room.floor)
            if let incident = room.incident, incident.isActive {
                rooms[i].happiness = incident.kind == .fire ? 0.05 : 0.3
                continue
            }
            let serviced = room.kind != .hotel || servicedHotels[room.id] != nil
            let food = room.kind.needsNeighborhoodServices ? (coverage.rooms[room.id]?[.food]?.ratio ?? 0) : 1
            let shops = room.kind.needsNeighborhoodServices ? (coverage.rooms[room.id]?[.shops]?.ratio ?? 0) : 1
            var comfort = 0.76 - 0.08 + 0.14 * food + 0.04 * shops + (garden ? 0.08 : 0) + (security ? 0.04 : 0)
            comfort += leisureBonus + lobbyHappinessBonus
            comfort -= congestion + max(0, room.rent - 1) * 0.5
            if !serviced { comfort -= 0.4 }
            if isDisturbedByParty(room) { comfort -= 0.25 }
            if !connected { comfort = 0.1 }
            comfort = min(0.99,max(0.05,comfort))
            rooms[i].happiness = comfort
            let target = connected ? min(1,max(0,comfort + 0.16 - max(0,room.rent - 1) * 0.5)) : 0
            let moveInLimit = 0.028 * (room.kind.isApartment ? room.applicantMoveInMultiplier : 1) * (abilityRemainingMinutes(.openHouse) > 0 ? 2 : 1)
            let change = min(moveInLimit,max(-0.06,target - room.occupancy))
            if room.kind.isApartment && change > 0 {
                let risk = (room.effectiveDefaultRisk * room.occupancy + room.newTenantDefaultRisk * change) / (room.occupancy + change)
                rooms[i].tenantDefaultRisk = min(1,max(0,risk))
            }
            rooms[i].occupancy += change
            rooms[i].occupancy = min(1,max(0,rooms[i].occupancy))
        }
    }
    mutating func event(_ text: String) { events.insert(text,at:0); if events.count > 20 { events.removeLast() } }
    public func validated() throws -> TowerState {
        var result = self
        if result.scenerySeed == nil {
            // Stable migration: reopening the same old file must not reroll its city.
            let identity = "\(name)|\(day)|\(cash)|" + rooms.sorted { $0.id < $1.id }.map { "\($0.id):\($0.kind.rawValue):\($0.floor):\($0.slot)" }.joined(separator: ",")
            result.scenerySeed = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        guard version == 1 || version == 2 else { throw TowerError("This save version is not supported.") }
        guard topFloor >= 0,topFloor <= Self.maxFloor,minute >= 0,minute < 1440,day > 0,earnedStars >= 1,earnedStars <= 5,
              rooms.count <= Self.maximumRoomCapacity + 1,elevators.count <= 12,
              dailyIncome.isFinite,dailyExpenses.isFinite else { throw TowerError("This save contains an invalid tower.") }
        if version == 1 {
            result.version = 2; result.coreColumn = 60
            result.floorSpans = Dictionary(uniqueKeysWithValues:(0...topFloor).map { ($0,FloorSpan(0,120)) })
            for i in result.rooms.indices {
                guard (0...12).contains(result.rooms[i].slot) else { throw TowerError("Invalid legacy room.") }
                result.rooms[i].slot *= 10
            }
            result.travelers = [];result.nextTravelerID = 1;result.tripsCompleted = 0
            for i in result.elevators.indices { result.elevators[i].passengers = 0;result.elevators[i].topFloor = min(29,result.elevators[i].topFloor);result.elevators[i].position = min(Double(result.elevators[i].topFloor),result.elevators[i].position) }
        }
        guard result.core >= -128,result.core <= 256,Set(result.rooms.map(\.id)).count == result.rooms.count,
              result.nextID > (result.rooms.map(\.id).max() ?? 0),result.rooms.filter({ $0.kind == .lobby }).count == 1 else { throw TowerError("Invalid room identifiers.") }
        try result.validateUnderground()
        for floor in result.bottomFloor...result.topFloor {
            let span = result.span(floor)
            guard span.left >= -128,span.right <= 256,span.width > 0,span.width <= 256 else { throw TowerError("Invalid floor width.") }
            if floor > 0 { let below = result.span(floor-1);guard span.left >= below.left,span.right <= below.right else { throw TowerError("A floor is missing support.") } }
            if floor < 0 { let above = result.span(floor+1);guard span.left >= above.left,span.right <= above.right else { throw TowerError("An underground floor extends beyond the floor above.") } }
        }
        guard [1,4].contains(result.lobbyHeight), result.lobbyHeight == 1 || (result.effectiveLobbyStyle == .grand && result.topFloor >= 3) else { throw TowerError("Invalid lobby height.") }
        for floor in 0..<result.lobbyHeight {
            guard result.span(floor) == result.span(0) else { throw TowerError("Grand Lobby floors must have the same width.") }
        }
        var occupiedCells: [Int: Set<Int>] = [:]
        for room in result.rooms {
            guard room.style == nil || room.kind.hasStyles else { throw TowerError("Invalid room interior style.") }
            guard room.floor >= result.bottomFloor,room.floor <= topFloor,room.occupancy.isFinite,(0...1).contains(room.occupancy),room.rent.isFinite,(0.6...1.6).contains(room.rent),room.happiness.isFinite,(0...1).contains(room.happiness) else { throw TowerError("Invalid room data.") }
            if room.kind == .lobby { guard room.floor == 0 else { throw TowerError("Invalid lobby.") };continue }
            guard (room.floor < 0 && room.kind.canBuildUnderground || room.floor >= result.lobbyHeight),result.span(room.floor).contains(room.slot,width:room.kind.width),!result.crossesLegacyCore(column:room.slot,width:room.kind.width) else { throw TowerError("A room lies outside its permitted floor.") }
            for cell in room.slot..<(room.slot + room.kind.width) {
                guard occupiedCells[room.floor, default: []].insert(cell).inserted else { throw TowerError("Rooms overlap in this save.") }
            }
        }
        for lift in result.elevators {
            guard (lift.lobbyRise ?? 0) == result.lobbyRise else { throw TowerError("Invalid elevator lobby clearance.") }
            guard lift.bottom >= result.bottomFloor,lift.topFloor <= topFloor,lift.topFloor >= lift.bottom,lift.position.isFinite,(Double(lift.bottom)...Double(lift.topFloor)).contains(lift.position),(lift.direction == 1 || lift.direction == -1) else { throw TowerError("Invalid elevator.") }
        }
        guard result.activeTravelers.count <= 1000 else { throw TowerError("Too many active travelers.") }
        for person in result.activeTravelers {
            guard person.x.isFinite,person.destinationX.isFinite,person.floor >= result.bottomFloor,person.floor <= topFloor,person.destination >= result.bottomFloor,person.destination <= topFloor else { throw TowerError("Invalid traveler.") }
        }
        try result.validatePlacedElevators()
        try result.validateApartmentPolicies()
        try result.validateIncidents()
        try result.validateProgression()
        return result
    }
}
