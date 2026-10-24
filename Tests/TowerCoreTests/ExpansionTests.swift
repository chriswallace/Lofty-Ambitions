import XCTest
@testable import TowerCore

final class ExpansionTests: XCTestCase {
    func testNewRoomsUnlockBuildAndSurviveSaveRoundTrip() throws {
        for kind in [RoomKind.ramen, .bookshop, .coworking, .spa] {
            var game = TowerState.newGame(); game.cash = 500000
            try game.addFloor()
            game.earnedStars = kind.requiredStars - 1
            XCTAssertThrowsError(try game.build(kind, floor: 1, slot: 0))
            game.earnedStars += 1
            let before = game.cash
            let id = try game.build(kind, floor: 1, slot: 0)
            XCTAssertEqual(game.cash, before-kind.cost)
            let restored = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(game)).validated()
            XCTAssertEqual(restored.rooms.first { $0.id == id }?.kind, kind)
            XCTAssertTrue(RoomCatalog.search(query: kind.title).contains { $0.kind == kind })
        }
    }

    func testGrandLobbyEnforcesLevelFundsAndOneTimePurchase() throws {
        var game = TowerState.newGame()
        XCTAssertEqual(game.effectiveLobbyStyle, .standard)
        let startingCash = game.cash
        XCTAssertThrowsError(try game.upgradeLobby())
        XCTAssertEqual(game.cash, startingCash)
        game.earnedStars = 3; game.cash = TowerState.grandLobbyCost - 1
        XCTAssertThrowsError(try game.upgradeLobby())
        XCTAssertEqual(game.effectiveLobbyStyle, .standard)
        game.cash += 1
        let rooms = game.rooms, span = game.span(0)
        let expenses = game.projectedExpenses
        try game.upgradeLobby()
        XCTAssertEqual(game.cash, 0)
        XCTAssertEqual(game.effectiveLobbyStyle, .grand)
        XCTAssertEqual(game.rooms, rooms); XCTAssertEqual(game.span(0), span)
        XCTAssertEqual(game.projectedExpenses, expenses + 250)
        XCTAssertThrowsError(try game.upgradeLobby())
        XCTAssertEqual(game.cash, 0)
        XCTAssertTrue(TowerLevel.all[2].unlockTitles.contains("Grand Lobby upgrade"))
    }

    func testLobbyUpgradePersistsAndLegacySavesDefaultToStandard() throws {
        var game = TowerState.newGame(); game.earnedStars = 3
        try game.upgradeLobby()
        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(TowerState.self, from: data).validated()
        XCTAssertEqual(restored.effectiveLobbyStyle, .grand)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "lobbyStyle")
        legacy.removeValue(forKey: "lobbyFloorCount")
        let old = try JSONDecoder().decode(TowerState.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
        XCTAssertEqual(old.effectiveLobbyStyle, .standard)
        XCTAssertEqual(old.rooms, restored.rooms)
        XCTAssertEqual(old.cash, restored.cash)
    }

    func testNewRoomServicesAndGrandLobbyAffectHappiness() throws {
        var base = TowerState.newGame(); base.cash = 500000; base.earnedStars = 5
        try base.addFloor(); try base.addElevator(.standard, at: 60, from: 0, to: 1)
        let office = try base.build(.office, floor: 1, slot: 0)
        base.advance(minutes: 30)
        let happiness = base.rooms.first { $0.id == office }!.happiness
        for (kind, bonus) in [(RoomKind.ramen, 0.14), (.bookshop, 0.04), (.spa, 0.03)] {
            var single = base; let id = try single.build(kind, floor: 1, slot: 32)
            var duplicate = single; try duplicate.addFloor(); try duplicate.extendElevators()
            try duplicate.build(kind, floor: 2, slot: 0)
            single.advance(minutes: 30); duplicate.advance(minutes: 30)
            XCTAssertEqual(single.rooms.first { $0.id == office }!.happiness, happiness + bonus, accuracy: 0.0001)
            XCTAssertEqual(duplicate.rooms.first { $0.id == office }!.happiness, happiness + bonus, accuracy: 0.0001)
            try single.triggerIncident(.fire, roomID: id); single.advance(minutes: 30)
            XCTAssertEqual(single.rooms.first { $0.id == office }!.happiness, happiness, accuracy: 0.0001)
        }
        var grand = base; try grand.upgradeLobby(); grand.advance(minutes: 30)
        XCTAssertEqual(grand.rooms.first { $0.id == office }!.happiness, happiness + 0.03, accuracy: 0.0001)
        try grand.widenTower(left: true)
        XCTAssertEqual(grand.effectiveLobbyStyle, .grand)
        XCTAssertEqual(grand.lobbyHappinessBonus, 0.03)
    }

    func testDemolitionQuoteIsReadOnlyAndMatchesRefund() throws {
        var game = TowerState.demoTower()
        let room = try XCTUnwrap(game.rooms.first { $0.kind == .office })
        let before = game.cash, count = game.rooms.count
        let quote = try game.demolitionQuote(for: .room(room.id))
        XCTAssertTrue(quote.title.contains("floor \(room.floor)"))
        XCTAssertTrue(quote.consequences.contains("\(room.people) occupants"))
        XCTAssertEqual(game.rooms.count, count); XCTAssertEqual(game.cash, before)
        try game.demolish(room.id)
        XCTAssertEqual(game.cash, before + quote.refund)
        XCTAssertEqual(game.rooms.count, count - 1)
        XCTAssertThrowsError(try game.demolitionQuote(for: .room(room.id)))
        XCTAssertThrowsError(try game.demolitionQuote(for: .room(1)))
    }

    func testIncidentBlocksRoomDeletionAndElevatorQuoteReportsLostAccess() throws {
        var game = TowerState.demoTower()
        let room = try XCTUnwrap(game.rooms.first { $0.kind == .office })
        try game.triggerIncident(.fire, roomID: room.id)
        XCTAssertThrowsError(try game.demolitionQuote(for: .room(room.id)))
        let quote = try game.demolitionQuote(for: .elevator(1))
        XCTAssertEqual(quote.disconnectedRooms, game.rooms.count - 1)
        let cash = game.cash
        try game.removeElevator(1)
        XCTAssertEqual(game.cash, cash + quote.refund)
        XCTAssertFalse(game.isConnected(room.floor))
        XCTAssertThrowsError(try game.demolitionQuote(for: .elevator(1)))
    }

    func testBackupElevatorPreventsFalseLostAccessWarning() throws {
        var game = TowerState.demoTower()
        try game.addElevator(.standard, from: 0, to: 4)
        XCTAssertEqual(try game.demolitionQuote(for: .elevator(1)).disconnectedRooms, 0)
    }
}
