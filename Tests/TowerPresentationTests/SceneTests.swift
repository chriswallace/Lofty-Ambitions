import XCTest
import TowerCore
import TowerArt
@testable import TowerPresentation

final class SceneTests: XCTestCase {
    func testRenderGeometryRefreshesAfterResizePanZoomAndTowerChanges() throws {
        var game=TowerState.demoTower()
        let reused=TowerScene();reused.reducedMotion=true
        _ = reused.render(game:game,width:1200,height:800,elapsed:0)
        // Change both floor extents and inserted shaft width after a render.
        game.floorSpans=[0:FloorSpan(-10,80)]
        var lift=game.elevators[0];lift.id=2;game.elevators.append(lift)
        for (width,height,scale,pan) in [(3840.0,2054.0,0.25,37.0),(1200.0,800.0,2.0,-19.0)] {
            let fresh=TowerScene();fresh.reducedMotion=true
            for scene in [reused,fresh] {scene.scale=scale;scene.panX=pan;scene.panY=pan}
            XCTAssertEqual(reused.render(game:game,width:width,height:height,elapsed:0),fresh.render(game:game,width:width,height:height,elapsed:0))
            // Input geometry must also see camera changes between render calls.
            reused.panX+=11;fresh.panX+=11
            let room=try XCTUnwrap(game.rooms.first{$0.kind == .office})
            XCTAssertEqual(reused.roomRect(room,game:game,width:width,height:height),fresh.roomRect(room,game:game,width:width,height:height))
        }
    }

    func testRoomSignalsExposeTheSameVisibleFireTarget() throws {
        var game=TowerState.demoTower()
        let room=try XCTUnwrap(game.rooms.first{$0.kind == .office})
        try game.triggerIncident(.fire,roomID:room.id)
        let scene=TowerScene();scene.showsSignals=true
        scene.fit(game:game,width:1200,height:800)
        _ = scene.render(game:game,width:1200,height:800,elapsed:0)
        let signal=try XCTUnwrap(scene.roomSignals.first{$0.roomID == room.id})
        XCTAssertEqual(signal.mood,.alarmed)
        XCTAssertEqual(signal.text,"Fire! Call the FD!")
        let r=scene.roomRect(room,game:game,width:1200,height:800)
        XCTAssertGreaterThanOrEqual(signal.rect.x,r.x)
        XCTAssertLessThanOrEqual(signal.rect.x+signal.rect.width,r.x+r.width)
    }

    func testLegacyBanksHaveDistinctPointerTargets() throws {
        var game=TowerState.demoTower();game.cash=1_000_000
        // Original nil-column banks occupy adjacent inserted core slots.
        var second=game.elevators[0];second.id=2;game.elevators.append(second)
        let scene=TowerScene();scene.configure(game:game,width:1200,height:800)
        let a=scene.elevatorFootprint(0,game),b=scene.elevatorFootprint(1,game)
        let origin=scene.worldOrigin
        let y=800-origin.y-Double(2)*24*scene.scale
        XCTAssertEqual(scene.elevatorID(x:origin.x+a.midX*scene.scale,y:y,game:game,width:1200,height:800),1)
        XCTAssertEqual(scene.elevatorID(x:origin.x+b.midX*scene.scale,y:y,game:game,width:1200,height:800),2)
    }

    func testCameraHitsRoomAndBasementAfterFitAndPan() throws {
        let game = TowerState.demoTower()
        let scene = TowerScene()
        scene.fit(game: game, width: 1200, height: 800)
        scene.panX += 37; scene.panY -= 19
        for room in game.rooms where room.kind != .lobby {
            let r = scene.roomRect(room, game: game, width: 1200, height: 800)
            let cell = scene.hit(x: r.x + 1, y: r.y + r.height / 2, game: game, width: 1200, height: 800)
            XCTAssertEqual(cell?.floor, room.floor)
            XCTAssertEqual(cell?.slot, room.slot)
        }
    }

    func testRoomImagesUseOriginalThreeSlicesAndCorrectFrameRelativeCoordinates() throws {
        let game = TowerState.demoTower(), atlas = try TowerAtlas()
        let scene = TowerScene()
        let commands = scene.render(game: game, width: 1200, height: 800, elapsed: 0)
        let roomImages = commands.compactMap { command -> (String, SceneRect)? in
            if case let .image(key, source?, _, _, _) = command, key.hasPrefix("room.") { return (key, source) }
            return nil
        }
        XCTAssertFalse(roomImages.isEmpty)
        for (key, source) in roomImages {
            let frame = try XCTUnwrap(atlas.frames[key])
            XCTAssertGreaterThan(source.width, 0)
            XCTAssertGreaterThanOrEqual(source.x, 0)
            XCTAssertLessThanOrEqual(source.x + source.width, Double(frame.rect[2]) + 1)
            XCTAssertEqual(source.height, Double(frame.rect[3]))
        }
    }

