import AppKit
import TowerCore

/// A small, persistent invitation to pursue the next goal while building.
final class AmbitionPreviewView: NSView {
    let button: ActionButton
    let detail = textLabel("", size: 11, color: Theme.muted)
    let bar = NSProgressIndicator()

    init(action: @escaping () -> Void) {
        button = ActionButton("Your first ambition", symbol: "flag.checkered", action: action)
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Theme.selection.cgColor
        button.isBordered = false; button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1; detail.lineBreakMode = .byTruncatingTail
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        for child in [button, detail, bar] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 7), button.heightAnchor.constraint(equalToConstant: 22),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 2),
            bar.leadingAnchor.constraint(equalTo: detail.leadingAnchor), bar.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            bar.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 5), bar.heightAnchor.constraint(equalToConstant: 5)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ game: TowerState) {
        let ready = game.ambitions.filter { $0.isComplete && !$0.isClaimed && $0.requiredLevel <= game.stars }
        if let goal = ready.first ?? game.visibleAmbitions.first {
            button.title = goal.isComplete ? "Claim: \(goal.title)" : goal.title
            button.image = NSImage(systemSymbolName: goal.isComplete ? "gift.fill" : "flag.checkered", accessibilityDescription: nil)
            detail.stringValue = goal.isComplete ? "+$\(goal.reward.formatted()) ready · \(ready.count) reward\(ready.count == 1 ? "" : "s")" : "$\(goal.reward.formatted()) ambition · \(Int(goal.progress*100))% complete"
            button.toolTip = goal.detail + " · Open Tower to view ambitions and claim rewards."
            bar.doubleValue = goal.progress
            bar.setAccessibilityLabel("\(goal.title): \(Int(goal.progress*100)) percent complete")
        } else {
            button.title = "\(game.ambitions.filter(\.isClaimed).count) ambitions achieved"
            detail.stringValue = game.nextLevel.map { "Next: level \($0.number) · \($0.title)" } ?? "Skyline icon · Keep your districts thriving"
            bar.doubleValue = game.levelProgress
            bar.setAccessibilityLabel("Tower level progress")
        }
        button.setAccessibilityLabel(button.title + ". " + detail.stringValue)
    }
}

