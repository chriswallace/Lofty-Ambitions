import XCTest
@testable import TowerCore

final class RoomStyleTests: XCTestCase {
    func tower(seed: UInt64 = 42) throws -> TowerState {
        var game = TowerState.newGame(scenerySeed: seed)
        game.cash = 2_000_000
        try game.addFloor()
        return game
    }
    func testNewRowsNeverRepeatAdjacentStylesAndAreReproducible() throws {
        var drawn = Set<RoomStyle>()
        for kind in [RoomKind.office, .apartment] {
            for seed in 1...12 {
                var game = try tower(seed: UInt64(seed))
                var replay = game
                let slots = Array(stride(from: 0, through: 45, by: kind.width))
                for slot in slots.reversed() {
                    try game.build(kind, floor: 1, slot: slot)
                    try replay.build(kind, floor: 1, slot: slot)
                }
                let rooms = game.rooms.filter { $0.kind == kind }.sorted { $0.slot < $1.slot }
                for (left,right) in zip(rooms, rooms.dropFirst()) { XCTAssertNotEqual(left.effectiveStyle,right.effectiveStyle) }
                XCTAssertEqual(game.rooms,replay.rooms)
                drawn.formUnion(rooms.map(\.effectiveStyle))
            }
        }
        XCTAssertEqual(drawn,Set(RoomStyle.allCases))
    }
    func testGapBuildAvoidsBothNeighborsAndManualChoiceIsFree() throws {
        var game = try tower()
        let left = try game.build(.apartment,floor:1,slot:0)
        let right = try game.build(.apartment,floor:1,slot:8)
        try game.setRoomStyle(left,style:.one)
        try game.setRoomStyle(right,style:.two)
        let middle = try game.build(.apartment,floor:1,slot:4)
        XCTAssertEqual(game.rooms.first { $0.id == middle }?.style,.three)
        let cash = game.cash
        let rooms = game.rooms
        try game.setRoomStyle(middle,style:.one)
        XCTAssertEqual(game.cash,cash)
        XCTAssertEqual(game.rooms.count,rooms.count)
        XCTAssertEqual(game.rooms.first { $0.id == middle }?.occupancy,rooms.first { $0.id == middle }?.occupancy)
        XCTAssertEqual(game.rooms.first { $0.id == middle }?.artworkName,"apartment")
    }
    func testStylePersistsAndLegacyRoomsRetainOriginalArt() throws {
        var game = try tower()
        let id = try game.build(.office,floor:1,slot:0)
        try game.setRoomStyle(id,style:.three)
        let loaded = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(loaded.rooms,game.rooms)
        XCTAssertEqual(loaded.rooms.last?.artworkName,"office3")
        game.rooms[1].style = nil
        let legacy = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(legacy.rooms[1].effectiveStyle,.one)
        XCTAssertEqual(legacy.rooms[1].artworkName,"office")
        XCTAssertThrowsError(try game.setRoomStyle(1,style:.two))
        game.rooms[0].style = .two
        XCTAssertThrowsError(try game.validated())
    }
    func testActiveIncidentPreventsStyleChange() throws {
        var game = try tower()
        let id = try game.build(.office,floor:1,slot:0)
        try game.triggerIncident(.fire,roomID:id)
        let before = game.rooms
        XCTAssertThrowsError(try game.setRoomStyle(id,style:.three))
        XCTAssertEqual(game.rooms,before)
    }
    func testLuxuryUnlockEconomyLeasingIncidentsAndPersistence() throws {
        var game = try tower()
        game.earnedStars = 3
        let cash = game.cash
        XCTAssertThrowsError(try game.build(.luxuryApartment,floor:1,slot:0))
        XCTAssertEqual(game.cash,cash)
        game.earnedStars = 4
        let id = try game.build(.luxuryApartment,floor:1,slot:0)
        XCTAssertEqual(game.cash,cash-RoomKind.luxuryApartment.cost)
        XCTAssertTrue(game.level.unlocks.contains { $0.kind == .luxuryApartment })
        XCTAssertEqual(RoomCatalog.search(query:"luxury",category:.homes).map(\.kind),[.luxuryApartment])
        try game.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        game.rooms[1].occupancy = 0.5
        XCTAssertGreaterThan(game.income(for:game.rooms[1]),0)
        try game.triggerIncident(.rentArrears,roomID:id)
        let loaded = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(loaded.rooms,game.rooms)
        XCTAssertEqual(loaded.rooms[1].screeningPolicy,.strict)
        XCTAssertThrowsError(try game.setRoomStyle(id,style:.two))
    }
}
