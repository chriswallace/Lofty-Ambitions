// Compile with the TowerApp view sources (excluding main.swift) and the built
// TowerCore/TowerArt object files. See check-ui.sh. These checks exercise the
// real controller and native views without event injection or touching saves.
import AppKit
import TowerCore
import TowerArt

@main struct UIRegressionChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let controller = GameController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 650), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1080, height: 650))
        controller.view.setFrameSize(NSSize(width: 1080, height: 650))
        controller.timer?.invalidate(); controller.speed = 0
        func layout() { controller.view.layoutSubtreeIfNeeded() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func detailLabels() -> [NSTextField] { descendants(controller.roomBrowser.detailPanel).compactMap { $0 as? NSTextField } }
        func clickRoom(_ kind: RoomKind) {
            let row = controller.roomBrowser.roomList.arrangedSubviews.compactMap { $0 as? RoomCatalogRow }.first { $0.room.kind == kind }!
            NSApp.sendAction(row.action!, to: row.target, from: row)
        }
        func snapshot(_ name: String) throws {
            layout()
            let view = controller.view
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
        controller.updateUI(); layout()
        let titleMenu = NSMenu()
        let applicationItem = NSMenuItem(); applicationItem.submenu = NSMenu()
        titleMenu.addItem(applicationItem)
        titleMenu.addItem(NSMenuItem(title: "Game", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = titleMenu
        let titleRooms = controller.game.rooms
        let titleMinute = controller.game.minute
        let titleCash = controller.game.cash
        controller.speed = 4
        precondition(controller.showTitleScreen(), "Bundled splash artwork must load")
        layout()
        precondition(controller.titleScreen?.frame == controller.view.bounds)
        precondition(controller.titleScreenHiddenViews.allSatisfy { $0.0.isHidden })
        precondition(NSApp.mainMenu?.items.count == 1, "Construction menus must be hidden on the title screen")
        for _ in 0..<90 { controller.frame() }
        precondition(controller.speed == 0 && controller.game.minute == titleMinute && controller.game.cash == titleCash && controller.game.rooms == titleRooms, "Title screen must freeze the tower")
        try snapshot("lofty-title-screen")
        let enter = controller.titleScreen!.enterButton
        precondition(enter.keyEquivalent == "\r", "Return must enter the tower")
        NSApp.sendAction(enter.action!, to: enter.target, from: enter)
        precondition(controller.titleScreen == nil && controller.speed == 4)
        precondition(NSApp.mainMenu === titleMenu && window.firstResponder === controller.gameView)
        precondition(controller.chromeViews.allSatisfy { !$0.isHidden })
        controller.speed = 0
        precondition(controller.showTitleScreen())
        controller.enterTowerFromTitleScreen()
        precondition(controller.speed == 0, "Entering must preserve an already paused tower")
        controller.updateUI(); layout()
        print("Title screen checks passed: bundled artwork, paused simulation, hidden controls, entry action, Return shortcut, restored menus and play state.")
        precondition(controller.wideningMenuItems.values.flatMap { $0 }.allSatisfy { $0.title.contains("$1,200 (1 floor)") })
        let catalogScroll = descendants(controller.roomBrowser).compactMap { $0 as? NSScrollView }.first!
        precondition(catalogScroll.contentView.bounds.height >= 150, "Catalog must show several rows at the minimum window size")
        for (name, button) in controller.toolButtons {
            let rect = button.convert(button.bounds, to: controller.view)
            precondition(rect.minX >= 0 && rect.maxX <= 1080, "Tool clipped: \(name) \(rect)")
        }
        precondition(controller.roomBrowser.roomList.arrangedSubviews.count == RoomCatalog.search(query: "").count)
        precondition(controller.roomBrowser.selection == .office)
        let original = controller.game.rooms
        controller.roomBrowser.select(.hotel)
        layout()
        let hotelRow = controller.roomBrowser.roomList.arrangedSubviews.compactMap { $0 as? RoomCatalogRow }.first { $0.room.kind == .hotel }!
        precondition(hotelRow.visibleRect.height >= hotelRow.bounds.height - 1, "Selected room must be fully visible")
        precondition(controller.selectedKind == nil && controller.game.rooms == original)
        precondition(controller.selectedKind == nil, "Locked room must remain readable but unbuildable")
        precondition(detailLabels().contains { $0.stringValue.contains("Unlocks at level 2") })
        precondition(!descendants(controller.roomBrowser.detailPanel).contains { $0 is NSButton }, "No extra Build button")
        try snapshot("catalog-locked-room")
        controller.roomBrowser.categoryPicker.selectItem(at: RoomCatalog.categories.firstIndex(of: .services)! + 1)
        NSApp.sendAction(controller.roomBrowser.categoryPicker.action!, to: controller.roomBrowser.categoryPicker.target, from: controller.roomBrowser.categoryPicker)
        precondition(controller.roomBrowser.roomList.arrangedSubviews.count == 2, "Category filter must narrow the list")
        controller.roomBrowser.searchField.stringValue = "cleaning"
        controller.roomBrowser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(controller.roomBrowser.roomList.arrangedSubviews.count == 1)
        precondition(controller.roomBrowser.selection == .housekeeping)
        controller.roomBrowser.searchField.stringValue = "not a room"
        controller.roomBrowser.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(controller.roomBrowser.selection == nil && controller.selectedKind == nil)
        try snapshot("catalog-empty-search")
        controller.roomBrowser.select(.office)
        precondition(controller.roomBrowser.searchField.stringValue.isEmpty)
        precondition(controller.selectedKind == .office && controller.game.rooms == original)
        clickRoom(.office)
        precondition(controller.selectedKind == .office, "Clicking the selected room must keep it armed")
        controller.menuInspect()
        precondition(controller.selectedKind == nil)
        clickRoom(.office)
        precondition(controller.selectedKind == .office, "Clicking the room must arm construction directly")
        controller.perform { try $0.addFloor() }
        controller.dragged(fromFloor: 1, fromSlot: 0, toFloor: 1, toSlot: 0)
        precondition(controller.game.rooms.count == 2 && controller.game.rooms.last?.kind == .office)
        controller.chooseDemolition()
        precondition(controller.demolition && controller.selectedKind == nil && controller.toolButtons["delete"]?.state == .on)
        controller.chooseFloor()
        precondition(controller.floorMode && !controller.demolition && controller.elevatorPicker.item(at: 0)?.title == "Floor tool")
        controller.chooseElevator(.wide)
        precondition(controller.elevatorTool == .wide && !controller.floorMode && controller.selectedKind == nil)
        controller.menuInspect()
        precondition(controller.elevatorTool == nil && controller.toolButtons["inspect"]?.state == .on)
        controller.clicked(floor: 1, slot: 0)
        precondition(controller.selectedRoom == controller.game.rooms.last?.id)
        layout()
        precondition(controller.inspectorWidth.constant > 0)
        let menu = NSMenu(); controller.installConstructionMenus(in: menu)
        precondition(controller.wideningMenuItems.values.flatMap { $0 }.count == 4)
        precondition(controller.wideningMenuItems.values.flatMap { $0 }.allSatisfy { $0.title.contains("$2,400 (2 floors)") })
        let rooms = menu.items.first { $0.title == "Rooms" }!.submenu!
        let entries = rooms.items.flatMap { $0.submenu?.items ?? [] }
        precondition(Set(entries.compactMap { $0.representedObject as? String }) == Set(RoomCatalog.search(query: "").map { $0.kind.rawValue }))
        controller.browseRoomFromMenu(entries.first { $0.representedObject as? String == "hotel" }!)
        precondition(controller.roomBrowser.selection == .hotel && controller.selectedKind == nil)
        controller.browseRoomFromMenu(entries.first { $0.representedObject as? String == "office" }!)
        precondition(controller.selectedKind == .office, "Native Rooms menu must arm placement")
        controller.game.cash = 0; controller.updateUI()
        controller.roomBrowser.select(.office)
        precondition(controller.selectedKind == nil)
        precondition(detailLabels().contains { $0.stringValue.contains("Need $12,000 more") })
        controller.game = .demoTower(); controller.game.earnedStars = 2
        controller.choose(.office)
        precondition(controller.wideningMenuItems.values.flatMap { $0 }.allSatisfy { $0.title.contains("$6,000 (5 floors)") })
        let cameraScale = controller.gameView.scale
        controller.setFocusMode(true); layout()
        precondition(controller.focusMode && controller.selectedKind == nil && !controller.focusBar.isHidden)
        precondition(controller.chromeViews.allSatisfy(\.isHidden))
        precondition(controller.gameView.frame == controller.view.bounds, "Focus canvas must fill the window")
        precondition(controller.gameView.scale == cameraScale, "Focus must preserve zoom")
        try snapshot("tower-focus-mode")
        controller.showRoomIssues(); layout()
        precondition(!controller.focusMode && controller.showingIssues && controller.focusBar.isHidden)
        precondition(controller.chromeViews.allSatisfy { !$0.isHidden })
        controller.showTowerInformation(); layout()
        precondition(controller.showingInfo)
        try snapshot("tower-progression")
        for kind in RoomKind.allCases where kind != .lobby {
            controller.roomBrowser.select(kind); layout()
            precondition(!descendants(controller.roomBrowser.detailPanel).contains { $0 is NSButton })
            for label in detailLabels() where !label.isHidden {
                let rect = label.convert(label.bounds, to: controller.roomBrowser.detailPanel)
                precondition(controller.roomBrowser.detailPanel.bounds.contains(rect), "Details must remain visible for \(kind)")
            }
        }
        controller.roomBrowser.select(.office); controller.updateUI(); layout(); controller.gameView.fitTower()
        try snapshot("catalog-normal-window")
        // Lobby upgrade must be discoverable both on the lobby and in Tower info.
        controller.game = .demoTower(); controller.game.earnedStars = 2
        controller.showTowerInformation(); layout()
        func lobbyUpgradeButton() -> NSButton? {
            descendants(controller.detailStack).compactMap { $0 as? NSButton }.first { $0.title == "Upgrade to Grand Lobby" }
        }
        precondition(lobbyUpgradeButton()?.isEnabled == false)
        controller.game.earnedStars = 3; controller.game.cash = 100000
        controller.selectedRoom = controller.game.rooms.first { $0.kind == .lobby }!.id
        controller.showingInfo = false; controller.updateUI(rebuildInspector: true); layout()
        let upgrade = lobbyUpgradeButton()!
        precondition(upgrade.isEnabled)
        try snapshot("lobby-upgrade-available")
        let upgradeScale = controller.gameView.scale
        NSApp.sendAction(upgrade.action!, to: upgrade.target, from: upgrade)
        precondition(controller.gameView.scale == upgradeScale, "Lobby upgrade must preserve the player's zoom")
        precondition(controller.game.effectiveLobbyStyle == .grand && controller.game.cash == 60000)
        precondition(controller.game.lobbyHeight == 4 && controller.game.topFloor == 7)
        let lobbyRoom = controller.game.rooms.first { $0.kind == .lobby }!
        precondition(controller.gameView.roomRect(lobbyRoom).height == 96)
        precondition(controller.game.room(at: 3, slot: 0)?.id == lobbyRoom.id)
        precondition(controller.game.elevators[0].stops == [0,4,5,6,7])
        precondition(lobbyUpgradeButton() == nil)
        try snapshot("lobby-upgraded")

        // Exercise a legacy core and a placed wide bank together through the atrium.
        controller.game.cash = 500000
        try controller.game.addElevator(.wide, at: 54, from: 0, to: 7)
        controller.game.elevators[0].position = 1.5
        controller.game.elevators[1].position = 0
        controller.game.elevators[1].doorTime = 5
        let liftDemoRoom = controller.game.rooms.first { $0.kind == .office }!
        try controller.game.requestTrip(roomID: liftDemoRoom.id, from: 0, to: liftDemoRoom.floor)
        controller.game.travelers![0].phase = .riding
        controller.game.travelers![0].elevatorID = controller.game.elevators[0].id
        controller.game.elevators[0].passengers = 1
        try controller.game.requestTrip(roomID: liftDemoRoom.id, from: 0, to: liftDemoRoom.floor)
        let portalColumn = controller.game.boardingColumn(for: controller.game.elevators[1])
        let portalLiftID = controller.game.elevators[1].id
        controller.game.travelers![1].phase = .waiting
        controller.game.travelers![1].x = portalColumn
        controller.game.travelers![1].boardingElevatorID = portalLiftID
        controller.updateUI(rebuildInspector: true); layout()
        let lobbyBounds = controller.gameView.roomRect(controller.game.rooms.first { $0.kind == .lobby }!)
        precondition(lobbyBounds.width == controller.gameView.spanRect(0).width, "Legacy shaft gaps belong to the lobby bounds")
        let composition = controller.gameView.grandLobbyComposition(controller.game, in: lobbyBounds)
        precondition(composition.feature != nil)
        for i in controller.game.elevators.indices {
            let shaft = controller.gameView.elevatorFootprint(i,controller.game)
            precondition(!composition.feature!.intersects(shaft), "Lobby furniture must clear every shaft")
            let car = controller.gameView.elevatorCarRect(i,controller.game)
            precondition(shaft.contains(car) && car.height == 21)
            let landing = controller.gameView.elevatorLandingRect(i,floor: 0,controller.game)
            precondition(landing.minX > car.maxX && landing.height == 20)
            precondition(!controller.game.elevators[i].stops.contains(1) && !controller.game.elevators[i].stops.contains(3))
            let point = CGPoint(x:controller.gameView.origin.x+shaft.midX*controller.gameView.scale,
                                y:controller.gameView.origin.y+48*controller.gameView.scale)
            precondition(controller.gameView.liftHit(point) == i, "Glass lifts remain selectable throughout the atrium")
        }
        let placed = controller.game.elevators[1]
        let portal = controller.gameView.elevatorLandingRect(1,floor:0,controller.game)
        precondition(abs(controller.gameView.personX(controller.game.boardingColumn(for:placed))-portal.midX) < 0.01)
        // Visual check: a pedestrian crosses the shaft while the car is elsewhere.
        let crossingID = controller.game.rooms.first { $0.kind == .office }!.id
        controller.game.travelers!.append(Traveler(id:9999,roomID:crossingID,floor:5,destination:5,x:56,destinationX:60,phase:.walkingToRoom))
        try snapshot("coordinated-lobby-lifts")
        let coordinatedGame = controller.game
        controller.game = .newGame(); controller.game.cash = 500000
        try controller.game.addFloor()
        try controller.game.addElevator(.standard, at:10, from:0, to:1)
        try controller.game.addElevator(.wide, at:13, from:0, to:1)
        var queued = Traveler(id:1,roomID:1,floor:0,destination:1,x:12.5,destinationX:20,phase:.waiting,route:[1])
        queued.boardingElevatorID = controller.game.elevators[0].id
        let adjacentShaft = controller.gameView.elevatorFootprint(1,controller.game)
        var visibleAdjacentQueue = 0
        for ordinal in 0..<12 {
            guard let spot = controller.gameView.waitingPosition(for:queued,ordinal:ordinal,controller.game) else { continue }
            visibleAdjacentQueue += 1
            precondition(spot.y == 2.5, "Every queued traveler stands on the corridor floor")
            precondition(spot.x+2 <= adjacentShaft.minX, "Queues must not spill into the neighboring shaft")
        }
        precondition(visibleAdjacentQueue == 1, "A narrow landing samples its queue instead of stacking people")
        controller.game.travelers = (1...30).map { id in
            var person = queued
            person.id = id
            person.x = controller.game.boardingColumn(for:controller.game.elevators[1])
            person.boardingElevatorID = controller.game.elevators[1].id
            return person
        }
        let sampledQueue = controller.gameView.travelerMotionTargets(controller.game)
        precondition(controller.game.queueCount == 30 && sampledQueue.count == 8, "Visual queue sampling preserves every simulation passenger")
        precondition(sampledQueue.map(\.id) == Array(1...8), "Queue representatives retain their stable arrival order")
        for (index, target) in sampledQueue.enumerated() {
            precondition(target.position.y == 2.5, "A busy queue cannot float above the corridor")
            if index > 0 {
                let previous = sampledQueue[index-1]
                let previousBody = controller.gameView.atlas.actorRect("civilian.\(previous.id%4).0",feet:previous.position,height:10)!
                let body = controller.gameView.atlas.actorRect("civilian.\(target.id%4).0",feet:target.position,height:10)!
                precondition(previousBody.maxX <= body.minX, "Waiting sprites must not overlap")
            }
        }
        controller.resetSelection(); controller.updateUI(rebuildInspector:true)
        try snapshot("lofty-grounded-elevator-queue")
        controller.game = coordinatedGame
        print("Coordinated lift checks passed: clear furnishings, legacy gaps, car and door scale, landing alignment, moving atrium car, open ground portal, and hit targets.")

        // Render three intermediate poses for each 0.1-second simulation update.
        // This exercises the real controller clock rather than only the pure interpolator.
        for speed in [1, 4, 12] {
            controller.game = .demoTower(); controller.game.minute = 1001
            controller.resetSelection(); controller.speed = speed
            let room = controller.game.rooms.first { $0.kind == .office }!
            let id = 9901
            controller.game.travelers = [Traveler(id:id,roomID:room.id,floor:room.floor,destination:room.floor,
                                                   x:60,destinationX:5,phase:.walkingToRoom)]
            controller.gameView.synchronizeTravelerMotion(controller.game)
            let start = controller.gameView.travelerMotion.pose(for:id)!.position
            precondition(start.y == CGFloat(room.floor)*24+2.5, "Travelers stand on the foreground corridor surface")
            func renderFrame() {
                controller.lastFrameTime = ProcessInfo.processInfo.systemUptime - 1.0/30
                controller.frame()
            }
            controller.frameCount = 2
            renderFrame()
            let destination = controller.gameView.personX(controller.game.activeTravelers.first { $0.id == id }!.x)
            precondition(controller.gameView.travelerMotion.pose(for:id)!.position == start, "A simulation tick must not teleport the displayed actor")
            renderFrame()
            let first = controller.gameView.travelerMotion.pose(for:id)!
            renderFrame()
            let second = controller.gameView.travelerMotion.pose(for:id)!
            precondition(destination < second.position.x && second.position.x < first.position.x && first.position.x < start.x)
            precondition(abs(first.position.x-(start.x+(destination-start.x)/3)) < 0.2)
            precondition(first.facingLeft && second.facingLeft && second.distance > first.distance, "Gait and heading follow displayed motion")
            controller.speed = 0
            renderFrame()
            precondition(controller.gameView.travelerMotion.pose(for:id) == second, "Pausing freezes both the current position and its footstep")
            controller.game.travelers![0].phase = .riding
            renderFrame()
            precondition(controller.gameView.travelerMotion.pose(for:id) == nil, "Boarded travelers cannot leave a corridor ghost")
            controller.resetSelection()
            precondition(controller.gameView.travelerMotion.pose(for:id) == nil, "Loading another tower clears presentation history")
        }
        controller.game = coordinatedGame; controller.resetSelection(); controller.speed = 0
        print("Traveler motion checks passed: smooth 30 Hz positions at all speeds, grounded feet, physical gait, facing, pause, boarding, and reset.")

        controller.game = .demoTower(); controller.speed = 4
        let deleteRoom = controller.game.rooms.first { $0.kind == .office }!
        let deleteCash = controller.game.cash, deleteMinute = controller.game.minute
        let deleteRooms = controller.game.rooms
        let roomAlert = try controller.makeDemolitionAlert(for: .room(deleteRoom.id))
        precondition(roomAlert.messageText.contains("floor \(deleteRoom.floor)"))
        precondition(roomAlert.informativeText.contains("$6,000") && roomAlert.informativeText.contains("cannot be undone"))
        precondition(roomAlert.buttons[0].title == "Keep it" && roomAlert.buttons[0].keyEquivalent == "\r")
        precondition(roomAlert.buttons[1].hasDestructiveAction && roomAlert.buttons[1].keyEquivalent.isEmpty)
        let liftID = controller.game.elevators[0].id
        let shaftAlert = try controller.makeDemolitionAlert(for: .elevator(liftID))
        precondition(shaftAlert.buttons[1].title == "Delete Entire Shaft")
        precondition(shaftAlert.informativeText.contains("lose elevator access"))
        roomAlert.layout()
        if let content = roomAlert.window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/room-delete-confirmation.png"))
        }
        func finishDeletion(_ response: NSApplication.ModalResponse) {
            window.endSheet(controller.pendingDemolitionAlert!.window, returnCode: response)
            let deadline = Date().addingTimeInterval(3)
            while controller.pendingDemolitionAlert != nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            precondition(controller.pendingDemolitionAlert == nil, "Confirmation completion must run")
        }
        controller.requestDemolition(.room(deleteRoom.id))
        precondition(controller.pendingDemolitionAlert != nil && controller.speed == 0)
        for _ in 0..<90 { controller.frame() }
        precondition(controller.game.minute == deleteMinute && controller.game.rooms == deleteRooms)
        finishDeletion(.alertFirstButtonReturn)
        precondition(controller.game.rooms == deleteRooms && controller.game.cash == deleteCash && controller.speed == 4)
        controller.requestDemolition(.room(deleteRoom.id))
        finishDeletion(.alertSecondButtonReturn)
        precondition(!controller.game.rooms.contains { $0.id == deleteRoom.id })
        precondition(controller.game.cash == deleteCash + deleteRoom.kind.cost / 2 && controller.speed == 4)
        let shaftCash = controller.game.cash, shaftRefund = controller.game.elevators[0].kind.cost / 2
        controller.requestDemolition(.elevator(liftID))
        finishDeletion(.alertSecondButtonReturn)
        precondition(controller.game.elevators.isEmpty && controller.game.cash == shaftCash + shaftRefund)
        controller.speed = 0
        print("Expansion UI checks passed: lobby unlock and purchase, safe default deletion, frozen simulation, cancellation, confirmed room and shaft refunds, and restored speed.")
        print("UI checks passed: toolbar bounds, catalog search, locked rooms, empty results, direct room selection, cancellation, placement, tool exclusivity, inspector, menu coverage, insufficient funds, progression, all room details, focus mode, and widening prices in both menus.")
        try controller.setupInteriorDemo()
        layout()
        let styleRoom = controller.selectedRoom!
        let styleCash = controller.game.cash
        let stylePicker = descendants(controller.detailStack).compactMap { $0 as? NSSegmentedControl }.first!
        precondition(stylePicker.segmentCount == 3 && stylePicker.selectedSegment == 1)
        stylePicker.selectedSegment = 2
        NSApp.sendAction(stylePicker.action!,to:stylePicker.target,from:stylePicker)
        precondition(controller.game.rooms.first { $0.id == styleRoom }?.style == .three)
        precondition(controller.game.cash == styleCash && controller.didModify)
        let homeID = controller.game.rooms.first { $0.kind == .apartment }!.id
        controller.revealRoom(homeID); layout()
        precondition(descendants(controller.detailStack).contains { $0 is NSSegmentedControl })
        let luxuryID = controller.game.rooms.first { $0.kind == .luxuryApartment }!.id
        controller.revealRoom(luxuryID); layout()
        precondition(!descendants(controller.detailStack).contains { $0 is NSSegmentedControl })
        precondition(descendants(controller.detailStack).compactMap { $0 as? NSPopUpButton }.count == 2, "Luxury homes retain leasing controls")
        controller.game.earnedStars = 3; controller.choose(nil)
        controller.roomBrowser.select(.luxuryApartment); layout()
        precondition(controller.selectedKind == nil)
        precondition(detailLabels().contains { $0.stringValue.contains("Unlocks at level 4") })
        controller.game.earnedStars = 4; controller.updateUI()
        clickRoom(.luxuryApartment)
        precondition(controller.selectedKind == .luxuryApartment)
        try controller.setupInteriorDemo()
        let interiorTravelers = controller.game.travelers
        let luxuryInterior = controller.game.rooms.first { $0.kind == .luxuryApartment }!
        let luxuryCenter = Double(luxuryInterior.slot)+Double(luxuryInterior.kind.width)/2
        controller.game.travelers = [Traveler(id:9902,roomID:luxuryInterior.id,floor:luxuryInterior.floor,
                                               destination:luxuryInterior.floor,x:luxuryCenter,
                                               destinationX:luxuryCenter-2,phase:.walkingToRoom)]
        let luxuryWalker = controller.gameView.travelerMotionTargets(controller.game).first!
        let luxuryBounds = controller.gameView.roomRect(luxuryInterior)
        precondition(abs(luxuryWalker.position.y-(luxuryBounds.minY+RoomActivity.floorY(for:luxuryInterior)*luxuryBounds.height)) < 0.001,
                     "Visitors follow the same artwork floor as the room's residents")
        precondition(luxuryWalker.position.y < luxuryBounds.minY+2, "Luxury visitors stand on the low floorboard instead of floating above it")
        precondition(luxuryWalker.facingLeft, "Floor registration must preserve the traveler's route heading")
        controller.game.travelers = interiorTravelers
        window.setContentSize(NSSize(width:1440,height:940))
        controller.view.setFrameSize(NSSize(width:1440,height:940)); layout()
        controller.gameView.fitTower()
        try snapshot("lofty-room-variations-day")
        controller.gameView.spriteClock.advance(seconds:12,isRunning:true)
        try snapshot("lofty-room-variations-moving")
        controller.game.minute = 60
        controller.updateUI(rebuildInspector:true)
        try snapshot("lofty-room-variations-night")
        let frozen = controller.gameView.spriteClock.elapsed
        for _ in 0..<30 { controller.frame() }
        precondition(controller.gameView.spriteClock.elapsed == frozen, "Pausing freezes room activities")
        print("Interior UI checks passed: style controls, free changes, apartment and luxury properties, unlocks, rendering, and paused activity.")
        // Exercise the complete progression loop through native controls.
        controller.game = TowerState.newGame(); controller.resetSelection(); controller.updateUI(rebuildInspector:true)
        precondition(controller.ambitionPreview.bar.doubleValue < 1)
        precondition(controller.excavationMenuItems.allSatisfy { !$0.isEnabled }, "Excavation remains locked before level 2")
        controller.game.earnedStars = 3; controller.game.cash = 300000
        try controller.game.addFloor(); try controller.game.addFloor()
        controller.menuExcavate(); controller.menuExcavate()
        precondition(controller.game.bottomFloor == -2)
        controller.chooseElevator(.standard)
        controller.dragged(fromFloor:-2,fromSlot:60,toFloor:2,toSlot:60)
        controller.choose(.ramen); controller.clicked(floor:-1,slot:0)
        controller.choose(.bookshop); controller.clicked(floor:-1,slot:14)
        controller.choose(.arcade); controller.clicked(floor:-2,slot:0)
        precondition(controller.game.undergroundDistrictActive, "Basement rooms must form a live district")
        let basementRoom = controller.game.rooms.first { $0.floor == -1 }!
        controller.revealRoom(basementRoom.id); layout()
        precondition(descendants(controller.detailStack).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Floor B1") })
        let basementRect = controller.gameView.roomRect(basementRoom)
        let basementPoint = CGPoint(x:controller.gameView.origin.x + basementRect.midX*controller.gameView.scale,y:controller.gameView.origin.y + basementRect.midY*controller.gameView.scale)
        precondition(controller.gameView.hit(basementPoint)?.floor == -1)
        controller.openProgression(); layout()
        let ready = controller.game.visibleAmbitions.first { $0.isComplete && !$0.isClaimed }!
        let claim = descendants(controller.detailStack).compactMap { $0 as? ActionButton }.first { $0.title == "Claim $\(ready.reward.formatted())" }!
        let beforeClaim = controller.game.cash
        NSApp.sendAction(claim.action!,to:claim.target,from:claim)
        precondition(controller.game.cash == beforeClaim + ready.reward && controller.game.ambitions.first { $0.id == ready.id }!.isClaimed)
        let rewardCard = controller.celebration!
        precondition(rewardCard.superview != nil && !rewardCard.isDismissed)
        controller.claimAmbitionReward(ready.id)
        precondition(controller.game.cash == beforeClaim + ready.reward, "Repeated claims cannot award money")
        let openHouse = descendants(controller.detailStack).compactMap { $0 as? ActionButton }.first { $0.title == "Start · $1,500" }!
        NSApp.sendAction(openHouse.action!,to:openHouse.target,from:openHouse)
        precondition(controller.game.abilityRemainingMinutes(.openHouse) == 720)
        precondition(rewardCard.isDismissed, "A new celebration must remove the previous one")
        controller.celebration?.dismissImmediately()
        controller.showingInfo = false; controller.updateUI(rebuildInspector:true); layout(); controller.gameView.fitTower()
        try snapshot("lofty-underground-progression")
        controller.openProgression(); layout()
        try snapshot("lofty-ambitions-inspector")
        controller.game = TowerState.demoTower()
        for index in controller.game.rooms.indices { controller.game.rooms[index].occupancy = 1; controller.game.rooms[index].happiness = 0.9 }
        controller.resetSelection(); controller.updateUI(rebuildInspector:true); controller.gameView.fitTower()
        controller.frameCount = 2; controller.speed = 1; controller.frame(); controller.speed = 0
        precondition(controller.game.stars == 2)
        let levelCard = controller.celebration!
        precondition(levelCard.accessibilityLabel()?.contains("LEVEL 2 UNLOCKED") == true, "Actual simulation promotions must trigger the celebration")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            precondition(levelCard.layer?.animation(forKey:"milestoneEntrance") != nil)
            precondition(levelCard.layer?.sublayers?.contains { $0.animation(forKey:"confetti") != nil } == true)
        }
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        try snapshot("lofty-level-up")
        levelCard.dismissImmediately()
        precondition(levelCard.superview == nil && levelCard.isDismissed)
        print("Progression UI checks passed: locked excavation, underground building and hit testing, district bonus, one-time claim, ability activation, replacement/dismissal and animated promotion.")

        // Keep the same world point under the zoom anchor, including below ground
        // and across the old central elevator gap. Pixel snapping allows 0.5 pt.
        controller.game = .demoTower(); controller.game.earnedStars = 5; controller.game.cash = 500000
        try controller.game.widenTower(left:true)
        try controller.game.excavateBasement(); try controller.game.excavateBasement()
        let canvas = controller.gameView!
        func assertAnchoredZoom(_ factor: CGFloat, at anchor: CGPoint?, checkCell: Bool = true) {
            let point = anchor ?? CGPoint(x:canvas.bounds.midX,y:canvas.bounds.midY)
            let world = CGPoint(x:(point.x-canvas.origin.x)/canvas.scale,y:(point.y-canvas.origin.y)/canvas.scale)
            let before = canvas.hit(point)
            canvas.zoom(by:factor,at:anchor)
            let projected = CGPoint(x:canvas.origin.x+world.x*canvas.scale,y:canvas.origin.y+world.y*canvas.scale)
            precondition(abs(projected.x-point.x) <= 0.501 && abs(projected.y-point.y) <= 0.501, "Zoom must preserve its world anchor within pixel rounding")
            let after = canvas.hit(point)
            if checkCell { precondition(before?.floor == after?.floor && before?.slot == after?.slot, "Zoom must keep the anchored cell under the cursor") }
        }
        for (floor, slot) in [(3,-4),(-2,41),(1,controller.game.core)] {
            canvas.scale = 1.75; canvas.pan = .zero
            let worldX = slot == controller.game.core ? CGFloat(slot)*8+canvas.shaftWidth/2 : canvas.roomX(slot)+4
            let world = CGPoint(x:worldX,y:CGFloat(floor)*24+12)
            let screen = CGPoint(x:canvas.origin.x+world.x*canvas.scale,y:canvas.origin.y+world.y*canvas.scale)
            canvas.pan.x += canvas.bounds.width*0.23-screen.x
            canvas.pan.y += canvas.bounds.height*0.72-screen.y
            let anchor = CGPoint(x:canvas.origin.x+world.x*canvas.scale,y:canvas.origin.y+world.y*canvas.scale)
            precondition(canvas.bounds.contains(anchor) && canvas.hit(anchor)?.floor == floor && canvas.hit(anchor)?.slot == slot)
            assertAnchoredZoom(1.25,at:anchor)
            assertAnchoredZoom(0.8,at:anchor)
        }
        let clampAnchor = CGPoint(x:canvas.bounds.width*0.67,y:canvas.bounds.height*0.31)
        assertAnchoredZoom(100,at:clampAnchor,checkCell:false)
        precondition(canvas.scale == 16)
        let upperPan = canvas.pan
        canvas.zoom(by:2,at:clampAnchor)
        precondition(canvas.scale == 16 && canvas.pan == upperPan, "Zooming at the upper limit must not drift")
        assertAnchoredZoom(0.001,at:clampAnchor,checkCell:false)
        precondition(canvas.scale == 0.25)
        let lowerPan = canvas.pan
        canvas.zoom(by:0.5,at:clampAnchor)
        precondition(canvas.scale == 0.25 && canvas.pan == lowerPan, "Zooming at the lower limit must not drift")
        assertAnchoredZoom(2,at:nil,checkCell:false)
        print("Zoom UI checks passed: off-center cells, basement floors, widened tower, legacy shaft, centered controls, clamping, and no drift at limits.")

        // Coverage feedback must follow the real allocation and offer a usable build action.
        var neighborhood = TowerState.newGame(scenerySeed: 42)
        neighborhood.cash = 500000; neighborhood.earnedStars = 5
        try neighborhood.addFloor(); try neighborhood.addFloor()
        try neighborhood.addElevator(.standard, at: 61, from: 0, to: 2)
        var neighbors: [Int] = []
        for slot in [0, 9, 18, 27, 36, 45] {
            let id = try neighborhood.build(.office, floor: 1, slot: slot)
            neighborhood.rooms[neighborhood.rooms.firstIndex { $0.id == id }!].occupancy = 1
            neighbors.append(id)
        }
        let cafe = try neighborhood.build(.cafe, floor: 2, slot: 0)
        controller.game = neighborhood; controller.selectedKind = nil
        controller.gameView.scale = 1.5; controller.gameView.pan = .zero
        controller.showRoomIssues(); layout()
        func inspectorText() -> String { descendants(controller.detailStack).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") }
        precondition(inspectorText().contains("1 floor needs more service"))
        precondition(inspectorText().contains("Food · 50% covered") && inspectorText().contains("Shops · 0% covered"))
        let foodButton = controller.detailStack.arrangedSubviews.compactMap { $0 as? ActionButton }.first { $0.title == "Add food nearby" }!
        NSApp.sendAction(foodButton.action!, to: foodButton.target, from: foodButton)
        precondition(controller.selectedKind == .restaurant && controller.roomBrowser.selection == .restaurant)
        precondition(controller.statusLabel.stringValue.contains("floor 1"))
        controller.revealRoom(neighbors[0]); layout()
        precondition(inspectorText().contains("Food · 50%") && inspectorText().contains("Nearby venues need more capacity"))
        precondition(inspectorText().contains("No service within reach"))
        try snapshot("lofty-service-shortage")
        controller.revealRoom(cafe); layout()
        precondition(inspectorText().contains("Serving 120 / 120 neighbors"))
        let restaurant = try controller.game.build(.restaurant, floor: 2, slot: 12)
        try controller.game.build(.shop, floor: 2, slot: 30)
        controller.updateUI(rebuildInspector: true)
        controller.showRoomIssues(); layout()
        precondition(inspectorText().contains("All occupied neighborhoods have food and shops within reach."))
        precondition(!controller.detailStack.arrangedSubviews.compactMap { $0 as? ActionButton }.contains { $0.title == "Add food nearby" })
        controller.revealRoom(neighbors[0]); layout()
        precondition(inspectorText().contains("Food · 100%") && inspectorText().contains("Shops · 100%"))
        try snapshot("lofty-services-covered")
        try controller.game.demolish(restaurant)
        controller.updateUI(rebuildInspector: true)
        precondition(inspectorText().contains("Food · 50%"), "Demolition must refresh coverage without advancing time")
        controller.showRoomIssues(); layout()
        let shopAction = controller.serviceBuildButton(.shops, near: neighbors[0])
        NSApp.sendAction(shopAction.action!, to: shopAction.target, from: shopAction)
        precondition(controller.selectedKind == .shop)
        let fundedCash = controller.game.cash
        controller.game.cash = 0
        let unfundedFood = controller.serviceBuildButton(.food, near: neighbors[0])
        NSApp.sendAction(unfundedFood.action!, to: unfundedFood.target, from: unfundedFood)
        precondition(controller.selectedKind == nil && controller.statusLabel.stringValue == "Need $16,000 more", "Service shortcuts must preserve the funding blocker")
        controller.game.cash = fundedCash
        for kind in [RoomKind.restaurant, .cafe, .ramen, .shop, .bookshop] {
            controller.roomBrowser.select(kind); layout()
            let description = detailLabels().first { $0.stringValue.contains("neighbors within") }!
            let rect = description.convert(description.bounds, to: controller.roomBrowser.detailPanel)
            precondition(controller.roomBrowser.detailPanel.bounds.contains(rect), "Service description must fit catalog")
        }
        precondition(descendants(controller.view).compactMap { $0 as? NSPopUpButton }.contains { $0.itemTitles == ["Coverage: Off", "Coverage: Food", "Coverage: Shops"] }, "Construction needs a coverage overlay selector")
        print("Neighborhood service UI checks passed: grouped shortages, room percentages and causes, provider load, food/shop construction actions, and immediate construction/demolition refresh.")

        controller.game = neighborhood; controller.choose(nil); controller.selectedRoom = nil
        window.setContentSize(NSSize(width: 1080, height: 650))
        controller.view.setFrameSize(NSSize(width: 1080, height: 650)); layout()
        controller.gameView.fitTower()
        let overlayEncoder = JSONEncoder(); overlayEncoder.outputFormatting = .sortedKeys
        let beforeOverlay = try overlayEncoder.encode(controller.game)
        func selectOverlay(_ index: Int) {
            controller.coveragePicker.selectItem(at: index)
            NSApp.sendAction(controller.coveragePicker.action!, to: controller.coveragePicker.target, from: controller.coveragePicker)
            layout()
        }
        let firstNeighbor = controller.game.rooms.first { $0.id == neighbors[0] }!
        selectOverlay(1)
        precondition(controller.coverageOverlay == .food)
        controller.gameView.hovered = nil
        let restingLegend = controller.gameView.coverageLegendRect
        controller.gameView.hovered = (floor: 1, slot: 0)
        precondition(controller.gameView.coverageLegendRect == restingLegend, "Hover details must not change the legend hit boundary")
        controller.gameView.hovered = nil
        precondition(controller.coverageMark(for: firstNeighbor, service: .food)?.state == .partial)
        precondition(controller.coverageMark(for: firstNeighbor, service: .food)?.label == "50%")
        precondition(controller.gameView.coverageLegendText!.contains("6 rooms need"))
        let selectorRect = controller.coveragePicker.convert(controller.coveragePicker.bounds, to: controller.view)
        precondition(controller.view.bounds.contains(selectorRect), "Overlay control must fit the minimum window")
        let originalHit = controller.gameView.hit(CGPoint(x: controller.gameView.origin.x+36*controller.gameView.scale, y: controller.gameView.origin.y+36*controller.gameView.scale))
        selectOverlay(2)
        precondition(controller.coverageOverlay == .shops && controller.coverageMark(for: firstNeighbor, service: .shops)?.state == .missing)
        controller.gameView.hovered = (floor: 1, slot: 0)
        precondition(controller.gameView.coverageLegendText!.contains("no service within reach"))
        try snapshot("lofty-overlay-shops")
        selectOverlay(1)
        controller.roomBrowser.select(.restaurant)
        precondition(controller.coverageOverlay == .food, "Changing construction tools must preserve the overlay")
        controller.gameView.hovered = (floor: 2, slot: 12)
        precondition(controller.gameView.coverageGuideRooms(.food).count == 1)
        precondition(controller.gameView.coverageGuideRooms(.shops).isEmpty)
        controller.gameView.startCell = (floor: 2, slot: 12)
        controller.gameView.hovered = (floor: 2, slot: 28)
        precondition(controller.gameView.coverageGuideRooms(.food).map(\.slot) == [12, 28], "A drag previews each proposed venue")
        controller.gameView.startCell = nil
        controller.gameView.hovered = (floor: 1, slot: 0)
        precondition(controller.gameView.coverageGuideRooms(.food).isEmpty, "Occupied placements must not advertise service")
        controller.gameView.hovered = (floor: 2, slot: 12)
        try snapshot("lofty-overlay-food")
        precondition(controller.gameView.bounds.contains(controller.gameView.coverageLegendRect))
        let legendPoint = CGPoint(x: controller.gameView.coverageLegendRect.midX, y: controller.gameView.coverageLegendRect.midY)
        precondition(controller.gameView.hit(legendPoint) == nil && controller.gameView.signalHit(legendPoint) == nil, "The legend must shield covered construction cells")
        let afterOverlay = try overlayEncoder.encode(controller.game)
        precondition(afterOverlay == beforeOverlay, "Viewing coverage must not mutate a tower")
        controller.dragged(fromFloor: 2, fromSlot: 12, toFloor: 2, toSlot: 12)
        precondition(controller.coverageMark(for: firstNeighbor, service: .food)?.state == .covered)
        precondition(controller.coverageMark(for: firstNeighbor, service: .food)?.label == "100%")
        try snapshot("lofty-overlay-improved")
        controller.choose(nil)
        controller.revealRoom(cafe)
        precondition(controller.gameView.coverageGuideRooms(.food).count == 1, "Inspecting a provider reveals its reach")
        controller.setFocusMode(true)
        precondition(controller.gameView.visibleCoverageService == nil && controller.coverageOverlay == .food)
        controller.setFocusMode(false)
        precondition(controller.gameView.visibleCoverageService == .food)
        // Inactive demand is gray rather than a false 0%; empty rooms create no shortage.
        controller.game.rooms[controller.game.rooms.firstIndex { $0.id == neighbors[0] }!].occupancy = 0
        controller.updateUI()
        precondition(controller.coverageMark(for: controller.game.rooms.first { $0.id == neighbors[0] }!, service: .food)?.state == .vacant)
        controller.game.elevators.removeAll(); controller.updateUI()
        precondition(controller.coverageMark(for: firstNeighbor, service: .food)?.state == .inactive)
        precondition(controller.gameView.coverageGuideRooms(.food).isEmpty)
        controller.gameView.scale = 0.25; try snapshot("lofty-overlay-zoomed-out")
        selectOverlay(0)
        precondition(controller.coverageOverlay == nil && controller.gameView.coverageLegendText == nil)
        let afterHit = controller.gameView.hit(CGPoint(x: controller.gameView.origin.x+36*controller.gameView.scale, y: controller.gameView.origin.y+36*controller.gameView.scale))
        precondition(originalHit?.floor == afterHit?.floor && originalHit?.slot == afterHit?.slot, "Overlay must preserve construction hit testing")
        print("Coverage overlay UI checks passed: modes, live coverage, hover details, minimum-size control and legend, valid/invalid/drag reach guides, construction recovery, focus restoration, inactive/vacant states, zoom and unchanged save data.")
        controller.timer?.invalidate()
    }
}
