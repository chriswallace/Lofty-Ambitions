import AppKit
import TowerCore
import TowerSession
import UniformTypeIdentifiers

final class GameController: NSViewController {
    let session = TowerSession()
    var game: TowerState { get { session.game } set { session.game = newValue } }
    var serviceCoverage = NeighborhoodCoverage()
    var coverageOverlay: NeighborhoodService?
    var coveragePicker: NSPopUpButton!
    var selectedKind: RoomKind?
    var selectedRoom: Int?
    var speed: Int { get { session.speed } set { session.speed = newValue } }
    var demolition = false
    var floorMode = false
    var elevatorTool: ElevatorKind?
    var selectedElevator: Int?
    var movingElevatorID: Int?
    var lastFrameTime = ProcessInfo.processInfo.systemUptime
    var inspectorWidth: NSLayoutConstraint!
    var showingInfo = false
    var showingIssues = false
    var timer: Timer?
    var titleScreen: TitleScreenView?
    var titleScreenSpeed = 1
    var titleScreenHiddenViews: [(NSView, Bool)] = []
    var titleScreenMenu: NSMenu?
    var pendingDemolitionAlert: NSAlert?
    var frameCount = 0
    var gameView: TowerView!
    let cashLabel = textLabel("",size:22,weight:.semibold,color:.white)
    let populationLabel = textLabel("",size:15,weight:.medium,color:.white)
    let timeLabel = textLabel("",size:15,weight:.medium,color:.white)
    let statusLabel = textLabel("",size:12,color:Theme.muted)
    let detailStack = NSStackView()
    var focusMode = false
    var chromeViews: [NSView] = []
    var regularCanvasConstraints: [NSLayoutConstraint] = []
    var focusCanvasConstraints: [NSLayoutConstraint] = []
    var focusBar: NSView!
    var focusPauseButton: ActionButton!
    var focusIssuesButton: ActionButton!
    var levelButton: ActionButton!
    var ambitionPreview: AmbitionPreviewView!
    var celebration: ProgressionCelebrationView?
    var excavationMenuItems: [NSMenuItem] = []
    var focusMenuItem: NSMenuItem?
    var roomBrowser: RoomBrowserView!
    var toolButtons: [String: ActionButton] = [:]
    var elevatorPicker: NSPopUpButton!
    var extendShaftsItem: NSMenuItem?
    var wideningMenuItems: [Bool: [NSMenuItem]] = [:]
    var pauseButton: ActionButton!
    var speedButtons: [Int: ActionButton] = [:]
    var savedURL: URL?
    var didModify = false
    var autosaveBlocked = false
    var bannerUntil: TimeInterval = 0
    var normalStatus = "Click a room to build · Esc cancels · Use the top tools to edit · Option-drag to pan"

