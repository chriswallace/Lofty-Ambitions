import XCTest
import TowerArt

final class CityLightingTests: XCTestCase {
    func testTimeOfDayHasFourDistinctViews() {
        XCTAssertEqual(CityLighting.layers(at: 360).last?.key, "city.sunrise")
        XCTAssertEqual(CityLighting.layers(at: 720).last?.key, "city.day")
        XCTAssertEqual(CityLighting.layers(at: 1080).last?.key, "city.sunset")
        XCTAssertEqual(CityLighting.layers(at: 1320).last?.key, "city.night")
    }
    func testTransitionsBlendContinuouslyAndWrapAtMidnight() {
        let middle = CityLighting.layers(at: 420)
        XCTAssertEqual(middle.count, 2)
        XCTAssertEqual(middle[0].key, "city.sunrise")
        XCTAssertEqual(middle[1].key, "city.day")
        XCTAssertEqual(middle[1].opacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(CityLighting.layers(at: 0), CityLighting.layers(at: 1440))
        XCTAssertEqual(CityLighting.layers(at: -1), CityLighting.layers(at: 1439))
    }
}
