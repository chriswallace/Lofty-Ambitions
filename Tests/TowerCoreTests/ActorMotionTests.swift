import XCTest
import TowerArt

final class ActorMotionTests: XCTestCase {
    private func target(_ x: CGFloat, y: CGFloat = 2.5, floor: Int = 0, id: Int = 1, facingLeft: Bool = false) -> ActorMotion.Target {
        .init(id: id, floor: floor, position: CGPoint(x: x, y: y), facingLeft: facingLeft)
    }

    func testTravelInterpolatesAtRenderCadenceRatherThanJumpingBetweenTicks() throws {
        var motion = ActorMotion()
        motion.synchronize([target(0)])
        motion.synchronize([target(6.4)])
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 0)
        motion.advance(seconds: 0.05, isRunning: true)
        let halfway = try XCTUnwrap(motion.pose(for: 1))
        XCTAssertEqual(halfway.position.x, 3.2, accuracy: 0.001)
        XCTAssertEqual(halfway.distance, 3.2, accuracy: 0.001)
        XCTAssertTrue(halfway.isWalking)
        motion.advance(seconds: 0.05, isRunning: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 6.4, accuracy: 0.001)
    }

    func testQueuePositionsSmoothInWorldSpaceAndKeepHeadingAfterStopping() throws {
        var motion = ActorMotion()
        motion.synchronize([target(40)])
        motion.synchronize([target(38, y: 4)])
        motion.advance(seconds: 0.05, isRunning: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position, CGPoint(x: 39, y: 3.25))
        XCTAssertTrue(try XCTUnwrap(motion.pose(for: 1)).facingLeft)
        motion.advance(seconds: 0.05, isRunning: true)
        motion.synchronize([target(38, y: 4, facingLeft: false)])
        motion.advance(seconds: 0.04, isRunning: true)
        let stopped = try XCTUnwrap(motion.pose(for: 1))
        XCTAssertTrue(stopped.facingLeft, "Reaching a waypoint must not turn a leftward walker around")
        XCTAssertFalse(stopped.isWalking)
    }

    func testPauseFreezesPositionAndGaitAndResumeContinuesTheSameStep() throws {
        var motion = ActorMotion()
        motion.synchronize([target(0)])
        motion.synchronize([target(8)])
        motion.advance(seconds: 0.025, isRunning: true)
        let paused = try XCTUnwrap(motion.pose(for: 1))
        motion.advance(seconds: 20, isRunning: false)
        XCTAssertEqual(motion.pose(for: 1), paused)
        motion.advance(seconds: 0.025, isRunning: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 4, accuracy: 0.001)
    }

    func testFloorChangesAndRemovedTravelersDoNotCreateGhostJourneys() throws {
        var motion = ActorMotion()
        motion.synchronize([target(10)])
        motion.synchronize([target(20)])
        motion.advance(seconds: 0.05, isRunning: true)
        motion.synchronize([target(300, y: 50.5, floor: 2, facingLeft: true)])
        let arrived = try XCTUnwrap(motion.pose(for: 1))
        XCTAssertEqual(arrived.position, CGPoint(x: 300, y: 50.5))
        XCTAssertFalse(arrived.isWalking)
        XCTAssertTrue(arrived.facingLeft)
        motion.synchronize([])
        XCTAssertNil(motion.pose(for: 1), "Boarded or removed passengers disappear immediately")
        motion.synchronize([target(9, id: 1)])
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 9)
        motion.reset()
        XCTAssertNil(motion.pose(for: 1))
    }

    func testRepeatedDrawsDoNotRestartInterpolationAndRetargetingIsContinuous() throws {
        var motion = ActorMotion()
        motion.synchronize([target(0)])
        motion.synchronize([target(10)])
        motion.advance(seconds: 0.05, isRunning: true)
        motion.synchronize([target(10)])
        motion.advance(seconds: 0.025, isRunning: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 7.5, accuracy: 0.001)
        motion.synchronize([target(16)])
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 7.5, accuracy: 0.001)
        motion.advance(seconds: 0.05, isRunning: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(for: 1)).position.x, 11.75, accuracy: 0.001)
    }

    func testGaitFollowsDistanceWithAlternatingPlantedAndPassingFeet() {
        XCTAssertEqual([CGFloat(0), 1.5, 3, 4.5, 6].map { ActorMotion.walkingFrame(distance: $0, identity: 0) }, [1, 0, 2, 0, 1])
        XCTAssertNotEqual(ActorMotion.walkingFrame(distance: 0, identity: 0), ActorMotion.walkingFrame(distance: 0, identity: 1))
        XCTAssertEqual(ActorMotion.walkingFrame(distance: 9, identity: 2), ActorMotion.walkingFrame(distance: 3, identity: 2))
    }
}
