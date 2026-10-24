import AppKit
import TowerCore

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(srgbRed:CGFloat((hex >> 16) & 255)/255,green:CGFloat((hex >> 8) & 255)/255,blue:CGFloat(hex & 255)/255,alpha:alpha)
    }
}
enum Theme {
    static let ink = NSColor(hex:0x243647)
    static let muted = NSColor(hex:0x5B6E7A)
    static let panel = NSColor(hex:0xEDF2F5)
    static let surface = NSColor(hex:0xF8FAFB)
    static let chrome = NSColor(hex:0xE4EBEF)
    static let selection = NSColor(hex:0xD5E7EE)
    static let previewSky = NSColor(hex:0xCBE0E9)
    static let accent = NSColor(hex:0x246A83)
    static let gold = NSColor(hex:0xD6B06C)

}
func textLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = Theme.ink) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString:text)
    label.font = .systemFont(ofSize:size,weight:weight)
    label.textColor = color
    label.isSelectable = false
    return label
}
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame:.zero)
        self.title = title; self.actionBlock = action
        bezelStyle = title.contains("\n") ? .smallSquare : .rounded; controlSize = .regular
        font = .systemFont(ofSize:12,weight:.medium)
        target = self; self.action = #selector(performAction)
        if let symbol { image = NSImage(systemSymbolName:symbol, accessibilityDescription:nil); imagePosition = .imageLeading }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func performAction() { actionBlock?() }
}
final class PanelView: NSView {
    let color: NSColor
    init(_ color: NSColor) { self.color = color; super.init(frame:.zero); wantsLayer = true; layer?.backgroundColor = color.cgColor }
    required init?(coder: NSCoder) { fatalError() }
}
func vstack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views:views)
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
    return stack
}
func hstack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views:views)
    stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
    return stack
}
func separator() -> NSView {
    let view = NSBox(); view.boxType = .separator; return view
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
