import XCTest
@testable import TowerCore

final class ConstructionSimulationTests:XCTestCase {
    func testFineGridFitsFourApartmentsInSixteenCells() throws {
        var game = TowerState.demoTower()
        try game.addFloor()
        let ids = try game.buildRow(.apartment,floor:game.topFloor,from:0,to:12)
        XCTAssertEqual(ids.count,4)
        XCTAssertEqual(game.rooms.filter { ids.contains($0.id) }.map(\.slot),[0,4,8,12])
        XCTAssertEqual(RoomKind.office.width,9)
    }
    func testWideningCreatesBuildableSpaceAndPreservesExistingRooms() throws {
        var game = TowerState.demoTower()
        let rooms = game.rooms
        let cash = game.cash
        try game.widenTower(left:false)
        XCTAssertEqual(game.rightEdge,72)
        XCTAssertEqual(game.rooms,rooms)
        XCTAssertEqual(game.cash,cash-(game.topFloor+1)*8*TowerState.cellCost)
        XCTAssertNoThrow(try game.build(.apartment,floor:2,slot:64))
    }
    func testUnsupportedFloorExpansionDoesNotCharge() throws {
        var game = TowerState.demoTower()
        let cash = game.cash
        XCTAssertThrowsError(try game.constructFloor(floor:2,from:64,to:70))
        XCTAssertEqual(game.cash,cash)
        try game.constructFloor(floor:0,from:-8,to:-1)
        try game.constructFloor(floor:1,from:-8,to:-1)
        XCTAssertEqual(game.span(1).left,-8)
    }
    func testDragBuildIsAtomicWhenBudgetRunsOut() throws {
        var game = TowerState.demoTower()
        try game.addFloor()
        game.cash = RoomKind.office.cost+10
        let rooms=game.rooms
        XCTAssertThrowsError(try game.buildRow(.office,floor:game.topFloor,from:0,to:18))
        XCTAssertEqual(game.rooms,rooms)
        XCTAssertEqual(game.cash,RoomKind.office.cost+10)
    }
    func testPassengersQueueBoardAndLeaveAtDestination() throws {
        var game = TowerState.demoTower()
        let room = game.rooms.first { $0.kind == .office && $0.floor == 2 }!
        game.minute=1
        game.travelers=[Traveler(id:999,roomID:room.id,floor:0,destination:2,x:Double(game.core),destinationX:4,phase:.waiting,route:[2])]
        var boarded=false,arrived=false,stopped=false
        for _ in 0..<200 {
            game.updateTransit()
            if let person=game.activeTravelers.first(where:{$0.id==999}) {
                boarded = boarded || person.phase == .riding
                arrived = arrived || (person.phase == .walkingToRoom && person.floor == 2)
            }
            if game.elevators[0].doorsOpen && game.elevators[0].position == 2 { stopped=true }
        }
        XCTAssertTrue(boarded)
        XCTAssertTrue(arrived)
        XCTAssertTrue(stopped)
        XCTAssertFalse(game.activeTravelers.contains { $0.id==999 })
        XCTAssertEqual(game.completedTrips,1)
    }
    func testWideCarBoardsMorePassengersWithoutExceedingCapacity() throws {
        var standard = TowerState.demoTower()
        standard.minute=1
        let room=standard.rooms.first { $0.kind == .office }!
        standard.travelers=(1...30).map { Traveler(id:$0,roomID:room.id,floor:0,destination:2,x:Double(standard.core),destinationX:4,phase:.waiting,route:[2]) }
        var wide=standard;wide.elevators[0].type = .wide
        for _ in 0..<3 { standard.updateTransit();wide.updateTransit() }
        XCTAssertEqual(standard.elevators[0].passengers,12)
        XCTAssertEqual(wide.elevators[0].passengers,24)
        XCTAssertEqual(standard.queueCount,18)
        XCTAssertEqual(wide.queueCount,6)
    }
    func testStandardRangeAndExpressTransfersAboveThirtyFloors() throws {
        var game = TowerState.demoTower()
        game.cash=10_000_000
        for _ in 0..<46 { try game.addFloor() }
        XCTAssertThrowsError(try game.addElevator(.standard,from:0,to:30))
        try game.addElevator(.express,from:0,to:50)
        XCTAssertEqual(game.elevators.last!.stops,[0,15,30,45])
        XCTAssertFalse(game.isConnected(49))
        try game.addElevator(.standard,from:45,to:50)
        XCTAssertTrue(game.isConnected(49))
        XCTAssertEqual(game.route(from:0,to:49),[45,49])
        XCTAssertEqual(game.route(from:49,to:0),[45,0])
    }
    func testPassengersTransferFromExpressToLocal() throws {
        var game = TowerState.demoTower();game.cash=10_000_000
        for _ in 0..<46 { try game.addFloor() }
        try game.addElevator(.express,from:0,to:50)
        try game.addElevator(.standard,from:45,to:50)
        let room=try game.build(.office,floor:49,slot:0)
        game.minute=1
        game.travelers=[Traveler(id:999,roomID:room,floor:0,destination:49,x:Double(game.core),destinationX:4,phase:.waiting,route:[45,49])]
        var used:Set<Int>=[]
        for _ in 0..<500 {
            game.updateTransit()
            if let car=game.activeTravelers.first?.elevatorID { used.insert(car) }
        }
        XCTAssertEqual(used,Set([2,3]))
        XCTAssertEqual(game.completedTrips,1)
    }
    func testLegacySaveMigrationKeepsRoomCountAndTreasury() throws {
        var old=TowerState.demoTower()
        old.version=1;old.floorSpans=nil;old.coreColumn=nil;old.rooms=Array(old.rooms.prefix(2));old.rooms[1].slot=0
        let migrated=try old.validated()
        XCTAssertEqual(migrated.version,2)
        XCTAssertEqual(migrated.rooms.count,old.rooms.count)
        XCTAssertEqual(migrated.cash,old.cash)
        XCTAssertEqual(migrated.rightEdge,120)
    }
}

extension ConstructionSimulationTests {
    func testFloorMustReachTheShaftBeforeTenantsCanUseIt() throws {
        var game=TowerState.demoTower()
        try game.constructFloor(floor:5,from:0,to:8)
        try game.extendElevators()
        XCTAssertFalse(game.isConnected(5))
        try game.constructFloor(floor:5,from:8,to:32)
        XCTAssertTrue(game.isConnected(5))
    }
    func testTransitStateSurvivesSaveAndLoad() throws {
        var game=TowerState.demoTower()
        game.advance(minutes:180)
        let data=try JSONEncoder().encode(game)
        let restored=try JSONDecoder().decode(TowerState.self,from:data).validated()
        XCTAssertEqual(restored.travelers,game.travelers)
        XCTAssertEqual(restored.elevators,game.elevators)
        XCTAssertEqual(restored.floorSpans,game.floorSpans)
        XCTAssertGreaterThan(game.completedTrips,0)
    }
}
