import AppKit
import TowerCore
import TowerPresentation

typealias CoverageMark = SceneCoverageMark

extension GameController {
    @objc func changeCoverageOverlay(_ sender: NSPopUpButton) {
        setCoverageOverlay(sender.indexOfSelectedItem == 1 ? .food : sender.indexOfSelectedItem == 2 ? .shops : nil)
    }
    func setCoverageOverlay(_ service: NeighborhoodService?) {
        coverageOverlay = service
        refreshCoverageControl()
        gameView.hoveredSignal = nil
        gameView.needsDisplay = true
    }
    func refreshCoverageControl() {
        coveragePicker?.selectItem(at: coverageOverlay == .food ? 1 : coverageOverlay == .shops ? 2 : 0)
        coveragePicker?.contentTintColor = coverageOverlay == nil ? Theme.ink : Theme.accent
        gameView.setAccessibilityValue(coverageOverlay.map {
            "\($0.title) coverage overlay. Rooms show coverage percentages; service venues show neighbors served. Use Issues or the room inspector for details."
        } ?? "Coverage overlay off")
    }
    func coverageMark(for room:Room,service:NeighborhoodService)->CoverageMark? {
        SceneCoverageMark.mark(for:room,service:service,allocation:serviceCoverage)
    }
}

typealias CoverageGuide = SceneCoverageGuide

extension TowerView {
    var visibleCoverageService: NeighborhoodService? { controller?.focusMode == false ? controller?.coverageOverlay : nil }

    /// Geometric reach, not a forecast: shared capacity is still allocated by the simulation.
    /// Match the construction preview's floor and drag slots; invalid placements have no guide.
    func coverageGuideRooms(_ service: NeighborhoodService) -> [CoverageGuide] {
        guard let c = controller else { return [] }
        if let kind = c.selectedKind {
            guard kind.neighborhoodService == service, let h = hovered else { return [] }
            let first = startCell ?? h
            guard c.game.isConnected(first.floor) else { return [] }
            return stride(from: min(first.slot, h.slot), through: max(first.slot, h.slot), by: kind.width).compactMap { slot -> CoverageGuide? in
                guard (try? c.game.validateBuild(kind, floor: first.floor, slot: slot)) != nil else { return nil }
                return CoverageGuide(kind: kind, floor: first.floor, slot: slot)
            }
        }
        guard !c.floorMode, !c.demolition, c.elevatorTool == nil,
              let room = c.game.rooms.first(where: { $0.id == c.selectedRoom }),
              c.serviceCoverage.venues[room.id]?.service == service,
              c.serviceCoverage.venues[room.id]?.operational == true else { return [] }
        return [CoverageGuide(kind: room.kind, floor: room.floor, slot: room.slot)]
    }

    func drawCoverageOverlay(_ game: TowerState) {
        guard let service = visibleCoverageService else { return }
        prepareScene(game)
        scene.coverage=service
        scene.coverageRoomID=nil
        scene.coverageGuides=coverageGuideRooms(service).map {SceneCoverageGuide(kind:$0.kind,floor:$0.floor,slot:$0.slot)}
        guard let ctx=NSGraphicsContext.current?.cgContext else{return}
        ctx.saveGState();ctx.scaleBy(x:1/scale,y:1/scale);ctx.translateBy(x:-origin.x,y:-origin.y)
        drawSceneCommands(scene.renderCoverage(game:game,width:bounds.width,height:bounds.height,labels:false))
        ctx.restoreGState()
    }

    func drawCoverageLabels() {
        guard let c = controller, let service = visibleCoverageService else { return }
        for room in c.game.rooms {
            guard let mark = c.coverageMark(for: room, service: service) else { continue }
            let world = roomRect(room)
            let rect = CGRect(x: origin.x+world.minX*scale, y: origin.y+world.minY*scale, width: world.width*scale, height: world.height*scale)
            guard rect.intersects(bounds), rect.height >= 20 else { continue }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
            let text = mark.label as NSString
            let size = text.size(withAttributes: attributes)
            guard size.width+8 <= rect.width-2 else { continue }
            let card = CGRect(x: (rect.midX-(size.width+8)/2).rounded(), y: (rect.minY+3).rounded(), width: size.width+8, height: 17)
            fill(card, mark.color)
            text.draw(at: CGPoint(x: card.minX+4, y: card.minY+2), withAttributes: attributes)
        }
    }

    var coverageLegendText: String? {
        guard let c = controller, let service = visibleCoverageService else { return nil }
        let short = c.serviceCoverage.rooms.values.filter { $0[service]?.isShort == true }.count
        var text = "\(service.title) coverage · \(short) \(short == 1 ? "room needs" : "rooms need") service\nTeal: 100% · Amber: 1–99% · Red: 0%\nBlue: venue load · Gray: empty or paused"
        if c.selectedKind?.neighborhoodService == service {
            text += "\nGuide: ±\(service.floorRange) floors / 48 cells; capacity still applies."
        } else {
            text += "\nSelect a venue to see its reach."
        }
        if let h = hovered, let room = c.game.room(at: h.floor, slot: h.slot), let mark = c.coverageMark(for: room, service: service) {
            text += "\nFloor \(TowerState.floorLabel(room.floor)) · \(room.kind.title): \(mark.detail)"
        } else {
            text += "\nHover a room for coverage details."
        }
        return text
    }

    var coverageLegendRect: CGRect {
        guard visibleCoverageService != nil else { return .zero }
        let width = max(80, min(500, bounds.width-24))
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        // Four legend rows plus two detail rows. Hover must never move the hit
        // boundary over the pointer, which would repeatedly clear/restore hover.
        let height = ceil(font.ascender-font.descender+font.leading)*6+20
        return CGRect(x: 12, y: bounds.height-38-height, width: width, height: height)
    }
    func drawCoverageLegend() {
        guard let text = coverageLegendText else { return }
        let rect = coverageLegendRect
        fill(rect, color: NSColor(hex: 0xF4F8FA, alpha: 0.96)); outline(rect, color: 0x657783, width: 1)
        (text as NSString).draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(hex: 0x233842)])
    }
}
