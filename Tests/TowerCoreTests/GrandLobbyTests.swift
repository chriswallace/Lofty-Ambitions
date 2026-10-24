import XCTest
@testable import TowerCore

final class GrandLobbyTests: XCTestCase {
    func testUpgradeLiftsRoomsSpansAndElevatorsWithoutLosingContents() throws {
        var game = TowerState.demoTower(); game.earnedStars = 3
        game.floorSpans?[4] = FloorSpan(0, 48)
        let original = game, cash = game.cash
        try game.upgradeLobby()
        XCTAssertEqual(game.lobbyHeight, 4)
        XCTAssertEqual(game.topFloor, original.topFloor + 3)
        XCTAssertEqual(game.cash, cash - 40000)
        XCTAssertEqual(game.population, original.population)
        for old in original.rooms {
            var expected = old
            if old.kind != .lobby { expected.floor += 3 }
            XCTAssertEqual(game.rooms.first { $0.id == old.id }, expected)
        }
        for floor in 1...original.topFloor { XCTAssertEqual(game.span(floor+3), original.span(floor)) }
        for floor in 0...3 {
            XCTAssertEqual(game.span(floor), original.span(0))
            XCTAssertEqual(game.room(at: floor, slot: 0)?.kind, .lobby)
            XCTAssertThrowsError(try game.build(.office, floor: floor, slot: 40))
        }
        XCTAssertEqual(game.elevators[0].stops, [0,4,5,6,7])
        XCTAssertEqual(game.reachableFloors, [0,4,5,6,7])
        _ = try game.validated()
    }

    func testTravelersAndMovingCarsKeepTheirDestinations() throws {
        var game = TowerState.demoTower(); game.earnedStars = 3
        let room = game.rooms.first { $0.floor == 4 }!
        try game.requestTrip(roomID: room.id, from: 0, to: 4)
        game.elevators[0].position = 1.5; game.elevators[0].targetFloor = 4
        game.travelers![0].phase = .riding; game.travelers![0].elevatorID = game.elevators[0].id
        game.elevators[0].passengers = 1
        let id = game.travelers![0].id
        try game.upgradeLobby()
        XCTAssertEqual(game.elevators[0].position, 4.5)
        XCTAssertEqual(game.elevators[0].targetFloor, 7)
        XCTAssertEqual(game.travelers![0].id, id)
        XCTAssertEqual(game.travelers![0].destination, 7)
        XCTAssertEqual(game.travelers![0].route, [7])
        game.advance(minutes: 100)
        XCTAssertFalse(game.activeTravelers.contains { $0.id == id })
        XCTAssertGreaterThan(game.completedTrips, 0)
        _ = try game.validated()
    }

    func testMaximumRangeAndExpressTransfersSurviveExpansion() throws {
        var game = TowerState.newGame(); game.cash = 1000000; game.earnedStars = 3
        for _ in 0..<45 { try game.addFloor() }
        try game.addElevator(.standard, at: 60, from: 0, to: 29)
        try game.addElevator(.express, at: 50, from: 0, to: 45)
        try game.addElevator(.standard, at: 55, from: 15, to: 44)
        try game.upgradeLobby()
        XCTAssertEqual(game.elevators[0].topFloor, 32)
        XCTAssertEqual(game.elevators[0].stops.count, 30)
        XCTAssertEqual(game.elevators[1].stops, [0,18,33,48])
        XCTAssertEqual(game.elevators[2].bottom, 18)
        XCTAssertNotNil(game.route(from: 0, to: 47))
        _ = try game.validated()
        try game.addElevator(.wide, at: 40, from: 0, to: 32)
        XCTAssertThrowsError(try game.addElevator(.wide, at: 35, from: 0, to: 33))
        XCTAssertThrowsError(try game.addElevator(.standard, at: 20, from: 1, to: 5))
        try game.addElevator(.express, at: 30, from: 18, to: 48)
        XCTAssertEqual(game.elevators.last?.stops, [18,33,48])
        _ = try game.validated()
    }

    func testLobbyWideningKeepsFourLevelsAlignedAndChargesForAllFour() throws {
        var game = TowerState.newGame(); game.earnedStars = 3
        try game.upgradeLobby()
        let cash = game.cash
        XCTAssertEqual(try game.floorConstructionCost(floor: 0, from: -8, to: -1), 4800)
        try game.constructFloor(floor: 0, from: -8, to: -1)
        XCTAssertEqual(game.cash, cash - 4800)
        for floor in 0...3 { XCTAssertEqual(game.span(floor), FloorSpan(-8,64)) }
        XCTAssertThrowsError(try game.constructFloor(floor: 1, from: -9, to: -9))
        try game.addFloor()
        XCTAssertEqual(try game.towerWideningCost(left: false), 6000)
        try game.widenTower(left: false)
        for floor in 0...4 { XCTAssertEqual(game.span(floor), FloorSpan(-8,72)) }
        _ = try game.validated()
    }

    func testHeightAndFireBlockersAreAtomic() throws {
        var game = TowerState.newGame(); game.cash = 2000000; game.earnedStars = 3
        for _ in 0..<98 { try game.addFloor() }
        let cash = game.cash, rooms = game.rooms
        XCTAssertThrowsError(try game.upgradeLobby())
        XCTAssertEqual(game.cash, cash); XCTAssertEqual(game.rooms, rooms); XCTAssertEqual(game.topFloor, 98)
        game.topFloor = 97; game.floorSpans?.removeValue(forKey: 98)
        try game.upgradeLobby()
        XCTAssertEqual(game.topFloor, 100)
        _ = try game.validated()
        var fire = TowerState.demoTower(); fire.earnedStars = 3
        try fire.triggerIncident(.fire, roomID: fire.rooms.first { $0.kind == .office }!.id)
        let before = fire.cash
        XCTAssertThrowsError(try fire.upgradeLobby())
        XCTAssertEqual(fire.cash, before); XCTAssertEqual(fire.lobbyHeight, 1)
    }

    func testOlderGrandLobbyCanExpandForFreeAndNewSaveRoundTrips() throws {
        var old = TowerState.demoTower(); old.earnedStars = 3; old.lobbyStyle = .grand; old.cash = 0
        let legacy = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(old)).validated()
        XCTAssertEqual(legacy.lobbyHeight, 1)
        var expanded = legacy
        XCTAssertEqual(expanded.lobbyUpgradeCost, 0)
        try expanded.upgradeLobby()
        XCTAssertEqual(expanded.cash, 0)
        let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(expanded)).validated()
        XCTAssertEqual(restored.lobbyHeight, 4)
        XCTAssertEqual(restored.rooms, expanded.rooms)
        XCTAssertEqual(restored.elevators, expanded.elevators)
        XCTAssertThrowsError(try expanded.upgradeLobby())
        var corrupt = restored; corrupt.rooms[1].floor = 2
        XCTAssertThrowsError(try corrupt.validated())
    }
}
