import Foundation

/// Optional on TowerState so existing towers can discover the new goals naturally.
public struct TowerProgressionState: Codable, Sendable {
    public var claimedAmbitionIDs: Set<String> = []
    public var achievedAmbitionIDs: Set<String>? = nil
    /// Simulation minutes at activation, including completed days; saving never resets a cooldown.
    public var abilityActivations: [String: Int] = [:]
    public init() {}
}

public struct TowerAmbitionProgress: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let reward: Int
    public let progress: Double
    public let isComplete: Bool
    public let isClaimed: Bool
    public let requiredLevel: Int
}

public enum TowerAbility: String, Codable, CaseIterable, Sendable {
    case openHouse, nightMarket

    public var title: String { self == .openHouse ? "Open House" : "Night Market" }
    public var detail: String {
        switch self {
        case .openHouse: return "Double the move-in rate for 12 game hours. Available every 2 days."
        case .nightMarket: return "Earn 50% more from basement food and shops for 6 game hours. Needs 2 operational basement businesses. Available every 2 days."
        }
    }
    public var symbol: String { self == .openHouse ? "megaphone.fill" : "moon.stars.fill" }
    public var requiredLevel: Int { self == .openHouse ? 2 : 3 }
    public var cost: Int { self == .openHouse ? 1500 : 250 }
    public var durationMinutes: Int { self == .openHouse ? 720 : 360 }
    public var cooldownMinutes: Int { 2880 }
}

extension TowerState {
    private var progressionMinute: Int {
        let (days, overflow) = max(0, day - 1).multipliedReportingOverflow(by: 1440)
        let (total, minuteOverflow) = days.addingReportingOverflow(minute)
        return overflow || minuteOverflow ? Int.max : total
    }

    private var operationalRooms: [Room] {
        let connected = reachableFloors
        return rooms.filter { $0.incident?.isActive != true && connected.contains($0.floor) }
    }

    public var ambitions: [TowerAmbitionProgress] {
        let operational = operationalRooms.filter { $0.kind != .lobby }
        let claimed = progression?.claimedAmbitionIDs ?? []
        let achieved = (progression?.achievedAmbitionIDs ?? []).union(claimed)
        let underground = operational.filter { $0.floor < 0 }
        let categories = Set(operational.map { $0.kind.definition.category.rawValue }).count
        let essentials = (operational.contains { $0.kind.providesFood } ? 1 : 0)
            + (operational.contains { $0.kind.providesRetail } ? 1 : 0)
        let district = (underground.contains { $0.kind.providesFood } ? 1 : 0)
            + (underground.contains { $0.kind.providesRetail } ? 1 : 0)
            + (underground.contains { $0.kind == .arcade } ? 1 : 0)
        let servicedHotels = operational.contains { $0.kind == .hotel } ? hotelServiceAssignments : [:]
        func goal(_ id: String, _ title: String, _ detail: String, _ reward: Int, _ current: Int, _ target: Int = 1, level: Int = 1) -> TowerAmbitionProgress {
            let isClaimed = claimed.contains(id)
            let isAchieved = achieved.contains(id)
            let progress = isAchieved ? 1 : min(1, max(0, Double(current) / Double(target)))
            return .init(id: id, title: title, detail: detail, reward: reward, progress: progress,
                         isComplete: isAchieved || current >= target, isClaimed: isClaimed, requiredLevel: level)
        }
        return [
            goal("first-business", "Open for business", "Connect your first income-earning room to an elevator.", 3000, operational.contains { $0.kind.dailyRent > 0 } ? 1 : 0),
            goal("daily-essentials", "Lunch, then a little shopping", "Keep a food venue and a shop connected and operational.", 4000, essentials, 2),
            goal("first-hundred", "Hello, neighbors!", "Welcome 100 people to your tower.", 5000, population, 100),
            goal("smooth-operator", "Going places", "Complete 100 elevator journeys.", 5000, completedTrips, 100),
            goal("below-the-street", "A whole new world below", "Open an income-earning basement room with elevator access.", 7000, underground.contains { $0.kind.dailyRent > 0 } ? 1 : 0, level: 2),
            goal("vertical-neighborhood", "A little of everything", "Operate rooms from 3 different categories, beyond the lobby.", 6000, categories, 3),
            goal("be-our-guest", "Be our guest", "Open a connected hotel suite with available housekeeping.", 8000, operational.contains { $0.kind == .hotel && servicedHotels[$0.id] != nil } ? 1 : 0, level: 2),
            goal("underground-district", "After-hours district", "Run basement food, retail, and an arcade together. While all operate, basement food and shops earn 15% more.", 12000, district, 3, level: 3),
            goal("bustling-tower", "The place to be", "Grow your vertical neighborhood to 500 people.", 10000, population, 500, level: 2),
            goal("skyline-icon", "On top of the world", "Reach level 5 and open a connected observation lounge.", 18000, earnedStars >= 5 && operational.contains { $0.kind == .observatory } ? 1 : 0, level: 5)
        ]
    }

