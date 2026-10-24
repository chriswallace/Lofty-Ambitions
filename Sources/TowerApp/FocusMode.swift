import AppKit
import TowerCore

extension GameController {
    func setupFocusMode() {
        focusBar = PanelView(Theme.surface)
        focusBar.wantsLayer = true; focusBar.layer?.cornerRadius = 10
        focusBar.translatesAutoresizingMaskIntoConstraints = false
        focusPauseButton = ActionButton("Pause", symbol: "pause.fill") { [weak self] in self?.togglePause() }
        focusIssuesButton = ActionButton("Issues", symbol: "exclamationmark.bubble") { [weak self] in self?.showRoomIssues() }
        let exit = ActionButton("Exit focus", symbol: "sidebar.left") { [weak self] in self?.setFocusMode(false) }
        exit.toolTip = "Show controls again. Tab or Esc."
        let controls = hstack([focusPauseButton, focusIssuesButton, exit], spacing: 8)
        controls.translatesAutoresizingMaskIntoConstraints = false
        focusBar.addSubview(controls); view.addSubview(focusBar)
        NSLayoutConstraint.activate([
            focusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            focusBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            controls.leadingAnchor.constraint(equalTo: focusBar.leadingAnchor, constant: 10),
            controls.trailingAnchor.constraint(equalTo: focusBar.trailingAnchor, constant: -10),
            controls.topAnchor.constraint(equalTo: focusBar.topAnchor, constant: 8),
            controls.bottomAnchor.constraint(equalTo: focusBar.bottomAnchor, constant: -8)
        ])
        focusBar.isHidden = true
    }
    @objc func toggleFocusMode() { setFocusMode(!focusMode) }
    func setFocusMode(_ enabled: Bool) {
        guard enabled != focusMode else { return }
        if enabled {
            // Cancel placement before hiding controls. Focus mode supports camera
            // navigation only, so hidden tools can never alter a tower.
            choose(nil)
            gameView.hovered = nil; gameView.hoveredSignal = nil
            gameView.startDrag = nil; gameView.startCell = nil; gameView.placementReason = nil
        }
        focusMode = enabled
        NSLayoutConstraint.deactivate(enabled ? regularCanvasConstraints : focusCanvasConstraints)
        NSLayoutConstraint.activate(enabled ? focusCanvasConstraints : regularCanvasConstraints)
        for chrome in chromeViews { chrome.isHidden = enabled }
        focusBar.isHidden = !enabled
        focusMenuItem?.state = enabled ? .on : .off
        view.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(gameView)
        updateUI(rebuildInspector: true)
    }
    func addLevelDetails(_ add: (NSView) -> Void) {
        add(textLabel("Level \(game.level.number) · \(game.level.title)", size: 17, weight: .semibold))
        if let next = game.nextLevel {
            add(textLabel("Next: \(next.title)", size: 13, weight: .medium))
            let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false
            bar.minValue = 0; bar.maxValue = 1; bar.doubleValue = game.levelProgress
            bar.setAccessibilityLabel("Progress toward level \(next.number)"); add(bar)
            for requirement in game.levelRequirements {
                add(textLabel("\(requirement.complete ? "✓" : "○")  \(requirement.text)", size: 12, color: requirement.complete ? Theme.accent : Theme.muted))
            }
            add(textLabel("Unlocks \(next.unlockTitles.joined(separator: ", "))\n$\(next.grant.formatted()) development grant", size: 12))
        } else {
            add(textLabel("Skyline icon. All rooms and four basement permits are yours! Finish your ambitions and keep your districts thriving.", size: 13, color: Theme.accent))
        }
        addAmbitionDetails(add)
        addAbilityDetails(add)
        addUndergroundDetails(add)
        add(separator())
        add(textLabel("Unlock roadmap", size: 14, weight: .semibold))
        for level in TowerLevel.all.dropFirst() {
            let state = level.number <= game.stars ? "✓" : "Level \(level.number)"
            add(textLabel("\(state) · \(level.title)\n\(level.unlockTitles.joined(separator: ", "))", size: 12, color: level.number <= game.stars ? Theme.ink : Theme.muted))
        }
    }
}
