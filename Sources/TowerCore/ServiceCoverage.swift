import Foundation

public enum NeighborhoodService: String, CaseIterable, Hashable, Sendable {
    case food, shops
    public var title: String { self == .food ? "Food" : "Shops" }
    public var symbol: String { self == .food ? "fork.knife" : "bag" }
    public var floorRange: Int { self == .food ? 4 : 6 }
    public var defaultRoom: RoomKind { self == .food ? .restaurant : .shop }
    public var horizontalRange: Int { 48 }
}

extension RoomKind {
    public var needsNeighborhoodServices: Bool {
        [.office, .coworking, .apartment, .luxuryApartment, .hotel].contains(self)
    }
    public var neighborhoodService: NeighborhoodService? {
        providesFood ? .food : providesRetail ? .shops : nil
    }
    public var serviceCapacity: Int {
        switch self {
        case .restaurant: return 240
        case .cafe: return 120
        case .ramen: return 180
        case .shop: return 320
        case .bookshop: return 140
        default: return 0
        }
    }
    public var serviceDescription: String? {
        guard let service = neighborhoodService else { return nil }
        return "Serves \(serviceCapacity) neighbors within \(service.floorRange) floors and \(service.horizontalRange) cells."
    }
}

public struct ServiceAmount: Equatable, Sendable {
    public var demand: Double = 0
    public var served: Double = 0
    public var nearbyVenues: Int = 0
    public var prospectiveCoverage: Double = 0
    public var ratio: Double { min(1, max(0, demand > 0 ? served / demand : prospectiveCoverage)) }
    public var percent: Int { Int((ratio * 100 + 0.000001).rounded(.down)) }
    public var isShort: Bool { demand > 0 && served + 0.000001 < demand }
    public var explanation: String { nearbyVenues == 0 ? "No service within reach" : isShort || (demand == 0 && ratio < 1) ? "Nearby venues need more capacity" : "Covered by nearby venues" }
}

public struct VenueServiceLoad: Equatable, Sendable {
    public let service: NeighborhoodService
    public let capacity: Int
    public let served: Double
    public let operational: Bool
}

public struct NeighborhoodCoverage: Equatable, Sendable {
    public var rooms: [Int: [NeighborhoodService: ServiceAmount]] = [:]
    public var venues: [Int: VenueServiceLoad] = [:]
    public var floors: [Int: [NeighborhoodService: ServiceAmount]] = [:]
    public init() {}
    public func shortage(for id: Int) -> NeighborhoodService? {
        NeighborhoodService.allCases.filter { rooms[id]?[$0]?.isShort == true }
            .min { (rooms[id]?[$0]?.ratio ?? 1) < (rooms[id]?[$1]?.ratio ?? 1) }
    }
}

