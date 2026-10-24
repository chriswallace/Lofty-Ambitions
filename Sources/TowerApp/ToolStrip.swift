import AppKit
import TowerCore

extension GameController {
    func setupToolStrip(_ strip: NSView) {
        func button(_ key: String, _ title: String, _ symbol: String, _ help: String, action: @escaping () -> Void) -> ActionButton {
            let button = ActionButton(title, symbol: symbol, action: action)
            button.toolTip = help; button.setAccessibilityLabel(title)
            if ["inspect", "delete", "floor"].contains(key) { button.setButtonType(.pushOnPushOff) }
            toolButtons[key] = button
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            return button
        }
        func divider() -> NSView {
            let view = NSBox(); view.boxType = .separator
            view.widthAnchor.constraint(equalToConstant: 1).isActive = true
            view.heightAnchor.constraint(equalToConstant: 20).isActive = true
            return view
        }
        let inspect = button("inspect", "Inspect / edit", "cursorarrow", "Inspect a room to change its rent, leasing requirements, or respond to an incident. I or Esc.") { [weak self] in self?.choose(nil) }
        let delete = button("delete", "Delete", "trash", "Review removal of a room or elevator, then confirm a 50% refund. X.") { [weak self] in self?.chooseDemolition() }
        elevatorPicker = NSPopUpButton(frame: .zero, pullsDown: true)
        elevatorPicker.addItem(withTitle: "Build")
        for (title, action) in [("Draw or extend a floor · $150/cell", #selector(menuFloor)), ("Add floor · $8,000", #selector(menuAddFloor)), ("Widen left · 8 cells", #selector(menuWidenLeft)), ("Widen right · 8 cells", #selector(menuWidenRight))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; elevatorPicker.menu?.addItem(item)
            trackWideningItem(item)
        }
        elevatorPicker.menu?.addItem(.separator())
        elevatorPicker.menu?.autoenablesItems = false
        let excavate = NSMenuItem(title: "Excavate B1 · Level 2", action: #selector(menuExcavate), keyEquivalent: "")
        excavate.target = self; elevatorPicker.menu?.addItem(excavate); excavationMenuItems.append(excavate)
        elevatorPicker.menu?.addItem(.separator())
        for kind in ElevatorKind.allCases {
            let item = NSMenuItem(title: "\(kind.title) · $\(kind.cost.formatted())", action: #selector(pickElevator(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = kind.rawValue
            elevatorPicker.menu?.addItem(item)
        }
        elevatorPicker.menu?.addItem(.separator())
        let extend = NSMenuItem(title: "Extend all shafts", action: #selector(extendShafts), keyEquivalent: "")
        extend.target = self; elevatorPicker.menu?.addItem(extend); extendShaftsItem = extend
        elevatorPicker.setAccessibilityLabel("Build floors, widen tower, or add elevators")
        elevatorPicker.toolTip = "Build floors, widen the tower, add elevators, or extend shafts."
        elevatorPicker.font = .systemFont(ofSize: 12, weight: .medium)
        elevatorPicker.widthAnchor.constraint(equalToConstant: 106).isActive = true
        coveragePicker = NSPopUpButton(frame: .zero, pullsDown: false)
        coveragePicker.addItems(withTitles: ["Coverage: Off", "Coverage: Food", "Coverage: Shops"])
        coveragePicker.target = self; coveragePicker.action = #selector(changeCoverageOverlay(_:))
        coveragePicker.font = .systemFont(ofSize: 12, weight: .medium)
        coveragePicker.setAccessibilityLabel("Service coverage overlay")
        coveragePicker.toolTip = "Show food or shop coverage while building. Percentages describe current demand; select a venue or place one to see its reach."
        coveragePicker.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let issues = button("issues", "Issues", "exclamationmark.bubble", "Find rooms that need attention.") { [weak self] in self?.showRoomIssues() }
        let info = button("info", "Tower", "info.circle", "View finances, goals, and construction limits.") { [weak self] in self?.showTowerInformation() }
        let save = button("save", "Save", "square.and.arrow.down", "Save this tower. ⌘S.") { [weak self] in self?.save() }
        let focus = button("focus", "Focus", "viewfinder", "Hide panels and enjoy the tower. Tab toggles; Esc returns.") { [weak self] in self?.toggleFocusMode() }
        let stack = hstack([inspect, delete, elevatorPicker, coveragePicker, spacer, issues, info, save, divider(), focus], spacing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: strip.centerYAnchor)
        ])
    }
    @objc func pickElevator(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let kind = ElevatorKind(rawValue: value) else { return }
        chooseElevator(kind)
    }
    @objc func extendShafts() { performCommand(.extendElevators) }
    func chooseDemolition() {
        choose(nil); demolition = true
        message("Delete tool · Click a room or shaft to review removal · Esc cancels")
        updateUI()
    }
    func refreshToolStrip() {
        refreshCoverageControl()
        let inspecting = selectedKind == nil && !demolition && !floorMode && elevatorTool == nil
        for (key, active) in [("inspect", inspecting), ("delete", demolition), ("floor", floorMode)] {
            toolButtons[key]?.state = active ? .on : .off
            toolButtons[key]?.contentTintColor = active ? (key == "delete" ? .systemRed : Theme.accent) : Theme.ink
        }
        elevatorPicker?.contentTintColor = elevatorTool == nil && !floorMode ? Theme.ink : Theme.accent
        elevatorPicker?.item(at: 0)?.title = floorMode ? "Floor tool" : elevatorTool != nil ? "Elevator tool" : "Build"
        let issueCount = game.rooms.filter { game.signal(for: $0, coverage: serviceCoverage) != nil }.count
        toolButtons["issues"]?.title = issueCount > 0 ? "Issues \(issueCount)" : "Issues"
        focusIssuesButton?.title = issueCount > 0 ? "Issues \(issueCount)" : "No issues"
        toolButtons["issues"]?.contentTintColor = showingIssues ? Theme.accent : Theme.ink
        toolButtons["info"]?.contentTintColor = showingInfo ? Theme.accent : Theme.ink
        extendShaftsItem?.title = game.extensionCost > 0 ? "Extend all shafts · $\(game.extensionCost.formatted())" : "All shafts fully extended"
        extendShaftsItem?.isEnabled = game.extensionCost > 0
        refreshWideningPrices()
        for item in excavationMenuItems {
            item.title = game.basementDepth == 4 ? "All basements excavated" : "Excavate B\(game.basementDepth+1) · $\(game.nextBasementCost.formatted())"
            item.toolTip = game.excavationBlocker ?? "Dig a new basement, then connect it to the lobby with an elevator."
            item.isEnabled = game.excavationBlocker == nil
            if game.basementDepth >= game.basementPermitDepth && game.basementDepth < 4 {
                item.title = "Excavate B\(game.basementDepth+1) · Level \(game.basementDepth+2)"
            }
        }
    }
    private func trackWideningItem(_ item: NSMenuItem) {
        if item.action == #selector(menuWidenLeft) { wideningMenuItems[true, default: []].append(item) }
        if item.action == #selector(menuWidenRight) { wideningMenuItems[false, default: []].append(item) }
    }
    func refreshWideningPrices() {
        for (left, items) in wideningMenuItems {
            let direction = left ? "left" : "right"
            do {
                let cost = try game.towerWideningCost(left: left)
                let floors = game.topFloor + 1 + game.basementDepth
                for item in items {
                    item.title = "Widen \(direction) · $\(cost.formatted()) (\(floors) \(floors == 1 ? "floor" : "floors"))"
                    item.toolTip = "Extend this edge by 8 cells on every floor, including the lobby and excavated basements. $150 per added cell per floor; narrower floors also pay for alignment. Total: $\(cost.formatted())."
                }
            } catch {
                for item in items { item.title = "Widen \(direction) · Limit reached"; item.toolTip = error.localizedDescription }
            }
        }
    }
    func installConstructionMenus(in menuBar: NSMenu) {
        let viewMenu = NSMenu(title: "View")
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: ""); viewItem.submenu = viewMenu; menuBar.addItem(viewItem)
        let focus = viewMenu.addItem(withTitle: "Distraction-free mode", action: #selector(toggleFocusMode), keyEquivalent: "f")
        focus.keyEquivalentModifierMask = [.command, .shift]; focus.target = self; focusMenuItem = focus
        let rooms = NSMenu(title: "Rooms")
        let roomItem = NSMenuItem(title: "Rooms", action: nil, keyEquivalent: ""); roomItem.submenu = rooms; menuBar.addItem(roomItem)
        let search = rooms.addItem(withTitle: "Search Rooms…", action: #selector(searchRooms), keyEquivalent: "r")
        search.target = self; search.keyEquivalentModifierMask = [.command, .shift]
        rooms.addItem(.separator())
        for category in RoomCatalog.categories {
            let submenu = NSMenu(title: category.title)
            let section = NSMenuItem(title: category.title, action: nil, keyEquivalent: ""); section.submenu = submenu; rooms.addItem(section)
            for room in RoomCatalog.search(query: "", category: category) {
                let item = submenu.addItem(withTitle: "\(room.title) · $\(room.cost.formatted())", action: #selector(browseRoomFromMenu(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = room.kind.rawValue
            }
        }
        let tools = NSMenu(title: "Tools")
        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: ""); toolsItem.submenu = tools; menuBar.addItem(toolsItem)
        for (title, action) in [("Inspect / edit", #selector(menuInspect)), ("Delete room or shaft", #selector(menuDelete)), ("Draw floor", #selector(menuFloor)), ("Add floor · $8,000", #selector(menuAddFloor)), ("Widen left", #selector(menuWidenLeft)), ("Widen right", #selector(menuWidenRight))] {
            let item = tools.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self; trackWideningItem(item)
        }
        let elevators = NSMenu(title: "Elevators")
        let excavate = tools.addItem(withTitle: "Excavate B1 · Level 2", action: #selector(menuExcavate), keyEquivalent: "")
        excavate.target = self; excavationMenuItems.append(excavate)
        let item = NSMenuItem(title: "Elevators", action: nil, keyEquivalent: ""); item.submenu = elevators; tools.addItem(item)
        for kind in ElevatorKind.allCases {
            let item = elevators.addItem(withTitle: "\(kind.title) · $\(kind.cost.formatted())", action: #selector(pickElevator(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = kind.rawValue
        }
        elevators.addItem(.separator()); elevators.addItem(withTitle: "Extend all shafts", action: #selector(extendShafts), keyEquivalent: "").target = self
        refreshWideningPrices()
    }
    @objc func searchRooms() { if focusMode { setFocusMode(false) }; roomBrowser.focusSearch() }
    @objc func browseRoomFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = RoomKind(rawValue: raw) else { return }
        roomBrowser.select(kind)
    }
    @objc func menuInspect() { choose(nil) }
    @objc func menuDelete() { chooseDemolition() }
    @objc func menuFloor() { chooseFloor() }
    @objc func menuAddFloor() { if performCommand(.addFloor) { gameView.revealTop() } }
    @objc func menuExcavate() {
        if performCommand(.excavateBasement) {
            gameView.revealBasement()
            message("B\(game.basementDepth) excavated! Connect an elevator, then add shops, food, services, or indoor leisure.")
        }
    }
    @objc func menuWidenLeft() { performCommand(.widenTower(left:true,cells:8)) }
    @objc func menuWidenRight() { performCommand(.widenTower(left:false,cells:8)) }
}
