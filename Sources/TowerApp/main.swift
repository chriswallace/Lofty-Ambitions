import AppKit
import TowerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var controller: GameController!
    func applicationDidFinishLaunching(_ notification:Notification) {
        controller = GameController()
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:940),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Lofty Ambitions — New Horizon"
        window.minSize = NSSize(width:1080,height:650)
        window.contentViewController = controller
        window.delegate = self
        window.center(); window.makeKeyAndOrderFront(nil)
        window.backgroundColor = Theme.panel
        window.appearance = NSAppearance(named:.aqua)
        setupMenu()
        if CommandLine.arguments.contains("--incident-demo") { setupIncidentDemo() }
        else if !CommandLine.arguments.contains("--fresh") { controller.restoreAutosave() }
        if CommandLine.arguments.contains("--room-demo") || CommandLine.arguments.contains("--expansion-demo") {
            controller.game = .newGame(scenerySeed: 20260920)
            controller.game.cash = 500000; controller.game.earnedStars = 5; controller.speed = 0
            let roomKinds: [RoomKind] = CommandLine.arguments.contains("--expansion-demo") ? [.ramen, .bookshop, .coworking, .spa] : [.cafe, .arcade, .fitness, .observatory]
            for (i, kind) in roomKinds.enumerated() {
                try! controller.game.addFloor()
                try! controller.game.build(kind, floor: i+1, slot: 0)
                try! controller.game.build(kind, floor: i+1, slot: 32)
            }
            try! controller.game.addElevator(.standard, from: 0, to: 4)
            for i in controller.game.rooms.indices { controller.game.rooms[i].occupancy = 0.75 }
            controller.game.minute = 720
            if CommandLine.arguments.contains("--expansion-demo") { try! controller.game.upgradeLobby() }
            controller.roomBrowser.select(roomKinds[0])
            controller.updateUI(rebuildInspector: true)
        }
        if CommandLine.arguments.contains("--interior-demo") { try! controller.setupInteriorDemo() }
        if CommandLine.arguments.contains("--focus") { controller.setFocusMode(true) }
        if let index=CommandLine.arguments.firstIndex(of:"--city-seed"),CommandLine.arguments.count>index+1,let value=UInt64(CommandLine.arguments[index+1]) { controller.game.scenerySeed=value }
        if let index=CommandLine.arguments.firstIndex(of:"--advance-minutes"),CommandLine.arguments.count>index+1,let minutes=Int(CommandLine.arguments[index+1]) {controller.game.advance(minutes:min(1440,max(0,minutes)))}
        if CommandLine.arguments.contains("--incident-demo") {window.contentView?.layoutSubtreeIfNeeded()}
        controller.gameView.fitTower()
        if !CommandLine.arguments.contains("--incident-demo") {controller.gameView.scale=max(1.5,controller.gameView.scale)}
        if let index=CommandLine.arguments.firstIndex(of:"--view-scale"),CommandLine.arguments.count>index+1,let value=Double(CommandLine.arguments[index+1]) {
            controller.gameView.scale=min(16,max(0.25,value))
        }
        if let index=CommandLine.arguments.firstIndex(of:"--cloud-seconds"),CommandLine.arguments.count>index+1,let value=Double(CommandLine.arguments[index+1]) {
            controller.gameView.cloudSeconds=max(0,value)
        }
        window.makeFirstResponder(controller.gameView)
        let previewMode = ["--screenshot", "--incident-demo", "--room-demo", "--expansion-demo", "--interior-demo"].contains { CommandLine.arguments.contains($0) }
        if !previewMode || CommandLine.arguments.contains("--title-screen") { controller.showTitleScreen() }
        NSApp.activate(ignoringOtherApps:true)
        if let index = CommandLine.arguments.firstIndex(of:"--screenshot"),CommandLine.arguments.count > index+1 {
            let path = CommandLine.arguments[index+1]
            controller.speed = 0
            controller.updateUI(rebuildInspector:true)
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in
                guard let self,let view = self.window.contentView,let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path)) }
                if CommandLine.arguments.contains("--exit-after-screenshot") { NSApp.terminate(nil) }
            }
        }
    }
    func setupMenu() {
        let bar = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; bar.addItem(appItem)
        appMenu.addItem(withTitle:"About Lofty Ambitions",action:#selector(about),keyEquivalent:"").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Quit Lofty Ambitions",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file = NSMenu(); let fileItem = NSMenuItem(title:"File",action:nil,keyEquivalent:""); fileItem.submenu = file; bar.addItem(fileItem)
        for (title,action,key) in [("New Tower",#selector(newTower),"n"),("Open Tower…",#selector(openTower),"o"),("Save Tower",#selector(saveTower),"s")] { file.addItem(withTitle:title,action:action,keyEquivalent:key).target = self }
        file.addItem(withTitle:"Recover a Tower…",action:#selector(recoverTower),keyEquivalent:"").target = self
        controller.installConstructionMenus(in:bar)
        let game = NSMenu(); let gameItem = NSMenuItem(title:"Game",action:nil,keyEquivalent:""); gameItem.submenu = game; bar.addItem(gameItem)
        game.addItem(withTitle:"Pause / Resume",action:#selector(pause),keyEquivalent:"p").target = self
        game.addItem(withTitle:"Fit Tower",action:#selector(fit),keyEquivalent:"0").target = self
        let sandbox=NSMenu();let sandboxItem=NSMenuItem(title:"Incident Sandbox",action:nil,keyEquivalent:"");sandboxItem.submenu=sandbox;game.addItem(sandboxItem)
        for (title,action) in [("Party in selected hotel",#selector(triggerParty)),("Rent overdue in selected apartment",#selector(triggerRentArrears)),("Fire in selected room",#selector(triggerFire))] {sandbox.addItem(withTitle:title,action:action,keyEquivalent:"").target=self}
        game.addItem(withTitle:"How to Play",action:#selector(help),keyEquivalent:"?").target = self
        NSApp.mainMenu = bar
    }
    @objc func about() { let alert = NSAlert(); alert.messageText = "Lofty Ambitions"; alert.informativeText = "Build a neighborhood in the sky.\nA native macOS tower management game.\nVersion \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")\n\nGrow a Tokyo-inspired tower from a neighborhood lobby to a bustling city landmark. Original pixel artwork, lively residents, and sky-high possibilities.\n\nBuilt with Swift and AppKit. No emulator required."; alert.runModal() }
    @objc func newTower() { controller.newGame() }
    @objc func openTower() { controller.openSave() }
    @objc func recoverTower() { controller.openSave(recovery:true) }
    @objc func saveTower() { controller.save() }
    @objc func pause() { controller.togglePause() }
    @objc func fit() { controller.gameView.fitTower() }
    @objc func help() { controller.showHelp() }
    @objc func triggerParty() {trigger(.party)}
    @objc func triggerRentArrears() {trigger(.rentArrears)}
    @objc func triggerFire() {trigger(.fire)}
    func trigger(_ kind:IncidentKind) {controller.perform {try $0.triggerIncident(kind,roomID:self.controller.selectedRoom ?? -1)}}
    func setupIncidentDemo() {
        controller.game = .demoTower();controller.game.cash=500_000;controller.game.earnedStars=2
        try? controller.game.addFloor();try? controller.game.extendElevators()
        let hotelID=try? controller.game.build(.hotel,floor:5,slot:0)
        _ = try? controller.game.build(.housekeeping,floor:5,slot:32)
        let apartmentID=controller.game.rooms.first(where:{$0.kind == .apartment})?.id
        let fireID=controller.game.rooms.first(where:{$0.kind == .office && $0.floor == 4})?.id
        if let hotelID {try? controller.game.triggerIncident(.party,roomID:hotelID)}
        if let apartmentID {try? controller.game.triggerIncident(.rentArrears,roomID:apartmentID)}
        if let fireID {try? controller.game.triggerIncident(.fire,roomID:fireID);try? controller.game.respond(to:fireID,action:.dispatchFireDepartment)}
        controller.game.advance(minutes:90);controller.speed=0;controller.didModify=false;controller.showRoomIssues()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification:Notification) { if !CommandLine.arguments.contains("--exit-after-screenshot") { controller?.autosave() } }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