extension GameController {
    func openProgression() {
        if focusMode { setFocusMode(false) }
        selectedRoom = nil; selectedElevator = nil; showingIssues = false; showingInfo = true
        updateUI(rebuildInspector: true)
        detailStack.scrollToVisible(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func addAmbitionDetails(_ add: (NSView) -> Void) {
        add(separator())
        let claimed = game.ambitions.filter(\.isClaimed)
        add(textLabel("Tower ambitions · \(claimed.count)/\(game.ambitions.count)", size: 15, weight: .semibold))
        add(textLabel("Build a place people love. Complete a goal, claim its grant, and take on the next ambition.", size: 12, color: Theme.muted))
        for goal in game.visibleAmbitions {
            add(textLabel(goal.title, size: 13, weight: .semibold))
            add(textLabel(goal.detail, size: 12, color: Theme.muted))
            let bar = NSProgressIndicator(); bar.style = .bar; bar.isIndeterminate = false
            bar.minValue = 0; bar.maxValue = 1; bar.doubleValue = goal.progress
            bar.setAccessibilityLabel("\(goal.title): \(Int(goal.progress*100)) percent complete"); add(bar)
            let claim = ActionButton(goal.isComplete ? "Claim $\(goal.reward.formatted())" : "$\(goal.reward.formatted()) · \(Int(goal.progress*100))% complete", symbol: goal.isComplete ? "gift.fill" : "flag") { [weak self] in
                self?.claimAmbitionReward(goal.id)
            }
            claim.isEnabled = goal.isComplete
            claim.toolTip = goal.isComplete ? "Collect this ambition's one-time development grant." : goal.detail
            add(claim)
        }
        if game.visibleAmbitions.isEmpty {
            add(textLabel(claimed.count == game.ambitions.count ? "Every ambition achieved. What a place you've built." : "More ambitions arrive with your next tower level.", size: 12, color: Theme.accent))
        }
        if !claimed.isEmpty { add(textLabel("Earned: " + claimed.map(\.title).joined(separator: " · "), size: 11, color: Theme.muted)) }
    }

    func claimAmbitionReward(_ id: String) {
        guard let goal = game.ambitions.first(where: { $0.id == id }) else { return }
        if performCommand(.claimAmbition(id)) {
            presentCelebration(eyebrow: "AMBITION ACHIEVED", title: goal.title, detail: "A little ambition goes a long way.", reward: "+$\(goal.reward.formatted()) development grant", isLevelUp: false)
        }
    }

    func addAbilityDetails(_ add: (NSView) -> Void) {
        add(separator()); add(textLabel("Tower abilities", size: 15, weight: .semibold))
        for ability in TowerAbility.allCases {
            add(textLabel(ability.title, size: 13, weight: .semibold))
            add(textLabel(ability.detail, size: 12, color: Theme.muted))
            let remaining = game.abilityRemainingMinutes(ability)
            let blocker = game.abilityBlocker(ability)
            let actionTitle = remaining > 0 ? "Active · \(formatGameMinutes(remaining)) left" : "Start · $\(ability.cost.formatted())"
            let button = ActionButton(actionTitle, symbol: ability.symbol) { [weak self] in
                guard let self else { return }
                if self.performCommand(.activateAbility(ability)) {
                    self.presentCelebration(eyebrow: "TOWER EVENT", title: ability.title, detail: ability.detail, reward: "Now active · \(self.formatGameMinutes(self.game.abilityRemainingMinutes(ability)))", isLevelUp: false)
                }
            }
            button.isEnabled = blocker == nil; button.toolTip = blocker ?? ability.detail; add(button)
            if let blocker, remaining == 0 {
                let cooldown = game.abilityCooldownMinutes(ability)
                add(textLabel(cooldown > 0 ? "Ready again in \(formatGameMinutes(cooldown)) of game time." : blocker, size: 11, color: Theme.muted))
            }
            if remaining > 0 { add(textLabel("Time advances with your tower. Pausing pauses the event.", size: 11, color: Theme.accent)) }
        }
    }

    func addUndergroundDetails(_ add: (NSView) -> Void) {
        add(separator()); add(textLabel("Below the surface", size: 15, weight: .semibold))
        add(textLabel(game.basementPermitDepth == 0 ? "Reach level 2 to unlock your first basement. Each new level lets you dig one floor deeper, down to B4." : "\(game.basementDepth) excavated · Permit to B\(game.basementPermitDepth)\nShops, food, services and indoor leisure can thrive underground.", size: 12, color: Theme.muted))
        let dig = ActionButton(game.basementDepth == 4 ? "All four basements open" : "Excavate B\(game.basementDepth+1) · $\(game.nextBasementCost.formatted())", symbol: "arrow.down.to.line") { [weak self] in self?.menuExcavate() }
        dig.isEnabled = game.excavationBlocker == nil; dig.toolTip = game.excavationBlocker; add(dig)
        if let blocker = game.excavationBlocker, game.basementDepth < 4 { add(textLabel(blocker, size: 11, color: Theme.muted)) }
        add(textLabel("Connect each basement to G with a local elevator. Search “underground” in Rooms for suitable spaces.", size: 12, color: Theme.muted))
        add(textLabel(game.undergroundDistrictActive ? "✓ Underground district · +15% food and retail income" : "District bonus: connect food, retail and an arcade underground for +15% basement food and retail income.", size: 12, color: game.undergroundDistrictActive ? Theme.accent : Theme.muted))
    }

    func celebrateLevelUp() {
        let level = game.level
        message("Level \(level.number): \(level.title)! $\(level.grant.formatted()) grant and new unlocks.")
        presentCelebration(eyebrow: "LEVEL \(level.number) UNLOCKED", title: level.title, detail: level.unlockTitles.joined(separator: " · "), reward: "+$\(level.grant.formatted()) development grant", isLevelUp: true)
    }

    func presentCelebration(eyebrow: String, title: String, detail: String, reward: String, isLevelUp: Bool) {
        celebration?.dismissImmediately()
        let card = ProgressionCelebrationView(eyebrow: eyebrow, title: title, detail: detail, reward: reward, isLevelUp: isLevelUp) { [weak self] in self?.openProgression() }
        celebration = card; card.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(card)
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 410); preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: gameView.centerXAnchor), card.topAnchor.constraint(equalTo: gameView.topAnchor, constant: 20),
            card.widthAnchor.constraint(lessThanOrEqualTo: gameView.widthAnchor, constant: -24), preferredWidth
        ])
        view.layoutSubtreeIfNeeded(); card.present()
    }
}
