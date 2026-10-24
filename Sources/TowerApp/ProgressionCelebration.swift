import AppKit
import QuartzCore

/// Rare milestones get a short burst of motion; the reward remains readable.
/// Animation uses wall time, independently of simulation speed or pause state.
final class ProgressionCelebrationView: NSView {
    private let isLevelUp: Bool
    private var dismissal: DispatchWorkItem?
    private var particles: [CALayer] = []
    private(set) var isDismissed = false

    init(eyebrow: String, title: String, detail: String, reward: String, isLevelUp: Bool, action: @escaping () -> Void) {
        self.isLevelUp = isLevelUp
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x173C4C).cgColor
        layer?.cornerRadius = 16
        layer?.borderColor = Theme.gold.withAlphaComponent(0.75).cgColor; layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 16; layer?.shadowOffset = CGSize(width: 0, height: -5)
        let badge = textLabel(eyebrow, size: 11, weight: .bold, color: Theme.gold)
        let heading = textLabel(title, size: isLevelUp ? 26 : 21, weight: .bold, color: .white)
        let description = textLabel(detail, size: 13, color: NSColor(hex: 0xD5E7EE))
        let prize = textLabel(reward, size: 14, weight: .semibold, color: Theme.gold)
        let explore = ActionButton(isLevelUp ? "Explore your unlocks" : "View ambitions", symbol: "arrow.right", action: { [weak self] in self?.dismissImmediately(); action() })
        let close = ActionButton("Dismiss", action: { [weak self] in self?.dismissImmediately() })
        explore.contentTintColor = .white; close.contentTintColor = .white
        for button in [explore, close] {
            button.appearance = NSAppearance(named: .darkAqua)
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
            ])
        }
        close.setAccessibilityLabel("Dismiss reward celebration")
        let controls = hstack([explore, close], spacing: 6)
        let stack = vstack([badge, heading, description, prize, controls], spacing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        for child in [badge, heading, description, prize] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(eyebrow). \(title). \(detail). \(reward)")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { dismissal?.cancel() }

    func present() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.15 : 0.28
            animator().alphaValue = 1
        }
        if !reduced, let layer {
            let entrance = CAKeyframeAnimation(keyPath: "transform")
            entrance.values = [0.94, 1.025, 1.0].map { scale -> NSValue in
                var transform = CATransform3DMakeScale(scale, scale, 1)
                transform.m41 = bounds.width * (1-scale) / 2
                transform.m42 = bounds.height * (1-scale) / 2
                return NSValue(caTransform3D: transform)
            }
            entrance.keyTimes = [0, 0.65, 1]
            entrance.duration = 0.45; entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(entrance, forKey: "milestoneEntrance")
            burst(count: isLevelUp ? 28 : 10)
        }
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: accessibilityLabel() ?? "Reward unlocked", .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
        let work = DispatchWorkItem { [weak self] in self?.dismissAnimated() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isLevelUp ? 10 : 6), execute: work)
    }

    private func burst(count: Int) {
        guard let layer else { return }
        for index in 0..<count {
            let particle = CALayer()
            let colors = [Theme.gold, NSColor(hex: 0x75D8D0), NSColor(hex: 0xFFF2C7), NSColor(hex: 0xEEA282)]
            particle.backgroundColor = colors[index % colors.count].cgColor
            particle.bounds = CGRect(x: 0, y: 0, width: index % 3 == 0 ? 5 : 3, height: 7)
            particle.cornerRadius = 1; particle.opacity = 0
            let start = CGPoint(x: bounds.midX, y: bounds.maxY - 14)
            particle.position = start; layer.addSublayer(particle); particles.append(particle)
            let spread = CGFloat(index) / CGFloat(max(1, count - 1)) * 2 - 1
            let path = CGMutablePath(); path.move(to: start)
            path.addQuadCurve(to: CGPoint(x: start.x + spread * bounds.width * 0.65, y: bounds.minY - 22), control: CGPoint(x: start.x + spread * bounds.width * 0.7, y: start.y + CGFloat(65 + index % 5 * 12)))
            let motion = CAKeyframeAnimation(keyPath: "position"); motion.path = path
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.08, 0.65, 1]
            let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = 0; spin.toValue = (index % 2 == 0 ? 1 : -1) * Double.pi * 3
            let group = CAAnimationGroup(); group.animations = [motion, fade, spin]
            group.duration = 1.3 + Double(index % 5) * 0.08
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            particle.add(group, forKey: "confetti")
        }
    }

    private func dismissAnimated() {
        guard !isDismissed else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2; animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.dismissImmediately() })
    }

    func dismissImmediately() {
        dismissal?.cancel(); dismissal = nil; isDismissed = true
        layer?.removeAllAnimations()
        for particle in particles { particle.removeAllAnimations(); particle.removeFromSuperlayer() }
        particles.removeAll(); removeFromSuperview()
    }
}
