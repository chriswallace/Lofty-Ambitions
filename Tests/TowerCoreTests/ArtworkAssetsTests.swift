import XCTest
import Foundation
import AppKit
import TowerArt
@testable import TowerCore

final class ArtworkAssetsTests: XCTestCase {
    func testBundledAtlasDecodesEveryFrameAtItsActualPixelSize() throws {
        let atlas = try TowerAtlas()
        XCTAssertEqual(atlas.frames.count, 376)
        for (key, frame) in atlas.frames {
            let image = try XCTUnwrap(atlas.image(key), key)
            XCTAssertEqual(image.width, frame.rect[2], key)
            XCTAssertEqual(image.height, frame.rect[3], key)
        }
    }

    func testRoomWindowsRespectInteriorWallsAndStructureStaysOpaque() throws {
        let atlas = try TowerAtlas()
        let windowlessRooms: Set<String> = ["cafe", "arcade", "fitness", "ramen", "bookshop", "coworking", "spa", "grandLobby", "office2", "office3", "apartment3", "luxuryApartment"]
        for key in atlas.frames.keys.filter({ $0.hasPrefix("room.") }) {
            let image = try XCTUnwrap(atlas.image(key), key)
            let bitmap = NSBitmapImageRep(cgImage:image)
            var clear = 0, opaque = 0
            for y in stride(from:0,to:image.height,by:4) {
                for x in stride(from:0,to:image.width,by:4) {
                    let alpha = try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent
                    if alpha < 0.05 {clear += 1}
                    if alpha > 0.9 {opaque += 1}
                }
            }
            let room = key.split(separator: ".")[1]
            if windowlessRooms.contains(String(room)) {
                XCTAssertEqual(clear, 0, "Interior rooms must not expose the city through shared side walls: \(key)")
            } else {
                XCTAssertGreaterThan(clear, 20, "Missing transparent back-wall window panes: \(key)")
            }
            if ["office2", "office3", "apartment2", "apartment3", "luxuryApartment"].contains(String(room)) {
                // Transparent panes belong to the rear wall, never the shared room edges.
                let edge = max(1,image.width / 25)
                for y in stride(from:0,to:image.height,by:4) {
                    for x in [edge/2,image.width-edge/2-1] {
                        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent,0.9,"Shared side wall became transparent: \(key)")
                    }
                }
            }
            XCTAssertGreaterThan(opaque, clear, "The room structure must remain visible: \(key)")
        }
        for name in ["sunrise","day","sunset","night"] {
            for index in CityBuildings.styles.indices {
                let image = try XCTUnwrap(atlas.image("building.\(name).\(index)"))
                let daytime = try XCTUnwrap(atlas.image("building.day.\(index)"))
                XCTAssertEqual(image.width, daytime.width)
                XCTAssertEqual(image.height, daytime.height)
                let bitmap = NSBitmapImageRep(cgImage:image)
                XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x:0,y:0)).alphaComponent,0.05,"Sky outside each facade must remain transparent")
                var solid = 0
                for y in stride(from:0,to:image.height,by:8) {
                    for x in stride(from:0,to:image.width,by:8) {
                        if try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent > 0.9 { solid += 1 }
                    }
                }
                XCTAssertGreaterThan(solid,50,"Facade or lattice must remain visible: \(name).\(index)")
            }
        }
        for index in 0..<4 {
            let cloud = NSBitmapImageRep(cgImage:try XCTUnwrap(atlas.image("cloud.\(index)")))
            XCTAssertLessThan(try XCTUnwrap(cloud.colorAt(x:0,y:0)).alphaComponent,0.05)
        }
    }

    func testRoomArtworkTracksActivityAndIncidentProgress() throws {
        var room = Room(id: 1, kind: .office, floor: 1, slot: 0, occupancy: 0, rent: 1, happiness: 1)
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .vacant)
        room.occupancy = 0.2
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .open)
        room.occupancy = 1
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .open, "Busy rooms share the environment and add actors")
        XCTAssertEqual(RoomArtState.state(for: room, minute: 0), .closed)
        room.occupancy = 0
        room.incident = RoomIncident(kind: .fire, stage: .burning, severity: 0.4)
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .damaged)
        room.incident?.severity = 1
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .destroyed)
        room.incident?.stage = .awaitingRepairs
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .destroyed)
        room.incident?.stage = .repairing
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .rebuilding)
        room.incident?.stage = .resolved
        XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .vacant)
    }

    func testNewRoomOpeningHoursAndDestroyedArtwork() throws {
        let atlas = try TowerAtlas()
        for kind in [RoomKind.cafe, .arcade, .fitness, .observatory, .ramen, .bookshop, .coworking, .spa] {
            var room = Room(id: 1, kind: kind, floor: 1, slot: 0, occupancy: 0.8, rent: 1, happiness: 1)
            XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .open)
            XCTAssertEqual(RoomArtState.state(for: room, minute: 120), .closed)
            room.incident = RoomIncident(kind: .fire, stage: .awaitingRepairs, severity: 1)
            XCTAssertEqual(RoomArtState.state(for: room, minute: 720), .destroyed)
            for state in RoomArtState.allCases { XCTAssertNotNil(atlas.image("room.\(kind.rawValue).\(state.rawValue)")) }
        }
    }

    func testRuntimeAtlasContainsEveryRoomStateAndSeparateActors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = root.appendingPathComponent("Assets/Tokyo/Runtime/atlas.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "The game needs a runtime atlas, not just generated source sheets")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return }
        let atlas = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        let frames = atlas["frames"] as! [String: [String: Any]]
        for room in RoomKind.allCases.map(\.rawValue) {
            for state in ["vacant", "open", "closed", "damaged", "destroyed", "rebuilding"] {
                XCTAssertNotNil(frames["room.\(room).\(state)"])
            }
        }
        for key in ["civilian.0.0", "civilian.3.7", "staff.3.3", "responder.3.3", "effect.5.3", "elevator.2.3", "car.1.3", "structure.2.3", "vehicle.fireEngine"] {
            XCTAssertNotNil(frames[key], key)
        }
        for (key, frame) in frames {
            let rect = frame["rect"] as! [Int]
            XCTAssertEqual(rect.count, 4)
            XCTAssertGreaterThan(rect[2], 0, key)
            XCTAssertGreaterThan(rect[3], 0, key)
            let sheet = frame["sheet"] as! String
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.deletingLastPathComponent().appendingPathComponent("Sheets/" + sheet).path), sheet)
        }
    }
}
