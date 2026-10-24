import Foundation
import TowerCore
import TowerArt

extension TowerScene {
    /// Empty built space is finished circulation space. Compose whole clear bays,
    /// rather than decorating individual construction cells or clipping furniture.
    func drawCorridors(_ game: TowerState, floor: Int, in bounds: CGRect, rooms: [Room]) {
        let shafts = game.elevators.indices.map { elevatorFootprint($0, game) }
        let occupied = rooms.map { roomRect($0) } + shafts
        let bays = LobbyComposition(bounds: bounds, shafts: occupied).clearBays
        let residentialWidth = rooms.filter { [.apartment, .luxuryApartment, .hotel].contains($0.kind) }.reduce(0) { $0 + $1.kind.width }
        let totalWidth = rooms.reduce(0) { $0 + $1.kind.width }
        let palette = CorridorPalette(underground: floor < 0, residential: residentialWidth > totalWidth / 2)
        for bay in bays {
            pushClip(bay)
            drawCorridorShell(bay, palette)
            // Wall fixtures need some breathing room; slivers remain quiet infill.
            if bay.width >= 16 {
                let count = max(1, Int(bay.width / 40))
                for index in 0..<count {
                    let x = (bay.minX + bay.width * (CGFloat(index) + 0.5) / CGFloat(count)).rounded()
                    drawCorridorLight(at: CGPoint(x: x, y: bay.minY), palette)
                }
            }
            if bay.width >= 48 {
                // One sparse grouping per generous stretch. Placement depends only
                // on the built layout, so it stays still during play, pan and zoom.
                let count = max(1, Int(bay.width / 128))
                for index in 0..<count {
                    let x = (bay.minX + bay.width * (CGFloat(index) + 0.5) / CGFloat(count)).rounded()
                    let variation = (abs(floor) + index + Int(abs(bay.minX) / 8)) % 3
                    drawCorridorFurnishings(at: CGPoint(x: x, y: bay.minY), palette, variation: variation)
                }
            }
            if bay.width >= 24 {
                let rightLanding = shafts.contains { $0.intersects(bounds) && abs($0.minX - bay.maxX) < 0.5 }
                let leftLanding = shafts.contains { $0.intersects(bounds) && abs($0.maxX - bay.minX) < 0.5 }
                if rightLanding || leftLanding {
                    drawCorridorWayfinding(at: CGPoint(x: rightLanding ? bay.maxX - 12 : bay.minX + 3, y: bay.minY + 14), floor: floor, pointsRight: rightLanding)
                }
            }
            popClip()
        }
    }

