import Foundation
import TowerCore
import TowerArt

extension TowerScene {
    func drawRoom(_ room:Room,_ r:CGRect,_ game:TowerState) {
        let state = RoomArtState.state(for:room,minute:game.minute)
        if room.floor < 0 {
            drawBasementWall(r)
        } else {
            drawCityBehindRoom(r,game)
            if state != .destroyed && state != .rebuilding { drawWindowGlass(r) }
        }
        let restingHours = game.minute < 420 || game.minute >= 1320
        let displayState: RoomArtState = room.kind.isApartment && state == .open && restingHours ? .closed : state
        roomArt(room.artworkName,state:displayState,in:r)
        if !game.isConnected(room.floor) {fill(r,color:SceneColor(hex:0,alpha:0.3))}
        guard state == .open, room.incident?.isActive != true || room.incident?.kind == .rentArrears else {return}
        // Some interiors have a shallow foreground floor above the bottom beam.
        pushClip(r.insetBy(dx:1,dy:0.5))
        defer {popClip()}
        let phase = animationPhase(game)
        if room.kind == .housekeeping || room.kind == .security || room.kind.providesFood {
            let role = room.kind.providesFood ? 0 : room.kind == .housekeeping ? 1 : 3
            actor("staff.\(role).\(phase)",feet:CGPoint(x:r.minX+r.width*0.3,y:r.minY+2),height:11)
        }
        drawRoomOccupants(room,in:r,game:game)
    }
    public func travelerMotionTargets(_ game: TowerState) -> [ActorMotion.Target] {
        var queues:[String:Int]=[:]
        let interiors = Dictionary(grouping:game.rooms.filter { $0.kind != .lobby },by:\.floor)
        return game.activeTravelers.filter { $0.phase != .riding }.compactMap { p in
            var x=personX(p.x)
            // Unfurnished corridors use the shaft's surface. Inside an interior,
            // follow that artwork's floor so a shallow floorboard never looks like air.
            var y=CGFloat(p.floor)*24+2.5
            if p.phase == .waiting {
                let key="\(p.floor):\(p.boardingElevatorID.map(String.init) ?? String(p.x))"
                let n=queues[key,default:0];queues[key]=n+1
                guard let point=waitingPosition(for:p,ordinal:n,game) else { return nil }
                x=point.x;y=point.y
            }
            if let room = interiors[p.floor]?.first(where: {
                let rect = roomRect($0)
                return x >= rect.minX && x < rect.maxX
            }) {
                let rect = roomRect(room)
                y = rect.minY+RoomActivity.floorY(for:room)*rect.height
            }
            let target=game.walkingTarget(for:p)
            return ActorMotion.Target(id:p.id,floor:p.floor,position:CGPoint(x:x,y:y),facingLeft:(target ?? p.x) < p.x)
        }
    }
    public func synchronizeTravelerMotion(_ game: TowerState) {
        travelerMotion.synchronize(travelerMotionTargets(game))
    }
    func drawPeople(_ game:TowerState) {
        synchronizeTravelerMotion(game)
        let reducedMotion = reducedMotion
        for p in game.activeTravelers where p.phase != .riding {
            guard let presentation = travelerMotion.pose(for:p.id) else { continue }
            let pose = presentation.isWalking && !reducedMotion ? ActorMotion.walkingFrame(distance:presentation.distance,identity:p.id) : 0
            person(at:presentation.position,id:p.id,waiting:p.phase == .waiting && p.waited>40,pose:pose,facingLeft:presentation.facingLeft)
        }
    }
    func person(at p:CGPoint,id:Int,waiting:Bool,pose:Int=0,facingLeft:Bool=false) {
        actor("civilian.\(abs(id)%4).\(pose)",feet:p,height:10,flipped:facingLeft)
        if waiting {fill(CGRect(x:p.x-0.5,y:p.y+11,width:1,height:2),0xFF715F)}
    }
    func drawBasementFoundation(_ game:TowerState) {
        guard game.basementDepth > 0 else {return}
        for level in game.bottomFloor..<0 {
            let r=spanRect(level)
            // The exposed retaining wall makes the excavated edge legible against soil.
            for x in [r.minX-5,r.maxX] {
                fill(CGRect(x:x,y:r.minY,width:5,height:r.height),0x4E5752)
                fill(CGRect(x:x+1,y:r.minY,width:3,height:r.height),0x89928A)
                for y in stride(from:r.minY+4,to:r.maxY,by:8) {
                    fill(CGRect(x:x+1,y:y,width:3,height:1),0x5B655F)
                }
            }
            if level == game.bottomFloor {
                fill(CGRect(x:r.minX-5,y:r.minY-6,width:r.width+10,height:6),0x4E5752)
                fill(CGRect(x:r.minX-4,y:r.minY-3,width:r.width+8,height:2),0x89928A)
            }
        }
    }
    func drawBasementWall(_ r:CGRect) {
        // An opaque service wall replaces the skyline behind basement artwork.
        fill(r,0x777F79)
        fill(CGRect(x:r.minX,y:r.maxY-4,width:r.width,height:4),0x535F59)
        for x in stride(from:r.minX+2,to:r.maxX,by:16) {
            fill(CGRect(x:x,y:r.minY+3,width:min(14,r.maxX-x),height:15),0x858D84)
            fill(CGRect(x:x,y:r.minY+3,width:1,height:15),0x6B756D)
        }
        fill(CGRect(x:r.minX,y:r.maxY-3,width:r.width,height:1),0xB59A69)
        for x in stride(from:r.minX+10,to:r.maxX-3,by:40) {
            fill(CGRect(x:x-1,y:r.maxY-6,width:8,height:3),0x4B5751)
            fill(CGRect(x:x,y:r.maxY-5,width:6,height:1),0xF4DFA5)
        }
    }
}
