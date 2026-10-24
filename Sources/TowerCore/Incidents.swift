import Foundation

public enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case party, rentArrears, fire
}
public enum IncidentStage: String, Codable, Sendable {
    case partying, awaitingCleaning, cleaning
    case rentOverdue, noticeServed, courtPending, evictionApproved, evicting
    case burning, dispatched, extinguishing, awaitingRepairs, repairing, resolved
}
public enum FireResponseRoute: String, Codable, Sendable { case ladder, interior }
public enum RoomMood: String, Sendable { case angry, annoyed, worried, alarmed, sad, relieved, busy }
public struct RoomSignal: Equatable, Sendable {
    public var mood: RoomMood
    public var text: String
    public var symbol: String
}
public struct RoomIncident: Codable, Equatable, Sendable {
    public var kind: IncidentKind
    public var stage: IncidentStage
    public var remainingMinutes: Int = 0
    public var durationMinutes: Int = 0
    public var severity: Double = 0
    public var arrears: Double = 0
    public var responderRoomID: Int? = nil
    public var responseRoute: FireResponseRoute? = nil
    public var isActive: Bool { stage != .resolved }
    public var progress: Double {
        durationMinutes > 0 ? min(1,max(0,1 - Double(remainingMinutes)/Double(durationMinutes))) : 0
    }
    public var title: String {
        switch stage {
        case .partying: return "Noisy hotel party"
        case .awaitingCleaning: return "Suite trashed"
        case .cleaning: return "Housekeeping at work"
        case .rentOverdue: return "Unpaid rent"
        case .noticeServed: return "Payment notice served"
        case .courtPending: return "Court proceedings"
        case .evictionApproved: return "Eviction order granted"
        case .evicting: return "Eviction in progress"
        case .burning: return "Room on fire"
        case .dispatched: return "Firefighters responding"
        case .extinguishing: return "Firefighters extinguishing"
        case .awaitingRepairs: return "Fire damage"
        case .repairing: return "Repairs in progress"
        case .resolved: return "Issue resolved"
        }
    }
    mutating func transition(to next: IncidentStage, minutes: Int = 0) {
        stage = next; remainingMinutes = minutes; durationMinutes = minutes
    }
}
public enum IncidentAction: String, CaseIterable, Sendable {
    case sendHousekeeping, serveNotice, fileCourtCase, evict, dispatchFireDepartment, repair
    public var title: String {
        switch self {
        case .sendHousekeeping: return "Send housekeeping"
        case .serveNotice: return "Serve payment notice"
        case .fileCourtCase: return "File court case · $500"
        case .evict: return "Enforce eviction order"
        case .dispatchFireDepartment: return "Dispatch FD · $1,500 billed"
        case .repair: return "Repair room"
        }
    }
}

extension TowerState {
    public static let ladderReach = 7
    static func fireResponseRoute(for floor: Int) -> FireResponseRoute {
        floor >= 0 && floor <= ladderReach ? .ladder : .interior
    }
    static func fireResponseMinutes(for floor: Int) -> Int {
        fireResponseRoute(for: floor) == .ladder ? 30 : 60 + abs(floor) * 3
    }

