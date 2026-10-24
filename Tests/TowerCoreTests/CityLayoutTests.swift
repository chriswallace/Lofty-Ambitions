import XCTest
import Foundation
import TowerArt
import TowerCore

final class CityLayoutTests: XCTestCase {
    let sizes = (0..<8).map { CGSize(width: 55+$0*7, height: 90+$0*20) }

    func testNewGamesGetSeparateSeedsAndSavesPreserveThem() throws {
        let first = TowerState.newGame(), second = TowerState.newGame()
        XCTAssertNotNil(first.scenerySeed)
        XCTAssertNotEqual(first.scenerySeed, second.scenerySeed)
        var loaded = try JSONDecoder().decode(TowerState.self, from: JSONEncoder().encode(first)).validated()
        loaded.advance(minutes: 720)
        XCTAssertEqual(loaded.scenerySeed, first.scenerySeed)
        XCTAssertEqual(CityLayout.buildings(in: -500...1500, sizes: sizes, seed: loaded.citySeed),
                       CityLayout.buildings(in: -500...1500, sizes: sizes, seed: first.citySeed))
    }

    func testLegacySaveGetsARepeatableSeedBeforeItIsResaved() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TowerState.newGame())) as! [String: Any]
        json.removeValue(forKey: "scenerySeed")
        let data = try JSONSerialization.data(withJSONObject: json)
        let a = try JSONDecoder().decode(TowerState.self, from: data).validated()
        let b = try JSONDecoder().decode(TowerState.self, from: data).validated()
        XCTAssertNotNil(a.scenerySeed)
        XCTAssertEqual(a.citySeed, b.citySeed)
    }

    func testCityIsSeededAndIndependentOfViewportOrVisitOrder() {
        let wide = CityLayout.buildings(in: -1600...2400, sizes: sizes, seed: 123)
        let narrow = CityLayout.buildings(in: 100...700, sizes: sizes, seed: 123)
        XCTAssertEqual(narrow, wide.filter { $0.rect.maxX > 100 && $0.rect.minX < 700 })
        XCTAssertEqual(wide, CityLayout.buildings(in: -1600...2400, sizes: sizes, seed: 123))
        XCTAssertNotEqual(wide, CityLayout.buildings(in: -1600...2400, sizes: sizes, seed: 456))
        for pair in zip(wide, wide.dropFirst()) {
            XCTAssertNotEqual(pair.0.art, pair.1.art, "No identical adjacent facades, including group boundaries")
            XCTAssertGreaterThanOrEqual(pair.1.rect.minX, pair.0.rect.maxX)
            XCTAssertLessThan(pair.1.rect.minX-pair.0.rect.maxX, 25)
        }
        XCTAssertEqual(Set(wide.map(\.art)).count, 8)
    }

    func testCloudsHaveIndividualShapesAndStaySparseAcrossAWideSky() {
        let rect = CGRect(x: -1000, y: 0, width: 3000, height: 1500)
        let clouds = CityLayout.clouds(in: rect, seconds: 20, seed: 123)
        XCTAssertEqual(clouds, CityLayout.clouds(in: rect, seconds: 20, seed: 123))
        XCTAssertNotEqual(clouds, CityLayout.clouds(in: rect, seconds: 20, seed: 456))
        XCTAssertGreaterThan(clouds.count, 4)
        XCTAssertLessThan(clouds.count, 25)
        XCTAssertEqual(Set(clouds.map(\.seed)).count, clouds.count)
        XCTAssertGreaterThan(Set(clouds.map { $0.rect.width }).count, 4)
        XCTAssertGreaterThan(Set(clouds.map { $0.rect.height }).count, 4)
        XCTAssertTrue(clouds.allSatisfy { (100...280).contains($0.rect.width) && (24...90).contains($0.rect.height) })
    }

    func testCloudsDoNotReshuffleWithViewportOrElapsedTime() {
        let wideRect = CGRect(x: -4500, y: -200, width: 9000, height: 2700)
        let narrowRects = [CGRect(x: -2300, y: 110, width: 760, height: 650),
                           CGRect(x: 80, y: 430, width: 1250, height: 850)]
        for seconds in [0.0, 20.0, 255.9, 256.1, 864_000.0] {
            let wide = CityLayout.clouds(in: wideRect, seconds: seconds, seed: 123)
            for narrow in narrowRects {
                XCTAssertEqual(CityLayout.clouds(in: narrow, seconds: seconds, seed: 123),
                               wide.filter { $0.rect.intersects(narrow) }, "Culling must not depend on the camera at \(seconds)s")
            }
        }
    }

    func testCloudCullingIncludesShapeOverhangAtNegativeCoordinatesAfterLongDrift() throws {
        let seconds = 864_000.0
        let view = CGRect(x: -6000, y: 0, width: 4000, height: 1500)
        let clouds = CityLayout.clouds(in: view, seconds: seconds, seed: 123)
        XCTAssertGreaterThan(clouds.count, 4)
        for cloud in clouds {
            // A tiny view of only the upper-right tip must still find a cloud whose
            // source cell and origin are both outside that view.
            let tip = CGRect(x: cloud.rect.maxX-1, y: cloud.rect.maxY-1, width: 0.5, height: 0.5)
            XCTAssertTrue(CityLayout.clouds(in: tip, seconds: seconds, seed: 123).contains(cloud))
        }
        XCTAssertTrue(CityLayout.clouds(in: CGRect(x: -500, y: -1000, width: 1000, height: 900), seconds: seconds, seed: 123).isEmpty)
    }

    func testBuildingRarityProducesOccasionalLandmarksWithoutForcingEveryStyleIntoEachBlock() {
        let sizes = CityBuildings.styles.map { CGSize(width: 60, height: $0.floors*18+14) }
        var counts: [CityBuildings.Rarity: Int] = [:]
        var seen = Set<Int>()
        for seed in 0..<40 {
            let buildings = CityLayout.buildings(in: -10000...10000, sizes: sizes, seed: UInt64(seed))
            for building in buildings {
                counts[CityBuildings.styles[building.art].rarity, default: 0] += 1
                seen.insert(building.art)
            }
            for pair in zip(buildings, buildings.dropFirst()) { XCTAssertNotEqual(pair.0.art, pair.1.art) }
        }
        let total = Double(counts.values.reduce(0,+))
        XCTAssertEqual(seen.count, 24)
        XCTAssertGreaterThan(Double(counts[.common,default:0])/total, 0.65)
        XCTAssertLessThan(Double(counts[.common,default:0])/total, 0.78)
        XCTAssertGreaterThan(Double(counts[.uncommon,default:0])/total, 0.18)
        XCTAssertLessThan(Double(counts[.uncommon,default:0])/total, 0.28)
        XCTAssertGreaterThan(Double(counts[.rare,default:0])/total, 0.03)
        XCTAssertLessThan(Double(counts[.rare,default:0])/total, 0.08)
        XCTAssertGreaterThan(Double(counts[.landmark,default:0])/total, 0.004)
        XCTAssertLessThan(Double(counts[.landmark,default:0])/total, 0.02)
    }

    func testCachedStreetDoesNotChangeWhenVisitingFarAwayFirst() {
        let sizes = CityBuildings.styles.map { CGSize(width: 45+$0.floors*3, height: $0.floors*18) }
        let street = CityLayout.Street(sizes: sizes, seed: 123)
        let initial = street.buildings(in: -400...800)
        _ = street.buildings(in: -12000 ... -11000)
        _ = street.buildings(in: 8000...9000)
        XCTAssertEqual(initial, street.buildings(in: -400...800))
        XCTAssertEqual(initial, CityLayout.buildings(in: -400...800, sizes: sizes, seed: 123))
    }

    func testCityUsesTheSameCameraAsTheTower() {
        let tile = CGRect(x: -512, y: 0, width: 1024, height: 512)
        let origin = CGPoint(x: 300, y: 96)
        let normal = CityLayout.screenRect(tile, origin: origin, scale: 1)
        let zoomed = CityLayout.screenRect(tile, origin: origin, scale: 3)
        XCTAssertEqual(zoomed.width, normal.width * 3)
        XCTAssertEqual(zoomed.height, normal.height * 3)
        XCTAssertEqual(zoomed.minX - origin.x, (normal.minX - origin.x) * 3)
        let panned = CityLayout.screenRect(tile, origin: CGPoint(x: 423, y: 26), scale: 3)
        XCTAssertEqual(panned.minX - zoomed.minX, 123)
        XCTAssertEqual(panned.minY - zoomed.minY, -70)
    }

    func testTileGridCoversNegativeCoordinatesAndExpandsWithTheView() {
        let small = CityLayout.indices(min: -20, max: 500, step: 512)
        XCTAssertEqual(Array(small), [-1, 0])
        let wide = CityLayout.indices(min: -1050, max: 1600, step: 512)
        XCTAssertEqual(Array(wide), [-3, -2, -1, 0, 1, 2, 3])
        XCTAssertEqual(Array(CityLayout.indices(min: 0, max: 512, step: 512)), [0])
    }

    func testCloudMovementKeepsTheSameShapeAndMovesContinuously() throws {
        let view = CGRect(x: -2000, y: 0, width: 4000, height: 1500)
        for seconds in [255.9, 864_000.0] {
            let before = try XCTUnwrap(CityLayout.clouds(in: view, seconds: seconds, seed: 123).first {
                $0.rect.minX > -1500 && $0.rect.maxX < 1500
            })
            let after = try XCTUnwrap(CityLayout.clouds(in: view, seconds: seconds+0.2, seed: 123).first { $0.seed == before.seed })
            XCTAssertEqual(after.opacity, before.opacity)
            XCTAssertEqual(after.rect.minY, before.rect.minY)
            XCTAssertEqual(after.rect.size, before.rect.size)
            XCTAssertGreaterThan(after.rect.minX-before.rect.minX, 0.1)
            XCTAssertLessThan(after.rect.minX-before.rect.minX, 0.31)
        }
    }
}
