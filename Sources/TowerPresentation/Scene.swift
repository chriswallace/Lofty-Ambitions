import Foundation
import TowerCore
import TowerArt

public struct SceneRect: Equatable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x=x;self.y=y;self.width=width;self.height=height }
    init(_ r: CGRect) { self.init(x:r.minX,y:r.minY,width:r.width,height:r.height) }
    var cg: CGRect { CGRect(x:x,y:y,width:width,height:height) }
}
public struct SceneColor: Equatable {
    /// Packed RRGGBBAA, with straight alpha.
    public var rgba: UInt32
    public init(rgba: UInt32) { self.rgba=rgba }
    init(hex:Int, alpha:Double=1) { rgba = UInt32(hex)<<8 | UInt32((min(1,max(0,alpha))*255).rounded()) }
}
public enum SceneCommand: Equatable {
    case fill(SceneRect,UInt32)
    case line(x1:Double,y1:Double,x2:Double,y2:Double,color:UInt32)
    /// Source is relative to the cropped atlas frame, in top-left source pixels.
    /// `cloud.<seed>` uses CloudTexture.pixels(seed:) instead of the manifest.
    case image(key:String,source:SceneRect?,destination:SceneRect,flipped:Bool,opacity:Double)
    case text(String,x:Double,y:Double,size:Double,color:UInt32)
    /// Replaces the current clip. nil restores the full viewport.
    case clip(SceneRect?)
}

public struct SceneRoomSignal {
    public let roomID:Int
    public let rect:SceneRect
    public let text:String
    public let mood:RoomMood
}

