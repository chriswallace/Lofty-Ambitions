import AppKit
import TowerCore
import TowerSession

extension GameController {
    func makeDemolitionAlert(for target: DemolitionTarget) throws -> NSAlert {
        let quote = try game.demolitionQuote(for: target)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = quote.title
        alert.informativeText = "\(quote.consequences)\n\nYou receive $\(quote.refund.formatted()) back (50% of construction cost).\nThis cannot be undone."
        alert.addButton(withTitle: "Keep it")
        alert.buttons[0].keyEquivalent = "\r"
        let label: String
        switch target { case .room: label = "Delete Room"; case .elevator: label = "Delete Entire Shaft" }
        let remove = alert.addButton(withTitle: label)
        remove.keyEquivalent = ""
        remove.hasDestructiveAction = true
        return alert
    }

    func requestDemolition(_ target: DemolitionTarget) {
        guard pendingDemolitionAlert == nil, let window = view.window else { return }
        do {
            let alert = try makeDemolitionAlert(for: target)
            let previousSpeed = speed
            pendingDemolitionAlert = alert
            speed = 0
            updateUI()
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                self.pendingDemolitionAlert = nil
                self.speed = previousSpeed
                self.lastFrameTime = ProcessInfo.processInfo.systemUptime
                if response == .alertSecondButtonReturn {
                    let removed = self.performCommand(.demolish(TowerDemolitionTarget(target),confirmed:true))
                    if removed { self.selectedRoom = nil; self.selectedElevator = nil; self.message("Removed. 50% of construction cost refunded.") }
                } else { self.message("Deletion cancelled.") }
                self.updateUI(rebuildInspector: true)
                self.view.window?.makeFirstResponder(self.gameView)
            }
        } catch { message(error.localizedDescription) }
    }
}
