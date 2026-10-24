import Foundation
import TowerCore

public struct TowerSessionEvent: Sendable {
    public let command: TowerCommand
    public let succeeded: Bool
    public let message: String?
}

/// Frontends own a session on their simulation thread. File-dialog callbacks must be queued there.
/// Rules remain in TowerCore; this layer provides atomic commands and safe switching policy.
public final class TowerSession {
    public var game: TowerState { didSet { hasUnsavedChanges = true; revision &+= 1 } }
    public var speed: Int = 1 {
        didSet {
            if ![0, 1, 4, 12].contains(speed) || (pendingDemolition != nil && speed != 0) {
                speed = oldValue
            } else if speed > 0 { resumedSpeed = speed }
        }
    }
    public private(set) var revision: UInt64 = 0
    public private(set) var hasUnsavedChanges = false
    public private(set) var savedURL: URL?
    public private(set) var message: String?
    public private(set) var events: [TowerSessionEvent] = []
    public private(set) var pendingDemolition: TowerDemolitionTarget?
    private var resumedSpeed = 1
    private var confirmationSpeed = 1

    public init(game: TowerState = .newGame()) { self.game = game }

    public func execute(_ command: TowerCommand) throws {
        do {
            guard pendingDemolition == nil else { throw TowerError("Finish or cancel the demolition confirmation first.") }
            var candidate = game
            switch command {
            case let .build(kind, floor, slot): try candidate.build(kind, floor: floor, slot: slot)
            case let .buildRow(kind, floor, from, to): try candidate.buildRow(kind, floor: floor, from: from, to: to)
            case .addFloor: try candidate.addFloor()
            case let .constructFloor(floor, from, to): try candidate.constructFloor(floor: floor, from: from, to: to)
            case let .widenTower(left, cells): try candidate.widenTower(left: left, cells: cells)
            case let .addElevator(kind, column, from, to):
                if let column { try candidate.addElevator(kind, at: column, from: from, to: to) }
                else { try candidate.addElevator(kind, from: from, to: to) }
            case .extendElevators: try candidate.extendElevators()
            case .upgradeElevator(let id): try candidate.upgradeElevator(id)
            case let .relocateElevator(id, column, from, to): try candidate.relocateElevator(id, at: column, from: from, to: to)
            case let .demolish(target, confirmed):
                guard confirmed else { throw TowerError("Confirm demolition before removing anything.") }
                _ = try candidate.demolitionQuote(for: target.coreTarget)
                switch target {
                case .room(let id): try candidate.demolish(id)
                case .elevator(let id): try candidate.removeElevator(id)
                }
            case let .setRent(id, value): candidate.setRent(id, value: value)
            case let .setRoomStyle(id, style): try candidate.setRoomStyle(id, style: style)
            case let .setApartmentPolicy(id, screening, deposit): try candidate.setApartmentPolicy(id, screening: screening, deposit: deposit)
            case .claimAmbition(let id): try candidate.claimAmbition(id)
            case .activateAbility(let ability): try candidate.activateAbility(ability)
            case .excavateBasement: try candidate.excavateBasement()
            case .upgradeLobby: try candidate.upgradeLobby()
            case let .triggerIncident(kind, id): try candidate.triggerIncident(kind, roomID: id)
            case let .respondToIncident(id, action): try candidate.respond(to: id, action: action.coreAction)
            case let .requestTrip(id, from, to): try candidate.requestTrip(roomID: id, from: from, to: to)
            case .newGame(let seed): candidate = .newGame(scenerySeed: seed)
            case .advance(let minutes): candidate.advance(minutes: minutes)
            }
            candidate.evaluateAmbitions()
            game = candidate
            if case .newGame = command { savedURL = nil }
            record(command, succeeded: true, message: nil)
        } catch {
            record(command, succeeded: false, message: error.localizedDescription)
            throw error
        }
    }

    public func tick() {
        guard speed > 0, pendingDemolition == nil else { return }
        try? execute(.advance(minutes: speed))
    }
    public func togglePause() {
        guard pendingDemolition == nil else { return }
        speed = speed == 0 ? resumedSpeed : 0
    }

    @discardableResult public func requestDemolition(_ target: TowerDemolitionTarget) throws -> DemolitionQuote {
        guard pendingDemolition == nil else { throw TowerError("A demolition confirmation is already open.") }
        let quote = try game.demolitionQuote(for: target.coreTarget)
        confirmationSpeed = speed
        speed = 0
        pendingDemolition = target
        return quote
    }
    public func resolveDemolition(confirmed: Bool) throws {
        guard let target = pendingDemolition else { return }
        pendingDemolition = nil
        defer { speed = confirmationSpeed }
        if confirmed { try execute(.demolish(target, confirmed: true)) }
    }

    public func save(to url: URL, store: TowerSaveStore) throws {
        try store.write(game.validated(), to: url)
        savedURL = url
        hasUnsavedChanges = false
    }
    /// Autosave never clears manual-save dirty state or changes the selected save file.
    public func autosave(to url: URL, store: TowerSaveStore) throws {
        try store.write(game.validated(), to: url)
    }
    @discardableResult public func open(_ url: URL, store: TowerSaveStore) throws -> URL {
        try requireNoConfirmation()
        let switched = try store.switching(from: game, to: url)
        game = switched.game
        let needsSaveAs = TowerSavePolicy.requiresSaveAs(url,store:store)
        savedURL = needsSaveAs ? nil : url
        hasUnsavedChanges = needsSaveAs
        message = "Opened \(url.lastPathComponent). The previous tower has a recovery copy."
        return switched.recoveryURL
    }
    @discardableResult public func startNewGame(scenerySeed: UInt64 = UInt64.random(in: 1...UInt64.max), store: TowerSaveStore) throws -> URL {
        try requireNoConfirmation()
        let recovery = try store.preserve(game)
        try execute(.newGame(scenerySeed: scenerySeed))
        return recovery
    }
    private func requireNoConfirmation() throws {
        guard pendingDemolition == nil else { throw TowerError("Finish or cancel the demolition confirmation first.") }
    }
    private func record(_ command: TowerCommand, succeeded: Bool, message: String?) {
        self.message = message
        events.append(TowerSessionEvent(command: command, succeeded: succeeded, message: message))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
}

public enum TowerSavePolicy {
    public static func requiresSaveAs(_ url:URL,store:TowerSaveStore)->Bool {
        // Directory URL hints and trailing separators do not identify a different folder.
        let parent = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let recovery = store.recoveryDirectory.standardizedFileURL.pathComponents
        #if os(Windows)
        let isRecovery = parent.map { $0.lowercased() } == recovery.map { $0.lowercased() }
        #else
        let isRecovery = parent == recovery
        #endif
        return isRecovery || url.pathExtension.lowercased() != "loftyambitions"
    }
}
