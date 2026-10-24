import Foundation
import TowerCore
import TowerArt

extension TowerScene {
    public func elevatorFootprint(_ index: Int, _ game: TowerState) -> CGRect {
        let lift = game.elevators[index]
        return CGRect(x: shaftX(index), y: CGFloat(lift.bottom)*24,
                      width: CGFloat(lift.footprintWidth)*8, height: CGFloat(lift.topFloor-lift.bottom+1)*24)
    }

    public func grandLobbyComposition(_ game: TowerState, in rect: CGRect) -> LobbyComposition {
        LobbyComposition(bounds: rect, shafts: game.elevators.indices.map { elevatorFootprint($0, game) })
    }

    func drawGrandLobby(_ game: TowerState, in rect: CGRect) {
        pushClip(rect)
        // Continuous quiet architecture stays visible behind glass lift shafts.
        for x in stride(from: rect.minX, to: rect.maxX, by: 256) {
            drawImage("lobby.grandWall", in: CGRect(x: x, y: rect.minY, width: 256, height: rect.height))
        }
        let layout = grandLobbyComposition(game, in: rect)
        if let feature = layout.feature { drawImage("lobby.grandFeature", in: feature) }
        // One continuous cornice and floor unite the bays and elevator banks.
        fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2), 0x39464A)
        fill(CGRect(x: rect.minX, y: rect.minY+2, width: rect.width, height: 0.5), 0xDAC18B)
        fill(CGRect(x: rect.minX, y: rect.maxY-2, width: rect.width, height: 2), 0x243842)
        fill(CGRect(x: rect.minX, y: rect.maxY-3, width: rect.width, height: 1), 0xB59963)
        popClip()
    }
}
