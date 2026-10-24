import Foundation

public enum RoomStyle: Int, Codable, CaseIterable, Sendable {
    case one, two, three
    public var title: String { String(rawValue + 1) }
}

extension RoomKind {
    public var hasStyles: Bool { self == .office || self == .apartment }
    public var isApartment: Bool { self == .apartment || self == .luxuryApartment }
}

extension Room {
    /// Older towers keep their original interiors until the player changes them.
    public var effectiveStyle: RoomStyle { style ?? .one }
    public var artworkName: String {
        kind.hasStyles && effectiveStyle != .one ? "\(kind.rawValue)\(effectiveStyle.rawValue + 1)" : kind.rawValue
    }
}

extension TowerState {
    func nextRoomStyle(_ kind: RoomKind, floor: Int, slot: Int) -> RoomStyle? {
        guard kind.hasStyles else { return nil }
        let neighbors = Set(rooms.filter {
            $0.kind == kind && $0.floor == floor && ($0.slot + $0.kind.width == slot || slot + kind.width == $0.slot)
        }.map(\.effectiveStyle))
        let choices = RoomStyle.allCases.filter { !neighbors.contains($0) }
        // Saved city seed and construction ID make the draw repeatable after loading.
        var draw = citySeed ^ (UInt64(truncatingIfNeeded: nextID) &* 0x9E3779B97F4A7C15)
        draw ^= UInt64(truncatingIfNeeded: floor) &* 0xBF58476D1CE4E5B9
        draw ^= UInt64(truncatingIfNeeded: slot) &* 0x94D049BB133111EB
        draw = (draw ^ (draw >> 30)) &* 0xBF58476D1CE4E5B9
        draw ^= draw >> 27
        return choices[Int(draw % UInt64(choices.count))]
    }

    public mutating func setRoomStyle(_ id: Int, style: RoomStyle) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }), rooms[index].kind.hasStyles else {
            throw TowerError("Choose an office or apartment to change its interior.")
        }
        guard rooms[index].incident?.isActive != true else {
            throw TowerError("Resolve this room’s incident before changing its interior.")
        }
        rooms[index].style = style
    }
}
