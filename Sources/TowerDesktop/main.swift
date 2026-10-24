import Foundation
#if os(Windows)
import ucrt
#endif
import TowerCore
import TowerSession
import TowerArt
import TowerPresentation
import TowerDesktopModel
import CDesktop

struct Box {
    var x:Double;var y:Double;var w:Double;var h:Double
    func contains(_ px:Double,_ py:Double)->Bool {px>=x && px<x+w && py>=y && py<y+h}
}
struct ClickAction {let box:Box;let label:String;let enabled:Bool;let action:()->Void}

/// SDL is only the OS/drawing adapter; all mutation and scene generation are shared Swift.
final class DesktopGame {
    let desktop:OpaquePointer
    let session=TowerSession()
    let interaction:DesktopInteraction
    let scene:TowerScene
    let atlas:TowerAtlas
    let root=TowerResources.url
    let sheetPaths:[String:String]
    let titlePath:String
    let dataURL:URL
    let store:TowerSaveStore
    let smoke:Bool
    var running=true,title=true,focus=false,searching=false
    var actions:[ClickAction]=[];var keyboardFocus:Int?
    var query="",category:Int=0,catalogScroll=0.0,inspectorScroll=0.0
    var panel="",status="Build your neighborhood in the sky."
    var width=1440.0,height=940.0,mouseX=0.0,mouseY=0.0
    var startPoint:(Double,Double)?,startCell:(floor:Int,slot:Int)?,panning=false,moved=false
    var ambient=0.0
    var elapsed=0.0,lastTick=0.0,lastAuto=0.0,modalTitle="",modalBody=""
    var modalAccept:(()->Void)?,modalCancel:(()->Void)?
    var dialogPurpose="",dialogPreviousSpeed=0
    var restoreSpeed=0,celebrationUntil=0.0,celebrationText=""
    var smokeDirectory:URL?
    var assetMisses=Set<String>()
    var signalRevision:UInt64?
    var inputClip:Box?
    var autosaveBlocked=false
    var modalFocus=DesktopModalFocus()
    var displayedDemolition:TowerDemolitionTarget?
    var uiScale=DesktopUIScale()
    var effectiveUIScale=1.0

