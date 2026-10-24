import Foundation

public enum LobbyStyle: String, Codable, Sendable {
    case standard, grand
    public var title: String { self == .grand ? "Grand Lobby" : "Lobby" }
    public var artwork: String { self == .grand ? "grandLobby" : "lobby" }
}

extension TowerState {
    public static let grandLobbyLevel = 3
    public static let grandLobbyCost = 40000
    public var effectiveLobbyStyle: LobbyStyle { lobbyStyle ?? .standard }
    public var lobbyHeight: Int { lobbyFloorCount ?? 1 }
    public var lobbyRise: Int { lobbyHeight - 1 }
    public var lobbyUpgradeCost: Int { effectiveLobbyStyle == .grand ? 0 : Self.grandLobbyCost }
    public func elevatorTopLimit(_ kind: ElevatorKind, from bottom: Int) -> Int {
        min(Self.maxFloor, bottom + kind.range - 1 + (bottom <= 0 ? lobbyRise : 0))
    }
    public var lobbyExtraUpkeep: Int { effectiveLobbyStyle == .grand ? 250 : 0 }
    public var lobbyHappinessBonus: Double { effectiveLobbyStyle == .grand ? 0.03 : 0 }
    public var lobbyUpgradeBlocker: String? {
        if lobbyHeight == 4 { return "Four-floor Grand Lobby already installed." }
        if stars < Self.grandLobbyLevel { return "Grand Lobby unlocks at level \(Self.grandLobbyLevel)." }
        if topFloor > Self.maxFloor - 3 { return "The Grand Lobby adds 3 floors. Your tower must be at floor \(Self.maxFloor - 3) or lower (maximum height: \(Self.maxFloor))." }
        if rooms.contains(where: { $0.incident?.kind == .fire && $0.incident?.isActive == true }) { return "Resolve active fires and their repairs before lifting the tower." }
        if cash < lobbyUpgradeCost { return "Need $\((lobbyUpgradeCost-cash).formatted()) more to upgrade." }
        return nil
    }
    public mutating func upgradeLobby() throws {
        if let blocker = lobbyUpgradeBlocker { throw TowerError(blocker) }
        cash -= lobbyUpgradeCost
        // Insert three physical levels above the entrance, retaining room IDs,
        // leases, service assignments, floor widths and existing passenger trips.
        func lifted(_ floor: Int) -> Int { floor > 0 ? floor + 3 : floor }
        var spans = Dictionary(uniqueKeysWithValues: (0..<4).map { ($0, span(0)) })
        if basementDepth > 0 { for floor in bottomFloor..<0 { spans[floor] = span(floor) } }
        if topFloor > 0 { for floor in 1...topFloor { spans[floor + 3] = span(floor) } }
        floorSpans = spans
        topFloor += 3
        for i in rooms.indices where rooms[i].floor > 0 {
            rooms[i].floor += 3
            if rooms[i].incident?.responseRoute != nil {
                let route = Self.fireResponseRoute(for: rooms[i].floor)
                rooms[i].incident?.responseRoute = route
            }
        }
        for i in elevators.indices {
            elevators[i].bottomFloor = lifted(elevators[i].bottom)
            elevators[i].topFloor = lifted(elevators[i].topFloor)
            // Keep a car at ground on ground; lift all other cars with the tower.
            if elevators[i].position > 0 { elevators[i].position += 3 }
            elevators[i].targetFloor = elevators[i].targetFloor.map(lifted)
            elevators[i].lobbyRise = 3
        }
        if travelers != nil { for i in travelers!.indices {
            travelers![i].floor = lifted(travelers![i].floor)
            travelers![i].destination = lifted(travelers![i].destination)
            travelers![i].route = travelers![i].route.map(lifted)
        } }
        lobbyStyle = .grand
        lobbyFloorCount = 4
        // Basement teams stay in place and may lose their reach to a lifted hotel.
        releaseUnavailableCleaners()
        event("Four-floor Grand Lobby opened! Above-ground rooms moved up 3 floors. +3% tower happiness.")
    }
}