    public func income(for room: Room) -> Int {
        let bonus = room.floor < 0 && room.kind.definition.category == .commerce ? progressionIncomeBonuses[room.id, default: 0] : 0
        return income(for: room, bonus: bonus)
    }
    func income(for room: Room, bonus: Double) -> Int {
        guard room.incident?.isActive != true else { return 0 }
        return Int(Double(room.kind.dailyRent) * room.occupancy * room.rent * (1 + bonus))
    }
    public func signal(for room: Room, coverage: NeighborhoodCoverage? = nil) -> RoomSignal? {
        if let incident = room.incident {
            let mood: RoomMood, text: String, symbol: String
            switch incident.stage {
            case .partying: (mood,text,symbol) = (.angry,"Keep it down!","music.note")
            case .awaitingCleaning: (mood,text,symbol) = (.annoyed,"What a mess!","sparkles")
            case .cleaning: (mood,text,symbol) = (.busy,"Housekeeping is here","sparkles")
            case .rentOverdue: (mood,text,symbol) = (.worried,"Rent is overdue","banknote")
            case .noticeServed: (mood,text,symbol) = (.worried,incident.remainingMinutes > 0 ? "Payment notice received":"Notice expired · court available","envelope")
            case .courtPending: (mood,text,symbol) = (.sad,"Waiting for the court","building.columns")
            case .evictionApproved: (mood,text,symbol) = (.sad,"Court ordered eviction","building.columns")
            case .evicting: (mood,text,symbol) = (.sad,"Moving out…","shippingbox")
            case .burning: (mood,text,symbol) = (.alarmed,"Fire! Call the FD!","flame.fill")
            case .dispatched: (mood,text,symbol) = (.alarmed,"Firefighters on the way!","truck.box.fill")
            case .extinguishing: (mood,text,symbol) = (.busy,"Firefighters are here!","drop.fill")
            case .awaitingRepairs: (mood,text,symbol) = (.sad,"We need repairs","hammer")
            case .repairing: (mood,text,symbol) = (.busy,"Repairs underway","hammer")
            case .resolved: (mood,text,symbol) = (.relieved,incident.kind == .rentArrears ? "Ready for new tenants":"All better!","checkmark")
            }
            return RoomSignal(mood:mood,text:text,symbol:symbol)
        }
        if let warning = issue(for:room) {
            let mood:RoomMood = room.rent > 1.3 ? .angry : .annoyed
            let symbol = !isConnected(room.floor) ? "arrow.up.arrow.down" : room.kind == .hotel && !hasHotelService(room) ? "sparkles" : room.rent > 1.3 ? "banknote" : "clock"
            return RoomSignal(mood:mood,text:warning,symbol:symbol)
        }
        if isDisturbedByParty(room) { return RoomSignal(mood:.angry,text:"That party is too loud!",symbol:"music.note") }
        if let warning = serviceWarning(for: room, coverage: coverage ?? neighborhoodCoverage) { return warning }
        if room.people > 0 && room.happiness < 0.65 {
            return RoomSignal(mood:room.happiness < 0.4 ? .sad : .annoyed,text:room.happiness < 0.4 ? "I'm unhappy here":"This place could be better",symbol:"ellipsis")
        }
        return nil
    }
    func isDisturbedByParty(_ room: Room) -> Bool {
        room.kind.capacity > 0 && rooms.contains { $0.id != room.id && $0.floor == room.floor && $0.incident?.stage == .partying }
    }
    /// Assign each connected suite one of six local service slots. Serving the
    /// lowest floors first preserves the teams with reach into higher floors.
    var hotelServiceAssignments: [Int: Int] {
        let connected = reachableFloors
        let cleaners = rooms.filter { $0.kind == .housekeeping && $0.incident?.isActive != true && connected.contains($0.floor) }
            .sorted { ($0.floor, $0.id) < ($1.floor, $1.id) }
        let hotels = rooms.filter { $0.kind == .hotel && connected.contains($0.floor) && !($0.incident?.kind == .fire && $0.incident?.isActive == true) }
            .sorted { ($0.floor, $0.id) < ($1.floor, $1.id) }
        var assigned: [Int: Int] = [:], used: [Int: Int] = [:]
        for hotel in hotels {
            if let cleaner = cleaners.first(where: { abs($0.floor-hotel.floor) <= 5 && used[$0.id, default: 0] < 6 }) {
                assigned[hotel.id] = cleaner.id
                used[cleaner.id, default: 0] += 1
            }
        }
        return assigned
    }
    func hasHotelService(_ room: Room) -> Bool {
        room.kind != .hotel || hotelServiceAssignments[room.id] != nil
    }
    public func repairCost(for room: Room) -> Int {
        1500 + Int((room.incident?.severity ?? 0) * 6000)
    }
    public func incidentActions(for room: Room) -> [IncidentAction] {
        guard let incident = room.incident else { return [] }
        switch incident.stage {
        case .awaitingCleaning: return [.sendHousekeeping]
        case .rentOverdue: return [.serveNotice]
        case .noticeServed: return [.fileCourtCase]
        case .evictionApproved: return [.evict]
        case .burning: return [.dispatchFireDepartment]
        case .awaitingRepairs: return [.repair]
        default: return []
        }
    }
    private func availableCleaner(for room: Room) -> Room? {
        guard isConnected(room.floor) else { return nil }
        let busy = Set(rooms.compactMap { $0.incident?.stage == .cleaning ? $0.incident?.responderRoomID : nil })
        return rooms.first { $0.kind == .housekeeping && $0.incident?.isActive != true && abs($0.floor-room.floor) <= 5 && isConnected($0.floor) && !busy.contains($0.id) }
    }
    public func responseBlocker(for room: Room, action: IncidentAction) -> String? {
        guard incidentActions(for:room).contains(action) else { return "This response is not available at this stage." }
        switch action {
        case .sendHousekeeping:
            if availableCleaner(for:room) == nil { return "Needs an available housekeeping team within 5 floors and elevator access to both rooms." }
        case .fileCourtCase:
            if (room.incident?.remainingMinutes ?? 0) > 0 { return "Wait for the one-day payment notice to expire." }
            if cash < 500 { return "Court filing costs $500." }
        case .repair:
            if cash < repairCost(for:room) { return "Repairs cost $\(repairCost(for:room).formatted())." }
        default: break
        }
        return nil
    }
    public mutating func triggerIncident(_ kind: IncidentKind, roomID: Int) throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { throw TowerError("Select a room first.") }
        let room = rooms[index]
        guard room.kind != .lobby else { throw TowerError("Choose a room above the lobby.") }
        guard room.incident?.isActive != true else { throw TowerError("Resolve this room's current issue first.") }
        guard kind != .party || room.kind == .hotel else { throw TowerError("Parties can only start in hotel suites.") }
        guard kind != .rentArrears || room.kind.isApartment else { throw TowerError("Rent arrears apply to apartments.") }
        var incident = RoomIncident(kind:kind,stage:.burning)
        switch kind {
        case .party:
            incident.transition(to:.partying,minutes:120)
            travelers?.removeAll { $0.roomID == roomID }
            recountElevatorPassengers()
        case .rentArrears: incident.transition(to:.rentOverdue)
        case .fire:
            incident.severity = 0.15
            rooms[index].occupancy = 0
            // Evacuate sampled visitors as well as the room's counted occupants.
            travelers?.removeAll { $0.roomID == roomID }
            recountElevatorPassengers()
        }
        rooms[index].incident = incident
        rooms[index].happiness = kind == .fire ? 0.05 : 0.3
        event("\(incident.title) · \(room.kind.title), floor \(room.floor), unit \(roomID).")
        releaseUnavailableCleaners()
    }
    public mutating func respond(to roomID: Int, action: IncidentAction) throws {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { throw TowerError("Select a room first.") }
        let room = rooms[index]
        if let blocker = responseBlocker(for:room,action:action) { throw TowerError(blocker) }
        guard var incident = room.incident else { throw TowerError("This room has no incident.") }
        switch action {
        case .sendHousekeeping:
            incident.responderRoomID = availableCleaner(for:room)?.id
            incident.transition(to:.cleaning,minutes:180)
        case .serveNotice: incident.transition(to:.noticeServed,minutes:1440)
        case .fileCourtCase:
            cash -= 500
            incident.transition(to:.courtPending,minutes:2880)
        case .evict: incident.transition(to:.evicting,minutes:120)
        case .dispatchFireDepartment:
            dailyExpenses += 1500
            incident.responseRoute = Self.fireResponseRoute(for: room.floor)
            incident.transition(to:.dispatched,minutes:Self.fireResponseMinutes(for: room.floor))
        case .repair:
            cash -= repairCost(for:room)
            incident.transition(to:.repairing,minutes:240)
        }
        rooms[index].incident = incident
        event("\(incident.title) · floor \(room.floor), unit \(room.id).")
    }
    mutating func recountElevatorPassengers() {
        for i in elevators.indices { elevators[i].passengers = activeTravelers.filter { $0.elevatorID == elevators[i].id }.count }
    }
    mutating func releaseUnavailableCleaners() {
        for i in rooms.indices where rooms[i].incident?.stage == .cleaning {
            guard let cleaner = rooms.first(where: { $0.id == rooms[i].incident?.responderRoomID }), cleaner.kind == .housekeeping,
                  cleaner.incident?.isActive != true, abs(cleaner.floor-rooms[i].floor) <= 5,
                  isConnected(cleaner.floor), isConnected(rooms[i].floor) else {
                rooms[i].incident?.responderRoomID = nil
                rooms[i].incident?.transition(to:.awaitingCleaning)
                continue
            }
        }
    }
    mutating func updateIncidents() {
        releaseUnavailableCleaners()
        for i in rooms.indices {
            guard var incident = rooms[i].incident else { continue }
            if incident.kind == .rentArrears && incident.isActive {
                incident.arrears = min(999_999_999,incident.arrears + Double(rooms[i].kind.dailyRent) * rooms[i].occupancy * rooms[i].rent / 1440)
            }
            if incident.stage == .burning || incident.stage == .dispatched { incident.severity = min(1,incident.severity+0.001) }
            let previousStage = incident.stage
            if incident.remainingMinutes > 0 {
                incident.remainingMinutes -= 1
                if incident.remainingMinutes == 0 {
                    switch incident.stage {
                    case .partying: incident.transition(to:.awaitingCleaning)
                    case .cleaning, .repairing, .evicting:
                        if incident.stage == .evicting {
                            rooms[i].occupancy = 0
                            incident.arrears = 0
                            let id = rooms[i].id
                            travelers?.removeAll { $0.roomID == id }
                            recountElevatorPassengers()
                        }
                        incident.responderRoomID = nil
                        incident.transition(to:.resolved,minutes:180)
                        rooms[i].happiness = 0.8
                    case .courtPending: incident.transition(to:.evictionApproved)
                    case .dispatched: incident.transition(to:.extinguishing,minutes:180)
                    case .extinguishing: incident.transition(to:.awaitingRepairs)
                    case .resolved: rooms[i].incident = nil; continue
                    default: break
                    }
                }
            }
            rooms[i].incident = incident
            if previousStage != incident.stage { event("\(incident.title) · floor \(rooms[i].floor), unit \(rooms[i].id).") }
        }
        generateIncidentIfDue()
    }
    private mutating func generateIncidentIfDue() {
        guard day >= 3, minute == 600, rooms.filter({ $0.incident?.isActive == true }).count < 3 else { return }
        // Stable scheduling rather than wall-clock randomness: replay and save/load agree.
        let kind:IncidentKind = day % 7 == 0 ? .fire : day % 2 == 0 ? .party : .rentArrears
        let candidates = rooms.filter { room in
            guard room.incident == nil,room.people > 0 else { return false }
            return kind == .fire || (kind == .party && room.kind == .hotel) || (kind == .rentArrears && room.kind.isApartment)
        }
        guard !candidates.isEmpty else { return }
        let room = candidates[(day / 3) % candidates.count]
        if kind == .rentArrears && !apartmentDefaults(room,onDay:day) { return }
        try? triggerIncident(kind,roomID:room.id)
    }
    func validateIncidents() throws {
        var assignedTeams = Set<Int>()
        for room in rooms {
            guard let incident = room.incident else { continue }
            guard room.kind != .lobby,
                  incident.remainingMinutes >= 0, incident.remainingMinutes <= incident.durationMinutes,
                  (0...10000).contains(incident.durationMinutes), incident.severity.isFinite, (0...1).contains(incident.severity),
                  incident.arrears.isFinite, (0...999_999_999).contains(incident.arrears) else { throw TowerError("Invalid room incident data.") }
            let stages:Set<IncidentStage>
            switch incident.kind {
            case .party:
                guard room.kind == .hotel else { throw TowerError("Invalid party room.") }
                stages = [.partying,.awaitingCleaning,.cleaning,.resolved]
            case .rentArrears:
                guard room.kind.isApartment else { throw TowerError("Invalid rent dispute room.") }
                stages = [.rentOverdue,.noticeServed,.courtPending,.evictionApproved,.evicting,.resolved]
            case .fire:
                guard !incident.isActive || room.occupancy == 0 else { throw TowerError("A fire-damaged room must be evacuated.") }
                stages = [.burning,.dispatched,.extinguishing,.awaitingRepairs,.repairing,.resolved]
            }
            guard stages.contains(incident.stage) else { throw TowerError("Invalid incident stage.") }
            let duration:Int
            switch incident.stage {
            case .partying,.evicting: duration = 120
            case .cleaning,.extinguishing,.resolved: duration = 180
            case .noticeServed: duration = 1440
            case .courtPending: duration = 2880
            case .repairing: duration = 240
            case .dispatched: duration = Self.fireResponseMinutes(for: room.floor)
            default: duration = 0
            }
            guard incident.durationMinutes == duration,
                  duration == 0 || incident.remainingMinutes > 0 || incident.stage == .noticeServed else { throw TowerError("Invalid incident timer.") }
            if incident.stage == .cleaning {
                guard let id = incident.responderRoomID, assignedTeams.insert(id).inserted,
                      rooms.contains(where: { $0.id == id && $0.kind == .housekeeping && $0.incident?.isActive != true && abs($0.floor-room.floor) <= 5 }),
                      let cleaner = rooms.first(where: { $0.id == id }), isConnected(cleaner.floor),isConnected(room.floor) else { throw TowerError("Invalid housekeeping assignment.") }
            } else if incident.responderRoomID != nil { throw TowerError("Unexpected housekeeping assignment.") }
            let needsRoute = incident.kind == .fire && incident.stage != .burning
            if needsRoute {
                guard incident.responseRoute == Self.fireResponseRoute(for: room.floor) else { throw TowerError("Invalid fire response route.") }
            } else if incident.responseRoute != nil { throw TowerError("Unexpected fire response route.") }
        }
    }
}
