import XCTest
@testable import TowerCore

final class IncidentTests: XCTestCase {
    func hotelTower() throws -> (TowerState, Int, Int) {
        var game = TowerState.demoTower()
        game.earnedStars = 2
        try game.addFloor()
        try game.extendElevators()
        let hotel = try game.build(.hotel, floor:5, slot:0)
        let cleaner = try game.build(.housekeeping, floor:5, slot:16)
        game.rooms[game.rooms.firstIndex { $0.id == hotel }!].occupancy = 0.8
        return (game, hotel, cleaner)
    }
    func room(_ id:Int, in game:TowerState) -> Room { game.rooms.first { $0.id == id }! }

    // Removing incident income suppression would fail this test.
    func testPartyClosesSuiteUntilHousekeepingFinishes() throws {
        var (game, id, _) = try hotelTower()
        try game.triggerIncident(.party, roomID:id)
        XCTAssertEqual(game.income(for:room(id,in:game)),0)
        XCTAssertEqual(game.signal(for:room(id,in:game))?.mood,.angry)
        game.advance(minutes:120)
        XCTAssertEqual(room(id,in:game).incident?.stage,.awaitingCleaning)
        try game.respond(to:id,action:.sendHousekeeping)
        game.advance(minutes:179)
        XCTAssertEqual(room(id,in:game).incident?.stage,.cleaning)
        game.advance(minutes:1)
        XCTAssertEqual(room(id,in:game).incident?.stage,.resolved)
        XCTAssertEqual(game.signal(for:room(id,in:game))?.mood,.relieved)
        XCTAssertGreaterThan(game.income(for:room(id,in:game)),0)
    }
    func testHousekeepingHasOneJobAndReleasesRoomWhenTeamRemoved() throws {
        var (game,id,cleaner) = try hotelTower()
        let second = try game.build(.hotel,floor:5,slot:32)
        for target in [id,second] { try game.triggerIncident(.party,roomID:target) }
        game.advance(minutes:120)
        try game.respond(to:id,action:.sendHousekeeping)
        XCTAssertThrowsError(try game.respond(to:second,action:.sendHousekeeping))
        try game.demolish(cleaner)
        game.advance(minutes:1)
        XCTAssertEqual(room(id,in:game).incident?.stage,.awaitingCleaning)
        XCTAssertNotNil(game.responseBlocker(for:room(id,in:game),action:.sendHousekeeping))
    }
    func testRentArrearsKeepTenantsUntilCourtAndEviction() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .apartment }!.id
        let occupied = room(id,in:game).occupancy
        try game.triggerIncident(.rentArrears,roomID:id)
        XCTAssertThrowsError(try game.respond(to:id,action:.evict))
        XCTAssertThrowsError(try game.demolish(id))
        try game.respond(to:id,action:.serveNotice)
        XCTAssertThrowsError(try game.respond(to:id,action:.fileCourtCase))
        game.advance(minutes:1440)
        XCTAssertEqual(room(id,in:game).occupancy,occupied)
        XCTAssertEqual(game.income(for:room(id,in:game)),0)
        XCTAssertGreaterThan(room(id,in:game).incident!.arrears,0)
        let cash = game.cash
        try game.respond(to:id,action:.fileCourtCase)
        XCTAssertEqual(game.cash,cash-500)
        game.advance(minutes:2880)
        XCTAssertEqual(room(id,in:game).incident?.stage,.evictionApproved)
        try game.respond(to:id,action:.evict)
        game.advance(minutes:120)
        XCTAssertEqual(room(id,in:game).occupancy,0)
        XCTAssertEqual(room(id,in:game).incident?.stage,.resolved)
        XCTAssertEqual(room(id,in:game).incident?.arrears,0)
    }
    func testFireDispatchWorksWithoutCashAndRequiresRepair() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .office }!.id
        try game.triggerIncident(.fire,roomID:id)
        XCTAssertEqual(room(id,in:game).people,0)
        XCTAssertEqual(game.income(for:room(id,in:game)),0)
        XCTAssertEqual(game.signal(for:room(id,in:game))?.mood,.alarmed)
        game.cash = 0
        let expenses = game.dailyExpenses
        try game.respond(to:id,action:.dispatchFireDepartment)
        XCTAssertEqual(game.dailyExpenses,expenses+1500)
        XCTAssertEqual(room(id,in:game).incident?.responseRoute,.ladder)
        game.advance(minutes:30)
        XCTAssertEqual(room(id,in:game).incident?.stage,.extinguishing)
        game.advance(minutes:180)
        XCTAssertEqual(room(id,in:game).incident?.stage,.awaitingRepairs)
        game.cash = 0 // A star promotion during the response may have awarded a grant.
        XCTAssertThrowsError(try game.respond(to:id,action:.repair))
        game.cash = 20000
        let cost = game.repairCost(for:room(id,in:game))
        try game.respond(to:id,action:.repair)
        XCTAssertEqual(game.cash,20000-cost)
        game.advance(minutes:240)
        XCTAssertEqual(room(id,in:game).incident?.stage,.resolved)
    }
    func testUpperFloorFireUsesInteriorResponse() throws {
        var game = TowerState.demoTower()
        game.cash = 1000000
        for _ in 0..<4 { try game.addFloor() }
        let id = try game.build(.office,floor:8,slot:0)
        try game.triggerIncident(.fire,roomID:id)
        try game.respond(to:id,action:.dispatchFireDepartment)
        XCTAssertEqual(room(id,in:game).incident?.responseRoute,.interior)
        game.advance(minutes:84+180)
        XCTAssertEqual(room(id,in:game).incident?.stage,.awaitingRepairs)
    }
    func testIncidentPersistenceAndOldSaveWithoutIncident() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .office }!.id
        try game.triggerIncident(.fire,roomID:id)
        try game.respond(to:id,action:.dispatchFireDepartment)
        game.advance(minutes:45)
        let data = try JSONEncoder().encode(game)
        var restored = try JSONDecoder().decode(TowerState.self,from:data).validated()
        XCTAssertEqual(restored.rooms,game.rooms)
        restored.advance(minutes:165)
        XCTAssertEqual(room(id,in:restored).incident?.stage,.awaitingRepairs)
        var json = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var rooms = json["rooms"] as! [[String:Any]]
        for i in rooms.indices { rooms[i].removeValue(forKey:"incident") }
        json["rooms"] = rooms
        let old = try JSONDecoder().decode(TowerState.self,from:JSONSerialization.data(withJSONObject:json)).validated()
        XCTAssertTrue(old.rooms.allSatisfy { $0.incident == nil })
    }
    func testInvalidStageTimerOrReferenceIsRejected() throws {
        var game = TowerState.demoTower()
        let index = game.rooms.firstIndex { $0.kind == .office }!
        try game.triggerIncident(.fire,roomID:game.rooms[index].id)
        var broken = game
        broken.rooms[index].incident?.stage = .courtPending
        XCTAssertThrowsError(try broken.validated())
        broken = game; broken.rooms[index].incident?.remainingMinutes = -1
        XCTAssertThrowsError(try broken.validated())
        broken = game; broken.rooms[index].incident?.severity = .nan
        XCTAssertThrowsError(try broken.validated())
        broken = game; broken.rooms[index].incident?.responderRoomID = 9999
        XCTAssertThrowsError(try broken.validated())
    }
    func testTriggerAndResponseErrorsAreAtomic() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .office }!.id
        let before = try JSONEncoder().encode(game)
        XCTAssertThrowsError(try game.triggerIncident(.party,roomID:id))
        XCTAssertEqual(try JSONEncoder.sorted.encode(game),try JSONEncoder.sorted.encode(JSONDecoder().decode(TowerState.self,from:before)))
        try game.triggerIncident(.fire,roomID:id)
        XCTAssertThrowsError(try game.triggerIncident(.fire,roomID:id))
        XCTAssertThrowsError(try game.respond(to:id,action:.fileCourtCase))
        XCTAssertEqual(room(id,in:game).incident?.stage,.burning)
    }
    func testOrdinaryWarningsAndSadTenantsHaveSignals() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .apartment }!.id
        game.setRent(id,value:1.6)
        XCTAssertEqual(game.signal(for:room(id,in:game))?.mood,.angry)
        game.setRent(id,value:1)
        game.rooms[game.rooms.firstIndex { $0.id == id }!].happiness = 0.2
        XCTAssertEqual(game.signal(for:room(id,in:game))?.mood,.sad)
        try game.addFloor()
        let upper = try game.build(.office,floor:5,slot:0)
        XCTAssertNotNil(game.signal(for:room(upper,in:game)))
    }
    func testBurnedRestaurantStopsProvidingFoodComfort() throws {
        var game = TowerState.demoTower()
        game.advance(minutes:30)
        let office = game.rooms.first { $0.kind == .office }!.id
        let restaurant = game.rooms.first { $0.kind == .restaurant }!.id
        let before = room(office,in:game).happiness
        try game.triggerIncident(.fire,roomID:restaurant)
        game.advance(minutes:30)
        XCTAssertLessThan(room(office,in:game).happiness,before)
    }
    func testSaveRejectsOccupiedFireRoom() throws {
        var game = TowerState.demoTower()
        let index = game.rooms.firstIndex { $0.kind == .office }!
        try game.triggerIncident(.fire,roomID:game.rooms[index].id)
        game.rooms[index].occupancy = 0.5
        XCTAssertThrowsError(try game.validated())
    }
    func testClosedHotelDoesNotGenerateVisitorJourneys() throws {
        var (game,id,_) = try hotelTower()
        try game.triggerIncident(.party,roomID:id)
        game.advance(minutes:120)
        XCTAssertThrowsError(try game.requestTrip(roomID:id,from:0,to:5))
        game.advance(minutes:300)
        XCTAssertFalse(game.activeTravelers.contains { $0.roomID == id })
    }
    func testDisconnectedHousekeepingCannotClean() throws {
        var (game,id,_) = try hotelTower()
        try game.triggerIncident(.party,roomID:id)
        game.advance(minutes:120)
        game.elevators[0].topFloor = 4
        XCTAssertThrowsError(try game.respond(to:id,action:.sendHousekeeping))
        XCTAssertEqual(room(id,in:game).incident?.stage,.awaitingCleaning)
    }
    func testNoisyPartyUpsetsNeighborsAndProvidesSignal() throws {
        var (game,id,_) = try hotelTower()
        let neighbor = try game.build(.apartment,floor:5,slot:32)
        game.advance(minutes:30)
        let before = room(neighbor,in:game).happiness
        try game.triggerIncident(.party,roomID:id)
        game.advance(minutes:30)
        XCTAssertLessThan(room(neighbor,in:game).happiness,before)
        XCTAssertEqual(game.signal(for:room(neighbor,in:game))?.mood,.angry)
    }
    func testEvacuatedRoomsCannotReceiveVisitorsOrRefill() throws {
        var game = TowerState.demoTower()
        let id = game.rooms.first { $0.kind == .office }!.id
        try game.requestTrip(roomID:id,from:0,to:2)
        try game.triggerIncident(.fire,roomID:id)
        XCTAssertFalse(game.activeTravelers.contains { $0.roomID == id })
        XCTAssertThrowsError(try game.requestTrip(roomID:id,from:0,to:2))
        game.advance(minutes:300)
        XCTAssertEqual(room(id,in:game).occupancy,0)
        XCTAssertEqual(game.income(for:room(id,in:game)),0)
        XCTAssertEqual(room(id,in:game).incident?.stage,.burning)
    }
    func testEveryTimedStageCanSaveAndResumeAndReliefExpires() throws {
        var (game,id,_) = try hotelTower()
        try game.triggerIncident(.party,roomID:id)
        for minutes in [30,90] {
            game.advance(minutes:minutes)
            game = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        }
        try game.respond(to:id,action:.sendHousekeeping)
        game.advance(minutes:50)
        var loaded = try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        game.advance(minutes:130); loaded.advance(minutes:130)
        XCTAssertEqual(game.rooms,loaded.rooms)
        XCTAssertEqual(room(id,in:game).incident?.stage,.resolved)
        game.advance(minutes:180)
        XCTAssertNil(room(id,in:game).incident)
    }
    func testAutomaticIncidentsAreDeterministicAndGracePeriodIsQuiet() throws {
        var a = TowerState.demoTower()
        a.advance(minutes:1440)
        XCTAssertTrue(a.rooms.allSatisfy { $0.incident == nil })
        a.day = 3; a.minute = 599
        var b = a
        a.advance(minutes:1)
        b.advance(minutes:1)
        XCTAssertTrue(a.rooms.contains { $0.incident?.isActive == true })
        XCTAssertEqual(a.rooms,b.rooms)
        a.advance(minutes:400)
        for _ in 0..<40 { b.advance(minutes:10) }
        XCTAssertEqual(a.rooms,b.rooms)
        XCTAssertEqual(a.cash,b.cash)
    }
}

private extension JSONEncoder {
    static var sorted:JSONEncoder { let e=JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
}