    public var visibleAmbitions: [TowerAmbitionProgress] {
        let available = ambitions.filter { !$0.isClaimed && $0.requiredLevel <= earnedStars }
        return Array((available.filter(\.isComplete) + available.filter { !$0.isComplete }).prefix(3))
    }

    /// Achievements stay earned even if a tenant leaves or the player rebuilds a room.
    public mutating func evaluateAmbitions() {
        let reached = Set(ambitions.filter { $0.isComplete && $0.requiredLevel <= earnedStars }.map(\.id))
        let achieved = progression?.achievedAmbitionIDs ?? []
        guard !reached.isSubset(of: achieved) else { return }
        if progression == nil { progression = TowerProgressionState() }
        progression?.achievedAmbitionIDs = achieved.union(reached)
    }

    public mutating func claimAmbition(_ id: String) throws {
        guard let ambition = ambitions.first(where: { $0.id == id }) else { throw TowerError("That ambition is not available.") }
        guard !ambition.isClaimed else { throw TowerError("You already collected this ambition's reward.") }
        guard earnedStars >= ambition.requiredLevel, ambition.isComplete else { throw TowerError("Complete this ambition before collecting its reward.") }
        if progression == nil { progression = TowerProgressionState() }
        progression?.claimedAmbitionIDs.insert(id)
        cash += ambition.reward
        event("Ambition complete: \(ambition.title)! +$\(ambition.reward.formatted()).")
    }

    public func abilityRemainingMinutes(_ ability: TowerAbility) -> Int {
        guard let activated = progression?.abilityActivations[ability.rawValue], activated <= progressionMinute else { return 0 }
        return max(0, ability.durationMinutes - (progressionMinute - activated))
    }

    public func abilityCooldownMinutes(_ ability: TowerAbility) -> Int {
        guard let activated = progression?.abilityActivations[ability.rawValue], activated <= progressionMinute else { return 0 }
        return max(0, ability.cooldownMinutes - (progressionMinute - activated))
    }

    public func abilityBlocker(_ ability: TowerAbility) -> String? {
        if earnedStars < ability.requiredLevel { return "Unlocks at level \(ability.requiredLevel)." }
        if abilityRemainingMinutes(ability) > 0 { return "\(ability.title) is already active." }
        if abilityCooldownMinutes(ability) > 0 { return "Ready again in \(abilityCooldownMinutes(ability)) game minutes." }
        if ability == .nightMarket && operationalRooms.filter({ $0.floor < 0 && $0.kind.definition.category == .commerce }).count < 2 {
            return "Connect 2 operational basement food venues or shops first."
        }
        if cash < ability.cost { return "You need $\(ability.cost.formatted()) to host \(ability.title)." }
        return nil
    }

    public mutating func activateAbility(_ ability: TowerAbility) throws {
        if let blocker = abilityBlocker(ability) { throw TowerError(blocker) }
        if progression == nil { progression = TowerProgressionState() }
        let activated = progressionMinute
        progression?.abilityActivations[ability.rawValue] = activated
        cash -= ability.cost
        event("\(ability.title) is on! \(ability == .openHouse ? "Double move-ins for 12 hours." : "Basement food and shop income +50% for 6 hours.")")
    }

    public var undergroundDistrictActive: Bool {
        hasUndergroundDistrict(operationalRooms.filter { $0.floor < 0 })
    }

    private func hasUndergroundDistrict(_ rooms: [Room]) -> Bool {
        rooms.contains { $0.kind.providesFood } && rooms.contains { $0.kind.providesRetail } && rooms.contains { $0.kind == .arcade }
    }

    /// Compute once for the whole income pass, keeping large towers linear in room count.
    var progressionIncomeBonuses: [Int: Double] {
        let underground = operationalRooms.filter { $0.floor < 0 }
        let bonus = (hasUndergroundDistrict(underground) ? 0.15 : 0) + (abilityRemainingMinutes(.nightMarket) > 0 ? 0.5 : 0)
        guard bonus > 0 else { return [:] }
        return Dictionary(underground.filter { $0.kind.definition.category == .commerce }.map { ($0.id, bonus) }, uniquingKeysWith: { first, _ in first })
    }

    func validateProgression() throws {
        guard day > 0, day - 1 <= (Int.max - minute) / 1440 else { throw TowerError("Invalid progression clock.") }
        guard let progression else { return }
        let validIDs = Set(ambitions.filter { $0.requiredLevel <= earnedStars }.map(\.id))
        guard progression.claimedAmbitionIDs.isSubset(of: validIDs),
              (progression.achievedAmbitionIDs ?? []).isSubset(of: validIDs), progression.abilityActivations.allSatisfy({
            guard let ability = TowerAbility(rawValue: $0.key) else { return false }
            return ability.requiredLevel <= earnedStars && $0.value >= 0 && $0.value <= progressionMinute
        }) else { throw TowerError("Invalid saved ambitions or ability timers.") }
    }
}
