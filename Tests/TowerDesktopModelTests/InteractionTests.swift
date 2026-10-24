import XCTest
import Foundation
import TowerCore
import TowerSession
@testable import TowerDesktopModel
final class InteractionTests:XCTestCase {
    func testBuildDragUsesSharedRulesAndFailureIsAtomic() throws {
        let s=TowerSession();s.game.cash=200_000
        try s.execute(.addFloor)
        let ui=DesktopInteraction(session:s);ui.tool = .room(.office)
        try ui.drag(from:(1,0),to:(1,18))
        XCTAssertEqual(s.game.rooms.filter{$0.kind == .office}.count,3)
        let before=try TowerSnapshot.canonicalData(s.game)
        XCTAssertThrowsError(try ui.drag(from:(1,0),to:(1,18)))
        XCTAssertEqual(try TowerSnapshot.canonicalData(s.game),before)
    }
    func testInspectionAndDeletionRequireConfirmation() throws {
        let s=TowerSession(game:.demoTower());let ui=DesktopInteraction(session:s)
        try ui.drag(from:(2,0),to:(2,0))
        let selected=try XCTUnwrap(ui.selectedRoom)
        XCTAssertEqual(selected,s.game.room(at:2,slot:0)?.id)
        let count=s.game.rooms.count
        ui.tool = .delete
        try ui.drag(from:(2,0),to:(2,0))
        XCTAssertNotNil(s.pendingDemolition)
        XCTAssertEqual(s.game.rooms.count,count)
        try s.resolveDemolition(confirmed:false)
        XCTAssertEqual(s.game.rooms.count,count)
    }
    func testLegacyElevatorCanBeSelectedAndSingleClickBuildStartsAtGround() throws {
        let legacy = TowerSession(game:.demoTower())
        let ui=DesktopInteraction(session:legacy)
        try ui.drag(from:(2,legacy.game.core),to:(2,legacy.game.core),hitElevatorID:legacy.game.elevators.first?.id)
        XCTAssertEqual(ui.selectedElevator,legacy.game.elevators.first?.id)
        let session=TowerSession();session.game.cash=500_000
        for _ in 0..<3 {try session.execute(.addFloor)}
        let editor=DesktopInteraction(session:session);editor.tool = .elevator(.standard)
        try editor.drag(from:(3,30),to:(3,30))
        XCTAssertEqual(session.game.elevators.first?.bottom,0)
        XCTAssertEqual(session.game.elevators.first?.topFloor,3)
    }

    func testRoomBesideCentralBanksDoesNotSelectOrDeleteTheBank() throws {
        let session=TowerSession(game:.demoTower())
        let editor=DesktopInteraction(session:session)
        let room=try XCTUnwrap(session.game.room(at:1,slot:session.game.core))
        try editor.drag(from:(1,session.game.core),to:(1,session.game.core),hitElevatorID:nil)
        XCTAssertEqual(editor.selectedRoom,room.id)
        XCTAssertNil(editor.selectedElevator)
        editor.tool = .delete
        try editor.drag(from:(1,session.game.core),to:(1,session.game.core),hitElevatorID:nil)
        XCTAssertEqual(session.pendingDemolition,.room(room.id))
    }
    func testGroundClickCreatesServiceToFirstBuiltFloor() throws {
        let session=TowerSession();try session.execute(.addFloor)
        let editor=DesktopInteraction(session:session);editor.tool = .elevator(.standard)
        try editor.drag(from:(0,30),to:(0,30))
        XCTAssertEqual(session.game.elevators.first?.bottom,0)
        XCTAssertEqual(session.game.elevators.first?.topFloor,1)
    }

    func testCleanSessionQuitUpdatesAutosaveToCurrentlyOpenedTower() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=TowerSaveStore(recoveryDirectory:directory.appendingPathComponent("Recovery"))
        let url=directory.appendingPathComponent("Auto.loftyambitions")
        let incoming=directory.appendingPathComponent("Other.loftyambitions")
        try store.write(.newGame(scenerySeed:1),to:url)
        try store.write(.newGame(scenerySeed:2),to:incoming)
        let session=TowerSession();_ = try session.open(incoming,store:store)
        XCTAssertFalse(session.hasUnsavedChanges)
        try DesktopPersistence.finishSession(session,autosaveURL:url,store:store,autosaveBlocked:false)
        XCTAssertEqual(try store.read(url).citySeed,2)
    }

    func testNewModalAlwaysDefaultsToCancel() {
        var modal=DesktopModalFocus()
        modal.selectContinue()
        modal.begin()
        XCTAssertFalse(modal.acceptsReturn)
    }

    func testFloorAndPositionedElevatorToolsUseSamePlacementValidation() throws {
        let s=TowerSession();s.game.cash=500_000
        let ui=DesktopInteraction(session:s);ui.tool = .floor
        try ui.drag(from:(1,0),to:(1,63))
        ui.tool = .elevator(.standard)
        try ui.drag(from:(0,30),to:(1,30))
        XCTAssertEqual(s.game.elevators.first?.column,30)
        XCTAssertEqual(s.game.elevators.first?.topFloor,1)
        XCTAssertThrowsError(try ui.drag(from:(0,30),to:(1,30)))
        XCTAssertEqual(s.game.elevators.count,1)
    }
}
