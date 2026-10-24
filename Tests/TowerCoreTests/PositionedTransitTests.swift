import XCTest
@testable import TowerCore

final class PositionedTransitTests:XCTestCase {
    private func lift(_ id:Int,at column:Int,from:Int=0,to:Int=4,position:Double=0,doors:Int=0) throws -> Elevator {
        var lift=Elevator(id:id,topFloor:to,position:position,direction:1,passengers:0)
        lift.bottomFloor=from;lift.doorTime=doors
        var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(lift)) as! [String:Any]
        json["column"]=column
        return try JSONDecoder().decode(Elevator.self,from:JSONSerialization.data(withJSONObject:json))
    }
    private func game(_ lifts:[Elevator],x:Double,phase:TravelPhase = .walkingToLift,route:[Int] = [2],floor:Int=0) -> TowerState {
        var game=TowerState.demoTower();game.minute=1;game.elevators=lifts
        game.travelers=[Traveler(id:999,roomID:game.rooms[0].id,floor:floor,destination:route.last!,x:x,destinationX:4,phase:phase,route:route)]
        return game
    }
    func testWalksToNearestUsableBankAndCompletesTrip() throws {
        var game=game([try lift(1,at:8),try lift(2,at:45)],x:50)
        game.updateTransit()
        XCTAssertEqual(game.activeTravelers[0].x,49.2,accuracy:0.001)
        var used:Set<Int>=[]
        for _ in 0..<200 {
            game.updateTransit()
            if let id=game.activeTravelers.first?.elevatorID { used.insert(id) }
        }
        XCTAssertEqual(used,[2]);XCTAssertEqual(game.completedTrips,1)
    }
    func testWalkingTargetFacesTheLiftRatherThanTheFinalRoom() throws {
        for (start, column, destination) in [(20.0,45,4.0),(40.0,8,60.0)] {
            var state=game([try lift(1,at:column)],x:start)
            state.travelers![0].destinationX=destination
            let person=state.activeTravelers[0]
            let target=try XCTUnwrap(state.walkingTarget(for:person))
            XCTAssertEqual(target,state.boardingColumn(for:state.elevators[0]))
            state.updateTransit()
            let movement=state.activeTravelers[0].x-start
            XCTAssertGreaterThan(movement*(target-start),0,"Facing must agree with actual motion")
            XCTAssertLessThan(movement*(destination-start),0,"Final room is deliberately in the opposite direction")
        }
    }
    func testWalkingTargetChangesForTransfersAndFinalRoomLeg() throws {
        var state=game([try lift(1,at:8,to:2),try lift(2,at:45,from:2)],x:9,route:[4],floor:2)
        XCTAssertEqual(state.walkingTarget(for:state.activeTravelers[0]),47.5)
        state.travelers![0].phase = .walkingToRoom
        XCTAssertEqual(state.walkingTarget(for:state.activeTravelers[0]),4)
        state.travelers![0].phase = .riding
        XCTAssertNil(state.walkingTarget(for:state.activeTravelers[0]))
    }
    func testDistantOpenCarCannotBoardOrReceiveWaitingCall() throws {
        var game=game([try lift(1,at:8,doors:8),try lift(2,at:45,position:2)],x:47.5,phase:.waiting)
        game.updateTransit()
        XCTAssertEqual(game.activeTravelers[0].phase,.waiting)
        XCTAssertNil(game.activeTravelers[0].elevatorID)
        XCTAssertEqual(game.elevators[1].targetFloor,0)
        game.elevators[0].doorTime=0
        game.updateTransit()
        XCTAssertFalse(game.elevators[0].doorsOpen)
        XCTAssertNil(game.elevators[0].targetFloor)
    }
    func testOldSavedQueueWalksFromShaftCenterToNewLanding() throws {
        var state=game([try lift(1,at:45)],x:46,phase:.waiting)
        state.travelers![0].boardingElevatorID=1
        state.updateTransit()
        XCTAssertEqual(state.activeTravelers[0].phase,.walkingToLift)
        XCTAssertEqual(state.activeTravelers[0].x,46.8,accuracy:0.001)
        state.updateTransit()
        XCTAssertEqual(state.activeTravelers[0].phase,.waiting)
        XCTAssertEqual(state.activeTravelers[0].x,47.5,accuracy:0.001)
        for _ in 0..<200 { state.updateTransit() }
        XCTAssertEqual(state.completedTrips,1)
    }
    func testTransferWalksAcrossFloorBeforeBoardingNextBank() throws {
        var game=game([try lift(1,at:8,to:2,position:2,doors:8),try lift(2,at:45,from:2,position:2,doors:8)],x:9,phase:.riding,route:[2,4])
        game.travelers![0].elevatorID=1
        game.updateTransit()
        XCTAssertEqual(game.activeTravelers[0].x,10.5)
        XCTAssertEqual(game.activeTravelers[0].floor,2)
        XCTAssertEqual(game.activeTravelers[0].phase,.walkingToLift)
        XCTAssertNil(game.activeTravelers[0].elevatorID)
        game.updateTransit()
        XCTAssertEqual(game.activeTravelers[0].x,11.3,accuracy:0.001)
        for _ in 0..<200 { game.updateTransit() }
        XCTAssertEqual(game.completedTrips,1)
    }
    func testEquidistantBanksChooseLowestIDRegardlessOfArrayOrder() throws {
        var game=game([try lift(9,at:20),try lift(2,at:10)],x:17.5)
        game.updateTransit()
        XCTAssertEqual(game.activeTravelers[0].x,16.7,accuracy:0.001)
    }
    func testNearbyBankThatCannotServeNextLegIsIgnored() throws {
        var game=game([try lift(1,at:45,to:1),try lift(2,at:8)],x:46)
        for _ in 0..<200 { game.updateTransit() }
        XCTAssertEqual(game.completedTrips,1)
    }
    func testPlacedBankNeedsEntireFootprintOnFloor() throws {
        var game=game([try lift(1,at:8)],x:9)
        game.floorSpans?[2]=FloorSpan(0,10)
        XCTAssertFalse(game.servedFloors(game.elevators[0]).contains(2))
        game.floorSpans?[2]=FloorSpan(0,11)
        XCTAssertTrue(game.servedFloors(game.elevators[0]).contains(2))
    }
}
