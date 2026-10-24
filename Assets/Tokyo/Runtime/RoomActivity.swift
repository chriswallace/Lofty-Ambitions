import Foundation
import TowerCore

public enum RoomOccupantPose: Equatable {
    case working, reading, resting, standing, walking
}

public struct RoomOccupant: Equatable {
    public let character: Int
    /// Normalized coordinates in the source room, with Y measured from the floor.
    public let position: CGPoint
    public let pose: RoomOccupantPose
    public let facingLeft: Bool
    /// Distance traveled along this stroll, in world points, for a planted walking gait.
    public let walkDistance: CGFloat
}

/// Furniture anchors belong to each interior, rather than a row of evenly spaced people.
/// This is ambient population sampling, independent of the elevator journey simulation.
public enum RoomActivity {
    /// Upright feet follow the visible floor in each interior's source artwork.
    public static func floorY(for room: Room) -> CGFloat {
        // Furniture depth and the front beam vary by artwork. Keep walkers on
        // the clear floor strip in front of beds, chairs, shelves, and equipment.
        switch room.artworkName {
        case "luxuryApartment": return 0.055
        case "coworking", "ramen", "spa": return 0.045
        case "bookshop": return 0.0425
        case "fitness": return 0.065
        case "hotel": return 0.07
        default: return 0.085
        }
    }

    public static func occupants(in room: Room, minute: Int, elapsed: Double, reducedMotion: Bool = false,
                                 worldX: ((CGFloat) -> CGFloat)? = nil) -> [RoomOccupant] {
        guard room.people > 0, RoomArtState.state(for: room, minute: minute) == .open,
              room.incident?.isActive != true || room.incident?.kind == .rentArrears else { return [] }
        let seats: [CGPoint]
        let office = room.kind == .office || room.kind == .coworking
        let home = room.kind.isApartment || room.kind == .hotel
        switch room.artworkName {
        case "office": seats = [CGPoint(x:0.24,y:0.11),CGPoint(x:0.41,y:0.11),CGPoint(x:0.59,y:0.11),CGPoint(x:0.76,y:0.11)]
        case "office2": seats = [CGPoint(x:0.27,y:0.11),CGPoint(x:0.45,y:0.11),CGPoint(x:0.63,y:0.11)]
        case "office3": seats = [CGPoint(x:0.28,y:0.11),CGPoint(x:0.47,y:0.11),CGPoint(x:0.66,y:0.11)]
        case "coworking": seats = [CGPoint(x:0.22,y:0.10),CGPoint(x:0.40,y:0.10),CGPoint(x:0.62,y:0.10)]
        case "apartment", "apartment2": seats = [CGPoint(x:0.32,y:0.19)]
        case "apartment3": seats = [CGPoint(x:0.28,y:0.19)]
        case "luxuryApartment": seats = [CGPoint(x:0.19,y:0.17),CGPoint(x:0.50,y:0.11)]
        case "hotel": seats = [CGPoint(x:0.65,y:0.10)]
        default:
            let count = min(5,max(1,room.kind.width / 2))
            seats = (0..<count).map { CGPoint(x:0.15 + Double($0) * 0.55 / Double(max(1,count-1)),y:0.085) }
        }
        let count = min(seats.count,max(1,Int(ceil(room.occupancy * Double(seats.count)))))
        let time = reducedMotion ? 0 : max(0,elapsed.isFinite ? elapsed : 0)
        let mappedX = worldX ?? { $0 * CGFloat(room.kind.width * 8) }
        let ground = floorY(for:room)
        return (0..<count).map { index in
            let identity = UInt64(truncatingIfNeeded:room.id)
            let character = Int((identity % 4 + UInt64(index)) % 4)
            // Stagger each person and each room. A 60s cycle also survives the clock's wrap.
            let phase = (time + Double(((identity % 60) * 17 + UInt64(index) * 23) % 60)).truncatingRemainder(dividingBy:60)
            let seat = seats[index]
            let resting = room.kind.isApartment && index == 0 && (minute < 420 || minute >= 1320)
            let furniturePose: RoomOccupantPose = office ? .working : resting ? .resting : home ? .reading : .standing
            let furniture = RoomOccupant(character:character,
                                         position:CGPoint(x:seat.x,y:resting ? seat.y + 0.15 : furniturePose == .standing ? ground : seat.y),
                                         pose:furniturePose,facingLeft:false,walkDistance:0)
            if reducedMotion || resting || phase < 44 { return furniture }

            // Give each person a lane around their furniture. Six points of clearance
            // between adjacent lanes prevents neighbors from walking through each other.
            let left = index > 0 ? (seats[index-1].x + seat.x)/2 : max(0.08,seat.x-0.22)
            let right = index+1 < seats.count ? (seat.x + seats[index+1].x)/2 : min(0.84,seat.x+0.22)
            let start = mappedX(seat.x)
            let leftSpace = start-mappedX(left)-3
            let rightSpace = mappedX(right)-start-3
            var goesLeft = seat.x >= 0.5
            if (goesLeft ? leftSpace : rightSpace) < 1 { goesLeft.toggle() }
            let distance = min(10,goesLeft ? leftSpace : rightSpace)
            guard distance.isFinite, distance >= 1 else { return furniture }
            let boundary = goesLeft ? left : right
            // These furniture lanes lie in the room's center stretch. Mapping the
            // endpoints keeps a stroll the same speed in compact and wide interiors.
            let destination = seat.x + (boundary-seat.x) * distance / abs(mappedX(boundary)-start)
            let duration = Double(distance)/4
            var step = phase-44
            let x: CGFloat
            let pose: RoomOccupantPose
            let facingLeft: Bool
            let traveled: CGFloat
            if step < 0.45 {
                x=seat.x; pose = .standing; facingLeft=goesLeft; traveled=0
            } else if step < 0.45+duration {
                step -= 0.45
                x=seat.x+(destination-seat.x)*CGFloat(step/duration)
                pose = .walking; facingLeft=goesLeft; traveled=CGFloat(step)*4
            } else if step < 0.45+duration+0.65 {
                x=destination; pose = .standing; facingLeft = !goesLeft; traveled=distance
            } else if step < 0.45+duration*2+0.65 {
                step -= 0.45+duration+0.65
                x=destination+(seat.x-destination)*CGFloat(step/duration)
                pose = .walking; facingLeft = !goesLeft; traveled=distance+CGFloat(step)*4
            } else if step < 0.45+duration*2+0.65+0.45 {
                x=seat.x; pose = .standing; facingLeft = !goesLeft; traveled=distance*2
            } else {
                return furniture
            }
            return RoomOccupant(character:character,position:CGPoint(x:x,y:ground),pose:pose,
                                facingLeft:facingLeft,walkDistance:traveled)
        }
    }
}
