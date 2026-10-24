import Foundation

public enum DemolitionTarget: Equatable, Sendable {
    case room(Int), elevator(Int)
}

public struct DemolitionQuote: Sendable {
    public let title: String
    public let refund: Int
    public let consequences: String
    public let disconnectedRooms: Int
}

extension TowerState {
    public func demolitionQuote(for target: DemolitionTarget) throws -> DemolitionQuote {
        switch target {
        case .room(let id):
            guard let room = rooms.first(where: { $0.id == id }) else { throw TowerError("Select a room first.") }
            guard room.kind != .lobby else { throw TowerError("The lobby is the entrance to your tower and cannot be removed.") }
            guard room.incident?.isActive != true else { throw TowerError("Resolve this room’s incident before demolishing it.") }
            let occupancy = room.people > 0 ? "\(room.people) occupants will leave this room. " : ""
            return DemolitionQuote(title: "Delete \(room.kind.title) on floor \(room.floor)?", refund: room.kind.cost / 2,
                consequences: "Unit \(room.id) · \(room.kind.width) cells wide.\n\(occupancy)Its income and services will stop. The floor remains available to rebuild.", disconnectedRooms: 0)
        case .elevator(let id):
            guard let lift = elevators.first(where: { $0.id == id }) else { throw TowerError("Select an elevator first.") }
            let before = reachableFloors
            var after = self; after.elevators.removeAll { $0.id == id }
            let remaining = after.reachableFloors
            let disconnected = rooms.filter { $0.kind != .lobby && before.contains($0.floor) && !remaining.contains($0.floor) }.count
            let impact = disconnected > 0 ? "\(disconnected) \(disconnected == 1 ? "room will" : "rooms will") lose elevator access to the lobby." : "All currently connected rooms keep elevator access."
            return DemolitionQuote(title: "Delete \(lift.kind.title.lowercased()) \(id)?", refund: lift.kind.cost / 2,
                consequences: "Entire shaft · Floors \(lift.bottom == 0 ? "G" : String(lift.bottom))–\(lift.topFloor).\n\(impact) Passengers will be rerouted where possible.", disconnectedRooms: disconnected)
        }
    }
}
