import Foundation

public enum ElevatorKind:String,Codable,CaseIterable,Sendable {
    case standard,wide,express
    public var title:String { switch self { case .standard:return "Standard elevator";case .wide:return "Wide elevator";case .express:return "Express elevator" } }
    public var capacity:Int { switch self { case .standard:return 12;case .wide:return 24;case .express:return 32 } }
    public var width:Int { self == .standard ? 2 : 4 }
    public var speed:Double { self == .express ? 0.55 : 0.16 }
    public var cost:Int { switch self { case .standard:return 18000;case .wide:return 32000;case .express:return 60000 } }
    public var range:Int { self == .express ? 101 : 30 }
}
public enum TravelPhase:String,Codable,Sendable { case walkingToLift,waiting,riding,walkingToRoom }
public struct Traveler:Codable,Equatable,Identifiable,Sendable {
    public var id:Int
    public var roomID:Int
    public var floor:Int
    public var destination:Int
    public var x:Double
    public var destinationX:Double
    public var phase:TravelPhase
    public var route:[Int]
    public var elevatorID:Int?
    public var boardingElevatorID: Int? = nil
    public var waited:Int
    public init(id:Int,roomID:Int,floor:Int,destination:Int,x:Double,destinationX:Double,phase:TravelPhase = .walkingToLift,route:[Int] = [],elevatorID:Int? = nil,waited:Int = 0) {
        self.id=id;self.roomID=roomID;self.floor=floor;self.destination=destination;self.x=x;self.destinationX=destinationX;self.phase=phase;self.route=route;self.elevatorID=elevatorID;self.waited=waited
    }
}
extension Elevator {
    public var kind:ElevatorKind { type ?? .standard }
    public var bottom:Int { bottomFloor ?? 0 }
    public var doorsOpen:Bool { (doorTime ?? 0) > 0 }
    public var capacity:Int { kind.capacity }
    public var stops:[Int] {
        let rise = lobbyRise ?? 0
        return (bottom...topFloor).filter { floor in
            (floor <= 0 || floor > rise) && (kind != .express || floor == 0 || (floor > rise && (floor-rise) % 15 == 0))
        }
    }
}
extension TowerState {
    public var activeTravelers:[Traveler] { travelers ?? [] }
    public var queueCount:Int { activeTravelers.filter { $0.phase == .waiting }.count }
    public var completedTrips:Int { tripsCompleted ?? 0 }
    public func servedFloors(_ lift:Elevator)->[Int] {
        lift.stops.filter {
            let floor=span($0)
            if let column=lift.column { return floor.left <= column && column+lift.footprintWidth <= floor.right }
            return floor.left <= core && floor.right >= core
        }
    }
    public var reachableFloors:Set<Int> {
        var visited:Set<Int> = [0]
        var changed = true
        while changed {
            changed = false
            for lift in elevators where !visited.isDisjoint(with:servedFloors(lift)) {
                for floor in servedFloors(lift) where !visited.contains(floor) { visited.insert(floor); changed = true }
            }
        }
        return visited
    }
    public func route(from:Int,to:Int) -> [Int]? {
        if from == to { return [] }
        var seen:Set<Int> = [from]
        var queue:[(Int,[Int])] = [(from,[])]
        var index = 0
        let ordered = elevators.sorted { $0.kind == .express && $1.kind != .express }
        while index < queue.count {
            let (floor,path) = queue[index]; index += 1
            for lift in ordered where servedFloors(lift).contains(floor) {
                for stop in servedFloors(lift) where !seen.contains(stop) {
                    let next = path+[stop]
                    if stop == to { return next }
                    seen.insert(stop);queue.append((stop,next))
                }
            }
        }
        return nil
    }
    // Recomputing the nearest usable bank preserves old travelers without a new saved target field.
    private func boardingBank(for person:Traveler) -> Elevator? {
        guard let next=person.route.first else { return nil }
        let candidates = elevators.filter {
            let stops=servedFloors($0)
            return stops.contains(person.floor) && stops.contains(next)
        }
        if let assigned = candidates.first(where: { $0.id == person.boardingElevatorID }) { return assigned }
        return candidates.min {
            let left=abs(boardingColumn(for:$0)-person.x),right=abs(boardingColumn(for:$1)-person.x)
            return left == right ? $0.id < $1.id : left < right
        }
    }
    private func isWaiting(_ person:Traveler,for lift:Elevator) -> Bool {
        guard person.phase == .waiting,let next=person.route.first else { return false }
        let stops=servedFloors(lift)
        // Legacy banks intentionally share the same logical queue position.
        return (person.boardingElevatorID == nil || person.boardingElevatorID == lift.id) && stops.contains(person.floor) && stops.contains(next) && abs(person.x-boardingColumn(for:lift)) < 0.001
    }
    /// The next horizontal waypoint, shared by movement and sprite facing.
    /// A room's final column may be opposite the elevator needed for the current leg.
    public func walkingTarget(for person:Traveler) -> Double? {
        switch person.phase {
        case .walkingToLift, .waiting:
            return boardingBank(for:person).map { boardingColumn(for:$0) }
        case .walkingToRoom:
            return person.destinationX
        case .riding:
            return nil
        }
    }
    public mutating func requestTrip(roomID:Int,from:Int,to:Int) throws {
        guard let room = rooms.first(where: { $0.id == roomID }),from >= bottomFloor,from <= topFloor,to >= bottomFloor,to <= topFloor,from != to else { throw TowerError("Invalid passenger trip.") }
        guard room.incident?.isActive != true || room.incident?.kind == .rentArrears else { throw TowerError("This room is closed until its incident is resolved.") }
        guard let path = route(from:from,to:to) else { throw TowerError("No elevator route connects these floors.") }
        if travelers == nil { travelers = [] }
        let id = (nextTravelerID ?? 1); nextTravelerID=id+1
        let roomCenter = Double(room.slot)+Double(room.kind.width)/2
        let startX = from == 0 ? Double(span(0).left+1) : roomCenter
        let targetX = to == 0 ? Double(span(0).left+1) : roomCenter
        travelers?.append(Traveler(id:id,roomID:roomID,floor:from,destination:to,x:startX,destinationX:targetX,route:path))
    }
    mutating func updateTransit() {
        if travelers == nil { travelers=[] }
        if minute%12 == 0 && activeTravelers.count < 240 {
            let connected=reachableFloors
            let eligible = rooms.filter { $0.people > 0 && $0.floor != 0 && connected.contains($0.floor) && ($0.incident?.isActive != true || $0.incident?.kind == .rentArrears) }
            if !eligible.isEmpty {
                let batch=min(240-activeTravelers.count,max(1,min(6,population/400)))
                for offset in 0..<batch {
                    let room = eligible[(minute/3+day*7+offset*13)%eligible.count]
                    let outgoing = minute >= 1020 && minute < 1260 || (minute+offset)%9 == 0
                    try? requestTrip(roomID:room.id,from:outgoing ? room.floor : 0,to:outgoing ? 0 : room.floor)
                }
            }
        }
        var people = travelers ?? []
        var finished:Set<Int> = []
        // Reserve queues once per leg so people spread across cars without
        // changing their minds every frame or boarding a distant open car.
        var reserved: [Int: Int] = [:]
        for person in people {
            if let id = person.elevatorID ?? person.boardingElevatorID { reserved[id, default: 0] += 1 }
        }
        for i in people.indices.sorted(by: { people[$0].waited == people[$1].waited ? people[$0].id < people[$1].id : people[$0].waited > people[$1].waited })
            where people[i].phase == .walkingToLift || people[i].phase == .waiting {
            guard people[i].boardingElevatorID == nil, let next = people[i].route.first else { continue }
            let person = people[i]
            let candidates = elevators.filter { let stops = servedFloors($0); return stops.contains(person.floor) && stops.contains(next) }
            func cost(_ lift: Elevator) -> Double {
                let walk = abs(boardingColumn(for: lift)-person.x)/0.8
                let pickup = abs(lift.position-Double(person.floor))/lift.kind.speed + Double(lift.doorTime ?? 0)
                let service = 16 + 2*Double(abs(next-person.floor))/lift.kind.speed
                let queue = reserved[lift.id, default: 0]
                return walk + pickup + (Double(queue)/Double(lift.capacity) + Double(queue/lift.capacity))*service
            }
            if let best = candidates.min(by: { cost($0) == cost($1) ? $0.id < $1.id : cost($0) < cost($1) }) {
                people[i].boardingElevatorID = best.id
                reserved[best.id, default: 0] += 1
            }
        }
        for i in people.indices {
            switch people[i].phase {
            case .walkingToLift,.waiting:
                if people[i].route.isEmpty,let path=route(from:people[i].floor,to:people[i].destination) { people[i].route=path }
                guard let target=walkingTarget(for:people[i]) else { continue }
                let delta=target-people[i].x
                if people[i].phase == .waiting && abs(delta)<0.001 {
                    people[i].waited += 1
                } else {
                    people[i].phase = .walkingToLift
                    people[i].x += min(0.8,max(-0.8,delta))
                    if abs(delta)<=0.8 { people[i].x=target;people[i].phase = .waiting }
                }
            case .walkingToRoom:
                let delta = people[i].destinationX-people[i].x
                people[i].x += min(0.8,max(-0.8,delta))
                if abs(delta)<0.8 { finished.insert(people[i].id);tripsCompleted=(tripsCompleted ?? 0)+1 }
            case .riding: break
            }
        }
        for e in elevators.indices {
            var lift = elevators[e]
            let floor = Int(lift.position.rounded())
            if lift.doorsOpen {
                for i in people.indices where people[i].elevatorID == lift.id && people[i].route.first == floor {
                    people[i].floor=floor;people[i].elevatorID=nil;people[i].boardingElevatorID=nil;people[i].route.removeFirst();people[i].x=boardingColumn(for:lift)
                    guard let remaining = route(from: floor, to: people[i].destination) else { finished.insert(people[i].id); continue }
                    people[i].route = remaining
                    people[i].phase = remaining.isEmpty ? .walkingToRoom : .walkingToLift
                }
                var onboard = people.filter { $0.elevatorID == lift.id }.count
                let waiting = people.indices.filter { people[$0].floor == floor && isWaiting(people[$0],for:lift) }.sorted { people[$0].waited > people[$1].waited }
                for i in waiting where onboard < lift.capacity {
                    people[i].phase = .riding;people[i].boardingElevatorID=nil;people[i].elevatorID=lift.id;onboard += 1
                }
                lift.doorTime=max(0,(lift.doorTime ?? 0)-1)
                lift.passengers=onboard
            } else if let target = lift.targetFloor {
                let delta = Double(target)-lift.position
                if abs(delta) <= lift.kind.speed {
                    lift.position=Double(target);lift.targetFloor=nil;lift.doorTime=8
                } else { lift.direction=delta>0 ? 1 : -1;lift.position += Double(lift.direction)*lift.kind.speed }
            } else {
                let onboard = people.filter { $0.elevatorID == lift.id }
                var requests = Set(onboard.compactMap { $0.route.first })
                if onboard.count < lift.capacity {
                    for person in people where isWaiting(person,for:lift) {
                        requests.insert(person.floor)
                    }
                }
                if requests.contains(floor) { lift.doorTime=8 }
                else if !requests.isEmpty {
                    let forward = requests.filter { Double($0) * Double(lift.direction) > lift.position * Double(lift.direction) }
                    let choices = forward.isEmpty ? Array(requests) : Array(forward)
                    lift.targetFloor=choices.min { abs(Double($0)-lift.position) < abs(Double($1)-lift.position) }
                }
                lift.passengers=onboard.count
            }
            elevators[e]=lift
        }
        let roomIDs = Set(rooms.map(\.id))
        travelers=people.filter { !finished.contains($0.id) && roomIDs.contains($0.roomID) }
    }
}