    init() throws {
        smoke=CommandLine.arguments.contains("--smoke") || CommandLine.arguments.contains("--performance-smoke")
        if let i=CommandLine.arguments.firstIndex(of:"--smoke-output"),CommandLine.arguments.count>i+1 {
            smokeDirectory=URL(fileURLWithPath:CommandLine.arguments[i+1],isDirectory:true)
        }
        dataURL=smoke ? (smokeDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("LoftyDesktop-Smoke-\(UUID().uuidString)",isDirectory:true)) : DesktopPaths.applicationData()
        store=TowerSaveStore(recoveryDirectory:dataURL.appendingPathComponent("Recovery",isDirectory:true))
        interaction=DesktopInteraction(session:session)
        atlas=try TowerAtlas()
        // Foundation may query the Windows filesystem when constructing URLs.
        // Resolve each sheet once, never once per sprite in the draw loop.
        sheetPaths=Dictionary(uniqueKeysWithValues:Set(atlas.frames.values.map(\.sheet)).map {
            ($0,TowerResources.url.appendingPathComponent("Sheets/\($0)",isDirectory:false).path)
        })
        titlePath=TowerResources.url.appendingPathComponent("TitleScreen.png",isDirectory:false).path
        scene=TowerScene(atlas:atlas)
        guard let d=lt_create("Lofty Ambitions",1440,940) else {throw TowerError(String(cString:lt_error()))}
        desktop=d
        if !smoke,let data=try? Data(contentsOf:dataURL.appendingPathComponent("Interface.json")),let saved=try? JSONDecoder().decode(DesktopUIScale.self,from:data) {uiScale=saved}
        refreshUIScale(preserveZoom:false)
        if !smoke,FileManager.default.fileExists(atPath:autosaveURL.path) {
            do {session.game=try store.read(autosaveURL)} catch {
                do {
                    try FileManager.default.createDirectory(at:store.recoveryDirectory,withIntermediateDirectories:true)
                    let backup=store.recoveryDirectory.appendingPathComponent("Unreadable-\(UUID().uuidString).loftyambitions")
                    try FileManager.default.copyItem(at:autosaveURL,to:backup)
                    status="Unreadable autosave preserved in Recovery. \(error.localizedDescription)"
                } catch {autosaveBlocked=true;status="Autosave disabled to preserve its unreadable original. Save your tower elsewhere."}
            }
        }
        session.speed=0
        scene.fit(game:session.game,width:canvas.w,height:canvas.h)
    }
    deinit {lt_destroy(desktop)}
    var autosaveURL:URL {dataURL.appendingPathComponent("Autosave.loftyambitions")}
    var uiScaleTitle:String {"UI: \(uiScale.requested==0 ? "Auto ":"")\(Int((effectiveUIScale*100).rounded()))%"}
    func refreshUIScale(preserveZoom:Bool=true) {
        var rawWidth:Int32=0,rawHeight:Int32=0
        lt_window_size(desktop,&rawWidth,&rawHeight)
        let next=uiScale.factor(width:Double(rawWidth),height:Double(rawHeight),contentScale:Double(lt_content_scale(desktop)))
        if preserveZoom,next != effectiveUIScale {
            scene.scale=max(0.25,min(16,scene.scale*effectiveUIScale/next))
            startCell=nil;startPoint=nil;panning=false;keyboardFocus=nil
        }
        effectiveUIScale=next;lt_set_ui_scale(desktop,Float(next))
        var w:Int32=0,h:Int32=0;lt_size(desktop,&w,&h);width=Double(w);height=Double(h)
    }
    func cycleUIScale() {
        uiScale.cycle();refreshUIScale()
        status="Interface size: \(Int(effectiveUIScale*100))%. Auto follows your display and window size."
        guard !smoke else{return}
        do {
            try FileManager.default.createDirectory(at:dataURL,withIntermediateDirectories:true)
            try JSONEncoder().encode(uiScale).write(to:dataURL.appendingPathComponent("Interface.json"),options:.atomic)
        } catch {status="Interface size changed, but the preference could not be saved: \(error.localizedDescription)"}
    }
    var canvas:Box {
        if focus {return Box(x:0,y:0,w:width,h:height)}
        let side=(panel.isEmpty && interaction.selectedRoom == nil && interaction.selectedElevator == nil) ? 0.0 : 310.0
        return Box(x:268,y:84,w:width-268-side,h:height-112)
    }
    func execute(_ command:TowerCommand) {
        let old=session.game.stars
        do {try session.execute(command);status=interaction.tool.title
            if session.game.stars>old {celebrate("Level \(session.game.stars) · \(session.game.level.title)")}
        } catch {status=error.localizedDescription}
    }
    func celebrate(_ text:String) {celebrationText=text;celebrationUntil=elapsed+4}
    func text(_ value:String,_ x:Double,_ y:Double,_ size:Double=13,_ color:UInt32=0x253D4AFF,_ bold:Bool=false) {
        lt_text(desktop,value,Float(x),Float(y),Float(size),color,bold ? 1:0)
    }
    func rect(_ b:Box,_ color:UInt32) {lt_rect(desktop,Float(b.x),Float(b.y),Float(b.w),Float(b.h),color)}
    func button(_ label:String,_ b:Box,enabled:Bool=true,active:Bool=false,action:@escaping()->Void) {
        let hovered=b.contains(mouseX,mouseY)
        let idx=actions.count
        var hitBox=b
        if let clip=inputClip {
            hitBox=Box(x:max(b.x,clip.x),y:max(b.y,clip.y),w:max(0,min(b.x+b.w,clip.x+clip.w)-max(b.x,clip.x)),h:max(0,min(b.y+b.h,clip.y+clip.h)-max(b.y,clip.y)))
        }
        actions.append(ClickAction(box:hitBox,label:label,enabled:enabled && hitBox.w>0 && hitBox.h>0,action:action))
        rect(b,active ? 0x276A68FF : enabled ? (hovered ? 0xCCDADCFF:0xDFE6E8FF):0xEBEDEEFF)
        text(label,b.x+9,b.y+7,12,active ? 0xFFFFFFFF : enabled ? 0x263D48FF:0x819096FF,true)
        if keyboardFocus==idx {
            lt_line(desktop,Float(b.x),Float(b.y+b.h-2),Float(b.x+b.w),Float(b.y+b.h-2),0x276A68FF)
        }
    }
    func choose(_ tool:DesktopTool) {interaction.tool=tool;interaction.selectedRoom=nil;interaction.selectedElevator=nil;panel="";status=tool.title;searching=false}
    func drawScene() {
        // Fill a newly exposed sky over several frames so resize/zoom keeps
        // pumping events. The GPU cache owns pixels after their first upload.
        var cloudUploads=0
        if signalRevision != session.revision {scene.signalCoverage=session.game.neighborhoodCoverage;signalRevision=session.revision}
        scene.showsSignals = !focus
        scene.ambientElapsed=ambient
        scene.coverageRoomID=interaction.selectedRoom
        scene.coverageGuides=[]
        if case .room(let kind)=interaction.tool, let first=startCell,kind.neighborhoodService==scene.coverage {scene.coverageGuides=[SceneCoverageGuide(kind:kind,floor:first.floor,slot:first.slot)]}
        let b=canvas
        lt_clip(desktop,Float(b.x),Float(b.y),Float(b.w),Float(b.h))
        for command in scene.render(game:session.game,width:b.w,height:b.h,elapsed:elapsed) {
            switch command {
            case .fill(let r,let color):lt_rect(desktop,Float(r.x+b.x),Float(r.y+b.y),Float(r.width),Float(r.height),color)
            case .line(let x1,let y1,let x2,let y2,let color):lt_line(desktop,Float(x1+b.x),Float(y1+b.y),Float(x2+b.x),Float(y2+b.y),color)
            case .text(let s,let x,let y,let size,let color):text(s,x+b.x,y+b.y,size,color)
            case .clip(let r):
                if let r {let x=max(b.x,r.x+b.x),y=max(b.y,r.y+b.y);lt_clip(desktop,Float(x),Float(y),Float(max(0,min(b.x+b.w,r.x+b.x+r.width)-x)),Float(max(0,min(b.y+b.h,r.y+b.y+r.height)-y)))}
                else {lt_clip(desktop,Float(b.x),Float(b.y),Float(b.w),Float(b.h))}
            case .image(let key,let source,let destination,let flipped,let opacity):
                let alpha=UInt8(max(0,min(255,Int(opacity*255))))
                if let frame=atlas.frames[key] {
                    let src=source ?? SceneRect(x:0,y:0,width:Double(frame.rect[2]),height:Double(frame.rect[3]))
                    lt_image(desktop,sheetPaths[frame.sheet]!,Float(Double(frame.rect[0])+src.x),Float(Double(frame.rect[1])+src.y),Float(src.width),Float(src.height),Float(destination.x+b.x),Float(destination.y+b.y),Float(destination.width),Float(destination.height),flipped ? 1:0,alpha)
                } else if key.hasPrefix("cloud."),let seed=UInt64(key.dropFirst(6)) {
                    if lt_cached_pixels(desktop,key,Float(destination.x+b.x),Float(destination.y+b.y),Float(destination.width),Float(destination.height),alpha) {continue}
                    guard cloudUploads<2 else {continue}
                    cloudUploads+=1
                    let pixels=CloudTexture.pixels(seed:seed)
                    pixels.rgba.withUnsafeBufferPointer { p in
                        lt_pixels(desktop,key,p.baseAddress,Int32(pixels.width),Int32(pixels.height),Float(destination.x+b.x),Float(destination.y+b.y),Float(destination.width),Float(destination.height),alpha)
                    }
                } else {assetMisses.insert(key)}
            }
        }
        // Selection and construction preview use the same shared camera and room geometry.
        if let id=interaction.selectedRoom,let room=session.game.rooms.first(where:{$0.id==id}) {
            let r=scene.roomRect(room,game:session.game,width:b.w,height:b.h)
            rect(Box(x:b.x+r.x,y:b.y+r.y,w:r.width,h:2),0xFF765BFF)
            rect(Box(x:b.x+r.x,y:b.y+r.y,w:2,h:r.height),0xFF765BFF)
        }
        if !focus,let cell=scene.hit(x:mouseX-b.x,y:mouseY-b.y,game:session.game,width:b.w,height:b.h),b.contains(mouseX,mouseY) {
            let first=startCell ?? cell
            var preview:RoomKind?
            if case .room(let kind)=interaction.tool {preview=kind}
            if let kind=preview {
                let valid=(try? session.game.validateBuild(kind,floor:first.floor,slot:cell.slot)) != nil
                // Reuse roomRect with a temporary representative room only for geometry.
                var template=session.game.rooms[0];template.kind=kind;template.floor=first.floor;template.slot=cell.slot
                let r=scene.roomRect(template,game:session.game,width:b.w,height:b.h)
                rect(Box(x:b.x+r.x,y:b.y+r.y,w:r.width,h:r.height),valid ? 0x73C7A777:0xED6D6D88)
            }
        }
        lt_clip(desktop,0,0,-1,-1)
    }
    func draw() {
        actions=[]
        lt_begin(desktop,0xEAF0F2FF)
        if title {drawTitle();drawModal();return}
        drawScene()
        if focus {
            button("Exit focus  [Tab]",Box(x:width-175,y:12,w:160,h:32)){self.focus=false}
            button(session.speed==0 ? "Resume":"Pause",Box(x:width-267,y:12,w:82,h:32)){self.session.togglePause()}
        } else {
            drawHeader();drawCatalog();drawInspector()
            rect(Box(x:0,y:height-28,w:width,h:28),0xD8E3E7FF)
            let hint=actions.last(where:{$0.box.contains(mouseX,mouseY)})?.label ?? scene.roomSignals.first(where:{Box(x:$0.rect.x+canvas.x,y:$0.rect.y+canvas.y,w:$0.rect.width,h:$0.rect.height).contains(mouseX,mouseY)})?.text
            text(hint ?? status,12,height-21,12)
        }
        if elapsed<celebrationUntil {
            rect(Box(x:width/2-280,y:105,w:560,h:72),0x235E5DF2)
            text(celebrationText,width/2-260,124,20,0xFFF2D4FF,true)
            if !scene.reducedMotion {for i in 0..<28 {rect(Box(x:width/2-270+Double(i*19),y:100+Double((i*13)%64),w:4,h:4),i%2==0 ? 0xFFD98AFF:0xF48677FF)}}
        }
        drawModal()
    }
    func drawTitle() {
        lt_image(desktop,titlePath,0,0,0,0,0,0,Float(width),Float(height),0,255)
        rect(Box(x:width/2-240,y:height-138,w:480,h:108),0x152A3BEA)
        text("Build your neighborhood in the sky.",width/2-217,height-123,17,0xFFF2D4FF,true)
        button("Enter Tower  [Enter]",Box(x:width/2-130,y:height-86,w:260,h:38)){self.title=false;self.session.speed=1}
    }
    func drawHeader() {
        rect(Box(x:0,y:0,w:width,h:84),0xE1E9EDFF)
        text("Lofty Ambitions",12,14,17,0x213746FF,true)
        button("Level \(session.game.stars)",Box(x:188,y:8,w:80,h:30)){self.showPanel("tower")}
        text("Day \(session.game.day)  \(session.game.clock)    $\(session.game.cash.formatted())    \(session.game.population) people",284,16,13)
        var x=width-348
        for value in [1,4,12] {button("\(value)×",Box(x:x,y:8,w:45,h:30),active:session.speed==value){self.session.speed=value};x+=49}
        button(session.speed==0 ? "Resume":"Pause",Box(x:x,y:8,w:76,h:30)){self.session.togglePause()}
        button("Focus",Box(x:width-110,y:8,w:94,h:30)){self.focus=true}
        let controls:[(String,Double,()->Void)]=[
            ("Inspect",69,{self.choose(.inspect)}),("Delete",63,{self.choose(.delete)}),("Build…",67,{self.showPanel("build")}),
            ("Issues",62,{self.showPanel("issues")}),("Tower",62,{self.showPanel("tower")}),
            (scene.coverage.map{"\($0.title) coverage"} ?? "Coverage: off",126,{self.scene.coverage=self.scene.coverage == nil ? .food:self.scene.coverage == .food ? .shops:nil}),
            ("Save",58,{self.save()}),("Open",58,{self.safeSwitch{self.openDialog("open")}}),("New",54,{self.safeSwitch{self.newTower()}}),
            ("Fit",44,{self.scene.fit(game:self.session.game,width:self.canvas.w,height:self.canvas.h)}),
            ("−",30,{self.zoom(0.8)}),("+",30,{self.zoom(1.25)}),("Help",50,{self.showPanel("help")}),
            (uiScaleTitle,118,{self.cycleUIScale()})]
        x=10
        for (label,w,action) in controls {button(label,Box(x:x,y:48,w:w,h:29),action:action);x+=w+5}
    }
    func showPanel(_ name:String) {panel=name;interaction.selectedRoom=nil;interaction.selectedElevator=nil;inspectorScroll=0;searching=false}
    func drawCatalog() {
        rect(Box(x:0,y:84,w:268,h:height-112),0xF5F7F8FF)
        text("Rooms",14,98,19,0x263D48FF,true)
        let search=Box(x:12,y:132,w:244,h:32)
        button(query.isEmpty ? "Search rooms…":"Search: \(query)",search,active:searching){self.searching=true;self.keyboardFocus=nil}
        let categories=["All"]+RoomCategory.allCases.map(\.title)
        button("Category: \(categories[min(category,categories.count-1)])",Box(x:12,y:173,w:244,h:29)){self.category=(self.category+1)%categories.count;self.catalogScroll=0}
        let chosen:RoomCategory?=category==0 ? nil:RoomCategory.allCases[category-1]
        let rooms=RoomCatalog.search(query:query).filter{$0.kind != .lobby && (chosen==nil || $0.category==chosen)}
        let listBottom=height-220
        catalogScroll=max(0,min(catalogScroll,max(0,Double(rooms.count)*64-(listBottom-214))))
        lt_clip(desktop,0,210,268,Float(max(0,listBottom-210)))
        inputClip=Box(x:0,y:210,w:268,h:max(0,listBottom-210))
        for (i,room) in rooms.enumerated() {
            let y=214+Double(i)*64-catalogScroll
            guard y+60>210 && y<listBottom else {continue}
            let active:Bool=interaction.tool == .room(room.kind)
            let b=Box(x:10,y:y,w:248,h:58)
            let blocker=room.buildBlocker(stars:session.game.stars,cash:session.game.cash)
            button("",b,active:active){
                if let blocker {self.status="\(room.title): \(blocker)";self.selectedCatalog=room.kind}
                else {self.choose(.room(room.kind));self.selectedCatalog=room.kind}
            }
            if let frame=atlas.frames["room.\(room.kind.rawValue).open"] {
                lt_image(desktop,sheetPaths[frame.sheet]!,Float(frame.rect[0]),Float(frame.rect[1]),Float(frame.rect[2]),Float(frame.rect[3]),18,Float(y+9),78,36,0,255)
            }
            text(room.title,105,y+9,12,active ? 0xFFFFFFFF:0x263D48FF,true)
            text(blocker == nil ? "$\(room.cost.formatted()) · \(room.width) cells":"Level \(room.requiredStars) · $\(room.cost.formatted())",105,y+31,10,active ? 0xDBF2EFFF:0x59717AFF)
        }
        lt_clip(desktop,0,0,-1,-1)
        inputClip=nil
        if rooms.isEmpty {text("No matching rooms.",16,223)}
        rect(Box(x:0,y:listBottom,w:268,h:height-listBottom-28),0xE7EFF1FF)
        let room=selectedCatalog.definition
        text(room.title,14,listBottom+12,15,0x263D48FF,true)
        var y=listBottom+40
        for line in wrap(room.detail,columns:33) {text(line,14,y,12);y+=17}
        text("\(room.width) cells · \(room.capacity) capacity",14,y+8,12)
        text("$\(room.cost.formatted()) to build",14,y+29,12)
        text("$\(room.dailyRent.formatted())/day · $\(room.upkeep)/day upkeep",14,y+50,11)
        if let blocker=room.buildBlocker(stars:session.game.stars,cash:session.game.cash) {text(blocker,14,y+72,11,0x9D4035FF)}
    }
    var selectedCatalog:RoomKind = .office
    func wrap(_ s:String,columns:Int=37)->[String] {
        s.split(separator:"\n",omittingEmptySubsequences:false).flatMap { paragraph->[String] in
            var lines:[String]=[],line=""
            for word in paragraph.split(separator:" ") {
                if line.count+word.count+1>columns && !line.isEmpty {lines.append(line);line=""}
                line+=(line.isEmpty ? "":" ")+word
            }
            lines.append(line);return lines
        }
    }
    func drawInspector() {
        guard !panel.isEmpty || interaction.selectedRoom != nil || interaction.selectedElevator != nil else {return}
        let x=width-310
        rect(Box(x:x,y:84,w:310,h:height-112),0xF5F7F8FF)
        lt_clip(desktop,Float(x),84,310,Float(height-112))
        inputClip=Box(x:x,y:84,w:310,h:height-112)
        var y=96-inspectorScroll
        func label(_ s:String,size:Double=13,color:UInt32=0x253D4AFF) {for line in self.wrap(s) {self.text(line,x+15,y,size,color);y+=size+6};y+=7}
        func action(_ s:String,enabled:Bool=true,_ body:@escaping()->Void) {
            if y+30>84 && y<height-28 {self.button(s,Box(x:x+12,y:y,w:286,h:30),enabled:enabled,action:body)}
            y+=38
        }
        action("Close inspector ×"){self.panel="";self.interaction.selectedRoom=nil;self.interaction.selectedElevator=nil}
        let g=session.game
        if let id=interaction.selectedRoom,let room=g.rooms.first(where:{$0.id==id}) {
            label(room.kind.title,size:19);label("Floor \(TowerState.floorLabel(room.floor)) · Unit \(room.id)\n\(room.people)/\(room.kind.capacity) occupants · \(Int(room.happiness*100))% happy")
            if let signal=g.signal(for:room) {label(signal.text,color:0x9D4035FF)}
            if let incident=room.incident {label("\(incident.title)\n\(incident.remainingMinutes) game minutes remaining")}
            for response in g.incidentActions(for:room) {
                let blocker=g.responseBlocker(for:room,action:response)
                action(response.title,enabled:blocker==nil){self.execute(.respondToIncident(id,action:TowerIncidentAction(response)))}
                if let blocker {label(blocker,size:11)}
            }
            let coverage=g.neighborhoodCoverage
            if let services=coverage.rooms[id] {for service in NeighborhoodService.allCases {if let amount=services[service] {label("\(service.title): \(amount.percent)% · \(amount.explanation)",size:12)}}}
            if let load=coverage.venues[id] {label("Serves \(Int(load.served))/\(load.capacity) neighbors",size:12)}
            if room.kind.capacity>0 {
                label("Rent: \(Int(room.rent*100))% of market")
                action("Rent −10%",enabled:room.rent>0.6){self.execute(.setRent(id,value:max(0.6,room.rent-0.1)))}
                action("Rent +10%",enabled:room.rent<1.6){self.execute(.setRent(id,value:min(1.6,room.rent+0.1)))}
                action("Follow a visitor"){self.execute(.requestTrip(roomID:id,from:0,to:room.floor))}
            }
            if room.kind.hasStyles {for style in RoomStyle.allCases {action("Interior style \(style.title)",enabled:room.incident?.isActive != true){self.execute(.setRoomStyle(id,style:style))}}}
            if room.kind.isApartment {
                label("Leasing requirements",size:15)
                for policy in TenantScreening.allCases {action("Checks: \(policy.title)\(room.screeningPolicy==policy ? " ✓":"")"){self.execute(.setApartmentPolicy(id,screening:policy,deposit:room.depositPolicy))}}
                for deposit in ApartmentDeposit.allCases {action("Deposit: \(deposit.title)\(room.depositPolicy==deposit ? " ✓":"")"){self.execute(.setApartmentPolicy(id,screening:room.screeningPolicy,deposit:deposit))}}
            }
            if room.kind == .lobby {action("Grand Lobby · $40,000",enabled:g.stars>=3 && g.lobbyHeight<4){self.execute(.upgradeLobby);self.scene.fit(game:self.session.game,width:self.canvas.w,height:self.canvas.h)}}
            if room.kind != .lobby {action("Delete room…",enabled:room.incident?.isActive != true){self.delete(.room(id))}}
            label("Incident sandbox",size:14)
            for kind in IncidentKind.allCases {action("Trigger \(kind.rawValue)",enabled:room.kind != .lobby && room.incident?.isActive != true){self.execute(.triggerIncident(kind,roomID:id))}}
        } else if let id=interaction.selectedElevator,let lift=g.elevators.first(where:{$0.id==id}) {
            label("\(lift.kind.title) \(id)",size:18)
            label("\(lift.passengers)/\(lift.capacity) passengers\nServes \(TowerState.floorLabel(lift.bottom))–\(lift.topFloor)\nColumn \(lift.column.map(String.init) ?? "center")\n\(lift.doorsOpen ? "Doors open":"In service")")
            if lift.kind == .express {label("Stops: \(g.servedFloors(lift).map{TowerState.floorLabel($0)}.joined(separator:", "))")}
            action("Upgrade to wide · $14,000",enabled:lift.kind == .standard){self.execute(.upgradeElevator(id))}
            action("Relocate shaft · free"){self.choose(.relocate(id,lift.kind))}
            action("Delete entire shaft…"){self.delete(.elevator(id))}
        } else if panel=="build" {
            label("Build your tower",size:19)
            action("Draw floor / extend lobby"){self.choose(.floor)}
            action("Add floor · $8,000"){self.execute(.addFloor)}
            action("Widen left by 8 cells"){self.execute(.widenTower(left:true,cells:8))}
            action("Widen right by 8 cells"){self.execute(.widenTower(left:false,cells:8))}
            for kind in [ElevatorKind.standard,.wide,.express] {action("\(kind.title) · $\(kind.cost.formatted())"){self.choose(.elevator(kind))}}
            action("Extend all elevator shafts"){self.execute(.extendElevators)}
            action("Excavate \(TowerState.floorLabel(g.bottomFloor-1)) · $\(g.nextBasementCost.formatted())",enabled:g.excavationBlocker==nil){self.execute(.excavateBasement);self.scene.fit(game:self.session.game,width:self.canvas.w,height:self.canvas.h)}
            if let blocker=g.excavationBlocker {label(blocker,size:12)}
            label(TowerState.buildingLimitsDescription,size:12)
        } else if panel=="tower" {
            label("Level \(g.stars) · \(g.level.title)",size:19)
            for requirement in g.levelRequirements {label("\(requirement.complete ? "Met:":"Next:") \(requirement.text)",size:12)}
            label("Ambitions",size:16)
            for ambition in g.visibleAmbitions {
                label("\(ambition.title)\n\(ambition.detail)",size:12)
                action("Claim $\(ambition.reward.formatted())",enabled:ambition.isComplete && !ambition.isClaimed){self.execute(.claimAmbition(ambition.id));self.celebrate(ambition.title)}
            }
            label("Tower events",size:16)
            for ability in TowerAbility.allCases {
                action("\(ability.title) · $\(ability.cost)",enabled:g.abilityBlocker(ability)==nil){self.execute(.activateAbility(ability));self.celebrate(ability.title)}
                if let blocker=g.abilityBlocker(ability) {label(blocker,size:11)}
                else {label("\(ability.detail)\n\(g.abilityRemainingMinutes(ability)) min active; \(g.abilityCooldownMinutes(ability)) min cooldown",size:11)}
            }
            action("Grand Lobby · $40,000",enabled:g.stars>=3 && g.lobbyHeight<4){self.execute(.upgradeLobby);self.scene.fit(game:self.session.game,width:self.canvas.w,height:self.canvas.h)}
            action("Excavate next basement",enabled:g.excavationBlocker==nil){self.execute(.excavateBasement)}
            label("Roadmap",size:16)
            for level in TowerLevel.all {label("Level \(level.number): \(level.title)\n\(level.unlockTitles.joined(separator:", "))",size:12)}
            label("\(g.topFloor+1) floors · \(g.basementDepth) basements\n\(g.rooms.count-1) rooms · \(g.queueCount) lift queue\n\(g.completedTrips) completed trips\n$\(g.projectedIncome)/day income\n$\(g.projectedExpenses)/day costs",size:12)
            action("Recover a tower…"){self.safeSwitch{self.openDialog("recover")}}
            action(scene.reducedMotion ? "Reduce motion: on":"Reduce motion: off"){self.scene.reducedMotion.toggle()}
        } else if panel=="issues" {
            label("Room issues",size:19)
            let coverage=g.neighborhoodCoverage
            let issues=g.rooms.compactMap{room in g.signal(for:room,coverage:coverage).map{(room,$0)}}
            if issues.isEmpty {label("No rooms need attention.")}
            for (room,signal) in issues {
                action("\(TowerState.floorLabel(room.floor)) · \(room.kind.title)"){self.interaction.selectedRoom=room.id;self.panel="";self.inspectorScroll=0;self.reveal(room)}
                label(signal.text,size:11)
                if let service=coverage.shortage(for:room.id) {action("Add \(service.title.lowercased()) nearby"){self.choose(.room(service.defaultRoom));self.scene.coverage=service;self.reveal(room)}}
            }
        } else {
            label("How to play",size:19)
            label("Start with your lobby and $180,000. Add a floor, place businesses, then connect them with elevators. Tenants arrive while time runs. Food, shops and services help them thrive.")
            label("Click or drag a row to build rooms. Draw a floor to extend it. Elevator tools drag vertically at the shaft's chosen column. Blocking rooms must be demolished first.")
            label("Space: pause / resume\n1 / 2 / 3: 1× / 4× / 12×\nI / Escape: inspect / cancel\nX: delete\nF: fit\n+ / −: zoom\nTab: focus mode\nCtrl+S: save\nCtrl+O: open\nCtrl+N: new\nCtrl+F: search\nAlt-drag: pan with a tool\nCtrl+wheel: cursor-centered zoom")
            label("Use Tower for progression, ambitions, special events, the Grand Lobby, and basement permits. Inspect a room to set rent, style, leasing policies or resolve incidents. Issues locates rooms needing help.")
        }
        inspectorScroll=max(0,inspectorScroll)
        inspectorContentHeight=y+inspectorScroll-96
        if inspectorContentHeight<height-130 {inspectorScroll=0}
        lt_clip(desktop,0,0,-1,-1)
        inputClip=nil
    }
    var inspectorContentHeight=0.0
    func reveal(_ room:Room) {
        let r=scene.roomRect(room,game:session.game,width:canvas.w,height:canvas.h)
        scene.panX += canvas.w/2-r.x-r.width/2
        scene.panY += canvas.h/2-r.y-r.height/2
    }
    func delete(_ target:TowerDemolitionTarget) {
        do {_ = try session.requestDemolition(target)} catch {status=error.localizedDescription}
    }
    func drawModal() {
        if let target=session.pendingDemolition {
            if displayedDemolition != target {modalFocus.begin();keyboardFocus=0;displayedDemolition=target}
            let quote=try? session.game.demolitionQuote(for:target.coreTarget)
            modalTitle=quote?.title ?? "Delete selection?"
            modalBody="\(quote?.consequences ?? "")\nRefund: $\(quote?.refund ?? 0)"
            modalAccept={try? self.session.resolveDemolition(confirmed:true);self.interaction.cancel();self.modalTitle=""}
            modalCancel={try? self.session.resolveDemolition(confirmed:false);self.modalTitle=""}
        }
        guard !modalTitle.isEmpty else {return}
        actions=[]
        rect(Box(x:0,y:0,w:width,h:height),0x14232B99)
        let b=Box(x:width/2-300,y:height/2-150,w:600,h:300)
        rect(b,0xF7F9FAFF)
        text(modalTitle,b.x+24,b.y+22,19,0x253D4AFF,true)
        for (i,line) in wrap(modalBody,columns:65).prefix(8).enumerated() {text(line,b.x+24,b.y+67+Double(i)*19,13)}
        button("Keep it / Cancel",Box(x:b.x+24,y:b.y+248,w:205,h:32)){self.dismissModal(accept:false)}
        button("Continue",Box(x:b.x+360,y:b.y+248,w:205,h:32)){self.dismissModal(accept:true)}
    }
    func dismissModal(accept:Bool) {
        let action=accept ? modalAccept:modalCancel
        modalTitle="";modalAccept=nil;modalCancel=nil;keyboardFocus=nil;modalFocus.begin();displayedDemolition=nil;action?()
    }
    func confirm(_ title:String,_ body:String,accept:@escaping()->Void) {
        guard modalTitle.isEmpty else {return}
        let previous=session.speed;session.speed=0
        modalFocus.begin();keyboardFocus=0
        modalTitle=title;modalBody=body
        modalAccept={self.session.speed=previous;accept()}
        modalCancel={self.session.speed=previous}
    }
    func safeSwitch(_ action:@escaping()->Void) {
        if session.hasUnsavedChanges {confirm("Keep your current tower?","Continue keeps a recovery copy before switching towers. Use Save first if you want a named save file.",accept:action)}
        else {action()}
    }
    func newTower() {
        do {_ = try session.startNewGame(store:store);scene.travelerMotion.reset();interaction.cancel();panel="";title=false;session.speed=1;scene.fit(game:session.game,width:canvas.w,height:canvas.h)}
        catch {status=error.localizedDescription}
    }
    func save() {
        if let url=session.savedURL {do {try session.save(to:url,store:store);status="Saved \(url.lastPathComponent)"} catch {status=error.localizedDescription}}
        else {openDialog("save")}
    }
    func openDialog(_ purpose:String) {
        dialogPurpose=purpose;dialogPreviousSpeed=session.speed;session.speed=0
        let path=purpose=="recover" ? store.recoveryDirectory.path:session.savedURL?.path ?? dataURL.appendingPathComponent("My Tower.loftyambitions").path
        lt_file_dialog(desktop,purpose=="save" ? 1:0,path)
    }
    func fileResult(_ path:String) {
        let purpose=dialogPurpose;dialogPurpose="";defer{session.speed=dialogPreviousSpeed}
        guard !path.isEmpty else {return}
        var url=URL(fileURLWithPath:path)
        do {
            if purpose=="save" {
                if url.pathExtension.isEmpty {url.appendPathExtension("loftyambitions")}
                try session.save(to:url,store:store);status="Saved \(url.lastPathComponent)"
            } else {
                _ = try session.open(url,store:store);scene.travelerMotion.reset();interaction.cancel();panel="";title=false;scene.fit(game:session.game,width:canvas.w,height:canvas.h);status="Opened \(url.lastPathComponent)"
            }
        } catch {status=error.localizedDescription}
    }
    func zoom(_ multiplier:Double,at pointer:(Double,Double)?=nil) {
        let old=scene.scale,new=min(16,max(0.25,old*multiplier))
        let b=canvas,p=pointer ?? (b.x+b.w/2,b.y+b.h/2)
        // Camera origin has fixed ground offset; preserve the world point under the cursor.
        scene.panX=(scene.panX-(p.0-b.x-b.w/2))*new/old+(p.0-b.x-b.w/2)
        scene.panY=(scene.panY+(b.h-(p.1-b.y)-96))*new/old-(b.h-(p.1-b.y)-96)
        scene.scale=new
    }
    func handle(_ e:LTEvent) {
        let x=Double(e.x),y=Double(e.y)
        switch e.type {
        case 1:
            if smoke {running=false}
            else if session.hasUnsavedChanges {confirm("Save a recovery copy and quit?","Continue safely keeps the current tower in autosave and recovery."){self.finishQuit()}}
            else {finishQuit()}
        case 8:refreshUIScale()
        case 9:fileResult(e.text.map{String(cString:$0)} ?? "")
        case 7:if searching {query += e.text.map{String(cString:$0)} ?? "";catalogScroll=0}
        case 6:key(Int(e.key),mods:Int(e.mods))
        case 2:
            mouseX=x;mouseY=y
            if let hit=actions.last(where:{$0.enabled && $0.box.contains(x,y)}) {hit.action();return}
            guard modalTitle.isEmpty,!title,canvas.contains(x,y) else {return}
            if interaction.tool == .inspect,let signal=scene.roomSignals.first(where:{Box(x:$0.rect.x+canvas.x,y:$0.rect.y+canvas.y,w:$0.rect.width,h:$0.rect.height).contains(x,y)}) {
                interaction.selectedRoom=signal.roomID;interaction.selectedElevator=nil;panel="";inspectorScroll=0;startPoint=nil;return
            }
            searching=false;keyboardFocus=nil;startPoint=(x,y);moved=false
            panning=e.button==3 || e.mods&4 != 0 || interaction.tool == .inspect || focus
            startCell=scene.hit(x:x-canvas.x,y:y-canvas.y,game:session.game,width:canvas.w,height:canvas.h)
        case 4:
            if let start=startPoint {
                moved=moved || hypot(x-start.0,y-start.1)>4
                if panning && moved {scene.panX += Double(e.dx);scene.panY += Double(e.dy)}
            }
            mouseX=x;mouseY=y
        case 3:
            defer {startPoint=nil;startCell=nil;panning=false}
            guard startPoint != nil,!title,!focus,modalTitle.isEmpty,canvas.contains(x,y),let from=startCell,let to=scene.hit(x:x-canvas.x,y:y-canvas.y,game:session.game,width:canvas.w,height:canvas.h) else {return}
            if panning && moved {return}
            do {
                let bank=scene.elevatorID(x:x-canvas.x,y:y-canvas.y,game:session.game,width:canvas.w,height:canvas.h)
                try interaction.drag(from:from,to:to,hitElevatorID:bank);status=interaction.tool.title
                if interaction.selectedRoom != nil || interaction.selectedElevator != nil {panel="";inspectorScroll=0}
            }
            catch {status=error.localizedDescription}
        case 5:
            if mouseX<268 && !focus {catalogScroll=max(0,catalogScroll-Double(e.dy)*40)}
            else if mouseX>width-310 && !focus && (!panel.isEmpty || interaction.selectedRoom != nil || interaction.selectedElevator != nil) {inspectorScroll=min(max(0,inspectorContentHeight-(height-130)),max(0,inspectorScroll-Double(e.dy)*40))}
            else if e.mods&2 != 0 || e.mods&8 != 0 {zoom(pow(1.12,Double(e.dy)),at:(mouseX,mouseY))}
            else {scene.panX -= Double(e.dx)*24;scene.panY -= Double(e.dy)*24}
        default:break
        }
    }
    func key(_ key:Int,mods:Int) {
        if !modalTitle.isEmpty {if key==27 {dismissModal(accept:false)} else if key==13 {dismissModal(accept:modalFocus.acceptsReturn)} else if key==9 {modalFocus.toggle();keyboardFocus=modalFocus.acceptsReturn ? 1:0};return}
        if title {if key==13 {title=false;session.speed=1};return}
        let command=mods&2 != 0 || mods&8 != 0
        if command {
            switch key {case 115:save();case 111:safeSwitch{self.openDialog("open")};case 110:safeSwitch{self.newTower()};case 102,114:searching=true;default:break};return
        }
        if searching {
            if key==8,!query.isEmpty {query.removeLast();catalogScroll=0}
            if key==27 || key==13 {searching=false}
            return
        }
        if key==9,mods&1 != 0 {
            let valid=actions.indices.filter{actions[$0].enabled}
            if !valid.isEmpty {let index=valid.firstIndex(of:keyboardFocus ?? -1) ?? 0;keyboardFocus=valid[(index+1)%valid.count]};return
        }
        if key==13,let i=keyboardFocus,actions.indices.contains(i),actions[i].enabled {actions[i].action();return}
        switch key {
        case 32:session.togglePause()
        case 49:session.speed=1
        case 50:session.speed=4
        case 51:session.speed=12
        case 27:if focus {focus=false}else{choose(.inspect)}
        case 105:choose(.inspect)
        case 120:choose(.delete)
        case 102:scene.fit(game:session.game,width:canvas.w,height:canvas.h)
        case 9:focus.toggle()
        case 43,61:zoom(1.25)
        case 45:zoom(0.8)
        default:break
        }
    }
    func finishQuit() {
        if !smoke {
            do {
                try DesktopPersistence.finishSession(session,autosaveURL:autosaveURL,store:store,autosaveBlocked:autosaveBlocked)
            } catch {status=error.localizedDescription;return}
        }
        running=false
    }
    func run() throws {
        if CommandLine.arguments.contains("--performance-smoke") {try performanceCheck();return}
        if smoke {try smokeCheck();return}
        var previous=lt_time();lastTick=previous;lastAuto=previous
        while running {
            let now=lt_time(),delta=min(0.1,max(0,now-previous));previous=now
            ambient+=delta
            var e=LTEvent()
            while lt_poll(desktop,&e) {handle(e)}
            if !title && modalTitle.isEmpty && dialogPurpose.isEmpty {
                if session.speed>0 {elapsed+=delta}
                if now-lastTick>=0.1 {
                    let old=session.game.stars;session.tick();lastTick=now
                    if session.game.stars>old {celebrate("Level \(session.game.stars) · \(session.game.level.title)")}
                }
            }
            if !autosaveBlocked && now-lastAuto>60 && !title && modalTitle.isEmpty && dialogPurpose.isEmpty {
                do {try session.autosave(to:autosaveURL,store:store)}catch{status=error.localizedDescription};lastAuto=now
            }
            draw();lt_present(desktop);lt_delay(16)
        }
    }
    func performanceCheck() throws {
        guard let index=CommandLine.arguments.firstIndex(of:"--tower"),CommandLine.arguments.count>index+1 else {throw TowerError("Performance smoke requires --tower FILE.")}
        try FileManager.default.createDirectory(at:dataURL,withIntermediateDirectories:true)
        session.game=try store.read(URL(fileURLWithPath:CommandLine.arguments[index+1]))
        session.speed=0;title=false
        scene.fit(game:session.game,width:canvas.w,height:canvas.h)
        var reports:[[String:Any]]=[]
        func frame()->Double {
            let start=lt_time()
            var event=LTEvent()
            while lt_poll(desktop,&event) {handle(event)}
            draw();lt_present(desktop)
            return lt_time()-start
        }
        for phase in ["maximized","zoomed-out","unscaled","restored","maximized-again"] {
            if phase=="unscaled" {uiScale=DesktopUIScale(requested:1)}
            if phase=="restored" {uiScale=DesktopUIScale()}
            if phase=="restored" {lt_restore(desktop)} else {lt_maximize(desktop)}
            refreshUIScale()
            if phase=="zoomed-out" {scene.scale=0.25}
            // Warm the bounded procedural cache without blocking input for a
            // whole viewport's cloud generation in a single frame.
            for _ in 0..<240 {_ = frame()}
            var before=LTCacheStats();lt_cache_stats(desktop,&before)
            var samples:[Double]=[]
            for _ in 0..<120 {samples.append(frame())}
            var after=LTCacheStats();lt_cache_stats(desktop,&after)
            let sorted=samples.sorted(),p95=sorted[Int(Double(sorted.count-1)*0.95)]
            let decodes=after.png_decodes-before.png_decodes
            var windowWidth:Int32=0,windowHeight:Int32=0;lt_window_size(desktop,&windowWidth,&windowHeight)
            let report:[String:Any]=["phase":phase,"width":width,"height":height,"windowWidth":windowWidth,"windowHeight":windowHeight,"uiScale":effectiveUIScale,"scale":scene.scale,"frames":samples.count,"averageFPS":Double(samples.count)/samples.reduce(0,+),"p95FrameMilliseconds":p95*1000,"maxFrameMilliseconds":sorted.last!*1000,"steadyPNGDecodes":decodes,"spriteTextures":after.images,"cloudTextures":after.dynamic_images]
            reports.append(report)
            try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:dataURL.appendingPathComponent("performance.json"))
            guard decodes==0,p95<0.25 else {throw TowerError("Resize regression in \(phase): \(decodes) repeated PNG decodes, p95 \(p95*1000) ms.")}
        }
        draw();_ = lt_capture(desktop,dataURL.appendingPathComponent("maximized-gameplay.png").path);lt_present(desktop)
        print("Resize performance smoke passed: default UI, maximum zoom-out, unscaled 4K, restored, maximized again; no steady-state PNG decoding. Output: \(dataURL.path)")
    }
    func smokeCheck() throws {
        try FileManager.default.createDirectory(at:dataURL,withIntermediateDirectories:true)
        session.game=try TowerReplayTimeline.selfCheck.run();session.speed=0;title=false
        scene.fit(game:session.game,width:canvas.w,height:canvas.h)
        for i in 0..<5 {elapsed=Double(i);draw();if i==4 {guard lt_capture(desktop,dataURL.appendingPathComponent("desktop-gameplay.png").path) else {throw TowerError(String(cString:lt_error()))}};lt_present(desktop)}
        let save=dataURL.appendingPathComponent("Smoke Tower.loftyambitions")
        try session.save(to:save,store:store)
        let before=try TowerSnapshot.canonicalData(session.game)
        _ = try session.open(save,store:store)
        guard before == (try TowerSnapshot.canonicalData(session.game)),assetMisses.isEmpty else {throw TowerError("Smoke check failed. Missing assets: \(assetMisses.sorted())")}
        showPanel("tower");draw();_ = lt_capture(desktop,dataURL.appendingPathComponent("desktop-progression.png").path);lt_present(desktop)
        showPanel("build");draw();_ = lt_capture(desktop,dataURL.appendingPathComponent("desktop-building.png").path);lt_present(desktop)
        try before.write(to:dataURL.appendingPathComponent("snapshot.json"))
        print("Desktop smoke passed: shared replay, rendered assets, progression/build controls, and save/recovery round-trip. Output: \(dataURL.path)")
    }
}

do {try DesktopGame().run()} catch {fputs("Lofty Ambitions: \(error.localizedDescription)\n",stderr);exit(1)}