    func testDispatchedAndExtinguishingFireUseEngineRespondersAndWaterArtwork() throws {
        var game = TowerState.demoTower()
        let id = try XCTUnwrap(game.rooms.first { $0.kind == .office }?.id)
        try game.triggerIncident(.fire, roomID: id)
        try game.respond(to: id, action: .dispatchFireDepartment)
        game.advance(minutes: 30)
        let scene = TowerScene(); scene.fit(game: game, width: 1600, height: 1000)
        let commands = scene.render(game: game, width: 1600, height: 1000, elapsed: 2)
        let keys = commands.compactMap { c -> String? in if case let .image(key, _, _, _, _) = c { return key }; return nil }
        XCTAssertTrue(keys.contains("vehicle.fireEngine"))
        XCTAssertTrue(keys.contains { $0.hasPrefix("responder.") })
        XCTAssertTrue(keys.contains { $0.hasPrefix("effect.3.") })
        let atlas = try TowerAtlas()
        XCTAssertTrue(keys.allSatisfy { atlas.frames[$0] != nil || $0.hasPrefix("cloud.") })
    }

    func testReducedMotionProducesIdenticalActorKeysAcrossElapsedTimes() {
        let scene = TowerScene(); scene.reducedMotion = true
        let game = TowerState.demoTower()
        func keys(_ time: Double) -> [String] {
            scene.render(game: game, width: 1200, height: 800, elapsed: time).compactMap {
                if case let .image(key, _, _, _, _) = $0 { return key }; return nil
            }
        }
        XCTAssertEqual(keys(0), keys(9.8))
    }
    func testGrandLobbyAndBasementShareActualArtworkAndHitGeometry() throws {
        var game=TowerState.demoTower();game.cash=500_000;game.earnedStars=3
        try game.upgradeLobby();try game.excavateBasement()
        let roomID=try game.build(.cafe,floor:-1,slot:0)
        let room=try XCTUnwrap(game.rooms.first{$0.id==roomID})
        let scene=TowerScene();scene.fit(game:game,width:1400,height:1000)
        let rect=scene.roomRect(room,game:game,width:1400,height:1000)
        let cell=scene.hit(x:rect.x+1,y:rect.y+rect.height/2,game:game,width:1400,height:1000)
        XCTAssertEqual(cell?.floor,-1);XCTAssertEqual(cell?.slot,0)
        let keys=scene.render(game:game,width:1400,height:1000,elapsed:0).compactMap {c->String? in
            if case let .image(key,_,_,_,_)=c{return key};return nil
        }
        XCTAssertTrue(keys.contains("lobby.grandWall"))
        XCTAssertTrue(keys.contains{$0.hasPrefix("room.cafe.")})
        XCTAssertTrue(keys.contains{$0.hasPrefix("panoramicCar.")})
    }

    func testPortableActorAnchorsKeepBodyAxisAndFloorInBothDirections() throws {
        let atlas=try TowerAtlas(),feet=CGPoint(x:80,y:26.04)
        for character in 0..<4 {for pose in 0..<4 {
            let key="civilian.\(character).\(pose)",frame=try XCTUnwrap(atlas.frames[key])
            let anchor=try XCTUnwrap(frame.footAnchor)
            let factor=10/Double(frame.referenceHeight)
            for flipped in [false,true] {
                let rect=try XCTUnwrap(atlas.actorRect(key,feet:feet,height:10,flipped:flipped))
                let axis=(flipped ? Double(frame.rect[2])-anchor[0]:anchor[0])*factor
                XCTAssertEqual(rect.minX+axis,feet.x,accuracy:0.0001)
                XCTAssertEqual(rect.minY+anchor[1]*factor,feet.y,accuracy:0.0001)
            }
        }}
    }

    func testOffscreenClipsHaveFiniteCoordinates() {
        let scene=TowerScene();scene.panX=100_000
        let commands=scene.render(game:.demoTower(),width:800,height:600,elapsed:0)
        for command in commands {
            if case let .clip(rect?)=command {
                XCTAssertTrue([rect.x,rect.y,rect.width,rect.height].allSatisfy(\.isFinite))
            }
        }
    }

}
