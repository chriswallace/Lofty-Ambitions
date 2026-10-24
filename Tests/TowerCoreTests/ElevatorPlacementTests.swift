import XCTest
@testable import TowerCore

final class ElevatorPlacementTests:XCTestCase {
    func emptyTower(floors:Int = 4) throws -> TowerState {
        var game = TowerState.newGame();game.cash=1_000_000
        for _ in 0..<floors {try game.addFloor()}
        return game
    }
    func testPlacedShaftUsesChosenColumnWithoutMovingRooms() throws {
        var game = try emptyTower()
        let id = try game.build(.office,floor:1,slot:20)
        let rooms = game.rooms
        try game.addElevator(.standard,at:4,from:0,to:4)
        XCTAssertEqual(game.elevators.last?.column,4)
        XCTAssertEqual(game.rooms,rooms)
        XCTAssertEqual(game.rooms.first{$0.id==id}?.slot,20)
        XCTAssertEqual(game.legacyShaftWidth,0)
        XCTAssertTrue(game.isConnected(4))
    }
    func testRoomAtIntermediateFloorBlocksEntireShaftWithoutCharging() throws {
        var game = try emptyTower()
        let id = try game.build(.apartment,floor:2,slot:5)
        let cash = game.cash
        XCTAssertThrowsError(try game.addElevator(.standard,at:4,from:0,to:4)) { error in
            XCTAssertTrue(error.localizedDescription.contains("\(id)"))
            XCTAssertTrue(error.localizedDescription.contains("floor 2"))
        }
        XCTAssertEqual(game.cash,cash)
        XCTAssertTrue(game.elevators.isEmpty)
        try game.demolish(id)
        XCTAssertNoThrow(try game.addElevator(.standard,at:4,from:0,to:4))
    }
    func testExpressChecksFloorsWhereItDoesNotStop() throws {
        var game = try emptyTower(floors:15)
        _ = try game.build(.office,floor:7,slot:0)
        XCTAssertThrowsError(try game.addElevator(.express,at:4,from:0,to:15))
    }
    func testShaftsAndRoomsMayTouchButCannotOverlap() throws {
        var game = try emptyTower()
        try game.addElevator(.standard,at:8,from:0,to:4)
        XCTAssertEqual(game.elevators[0].footprintWidth,3)
        XCTAssertNoThrow(try game.build(.apartment,floor:2,slot:4))
        XCTAssertNoThrow(try game.build(.apartment,floor:2,slot:11))
        XCTAssertThrowsError(try game.build(.office,floor:3,slot:0))
        XCTAssertThrowsError(try game.addElevator(.standard,at:10,from:0,to:4))
        XCTAssertNoThrow(try game.addElevator(.standard,at:15,from:0,to:4))
    }
    func testSameColumnAllowsVerticallyDisjointShafts() throws {
        var game = try emptyTower()
        try game.addElevator(.standard,at:8,from:0,to:1)
        XCTAssertNoThrow(try game.addElevator(.standard,at:8,from:2,to:4))
        XCTAssertThrowsError(try game.addElevator(.standard,at:8,from:1,to:2))
    }
    func testNewTowersDoNotReserveTheMiddleForElevators() throws {
        var game = try emptyTower()
        XCTAssertNoThrow(try game.build(.office,floor:1,slot:30))
        XCTAssertThrowsError(try game.addElevator(.standard,at:32,from:0,to:4))
    }
    func testFullFootprintMustFitEveryFloor() throws {
        var game = TowerState.newGame();game.cash=1_000_000
        try game.constructFloor(floor:1,from:0,to:12)
        XCTAssertThrowsError(try game.addElevator(.standard,at:12,from:0,to:1))
        XCTAssertThrowsError(try game.addElevator(.standard,at:-1,from:0,to:1))
        XCTAssertNoThrow(try game.addElevator(.standard,at:10,from:0,to:1))
    }
    func testExtensionIsAtomicWhenOneBankHasBlockedPath() throws {
        var game = try emptyTower()
        try game.addElevator(.standard,at:4,from:0,to:1)
        try game.addElevator(.standard,at:20,from:0,to:1)
        let room = try game.build(.apartment,floor:3,slot:20)
        let elevators = game.elevators, cash = game.cash
        XCTAssertThrowsError(try game.extendElevators())
        XCTAssertEqual(game.elevators,elevators)
        XCTAssertEqual(game.cash,cash)
        try game.demolish(room)
        XCTAssertNoThrow(try game.extendElevators())
        XCTAssertEqual(game.elevators.map(\.topFloor),[4,4])
    }
    func testWideningUpgradeRequiresClearAdjacentCells() throws {
        var game = try emptyTower()
        try game.addElevator(.standard,at:8,from:0,to:4)
        let room = try game.build(.apartment,floor:3,slot:11)
        let cash = game.cash
        XCTAssertThrowsError(try game.upgradeElevator(game.elevators[0].id))
        XCTAssertEqual(game.elevators[0].kind,.standard)
        XCTAssertEqual(game.cash,cash)
        try game.demolish(room)
        let before = game.cash
        try game.upgradeElevator(game.elevators[0].id)
        XCTAssertEqual(game.elevators[0].kind,.wide)
        XCTAssertEqual(game.elevators[0].column,8)
        XCTAssertEqual(game.cash,before-14000)
    }
    func testPlacedShaftSaveRoundTripAndOverlapValidation() throws {
        var game = try emptyTower()
        try game.addElevator(.standard,at:5,from:0,to:4)
        let restored = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.elevators,game.elevators)
        let index = game.rooms.count
        _ = try game.build(.apartment,floor:2,slot:12)
        game.rooms[index].slot = 5
        XCTAssertThrowsError(try game.validated())
    }
    func testLegacyCentralBanksStillLoadWithoutMovingRooms() throws {
        let game = TowerState.demoTower()
        let restored = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertNil(restored.elevators[0].column)
        XCTAssertEqual(restored.rooms,game.rooms)
        XCTAssertEqual(restored.legacyShaftWidth,3)
    }
}
