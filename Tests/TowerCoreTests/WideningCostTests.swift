import XCTest
@testable import TowerCore

final class WideningCostTests: XCTestCase {
    func testQuoteScalesWithFloorsAndMatchesChargeInBothDirections() throws {
        for floors in [1, 5, 10] {
            for left in [true, false] {
                var game = TowerState.newGame(); game.cash = 1000000
                for _ in 1..<floors { try game.addFloor() }
                let before = game.cash
                let quote = try game.towerWideningCost(left: left)
                XCTAssertEqual(quote, floors * 1200)
                XCTAssertEqual(game.cash, before, "Quoting must not charge")
                try game.widenTower(left: left)
                XCTAssertEqual(before - game.cash, quote)
                XCTAssertTrue((0..<floors).allSatisfy { game.span($0).width == 72 })
            }
        }
    }
    func testTaperedTowerQuotesEveryAddedCellOnEachSide() throws {
        var game = TowerState.newGame(); game.topFloor = 2
        game.floorSpans = [0: FloorSpan(-8,72), 1: FloorSpan(0,64), 2: FloorSpan(8,56)]
        XCTAssertEqual(try game.towerWideningCost(left: true), (8 + 16 + 24) * 150)
        XCTAssertEqual(try game.towerWideningCost(left: false), (8 + 16 + 24) * 150)
    }
    func testInsufficientCashReportsTotalAndDoesNotPartiallyExpand() throws {
        var game = TowerState.demoTower(); game.cash = 5999
        let spans = game.floorSpans
        XCTAssertEqual(try game.towerWideningCost(left: false), 6000)
        XCTAssertThrowsError(try game.widenTower(left: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("6,000"))
            XCTAssertTrue(error.localizedDescription.contains("5 floors"))
        }
        XCTAssertEqual(game.cash, 5999); XCTAssertEqual(game.floorSpans, spans)
        game.cash = 6000; try game.widenTower(left: false)
        XCTAssertEqual(game.cash, 0)
    }
    func testQuoteRejectsWidthAndSiteLimitsWithoutChanges() throws {
        var game = TowerState.newGame(); game.floorSpans = [0: FloorSpan(-128,128)]
        let spans = game.floorSpans
        XCTAssertThrowsError(try game.towerWideningCost(left: true))
        XCTAssertThrowsError(try game.towerWideningCost(left: false))
        XCTAssertThrowsError(try game.towerWideningCost(left: true, cells: 0))
        XCTAssertThrowsError(try game.widenTower(left: false))
        XCTAssertEqual(game.floorSpans, spans)
    }
}
