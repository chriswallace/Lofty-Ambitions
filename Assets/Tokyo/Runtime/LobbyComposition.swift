import Foundation

/// Allocate furnishings only in clear space, independent of elevator count,
/// legacy shaft gaps, tower width, or camera zoom.
public struct LobbyComposition {
    public let clearBays: [CGRect]
    public let feature: CGRect?

    public init(bounds: CGRect, shafts: [CGRect]) {
        // Foundation on Windows includes touching edges in intersects; only area
        // inside the lobby can block a furnishing bay.
        let occupied = shafts.map { $0.intersection(bounds) }.filter { !$0.isEmpty }.sorted { $0.minX < $1.minX }
        var cursor = bounds.minX
        var bays: [CGRect] = []
        for shaft in occupied {
            if shaft.minX > cursor { bays.append(CGRect(x: cursor, y: bounds.minY, width: shaft.minX-cursor, height: bounds.height)) }
            cursor = max(cursor, shaft.maxX)
        }
        if cursor < bounds.maxX { bays.append(CGRect(x: cursor, y: bounds.minY, width: bounds.maxX-cursor, height: bounds.height)) }
        clearBays = bays
        let largest = bays.max { $0.width < $1.width }
        if let bay = largest, bay.width >= 100 {
            let width = min(252, bay.width-4)
            feature = CGRect(x: bay.midX-width/2, y: bay.minY, width: width, height: bay.height)
        } else { feature = nil }
    }
}
