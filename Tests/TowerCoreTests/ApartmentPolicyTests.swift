import XCTest
@testable import TowerCore

final class ApartmentPolicyTests:XCTestCase {
    func apartmentTower() throws -> (TowerState,Int) {
        var game=TowerState.newGame()
        try game.addFloor()
        let id=try game.build(.apartment,floor:1,slot:0)
        try game.addElevator(.standard,at:8,from:0,to:1)
        return (game,id)
    }
    func apartment(_ game:TowerState,_ id:Int)->Room {game.rooms.first{$0.id==id}!}

    func testStrictChecksAndDepositsSlowMoveInsAndLowerNewTenantRisk() throws {
        var (normal,id)=try apartmentTower()
        var strict=normal
        let cash=strict.cash
        try strict.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        XCTAssertEqual(strict.cash,cash)
        normal.advance(minutes:600);strict.advance(minutes:600)
        XCTAssertGreaterThan(apartment(strict,id).occupancy,0)
        XCTAssertLessThan(apartment(strict,id).occupancy,apartment(normal,id).occupancy)
        XCTAssertEqual(apartment(strict,id).effectiveDefaultRisk,0.18,accuracy:0.000001)
        XCTAssertEqual(apartment(normal,id).effectiveDefaultRisk,1,accuracy:0.000001)
    }
    func testChecksAndDepositsEachHaveIndependentTradeoffs() throws {
        let (initial,id)=try apartmentTower()
        var normal=initial,checked=initial,deposited=initial
        try checked.setApartmentPolicy(id,screening:.thorough,deposit:.none)
        try deposited.setApartmentPolicy(id,screening:.standard,deposit:.oneMonth)
        normal.advance(minutes:300);checked.advance(minutes:300);deposited.advance(minutes:300)
        for game in [checked,deposited] {
            XCTAssertLessThan(apartment(game,id).occupancy,apartment(normal,id).occupancy)
            XCTAssertLessThan(apartment(game,id).effectiveDefaultRisk,apartment(normal,id).effectiveDefaultRisk)
        }
    }
    func testPolicyChangesDoNotRetroactivelyRescreenExistingTenants() throws {
        var (game,id)=try apartmentTower()
        game.advance(minutes:300)
        let before=apartment(game,id)
        try game.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        XCTAssertEqual(apartment(game,id).occupancy,before.occupancy)
        XCTAssertEqual(apartment(game,id).effectiveDefaultRisk,before.effectiveDefaultRisk)
        game.advance(minutes:30)
        let after=apartment(game,id)
        let newTenants=after.occupancy-before.occupancy
        let expected=(before.occupancy+newTenants*0.18)/after.occupancy
        XCTAssertEqual(after.effectiveDefaultRisk,expected,accuracy:0.000001)
        XCTAssertGreaterThan(after.effectiveDefaultRisk,0.18)
    }
    func testStricterPolicyDoesNotSlowMoveOuts() throws {
        var (normal,id)=try apartmentTower()
        normal.advance(minutes:300)
        var strict=normal
        try strict.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        normal.elevators=[];strict.elevators=[]
        normal.advance(minutes:60);strict.advance(minutes:60)
        XCTAssertEqual(apartment(normal,id).occupancy,apartment(strict,id).occupancy)
    }
    func testScreenedTenantsActuallyDefaultLessOften() throws {
        var (normal,id)=try apartmentTower()
        var strict=normal
        try strict.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        normal.advance(minutes:300);strict.advance(minutes:300)
        var normalDefaults=0,strictDefaults=0
        for day in 3...365 where day%2 != 0 && day%7 != 0 {
            var a=normal,b=strict
            a.day=day;b.day=day;a.minute=599;b.minute=599
            a.advance(minutes:1);b.advance(minutes:1)
            if apartment(a,id).incident?.kind == .rentArrears {normalDefaults += 1}
            if apartment(b,id).incident?.kind == .rentArrears {strictDefaults += 1}
        }
        XCTAssertGreaterThan(strictDefaults,0)
        XCTAssertLessThan(strictDefaults,normalDefaults/2)
        XCTAssertGreaterThan(normalDefaults,100)
    }
    func testPolicyAndTenantRiskSurviveSaveAndLoad() throws {
        var (game,id)=try apartmentTower()
        try game.setApartmentPolicy(id,screening:.thorough,deposit:.oneMonth)
        game.advance(minutes:120)
        var loaded=try JSONDecoder().decode(TowerState.self,from:JSONEncoder().encode(game)).validated()
        XCTAssertEqual(loaded.rooms,game.rooms)
        game.advance(minutes:600)
        for _ in 0..<60 {loaded.advance(minutes:10)}
        XCTAssertEqual(loaded.rooms,game.rooms)
        XCTAssertEqual(loaded.cash,game.cash)
    }
    func testOldSavesDefaultToStandardChecksAndNoDeposit() throws {
        var (game,id)=try apartmentTower()
        try game.setApartmentPolicy(id,screening:.strict,deposit:.twoMonths)
        game.advance(minutes:30)
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(game)) as! [String:Any]
        var rooms=object["rooms"] as! [[String:Any]]
        for i in rooms.indices {
            for key in ["screening","depositRequirement","tenantDefaultRisk"] {rooms[i].removeValue(forKey:key)}
        }
        object["rooms"]=rooms
        let old=try JSONDecoder().decode(TowerState.self,from:JSONSerialization.data(withJSONObject:object)).validated()
        XCTAssertEqual(apartment(old,id).screeningPolicy,.standard)
        XCTAssertEqual(apartment(old,id).depositPolicy,.none)
        XCTAssertEqual(apartment(old,id).effectiveDefaultRisk,1)
    }
    func testPoliciesOnlyApplyToApartmentsAndRejectCorruptRisk() throws {
        var (game,id)=try apartmentTower()
        XCTAssertThrowsError(try game.setApartmentPolicy(game.rooms[0].id,screening:.strict,deposit:.twoMonths))
        XCTAssertThrowsError(try game.setApartmentPolicy(-1,screening:.strict,deposit:.twoMonths))
        let index=game.rooms.firstIndex{$0.id==id}!
        game.rooms[index].tenantDefaultRisk = .nan
        XCTAssertThrowsError(try game.validated())
        game.rooms[index].tenantDefaultRisk = 1.5
        XCTAssertThrowsError(try game.validated())
    }
}
