import XCTest
@testable import TowerCore

final class UndergroundTests: XCTestCase {
    func testExcavatedSaveCanBuildCafeBelowGround() throws {
        var tower = TowerState.newGame()
        tower.earnedStars = 2
        tower.floorSpans?[-1] = FloorSpan(0, 64)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tower)) as? [String: Any])
        data["basementFloorCount"] = 1
        var restored = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertNoThrow(try restored.build(.cafe, floor: -1, slot: 0))
    }

    func testExcavationRequiresPermitAndFundsWithoutPartialChanges() throws {
        var game = TowerState.newGame()
        let initialCash = game.cash
        XCTAssertThrowsError(try game.excavateBasement())
        XCTAssertEqual(game.cash, initialCash)
        XCTAssertEqual(game.bottomFloor, 0)
        game.earnedStars = 2; game.cash = 11999
        XCTAssertThrowsError(try game.excavateBasement())
        XCTAssertEqual(game.basementDepth, 0)
        game.cash += 1
        try game.excavateBasement()
        XCTAssertEqual(game.bottomFloor, -1)
        XCTAssertEqual(game.cash, 0)
        XCTAssertEqual(game.span(-1), FloorSpan(0, 64))
        game.cash = 100000
        XCTAssertThrowsError(try game.excavateBasement())
        XCTAssertEqual(game.bottomFloor, -1)
        game.earnedStars = 5
        for _ in 0..<3 { try game.excavateBasement() }
        XCTAssertEqual(game.bottomFloor, -4)
        XCTAssertThrowsError(try game.excavateBasement())
        XCTAssertNoThrow(try game.validated())
    }

    func testExcavatedFloorsHaveOngoingStructuralUpkeep() throws {
        var game = TowerState.newGame(); game.earnedStars = 3
        let before = game.projectedExpenses
        try game.excavateBasement()
        XCTAssertEqual(game.projectedExpenses, before + 60)
        try game.excavateBasement()
        XCTAssertEqual(game.projectedExpenses, before + 120)
        try game.upgradeLobby()
        XCTAssertEqual(game.projectedExpenses, before + 120 + 250)
    }

    func testUndergroundPlacementKeepsHomesAndOfficesAboveGround() throws {
        var base = TowerState.newGame(); base.earnedStars = 5
        try base.excavateBasement()
        for kind in [RoomKind.office, .apartment, .hotel, .luxuryApartment, .coworking, .garden, .observatory] {
            var game = base
            XCTAssertThrowsError(try game.build(kind, floor: -1, slot: 0), kind.title)
            XCTAssertEqual(game.rooms.count, 1)
        }
        for kind in [RoomKind.cafe, .shop, .restaurant, .ramen, .bookshop, .housekeeping, .security, .arcade, .fitness, .spa] {
            var game = base
            XCTAssertNoThrow(try game.build(kind, floor: -1, slot: 0), kind.title)
            XCTAssertNoThrow(try game.validated())
        }
        XCTAssertThrowsError(try base.build(.cafe, floor: -2, slot: 0))
    }

    func testBasementElevatorCarriesPassengersBetweenLobbyAndBusiness() throws {
        var game = TowerState.newGame(); game.earnedStars = 2
        try game.excavateBasement()
        let cafe = try game.build(.cafe, floor: -1, slot: 0)
        XCTAssertFalse(game.isConnected(-1))
        try game.addElevator(.standard, at: 60, from: -1, to: 0)
        XCTAssertEqual(game.elevators[0].stops, [-1, 0])
        XCTAssertEqual(game.route(from: 0, to: -1), [-1])
        try game.requestTrip(roomID: cafe, from: 0, to: -1)
        let traveler = try XCTUnwrap(game.activeTravelers.first?.id)
        game.advance(minutes: 240)
        XCTAssertFalse(game.activeTravelers.contains { $0.id == traveler })
        XCTAssertGreaterThan(game.completedTrips, 0)
        XCTAssertGreaterThan(game.rooms.first { $0.id == cafe }!.occupancy, 0)
        try game.requestTrip(roomID: cafe, from: -1, to: 0)
        let returnTraveler = try XCTUnwrap(game.activeTravelers.last?.id)
        let completed = game.completedTrips
        game.advance(minutes: 360)
        XCTAssertFalse(game.activeTravelers.contains { $0.id == returnTraveler })
        XCTAssertGreaterThan(game.completedTrips, completed)
        XCTAssertNoThrow(try game.validated())
    }

    func testGrandLobbyPreservesUndergroundRoomsCarsAndJourneys() throws {
        var game = TowerState.newGame(); game.earnedStars = 3; game.cash = 300000
        try game.addFloor()
        let office = try game.build(.office, floor: 1, slot: 0)
        try game.excavateBasement(); try game.excavateBasement()
        let cafe = try game.build(.cafe, floor: -2, slot: 0)
        try game.addElevator(.standard, at: 60, from: -2, to: 1)
        try game.requestTrip(roomID: cafe, from: 0, to: -2)
        game.elevators[0].position = -1.5; game.elevators[0].targetFloor = -2
        let below = game.rooms.first { $0.id == cafe }
        try game.upgradeLobby()
        XCTAssertEqual(game.rooms.first { $0.id == cafe }, below)
        XCTAssertEqual(game.rooms.first { $0.id == office }?.floor, 4)
        XCTAssertEqual(game.span(-2), FloorSpan(0, 64))
        XCTAssertEqual(game.elevators[0].bottom, -2)
        XCTAssertEqual(game.elevators[0].position, -1.5)
        XCTAssertEqual(game.elevators[0].targetFloor, -2)
        XCTAssertEqual(game.elevators[0].stops, [-2, -1, 0, 4])
        XCTAssertEqual(game.activeTravelers.first?.route, [-2])
        XCTAssertEqual(game.activeTravelers.first?.destination, -2)
        XCTAssertNoThrow(try game.validated())
    }

    func testGrandLobbyPreservesFullRangeElevatorStartingUnderground() throws {
        var game = TowerState.newGame(); game.earnedStars = 3; game.cash = 1000000
        for _ in 0..<28 { try game.addFloor() }
        try game.excavateBasement()
        try game.addElevator(.standard, at: 60, from: -1, to: 28)
        try game.upgradeLobby()
        XCTAssertEqual(game.elevators[0].topFloor, 31)
        XCTAssertEqual(game.elevators[0].stops.count, 30)
        XCTAssertNoThrow(try game.validated())
    }

    func testGrandLobbyReleasesBasementCleanersWhenHotelMovesOutOfRange() throws {
        var game = TowerState.newGame(); game.earnedStars = 3; game.cash = 300000
        try game.addFloor(); try game.addFloor(); try game.excavateBasement()
        let hotel = try game.build(.hotel, floor: 2, slot: 0)
        let cleaner = try game.build(.housekeeping, floor: -1, slot: 0)
        try game.addElevator(.standard, at: 60, from: -1, to: 2)
        try game.triggerIncident(.party, roomID: hotel)
        game.advance(minutes: 120)
        try game.respond(to: hotel, action: .sendHousekeeping)
        XCTAssertEqual(game.rooms.first { $0.id == hotel }?.incident?.responderRoomID, cleaner)
        XCTAssertNoThrow(try game.validated())
        try game.upgradeLobby()
        XCTAssertEqual(game.rooms.first { $0.id == hotel }?.incident?.stage, .awaitingCleaning)
        XCTAssertNil(game.rooms.first { $0.id == hotel }?.incident?.responderRoomID)
        XCTAssertNoThrow(try game.validated())
    }

    func testFloorToolWidensBasementsWithinFloorAboveAndCannotExcavate() throws {
        var game = TowerState.newGame(); game.earnedStars = 3; game.cash = 300000
        try game.excavateBasement(); try game.excavateBasement()
        game.floorSpans?[-1] = FloorSpan(0, 32)
        game.floorSpans?[-2] = FloorSpan(0, 24)
        try game.constructFloor(floor: -2, from: 24, to: 31)
        XCTAssertEqual(game.span(-2), FloorSpan(0, 32))
        XCTAssertThrowsError(try game.constructFloor(floor: -2, from: 32, to: 32))
        XCTAssertThrowsError(try game.constructFloor(floor: -3, from: 0, to: 10))
        try game.widenTower(left: false)
        XCTAssertEqual(game.span(0), FloorSpan(0, 72))
        XCTAssertEqual(game.span(-1), FloorSpan(0, 72))
        XCTAssertEqual(game.span(-2), FloorSpan(0, 72))
        XCTAssertNoThrow(try game.validated())
    }

    func testBasementSavesRoundTripAndOldSavesDefaultToGround() throws {
        var game = TowerState.newGame(); game.earnedStars = 2
        try game.excavateBasement()
        try game.build(.cafe, floor: -1, slot: 0)
        try game.addElevator(.standard, at: 60, from: -1, to: 0)
        let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.basementDepth, 1)
        XCTAssertEqual(restored.rooms, game.rooms)
        XCTAssertEqual(restored.elevators, game.elevators)
        var oldData = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(TowerState.newGame())) as? [String: Any])
        oldData.removeValue(forKey: "basementFloorCount")
        let legacy = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: oldData)).validated()
        XCTAssertEqual(legacy.bottomFloor, 0)
        XCTAssertNotNil(legacy.excavationBlocker)
    }

    func testInvalidBasementDepthMissingFloorAndForbiddenRoomsRejectSave() throws {
        var base = TowerState.newGame(); base.earnedStars = 2
        try base.excavateBasement()
        var negative = base; negative.basementFloorCount = -1
        XCTAssertThrowsError(try negative.validated())
        var deep = base; deep.basementFloorCount = 5
        XCTAssertThrowsError(try deep.validated())
        var locked = base; locked.earnedStars = 1
        XCTAssertThrowsError(try locked.validated())
        var missing = base; missing.floorSpans?.removeValue(forKey: -1)
        XCTAssertThrowsError(try missing.validated())
        var residence = base
        residence.rooms.append(Room(id: 2, kind: .apartment, floor: -1, slot: 0, occupancy: 0, rent: 1, happiness: 0.75)); residence.nextID = 3
        XCTAssertThrowsError(try residence.validated())
    }

    func testBasementFireUsesInteriorResponseAndRemainsValid() throws {
        var game = TowerState.newGame(); game.earnedStars = 2
        try game.excavateBasement()
        let cafe = try game.build(.cafe, floor: -1, slot: 0)
        try game.triggerIncident(.fire, roomID: cafe)
        try game.respond(to: cafe, action: .dispatchFireDepartment)
        XCTAssertEqual(game.rooms.first { $0.id == cafe }?.incident?.responseRoute, .interior)
        XCTAssertNoThrow(try game.validated())
        game.advance(minutes: 64)
        XCTAssertEqual(game.rooms.first { $0.id == cafe }?.incident?.stage, .extinguishing)
        XCTAssertNoThrow(try game.validated())
    }
}
