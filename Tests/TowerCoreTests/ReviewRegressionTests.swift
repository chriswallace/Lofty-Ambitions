import XCTest
@testable import TowerCore

final class ReviewRegressionTests: XCTestCase {
    // A room count cap must never reject a layout built through normal construction.
    func testEveryRoomThatFitsTheLargestBuildingCanSaveAndReload() throws {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 2_000_000_000
        try game.constructFloor(floor: 0, from: 0, to: 255)
        for _ in 0..<100 {
            try game.addFloor()
            for slot in stride(from: 0, to: 256, by: 4) {
                try game.build(.apartment, floor: game.topFloor, slot: slot)
            }
        }
        XCTAssertEqual(game.rooms.count, 6401)
        XCTAssertThrowsError(try game.buildRow(.apartment, floor: 100, from: 0, to: 255)) { error in
            XCTAssertTrue(error.localizedDescription.contains("full"))
            XCTAssertTrue(error.localizedDescription.contains("256"))
        }
        let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.rooms, game.rooms)
        XCTAssertEqual(restored.cash, game.cash)
        XCTAssertThrowsError(try game.addFloor()) { error in
            XCTAssertTrue(error.localizedDescription.contains("100"))
        }
        XCTAssertThrowsError(try game.constructFloor(floor: 0, from: -1, to: 255)) { error in
            XCTAssertTrue(error.localizedDescription.contains("256"))
        }
    }

    func testSeventhHotelDoesNotTakeServiceAwayFromSixExistingSuites() throws {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 1_000_000; game.earnedStars = 2
        try game.constructFloor(floor: 0, from: 0, to: 127)
        try game.addFloor(); try game.addFloor()
        try game.addElevator(.standard, at: 120, from: 0, to: 2)
        try game.build(.housekeeping, floor: 2, slot: 0)
        for slot in stride(from: 0, through: 96, by: 16) { try game.build(.hotel, floor: 1, slot: slot) }
        let hotels = game.rooms.filter { $0.kind == .hotel }
        XCTAssertEqual(hotels.filter { game.hasHotelService($0) }.map(\.id), Array(hotels.prefix(6)).map(\.id))
        XCTAssertFalse(game.hasHotelService(hotels[6]))
    }

    func testSecondElevatorSharesTheQueueAndCompletesTripsSooner() throws {
        func run(cars: Int) throws -> (Int, Set<Int>) {
            var game = TowerState.newGame(scenerySeed: 1)
            game.cash = 1_000_000; game.minute = 1
            for _ in 0..<4 { try game.addFloor() }
            let room = try game.build(.office, floor: 4, slot: 0)
            try game.addElevator(.standard, at: 32, from: 0, to: 4)
            if cars == 2 { try game.addElevator(.standard, at: 40, from: 0, to: 4) }
            for _ in 0..<24 { try game.requestTrip(roomID: room, from: 0, to: 4) }
            var minutes = 0, used = Set<Int>()
            while game.completedTrips < 24 && minutes < 500 {
                game.updateTransit(); minutes += 1
                used.formUnion(game.activeTravelers.compactMap(\.elevatorID))
                XCTAssertTrue(game.elevators.allSatisfy { $0.passengers <= $0.capacity })
            }
            XCTAssertEqual(game.completedTrips, 24)
            return (minutes, used)
        }
        let single = try run(cars: 1), pair = try run(cars: 2)
        XCTAssertEqual(pair.1, [1, 2])
        XCTAssertLessThan(pair.0, single.0)
    }
}

extension ReviewRegressionTests {
    func testRemoteHousekeepingCannotLendCapacityToAnOverloadedLocalTeam() throws {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 2_000_000; game.earnedStars = 2
        try game.constructFloor(floor: 0, from: 0, to: 127)
        for _ in 0..<20 { try game.addFloor() }
        try game.addElevator(.standard, at: 120, from: 0, to: 20)
        try game.build(.housekeeping, floor: 2, slot: 0)
        try game.build(.housekeeping, floor: 20, slot: 0)
        for slot in stride(from: 0, through: 96, by: 16) { try game.build(.hotel, floor: 1, slot: slot) }
        XCTAssertEqual(game.rooms.filter { $0.kind == .hotel && game.hasHotelService($0) }.count, 6)
    }
    func testOverlappingHousekeepingAreasKeepCapacityForHigherFloors() throws {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 2_000_000; game.earnedStars = 2
        try game.constructFloor(floor: 0, from: 0, to: 127)
        for _ in 0..<15 { try game.addFloor() }
        try game.addElevator(.standard, at: 120, from: 0, to: 15)
        // Deliberately insert the upper team first. Array order must not waste its reach.
        try game.build(.housekeeping, floor: 10, slot: 0)
        try game.build(.housekeeping, floor: 1, slot: 0)
        for floor in [5, 15] {
            for slot in stride(from: 0, through: 80, by: 16) { try game.build(.hotel, floor: floor, slot: slot) }
        }
        XCTAssertEqual(game.rooms.filter { $0.kind == .hotel && game.hasHotelService($0) }.count, 12)
    }
    func testBankAssignmentsSurviveSaveWithoutChangingTrips() throws {
        var game = TowerState.newGame(scenerySeed: 1)
        game.cash = 1_000_000; game.minute = 1
        for _ in 0..<4 { try game.addFloor() }
        let id = try game.build(.office, floor: 4, slot: 0)
        try game.addElevator(.standard, at: 32, from: 0, to: 4)
        try game.addElevator(.standard, at: 40, from: 0, to: 4)
        for _ in 0..<24 { try game.requestTrip(roomID: id, from: 0, to: 4) }
        game.updateTransit()
        var restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertEqual(Set(restored.activeTravelers.compactMap(\.boardingElevatorID)), [1, 2])
        for _ in 0..<200 { game.updateTransit(); restored.updateTransit() }
        XCTAssertEqual(restored.completedTrips, 24)
        XCTAssertEqual(restored.elevators, game.elevators)
        XCTAssertEqual(restored.activeTravelers, game.activeTravelers)
    }
}
