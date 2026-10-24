import XCTest
@testable import TowerCore

final class ServiceCoverageTests: XCTestCase {
    func tower(floors: Int = 10, width: Int = 64) throws -> TowerState {
        var game = TowerState.newGame(scenerySeed: 42)
        game.cash = 2_000_000; game.earnedStars = 5
        game.floorSpans = [0: FloorSpan(0, width)]
        for _ in 0..<floors { try game.addFloor() }
        try game.addElevator(.standard, at: width - 3, from: 0, to: floors)
        return game
    }
    func occupy(_ id: Int, in game: inout TowerState) {
        game.rooms[game.rooms.firstIndex { $0.id == id }!].occupancy = 1
    }
    func happiness(_ id: Int, in game: TowerState) -> Double {
        game.rooms.first { $0.id == id }!.happiness
    }
    func testFoodDoesNotSupplyDistantFloors() throws {
        var game = try tower()
        let near = try game.build(.office, floor: 1, slot: 0)
        let far = try game.build(.office, floor: 10, slot: 0)
        occupy(near, in: &game); occupy(far, in: &game)
        try game.build(.restaurant, floor: 1, slot: 16)
        game.advance(minutes: 30)
        XCTAssertEqual(happiness(near, in: game) - happiness(far, in: game), 0.14, accuracy: 0.0001)
    }
    func testHorizontalLayoutMattersOnWideFloors() throws {
        var game = try tower(floors: 1, width: 128)
        let near = try game.build(.office, floor: 1, slot: 0)
        let far = try game.build(.office, floor: 1, slot: 100)
        occupy(near, in: &game); occupy(far, in: &game)
        try game.build(.restaurant, floor: 1, slot: 16)
        game.advance(minutes: 30)
        XCTAssertEqual(happiness(near, in: game) - happiness(far, in: game), 0.14, accuracy: 0.0001)
    }
    func testShopsReachSixFloorsWhileFoodReachesFour() throws {
        var game = try tower(floors: 8)
        let withinShopRange = try game.build(.office, floor: 7, slot: 0)
        let outside = try game.build(.office, floor: 8, slot: 0)
        occupy(withinShopRange, in: &game); occupy(outside, in: &game)
        try game.build(.restaurant, floor: 1, slot: 0)
        try game.build(.shop, floor: 1, slot: 20)
        game.advance(minutes: 30)
        XCTAssertEqual(happiness(withinShopRange, in: game), 0.72, accuracy: 0.0001)
        XCTAssertEqual(happiness(outside, in: game), 0.68, accuracy: 0.0001)
    }
    func testAddingCapacityImprovesAnOverloadedNeighborhood() throws {
        var game = try tower(floors: 3)
        var offices: [Int] = []
        for floor in 1...2 {
            for slot in [0, 9, 18, 27, 36] {
                let id = try game.build(.office, floor: floor, slot: slot)
                offices.append(id); occupy(id, in: &game)
            }
        }
        try game.build(.cafe, floor: 3, slot: 12)
        var improved = game
        try improved.build(.restaurant, floor: 3, slot: 28)
        game.advance(minutes: 30); improved.advance(minutes: 30)
        let before = offices.map { happiness($0, in: game) }.reduce(0, +)
        let after = offices.map { happiness($0, in: improved) }.reduce(0, +)
        XCTAssertGreaterThan(after, before + 0.5)
    }
    func testFiniteCapacityIsSharedWithoutDoubleCounting() throws {
        var game = try tower(floors: 2)
        let cafe = try game.build(.cafe, floor: 2, slot: 18)
        var ids: [Int] = []
        for slot in [0, 9, 18, 27, 36, 45] {
            let id = try game.build(.office, floor: 1, slot: slot)
            occupy(id, in: &game); ids.append(id)
        }
        let coverage = game.neighborhoodCoverage
        XCTAssertEqual(coverage.venues[cafe]!.served, 120, accuracy: 0.00001)
        XCTAssertEqual(coverage.floors[1]![.food]!.served, 120, accuracy: 0.00001)
        for id in ids { XCTAssertEqual(coverage.rooms[id]![.food]!.ratio, 0.5, accuracy: 0.00001) }
        let room = game.rooms.first { $0.id == ids[0] }!
        XCTAssertEqual(coverage.rooms[room.id]![.food]!.explanation, "Nearby venues need more capacity")
        XCTAssertTrue(game.serviceWarning(for: room, coverage: coverage)!.text.contains("nothing nearby"), "The room badge prioritizes the worse shortage")
    }
    func testOverlappingCatchmentsReassignDemandToAvoidStrandingCapacity() throws {
        var game = try tower(floors: 9)
        // Floor 5 can use either café; floor 1 can only use the lower one.
        for floor in [5, 1] {
            for slot in [0, 9, 18] { occupy(try game.build(.office, floor: floor, slot: slot), in: &game) }
        }
        try game.build(.cafe, floor: 1, slot: 30)
        try game.build(.cafe, floor: 9, slot: 30)
        let coverage = game.neighborhoodCoverage
        for amounts in coverage.rooms.values { XCTAssertEqual(amounts[.food]!.ratio, 1, accuracy: 0.00001) }
        XCTAssertEqual(coverage.venues.values.reduce(0) { $0 + $1.served }, 240, accuracy: 0.00001)
    }
    func testVacantRoomsEstimateFullOccupancyWithoutReservingCapacity() throws {
        var game = try tower(floors: 2)
        let cafe = try game.build(.cafe, floor: 2, slot: 0)
        for slot in [0, 9] { occupy(try game.build(.office, floor: 1, slot: slot), in: &game) }
        let a = try game.build(.office, floor: 1, slot: 18)
        let b = try game.build(.office, floor: 1, slot: 27)
        let coverage = game.neighborhoodCoverage
        XCTAssertEqual(coverage.venues[cafe]!.served, 80, accuracy: 0.00001)
        XCTAssertEqual(coverage.floors[1]![.food]!.demand, 80)
        for id in [a, b] {
            XCTAssertEqual(coverage.rooms[id]![.food]!.demand, 0)
            XCTAssertEqual(coverage.rooms[id]![.food]!.ratio, 1)
            XCTAssertNil(coverage.shortage(for: id))
        }
    }
    func testAccessIncidentsAndDemolitionImmediatelyChangeCoverage() throws {
        var game = try tower(floors: 2)
        let office = try game.build(.office, floor: 1, slot: 0); occupy(office, in: &game)
        let cafe = try game.build(.cafe, floor: 2, slot: 0)
        XCTAssertEqual(game.neighborhoodCoverage.rooms[office]![.food]!.ratio, 1)
        var disconnected = game
        disconnected.elevators.removeAll()
        XCTAssertTrue(disconnected.neighborhoodCoverage.rooms.isEmpty)
        XCTAssertFalse(disconnected.neighborhoodCoverage.venues[cafe]!.operational)
        var burning = game
        try burning.triggerIncident(.fire, roomID: cafe)
        XCTAssertFalse(burning.neighborhoodCoverage.venues[cafe]!.operational)
        XCTAssertEqual(burning.neighborhoodCoverage.rooms[office]![.food]!.nearbyVenues, 0)
        try game.demolish(cafe)
        XCTAssertEqual(game.neighborhoodCoverage.rooms[office]![.food]!.ratio, 0)
        XCTAssertEqual(game.rooms.first { $0.id == office }!.occupancy, 1, "Construction must not evict tenants")
        game.advance(minutes: 30)
        XCTAssertGreaterThanOrEqual(game.rooms.first { $0.id == office }!.occupancy, 0.94)
    }
    func testArrearsStillNeedServicesAndWarningsKeepPriority() throws {
        var game = try tower(floors: 1)
        let apartment = try game.build(.apartment, floor: 1, slot: 0); occupy(apartment, in: &game)
        try game.triggerIncident(.rentArrears, roomID: apartment)
        XCTAssertEqual(game.neighborhoodCoverage.rooms[apartment]![.food]!.demand, 24)
        XCTAssertEqual(game.signal(for: game.rooms.first { $0.id == apartment }!)?.symbol, "banknote")
        let office = try game.build(.office, floor: 1, slot: 10); occupy(office, in: &game)
        try game.triggerIncident(.fire, roomID: office)
        XCTAssertNil(game.neighborhoodCoverage.rooms[office])
        XCTAssertEqual(game.signal(for: game.rooms.first { $0.id == office }!)?.mood, .alarmed)
    }
    func testBasementVenueAndExactHorizontalBoundary() throws {
        var game = try tower(floors: 1, width: 128)
        try game.excavateBasement()
        try game.addElevator(.standard, at: 120, from: -1, to: 1)
        let cafe = try game.build(.cafe, floor: -1, slot: 0) // Center 5
        let inRange = try game.build(.apartment, floor: 1, slot: 51) // Center 53
        let outside = try game.build(.apartment, floor: 1, slot: 55)
        occupy(inRange, in: &game); occupy(outside, in: &game)
        let coverage = game.neighborhoodCoverage
        XCTAssertTrue(coverage.venues[cafe]!.operational)
        XCTAssertEqual(coverage.rooms[inRange]![.food]!.ratio, 1)
        XCTAssertEqual(coverage.rooms[outside]![.food]!.ratio, 0)
    }
    func testCoverageSurvivesRoomOrderAndSaveRoundTrip() throws {
        var game = try tower(floors: 3)
        for floor in 1...2 {
            for slot in [0, 9, 18, 27, 36] { occupy(try game.build(.office, floor: floor, slot: slot), in: &game) }
        }
        try game.build(.cafe, floor: 3, slot: 0)
        try game.build(.ramen, floor: 3, slot: 15)
        try game.build(.bookshop, floor: 3, slot: 30)
        let coverage = game.neighborhoodCoverage
        game.rooms.reverse()
        XCTAssertEqual(game.neighborhoodCoverage, coverage)
        var loaded = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(loaded.neighborhoodCoverage, coverage)
        game.advance(minutes: 120); loaded.advance(minutes: 120)
        XCTAssertEqual(loaded.neighborhoodCoverage, game.neighborhoodCoverage)
        XCTAssertEqual(loaded.rooms, game.rooms)
    }

}
