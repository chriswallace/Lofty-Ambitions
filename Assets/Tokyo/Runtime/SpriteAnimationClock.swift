import Foundation

/// Animation uses elapsed real time, avoiding aliasing when the simulation
/// advances four or twelve minutes per update. Pausing freezes its phase.
public struct SpriteAnimationClock {
    public private(set) var elapsed: Double = 0
    public init() {}
    public mutating func advance(seconds: Double, isRunning: Bool) {
        guard isRunning, seconds.isFinite, seconds > 0 else { return }
        elapsed = (elapsed + seconds.truncatingRemainder(dividingBy: 3600)).truncatingRemainder(dividingBy: 3600)
    }
    public func phase(reducedMotion: Bool) -> Int {
        reducedMotion ? 0 : Int(elapsed * 8) % 4
    }
}