    private func drawCorridorShell(_ r: CGRect, _ p: CorridorPalette) {
        fill(r, p.wall)
        fill(CGRect(x: r.minX, y: r.minY + 20, width: r.width, height: 2), p.wallShade)
        // A low dado and skirting read as a finished wall, not exposed studs.
        fill(CGRect(x: r.minX, y: r.minY + 4, width: r.width, height: 5.5), p.dado)
        fill(CGRect(x: r.minX, y: r.minY + 9.5, width: r.width, height: 0.5), p.trim)
        fill(CGRect(x: r.minX, y: r.minY + 4, width: r.width, height: 0.75), p.skirt)
        fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 1.5), p.beam)
        fill(CGRect(x: r.minX, y: r.minY + 1.5, width: r.width, height: 0.5), p.floorEdge)
        fill(CGRect(x: r.minX, y: r.minY + 2, width: r.width, height: 2), p.floor)
        fill(CGRect(x: r.minX, y: r.minY + 2, width: r.width, height: 0.5), p.floorEdge)
        // Small floor joints share a world-space origin across gaps and landings.
        for x in stride(from: (r.minX / 16).rounded(.down) * 16, to: r.maxX, by: 16) {
            fill(CGRect(x: x, y: r.minY + 2.5, width: 0.25, height: 1.5), p.floorJoint)
        }
        fill(CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2), p.beam)
        fill(CGRect(x: r.minX, y: r.maxY - 2.5, width: r.width, height: 0.5), p.trim)
        // A thin return meets each neighboring room without adding a false doorway.
        for x in [r.minX, r.maxX - 0.5] {
            fill(CGRect(x: x, y: r.minY + 4, width: 0.5, height: 17.5), p.wallShade)
        }
    }

    private func drawCorridorLight(at point: CGPoint, _ p: CorridorPalette) {
        let x = point.x, y = point.y
        for row in 0..<11 {
            let half = 2+CGFloat(row)*5/11
            fill(CGRect(x:x-half,y:y+20-CGFloat(row),width:half*2,height:1),color:SceneColor(hex:0xFFE6AA,alpha:0.15))
        }
        fill(CGRect(x: x - 3, y: y + 21, width: 6, height: 0.75), p.beam)
        fill(CGRect(x: x - 2.25, y: y + 20.5, width: 4.5, height: 0.75), 0xF4D89A)
        fill(CGRect(x: x - 1.5, y: y + 20.5, width: 3, height: 0.25), 0xFFF1C7)
    }

    private func drawCorridorFurnishings(at point: CGPoint, _ p: CorridorPalette, variation: Int) {
        let x = point.x, y = point.y
        // Everything sits against the back wall, leaving the foreground walkway open.
        if p.underground && variation == 1 {
            drawCorridorVending(at: CGPoint(x: x - 3, y: y + 3.5))
        } else {
            fill(CGRect(x: x - 6.5, y: y + 3.25, width: 13, height: 0.5), color: SceneColor(hex: 0x243A37, alpha: 0.16))
            for leg in [x - 4.5, x + 4] {
                fill(CGRect(x: leg, y: y + 3.5, width: 0.75, height: 2), p.beam)
            }
            fill(CGRect(x: x - 5.5, y: y + 5, width: 11, height: 2.5), p.seat)
            fill(CGRect(x: x - 5.5, y: y + 5, width: 11, height: 0.5), p.skirt)
            fill(CGRect(x: x - 5.5, y: y + 7.5, width: 11, height: 0.5), p.seatHighlight)
            fill(CGRect(x: x, y: y + 5.5, width: 0.25, height: 2), p.skirt)
            drawCorridorPicture(in: CGRect(x: x - 3, y: y + 12, width: 6, height: 5), palette: p, variation: variation)
        }
        drawCorridorPlant(at: CGPoint(x: x + (variation == 2 ? -11 : 10), y: y + 3.5))
    }

    private func drawCorridorPicture(in r: CGRect, palette p: CorridorPalette, variation: Int) {
        fill(r.offsetBy(dx: 0.5, dy: -0.5), p.wallShade)
        fill(r, p.trim)
        let art = r.insetBy(dx: 0.5, dy: 0.5)
        fill(art, 0xEEE8D1)
        fill(CGRect(x: art.minX + 0.5, y: art.minY + 0.5, width: 2, height: 2.5), variation == 0 ? 0x688D81 : 0xB77C57)
        fill(CGRect(x: art.minX + 2.5, y: art.minY + 0.5, width: 1.5, height: 1.5), 0x344F59)
        fill(CGRect(x: art.minX + 3, y: art.minY + 2.5, width: 1, height: 0.75), 0xD4AD66)
    }

    private func drawCorridorPlant(at point: CGPoint) {
        let x = point.x, y = point.y
        fill(CGRect(x: x - 2, y: y - 0.25, width: 4, height: 0.5), color: SceneColor(hex: 0x243A37, alpha: 0.16))
        fill(CGRect(x: x - 1.25, y: y, width: 2.5, height: 2.5), 0xB6AB8D)
        fill(CGRect(x: x - 1.5, y: y + 2, width: 3, height: 0.75), 0xD9CEAE)
        fill(CGRect(x: x - 1, y: y + 2.5, width: 2, height: 0.25), 0x5A5543)
        fill(CGRect(x: x - 0.25, y: y + 2.5, width: 0.5, height: 4.5), 0x6F7050)
        for (dx, dy, width) in [(-2.0, 4.0, 2.0), (0.0, 5.0, 2.5), (-2.5, 6.0, 2.5), (-0.5, 7.0, 2.0)] {
            fill(CGRect(x: x + dx, y: y + dy, width: width, height: 1), 0x376555)
            fill(CGRect(x: x + dx + 0.5, y: y + dy + 0.75, width: width - 0.5, height: 0.5), 0x6C8E67)
        }
    }

    private func drawCorridorVending(at point: CGPoint) {
        let x = point.x, y = point.y
        fill(CGRect(x: x, y: y, width: 6, height: 11), 0x355B61)
        fill(CGRect(x: x + 0.5, y: y + 3, width: 4, height: 7), 0xB8C9B8)
        for row in 0..<3 {
            for column in 0..<3 {
                fill(CGRect(x: x + 1 + CGFloat(column), y: y + 4 + CGFloat(row) * 1.75, width: 0.5, height: 1.25), column == 1 ? 0xB86F4E : 0xE9D9A4)
            }
        }
        fill(CGRect(x: x + 1, y: y + 1, width: 3.5, height: 1), 0x223D43)
        fill(CGRect(x: x + 5, y: y + 5, width: 0.5, height: 1), 0xE4BB70)
        fill(CGRect(x: x + 0.5, y: y + 10, width: 5, height: 0.5), 0xE2DAC0)
    }

    private func drawCorridorWayfinding(at point: CGPoint, floor: Int, pointsRight: Bool) {
        fill(CGRect(x: point.x, y: point.y, width: 9, height: 3.5), 0x3F625D)
        label(TowerState.floorLabel(floor), at: CGPoint(x: point.x + 0.5, y: point.y + 0.25), size: 2.5, color: 0xECE6CE)
        let x = point.x + 7.25, y = point.y + 1.75
        fill(CGRect(x: x - 0.75, y: y, width: 1.5, height: 0.25), 0xECE6CE)
        let tip = pointsRight ? x + 0.5 : x - 0.75
        fill(CGRect(x: tip, y: y - 0.25, width: 0.25, height: 0.75), 0xECE6CE)
    }
}

private struct CorridorPalette {
    let underground: Bool
    let wall: Int, wallShade: Int, dado: Int, skirt: Int, trim: Int
    let floor: Int, floorEdge: Int, floorJoint: Int, beam: Int
    let seat: Int, seatHighlight: Int

    init(underground: Bool, residential: Bool) {
        self.underground = underground
        wall = underground ? 0xB9C2B5 : residential ? 0xDCD1B8 : 0xDEDCCB
        wallShade = underground ? 0xA6B1A4 : residential ? 0xC6B99E : 0xC8CCBD
        dado = underground ? 0x728A80 : residential ? 0xA99474 : 0x8FA59A
        skirt = underground ? 0x526B63 : residential ? 0x776B53 : 0x607B71
        trim = residential ? 0x9A8159 : 0xA9AA8B
        floor = residential ? 0xC4B393 : 0xB7C0B2
        floorEdge = 0xD4D8C8
        floorJoint = residential ? 0xA7987D : 0x98A89B
        beam = 0x28434D
        seat = residential ? 0x8D7659 : 0x4E736C
        seatHighlight = residential ? 0xB29A71 : 0x72968A
    }
}
