import Foundation

public enum RoomCategory: String, CaseIterable, Sendable {
    case work, homes, commerce, services, leisure, structure
    public var title: String {
        switch self {
        case .work: return "Workplaces"
        case .homes: return "Homes & hotels"
        case .commerce: return "Food & shopping"
        case .services: return "Services"
        case .leisure: return "Leisure"
        case .structure: return "Structure"
        }
    }
}

public struct RoomDefinition: Identifiable, Sendable {
    public let kind: RoomKind
    public let title: String
    public let symbol: String
    public let category: RoomCategory
    public let cost: Int
    public let width: Int
    public let capacity: Int
    public let dailyRent: Int
    public let upkeep: Int
    public let requiredStars: Int
    public let detail: String
    public let keywords: String
    public var id: RoomKind { kind }

    public func buildBlocker(stars: Int, cash: Int) -> String? {
        if stars < requiredStars { return "Unlocks at level \(requiredStars)" }
        if cash < cost { return "Need $\((cost-cash).formatted()) more" }
        return nil
    }
}

/// A room's balance, browsing information, and build details have one source.
/// Add its stable RoomKind identifier and artwork alongside a definition here;
/// the sidebar, category filters, and Rooms menu discover it automatically.
public enum RoomCatalog {
    public static let definitions: [RoomDefinition] = [
        .init(kind: .lobby, title: "Lobby", symbol: "building.columns", category: .structure,
              cost: 0, width: 64, capacity: 0, dailyRent: 0, upkeep: 100, requiredStars: 1,
              detail: "The front door to your vertical neighborhood.", keywords: "entrance"),
        .init(kind: .office, title: "Office", symbol: "desktopcomputer", category: .work,
              cost: 12000, width: 9, capacity: 40, dailyRent: 1200, upkeep: 180, requiredStars: 1,
              detail: "Steady weekday rent. Workers need lunch and a quick lift.", keywords: "business desks workplace"),
        .init(kind: .apartment, title: "Apartment", symbol: "sofa", category: .homes,
              cost: 18000, width: 4, capacity: 24, dailyRent: 1500, upkeep: 180, requiredStars: 1,
              detail: "A place to call home. Residents value shops and quiet surroundings.", keywords: "residential housing tenants"),
        .init(kind: .luxuryApartment, title: "Luxury apartment", symbol: "sparkles", category: .homes,
              cost: 65000, width: 12, capacity: 16, dailyRent: 5200, upkeep: 700, requiredStars: 4,
              detail: "Spacious residences with premium rents. Residents value quiet, shops, and good lifts.", keywords: "residential housing tenants luxury upscale home"),
        .init(kind: .restaurant, title: "Restaurant", symbol: "fork.knife", category: .commerce,
              cost: 16000, width: 16, capacity: 32, dailyRent: 1350, upkeep: 180, requiredStars: 1,
              detail: RoomKind.restaurant.serviceDescription!, keywords: "food dining lunch cafe"),
        .init(kind: .shop, title: "Shop", symbol: "bag", category: .commerce,
              cost: 10000, width: 20, capacity: 20, dailyRent: 1000, upkeep: 180, requiredStars: 1,
              detail: RoomKind.shop.serviceDescription!, keywords: "retail store market shopping"),
        .init(kind: .hotel, title: "Hotel suite", symbol: "bed.double", category: .homes,
              cost: 24000, width: 16, capacity: 28, dailyRent: 2400, upkeep: 180, requiredStars: 2,
              detail: "Premium daily income. Needs housekeeping within 5 floors.", keywords: "guests overnight accommodation"),
        .init(kind: .housekeeping, title: "Housekeeping", symbol: "sparkles", category: .services,
              cost: 8000, width: 15, capacity: 0, dailyRent: 0, upkeep: 240, requiredStars: 2,
              detail: "Services hotel suites within 5 floors. One team supports 6 suites.", keywords: "cleaning staff laundry"),
        .init(kind: .security, title: "Security", symbol: "shield.lefthalf.filled", category: .services,
              cost: 14000, width: 16, capacity: 0, dailyRent: 0, upkeep: 350, requiredStars: 3,
              detail: "Makes the whole tower feel safer. Needed for level 4.", keywords: "safety guards staff"),
        .init(kind: .garden, title: "Sky garden", symbol: "leaf", category: .leisure,
              cost: 12000, width: 12, capacity: 0, dailyRent: 0, upkeep: 120, requiredStars: 3,
              detail: "A pocket of green. Improves happiness throughout the tower.", keywords: "park plants recreation green space"),
        .init(kind: .cafe, title: "Café", symbol: "cup.and.saucer", category: .commerce,
              cost: 14000, width: 10, capacity: 18, dailyRent: 1150, upkeep: 180, requiredStars: 2,
              detail: RoomKind.cafe.serviceDescription!, keywords: "coffee breakfast food kissaten"),
        .init(kind: .arcade, title: "Arcade", symbol: "gamecontroller", category: .leisure,
              cost: 26000, width: 16, capacity: 32, dailyRent: 2300, upkeep: 360, requiredStars: 3,
              detail: "Adds 2% tower happiness when connected and operational.", keywords: "games entertainment neon"),
        .init(kind: .fitness, title: "Fitness studio", symbol: "figure.strengthtraining.traditional", category: .leisure,
              cost: 32000, width: 14, capacity: 28, dailyRent: 2600, upkeep: 400, requiredStars: 4,
              detail: "Adds 3% tower happiness when connected and operational.", keywords: "gym health exercise wellness"),
        .init(kind: .observatory, title: "Observation lounge", symbol: "binoculars", category: .leisure,
              cost: 60000, width: 24, capacity: 40, dailyRent: 4200, upkeep: 650, requiredStars: 5,
              detail: "Adds 4% tower happiness when connected and operational.", keywords: "observatory view telescope tourism skyline"),
        .init(kind: .ramen, title: "Ramen bar", symbol: "fork.knife", category: .commerce,
              cost: 20000, width: 12, capacity: 24, dailyRent: 1800, upkeep: 260, requiredStars: 2,
              detail: RoomKind.ramen.serviceDescription!, keywords: "food dining japanese noodles kitchen"),
        .init(kind: .bookshop, title: "Bookshop", symbol: "books.vertical", category: .commerce,
              cost: 18000, width: 8, capacity: 14, dailyRent: 1400, upkeep: 200, requiredStars: 3,
              detail: RoomKind.bookshop.serviceDescription!, keywords: "retail shopping books reading store"),
        .init(kind: .coworking, title: "Coworking studio", symbol: "person.2", category: .work,
              cost: 38000, width: 12, capacity: 56, dailyRent: 3400, upkeep: 500, requiredStars: 4,
              detail: "Shared desks for growing businesses. High capacity needs good lifts.", keywords: "workspace business desks shared startup"),
        .init(kind: .spa, title: "Spa", symbol: "drop", category: .leisure,
              cost: 48000, width: 18, capacity: 24, dailyRent: 4000, upkeep: 600, requiredStars: 5,
              detail: "Adds 3% tower happiness when connected and operational.", keywords: "wellness relaxation massage bath sauna")
    ]
    private static let byKind = Dictionary(uniqueKeysWithValues: definitions.map { ($0.kind, $0) })
    public static func definition(for kind: RoomKind) -> RoomDefinition { byKind[kind]! }
    public static var categories: [RoomCategory] {
        RoomCategory.allCases.filter { category in definitions.contains { $0.kind != .lobby && $0.category == category } }
    }
    public static func search(query: String, category: RoomCategory? = nil) -> [RoomDefinition] {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).split(whereSeparator: \.isWhitespace)
        return definitions.filter { room in
            guard room.kind != .lobby, category == nil || room.category == category else { return false }
            let text = "\(room.title) \(room.detail) \(room.category.rawValue) \(room.keywords) \(room.kind.canBuildUnderground ? "underground basement" : "above ground")"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return words.allSatisfy { text.contains($0) }
        }.sorted { $0.requiredStars < $1.requiredStars }
    }
}
