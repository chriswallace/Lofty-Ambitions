import Foundation
import TowerCore

/// A versioned, seeded timeline can be replayed unchanged on macOS and Windows.
public struct TowerReplayTimeline: Codable, Sendable {
    public var formatVersion: Int
    public var scenerySeed: UInt64
    public var commands: [TowerCommand]
    public init(formatVersion: Int = 1, scenerySeed: UInt64, commands: [TowerCommand]) {
        self.formatVersion = formatVersion
        self.scenerySeed = scenerySeed
        self.commands = commands
    }
    public func run() throws -> TowerState {
        guard formatVersion == 1 else { throw TowerError("Unsupported replay version.") }
        let session = TowerSession(game: .newGame(scenerySeed: scenerySeed))
        for command in commands { try session.execute(command) }
        return try session.game.validated()
    }
    public static let selfCheck = TowerReplayTimeline(scenerySeed: 20261024, commands: [
        .addFloor,
        .constructFloor(floor: 2, from: 0, to: 63),
        .build(.office, floor: 1, slot: 0),
        .build(.apartment, floor: 1, slot: 12),
        .buildRow(.apartment, floor: 1, from: 16, to: 20),
        .build(.restaurant, floor: 2, slot: 0),
        .build(.shop, floor: 2, slot: 32),
        .addElevator(.standard, column: 56, from: 0, to: 2),
        .upgradeElevator(1),
        .relocateElevator(1, column: 52, from: 0, to: 2),
        .addFloor,
        .extendElevators,
        .widenTower(left: false, cells: 2),
        .setRoomStyle(2, style: .two),
        .setRent(2, value: 1.1),
        .setApartmentPolicy(3, screening: .standard, deposit: .none),
        .claimAmbition("first-business"),
        .claimAmbition("daily-essentials"),
        .requestTrip(roomID: 2, from: 0, to: 1),
        .advance(minutes: 240),
        .triggerIncident(.fire, roomID: 2),
        .respondToIncident(2, action: .dispatchFireDepartment),
        .advance(minutes: 210),
        .respondToIncident(2, action: .repair),
        .advance(minutes: 240)
    ])
}

public enum TowerSnapshot {
    /// Save-compatible JSON with stable object keys and sorted progression sets.
    /// Ordered arrays (rooms, travelers, events, history) retain their simulation order.
    /// No rounding or field exclusions hide behavioral differences across platforms.
    public static func canonicalData(_ game: TowerState) throws -> Data {
        let encoded = try JSONEncoder().encode(game)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        if var progression = object["progression"] as? [String: Any] {
            for key in ["claimedAmbitionIDs", "achievedAmbitionIDs"] {
                if let ids = progression[key] as? [String] { progression[key] = ids.sorted() }
            }
            object["progression"] = progression
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }
}
