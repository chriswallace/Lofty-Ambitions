import Foundation

extension RoomKind {
    public var canBuildUnderground: Bool {
        definition.category == .commerce || definition.category == .services || self == .arcade || self == .fitness || self == .spa
    }
}

extension TowerState {
    public static let maxBasementDepth = 4
    public var basementDepth: Int { max(0, basementFloorCount ?? 0) }
    public var bottomFloor: Int { -basementDepth }
    public var basementPermitDepth: Int { min(Self.maxBasementDepth, max(0, stars - 1)) }
    public var nextBasementCost: Int { 12000 + basementDepth * 6000 }
    public static func floorLabel(_ floor: Int) -> String { floor == 0 ? "G" : floor < 0 ? "B\(-floor)" : String(floor) }

    public var excavationBlocker: String? {
        if basementDepth >= Self.maxBasementDepth { return "All four underground levels have been excavated." }
        if basementDepth >= basementPermitDepth { return "\(Self.floorLabel(bottomFloor - 1)) excavation unlocks at level \(basementDepth + 2)." }
        if cash < nextBasementCost { return "Need $\((nextBasementCost - cash).formatted()) more to excavate." }
        return nil
    }

    public mutating func excavateBasement() throws {
        if let blocker = excavationBlocker { throw TowerError(blocker) }
        let newFloor = bottomFloor - 1
        let newSpan = span(bottomFloor)
        let cost = nextBasementCost
        if floorSpans == nil { floorSpans = Dictionary(uniqueKeysWithValues: (bottomFloor...topFloor).map { ($0, span($0)) }) }
        floorSpans?[newFloor] = newSpan
        basementFloorCount = basementDepth + 1
        cash -= cost
        event("\(Self.floorLabel(newFloor)) excavated! Build shops, dining, services, or indoor leisure, then connect an elevator to bring it to life.")
    }

    func validateUnderground() throws {
        let depth = basementFloorCount ?? 0
        guard (0...Self.maxBasementDepth).contains(depth), depth <= basementPermitDepth else { throw TowerError("Invalid underground excavation depth.") }
        if depth > 0 {
            for floor in bottomFloor..<0 {
                guard floorSpans?[floor] != nil else { throw TowerError("An underground floor is missing its excavation.") }
            }
        }
        guard floorSpans?.keys.allSatisfy({ $0 >= bottomFloor }) ?? true else { throw TowerError("An underground floor lies below the excavation.") }
    }
}
