import XCTest
import CoreGraphics
import TowerArt

final class CloudTextureTests: XCTestCase {
    func testSeedKeepsCloudArtworkStableAcrossRedraws() throws {
        let first = CloudTexture.image(seed: 0xC10D)
        let repeated = CloudTexture.image(seed: 0xC10D)
        XCTAssertEqual(try bytes(first), try bytes(repeated))
    }

    func testSeedsProduceDifferentSilhouettesInsteadOfRecoloringOneStamp() throws {
        let masks = try (0..<12).map { seed in
            let image = CloudTexture.image(seed: UInt64(seed))
            let pixels = try bytes(image)
            return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] > 127 }
        }
        for i in masks.indices {
            for j in masks.indices where j > i {
                let changed = zip(masks[i], masks[j]).filter { $0 != $1 }.count
                XCTAssertGreaterThan(Double(changed) / Double(masks[i].count), 0.025,
                                     "Clouds \(i) and \(j) should have visibly different outlines")
            }
        }
    }

    func testCloudsHaveClearMarginsAndVisiblePaleBodies() throws {
        for seed: UInt64 in [0, 1, 7, 23, 42, UInt64.max] {
            let image = CloudTexture.image(seed: seed)
            let pixels = try bytes(image)
            var bodyPixels = 0, highlightPixels = 0
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let i = (y * image.width + x) * 4
                    if x < 2 || y < 2 || x >= image.width - 2 || y >= image.height - 2 {
                        XCTAssertEqual(pixels[i + 3], 0, "Cloud must not be clipped at its texture edge")
                    }
                    if pixels[i + 3] > 240 {
                        bodyPixels += 1
                        XCTAssertGreaterThan(pixels[i], 210, "Avoid dark cloud outlines")
                        XCTAssertLessThan(Int(pixels[i + 2]) - Int(pixels[i]), 20,
                                          "Cloud shading should stay subtle, without saturated blue outlines")
                        if pixels[i] > 246 { highlightPixels += 1 }
                    }
                }
            }
            let total = image.width * image.height
            XCTAssertGreaterThan(bodyPixels, total / 12, "Cloud should contain a substantial visible body")
            XCTAssertLessThan(bodyPixels, total * 2 / 3, "Cloud should retain an airy silhouette")
            XCTAssertGreaterThan(highlightPixels, bodyPixels / 10)
        }
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let data = try XCTUnwrap(image.dataProvider?.data)
        return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
    }
}
