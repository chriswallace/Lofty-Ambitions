import AppKit
import TowerCore

extension TowerView {
    /// One compact badge per room. Size follows floor spacing even at minimum zoom.
    func signalRect(_ room: Room) -> CGRect {
        let r = roomRect(room)
        let height = min(18, max(4, 20 * scale))
        let width = min(30, max(4, r.width * scale - 2))
        return CGRect(x: origin.x + r.midX * scale - width / 2,
                      y: origin.y + r.maxY * scale - height - scale,
                      width: width, height: height).integral
    }

    func signalHit(_ point: CGPoint) -> Int? {
        guard let game = controller?.game, !coverageLegendRect.contains(point) else { return nil }
        return game.rooms.first { (visibleCoverageService == nil || $0.incident?.isActive == true) && game.signal(for: $0, coverage: controller?.serviceCoverage ?? NeighborhoodCoverage()) != nil && signalRect($0).contains(point) }?.id
    }

    func drawRoomSignals(_ game: TowerState) {
        var expanded: (Room, RoomSignal)?
        for room in game.rooms {
            if visibleCoverageService != nil && room.incident?.isActive != true { continue }
            let r = signalRect(room)
            guard bounds.intersects(r), let signal = game.signal(for: room, coverage: controller?.serviceCoverage ?? NeighborhoodCoverage()) else { continue }
            let color: Int
            switch signal.mood {
            case .angry, .alarmed: color = 0xFFACA0
            case .annoyed, .worried: color = 0xFFE298
            case .sad: color = 0xBFD1EB
            case .relieved: color = 0xBDE4B2
            case .busy: color = 0xD4C8EB
            }
            fill(r, 0x34313A)
            fill(r.insetBy(dx: 1, dy: 1), color)
            if r.height >= 12 {
                // Stepped speech tail occupies the badge’s lower edge, inside this floor.
                fill(CGRect(x: r.minX + 1, y: r.minY, width: 3, height: 3), 0x34313A)
                fill(CGRect(x: r.minX + 2, y: r.minY + 1, width: 2, height: 2), color)
            }
            if r.height >= 12 && r.width >= 16 {
                // Pixel faces remain recognizable without relying on color or emoji fonts.
                let x = r.minX + 4, y = r.minY + 3
                fill(CGRect(x: x, y: y + 5, width: 2, height: 2), 0x34313A)
                fill(CGRect(x: x + 6, y: y + 5, width: 2, height: 2), 0x34313A)
                switch signal.mood {
                case .alarmed, .worried:
                    outline(CGRect(x: x + 3, y: y, width: 3, height: 3), color: 0x34313A, width: 1)
                case .relieved:
                    fill(CGRect(x: x + 2, y: y, width: 4, height: 1), 0x34313A)
                    fill(CGRect(x: x + 1, y: y + 1, width: 1, height: 2), 0x34313A)
                    fill(CGRect(x: x + 6, y: y + 1, width: 1, height: 2), 0x34313A)
                case .angry, .annoyed, .sad:
                    fill(CGRect(x: x + 2, y: y + 2, width: 4, height: 1), 0x34313A)
                    fill(CGRect(x: x + 1, y: y, width: 1, height: 2), 0x34313A)
                    fill(CGRect(x: x + 6, y: y, width: 1, height: 2), 0x34313A)
                    if signal.mood == .angry {
                        line(CGPoint(x: x, y: y + 9), CGPoint(x: x + 3, y: y + 8), 0x34313A)
                        line(CGPoint(x: x + 5, y: y + 8), CGPoint(x: x + 8, y: y + 9), 0x34313A)
                    }
                case .busy:
                    fill(CGRect(x: x + 2, y: y + 1, width: 4, height: 1), 0x34313A)
                }
                if r.width >= 28 {
                    if let icon = NSImage(systemSymbolName: signal.symbol, accessibilityDescription: signal.text)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)) {
                        icon.draw(in: CGRect(x: r.maxX - 11, y: r.midY - 5, width: 9, height: 10))
                    }
                }
            } else {
                fill(CGRect(x: r.midX.rounded(), y: r.minY + 1, width: 1, height: max(1, r.height - 2)), 0x34313A)
            }
            if controller?.selectedRoom == room.id { expanded = (room, signal) }
        }
        // Hover wins over selection. Text lives in one overlay, never covering adjacent badges.
        if let id = hoveredSignal, let room = game.rooms.first(where: { $0.id == id }), (visibleCoverageService == nil || room.incident?.isActive == true), let signal = game.signal(for: room, coverage: controller?.serviceCoverage ?? NeighborhoodCoverage()) {
            expanded = (room, signal)
        }
        if let (room, signal) = expanded {
            let text = "Floor \(TowerState.floorLabel(room.floor)) · \(room.kind.rawValue.capitalized) · \(signal.text)"
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(hex: 0x29252D)]
            let width = min(max(40, bounds.width - 32), 520)
            let measured = (text as NSString).boundingRect(with: CGSize(width: width - 16, height: 200), options: [.usesLineFragmentOrigin], attributes: attributes)
            let card = CGRect(x: 16, y: (visibleCoverageService == nil ? bounds.height - 36 : coverageLegendRect.minY - 8) - ceil(measured.height) - 16, width: width, height: ceil(measured.height) + 16)
            fill(card, 0xFFF3D3); outline(card, color: 0x403844, width: 1)
            (text as NSString).draw(in: card.insetBy(dx: 8, dy: 8), withAttributes: attributes)
        }
    }

}
