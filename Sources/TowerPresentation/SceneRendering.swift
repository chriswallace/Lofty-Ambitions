import Foundation
import TowerCore
import TowerArt

extension TowerScene {
    public func render(game:TowerState,width:Double,height:Double,elapsed:Double)->[SceneCommand] {
        guard width.isFinite,height.isFinite,width>0,height>0,scale.isFinite,scale>0 else{return []}
        self.game=game;bounds=CGRect(x:0,y:0,width:width,height:height)
        self.elapsed=elapsed.isFinite ? max(0,elapsed):0
        let delta=previousElapsed.map{max(0,min(0.25,self.elapsed-$0))} ?? 0
        previousElapsed=self.elapsed
        if interpolatesMotion {travelerMotion.advance(seconds:delta,isRunning:!reducedMotion)}
        commands.removeAll(keepingCapacity:true);clips.removeAll(keepingCapacity:true)
        drawCity(game)
        let gy=origin.y
        // The landscape is in screen space vertically and fixed to the shared street.
        screenFill(CGRect(x:0,y:height-gy-6,width:width,height:14),0xB6B8AA)
        screenFill(CGRect(x:0,y:height-gy+8,width:width,height:4),0x59623D)
        screenFill(CGRect(x:0,y:height-gy+12,width:width,height:max(0,gy-12)),0x8B7662)
        for x in stride(from:Double(0),to:width,by:16) {
            for y in stride(from:Double(3),to:max(3,gy-12),by:14) {
                screenFill(CGRect(x:x+Double(Int(y)%7),y:height-y-1,width:2,height:1),0x705F50)
            }
        }
        drawBasementFoundation(game)
        let roomsByFloor=Dictionary(grouping:game.rooms.filter{$0.kind != .lobby},by:\.floor)
        for level in game.bottomFloor...game.topFloor where level<=0 || level>=game.lobbyHeight {
            var r=spanRect(level)
            if level==0 {r.size.height=Double(game.lobbyHeight)*24}
            guard r.intersects(visible) else{continue}
            if level==0 && game.lobbyHeight==4 {drawGrandLobby(game,in:r)}
            else if level==0 {
                for x in stride(from:r.minX,to:r.maxX,by:256) {
                    pushClip(CGRect(x:x,y:0,width:min(256,r.maxX-x),height:r.height))
                    let tile=CGRect(x:x,y:0,width:256,height:24)
                    drawWindowGlass(tile);roomArt(game.effectiveLobbyStyle.artwork,state:.open,in:tile)
                    popClip()
                }
            } else {drawCorridors(game,floor:level,in:r,rooms:roomsByFloor[level,default:[]])}
            if level==0 {
                pushClip(CGRect(x:r.minX,y:r.minY,width:r.width,height:2))
                for x in stride(from:r.minX,to:r.maxX,by:24) {drawImage("structure.0.0",in:CGRect(x:x,y:r.minY,width:24,height:2))}
                popClip()
            }
            fill(CGRect(x:r.minX,y:r.maxY-1,width:r.width,height:1),0xE1E0CD)
            let name=level==0 && game.lobbyHeight==4 ? "G–3":TowerState.floorLabel(level)
            if level<0 {fill(CGRect(x:r.minX-25,y:r.minY+6,width:19,height:12),0x3A413D)}
            label(name,at:CGPoint(x:r.minX-(level<0 ? 23:20),y:r.minY+8),size:8,color:level<0 ? 0xF0DBAB:0x202020)
        }
        for room in game.rooms where room.kind != .lobby {
            let r=roomRect(room);guard r.intersects(visible) else{continue}
            drawRoom(room,r,game);drawIncidentEffects(room,r,game)
        }
        drawElevators(game);drawPeople(game)
        for level in game.bottomFloor...game.topFloor where level<=0 || level>=game.lobbyHeight {
            var r=spanRect(level);if level==0 {r.size.height=Double(game.lobbyHeight)*24}
            guard r.intersects(visible) else{continue}
            fill(CGRect(x:r.minX-1,y:r.minY,width:1,height:r.height),0x55564C)
            fill(CGRect(x:r.maxX,y:r.minY,width:1,height:r.height),0x55564C)
            guard level>=0 else{continue}
            let next=level==0 ? game.lobbyHeight:level+1
            let above=next<=game.topFloor ? spanRect(next):.zero
            if next>game.topFloor || above.minX>r.minX {roof(CGRect(x:r.minX,y:r.maxY,width:next>game.topFloor ? r.width:above.minX-r.minX,height:3))}
            if next<=game.topFloor && above.maxX<r.maxX {roof(CGRect(x:above.maxX,y:r.maxY,width:r.maxX-above.maxX,height:3))}
        }
        drawFireResponse(game);drawCoverage(game);drawRoomSignals()
        return commands
    }
    func screenFill(_ r:CGRect,_ hex:Int,alpha:Double=1) {commands.append(.fill(SceneRect(r),SceneColor(hex:hex,alpha:alpha).rgba))}

