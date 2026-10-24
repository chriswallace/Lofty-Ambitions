import XCTest
@testable import TowerCore
final class SimulationTests: XCTestCase {
    func testConstructionRejectsOverlapAndDoesNotCharge() throws {
        var game = TowerState.demoTower()
        let money = game.cash
        XCTAssertThrowsError(try game.build(.office, floor: 1, slot: 0))
        XCTAssertEqual(game.cash, money)
    }
    func testConstructionRequiresFloorAndFunds() throws {
        var game = TowerState.demoTower()
        XCTAssertThrowsError(try game.build(.office, floor: 8, slot: 0))
        game.cash = 0
        XCTAssertThrowsError(try game.addFloor())
    }
    func testNewFloorAndRoomChargeExactCost() throws {
        var game = TowerState.demoTower()
        let oldCash = game.cash
        try game.addFloor()
        try game.build(.office, floor: game.topFloor, slot: 0)
        XCTAssertEqual(game.cash, oldCash - TowerState.floorCost - RoomKind.office.cost)
    }
    func testInaccessibleRoomsLoseOccupancy() throws {
        var game = TowerState.demoTower()
        try game.addFloor()
        let id = try game.build(.office, floor: game.topFloor, slot: 0)
        for _ in 0..<24 { game.advance(minutes: 60) }
        XCTAssertEqual(game.rooms.first { $0.id == id }!.occupancy, 0)
        try game.extendElevators()
        for _ in 0..<24 { game.advance(minutes: 60) }
        XCTAssertGreaterThan(game.rooms.first { $0.id == id }!.occupancy, 0)
    }
    func testDailyAccountingAndPersistenceRoundTrip() throws {
        var game = TowerState.demoTower()
        game.advance(minutes: 24 * 60)
        XCTAssertEqual(game.day, 2)
        XCTAssertEqual(game.history.count, 1)
        XCTAssertNotEqual(game.history[0].income, 0)
        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(TowerState.self, from: data)
        XCTAssertEqual(restored.cash, game.cash)
        XCTAssertEqual(restored.rooms, game.rooms)
        XCTAssertEqual(restored.minute, game.minute)
    }
    func testDemolitionRefundAndProtectedLobby() throws {
        var game = TowerState.demoTower()
        let lobby = game.rooms.first { $0.kind == .lobby }!
        XCTAssertThrowsError(try game.demolish(lobby.id))
        let office = game.rooms.first { $0.kind == .office }!
        let balance = game.cash
        try game.demolish(office.id)
        XCTAssertEqual(game.cash, balance + office.kind.cost / 2)
        XCTAssertFalse(game.rooms.contains { $0.id == office.id })
    }
    func testLockedRoomsAndOutOfBoundsAreRejected() throws {
        var game = TowerState.demoTower()
        XCTAssertThrowsError(try game.build(.hotel, floor: 1, slot: 10))
        XCTAssertThrowsError(try game.build(.office, floor: 1, slot: -1))
        XCTAssertThrowsError(try game.build(.office, floor: 1, slot: 63))
    }
}

extension SimulationTests {
    func testRoomsCannotCrossTheElevatorCore() throws {
        var game = TowerState.demoTower()
        try game.addFloor()
        XCTAssertThrowsError(try game.build(.office,floor:game.topFloor,slot:31))
    }
    func testProgressionAwardsOneGrantPerMilestone() throws {
        var game = TowerState.demoTower()
        let balance = game.cash
        game.advance(minutes:120)
        XCTAssertEqual(game.stars,2)
        XCTAssertEqual(game.cash,balance+20000)
        game.advance(minutes:120)
        XCTAssertEqual(game.cash,balance+20000)
    }
    func testHigherRentsReduceOccupancy() {
        var standard = TowerState.demoTower()
        var expensive = standard
        let id = standard.rooms.first { $0.kind == .office }!.id
        expensive.setRent(id,value:1.6)
        standard.advance(minutes:1440)
        expensive.advance(minutes:1440)
        XCTAssertLessThan(expensive.rooms.first { $0.id == id }!.occupancy,standard.rooms.first { $0.id == id }!.occupancy)
    }
    func testAdditionalElevatorsRelieveQueuePressureAndCharge() throws {
        var game = TowerState.demoTower()
        let room=game.rooms.first { $0.kind == .office }!
        game.travelers=(1...24).map { Traveler(id:$0,roomID:room.id,floor:0,destination:2,x:Double(game.core),destinationX:4,phase:.waiting,route:[2]) }
        let before = game.transportLoad
        let cash = game.cash
        try game.addElevator()
        XCTAssertLessThan(game.transportLoad,before)
        XCTAssertEqual(game.cash,cash-TowerState.elevatorCost)
    }
    func testHotelServiceRestoresHappiness() throws {
        var game = TowerState.demoTower()
        game.advance(minutes:120)
        try game.addFloor()
        try game.extendElevators()
        let hotel = try game.build(.hotel,floor:game.topFloor,slot:0)
        game.advance(minutes:180)
        let unserviced = game.rooms.first { $0.id == hotel }!.happiness
        try game.build(.housekeeping,floor:game.topFloor,slot:16)
        game.advance(minutes:180)
        XCTAssertGreaterThan(game.rooms.first { $0.id == hotel }!.happiness,unserviced)
    }
    func testTimeChunkingProducesIdenticalState() throws {
        var a = TowerState.demoTower()
        var b = a
        a.advance(minutes:2880)
        for _ in 0..<288 { b.advance(minutes:10) }
        XCTAssertEqual(a.cash,b.cash)
        XCTAssertEqual(a.rooms,b.rooms)
        XCTAssertEqual(a.history,b.history)
        XCTAssertEqual(a.elevators,b.elevators)
    }
    func testCorruptSaveIsRejected() throws {
        var game = TowerState.demoTower()
        game.topFloor = -1
        XCTAssertThrowsError(try game.validated())
        game = .demoTower(); game.rooms[1].occupancy = .nan
        XCTAssertThrowsError(try game.validated())
        game = .demoTower(); game.rooms.append(game.rooms[1])
        XCTAssertThrowsError(try game.validated())
    }
}
