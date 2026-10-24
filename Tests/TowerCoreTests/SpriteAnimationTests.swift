import XCTest
import TowerArt

final class SpriteAnimationTests: XCTestCase {
    func testAnimationAdvancesIndependentlyOfSimulationSpeed() {
        for speed in [1, 4, 12] {
            var clock = SpriteAnimationClock()
            var frames = Set<Int>()
            for _ in 0..<30 {
                clock.advance(seconds: 1.0/30, isRunning: speed > 0)
                frames.insert(clock.phase(reducedMotion: false))
            }
            XCTAssertEqual(frames, [0, 1, 2, 3])
        }
    }
    func testPauseAndReducedMotionDoNotAnimate() {
        var clock = SpriteAnimationClock()
        clock.advance(seconds: 0.15, isRunning: true)
        let phase = clock.phase(reducedMotion: false)
        clock.advance(seconds: 12, isRunning: false)
        XCTAssertEqual(clock.phase(reducedMotion: false), phase)
        XCTAssertEqual(clock.phase(reducedMotion: true), 0)
        clock.advance(seconds: .infinity, isRunning: true)
        XCTAssertEqual(clock.phase(reducedMotion: false), phase)
    }
}
