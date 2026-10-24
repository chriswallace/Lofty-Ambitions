import XCTest
@testable import TowerCore

final class SaveRecoveryTests: XCTestCase {
    func testSwitchesKeepDistinctRecoverableCopiesAfterAutosaveIsOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TowerSaveStore(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let autosave = directory.appendingPathComponent("Autosave.loftyambitions")
        let otherFile = directory.appendingPathComponent("Other.loftyambitions")
        var first = TowerState.newGame(scenerySeed: 11)
        try first.addFloor(); try first.build(.office, floor: 1, slot: 0)
        var other = TowerState.newGame(scenerySeed: 22)
        try other.addFloor(); try other.build(.apartment, floor: 1, slot: 0)
        try store.write(other, to: otherFile)
        let switched = try store.switching(from: first, to: otherFile)
        try store.write(switched.game, to: autosave)
        let secondRecovery = try store.preserve(switched.game)
        XCTAssertNotEqual(switched.recoveryURL, secondRecovery)
        XCTAssertEqual(try store.read(switched.recoveryURL).rooms, first.rooms)
        XCTAssertEqual(try store.read(secondRecovery).rooms, other.rooms)
        XCTAssertEqual(try store.read(autosave).citySeed, 22)
    }
    func testInvalidDestinationDoesNotReplaceCurrentTowerOrCreateRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TowerSaveStore(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        XCTAssertThrowsError(try store.switching(from: .newGame(), to: directory.appendingPathComponent("missing")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.recoveryDirectory.path))
    }
    func testFailedRecoveryStopsTheSwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)
        let store = TowerSaveStore(recoveryDirectory: blocked)
        let other = directory.appendingPathComponent("other.loftyambitions")
        try store.write(.newGame(), to: other)
        XCTAssertThrowsError(try store.switching(from: .newGame(), to: other))
        XCTAssertEqual(try Data(contentsOf: blocked), Data("occupied".utf8))
    }
}
