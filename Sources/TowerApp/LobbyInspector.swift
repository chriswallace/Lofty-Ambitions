import AppKit
import TowerCore

extension GameController {
    func addLobbyDetails(_ add: (NSView) -> Void, showHeading: Bool = true) {
        if showHeading { add(textLabel(game.effectiveLobbyStyle.title, size: 15, weight: .semibold)) }
        if game.lobbyHeight == 4 {
            add(textLabel("Four-floor atrium · Floors G–3\nMarble reception and upper galleries.\n+3% tower happiness · $350/day upkeep", size: 12, color: Theme.muted))
        } else {
            let benefits = game.effectiveLobbyStyle == .grand ? "Keeps your current happiness bonus and upkeep." : "+3% tower happiness\n+$250/day upkeep"
            add(textLabel("Grand Lobby · Level \(TowerState.grandLobbyLevel)\n$\(game.lobbyUpgradeCost.formatted()) to upgrade\n\(benefits)", size: 12))
            add(textLabel("Creates a four-floor atrium (G–3). All existing rooms move up 3 floors; ground elevators extend with them. Contents and leases are preserved.", size: 11, color: Theme.muted))
            let button = ActionButton("Upgrade to Grand Lobby", symbol: "building.columns") { [weak self] in
                guard let self else { return }
                if self.performCommand(.upgradeLobby) { self.message("Four-floor Grand Lobby opened! Existing rooms moved up 3 floors.") }
            }
            button.isEnabled = game.lobbyUpgradeBlocker == nil
            button.toolTip = game.lobbyUpgradeBlocker
            add(button)
            if let blocker = game.lobbyUpgradeBlocker { add(textLabel(blocker, size: 11, color: Theme.muted)) }
        }
    }
}
