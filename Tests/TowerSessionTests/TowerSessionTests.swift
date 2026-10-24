import Foundation
import XCTest
import TowerCore
@testable import TowerSession

final class TowerSessionTests: XCTestCase {
    func testPausedConstructionKeepsEarnedAmbitionAfterDemolition() throws {
        let session=TowerSession(game:.newGame(scenerySeed:42))
        session.speed=0
        try session.execute(.addFloor)
        try session.execute(.addElevator(.standard,column:nil,from:0,to:1))
        try session.execute(.build(.office,floor:1,slot:0))
        let id=try XCTUnwrap(session.game.rooms.first(where:{$0.kind == .office})?.id)
        try session.execute(.demolish(.room(id),confirmed:true))
        XCTAssertTrue(session.game.ambitions.first(where:{$0.id == "first-business"})?.isComplete == true)
        XCTAssertEqual(session.game.minute,480)
    }

    // A rejected row or blocked command must leave the entire tower untouched.
    func testFailedCommandIsAtomicAndReportsError() throws {
        let session = TowerSession(game: .newGame(scenerySeed: 42))
        try session.execute(.addFloor)
        let before = try TowerSnapshot.canonicalData(session.game)
        XCTAssertThrowsError(try session.execute(.buildRow(.office, floor: 1, from: 0, to: 63)))
        XCTAssertEqual(try TowerSnapshot.canonicalData(session.game), before)
        XCTAssertNotNil(session.message)
        XCTAssertFalse(session.events.last?.succeeded ?? true)
    }

    func testDemolitionNeedsConfirmationAndCancelRestoresSpeed() throws {
        let session = TowerSession(game: .demoTower())
        let id = try XCTUnwrap(session.game.rooms.first { $0.kind == .office }?.id)
        session.speed = 12
        let before = try TowerSnapshot.canonicalData(session.game)
        XCTAssertThrowsError(try session.execute(.demolish(.room(id))))
        let quote = try session.requestDemolition(.room(id))
        XCTAssertEqual(quote.refund, 6000)
        XCTAssertEqual(session.speed, 0)
        session.tick()
        XCTAssertThrowsError(try session.execute(.addFloor))
        try session.resolveDemolition(confirmed: false)
        XCTAssertEqual(session.speed, 12)
        XCTAssertNil(session.pendingDemolition)
        XCTAssertEqual(try TowerSnapshot.canonicalData(session.game), before)
        try session.execute(.demolish(.room(id), confirmed: true))
        XCTAssertFalse(session.game.rooms.contains { $0.id == id })
    }

    func testConfirmedDemolitionRevalidatesTargetAndAlwaysRestoresPause() throws {
        let session = TowerSession(game: .demoTower())
        let id = session.game.rooms.first { $0.kind == .office }!.id
        session.speed = 4
        try session.requestDemolition(.room(id))
        try session.game.triggerIncident(.fire, roomID: id)
        XCTAssertThrowsError(try session.resolveDemolition(confirmed: true))
        XCTAssertTrue(session.game.rooms.contains { $0.id == id })
        XCTAssertEqual(session.speed, 4)
        XCTAssertNil(session.pendingDemolition)
    }

    func testSpeedOnlyAcceptsSupportedRatesAndTickUsesRate() throws {
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        session.speed = 4
        session.tick()
        XCTAssertEqual(session.game.minute, 484)
        session.speed = 3
        XCTAssertEqual(session.speed, 4)
        session.speed = 0
        session.tick()
        XCTAssertEqual(session.game.minute, 484)
        session.togglePause()
        session.tick()
        XCTAssertEqual(session.game.minute, 488)
    }

    func testSaveAndSafeSwitchUseUnicodePathsAndDistinctRecovery() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TowerSaveStore(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let url = directory.appendingPathComponent("東京 🏙.loftyambitions")
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        try session.execute(.addFloor)
        try session.save(to: url, store: store)
        XCTAssertFalse(session.hasUnsavedChanges)
        try session.execute(.build(.office, floor: 1, slot: 0))
        let recovery = try session.open(url, store: store)
        XCTAssertEqual(session.game.rooms.count, 1)
        XCTAssertEqual(try store.read(recovery).rooms.count, 2)
        let recovery2 = try session.open(url, store: store)
        XCTAssertNotEqual(recovery, recovery2)
        try session.autosave(to: directory.appendingPathComponent("Auto.loftyambitions"), store: store)
        XCTAssertEqual(try store.read(recovery).rooms.count, 2)
    }