    func drawCity(_ game:TowerState) {
        let lighting=CityLighting.layers(at:game.minute)
        let palettes:[String:(Int,Int,Double)] = ["city.day":(0xC9E6ED,0x448BCD,0.9),"city.sunrise":(0xF9CFAB,0x799ACE,0.75),"city.sunset":(0xF6B589,0x565A9B,0.65),"city.night":(0x233B62,0x0B183B,0.2)]
        // Flat pixel bands approximate the native linear sky without a graphics dependency.
        var cloudOpacity=0.0
        for layer in lighting {
            let p=palettes[layer.key]!
            for y in stride(from:Double(0),to:bounds.height,by:4) {
                let t=min(1,max(0,(bounds.height-y-origin.y)/scale/1200))
                func channel(_ shift:Int)->Int {let a=Double((p.0>>shift)&255),b=Double((p.1>>shift)&255);return Int((a+(b-a)*t).rounded())}
                let hex=channel(16)<<16|channel(8)<<8|channel(0)
                screenFill(CGRect(x:0,y:y,width:bounds.width,height:min(4,bounds.height-y)),hex,alpha:layer.opacity)
            }
            cloudOpacity += (p.2-cloudOpacity)*layer.opacity
        }
        for cloud in CityLayout.clouds(in:visible,seconds:reducedMotion ? 0:(ambientElapsed ?? elapsed),seed:game.citySeed) {
            drawImage("cloud.\(cloud.seed)",in:cloud.rect,opacity:cloudOpacity*cloud.opacity)
        }
        let sizes=CityBuildings.styles.enumerated().map {i,style->CGSize in
            guard let frame=atlas.frames["building.day.\(i)"] else{return .zero}
            let h=style.floors*18+14
            return CGSize(width:h*Double(frame.rect[2])/Double(frame.rect[3]),height:h)
        }
        guard sizes.allSatisfy({$0.width>0}),visible.minY<(sizes.map(\.height).max() ?? 0),visible.maxY>0 else{return}
        if cityStreet?.seed != game.citySeed || cityStreet?.sizes != sizes {cityStreet=CityLayout.Street(sizes:sizes,seed:game.citySeed)}
        guard let street=cityStreet else{return}
        for building in street.buildings(in:visible.minX...visible.maxX) {
            for layer in lighting {
                let time=layer.key.replacingOccurrences(of:"city.",with:"")
                drawImage("building.\(time).\(building.art)",in:building.rect,opacity:layer.opacity)
            }
        }
    }
    func drawWindowGlass(_ r:CGRect) {
        fill(r,color:SceneColor(hex:0xE9F4FF,alpha:0.19));pushClip(r);defer{popClip()}
        for x in stride(from:r.minX+5,to:r.maxX,by:19) {
            for step in 0..<4 {fill(CGRect(x:x+Double(step),y:r.minY+10+Double(step)*2,width:1,height:2),color:SceneColor(hex:0xFFFFFF,alpha:0.17))}
        }
    }
    func drawCoverage(_ game:TowerState, labels:Bool=true) {
        guard let service=coverage else{return}
        var guides=coverageGuides
        if guides.isEmpty,let id=coverageRoomID,let room=game.rooms.first(where:{$0.id==id}),room.kind.neighborhoodService==service {
            guides=[SceneCoverageGuide(kind:room.kind,floor:room.floor,slot:room.slot)]
        }
        let connected=game.reachableFloors
        for guide in guides {
            let center=Double(guide.slot)+Double(guide.kind.width)/2
            for floor in max(game.bottomFloor,guide.floor-service.floorRange)...min(game.topFloor,guide.floor+service.floorRange) where floor<0 || floor>=game.lobbyHeight {
                guard connected.contains(floor) else{continue}
                let span=game.span(floor),left=max(Double(span.left),center-Double(service.horizontalRange)),right=min(Double(span.right),center+Double(service.horizontalRange)),core=Double(game.core)
                for (a,b,offset) in [(left,min(right,core),CGFloat(0)),(max(left,core),right,shaftWidth)] where b>a {
                    let band=CGRect(x:CGFloat(a)*8+offset,y:CGFloat(floor)*24+1,width:CGFloat(b-a)*8,height:22)
                    fill(band,color:SceneColor(hex:0x6DAFE4,alpha:0.14))
                    let dash=4/scale,gap=3/scale,w=1/scale
                    for x in stride(from:band.minX,to:band.maxX,by:dash+gap) {
                        for y in [band.minY,band.maxY-w] {fill(CGRect(x:x,y:y,width:min(dash,band.maxX-x),height:w),0xD4EDFF)}
                    }
                    for y in stride(from:band.minY,to:band.maxY,by:dash+gap) {
                        for x in [band.minX,band.maxX-w] {fill(CGRect(x:x,y:y,width:w,height:min(dash,band.maxY-y)),0xD4EDFF)}
                    }
                }
            }
        }
        let allocation=game.neighborhoodCoverage
        for room in game.rooms {
            guard let mark=SceneCoverageMark.mark(for:room,service:service,allocation:allocation) else{continue}
            let color=mark.color,label=mark.label
            let r=roomRect(room).insetBy(dx:0.5,dy:0.5)
            fill(r,color:SceneColor(hex:color,alpha:0.38));outline(r,color:color,width:max(0.6,2/scale))
            let p=screen(r)
            if labels,p.height>=20,p.width>Double(label.count)*7+8 {
                let width=Double(label.count)*7+8
                screenFill(CGRect(x:p.midX-width/2,y:p.maxY-20,width:width,height:17),color)
                commands.append(.text(label,x:p.midX-width/2+4,y:p.maxY-18,size:11,color:0xFFFFFFFF))
            }
        }
    }
}

public struct SceneCoverageGuide {
    public var kind:RoomKind
    public var floor:Int
    public var slot:Int
    public init(kind:RoomKind,floor:Int,slot:Int) {self.kind=kind;self.floor=floor;self.slot=slot}
}
extension TowerScene {
    public func renderCoverage(game:TowerState,width:Double,height:Double,labels:Bool=true)->[SceneCommand] {
        configure(game:game,width:width,height:height)
        commands.removeAll(keepingCapacity:true);clips.removeAll(keepingCapacity:true)
        drawCoverage(game,labels:labels)
        return commands
    }
}
