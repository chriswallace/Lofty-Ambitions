import XCTest
import TowerArt
import TowerCore

final class LobbyCompositionTests: XCTestCase {
    let bounds = CGRect(x: -64, y: 0, width: 512, height: 96)
    func testFocalAreaNeverCrossesShaftsOrRepeats() {
        for widths in [[24.0],[40,40],[24,40,24,40]] {
            let shafts = widths.enumerated().map { i,w in CGRect(x: CGFloat(i)*80,y: 0,width: w,height: 240) }
            let layout = LobbyComposition(bounds: bounds, shafts: shafts)
            if let feature = layout.feature {
                XCTAssertTrue(bounds.contains(feature))
                XCTAssertEqual(feature.height,96)
                for shaft in shafts { XCTAssertTrue(feature.intersection(shaft).isEmpty) }
            }
            for bay in layout.clearBays {
                XCTAssertGreaterThan(bay.width,0)
                for shaft in shafts { XCTAssertTrue(bay.intersection(shaft).isEmpty) }
            }
            XCTAssertEqual(layout.clearBays.reduce(0) { $0+$1.width } + widths.reduce(0,+),bounds.width)
        }
    }
    func testMergesTouchingShaftsAndIgnoresUpperBanks() {
        let shafts = [CGRect(x:0,y:0,width:24,height:96),CGRect(x:24,y:0,width:40,height:96),CGRect(x:100,y:96,width:24,height:120)]
        let layout = LobbyComposition(bounds:bounds,shafts:shafts)
        XCTAssertEqual(layout.clearBays.count,2)
        XCTAssertEqual(layout.clearBays[1].minX,64)
        XCTAssertEqual(layout.feature?.width,252)
    }
    func testNarrowAndFullyOccupiedLobbiesDoNotSqueezeFurniture() {
        let narrow=CGRect(x:0,y:0,width:64,height:96)
        XCTAssertNil(LobbyComposition(bounds:narrow,shafts:[]).feature)
        let blocked=LobbyComposition(bounds:narrow,shafts:[narrow])
        XCTAssertTrue(blocked.clearBays.isEmpty);XCTAssertNil(blocked.feature)
    }
    func testBoardingPointIsInLandingBesideCabin() throws {
        var game=TowerState.newGame();game.cash=500000
        try game.addFloor()
        for (i,kind) in ElevatorKind.allCases.enumerated() {
            try game.addElevator(kind,at:i*10,from:0,to:1)
            let lift=game.elevators.last!
            let point=game.boardingColumn(for:lift)
            XCTAssertGreaterThan(point,Double(i*10+kind.width))
            XCTAssertLessThan(point,Double(i*10+lift.footprintWidth))
        }
    }
}