    func testRecoveryAndImportedSavesRequireSaveAs() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TowerSaveStore(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let recovery = try store.preserve(.newGame(scenerySeed: 2))
        let original = try Data(contentsOf: recovery)
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        _ = try session.open(recovery, store: store)
        XCTAssertNil(session.savedURL, "Recovery originals must never become the save target")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: recovery), original)
        let imported = directory.appendingPathComponent("legacy.json")
        try store.write(.newGame(scenerySeed: 3), to: imported)
        _ = try session.open(imported, store: store)
        XCTAssertNil(session.savedURL)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testRecoveryPolicyIgnoresDirectoryHintsButKeepsSiblingSavesWritable() {
        let directory = scratch()
        for isDirectory in [false, true] {
            let recovery = directory.appendingPathComponent("Recovery", isDirectory: isDirectory)
            let store = TowerSaveStore(recoveryDirectory: recovery)
            let file = directory.appendingPathComponent("Recovery", isDirectory: true).appendingPathComponent("Tower.loftyambitions")
            XCTAssertTrue(TowerSavePolicy.requiresSaveAs(file, store: store))
            let sibling = directory.appendingPathComponent("Recovery Other").appendingPathComponent("Tower.loftyambitions")
            XCTAssertFalse(TowerSavePolicy.requiresSaveAs(sibling, store: store))
            #if os(Windows)
            let differentlyCased = directory.appendingPathComponent("RECOVERY").appendingPathComponent("Tower.loftyambitions")
            XCTAssertTrue(TowerSavePolicy.requiresSaveAs(differentlyCased, store: store))
            #endif
        }
    }
    func testInvalidIncomingSaveDoesNotTouchTowerOrRecovery() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("bad.loftyambitions")
        var bad = TowerState.newGame(scenerySeed: 2)
        bad.topFloor = -1
        try JSONEncoder().encode(bad).write(to: url)
        let store = TowerSaveStore(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        let before = try TowerSnapshot.canonicalData(session.game)
        XCTAssertThrowsError(try session.open(url, store: store))
        XCTAssertEqual(try TowerSnapshot.canonicalData(session.game), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.recoveryDirectory.path))
    }

    func testFailedRecoveryAndFailedSaveKeepCurrentTowerDirty() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("occupied")
        try Data("keep".utf8).write(to: blocked)
        let store = TowerSaveStore(recoveryDirectory: blocked)
        let incoming = directory.appendingPathComponent("other.loftyambitions")
        try store.write(.newGame(scenerySeed: 2), to: incoming)
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        try session.execute(.addFloor)
        XCTAssertThrowsError(try session.open(incoming, store: store))
        XCTAssertThrowsError(try session.save(to: blocked.appendingPathComponent("save"), store: store))
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(session.game.citySeed, 1)
        XCTAssertEqual(try Data(contentsOf: blocked), Data("keep".utf8))
        XCTAssertThrowsError(try session.startNewGame(scenerySeed: 3, store: store))
        XCTAssertEqual(session.game.topFloor, 1)
    }

    func testNewGamePreservesTowerBeforeSwitching() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TowerSaveStore(recoveryDirectory: directory)
        let session = TowerSession(game: .newGame(scenerySeed: 1))
        try session.execute(.addFloor)
        let recovery = try session.startNewGame(scenerySeed: 2, store: store)
        XCTAssertEqual(session.game.citySeed, 2)
        XCTAssertEqual(session.game.topFloor, 0)
        XCTAssertEqual(try store.read(recovery).topFloor, 1)
    }

    func testReplayIsDeterministicAcrossSaveRoundTripAndSetOrder() throws {
        let replay = TowerReplayTimeline.selfCheck
        let data = try JSONEncoder().encode(replay)
        let loaded = try JSONDecoder().decode(TowerReplayTimeline.self, from: data)
        let a = try replay.run()
        let b = try loaded.run()
        XCTAssertEqual(try TowerSnapshot.canonicalData(a), try TowerSnapshot.canonicalData(b))
        let restored = try JSONDecoder().decode(TowerState.self, from: TowerSnapshot.canonicalData(a)).validated()
        XCTAssertEqual(try TowerSnapshot.canonicalData(restored), try TowerSnapshot.canonicalData(a))
        XCTAssertTrue(a.rooms.contains { $0.incident?.stage == .resolved })
        XCTAssertGreaterThan(a.completedTrips, 0)
        var ordered = a
        ordered.progression?.claimedAmbitionIDs = ["beta", "alpha"]
        var reversed = a
        reversed.progression?.claimedAmbitionIDs = ["alpha", "beta"]
        XCTAssertEqual(try TowerSnapshot.canonicalData(ordered), try TowerSnapshot.canonicalData(reversed))
    }

    func testCommandsRoundTripAndCapabilityRegistryFindsMissingHandlers() throws {
        let commands: [TowerCommand] = [
            .build(.office, floor: 1, slot: 0), .buildRow(.apartment, floor: 1, from: 0, to: 4),
            .addFloor, .constructFloor(floor: 1, from: 0, to: 63), .widenTower(left: true, cells: 8),
            .addElevator(.wide, column: nil, from: 0, to: 1), .extendElevators, .upgradeElevator(1),
            .relocateElevator(1, column: 40, from: 0, to: 1), .demolish(.elevator(1), confirmed: true),
            .setRent(2, value: 1.3), .setRoomStyle(2, style: .two),
            .setApartmentPolicy(2, screening: .standard, deposit: .none),
            .claimAmbition("first-room"), .activateAbility(.openHouse), .excavateBasement, .upgradeLobby,
            .triggerIncident(.fire, roomID: 2), .respondToIncident(2, action: .dispatchFireDepartment),
            .requestTrip(roomID: 2, from: 0, to: 1), .newGame(scenerySeed: 4), .advance(minutes: 60)
        ]
        XCTAssertEqual(try JSONDecoder().decode([TowerCommand].self, from: JSONEncoder().encode(commands)), commands)
        let handlers = Set(commands.map(\.id))
        XCTAssertTrue(TowerCommandRegistry.missingHandlers(in: handlers).isEmpty)
        XCTAssertEqual(TowerCommandRegistry.missingHandlers(in: handlers.subtracting([.upgradeLobby])), [.upgradeLobby])
    }

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TowerSessionTests-\(UUID().uuidString)")
    }
}
