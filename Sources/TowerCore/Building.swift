import Foundation

public struct FloorSpan: Codable, Equatable, Sendable {
    public var left: Int
    public var right: Int
    public var width: Int { right-left }
    public init(_ left:Int,_ right:Int) { self.left = left; self.right = right }
    public func contains(_ column:Int,width:Int = 1) -> Bool { column >= left && column + width <= right }
}

extension TowerState {
    public static let maxFloorWidth = 256
    public static let minimumColumn = -128
    public static let maximumColumn = 256
    /// Geometric upper bound, not a separate gameplay quota. Shafts and larger rooms use space.
    public static var maximumRoomCapacity: Int {
        (maxFloor + maxBasementDepth) * (maxFloorWidth / RoomKind.allCases.filter { $0 != .lobby }.map(\.width).min()!)
    }
    public static var buildingLimitsDescription: String {
        "Up to \(maxFloor) floors above ground, \(maxBasementDepth) basement levels, and \(maxFloorWidth) cells per floor. Up to \(maximumRoomCapacity.formatted()) rooms using the smallest rooms, before elevator space."
    }

    public var core: Int { coreColumn ?? 32 }
    public func span(_ floor:Int) -> FloorSpan { floorSpans?[floor] ?? FloorSpan(0,64) }
    public var leftEdge: Int { (bottomFloor...topFloor).map { span($0).left }.min() ?? 0 }
    public var rightEdge: Int { (bottomFloor...topFloor).map { span($0).right }.max() ?? 64 }
    public static let cellCost = 150
    public func floorConstructionCost(floor:Int,from:Int,to:Int) throws -> Int {
        guard floor >= bottomFloor else { throw TowerError("Excavate this basement from the underground controls first.") }
        guard floor <= topFloor+1,floor <= Self.maxFloor else { throw TowerError(floor > Self.maxFloor ? "Maximum height reached: \(Self.maxFloor) floors above ground. Widen existing floors for more room space." : "Build directly above an existing floor.") }
        guard floor <= 0 || floor >= lobbyHeight else { throw TowerError("Expand the Grand Lobby from its ground floor; all four levels widen together.") }
        let left = min(from,to), right = max(from,to)+1
        guard left >= Self.minimumColumn,right <= Self.maximumColumn else { throw TowerError("Site boundary reached. Floors can be up to \(Self.maxFloorWidth) cells wide; expand toward the other side.") }
        let old = floor <= topFloor ? span(floor) : FloorSpan(left,left)
        let proposed = FloorSpan(min(old.left,left),max(old.right,right))
        guard proposed.width <= Self.maxFloorWidth else { throw TowerError("Maximum floor width reached: \(Self.maxFloorWidth) cells. Add a floor to create more room space (up to \(Self.maxFloor) floors).") }
        if floor > 0 {
            let below = span(floor-1)
            guard proposed.left >= below.left,proposed.right <= below.right else { throw TowerError("Widen the floor below first.") }
        }
        if floor < 0 {
            let above = span(floor+1)
            guard proposed.left >= above.left,proposed.right <= above.right else { throw TowerError("Widen the floor above first.") }
        }
        return (proposed.width-old.width)*Self.cellCost*(floor == 0 ? lobbyHeight : 1)
    }
    public mutating func constructFloor(floor:Int,from:Int,to:Int) throws {
        let cost = try floorConstructionCost(floor:floor,from:from,to:to)
        guard cash >= cost else { throw TowerError("This floor extension costs $\(cost.formatted()).") }
        if floorSpans == nil { floorSpans = Dictionary(uniqueKeysWithValues:(bottomFloor...topFloor).map { ($0,FloorSpan(0,64)) }) }
        let left = min(from,to), right = max(from,to)+1
        let old = floor <= topFloor ? span(floor) : FloorSpan(left,left)
        floorSpans?[floor] = FloorSpan(min(old.left,left),max(old.right,right))
        if floor == 0 { let lobby = span(0); for level in 1..<lobbyHeight { floorSpans?[level] = lobby } }
        topFloor = max(topFloor,floor); cash -= cost
    }
    private func towerWideningPlan(left:Bool,cells:Int) throws -> (spans:[Int:FloorSpan],cost:Int) {
        guard cells > 0,cells <= 32 else { throw TowerError("Choose 1–32 cells to extend.") }
        let target = left ? leftEdge-cells : rightEdge+cells-1
        var copy = self
        copy.floorSpans = Dictionary(uniqueKeysWithValues:(bottomFloor...topFloor).map { ($0,span($0)) })
        var total = 0
        // Plan bottom-up so every widened floor has support. Charge for actual
        // new cells, including the extra alignment of narrower upper floors.
        for floor in 0...topFloor where floor == 0 || floor >= lobbyHeight {
            total += try copy.floorConstructionCost(floor:floor,from:target,to:target)
            let old = copy.span(floor)
            copy.floorSpans?[floor] = FloorSpan(min(old.left,target),max(old.right,target+1))
            if floor == 0 { let lobby = copy.span(0); for level in 1..<lobbyHeight { copy.floorSpans?[level] = lobby } }
        }
        // Basements expand downward from the newly widened ground floor.
        if basementDepth > 0 {
            for floor in stride(from: -1, through: bottomFloor, by: -1) {
                total += try copy.floorConstructionCost(floor:floor,from:target,to:target)
                let old = copy.span(floor)
                copy.floorSpans?[floor] = FloorSpan(min(old.left,target),max(old.right,target+1))
            }
        }
        return (copy.floorSpans!,total)
    }
    public func towerWideningCost(left:Bool,cells:Int = 8) throws -> Int {
        try towerWideningPlan(left:left,cells:cells).cost
    }
    public mutating func widenTower(left:Bool,cells:Int = 8) throws {
        let plan = try towerWideningPlan(left:left,cells:cells)
        let count = topFloor+1+basementDepth
        guard cash >= plan.cost else { throw TowerError("Widening \(count) \(count == 1 ? "floor" : "floors"), including the lobby, costs $\(plan.cost.formatted()). You need $\((plan.cost-cash).formatted()) more.") }
        floorSpans = plan.spans
        cash -= plan.cost
    }
    @discardableResult public mutating func buildRow(_ kind:RoomKind,floor:Int,from:Int,to:Int) throws -> [Int] {
        var copy = self
        var ids:[Int] = []
        let left = min(from,to),right = max(from,to)
        for column in stride(from:left,through:right,by:kind.width) {
            if crossesLegacyCore(column:column,width:kind.width) { continue }
            if shaftOverlapsRoom(floor:floor,column:column,width:kind.width) { continue }
            if room(at:floor,slot:column) != nil { continue }
            ids.append(try copy.build(kind,floor:floor,slot:column))
        }
        guard !ids.isEmpty else {
            try validateBuild(kind, floor: floor, slot: left)
            throw TowerError("This space is already occupied.")
        }
        self = copy
        return ids
    }
}