    override func loadView() {
        view = PanelView(Theme.panel)
        let header = PanelView(Theme.chrome)
        let sidebar = PanelView(Theme.panel)
        let inspector = PanelView(Theme.surface)
        let footer = PanelView(Theme.chrome)
        let tools = PanelView(Theme.surface)
        gameView = TowerView(controller:self)
        for child in [header,tools,sidebar,inspector,footer,gameView!] {child.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(child)}
        chromeViews = [header, tools, sidebar, inspector, footer]
        inspectorWidth=inspector.widthAnchor.constraint(equalToConstant:0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo:view.topAnchor),header.leadingAnchor.constraint(equalTo:view.leadingAnchor),header.trailingAnchor.constraint(equalTo:view.trailingAnchor),header.heightAnchor.constraint(equalToConstant:48),
            footer.bottomAnchor.constraint(equalTo:view.bottomAnchor),footer.leadingAnchor.constraint(equalTo:view.leadingAnchor),footer.trailingAnchor.constraint(equalTo:view.trailingAnchor),footer.heightAnchor.constraint(equalToConstant:28),
            tools.topAnchor.constraint(equalTo:header.bottomAnchor),tools.leadingAnchor.constraint(equalTo:view.leadingAnchor),tools.trailingAnchor.constraint(equalTo:view.trailingAnchor),tools.heightAnchor.constraint(equalToConstant:46),
            sidebar.topAnchor.constraint(equalTo:tools.bottomAnchor),sidebar.bottomAnchor.constraint(equalTo:footer.topAnchor),sidebar.leadingAnchor.constraint(equalTo:view.leadingAnchor),sidebar.widthAnchor.constraint(equalToConstant:276),
            inspector.topAnchor.constraint(equalTo:tools.bottomAnchor),inspector.bottomAnchor.constraint(equalTo:footer.topAnchor),inspector.trailingAnchor.constraint(equalTo:view.trailingAnchor),inspectorWidth])
        regularCanvasConstraints = [gameView.topAnchor.constraint(equalTo:tools.bottomAnchor),gameView.bottomAnchor.constraint(equalTo:footer.topAnchor),gameView.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),gameView.trailingAnchor.constraint(equalTo:inspector.leadingAnchor)]
        focusCanvasConstraints = [gameView.topAnchor.constraint(equalTo:view.topAnchor),gameView.bottomAnchor.constraint(equalTo:view.bottomAnchor),gameView.leadingAnchor.constraint(equalTo:view.leadingAnchor),gameView.trailingAnchor.constraint(equalTo:view.trailingAnchor)]
        NSLayoutConstraint.activate(regularCanvasConstraints)
        setupHeader(header);setupSidebar(sidebar);setupInspector(inspector);setupToolStrip(tools)
        let footerStack=hstack([statusLabel,ActionButton("−",action:{[weak self] in self?.gameView.zoom(by:0.8)}),ActionButton("Fit",action:{[weak self] in self?.gameView.fitTower()}),ActionButton("+",action:{[weak self] in self?.gameView.zoom(by:1.25)})],spacing:6)
        footerStack.translatesAutoresizingMaskIntoConstraints=false;footer.addSubview(footerStack)
        statusLabel.maximumNumberOfLines=1;statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow,for:.horizontal)
        NSLayoutConstraint.activate([footerStack.leadingAnchor.constraint(equalTo:footer.leadingAnchor,constant:8),footerStack.trailingAnchor.constraint(equalTo:footer.trailingAnchor,constant:-8),footerStack.centerYAnchor.constraint(equalTo:footer.centerYAnchor)])
        setupFocusMode()
        updateUI(rebuildInspector:true)
        timer=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true){[weak self] _ in self?.frame()}
    }
    func setupHeader(_ header:NSView) {
        for label in [cashLabel,populationLabel,timeLabel] {label.font = .monospacedDigitSystemFont(ofSize:13,weight:.medium);label.textColor=Theme.ink}
        let brand=textLabel("Lofty Ambitions",size:16,weight:.bold)
        levelButton = ActionButton("Level 1", symbol: "star") { [weak self] in self?.showTowerInformation() }
        let left=hstack([brand,levelButton,timeLabel,cashLabel,populationLabel],spacing:16)
        populationLabel.toolTip = "Population and happiness affect your next level. Open Tower for milestones."
        left.translatesAutoresizingMaskIntoConstraints=false;header.addSubview(left)
        pauseButton=ActionButton("Pause",symbol:"pause.fill",action:{[weak self] in self?.togglePause()})
        let controls=hstack([pauseButton],spacing:4)
        for value in [1,4,12] {let button=ActionButton("\(value)×",action:{[weak self] in self?.speed=value;self?.updateUI()});speedButtons[value]=button;controls.addArrangedSubview(button)}
        controls.translatesAutoresizingMaskIntoConstraints=false;header.addSubview(controls)
        NSLayoutConstraint.activate([left.leadingAnchor.constraint(equalTo:header.leadingAnchor,constant:12),left.centerYAnchor.constraint(equalTo:header.centerYAnchor),controls.trailingAnchor.constraint(equalTo:header.trailingAnchor,constant:-10),controls.centerYAnchor.constraint(equalTo:header.centerYAnchor),controls.leadingAnchor.constraint(greaterThanOrEqualTo:left.trailingAnchor,constant:12)])
    }
    func mountStack(_ stack:NSStackView,in parent:NSView,padding:CGFloat=10) {
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true
        let document=FlippedView();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
        scroll.translatesAutoresizingMaskIntoConstraints=false;parent.addSubview(scroll);stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:parent.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:parent.trailingAnchor),scroll.topAnchor.constraint(equalTo:parent.topAnchor),scroll.bottomAnchor.constraint(equalTo:parent.bottomAnchor),document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:padding),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-padding),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:padding),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-padding)])
    }
    func setupSidebar(_ sidebar:NSView) {
        ambitionPreview = AmbitionPreviewView { [weak self] in self?.openProgression() }
        ambitionPreview.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(ambitionPreview)
        roomBrowser=RoomBrowserView(atlas:gameView.atlas)
        roomBrowser.onBrowse = { [weak self] _ in self?.choose(nil) }
        roomBrowser.onBuild = { [weak self] kind in
            guard let self else{return}
            if let blocker = kind.definition.buildBlocker(stars: self.game.stars, cash: self.game.cash) {
                self.choose(nil); self.message(blocker)
                return
            }
            self.choose(kind)
            self.view.window?.makeFirstResponder(self.gameView)
        }
        roomBrowser.translatesAutoresizingMaskIntoConstraints=false;sidebar.addSubview(roomBrowser)
        NSLayoutConstraint.activate([
            roomBrowser.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor),roomBrowser.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor),
            ambitionPreview.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor),ambitionPreview.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor),
            ambitionPreview.topAnchor.constraint(equalTo:sidebar.topAnchor),ambitionPreview.heightAnchor.constraint(equalToConstant:64),
            roomBrowser.topAnchor.constraint(equalTo:ambitionPreview.bottomAnchor),roomBrowser.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor)
        ])
    }
    func setupInspector(_ inspector:NSView) {
        detailStack.orientation = .vertical;detailStack.alignment = .leading;detailStack.spacing=10
        mountStack(detailStack,in:inspector,padding:12)
    }
    func rebuildInspector() {
        let visible=selectedRoom != nil || selectedElevator != nil || showingInfo || showingIssues
        inspectorWidth.constant=visible ? (showingInfo ? 280 : 230):0
        detailStack.superview?.superview?.superview?.isHidden = !visible
        for v in detailStack.arrangedSubviews {detailStack.removeArrangedSubview(v);v.removeFromSuperview()}
        guard visible else{return}
        func add(_ v:NSView) {detailStack.addArrangedSubview(v);v.widthAnchor.constraint(equalTo:detailStack.widthAnchor).isActive=true}
        add(ActionButton("Close inspector ×",action:{[weak self] in self?.selectedRoom=nil;self?.selectedElevator=nil;self?.showingInfo=false;self?.showingIssues=false;self?.updateUI(rebuildInspector:true)}))
        if let index=selectedElevator,game.elevators.indices.contains(index) {
            let lift=game.elevators[index]
            add(textLabel("\(lift.kind.title) \(index+1)",size:17,weight:.bold))
            add(textLabel("\(lift.passengers) / \(lift.capacity) passengers\nFloor \(Int(lift.position.rounded())) · \(lift.doorsOpen ? "Doors open":"In service")\nServes \(TowerState.floorLabel(lift.bottom))–\(lift.topFloor)",size:13))
            add(textLabel("Shaft column: \(lift.column.map(String.init) ?? "Legacy center") · \(lift.footprintWidth) cells wide",size:12,color:Theme.muted))
            add(textLabel(lift.kind == .express ? "Express stops: \(lift.stops.map{ TowerState.floorLabel($0) }.joined(separator:", "))\nPassengers transfer to local lifts at these floors.":"Stops at every room floor in this bank. Passes through the Grand Lobby to G. Maximum: 30 served levels.",size:12,color:Theme.muted))
            if let destination=lift.targetFloor {add(textLabel("Next stop: \(TowerState.floorLabel(destination))",size:13,weight:.medium))}
            if lift.kind == .standard {add(ActionButton("Upgrade to wide · $14k",action:{[weak self] in self?.performCommand(.upgradeElevator(lift.id))}))}
            add(ActionButton("Relocate shaft · no charge", symbol:"arrow.left.and.right", action:{[weak self] in self?.chooseRelocation(lift.id)}))
            add(ActionButton("Delete entire shaft…", symbol:"trash", action:{[weak self] in self?.removeElevator(lift.id)}))
            add(textLabel("Relocation checks the full shaft path. Removing a bank may leave rooms without access; affected visitors use another route when available.",size:11,color:Theme.muted))
        } else if let id=selectedRoom,let room=game.rooms.first(where:{$0.id==id}) {
            add(textLabel(room.kind == .lobby ? game.effectiveLobbyStyle.title : room.kind.title,size:18,weight:.bold));add(textLabel("Floor \(TowerState.floorLabel(room.floor)) · Unit \(room.id)",size:12))
            add(textLabel("Width: \(room.kind == .lobby ? game.span(0).width : room.kind.width) grid cells",size:12,color:Theme.muted));add(separator())
            if room.kind == .lobby { addLobbyDetails(add, showHeading: false) }
            if room.kind.hasStyles {
                add(textLabel("Interior style",size:12))
                let picker = NSSegmentedControl(labels: RoomStyle.allCases.map(\.title), trackingMode: .selectOne, target: self, action: #selector(changeRoomStyle(_:)))
                picker.selectedSegment = room.effectiveStyle.rawValue
                picker.setAccessibilityLabel("Room interior style")
                picker.isEnabled = room.incident?.isActive != true
                picker.toolTip = picker.isEnabled ? "Change the interior for free. New rooms avoid matching neighbors." : "Resolve this room’s incident before changing its interior."
                add(picker); add(separator())
            }
            if let incident=room.incident {
                if let signal=game.signal(for:room, coverage:serviceCoverage) {
                    add(textLabel("\(moodGlyph(signal.mood))  \(moodName(signal.mood))\n\(signal.text)",size:13,weight:.medium))
                }
                add(textLabel(incident.title,size:15,weight:.bold))
                if incident.durationMinutes > 0 {
                    let bar=NSProgressIndicator();bar.style = .bar;bar.isIndeterminate=false;bar.minValue=0;bar.maxValue=1;bar.doubleValue=incident.progress;add(bar)
                    add(textLabel("\(formatGameMinutes(incident.remainingMinutes)) remaining",size:12,color:Theme.muted))
                }
                if incident.arrears > 0 {add(textLabel("Rent arrears: $\(Int(incident.arrears).formatted())",size:13,weight:.medium,color:.systemRed))}
                for action in game.incidentActions(for:room) {
                    let title = action == .repair ? "\(action.title) · $\(game.repairCost(for:room).formatted())" : action.title
                    let button=ActionButton(title,action:{[weak self] in self?.performCommand(.respondToIncident(id,action:TowerIncidentAction(action)))})
                    let blocker=game.responseBlocker(for:room,action:action)
                    button.isEnabled = blocker == nil;button.toolTip=blocker;add(button)
                    if let blocker {add(textLabel(blocker,size:11,color:Theme.muted))}
                }
                add(separator())
            } else if let signal=game.signal(for:room, coverage:serviceCoverage) {
                add(textLabel("\(moodGlyph(signal.mood))  \(moodName(signal.mood))\n\(signal.text)",size:13,weight:.medium))
                add(separator())
            }
            addServiceDetails(for: room, add)
            if room.kind.capacity>0 {
                add(textLabel("\(room.people) / \(room.kind.capacity) occupants\nHappiness: \(Int(room.happiness*100))%\nRent: \(Int(room.rent*100))% of market",size:13))
                let slider=NSSlider(value:room.rent,minValue:0.6,maxValue:1.6,target:self,action:#selector(changeRent(_:)));slider.numberOfTickMarks=11;slider.allowsTickMarkValuesOnly=true;slider.isContinuous=false;slider.setAccessibilityLabel("Room rent");add(slider)
                if room.kind.isApartment {
                    add(separator());add(textLabel("Leasing requirements",size:14,weight:.bold))
                    add(textLabel("Background checks",size:12))
                    let screening=NSPopUpButton(frame:.zero,pullsDown:false)
                    screening.addItems(withTitles:TenantScreening.allCases.map(\.title))
                    screening.selectItem(at:TenantScreening.allCases.firstIndex(of:room.screeningPolicy) ?? 0)
                    screening.target=self;screening.action=#selector(changeScreening(_:))
                    screening.setAccessibilityLabel("Apartment background checks");add(screening)
                    add(textLabel("Deposit requirement",size:12))
                    let deposit=NSPopUpButton(frame:.zero,pullsDown:false)
                    deposit.addItems(withTitles:ApartmentDeposit.allCases.map(\.title))
                    deposit.selectItem(at:ApartmentDeposit.allCases.firstIndex(of:room.depositPolicy) ?? 0)
                    deposit.target=self;deposit.action=#selector(changeDeposit(_:))
                    deposit.setAccessibilityLabel("Apartment deposit requirement");add(deposit)
                    let pace=Int((room.applicantMoveInMultiplier*100).rounded())
                    let reduction=Int(((1-room.newTenantDefaultRisk)*100).rounded())
                    add(textLabel("Move-in pace: \(pace)% of normal\nNew-tenant default risk: \(reduction == 0 ? "normal":"\(reduction)% lower")",size:12))
                    if room.occupancy > 0 {
                        add(textLabel("Current tenant risk: \(Int((room.effectiveDefaultRisk*100).rounded()))% of normal",size:12,color:Theme.muted))
                    }
                    add(textLabel("Applies to incoming tenants. Stricter requirements take longer to fill vacancies. Deposits are not rental income.",size:11,color:Theme.muted))
                    add(separator())
                }
                if room.incident?.isActive != true || room.incident?.kind == .rentArrears {
                    add(ActionButton("Follow a visitor",action:{[weak self] in self?.performCommand(.requestTrip(roomID:id,from:0,to:room.floor));self?.message("A visitor is walking from the lobby to this room.")}))
                }
            }
            if game.signal(for:room, coverage:serviceCoverage) == nil {add(textLabel("Connected to the lobby.",size:12,color:Theme.muted))}
            if room.kind != .lobby && room.incident?.isActive != true {add(ActionButton("Delete room…",symbol:"trash",action:{[weak self] in self?.requestDemolition(.room(id))}))}
        } else if showingIssues {
            add(textLabel("Room issues",size:18,weight:.bold))
            let issues=game.rooms.compactMap { room -> (Room,RoomSignal)? in game.signal(for:room, coverage:serviceCoverage).map { (room,$0) } }
            if issues.isEmpty {add(textLabel("No rooms need attention.",size:13,color:Theme.muted))}
            addServiceSummary(add, shortagesOnly: true)
            for (room,signal) in issues where signal.text != game.serviceWarning(for: room, coverage: serviceCoverage)?.text {
                add(ActionButton("Floor \(TowerState.floorLabel(room.floor)) · \(room.kind.title)\n\(signal.text)",symbol:signal.symbol,action:{[weak self] in self?.revealRoom(room.id)}))
            }
        } else {add(textLabel("Tower information",size:18,weight:.bold))}
        if showingInfo {
        addServiceSummary(add, shortagesOnly: false)
        add(separator())
        addLevelDetails(add)
        add(separator()); addLobbyDetails(add)
        add(separator());add(textLabel("\(game.topFloor+1) floors + \(game.basementDepth) basements · \(game.rightEdge-game.leftEdge) cells wide\n\(game.rooms.count-1) rooms\n\(game.queueCount) waiting for lifts\n\(game.completedTrips) completed trips",size:13))
        add(textLabel(TowerState.buildingLimitsDescription,size:11,color:Theme.muted))
        add(textLabel("Daily income: $\(game.projectedIncome.formatted())\nDaily costs: $\(game.projectedExpenses.formatted())",size:12))
        add(separator());add(textLabel(game.nextGoal,size:12))
        for event in game.events.prefix(2) {add(textLabel(event,size:11,color:Theme.muted))}
        add(ActionButton("Open tower…",action:{[weak self] in self?.openSave()}));add(ActionButton("How to play",action:{[weak self] in self?.showHelp()}))
        }
    }
    func moodName(_ mood:RoomMood)->String {mood.rawValue.capitalized}
    func moodGlyph(_ mood:RoomMood)->String {
        switch mood {case .angry:return "😠";case .annoyed:return "😒";case .worried:return "😟";case .alarmed:return "😱";case .sad:return "😢";case .relieved:return "😌";case .busy:return "😤"}
    }
    func formatGameMinutes(_ minutes:Int)->String {
        if minutes >= 1440 {let days=minutes/1440,hours=(minutes%1440)/60;return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"}
        if minutes >= 60 {return "\(minutes/60)h \(minutes%60)m"}
        return "\(minutes)m"
    }
    func showRoomIssues() {if focusMode { setFocusMode(false) };selectedRoom=nil;selectedElevator=nil;showingInfo=false;showingIssues=true;updateUI(rebuildInspector:true)}
    func showTowerInformation() {if focusMode { setFocusMode(false) };selectedRoom=nil;selectedElevator=nil;showingIssues=false;showingInfo.toggle();updateUI(rebuildInspector:true)}
    func revealRoom(_ id:Int) {
        guard let room=game.rooms.first(where:{$0.id==id}) else{return}
        showingIssues=false;showingInfo=false;selectedElevator=nil;selectedRoom=id
        let rect=gameView.roomRect(room),screenCenter=CGPoint(x:gameView.origin.x+rect.midX*gameView.scale,y:gameView.origin.y+rect.midY*gameView.scale)
        gameView.pan.x += gameView.bounds.midX-screenCenter.x;gameView.pan.y += gameView.bounds.midY-screenCenter.y
        updateUI(rebuildInspector:true)
    }
    func chooseFloor() {choose(nil);floorMode=true;updateUI();message("Drag horizontally to build or widen a floor. Widen the ground lobby first. $150 per cell.")}
    func chooseElevator(_ kind:ElevatorKind) {choose(nil);elevatorTool=kind;updateUI();message("\(kind.title): \(kind.capacity) people. Drag where the shaft belongs across its service floors. Demolish blocking rooms first.")}
    func chooseRelocation(_ id:Int) {
        guard let lift=game.elevators.first(where:{$0.id==id}) else{return}
        choose(nil); movingElevatorID=id; elevatorTool=lift.kind;updateUI()
        message("Relocate elevator \(id): drag its new shaft path and service floors. No charge. Esc cancels.")
    }
    func removeElevator(_ id:Int) {
        requestDemolition(.elevator(id))
    }
    func inspectElevator(_ index:Int) {selectedRoom=nil;selectedElevator=index;updateUI(rebuildInspector:true)}
    func dragged(fromFloor:Int,fromSlot:Int,toFloor:Int,toSlot:Int) {
        if floorMode {performCommand(.constructFloor(floor:fromFloor,from:fromSlot,to:toSlot))}
        else if let kind=elevatorTool {
            let range=elevatorRange(from:fromFloor,to:toFloor)
            if let id=movingElevatorID {
                if performCommand(.relocateElevator(id,column:fromSlot,from:range.bottom,to:range.top)) {
                    choose(nil);selectedElevator=game.elevators.firstIndex(where:{$0.id==id});updateUI(rebuildInspector:true)
                    message("Elevator relocated. Visitors have been rerouted.")
                }
            } else {performCommand(.addElevator(kind,column:fromSlot,from:range.bottom,to:range.top))}
        } else if let kind=selectedKind {performCommand(.buildRow(kind,floor:fromFloor,from:fromSlot,to:toSlot))}
        else {clicked(floor:toFloor,slot:toSlot)}
    }
    func elevatorRange(from:Int,to:Int)->(bottom:Int,top:Int) {
        from == to ? (min(0,to),to < 0 ? 0 : max(1,to)) : (min(from,to),max(from,to))
    }
    @objc func changeRoomStyle(_ sender: NSSegmentedControl) {
        guard let id = selectedRoom, let style = RoomStyle(rawValue: sender.selectedSegment) else { return }
        performCommand(.setRoomStyle(id,style:style))
    }
    @objc func changeScreening(_ sender:NSPopUpButton) {
        guard TenantScreening.allCases.indices.contains(sender.indexOfSelectedItem),let id=selectedRoom,
              let room=game.rooms.first(where:{$0.id==id}) else{return}
        let screening=TenantScreening.allCases[sender.indexOfSelectedItem]
        performCommand(.setApartmentPolicy(id,screening:screening,deposit:room.depositPolicy))
    }
    @objc func changeDeposit(_ sender:NSPopUpButton) {
        guard ApartmentDeposit.allCases.indices.contains(sender.indexOfSelectedItem),let id=selectedRoom,
              let room=game.rooms.first(where:{$0.id==id}) else{return}
        let deposit=ApartmentDeposit.allCases[sender.indexOfSelectedItem]
        performCommand(.setApartmentPolicy(id,screening:room.screeningPolicy,deposit:deposit))
    }
    @objc func changeRent(_ sender: NSSlider) { if let id = selectedRoom { _ = performCommand(.setRent(id,value:sender.doubleValue)) } }
    func choose(_ kind: RoomKind?) { if focusMode { setFocusMode(false) }; selectedKind = kind; selectedRoom = nil; selectedElevator = nil; movingElevatorID = nil; floorMode = false; elevatorTool = nil; demolition = false; showingInfo=false;showingIssues=false; message(kind.map { "\($0.title): \($0.width) cells · $\($0.cost.formatted()) · Click or drag a row" } ?? normalStatus); updateUI(rebuildInspector:true) }
    func togglePause() { speed = speed == 0 ? 1 : 0; updateUI() }
    @discardableResult func performCommand(_ command: TowerCommand) -> Bool {
        do { try session.execute(command); didModify = true; updateUI(rebuildInspector:true); return true }
        catch { message(error.localizedDescription); return false }
    }
    @discardableResult func perform(_ action: (inout TowerState) throws -> Void) -> Bool {
        do { try action(&game); game.evaluateAmbitions(); didModify = true; updateUI(rebuildInspector:true); return true }
        catch { message(error.localizedDescription); return false }
    }
    func clicked(floor:Int,slot:Int) {
        if demolition {
            if let room = game.room(at:floor,slot:slot) { requestDemolition(.room(room.id)) }
            else { message("Select an occupied room to demolish.") }
        } else if let kind = selectedKind { performCommand(.build(kind,floor:floor,slot:slot)) }
        else { selectedElevator = nil; selectedRoom = game.room(at:floor,slot:slot)?.id; updateUI(rebuildInspector:true) }
    }
    func frame() {
        let now=ProcessInfo.processInfo.systemUptime
        let elapsed=max(0,now-lastFrameTime);lastFrameTime=now
        guard titleScreen == nil, pendingDemolitionAlert == nil else { return }
        frameCount += 1
        gameView.cloudSeconds += elapsed
        gameView.spriteClock.advance(seconds:elapsed,isRunning:speed>0)
        gameView.travelerMotion.advance(seconds:elapsed,isRunning:speed>0)
        if frameCount % 3 == 0 && speed > 0 {
            let oldLevel = game.stars
            session.tick(); didModify = true
            if game.stars > oldLevel { celebrateLevelUp(); updateUI(rebuildInspector: true) }
        }
        gameView.synchronizeTravelerMotion(game)
        if frameCount % 15 == 0 {
            let selectedHasIncident=selectedRoom.flatMap{id in game.rooms.first(where:{$0.id==id})?.incident} != nil
            let rentIsActive=view.window?.firstResponder is NSSlider
            updateUI(rebuildInspector:(selectedHasIncident && !rentIsActive) || frameCount % 120 == 0)
        }
        gameView.needsDisplay = true
        if frameCount % 1800 == 0 && didModify { autosave() }
    }
    func updateUI(rebuildInspector: Bool = false) {
        serviceCoverage = game.neighborhoodCoverage
        cashLabel.stringValue = "$\(game.cash.formatted())"
        cashLabel.textColor = game.cash < 0 ? .systemRed : Theme.ink
        populationLabel.stringValue = "\(game.population.formatted()) people"
        timeLabel.stringValue = "Day \(game.day)  \(game.clock)"
        levelButton?.title = "Level \(game.level.number)"
        levelButton?.toolTip = "\(game.level.title) · \(game.nextGoal)"
        ambitionPreview?.update(game)
        populationLabel.toolTip = "\(Int(game.happiness * 100))% happiness · \(game.nextGoal)"
        focusPauseButton?.title = speed == 0 ? "Play" : "Pause"
        focusPauseButton?.image = NSImage(systemSymbolName:speed == 0 ? "play.fill" : "pause.fill",accessibilityDescription:nil)
        pauseButton.title = speed == 0 ? "Play" : "Pause"
        pauseButton.image = NSImage(systemSymbolName:speed == 0 ? "play.fill" : "pause.fill",accessibilityDescription:nil)
        for (value,b) in speedButtons { b.contentTintColor = Theme.ink; b.state = speed == value ? .on : .off }
        roomBrowser?.update(stars:game.stars,cash:game.cash,building:selectedKind)
        refreshToolStrip()
        if Date.timeIntervalSinceReferenceDate > bannerUntil {
            if let kind=selectedKind {statusLabel.stringValue="\(kind.title) · \(kind.width) cells wide · Click or drag to build"}
            else if floorMode {statusLabel.stringValue="Floor tool · Drag horizontally to extend · Widen the floor below first · $150/cell"}
            else if let id=movingElevatorID {statusLabel.stringValue="Relocate elevator \(id) · Drag a clear shaft path · No charge · Esc cancels"}
            else if let kind=elevatorTool {statusLabel.stringValue="\(kind.title) · \(kind.capacity) people · Drag where the shaft belongs · Demolish blocking rooms first"}
            else if demolition {statusLabel.stringValue="Delete · Click a room or shaft to review removal · Confirm for a 50% refund · Esc cancels"}
            else {statusLabel.stringValue=normalStatus}
        }
        if rebuildInspector { self.rebuildInspector() }
        gameView.needsDisplay = true
    }
    func message(_ text:String) { statusLabel.stringValue = text; bannerUntil = Date.timeIntervalSinceReferenceDate + 6 }
    var autosaveURL: URL {
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        return base.appendingPathComponent("LoftyAmbitions/Autosave.loftyambitions")
    }
    var saveStore: TowerSaveStore { TowerSaveStore(recoveryDirectory: autosaveURL.deletingLastPathComponent().appendingPathComponent("Recovery")) }
    func writeSave(to url:URL) throws { try saveStore.write(game,to:url) }
    func autosave() {
        guard titleScreen == nil else { return }
        guard !autosaveBlocked,!CommandLine.arguments.contains("--incident-demo"),!CommandLine.arguments.contains("--exit-after-screenshot") else{return}
        do { try writeSave(to:autosaveURL) }
        catch { message("Autosave failed: \(error.localizedDescription)") }
    }
    func restoreAutosave() {
        guard FileManager.default.fileExists(atPath:autosaveURL.path) else { return }
        do { game = try saveStore.read(autosaveURL); gameView.travelerMotion.reset(); updateUI(rebuildInspector:true); message("Restored your autosaved tower.") }
        catch {
            // Preserve unreadable input before the next autosave can replace it.
            do {
                try FileManager.default.createDirectory(at:saveStore.recoveryDirectory,withIntermediateDirectories:true)
                let backup=saveStore.recoveryDirectory.appendingPathComponent("Unreadable-\(UUID().uuidString).loftyambitions")
                try FileManager.default.copyItem(at:autosaveURL,to:backup)
                message("Could not restore autosave. Original preserved in Recovery: \(error.localizedDescription)")
            } catch { autosaveBlocked=true;message("Autosave disabled to preserve the unreadable original. Use Save Tower to save elsewhere. \(error.localizedDescription)") }
        }
    }
    @discardableResult func save() -> Bool {
        if let url = savedURL {
            do { try writeSave(to:url); didModify = false; message("Tower saved."); return true }
            catch { message(error.localizedDescription); return false }
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Lofty Ambitions.loftyambitions"; panel.allowedContentTypes = [.json]; panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url=panel.url else{return false}
        do { try writeSave(to:url); savedURL = url; didModify = false; message("Tower saved.");return true }
        catch { message(error.localizedDescription);return false }
    }
    func confirmSaveBeforeSwitch(_ action:String) -> Bool {
        guard didModify else{return true}
        let alert=NSAlert();alert.messageText="Save changes before \(action)?"
        alert.informativeText="Save to your tower file, or keep a separate recovery copy. Recovery copies are available from File → Recover a Tower."
        alert.addButton(withTitle:"Save Changes");alert.addButton(withTitle:"Cancel");alert.addButton(withTitle:"Keep Recovery Copy")
        switch alert.runModal() {
        case .alertFirstButtonReturn:return save()
        case .alertThirdButtonReturn:return true
        default:return false
        }
    }
    func resetSelection() {
        selectedRoom=nil;selectedKind=nil;selectedElevator=nil;movingElevatorID=nil
        floorMode=false;elevatorTool=nil;demolition=false;showingInfo=false;showingIssues=false
        celebration?.dismissImmediately(); celebration=nil
        gameView.startCell=nil;gameView.startDrag=nil;gameView.hovered=nil;gameView.hoveredSignal=nil
        gameView.travelerMotion.reset()
    }
    func openSave(recovery:Bool=false) {
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        if recovery {panel.directoryURL=saveStore.recoveryDirectory;panel.title="Recover a Tower"}
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            _ = try saveStore.read(url)
            guard confirmSaveBeforeSwitch("opening another tower") else{return}
            let result=try saveStore.switching(from:game,to:url)
            game=result.game
            // Recovery snapshots and imported saves keep their originals intact.
            let needsNewFile = recovery || TowerSavePolicy.requiresSaveAs(url,store:saveStore)
            savedURL=needsNewFile ? nil:url;didModify=needsNewFile
            resetSelection();gameView.fitTower();updateUI(rebuildInspector:true)
            message("Tower opened. Previous tower preserved in File → Recover a Tower.")
        } catch {message("Could not open tower: \(error.localizedDescription)")}
    }
    func newGame() {
        guard confirmSaveBeforeSwitch("starting a new tower") else{return}
        do {
            try saveStore.preserve(game)
            game = .newGame(); savedURL=nil;resetSelection();speed=1;didModify=true
            gameView.fitTower();updateUI(rebuildInspector:true)
            message("New tower started. Previous tower preserved in File → Recover a Tower.")
        } catch {message("Could not preserve the current tower: \(error.localizedDescription)")}
    }
    func showHelp() {
        let alert = NSAlert(); alert.messageText = "Make room for a whole city."
        alert.informativeText = "BUILDING\nBrowse or search Rooms in the sidebar, click a room to select it for placement and see its details. Click or drag across a floor to place a row. Locked rooms explain their level requirement. Rooms occupy different numbers of 8-pixel cells.\n\nUse Build → Draw or extend a floor in the top toolbar and drag horizontally to create or widen a floor. Widen the ground lobby first, then work upwards. Build → Widen left/right extends every floor by 8 cells.\n\nELEVATORS\nSelect a lift type and drag where the shaft belongs between its bottom and top floors. Standard shafts use 3 cells; wide and express shafts use 5. Demolish blocking rooms first: the entire shaft path must be clear. Click a floor to serve G through that floor. Inspect a shaft to relocate it for free or remove it for a 50% refund. The bulldozer can also remove shafts. Standard cars carry 12 people and wide cars carry 24; both span 30 floors. Express cars carry 32 and serve G, 15, 30, 45, and so on. Add local banks from those transfer floors to reach upper rooms.\n\nROOM INCIDENTS\nPersistent speech bubbles show rooms that need attention. Click a bubble or use Issues in the top toolbar to find one, then respond in its inspector. Hotel parties eventually need nearby housekeeping. Apartment arrears proceed through notice, court, and eviction. Set apartment background checks and deposits in the inspector: stricter requirements slow move-ins but lower incoming tenants’ default risk. Fires require an FD response followed by paid repairs. Timed responses advance in game time and pause with the tower.\n\nPeople walk, queue, board when doors open, ride to their stop, and walk to their destination. Inspect a car to see its passengers or upgrade it.\n\nSpace: pause · 1 / 2 / 3: speed · I / Esc: inspect · X: delete · ⇧⌘R: search rooms · Tab / ⇧⌘F: Focus mode\nOption-drag or scroll: pan · Pinch / ⌘-scroll / + / −: zoom at cursor · F: fit\n⌘S: save · ⌘O: open · ⌘N: new tower\n\nAccounts settle at midnight. Autosaves run every minute and on quit. Opening or starting a tower preserves the previous one under File → Recover a Tower.\n\n\(TowerState.buildingLimitsDescription)"

        alert.addButton(withTitle:"Let’s build"); alert.runModal()
    }
}
