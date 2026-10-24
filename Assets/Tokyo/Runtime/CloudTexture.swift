#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Small, seeded pixel-art textures. The renderer caches these; clouds keep their
/// identity while drifting rather than changing their shape on every frame.
public enum CloudTexture {
    public struct Pixels {
        public let width: Int
        public let height: Int
        /// Premultiplied RGBA8, top row first.
        public let rgba: [UInt8]
    }
    public static func pixels(seed: UInt64) -> Pixels {
        let width = 192, height = 96
        var random = Random(seed: seed)
        let count = 3 + Int(random.next() % 4)
        let lean = random.unit() * 0.20 - 0.10
        let heightScale = 0.75 + random.unit() * 0.55
        let highMass = Int(random.next() % UInt64(count))
        let hasHighMass = random.unit() > 0.25
        var lobes: [Lobe] = []
        for i in 0..<count {
            let progress = Double(i) / Double(count - 1)
            let radiusY = hasHighMass && i == highMass
                ? 0.32 + random.unit() * 0.08
                : (0.12 + random.unit() * 0.16) * heightScale
            lobes.append(Lobe(x: 0.22 + progress * 0.56 + random.unit() * 0.10 - 0.05,
                              y: 0.54 + random.unit() * 0.08 + lean * (progress - 0.5),
                              radiusX: 0.13 + random.unit() * 0.11,
                              radiusY: radiusY,
                              strength: 0.8 + random.unit() * 0.5))
        }
        let tailY = 0.66 + random.unit() * 0.045
        lobes.append(Lobe(x: 0.5, y: tailY, radiusX: 0.46,
                          radiusY: 0.075 + random.unit() * 0.03, strength: 0.65))
        if random.unit() < 0.35 {
            // A small wind-torn fragment occasionally escapes the main bank.
            let side = random.unit() < 0.5 ? 0.11 : 0.89
            lobes.append(Lobe(x: side, y: 0.37 + random.unit() * 0.10,
                              radiusX: 0.04 + random.unit() * 0.025,
                              radiusY: 0.025 + random.unit() * 0.015, strength: 0.9))
        }
        let noise = Noise(seed: random.next())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for py in 2..<(height - 2) {
            let y = Double(py) / Double(height)
            for px in 2..<(width - 2) {
                let x = Double(px) / Double(width)
                let broad = noise.value(x * 5.2, y * 4.6)
                let detail = noise.value(x * 19.0 + 11, y * 14.0 + 7)
                let warpedX = x + broad * 0.025
                let warpedY = y + noise.value(x * 8.0 + 23, y * 6.0 + 19) * 0.05
                var density = 0.0
                var upperLight = 0.0
                for lobe in lobes {
                    let dx = (warpedX - lobe.x) / lobe.radiusX
                    let dy = (warpedY - lobe.y) / lobe.radiusY
                    let falloff = max(0, 1 - dx * dx - dy * dy)
                    let contribution = falloff * falloff * lobe.strength
                    density += contribution
                    upperLight += contribution * dy
                }
                // Coherent erosion interrupts the smooth lobes. The shallow lower
                // envelope gives the cloud an airy, wind-stretched base and tails.
                var edge = density - 0.23 + broad * 0.14 + detail * 0.075
                let bottom = tailY + 0.065 + noise.value(x * 11 + 31, 4) * 0.05
                edge = min(edge, (bottom - y) * 12)
                let alpha = smoothstep(-0.032, 0.032, edge)
                guard alpha > 0 else { continue }

                let underside = upperLight / max(0.001, density)
                let shade = underside * 0.52 + broad * 0.17 + detail * 0.035
                let color: (Double, Double, Double)
                if shade < -0.12 { color = (253, 254, 253) }
                else if shade < 0.08 { color = (248, 251, 251) }
                else if shade < 0.23 { color = (239, 245, 247) }
                else { color = (229, 237, 240) }
                let offset = (py * width + px) * 4
                pixels[offset] = UInt8((color.0 * alpha).rounded())
                pixels[offset + 1] = UInt8((color.1 * alpha).rounded())
                pixels[offset + 2] = UInt8((color.2 * alpha).rounded())
                pixels[offset + 3] = UInt8((255 * alpha).rounded())
            }
        }

        return Pixels(width: width, height: height, rgba: pixels)
    }

    #if canImport(CoreGraphics)
    public static func image(seed: UInt64) -> CGImage {
        let texture = pixels(seed: seed)
        let width = texture.width, height = texture.height
        let provider = CGDataProvider(data: Data(texture.rgba) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    #endif

    private struct Lobe {
        let x: Double, y: Double, radiusX: Double, radiusY: Double, strength: Double
    }

    private struct Random {
        var seed: UInt64
        mutating func next() -> UInt64 {
            seed &+= 0x9E3779B97F4A7C15
            var value = seed
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
    }

    private struct Noise {
        let seed: UInt64
        func value(_ x: Double, _ y: Double) -> Double {
            let ix = Int(floor(x)), iy = Int(floor(y))
            let tx = x - Double(ix), ty = y - Double(iy)
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let a = sample(ix, iy), b = sample(ix + 1, iy)
            let c = sample(ix, iy + 1), d = sample(ix + 1, iy + 1)
            return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
        }
        private func sample(_ x: Int, _ y: Int) -> Double {
            var random = Random(seed: seed ^ (UInt64(bitPattern: Int64(x)) &* 0xD6E8FEB86659FD93)
                                ^ (UInt64(bitPattern: Int64(y)) &* 0xA5A3564E27F8862F))
            return random.unit() - 0.5
        }
    }

    private static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
