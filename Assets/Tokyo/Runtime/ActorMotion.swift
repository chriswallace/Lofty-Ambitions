import Foundation

/// Presentation-only movement between simulation snapshots. Positions are already
/// in world space, so queues and legacy elevator gaps follow the same continuous path.
public struct ActorMotion {
    public struct Target {
        public let id: Int
        public let floor: Int
        public let position: CGPoint
        public let facingLeft: Bool

        public init(id: Int, floor: Int, position: CGPoint, facingLeft: Bool) {
            self.id = id; self.floor = floor; self.position = position; self.facingLeft = facingLeft
        }
    }

    public struct Pose: Equatable {
        public fileprivate(set) var position: CGPoint
        public fileprivate(set) var facingLeft: Bool
        public fileprivate(set) var distance: CGFloat
        public fileprivate(set) var isWalking: Bool
    }

    private struct Track {
        var floor: Int
        var start: CGPoint
        var target: CGPoint
        var elapsed: Double
        var pose: Pose
    }

    private var tracks: [Int: Track] = [:]
    private let interval: Double = 0.1

    public init() {}

    public mutating func reset() { tracks.removeAll(keepingCapacity: true) }

    public func pose(for id: Int) -> Pose? { tracks[id]?.pose }

    public mutating func synchronize(_ targets: [Target]) {
        let visible = Set(targets.map(\.id))
        tracks = tracks.filter { visible.contains($0.key) }
        for target in targets {
            guard var track = tracks[target.id], track.floor == target.floor else {
                tracks[target.id] = Track(floor: target.floor, start: target.position, target: target.position,
                                          elapsed: interval, pose: Pose(position: target.position,
                                          facingLeft: target.facingLeft, distance: 0, isWalking: false))
                continue
            }
            // Repaints and queue-facing changes must not restart an in-flight step.
            if target.position != track.target {
                track.start = track.pose.position
                track.target = target.position
                track.elapsed = 0
                tracks[target.id] = track
            }
        }
    }

    public mutating func advance(seconds: Double, isRunning: Bool) {
        guard isRunning, seconds.isFinite, seconds > 0 else { return }
        for id in Array(tracks.keys) {
            guard var track = tracks[id] else { continue }
            track.elapsed = min(interval, track.elapsed + seconds)
            let progress = CGFloat(track.elapsed / interval)
            let position = CGPoint(x: track.start.x + (track.target.x - track.start.x) * progress,
                                   y: track.start.y + (track.target.y - track.start.y) * progress)
            let dx = position.x - track.pose.position.x, dy = position.y - track.pose.position.y
            let moved = hypot(dx, dy)
            track.pose.position = position
            track.pose.isWalking = moved > 0.0001
            track.pose.distance += moved
            // Keep the last heading at a waypoint instead of turning right on arrival.
            if abs(dx) > 0.0001 { track.pose.facingLeft = dx < 0 }
            tracks[id] = track
        }
    }

    /// A six-point stride shared by corridor and room walkers. Frames 1 and 2
    /// plant opposite feet; frame 0 brings the feet together between those steps.
    /// Frame 3 is another spread stance, so using it as a passing pose causes skating.
    public static func walkingFrame(distance: CGFloat, identity: Int) -> Int {
        let distance = distance.isFinite ? max(0, distance) : 0
        let phase = Int((distance.truncatingRemainder(dividingBy: 6) / 1.5).rounded(.down))
        let offset = (identity % 4 + 4) % 4
        return [1, 0, 2, 0][(phase + offset) % 4]
    }
}
