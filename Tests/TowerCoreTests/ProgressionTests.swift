import XCTest
@testable import TowerCore

final class ProgressionTests: XCTestCase {
    func testNewRoomsUnlockAtSuccessiveLevelsAndPersist() throws {
        for (kind, level) in [(RoomKind.cafe, 2), (.arcade, 3), (.fitness, 4), (.observatory, 5)] {
            var game = TowerState.newGame(); try game.addFloor()
            game.earnedStars = level - 1
            XCTAssertThrowsError(try game.build(kind, floor: 1, slot: 0))
            game.earnedStars = level
            let id = try game.build(kind, floor: 1, slot: 0)
            let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
            XCTAssertEqual(restored.rooms.first { $0.id == id }?.kind, kind)
            XCTAssertEqual(restored.level.number, level)
            XCTAssertGreaterThan(kind.dailyRent, kind.upkeep)
        }
    }
    func testLevelRequiresAllMilestonesAndAwardsGrantOnlyOnce() {
        var game = TowerState.demoTower()
        for i in game.rooms.indices { game.rooms[i].occupancy = 1; game.rooms[i].happiness = 0.64 }
        let cash = game.cash
        game.evaluateLevel(); XCTAssertEqual(game.stars, 1)
        for i in game.rooms.indices { game.rooms[i].happiness = 0.65 }
        game.evaluateLevel(); XCTAssertEqual(game.stars, 2)
        XCTAssertEqual(game.cash, cash + 20000)
        XCTAssertTrue(game.events[0].contains("Café"))
        game.evaluateLevel(); XCTAssertEqual(game.cash, cash + 20000)
        for i in game.rooms.indices { game.rooms[i].occupancy = 0 }
        game.evaluateLevel(); XCTAssertEqual(game.stars, 2, "Unlocks are permanent")
    }
    func testFacilityMustBeConnectedAndOperationalForPromotion() {
        var game = TowerState.demoTower(); game.earnedStars = 2
        for i in game.rooms.indices { game.rooms[i].occupancy = 1; game.rooms[i].happiness = 0.8 }
        // The level evaluator also handles towers larger than this small demo.
        for id in 100..<110 { game.rooms.append(Room(id: id, kind: .office, floor: 2, slot: 0, occupancy: 1, rent: 1, happiness: 0.8)) }
        game.rooms.append(Room(id: 500, kind: .housekeeping, floor: 5, slot: 0, occupancy: 0, rent: 1, happiness: 0.8))
        game.evaluateLevel(); XCTAssertEqual(game.stars, 2)
        game.rooms[game.rooms.count - 1].floor = 4
        game.rooms[game.rooms.count - 1].incident = RoomIncident(kind: .fire, stage: .burning, severity: 0.2)
        game.evaluateLevel(); XCTAssertEqual(game.stars, 2)
        game.rooms[game.rooms.count - 1].incident = nil
        game.evaluateLevel(); XCTAssertEqual(game.stars, 3)
    }
    func testExistingSaveUsesItsRatingAndMaxLevelHasNoFurtherGoal() throws {
        var game = TowerState.newGame(); game.earnedStars = 5
        let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.level.title, "Skyline icon")
        XCTAssertNil(restored.nextLevel); XCTAssertTrue(restored.levelRequirements.isEmpty)
        XCTAssertEqual(restored.levelProgress, 1)
        XCTAssertTrue(TowerLevel.all.dropFirst().allSatisfy { !$0.unlocks.isEmpty })
    }
    func testCafeSuppliesFoodAndLeisureBonusesDoNotStackByRoomCount() throws {
        var base = TowerState.newGame(); base.cash = 500000; base.earnedStars = 5
        try base.addFloor(); try base.addElevator(.standard, at: 60, from: 0, to: 1)
        let office = try base.build(.office, floor: 1, slot: 0)
        var cafe = base; _ = try cafe.build(.cafe, floor: 1, slot: 10)
        base.advance(minutes: 30); cafe.advance(minutes: 30)
        let baseline = base.rooms.first { $0.id == office }!.happiness
        XCTAssertEqual(cafe.rooms.first { $0.id == office }!.happiness - baseline, 0.14, accuracy: 0.0001)
        for (kind, bonus) in [(RoomKind.arcade, 0.02), (.fitness, 0.03), (.observatory, 0.04)] {
            var single = base; _ = try single.build(kind, floor: 1, slot: 32)
            var double = single; try double.addFloor(); try double.extendElevators()
            _ = try double.build(kind, floor: 2, slot: 32)
            single.advance(minutes: 30); double.advance(minutes: 30)
            XCTAssertEqual(single.rooms.first { $0.id == office }!.happiness, baseline + bonus, accuracy: 0.0001)
            XCTAssertEqual(double.rooms.first { $0.id == office }!.happiness, baseline + bonus, accuracy: 0.0001)
        }
    }
}