extension TowerState {
    /// Derived from geometry and current occupants; no allocation state is saved.
    public var neighborhoodCoverage: NeighborhoodCoverage {
        var result = NeighborhoodCoverage()
        let connected = reachableFloors
        let consumers = rooms.filter { $0.kind.needsNeighborhoodServices && connected.contains($0.floor) &&
            ($0.incident?.isActive != true || $0.incident?.kind == .rentArrears) }.sorted { $0.id < $1.id }
        for service in NeighborhoodService.allCases {
            let venues = rooms.filter { $0.kind.neighborhoodService == service }.sorted { $0.id < $1.id }
            let operational = venues.map { connected.contains($0.floor) && $0.incident?.isActive != true }
            var spare = venues.indices.map { operational[$0] ? Double(venues[$0].kind.serviceCapacity) : 0 }
            let demand = consumers.map { Double($0.people) }
            var unmet = demand
            var flows = Array(repeating: [Int: Double](), count: venues.count)
            func distance(_ consumer: Room, _ venue: Room) -> Double {
                abs(Double(consumer.slot) + Double(consumer.kind.width)/2 - Double(venue.slot) - Double(venue.kind.width)/2)
            }
            let candidates = consumers.map { consumer in
                venues.indices.filter { operational[$0] && abs(consumer.floor - venues[$0].floor) <= service.floorRange && distance(consumer, venues[$0]) <= Double(service.horizontalRange) }
                    .sorted { a, b in
                        let da = Double(abs(consumer.floor - venues[a].floor)) + distance(consumer, venues[a])/8
                        let db = Double(abs(consumer.floor - venues[b].floor)) + distance(consumer, venues[b])/8
                        return da == db ? venues[a].id < venues[b].id : da < db
                    }
            }
            let epsilon = 0.0000001
            // Proportional rounds share shortages fairly, favoring nearer venues.
            for _ in 0...venues.count {
                var proposals = Array(repeating: [(Int, Double)](), count: venues.count)
                for c in consumers.indices where unmet[c] > epsilon {
                    let available = candidates[c].filter { spare[$0] > epsilon }
                    let weights = available.map { 1 / (1 + Double(abs(consumers[c].floor - venues[$0].floor)) + distance(consumers[c], venues[$0])/8) }
                    let total = weights.reduce(0, +)
                    for (offset, v) in available.enumerated() { proposals[v].append((c, unmet[c] * weights[offset] / total)) }
                }
                var progress = 0.0
                for v in venues.indices {
                    let requested = proposals[v].reduce(0) { $0 + $1.1 }
                    guard requested > epsilon else { continue }
                    let fraction = min(1, spare[v] / requested)
                    for (c, amount) in proposals[v] {
                        let allocated = amount * fraction
                        flows[v][c, default: 0] += allocated
                        unmet[c] = max(0, unmet[c] - allocated)
                        spare[v] = max(0, spare[v] - allocated)
                        progress += allocated
                    }
                }
                if progress < epsilon { break }
            }
            // Residual paths reassign already served demand so overlapping catchments
            // cannot strand usable capacity behind a full venue.
            for start in consumers.indices where unmet[start] > epsilon {
                while unmet[start] > epsilon {
                    var queue = [start], cursor = 0
                    var roomParent: [Int: Int] = [:], venueParent: [Int: Int] = [:]
                    var seenRooms: Set<Int> = [start]
                    var terminal: Int?
                    search: while cursor < queue.count {
                        let c = queue[cursor]; cursor += 1
                        for v in candidates[c] where venueParent[v] == nil {
                            venueParent[v] = c
                            if spare[v] > epsilon { terminal = v; break search }
                            for donor in flows[v].keys.sorted() where flows[v][donor, default: 0] > epsilon && !seenRooms.contains(donor) {
                                seenRooms.insert(donor); roomParent[donor] = v; queue.append(donor)
                            }
                        }
                    }
                    guard let end = terminal else { break }
                    var amount = min(unmet[start], spare[end]), v = end
                    while let c = venueParent[v], c != start {
                        let previous = roomParent[c]!
                        amount = min(amount, flows[previous][c, default: 0]); v = previous
                    }
                    v = end
                    while let c = venueParent[v] {
                        flows[v][c, default: 0] += amount
                        if c == start { break }
                        let previous = roomParent[c]!
                        flows[previous][c, default: 0] -= amount; v = previous
                    }
                    spare[end] -= amount; unmet[start] -= amount
                }
            }
            for v in venues.indices {
                result.venues[venues[v].id] = VenueServiceLoad(service: service, capacity: venues[v].kind.serviceCapacity, served: flows[v].keys.sorted().reduce(0) { $0 + flows[v][$1, default: 0] }, operational: operational[v])
            }
            for c in consumers.indices {
                let room = consumers[c]
                let prospective = min(1, candidates[c].reduce(0) { $0 + spare[$1] } / Double(room.kind.capacity))
                let amount = ServiceAmount(demand: demand[c], served: demand[c] - unmet[c], nearbyVenues: candidates[c].count, prospectiveCoverage: prospective)
                result.rooms[room.id, default: [:]][service] = amount
                if demand[c] > 0 {
                    var floor = result.floors[room.floor]?[service] ?? ServiceAmount()
                    floor.demand += amount.demand; floor.served += amount.served; floor.nearbyVenues += amount.nearbyVenues
                    result.floors[room.floor, default: [:]][service] = floor
                }
            }
        }
        return result
    }
    public func serviceWarning(for room: Room, coverage: NeighborhoodCoverage) -> RoomSignal? {
        guard let service = coverage.shortage(for: room.id), let amount = coverage.rooms[room.id]?[service] else { return nil }
        return RoomSignal(mood: room.happiness < 0.4 ? .sad : .annoyed, text: "\(service.title): \(amount.percent)% covered · \(amount.nearbyVenues == 0 ? "nothing nearby" : "more capacity needed")", symbol: service.symbol)
    }
}
