import AppKit

/// The artwork is decorative; the entry control stays native and keyboard accessible.
final class TitleScreenView: NSView {
    let artwork: NSImage
    let enterButton: ActionButton

    init(artwork: NSImage, onEnter: @escaping () -> Void) {
        self.artwork = artwork
        enterButton = ActionButton("Enter Tower", symbol: "arrow.right", action: onEnter)
        super.init(frame: .zero)
        enterButton.controlSize = .large
        enterButton.font = .systemFont(ofSize: 16, weight: .semibold)
        enterButton.bezelColor = Theme.accent
        enterButton.contentTintColor = .white
        enterButton.keyEquivalent = "\r"
        enterButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(enterButton)
        NSLayoutConstraint.activate([
            enterButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            enterButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
            enterButton.widthAnchor.constraint(equalToConstant: 190),
            enterButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        setAccessibilityLabel("Lofty Ambitions title screen")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0x152D38).setFill(); bounds.fill()
        let scale = max(bounds.width / artwork.size.width, bounds.height / artwork.size.height)
        let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
        let destination = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        artwork.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
        // Keep the entry button readable without covering the illustrated title.
        NSGradient(starting: NSColor(hex: 0x152D38, alpha: 0.85), ending: .clear)?
            .draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 150), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension GameController {
    @discardableResult func showTitleScreen() -> Bool {
        guard titleScreen == nil,
              let artwork = NSImage(contentsOf: gameView.atlas.resourceURL.appendingPathComponent("TitleScreen.png")) else { return false }
        titleScreenSpeed = speed
        speed = 0
        titleScreenHiddenViews = view.subviews.map { ($0, $0.isHidden) }
        for (child, _) in titleScreenHiddenViews { child.isHidden = true }
        let screen = TitleScreenView(artwork: artwork) { [weak self] in self?.enterTowerFromTitleScreen() }
        titleScreen = screen
        screen.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen)
        NSLayoutConstraint.activate([
            screen.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            screen.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            screen.topAnchor.constraint(equalTo: view.topAnchor),
            screen.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Keep About and Quit available, without exposing construction commands
        // for the tower hidden behind the title screen.
        titleScreenMenu = NSApp.mainMenu
        let launchMenu = NSMenu()
        if let applicationMenu = titleScreenMenu?.items.first?.copy() as? NSMenuItem { launchMenu.addItem(applicationMenu) }
        NSApp.mainMenu = launchMenu
        view.window?.makeFirstResponder(screen.enterButton)
        return true
    }

    func enterTowerFromTitleScreen() {
        guard let screen = titleScreen else { return }
        screen.removeFromSuperview()
        titleScreen = nil
        for (child, wasHidden) in titleScreenHiddenViews { child.isHidden = wasHidden }
        titleScreenHiddenViews = []
        NSApp.mainMenu = titleScreenMenu
        titleScreenMenu = nil
        speed = titleScreenSpeed
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        updateUI()
        view.window?.makeFirstResponder(gameView)
    }
}
