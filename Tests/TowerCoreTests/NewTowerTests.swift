import XCTest
@testable import TowerCore

final class NewTowerTests: XCTestCase {
    func testNewTowerStartsWithOnlyGroundLobbyAndNoTenantsOrLifts() {
        let game = TowerState.newGame()
        XCTAssertEqual(game.topFloor,0)
        XCTAssertEqual(game.rooms.map(\.kind),[.lobby])
        XCTAssertTrue(game.elevators.isEmpty)
        XCTAssertTrue(game.activeTravelers.isEmpty)
        XCTAssertEqual(game.population,0)
        XCTAssertEqual(game.projectedIncome,0)
        XCTAssertEqual(game.cash,180000)
        XCTAssertEqual(game.stars,1)
    }

    func testBlankTowerCanSaveAndRestoreWithoutElevators() throws {
        let game = TowerState.newGame()
        let restored = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.topFloor,0)
        XCTAssertEqual(restored.rooms.map(\.kind),[.lobby])
        XCTAssertTrue(restored.elevators.isEmpty)
    }

    func testFirstRoomNeedsPlayerBuiltFloorAndElevator() throws {
        var game = TowerState.newGame()
        XCTAssertThrowsError(try game.build(.office,floor:1,slot:0))
        try game.addFloor()
        let id = try game.build(.office,floor:1,slot:0)
        game.advance(minutes:60)
        XCTAssertEqual(game.rooms.first { $0.id == id }!.occupancy,0)
        XCTAssertNoThrow(try game.validated())
        try game.addElevator(.standard,from:0,to:1)
        game.advance(minutes:60)
        XCTAssertGreaterThan(game.rooms.first { $0.id == id }!.occupancy,0)
        XCTAssertNoThrow(try game.validated())
    }
}
