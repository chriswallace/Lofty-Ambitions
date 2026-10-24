import Foundation

public struct TowerLevel: Sendable {
    public let number: Int
    public let title: String
    public let population: Int
    public let happiness: Double
    public let facility: RoomKind?
    public var grant: Int { number == 1 ? 0 : number * 10000 }
    public var unlocks: [RoomDefinition] { RoomCatalog.definitions.filter { $0.kind != .lobby && $0.requiredStars == number } }
    public var unlockTitles: [String] {
        var titles = unlocks.map(\.title)
        if number == TowerState.grandLobbyLevel { titles.append("Grand Lobby upgrade") }
        if number >= 2 { titles.append("B\(number - 1) excavation permit") }
        titles += TowerAbility.allCases.filter { $0.requiredLevel == number }.map(\.title)
        return titles
    }

    public static let all: [TowerLevel] = [
        .init(number: 1, title: "Newcomer", population: 0, happiness: 0, facility: nil),
        .init(number: 2, title: "Neighborhood", population: 220, happiness: 0.65, facility: nil),
        .init(number: 3, title: "Destination", population: 500, happiness: 0.70, facility: .housekeeping),
        .init(number: 4, title: "City landmark", population: 900, happiness: 0.75, facility: .security),
        .init(number: 5, title: "Skyline icon", population: 1400, happiness: 0.80, facility: .garden)
    ]
}

public struct LevelRequirement: Sendable {
    public let text: String
    public let complete: Bool
    public let progress: Double
}

extension TowerState {
    // The existing saved star rating is the permanent level. Older towers retain
    // their earned unlocks without a second counter or a save migration.
    public var level: TowerLevel { TowerLevel.all[min(4, max(0, earnedStars - 1))] }
    public var nextLevel: TowerLevel? { TowerLevel.all.first { $0.number == earnedStars + 1 } }
    public var levelRequirements: [LevelRequirement] {
        guard let next = nextLevel else { return [] }
        var requirements = [
            LevelRequirement(text: "\(population.formatted()) / \(next.population.formatted()) people", complete: population >= next.population, progress: min(1, Double(population) / Double(next.population))),
            LevelRequirement(text: "\(Int(happiness * 100))% / \(Int(next.happiness * 100))% happiness", complete: happiness >= next.happiness, progress: min(1, happiness / next.happiness))
        ]
        if let facility = next.facility {
            let available = rooms.contains { $0.kind == facility && $0.incident?.isActive != true && isConnected($0.floor) }
            requirements.append(.init(text: "Operational \(facility.title.lowercased()) with elevator access", complete: available, progress: available ? 1 : 0))
        }
        return requirements
    }
    public var levelProgress: Double {
        let requirements = levelRequirements
        return requirements.isEmpty ? 1 : requirements.map(\.progress).reduce(0, +) / Double(requirements.count)
    }
    mutating func evaluateLevel() {
        guard let next = nextLevel, levelRequirements.allSatisfy(\.complete) else { return }
        earnedStars = next.number
        cash += next.grant
        event("Level \(next.number): \(next.title)! Unlocked \(next.unlockTitles.joined(separator: ", ")). $\(next.grant.formatted()) development grant.")
    }
}
