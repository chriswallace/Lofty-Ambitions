import XCTest
@testable import TowerCore

final class RoomCatalogTests: XCTestCase {
    func testCatalogCoversEverySaveKindExactlyOnceAndKeepsExistingEconomy() {
        XCTAssertEqual(Set(RoomCatalog.definitions.map(\.kind)), Set(RoomKind.allCases))
        XCTAssertEqual(RoomCatalog.definitions.count, RoomKind.allCases.count)
        let expected: [(RoomKind, Int, Int, Int, Int, Int, Int)] = [
            (.lobby, 0, 64, 0, 0, 100, 1), (.office, 12000, 9, 40, 1200, 180, 1),
            (.apartment, 18000, 4, 24, 1500, 180, 1), (.restaurant, 16000, 16, 32, 1350, 180, 1),
            (.shop, 10000, 20, 20, 1000, 180, 1), (.hotel, 24000, 16, 28, 2400, 180, 2),
            (.housekeeping, 8000, 15, 0, 0, 240, 2), (.security, 14000, 16, 0, 0, 350, 3),
            (.garden, 12000, 12, 0, 0, 120, 3)
        ]
        for (kind, cost, width, people, rent, upkeep, stars) in expected {
            XCTAssertEqual(kind.cost, cost); XCTAssertEqual(kind.width, width)
            XCTAssertEqual(kind.capacity, people); XCTAssertEqual(kind.dailyRent, rent)
            XCTAssertEqual(kind.upkeep, upkeep); XCTAssertEqual(kind.requiredStars, stars)
        }
    }
    func testSearchMatchesWordsAndCategoriesWithoutHidingLockedRooms() {
        XCTAssertEqual(RoomCatalog.search(query: "  HOTEL  ").map(\.kind), [.hotel, .housekeeping])
        XCTAssertEqual(RoomCatalog.search(query: "suite premium").map(\.kind), [.hotel])
        XCTAssertEqual(RoomCatalog.search(query: "", category: .services).map(\.kind), [.housekeeping, .security])
        XCTAssertTrue(RoomCatalog.search(query: "office", category: .homes).isEmpty)
        XCTAssertTrue(RoomCatalog.search(query: "no such room").isEmpty)
        XCTAssertFalse(RoomCatalog.search(query: "").contains { $0.kind == .lobby })
    }
    func testBuildAvailabilityExplainsUnlockAndFundsButDoesNotHideDetails() {
        let hotel = RoomCatalog.definition(for: .hotel)
        XCTAssertNotNil(hotel.buildBlocker(stars: 1, cash: 100000))
        XCTAssertNotNil(hotel.buildBlocker(stars: 2, cash: 23999))
        XCTAssertNil(hotel.buildBlocker(stars: 2, cash: 24000))
        XCTAssertFalse(hotel.detail.isEmpty)
        XCTAssertEqual(hotel.category, .homes)
    }
}
