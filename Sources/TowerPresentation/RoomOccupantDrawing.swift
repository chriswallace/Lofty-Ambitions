import Foundation
import TowerCore
import TowerArt

extension TowerScene {
    func drawRoomOccupants(_ room: Room, in rect: CGRect, game: TowerState) {
        let reduced = reducedMotion
        let people = RoomActivity.occupants(in:room,minute:game.minute,elapsed:elapsed,reducedMotion:reduced,
                                          worldX: { self.atlas.roomPoint(CGPoint(x:$0,y:0),name:room.artworkName,in:rect).x })
        for (index,person) in people.enumerated() {
            let point = atlas.roomPoint(person.position, name:room.artworkName, in:rect)
            let key: String
            switch person.pose {
            case .working: key = "roomActor.\(person.character).0"
            case .reading: key = "roomActor.\(person.character).1"
            case .resting: key = "roomActor.\(person.character).2"
            case .standing: key = "civilian.\(person.character).0"
            case .walking:
                let frame = ActorMotion.walkingFrame(distance:person.walkDistance,identity:room.id &* 31 &+ index)
                key = "civilian.\(person.character).\(frame)"
            }
            actor(key,feet:point,height:10,flipped:person.facingLeft)
        }
    }
}
