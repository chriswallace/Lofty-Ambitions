import AppKit
import XCTest
import TowerArt

final class ActorRegistrationTests: XCTestCase {
    private func opaqueBounds(_ image: CGImage, rows: Range<Int>? = nil) -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var left = image.width, right = 0, top = image.height, bottom = 0
        for y in rows ?? 0..<image.height {
            for x in 0..<image.width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                left = min(left, x); right = max(right, x + 1)
                top = min(top, y); bottom = max(bottom, y + 1)
            }
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    func testWalkingSpritesKeepTheirBodyAxisAndSolesRegisteredInBothDirections() throws {
        let atlas = try TowerAtlas()
        let feet = CGPoint(x: 80, y: 26.04)
        for character in 0..<4 {
            for pose in 0..<4 {
                let key = "civilian.\(character).\(pose)"
                let image = try XCTUnwrap(atlas.image(key))
                let opaque = opaqueBounds(image)
                let headRows = Int(opaque.minY)..<Int(opaque.minY + floor(opaque.height * 0.32))
                let head = opaqueBounds(image, rows: headRows)
                for flipped in [false, true] {
                    let rect = try XCTUnwrap(atlas.actorRect(key, feet: feet, height: 10, flipped: flipped))
                    let scale = rect.height / CGFloat(image.height)
                    let sole = rect.minY + (CGFloat(image.height) - opaque.maxY) * scale
                    XCTAssertEqual(sole, feet.y, accuracy: 0.001, "\(key) must touch the floor")
                    let axis = flipped ? CGFloat(image.width) - head.midX : head.midX
                    XCTAssertEqual(rect.minX + axis * scale, feet.x, accuracy: 0.001, "\(key) must not twitch as its crop changes")
                    if pose == 0 {
                        XCTAssertEqual(opaque.height * scale, 10, accuracy: 0.001, "Transparent pose padding must not shrink a character")
                    }
                }
            }
        }
    }
}
