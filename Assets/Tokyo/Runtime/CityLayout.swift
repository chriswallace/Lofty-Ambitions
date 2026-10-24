import Foundation
// Foundation supplies portable CGPoint, CGSize and CGRect.

/// Fixed world dimensions keep neighboring buildings at the tower's scale.
public enum CityLayout {
    public struct Building: Equatable {
        public let art: Int
        public let rect: CGRect
    }
    public struct Cloud: Equatable {
        /// Stable shape identity; the renderer can lazily generate and cache its texture.
        public let seed: UInt64
        public let rect: CGRect
        public let opacity: CGFloat
    }

    // Explicit integer mixing is stable across launches, platforms, and Swift versions.
    private static func mix(_ value: UInt64) -> UInt64 {
        var x = value &+ 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }
    private static func coordinate(_ value: Int) -> UInt64 { UInt64(bitPattern: Int64(value)) }

    /// A seed-owned street grows outward from a stable origin. Cached prefix positions
    /// let differently sized, weighted buildings form a continuous row without reshuffling.
    public final class Street {
        public let sizes: [CGSize]
        public let seed: UInt64
        private var right: [Building] = []
        private var left: [Building] = []
        private var rightEdge: CGFloat = 0
        private var leftEdge: CGFloat = 0

        public init(sizes: [CGSize], seed: UInt64) { self.sizes = sizes; self.seed = seed }

        private func choose(index: Int, excluding previous: Int?) -> Int {
            let weights = sizes.indices.map { i in
                i == previous ? 0 : (i < CityBuildings.styles.count ? CityBuildings.styles[i].rarity.weight : 60)
            }
            var roll = Int(mix(seed ^ mix(coordinate(index))) % UInt64(weights.reduce(0,+)))
            for i in weights.indices {
                if roll < weights[i] { return i }
                roll -= weights[i]
            }
            return 0
        }
        private func gap(_ index: Int) -> CGFloat {
            CGFloat(4 + mix(seed ^ mix(coordinate(index)) ^ 0xA11E7) % 9)
        }

        public func buildings(in range: ClosedRange<CGFloat>) -> [Building] {
            guard sizes.count > 2, sizes.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { return [] }
            // Always establish index zero, so both sides share the same boundary neighbor.
            while right.isEmpty || rightEdge < range.upperBound {
                let index = right.count
                let art = choose(index: index, excluding: right.last?.art)
                let size = sizes[art]
                let rect = CGRect(x: rightEdge, y: 0, width: size.width, height: size.height)
                right.append(Building(art: art, rect: rect))
                rightEdge = rect.maxX + gap(index)
            }
            while leftEdge > range.lowerBound {
                let index = -left.count-1
                let art = choose(index: index, excluding: left.last?.art ?? right.first?.art)
                let size = sizes[art]
                let rect = CGRect(x: leftEdge-gap(index)-size.width, y: 0, width: size.width, height: size.height)
                left.append(Building(art: art, rect: rect))
                leftEdge = rect.minX
            }
            return (Array(left.reversed())+right).filter { $0.rect.maxX > range.lowerBound && $0.rect.minX < range.upperBound }
        }
    }

    public static func buildings(in range: ClosedRange<CGFloat>, sizes: [CGSize], seed: UInt64) -> [Building] {
        Street(sizes: sizes, seed: seed).buildings(in: range)
    }

    /// An unbounded, sparse sky field. Generous position jitter hides the candidate
    /// grid; each cloud retains its own shape as the camera moves or time advances.
    public static func clouds(in visible: CGRect, seconds: Double, seed: UInt64) -> [Cloud] {
        guard !visible.isEmpty, !visible.isInfinite, seconds.isFinite else { return [] }
        var result: [Cloud] = []
        let columnSpacing: CGFloat = 440, rowSpacing: CGFloat = 270
        // A row starts at +160, jitters by ±155, and extends at most 90 upward.
        // Include that entire overhang so a partial cloud never pops into view.
        for row in indices(min: max(0, visible.minY-405), max: max(0, visible.maxY), step: rowSpacing) {
            let rowSeed = mix(seed ^ mix(coordinate(row) &+ 0xC10D))
            let wind = CGFloat(seconds) * (0.65+CGFloat(rowSeed % 81)/100)
            // Subtract the row's full continuous drift before finding candidates.
            // Runtime stays viewport-sized even after days of movement, with no wrap.
            for column in indices(min: visible.minX-wind-485, max: visible.maxX-wind+205, step: columnSpacing) {
                let bits = mix(rowSeed ^ mix(coordinate(column)))
                guard bits % 100 < 44 else { continue }
                let shapeSeed = mix(bits ^ 0xA6F04D1C)
                let width = CGFloat(112+(shapeSeed >> 8)%169)
                let tall = (shapeSeed >> 16)%100 < 18
                let height = tall ? CGFloat(56+(shapeSeed >> 24)%35) : CGFloat(24+(shapeSeed >> 24)%28)
                let rect = CGRect(x: CGFloat(column)*columnSpacing+CGFloat((bits >> 16)%411)-205+wind,
                                  y: CGFloat(row)*rowSpacing+160+CGFloat((bits >> 32)%311)-155,
                                  width: width, height: height)
                guard rect.minY >= 100, rect.intersects(visible) else { continue }
                result.append(Cloud(seed: shapeSeed, rect: rect, opacity: 0.48+CGFloat((shapeSeed >> 40)%36)/100))
            }
        }
        return result
    }

    public static func screenRect(_ world: CGRect, origin: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(x: origin.x + world.minX * scale, y: origin.y + world.minY * scale,
               width: world.width * scale, height: world.height * scale)
    }

    public static func indices(min: CGFloat, max: CGFloat, step: CGFloat) -> Range<Int> {
        let first = Int(floor(min / step))
        return first..<Swift.max(first, Int(ceil(max / step)))
    }

}
