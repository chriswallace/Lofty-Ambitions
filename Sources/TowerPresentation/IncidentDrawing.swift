import Foundation
import TowerCore

extension TowerScene {
    func drawIncidentEffects(_ room: Room, _ r: CGRect, _ game: TowerState) {
        guard let incident = room.incident, incident.isActive else {return}
        let phase = animationPhase(game)
        pushClip(r.insetBy(dx:1,dy:1))
        defer {popClip()}
        if incident.kind == .party {
            if incident.stage == .partying {label("♪",at:CGPoint(x:r.midX,y:r.minY+12),size:9,color:0xEBC84E)}
            if incident.stage == .cleaning {actor("staff.1.\(phase)",feet:CGPoint(x:r.midX,y:r.minY+2))}
        }
        if incident.kind == .fire {
            if [.burning,.dispatched,.extinguishing].contains(incident.stage) {
                let suppression = incident.stage == .extinguishing ? 1-incident.progress*0.8 : 1
                for i in 0..<max(1,min(5,Int(r.width/16))) {
                    let x = r.minX+5+CGFloat(i)*16
                    let h = CGFloat(10+incident.severity*8)*suppression
                    drawImage("effect.\(incident.severity > 0.5 ? 1 : 0).\((phase+i)%4)",in:CGRect(x:x,y:r.minY+2,width:10,height:max(4,h)))
                    drawImage("effect.2.\((phase+i)%4)",in:CGRect(x:x-1,y:r.minY+10,width:14,height:12))
                }
                drawImage("effect.5.\(phase)",in:CGRect(x:r.maxX-7,y:r.maxY-6,width:4,height:4))
            }
            if incident.stage == .repairing {
                drawImage("structure.2.1",in:CGRect(x:r.minX+4,y:r.minY+2,width:10,height:6))
                actor("staff.2.\(phase)",feet:CGPoint(x:r.midX,y:r.minY+2))
            }
        }
    }

    func firefighter(at p: CGPoint, cleaning: Bool = false, climbing: Bool = false, facingRight: Bool = false) {
        let phase = animationPhase(game)
        actor(cleaning ? "staff.1.\(phase)" : "responder.\(climbing ? 3 : 1).\(phase)",feet:p,height:11,flipped:facingRight)
    }

    func drawFireResponse(_ game: TowerState) {
        let reduced = reducedMotion
        for room in game.rooms {
            guard let state = room.incident, state.kind == .fire,
                  state.stage == .dispatched || state.stage == .extinguishing else { continue }
            let r = roomRect(room)
            let left = r.midX < CGFloat(game.core) * 8
            let edge = (min(0,room.floor)...max(0,room.floor)).map { spanRect($0) }.reduce(left ? r.minX : r.maxX) { left ? min($0, $1.minX) : max($0, $1.maxX) }
            let progress = state.durationMinutes > 0 ? min(1, max(0, 1 - Double(state.remainingMinutes) / Double(state.durationMinutes))) : 1
            let approaching = !reduced && state.stage == .dispatched && progress < 0.25
            let motion = reducedMotion ? 0 : (approaching ? CGFloat(1 - progress / 0.25) * 70 : 0)
            let x = (left ? edge - 48 : edge + 12) + (left ? -motion : motion)
            let sceneBottom=min(-10,r.minY)
            let scene = CGRect(x: min(x, r.minX), y: sceneBottom, width: max(x + 50, r.maxX) - min(x, r.minX), height: max(14,r.maxY)-sceneBottom)
            let visible = CGRect(x: -origin.x / scale, y: -origin.y / scale, width: bounds.width / scale, height: bounds.height / scale)
            guard scene.intersects(visible) else { continue }
            let base = CGPoint(x: x + 21, y: 4)
            if let engine = atlas.frames["vehicle.fireEngine"] {
                let height = 50 * CGFloat(engine.rect[3]) / CGFloat(engine.rect[2])
                drawImage("vehicle.fireEngine", in: CGRect(x: x, y: -9, width: 50, height: height), flipped: !left)
            }
            let target = CGPoint(x: left ? r.minX + 3 : r.maxX - 3, y: r.minY + 5)
            if approaching { continue }
            if state.responseRoute == .ladder && room.floor >= 0 {
                let reach = reduced || state.stage == .extinguishing ? 1 : max(0.08, (progress - 0.25) / 0.75)
                let tip = CGPoint(x: base.x + (target.x - base.x) * reach, y: base.y + (target.y - base.y) * reach)
                for offset: CGFloat in [-2, 2] { line(CGPoint(x: base.x + offset, y: base.y), CGPoint(x: tip.x + offset, y: tip.y), 0xE0D9C5) }
                let steps = max(1, Int(hypot(tip.x - base.x, tip.y - base.y) / 5))
                for n in 0...steps {
                    let t = CGFloat(n) / CGFloat(steps)
                    let p = CGPoint(x: base.x + (tip.x - base.x) * t, y: base.y + (tip.y - base.y) * t)
                    line(CGPoint(x: p.x - 2, y: p.y), CGPoint(x: p.x + 2, y: p.y), 0xA7A59A)
                }
                firefighter(at: CGPoint(x: tip.x, y: tip.y), climbing: state.stage == .dispatched, facingRight: left)
            } else {
                firefighter(at: CGPoint(x: x + 38, y: -5))
                firefighter(at: CGPoint(x: target.x, y: r.minY + 1), facingRight: left)
                label(room.floor < 0 ? "FD ↓" : "FD ↑", at: CGPoint(x: r.minX + 4, y: r.minY + 10), size: 6, color: 0xFFE8A0)
            }
            if state.stage == .extinguishing {
                let startX = target.x
                let width = max(6,abs(r.midX-startX))
                drawImage("effect.3.\(animationPhase(game))",in:CGRect(x:left ? startX : startX-width,y:r.minY+6,width:width,height:8),flipped:left)

            }
        }
    }
}
