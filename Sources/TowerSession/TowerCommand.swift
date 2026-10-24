import Foundation
import TowerCore

/// Stable identifiers for capability checks. New actions must be registered by both frontends.
public enum TowerCommandID: String, CaseIterable, Codable, Sendable {
    case build, buildRow, addFloor, constructFloor, widenTower
    case addElevator, extendElevators, upgradeElevator, relocateElevator, demolish
    case setRent, setRoomStyle, setApartmentPolicy, claimAmbition, activateAbility
    case excavateBasement, upgradeLobby, triggerIncident, respondToIncident, requestTrip, newGame, advance
}

public enum TowerDemolitionTarget: Codable, Equatable, Sendable {
    case room(Int), elevator(Int)
    public var coreTarget: DemolitionTarget {
        switch self { case .room(let id): return .room(id); case .elevator(let id): return .elevator(id) }
    }
    public init(_ target: DemolitionTarget) {
        switch target { case .room(let id): self = .room(id); case .elevator(let id): self = .elevator(id) }
    }
}

/// The Core enum intentionally has no persistence conformance; commands use its stable raw values.
public enum TowerIncidentAction: String, CaseIterable, Codable, Sendable {
    case sendHousekeeping, serveNotice, fileCourtCase, evict, dispatchFireDepartment, repair
    public var coreAction: IncidentAction { IncidentAction(rawValue: rawValue)! }
    public init(_ action: IncidentAction) { self = Self(rawValue: action.rawValue)! }
}

public enum TowerCommand: Codable, Equatable, Sendable {
    case build(RoomKind, floor: Int, slot: Int)
    case buildRow(RoomKind, floor: Int, from: Int, to: Int)
    case addFloor
    case constructFloor(floor: Int, from: Int, to: Int)
    case widenTower(left: Bool, cells: Int)
    case addElevator(ElevatorKind, column: Int?, from: Int, to: Int)
    case extendElevators
    case upgradeElevator(Int)
    case relocateElevator(Int, column: Int, from: Int, to: Int)
    case demolish(TowerDemolitionTarget, confirmed: Bool = false)
    case setRent(Int, value: Double)
    case setRoomStyle(Int, style: RoomStyle)
    case setApartmentPolicy(Int, screening: TenantScreening, deposit: ApartmentDeposit)
    case claimAmbition(String)
    case activateAbility(TowerAbility)
    case excavateBasement
    case upgradeLobby
    case triggerIncident(IncidentKind, roomID: Int)
    case respondToIncident(Int, action: TowerIncidentAction)
    case requestTrip(roomID: Int, from: Int, to: Int)
    /// UI callers with an existing tower use startNewGame(store:) to preserve recovery first.
    case newGame(scenerySeed: UInt64)
    /// Explicit simulation minutes for replay. Live frontends call tick() to honor pause/speed.
    case advance(minutes: Int)

    public var id: TowerCommandID {
        switch self {
        case .build: return .build
        case .buildRow: return .buildRow
        case .addFloor: return .addFloor
        case .constructFloor: return .constructFloor
        case .widenTower: return .widenTower
        case .addElevator: return .addElevator
        case .extendElevators: return .extendElevators
        case .upgradeElevator: return .upgradeElevator
        case .relocateElevator: return .relocateElevator
        case .demolish: return .demolish
        case .setRent: return .setRent
        case .setRoomStyle: return .setRoomStyle
        case .setApartmentPolicy: return .setApartmentPolicy
        case .claimAmbition: return .claimAmbition
        case .activateAbility: return .activateAbility
        case .excavateBasement: return .excavateBasement
        case .upgradeLobby: return .upgradeLobby
        case .triggerIncident: return .triggerIncident
        case .respondToIncident: return .respondToIncident
        case .requestTrip: return .requestTrip
        case .newGame: return .newGame
        case .advance: return .advance
        }
    }
}

public enum TowerCommandRegistry {
    public static func missingHandlers(in handlers: Set<TowerCommandID>) -> Set<TowerCommandID> {
        Set(TowerCommandID.allCases).subtracting(handlers)
    }
}