/// Shared scene generation. The simulation and artwork use upward world Y;
/// every emitted command uses top-left viewport pixel coordinates.
public final class TowerScene {
    public var scale:Double=2
    public var panX:Double=0
    /// Positive values move the tower down the viewport.
    public var panY:Double=0
    public var reducedMotion=false
    public var coverage:NeighborhoodService?
    public var coverageRoomID:Int?
    public var coverageGuides:[SceneCoverageGuide]=[]
    public var showsSignals=false
    public private(set) var roomSignals:[SceneRoomSignal]=[]
    public var signalCoverage:NeighborhoodCoverage?
    public var ambientElapsed:Double?
    let atlas:TowerAtlas
    var game:TowerState = .demoTower()
    var bounds=CGRect.zero
    var commands:[SceneCommand]=[]
    var clips:[CGRect]=[]
    var elapsed:Double=0
    var previousElapsed:Double?
    public var travelerMotion=ActorMotion()
    public var interpolatesMotion=true
    var cityStreet:CityLayout.Street?
    public init() { atlas = try! TowerAtlas() }
    public init(atlas:TowerAtlas) { self.atlas=atlas }
    var shaftWidth:CGFloat { CGFloat(game.legacyShaftWidth)*8 }
    var towerWidth:CGFloat { CGFloat(game.rightEdge-game.leftEdge)*8+shaftWidth }
    var origin:CGPoint { CGPoint(x:((bounds.width-towerWidth*scale)/2-CGFloat(game.leftEdge)*8*scale+panX).rounded(),y:(96-panY).rounded()) }
    public func fit(game:TowerState,width:Double,height:Double) {
        self.game=game;bounds=CGRect(x:0,y:0,width:width,height:height)
        let fit=min((width-80)/towerWidth,(height-160)/(Double(game.topFloor-game.bottomFloor+1)*24+12))
        scale=max(0.25,min(3,floor(fit*2)/2));panX=0;panY = -Double(game.basementDepth)*24*scale
    }
    public func hit(x:Double,y:Double,game:TowerState,width:Double,height:Double)->(floor:Int,slot:Int)? {
        self.game=game;bounds=CGRect(x:0,y:0,width:width,height:height)
        guard scale.isFinite,scale>0,x.isFinite,y.isFinite else{return nil}
        let wx=(x-origin.x)/scale,wy=(height-y-origin.y)/scale
        guard wy >= Double(game.bottomFloor)*24,wy < 24*102 else{return nil}
        let core=Double(game.core)*8
        if wx>=core && wx<core+shaftWidth {return (Int(floor(wy/24)),game.core)}
        let col=Int(floor((wx-(wx>=core+shaftWidth ? shaftWidth:0))/8))
        guard col>=(-128),col<256 else{return nil}
        return (Int(floor(wy/24)),col)
    }
    public func roomRect(_ room:Room,game:TowerState,width:Double,height:Double)->SceneRect {
        self.game=game;bounds=CGRect(x:0,y:0,width:width,height:height)
        return SceneRect(screen(roomRect(room)))
    }
    public func elevatorID(x:Double,y:Double,game:TowerState,width:Double,height:Double)->Int? {
        configure(game:game,width:width,height:height)
        let point=CGPoint(x:x,y:y)
        return game.elevators.indices.first(where:{screen(elevatorFootprint($0,game)).contains(point)}).map{game.elevators[$0].id}
    }
    func roomX(_ column:Int)->CGFloat { CGFloat(column)*8+(column>=game.core ? shaftWidth:0) }
    func personX(_ column:Double)->CGFloat { column*8+(column>Double(game.core) ? shaftWidth:0) }
    func shaftX(_ index:Int)->CGFloat {
        if let column=game.elevators[index].column{return roomX(column)}
        return CGFloat(game.core)*8+CGFloat(game.elevators.prefix(index).filter{$0.column==nil}.reduce(0){$0+$1.footprintWidth})*8
    }
    func roomRect(_ room:Room)->CGRect {
        if room.kind == .lobby {var r=spanRect(0);r.size.height=Double(game.lobbyHeight)*24;return r}
        return CGRect(x:roomX(room.slot),y:Double(room.floor)*24,width:Double(room.kind.width)*8,height:24)
    }
    func spanRect(_ floor:Int)->CGRect {
        let span=game.span(floor),gap=span.left<game.core && span.right>=game.core ? shaftWidth:0
        return CGRect(x:roomX(span.left),y:Double(floor)*24,width:Double(span.width)*8+gap,height:24)
    }
    func screen(_ r:CGRect)->CGRect { CGRect(x:origin.x+r.minX*scale,y:bounds.height-origin.y-r.maxY*scale,width:r.width*scale,height:r.height*scale) }
    func screen(_ p:CGPoint)->CGPoint {CGPoint(x:origin.x+p.x*scale,y:bounds.height-origin.y-p.y*scale)}
    var visible:CGRect {CGRect(x:-origin.x/scale,y:-origin.y/scale,width:bounds.width/scale,height:bounds.height/scale)}
    func pushClip(_ rect:CGRect) { let intersection=screen(rect).intersection(clips.last ?? bounds);let r=intersection.isNull ? CGRect.zero:intersection;clips.append(r);commands.append(.clip(SceneRect(r))) }
    func popClip() {if !clips.isEmpty {clips.removeLast()};commands.append(.clip(clips.last.map(SceneRect.init))) }
    func fill(_ r:CGRect,_ hex:Int) {fill(r,color:SceneColor(hex:hex))}
    func fill(_ r:CGRect,color:SceneColor) {guard r.width>0,r.height>0 else{return};commands.append(.fill(SceneRect(screen(r)),color.rgba))}
    func line(_ a:CGPoint,_ b:CGPoint,_ color:Int) {let p=screen(a),q=screen(b);commands.append(.line(x1:p.x,y1:p.y,x2:q.x,y2:q.y,color:SceneColor(hex:color).rgba))}
    func outline(_ r:CGRect,color:Int,width:CGFloat) {
        fill(CGRect(x:r.minX,y:r.minY,width:r.width,height:width),color);fill(CGRect(x:r.minX,y:r.maxY-width,width:r.width,height:width),color)
        fill(CGRect(x:r.minX,y:r.minY,width:width,height:r.height),color);fill(CGRect(x:r.maxX-width,y:r.minY,width:width,height:r.height),color)
    }
    func label(_ text:String,at point:CGPoint,size:CGFloat,color:Int) {let p=screen(point);commands.append(.text(text,x:p.x,y:p.y-size*scale,size:size*scale,color:SceneColor(hex:color).rgba))}
    func drawImage(_ key:String,in rect:CGRect,flipped:Bool=false,opacity:Double=1,source:CGRect?=nil) {
        guard atlas.frames[key] != nil || key.hasPrefix("cloud.") else{return}
        commands.append(.image(key:key,source:source.map(SceneRect.init),destination:SceneRect(screen(rect)),flipped:flipped,opacity:opacity))
    }
    func actor(_ key:String,feet:CGPoint,height:CGFloat=11,flipped:Bool=false) {
        guard let rect=atlas.actorRect(key,feet:feet,height:height,flipped:flipped) else{return}
        drawImage(key,in:rect,flipped:flipped)
    }
    func roomArt(_ name:String,state:RoomArtState,in rect:CGRect) {
        let key="room.\(name).\(state.rawValue)"
        pushClip(rect);defer{popClip()}
        for slice in atlas.roomSlices(key,in:rect) {drawImage(key,in:slice.destination,source:slice.source)}
    }

