import XCTest
import TowerArt
@testable import TowerCore

final class RoomActivityTests: XCTestCase {
    func room(_ kind: RoomKind, id: Int = 12, occupancy: Double = 1, style: RoomStyle? = nil) -> Room {
        Room(id:id,kind:kind,floor:1,slot:0,occupancy:occupancy,rent:1,happiness:0.8,style:style)
    }
    func testFurniturePosesAndNighttimeRest() {
        for style in RoomStyle.allCases {
            let office = RoomActivity.occupants(in:room(.office,style:style),minute:720,elapsed:0,reducedMotion:true)
            XCTAssertTrue(office.allSatisfy { $0.pose == .working })
            for kind in [RoomKind.apartment,.luxuryApartment] {
                let home = room(kind,style:kind == .apartment ? style:nil)
                XCTAssertEqual(RoomActivity.occupants(in:home,minute:720,elapsed:0,reducedMotion:true).first?.pose,.reading)
                XCTAssertEqual(RoomActivity.occupants(in:home,minute:60,elapsed:0,reducedMotion:true).first?.pose,.resting)
            }
        }
    }
    func testActivityMovesOverTimeButFreezesWithClockAndReduceMotion() {
        let office = room(.office)
        let start = RoomActivity.occupants(in:office,minute:720,elapsed:0)
        XCTAssertEqual(start,RoomActivity.occupants(in:office,minute:720,elapsed:0))
        var snapshots = [[RoomOccupant]]()
        for time in stride(from:0.0,to:60.0,by:2) { snapshots.append(RoomActivity.occupants(in:office,minute:720,elapsed:time)) }
        XCTAssertTrue(snapshots.contains { $0.contains { $0.pose == .walking } })
        XCTAssertTrue(snapshots.contains { $0 != start })
        XCTAssertEqual(RoomActivity.occupants(in:office,minute:720,elapsed:0,reducedMotion:true),RoomActivity.occupants(in:office,minute:720,elapsed:55,reducedMotion:true))
        XCTAssertNotEqual(RoomActivity.occupants(in:office,minute:720,elapsed:5).map(\.position),RoomActivity.occupants(in:room(.office,id:13),minute:720,elapsed:5).map(\.position))
    }
    func testNoAmbientPeopleInVacantClosedOrEvacuatedRooms() {
        XCTAssertTrue(RoomActivity.occupants(in:room(.office,occupancy:0),minute:720,elapsed:0).isEmpty)
        XCTAssertTrue(RoomActivity.occupants(in:room(.office),minute:0,elapsed:0).isEmpty)
        for stage in [IncidentStage.burning,.awaitingRepairs,.repairing] {
            var home = room(.apartment)
            home.incident = RoomIncident(kind:.fire,stage:stage,severity:1)
            XCTAssertTrue(RoomActivity.occupants(in:home,minute:720,elapsed:0).isEmpty)
        }
        XCTAssertLessThan(RoomActivity.occupants(in:room(.office,occupancy:0.2),minute:720,elapsed:0).count,RoomActivity.occupants(in:room(.office),minute:720,elapsed:0).count)
    }
    func testSleepingResidentsStayInBedForWholeActivityCycle() {
        for kind in [RoomKind.apartment, .luxuryApartment] {
            for elapsed in stride(from:0.0,to:120.0,by:0.25) {
                let resident = RoomActivity.occupants(in:room(kind),minute:60,elapsed:elapsed).first
                XCTAssertEqual(resident?.pose,.resting)
                XCTAssertEqual(resident?.position,RoomActivity.occupants(in:room(kind),minute:60,elapsed:0).first?.position)
            }
        }
    }
    func testWalkingUsesGroundedPausesAndStableWorldSpeed() throws {
        let atlas = try TowerAtlas()
        for kind in [RoomKind.apartment,.office,.shop,.bookshop,.luxuryApartment] {
            let occupied = room(kind)
            let rect = CGRect(x:0,y:0,width:kind.width*8,height:24)
            let mapX: (CGFloat) -> CGFloat = { atlas.roomPoint(CGPoint(x:$0,y:0),name:occupied.artworkName,in:rect).x }
            var previous = RoomActivity.occupants(in:occupied,minute:720,elapsed:0,worldX:mapX)
            var walkingFrames = 0
            var standingFrames = 0
            for tick in 1...6000 {
                let people = RoomActivity.occupants(in:occupied,minute:720,elapsed:Double(tick)/100,worldX:mapX)
                for (before,person) in zip(previous,people) {
                    if person.pose == .walking || person.pose == .standing {
                        XCTAssertEqual(person.position.y,RoomActivity.floorY(for:occupied),accuracy:0.000001)
                    }
                    if person.pose == .standing { standingFrames += 1 }
                    if before.pose == .walking && person.pose == .walking && before.facingLeft == person.facingLeft {
                        let delta = mapX(person.position.x)-mapX(before.position.x)
                        XCTAssertEqual(abs(delta),0.04,accuracy:0.00001)
                        XCTAssertEqual(person.facingLeft,delta < 0)
                        XCTAssertEqual(person.walkDistance-before.walkDistance,0.04,accuracy:0.00001)
                        walkingFrames += 1
                    }
                    // Turning and leaving furniture happen while standing, never in a walking frame.
                    if person.pose == .walking && before.pose != .walking { XCTAssertEqual(before.pose,.standing) }
                    if before.pose == .walking && person.pose != .walking { XCTAssertEqual(person.pose,.standing) }
                }
                previous = people
            }
            XCTAssertGreaterThan(walkingFrames,0)
            XCTAssertGreaterThan(standingFrames,0)
        }
    }
    func testLuxuryResidentsWalkOnClearFloorInFrontOfBed() throws {
        let occupied = room(.luxuryApartment)
        let atlas = try TowerAtlas()
        let frame = try XCTUnwrap(atlas.frames["room.luxuryApartment.open"])
        let sourceFloorY = CGFloat(frame.rect[1]) + CGFloat(frame.rect[3]) * (1-RoomActivity.floorY(for:occupied))
        // In this artwork the bed ends near source row232 and the wood floor
        // ends at241. Feet belong inside that clear strip, above the front beam.
        XCTAssertGreaterThan(sourceFloorY,232)
        XCTAssertLessThan(sourceFloorY,241)
        var uprightCount = 0
        for elapsed in stride(from:0.0,to:60.0,by:0.1) {
            for resident in RoomActivity.occupants(in:occupied,minute:720,elapsed:elapsed)
                where resident.pose == .standing || resident.pose == .walking {
                XCTAssertEqual(resident.position.y,0.055,accuracy:0.000001)
                uprightCount += 1
            }
        }
        XCTAssertGreaterThan(uprightCount,0)
    }
    func testWalkwaysStayAheadOfFurnitureAndAboveFrontBeams() throws {
        let atlas = try TowerAtlas()
        // Source pixel bands measured between furniture fronts and the blue
        // structural beam. Their different depths require separate baselines.
        let floorBands: [(RoomKind,CGFloat,CGFloat)] = [
            (.coworking,410,414), (.ramen,410,414), (.bookshop,411,414),
            (.spa,409,414), (.fitness,422,425), (.hotel,425,429),
            (.cafe,410,414), (.arcade,408,414), (.observatory,408,416)
        ]
        for (kind,back,front) in floorBands {
            let occupied = room(kind)
            let frame = try XCTUnwrap(atlas.frames["room.\(occupied.artworkName).open"])
            let sourceY = CGFloat(frame.rect[1]) + CGFloat(frame.rect[3]) * (1-RoomActivity.floorY(for:occupied))
            XCTAssertGreaterThan(sourceY,back,"\(kind) feet must reach the clear walkway")
            XCTAssertLessThan(sourceY,front,"\(kind) feet must stay above the front beam")
        }
    }
    func testPersonalWalkingLanesDoNotCrossOtherOccupants() {
        for kind in [RoomKind.office,.coworking,.shop,.bookshop] {
            let occupied = room(kind)
            for elapsed in stride(from:0.0,to:60.0,by:0.05) {
                let people = RoomActivity.occupants(in:occupied,minute:720,elapsed:elapsed)
                for index in 1..<people.count {
                    let gap = (people[index].position.x-people[index-1].position.x)*CGFloat(kind.width*8)
                    XCTAssertGreaterThanOrEqual(gap,5.9)
                }
            }
        }
    }
    func testAllStyleStatesAndTransparentFurnitureActorsAreBundled() throws {
        let atlas = try TowerAtlas()
        for name in ["office","office2","office3","apartment","apartment2","apartment3","luxuryApartment"] {
            for state in RoomArtState.allCases {
                let key = "room.\(name).\(state.rawValue)"
                XCTAssertNotNil(atlas.frames[key])
                #if canImport(AppKit)
                XCTAssertNotNil(atlas.image(key))
                #endif
            }
            let rect = CGRect(x:100,y:100,width:name.hasPrefix("apartment") ? 32:72,height:24)
            for x in stride(from:0.0,through:1.0,by:0.1) {
                let point = atlas.roomPoint(CGPoint(x:x,y:0.1),name:name,in:rect)
                XCTAssertGreaterThanOrEqual(point.x,rect.minX)
                XCTAssertLessThanOrEqual(point.x,rect.maxX)
            }
        }
        for row in 0..<4 {
            for pose in 0..<3 {
                let key = "roomActor.\(row).\(pose)"
                XCTAssertNotNil(atlas.frames[key])
                #if canImport(AppKit)
                let image = try XCTUnwrap(atlas.image(key))
                XCTAssertTrue(image.alphaInfo == .last || image.alphaInfo == .premultipliedLast || image.alphaInfo == .first || image.alphaInfo == .premultipliedFirst)
                #endif
            }
        }
    }
}
