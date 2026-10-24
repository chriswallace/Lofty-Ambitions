import XCTest
@testable import TowerCore

final class AmbitionsTests: XCTestCase {
    func testActiveOpenHouseDoublesMoveInsAfterLoading() throws {
        var ordinary = TowerState.newGame()
        ordinary.earnedStars = 2
        try ordinary.addFloor()
        let id = try ordinary.build(.office, floor: 1, slot: 0)
        try ordinary.addElevator(.standard, at: 60, from: 0, to: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ordinary)) as? [String: Any])
        json["progression"] = ["claimedAmbitionIDs": [], "abilityActivations": ["openHouse": 480]]
        var promoted = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: json))
        ordinary.advance(minutes: 30)
        promoted.advance(minutes: 30)
        XCTAssertEqual(ordinary.rooms.first { $0.id == id }!.occupancy, 0.028, accuracy: 0.000001)
        XCTAssertEqual(promoted.rooms.first { $0.id == id }!.occupancy, 0.056, accuracy: 0.000001)
    }

    func testAmbitionRequiresConnectedBusinessAndCanOnlyPayOnceAfterReload() throws {
        var game = TowerState.newGame()
        try game.addFloor()
        _ = try game.build(.office, floor: 1, slot: 0)
        XCTAssertThrowsError(try game.claimAmbition("first-business"))
        try game.addElevator(.standard, at: 60, from: 0, to: 1)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "first-business" }).isComplete)
        let cash = game.cash
        try game.claimAmbition("first-business")
        XCTAssertEqual(game.cash, cash + 3000)
        XCTAssertFalse(game.visibleAmbitions.contains { $0.id == "first-business" })
        var restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertThrowsError(try restored.claimAmbition("first-business"))
        XCTAssertThrowsError(try restored.claimAmbition("not-an-ambition"))
        XCTAssertEqual(restored.cash, cash + 3000)
    }

    func testAchievedAmbitionSurvivesPopulationLossAndReloadBeforeClaim() throws {
        var game = TowerState.demoTower()
        game.advance(minutes: 1)
        for index in game.rooms.indices { game.rooms[index].occupancy = 0 }
        var restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        let ambition = try XCTUnwrap(restored.ambitions.first { $0.id == "first-hundred" })
        XCTAssertTrue(ambition.isComplete)
        XCTAssertEqual(ambition.progress, 1)
        let cash = restored.cash
        try restored.claimAmbition("first-hundred")
        XCTAssertEqual(restored.cash, cash + 5000)
    }

    func testCompletedAmbitionsTakePriorityOverEarlierUnfinishedGoals() {
        var game = TowerState.newGame()
        game.tripsCompleted = 100
        XCTAssertEqual(game.visibleAmbitions.first?.id, "smooth-operator")
    }

    func testAmbitionsTrackDifferentGoalsAndHideFutureLevelGoals() throws {
        var game = try basementTower()
        XCTAssertEqual(game.visibleAmbitions.count, 3)
        XCTAssertTrue(game.visibleAmbitions.allSatisfy { $0.requiredLevel <= game.stars })
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "daily-essentials" }).isComplete)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "below-the-street" }).isComplete)
        XCTAssertFalse(try XCTUnwrap(game.ambitions.first { $0.id == "smooth-operator" }).isComplete)
        game.tripsCompleted = 100
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "smooth-operator" }).isComplete)
        game.earnedStars = 1
        XCTAssertThrowsError(try game.claimAmbition("below-the-street"))
        XCTAssertTrue(game.visibleAmbitions.allSatisfy { $0.requiredLevel == 1 })
    }

    func testPopulationAndHotelGoalsRequireThePromisedConditions() throws {
        var game = TowerState.demoTower()
        XCTAssertFalse(try XCTUnwrap(game.ambitions.first { $0.id == "bustling-tower" }).isComplete)
        for index in game.rooms.indices { game.rooms[index].occupancy = 1 }
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "first-hundred" }).isComplete)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "vertical-neighborhood" }).isComplete)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "bustling-tower" }).isComplete)
        game.earnedStars = 2; game.cash = 100000
        let hotel = try game.build(.hotel, floor: 4, slot: 44)
        XCTAssertFalse(try XCTUnwrap(game.ambitions.first { $0.id == "be-our-guest" }).isComplete)
        let housekeeping = try game.build(.housekeeping, floor: 3, slot: 44)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "be-our-guest" }).isComplete)
        game.rooms[game.rooms.firstIndex { $0.id == housekeeping }!].incident = .init(kind: .fire, stage: .burning, severity: 0.2)
        XCTAssertFalse(try XCTUnwrap(game.ambitions.first { $0.id == "be-our-guest" }).isComplete)
        XCTAssertNotNil(game.rooms.first { $0.id == hotel })
    }

    func testAbilityCostsCooldownAndExpiryPersistAcrossMidnightAndReload() throws {
        var game = TowerState.newGame()
        XCTAssertThrowsError(try game.activateAbility(.openHouse))
        game.earnedStars = 2
        game.cash = 1499
        XCTAssertThrowsError(try game.activateAbility(.openHouse))
        game.cash = 10000
        try game.activateAbility(.openHouse)
        XCTAssertEqual(game.cash, 8500)
        XCTAssertEqual(game.abilityRemainingMinutes(.openHouse), 720)
        XCTAssertThrowsError(try game.activateAbility(.openHouse))
        game.day = 2; game.minute = 0
        var restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
        XCTAssertEqual(restored.abilityRemainingMinutes(.openHouse), 0)
        XCTAssertEqual(restored.abilityCooldownMinutes(.openHouse), 1920)
        XCTAssertThrowsError(try restored.activateAbility(.openHouse))
        restored.day = 3; restored.minute = 480
        XCTAssertNil(restored.abilityBlocker(.openHouse))
        try restored.activateAbility(.openHouse)
        XCTAssertEqual(restored.cash, 7000)
    }

    func testOpenHouseExpiresAndNeverAcceleratesMoveOuts() throws {
        var game = TowerState.newGame()
        game.earnedStars = 2
        try game.addFloor()
        let id = try game.build(.office, floor: 1, slot: 0)
        try game.addElevator(.standard, at: 60, from: 0, to: 1)
        try game.activateAbility(.openHouse)
        let index = try XCTUnwrap(game.rooms.firstIndex { $0.id == id })
        game.rooms[index].occupancy = 1; game.rooms[index].rent = 1.6
        game.advance(minutes: 30)
        XCTAssertEqual(game.rooms[index].occupancy, 0.94, accuracy: 0.000001)
        game.minute = 1199; game.rooms[index].occupancy = 0; game.rooms[index].rent = 1
        game.advance(minutes: 1)
        XCTAssertEqual(game.abilityRemainingMinutes(.openHouse), 0)
        XCTAssertEqual(game.rooms[index].occupancy, 0.028, accuracy: 0.000001)
    }

    func testNightMarketRequiresConnectedBasementTradeAndBoostsOnlyItsIncome() throws {
        var game = try basementTower()
        let shop = try XCTUnwrap(game.rooms.first { $0.kind == .shop })
        let office = try XCTUnwrap(game.rooms.first { $0.kind == .office })
        game.elevators.removeAll()
        XCTAssertThrowsError(try game.activateAbility(.nightMarket))
        game.elevators = [Elevator(id: 1, topFloor: 1, position: 0, direction: 1, passengers: 0, column: 60, bottomFloor: -1)]
        game.rooms[game.rooms.firstIndex { $0.kind == .cafe }!].incident = .init(kind: .fire, stage: .burning, severity: 0.2)
        XCTAssertThrowsError(try game.activateAbility(.nightMarket))
        game.rooms[game.rooms.firstIndex { $0.kind == .cafe }!].incident = nil
        let cash = game.cash
        try game.activateAbility(.nightMarket)
        XCTAssertEqual(game.cash, cash - 250)
        XCTAssertEqual(game.income(for: shop), 1500)
        XCTAssertEqual(game.income(for: office), 1200)
        XCTAssertEqual(game.projectedIncome, 4425)
        game.minute += 360
        XCTAssertEqual(game.income(for: shop), 1000)
    }

    func testUndergroundDistrictBonusDependsOnLiveFoodRetailAndArcade() throws {
        var game = try basementTower()
        let shop = try XCTUnwrap(game.rooms.first { $0.kind == .shop })
        XCTAssertFalse(game.undergroundDistrictActive)
        _ = try game.build(.arcade, floor: -1, slot: 32)
        XCTAssertTrue(game.undergroundDistrictActive)
        XCTAssertEqual(game.income(for: shop), 1150)
        XCTAssertTrue(try XCTUnwrap(game.ambitions.first { $0.id == "underground-district" }).isComplete)
        try game.activateAbility(.nightMarket)
        XCTAssertEqual(game.income(for: shop), 1650)
        game.rooms[game.rooms.count - 1].incident = .init(kind: .fire, stage: .burning, severity: 0.2)
        XCTAssertFalse(game.undergroundDistrictActive)
        XCTAssertEqual(game.income(for: shop), 1500)
        game.elevators.removeAll()
        XCTAssertEqual(game.income(for: shop), 1000)
    }

    func testLegacySaveDefaultsAndMalformedProgressionIsRejected() throws {
        let game = TowerState.newGame()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        json.removeValue(forKey: "progression")
        let old = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: json)).validated()
        XCTAssertFalse(old.ambitions.contains(where: \.isClaimed))
        XCTAssertEqual(old.abilityCooldownMinutes(.openHouse), 0)
        let malformedStates: [[String: Any]] = [
            ["claimedAmbitionIDs": ["unknown"], "abilityActivations": [:]],
            ["claimedAmbitionIDs": ["skyline-icon"], "abilityActivations": [:]],
            ["claimedAmbitionIDs": [], "achievedAmbitionIDs": ["unknown"], "abilityActivations": [:]],
            ["claimedAmbitionIDs": [], "abilityActivations": ["openHouse": -1]],
            ["claimedAmbitionIDs": [], "abilityActivations": ["openHouse": 481]],
            ["claimedAmbitionIDs": [], "abilityActivations": ["unknown": 480]]
        ]
        for malformed in malformedStates {
            json["progression"] = malformed
            let decoded = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try decoded.validated())
        }
    }

    private func basementTower() throws -> TowerState {
        var game = TowerState.newGame()
        game.earnedStars = 3; game.cash = 500000
        try game.addFloor()
        _ = try game.build(.office, floor: 1, slot: 0)
        try game.excavateBasement()
        for (kind, slot) in [(RoomKind.cafe, 0), (.shop, 10)] {
            _ = try game.build(kind, floor: -1, slot: slot)
        }
        for index in game.rooms.indices where game.rooms[index].kind.capacity > 0 { game.rooms[index].occupancy = 1 }
        try game.addElevator(.standard, at: 60, from: -1, to: 1)
        return game
    }
}
