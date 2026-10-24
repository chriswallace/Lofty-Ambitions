import XCTest
@testable import TowerCore

final class ElevatorEditingTests: XCTestCase {
    func tower() throws -> TowerState {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 1_000_000; game.minute = 1
        for _ in 0..<4 { try game.addFloor() }
        try game.build(.office, floor: 4, slot: 0)
        try game.addElevator(.standard, at: 32, from: 0, to: 4)
        return game
    }
    func testRemovingLastLiftRefundsAndReleasesSpaceWithoutStrandedPassengers() throws {
        var game = try tower()
        let room = game.rooms.last!.id
        for _ in 0..<5 { try game.requestTrip(roomID: room, from: 0, to: 4) }
        for _ in 0..<55 { game.updateTransit() }
        XCTAssertTrue(game.activeTravelers.contains { $0.phase == .riding })
        let cash = game.cash
        try game.removeElevator(1)
        XCTAssertEqual(game.cash, cash + 9000)
        XCTAssertTrue(game.elevators.isEmpty)
        XCTAssertTrue(game.activeTravelers.isEmpty)
        XCTAssertFalse(game.isConnected(4))
        XCTAssertNoThrow(try game.build(.office, floor: 2, slot: 32))
        XCTAssertNoThrow(try game.validated())
        XCTAssertThrowsError(try game.removeElevator(1))
        XCTAssertEqual(game.cash, cash + 9000 - 12000)
    }
    func testRelocationIsAtomicAndPreservesTripsAndSaveState() throws {
        var game = try tower()
        let room = game.rooms.last!.id
        for _ in 0..<5 { try game.requestTrip(roomID: room, from: 0, to: 4) }
        for _ in 0..<55 { game.updateTransit() }
        let before = try JSONEncoder().encode(game)
        XCTAssertThrowsError(try game.relocateElevator(1, at: 0, from: 0, to: 4))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: before) as? NSDictionary)
        let cash = game.cash
        try game.relocateElevator(1, at: 45, from: 0, to: 4)
        XCTAssertEqual(game.cash, cash)
        XCTAssertEqual(game.elevators[0].column, 45)
        XCTAssertTrue(game.activeTravelers.allSatisfy { $0.elevatorID == nil })
        game = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        for _ in 0..<300 { game.updateTransit() }
        XCTAssertEqual(game.completedTrips, 5)
        XCTAssertTrue(game.activeTravelers.isEmpty)
        XCTAssertNoThrow(try game.build(.office, floor: 2, slot: 32))
    }
    func testRemovingOneCarReroutesPassengersToRemainingCar() throws {
        var game = try tower()
        try game.addElevator(.standard, at: 40, from: 0, to: 4)
        for _ in 0..<24 { try game.requestTrip(roomID: game.rooms.last!.id, from: 0, to: 4) }
        for _ in 0..<55 { game.updateTransit() }
        try game.removeElevator(1)
        for _ in 0..<400 { game.updateTransit() }
        XCTAssertEqual(game.completedTrips, 24)
        XCTAssertTrue(game.activeTravelers.isEmpty)
        XCTAssertNoThrow(try game.validated())
    }
}

extension ElevatorEditingTests {
    func testLegacyShaftCanBeRelocatedWithoutMovingRooms() throws {
        var game = TowerState.demoTower()
        let originalRooms = game.rooms
        let money = game.cash
        try game.relocateElevator(1, at: 27, from: 0, to: 4)
        XCTAssertEqual(game.legacyShaftWidth, 0)
        XCTAssertEqual(game.rooms, originalRooms)
        XCTAssertEqual(game.cash, money)
        XCTAssertNoThrow(try game.validated())
    }
    func testRemovingAccessReleasesAnActiveCleaningAssignment() throws {
        var game = try tower()
        game.earnedStars = 2
        let hotel = try game.build(.hotel, floor: 1, slot: 0)
        try game.build(.housekeeping, floor: 2, slot: 0)
        try game.triggerIncident(.party, roomID: hotel)
        game.advance(minutes: 120)
        try game.respond(to: hotel, action: .sendHousekeeping)
        try game.removeElevator(1)
        XCTAssertEqual(game.rooms.first { $0.id == hotel }?.incident?.stage, .awaitingCleaning)
        XCTAssertNil(game.rooms.first { $0.id == hotel }?.incident?.responderRoomID)
        XCTAssertNoThrow(try game.validated())
    }
}