    func animationPhase(_ game:TowerState)->Int {reducedMotion ? 0:Int(max(0,elapsed).truncatingRemainder(dividingBy:3600)*8)%4}
    func drawCityBehindRoom(_ r:CGRect,_ game:TowerState) {} // The continuous skyline is already beneath transparent room art.
    func roof(_ r:CGRect) {fill(r,0xBBBCA8);fill(CGRect(x:r.minX,y:r.maxY-1,width:r.width,height:1),0xF4ECCD);fill(CGRect(x:r.minX,y:r.minY,width:r.width,height:1),0x656454)}
}

extension TowerScene {
    func drawRoomSignals() {
        roomSignals=[]
        guard showsSignals else{return}
        let allocation=signalCoverage ?? game.neighborhoodCoverage
        for room in game.rooms {
            guard let signal=game.signal(for:room,coverage:allocation) else {continue}
            let r=screen(roomRect(room))
            let h=min(18,max(4,20*scale)),w=min(30,max(4,r.width-2))
            let badge=CGRect(x:r.midX-w/2,y:r.minY+scale,width:w,height:h)
            guard badge.intersects(bounds) else{continue}
            roomSignals.append(SceneRoomSignal(roomID:room.id,rect:SceneRect(badge),text:signal.text,mood:signal.mood))
            let color:UInt32
            switch signal.mood {
            case .angry,.alarmed:color=0xFFACA0FF
            case .annoyed,.worried:color=0xFFE298FF
            case .sad:color=0xBFD1EBFF
            case .relieved:color=0xBDE4B2FF
            case .busy:color=0xD4C8EBFF
            }
            commands.append(.fill(SceneRect(badge),0x34313AFF))
            commands.append(.fill(SceneRect(badge.insetBy(dx:1,dy:1)),color))
            if h>=12 && w>=16 {
                for x in [badge.minX+4,badge.minX+10] {commands.append(.fill(SceneRect(x:x,y:badge.minY+4,width:2,height:2),0x34313AFF))}
                commands.append(.fill(SceneRect(x:badge.minX+6,y:badge.minY+10,width:4,height:signal.mood == .alarmed ? 4:1),0x34313AFF))
            }
        }
    }
}

extension TowerScene {
    /// Platform controls use the same world geometry as scene generation.
    public func configure(game:TowerState,width:Double,height:Double) {
        self.game=game;bounds=CGRect(x:0,y:0,width:width,height:height)
    }
    public var worldOrigin:CGPoint {origin}
    public func worldRoomRect(_ room:Room)->CGRect {roomRect(room)}
    public func worldSpanRect(_ floor:Int)->CGRect {spanRect(floor)}
    public func worldRoomX(_ column:Int)->CGFloat {roomX(column)}
    public func worldPersonX(_ column:Double)->CGFloat {personX(column)}
    public func worldShaftX(_ index:Int)->CGFloat {shaftX(index)}
}
