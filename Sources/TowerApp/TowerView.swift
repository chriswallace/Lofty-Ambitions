import AppKit
import TowerCore
import TowerArt
import TowerPresentation

/// Simulation coordinates are independent of the high-resolution art atlas.
/// Native artwork stays sharp when zooming on Retina and 4K displays.
final class TowerView:NSView {
    weak var controller:GameController?
    var scale:CGFloat=2
    var cloudSeconds:Double=0
    let cloudTextures: NSCache<NSNumber, CGImage> = {
        let cache = NSCache<NSNumber, CGImage>()
        // A large external display at minimum zoom can expose hundreds of clouds.
        // Keep that working set resident instead of regenerating it every frame.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    var spriteClock = SpriteAnimationClock()
    lazy var scene = TowerScene(atlas:atlas)
    var travelerMotion:ActorMotion {get{scene.travelerMotion} set{scene.travelerMotion=newValue}}
    var cityStreet:CityLayout.Street?
    var pan=CGPoint.zero
    var hovered:(floor:Int,slot:Int)?
    var hoveredSignal:Int?
    var placementReason:String?
    var startDrag:CGPoint?
    var startCell:(floor:Int,slot:Int)?
    var didDrag=false
    var panGesture=false
    var tracking:NSTrackingArea?
    let atlas: TowerAtlas = {
        do { return try TowerAtlas() }
        catch { fatalError("Unable to load bundled Tokyo artwork: \(error)") }
    }()
    let slotWidth:CGFloat=8
    let floorHeight:CGFloat=24
    var shaftWidth:CGFloat { guard let c=controller else { return 0 };return CGFloat(c.game.legacyShaftWidth)*8 }
    var towerWidth:CGFloat { guard let c=controller else{return 512};return CGFloat(c.game.rightEdge-c.game.leftEdge)*8+shaftWidth }
    var ground:CGFloat { 96 }
    private var unroundedOrigin:CGPoint {
        let left=CGFloat(controller?.game.leftEdge ?? 0)*8
        return CGPoint(x:(bounds.width-towerWidth*scale)/2-left*scale+pan.x,y:ground+pan.y)
    }
    var origin:CGPoint {guard let game=controller?.game else{return .zero};prepareScene(game);return scene.worldOrigin}
    override var acceptsFirstResponder:Bool { true }
    init(controller:GameController) {
        self.controller=controller;super.init(frame:.zero)
        wantsLayer=true;layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("Tower construction grid. Eight-pixel cells. Select a tool, then click or drag to build. Drag elevator tools where the shaft belongs to choose its column and service floors. Demolish blocking rooms first.")
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas();if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(tracking!)
    }
    func roomX(_ column:Int)->CGFloat {guard let game=controller?.game else{return 0};prepareScene(game);return scene.worldRoomX(column)}
    func personX(_ column:Double)->CGFloat {guard let game=controller?.game else{return 0};prepareScene(game);return scene.worldPersonX(column)}
    func shaftX(_ index:Int)->CGFloat {guard let game=controller?.game else{return 0};prepareScene(game);return scene.worldShaftX(index)}
    func roomRect(_ room:Room)->CGRect {guard let game=controller?.game else{return .zero};prepareScene(game);return scene.worldRoomRect(room)}
    func spanRect(_ floor:Int)->CGRect {guard let game=controller?.game else{return .zero};prepareScene(game);return scene.worldSpanRect(floor)}
    func hit(_ point:CGPoint)->(floor:Int,slot:Int)? {
        guard let game=controller?.game,!coverageLegendRect.contains(point) else{return nil}
        prepareScene(game)
        return scene.hit(x:point.x,y:bounds.height-point.y,game:game,width:bounds.width,height:bounds.height)
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil)
        startDrag=p;startCell=hit(p);hovered=startCell;didDrag=false
        panGesture=event.modifierFlags.contains(.option) || (controller?.selectedKind == nil && controller?.floorMode == false && controller?.elevatorTool == nil && controller?.demolition == false)
    }
    override func mouseDragged(with event:NSEvent) {
        guard let startDrag else{return}
        let now=convert(event.locationInWindow,from:nil)
        if hypot(now.x-startDrag.x,now.y-startDrag.y)>3 || didDrag {
            didDrag=true
            if panGesture {pan.x += event.deltaX;pan.y -= event.deltaY}
            hovered=hit(now);needsDisplay=true
        }
    }
    override func mouseUp(with event:NSEvent) {
        if controller?.focusMode == true { startDrag=nil;startCell=nil;needsDisplay=true;return }
        let p=convert(event.locationInWindow,from:nil)
        if !didDrag, controller?.selectedKind == nil, controller?.floorMode == false, controller?.elevatorTool == nil, controller?.demolition == false, let id=signalHit(p) {
            controller?.selectedRoom=id;controller?.selectedElevator=nil
            controller?.updateUI(rebuildInspector:true)
            startDrag=nil;startCell=nil;needsDisplay=true;return
        }
        if let start=startCell,let end=hit(p),!panGesture || !didDrag {
            if controller?.demolition == true,let index=liftHit(p),let c=controller {
                c.removeElevator(c.game.elevators[index].id)
            } else if controller?.selectedKind == nil && controller?.floorMode == false && controller?.elevatorTool == nil && controller?.demolition == false,
               let index=liftHit(p) { controller?.inspectElevator(index) }
            else { controller?.dragged(fromFloor:start.floor,fromSlot:start.slot,toFloor:end.floor,toSlot:end.slot) }
        }
        startDrag=nil;startCell=nil;needsDisplay=true
    }
    func liftHit(_ p:CGPoint)->Int? {
        guard let c=controller else{return nil}
        let x=(p.x-origin.x)/scale,y=(p.y-origin.y)/scale
        for i in c.game.elevators.indices {
            let e=c.game.elevators[i]
            if x >= shaftX(i),x < shaftX(i)+CGFloat(e.footprintWidth)*8,y >= CGFloat(e.bottom)*24,y <= CGFloat(e.topFloor+1)*24 {return i}
        }
        return nil
    }
    override func mouseMoved(with event:NSEvent) {let p=convert(event.locationInWindow,from:nil);hovered=hit(p);hoveredSignal=controller?.selectedKind == nil && controller?.floorMode == false && controller?.elevatorTool == nil && controller?.demolition == false ? signalHit(p):nil;needsDisplay=true}
    override func mouseExited(with event:NSEvent) {hovered=nil;hoveredSignal=nil;needsDisplay=true}
    override func scrollWheel(with event:NSEvent) {
        if event.modifierFlags.contains(.command) {
            guard event.scrollingDeltaY != 0 else { return }
            zoom(by:event.scrollingDeltaY>0 ? 0.95:1.05,at:convert(event.locationInWindow,from:nil))
        }
        else {pan.x -= event.scrollingDeltaX;pan.y += event.scrollingDeltaY;needsDisplay=true}
    }
    override func magnify(with event:NSEvent) {zoom(by:1+event.magnification,at:convert(event.locationInWindow,from:nil))}
    override func keyDown(with event:NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ":controller?.togglePause()
        case "1":controller?.speed=1
        case "2":controller?.speed=4
        case "3":controller?.speed=12
        case "+","=":zoomAtCursor(by:1.25)
        case "-":zoomAtCursor(by:0.8)
        case "f":fitTower()
        case "\t":controller?.toggleFocusMode()
        case "\u{1b}":
            if controller?.focusMode == true { controller?.setFocusMode(false) } else { controller?.choose(nil) }
        case "i":controller?.choose(nil)
        case "x":controller?.chooseDemolition()
        default:super.keyDown(with:event)
        }
    }
    func zoomAtCursor(by value:CGFloat) {
        let cursor=window.map { convert($0.mouseLocationOutsideOfEventStream,from:nil) }
        zoom(by:value,at:cursor.flatMap { bounds.contains($0) ? $0:nil })
    }
    func zoom(by value:CGFloat,at anchor:CGPoint?=nil) {
        guard value.isFinite,value>0 else { return }
        let nextScale=min(16,max(0.25,scale*value))
        guard nextScale != scale else { return }
        let point=anchor ?? CGPoint(x:bounds.midX,y:bounds.midY)
        let world=CGPoint(x:(point.x-origin.x)/scale,y:(point.y-origin.y)/scale)
        scale=nextScale
        // Keep the same world point under the cursor, including the scale-dependent
        // horizontal centering. Leave rounding to the renderer for crisp artwork.
        let base=unroundedOrigin
        pan.x += point.x-world.x*scale-base.x
        pan.y += point.y-world.y*scale-base.y
        needsDisplay=true
    }
    func fitTower() {
        guard let game=controller?.game else{return}
        scene.fit(game:game,width:bounds.width,height:bounds.height)
        scale=scene.scale;pan=CGPoint(x:scene.panX,y:-scene.panY);needsDisplay=true
    }
    func revealTop() {
        guard let c=controller else{return}
        let top=origin.y+CGFloat(c.game.topFloor+1)*24*scale
        if top>bounds.height-55 {pan.y -= top-bounds.height+55};needsDisplay=true
    }
    func revealBasement() {
        guard let c=controller else{return}
        let bottom=origin.y+CGFloat(c.game.bottomFloor)*24*scale
        if bottom<64 {pan.y += 64-bottom};needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let c=controller,let ctx=NSGraphicsContext.current?.cgContext else{return}
        let game=c.game
        ctx.clip(to:bounds);ctx.setShouldAntialias(false);NSGraphicsContext.current?.imageInterpolation = .none
        drawSharedScene(game)
        ctx.saveGState();ctx.translateBy(x:origin.x,y:origin.y);ctx.scaleBy(x:scale,y:scale)
        if let room=game.rooms.first(where:{$0.id==c.selectedRoom}) {outline(roomRect(room),color:0xBA2D2D,width:1)}
        if c.floorMode || c.selectedKind != nil || c.elevatorTool != nil || c.movingElevatorID != nil {
            for level in game.bottomFloor...game.topFloor where level<=0 || level>=game.lobbyHeight {
                let r=spanRect(level)
                for column in game.span(level).left..<game.span(level).right {line(CGPoint(x:roomX(column),y:r.minY),CGPoint(x:roomX(column),y:r.maxY),0x8B9B8E)}
            }
        }
        drawCoverageOverlay(game)
        drawPreview(c)
        ctx.restoreGState()
        drawCoverageLabels()
        if !c.focusMode { drawRoomSignals(game) }
        drawCoverageLegend()
        if let reason=placementReason {
            let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor(hex:0x8F1515)]
            let text=reason as NSString
            let width=max(80,min(580,bounds.width-32))
            let height=text.boundingRect(with:CGSize(width:width-16,height:100),options:.usesLineFragmentOrigin,attributes:attributes).height.rounded(.up)
            let box=CGRect(x:16,y:40,width:width,height:height+16)
            fill(box,0xFFF1E8);outline(box,color:0xA93636,width:1)
            text.draw(in:box.insetBy(dx:8,dy:8),withAttributes:attributes)
        }
        label("\(Int(scale*100))%",at:CGPoint(x:bounds.width-48,y:12),size:11,color:0xF4F0D8)
        if c.speed==0 && !c.focusMode {fill(CGRect(x:bounds.midX-37,y:bounds.height-29,width:74,height:21),0xD8D8D8);outline(CGRect(x:bounds.midX-37,y:bounds.height-29,width:74,height:21),color:0x444444,width:1);label("PAUSED",at:CGPoint(x:bounds.midX-26,y:bounds.height-25),size:12,color:0x222222)}
    }
    func drawPreview(_ c:GameController) {
        placementReason=nil
        guard let h=hovered else{return}
        if c.floorMode {
            let first=startCell ?? h
            let l=min(first.slot,h.slot),r=max(first.slot,h.slot)+1
            let rect=CGRect(x:roomX(l),y:CGFloat(first.floor)*24,width:CGFloat(r-l)*8,height:24)
            let valid=(try? c.game.floorConstructionCost(floor:first.floor,from:l,to:r-1)) != nil
            fill(rect,color:NSColor(hex:valid ? 0xE0D884:0xC94141,alpha:0.35));outline(rect,color:valid ? 0xF5F0A4:0xA90000,width:1)
        } else if let kind=c.elevatorTool {
            let first=startCell ?? h
            let range=c.elevatorRange(from:first.floor,to:h.floor)
            let width=kind.width+1
            do {
                if let id=c.movingElevatorID {
                    try c.game.validateElevatorRelocation(id,at:first.slot,from:range.bottom,to:range.top)
                } else {
                    guard c.game.elevators.count<12 else {throw TowerError("The tower supports up to 12 shafts.")}
                    try c.game.validateElevatorPlacement(kind,at:first.slot,from:range.bottom,to:range.top)
                    guard c.game.cash>=kind.cost else {throw TowerError("This elevator costs $\(kind.cost.formatted()).")}
                }
            } catch {placementReason=error.localizedDescription}
            let valid=placementReason == nil
            let rect=CGRect(x:roomX(first.slot),y:CGFloat(range.bottom)*24,width:CGFloat(width)*8,height:CGFloat(range.top-range.bottom+1)*24)
            fill(rect,color:NSColor(hex:valid ? 0x65C389:0xC94141,alpha:0.4))
            outline(rect,color:valid ? 0x206D3C:0xA90000,width:1)
            for room in c.game.rooms where room.kind != .lobby && room.floor>=range.bottom && room.floor<=range.top && room.slot<first.slot+width && room.slot+room.kind.width>first.slot {
                fill(roomRect(room),color:NSColor.red.withAlphaComponent(0.3))
                outline(roomRect(room),color:0xA90000,width:1)
            }
        } else if let kind=c.selectedKind {
            let first=startCell ?? h
            for slot in stride(from:min(first.slot,h.slot),through:max(first.slot,h.slot),by:kind.width) {
                let r=CGRect(x:roomX(slot),y:CGFloat(first.floor)*24,width:CGFloat(kind.width)*8,height:24)
                let valid=(try? c.game.validateBuild(kind,floor:first.floor,slot:slot)) != nil
                fill(r,color:NSColor(hex:valid ? 0xFFFFA0:0xC62E32,alpha:0.4));outline(r,color:valid ? 0xFFFFC0:0xA60000,width:1)
            }
        } else if c.demolition {
            let point=CGPoint(x:origin.x+roomX(h.slot)*scale+scale,y:origin.y+CGFloat(h.floor)*24*scale+scale)
            if let index=liftHit(point) {
                let lift=c.game.elevators[index]
                fill(CGRect(x:shaftX(index),y:CGFloat(lift.bottom)*24,width:CGFloat(lift.footprintWidth)*8,height:CGFloat(lift.topFloor-lift.bottom+1)*24),color:NSColor.red.withAlphaComponent(0.4))
            } else if let room=c.game.room(at:h.floor,slot:h.slot) {fill(roomRect(room),color:NSColor.red.withAlphaComponent(0.4))}
        }
    }
    func fill(_ r:CGRect,_ hex:Int) {fill(r,color:NSColor(hex:hex))}
    func fill(_ r:CGRect,color:NSColor) {color.setFill();r.fill()}
    func outline(_ r:CGRect,color:Int,width:CGFloat) {NSColor(hex:color).setStroke();let p=NSBezierPath(rect:r);p.lineWidth=width;p.stroke()}
    func line(_ a:CGPoint,_ b:CGPoint,_ color:Int) {NSColor(hex:color).setStroke();let p=NSBezierPath();p.move(to:a);p.line(to:b);p.lineWidth=1;p.stroke()}
    func label(_ text:String,at point:CGPoint,size:CGFloat,color:Int) {(text as NSString).draw(at:point,withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:.regular),.foregroundColor:NSColor(hex:color)])}
}
