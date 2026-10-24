import AppKit
import TowerCore
import TowerArt

/// The catalog owns browsing state, independently of the active construction tool.
final class RoomBrowserView: NSView, NSSearchFieldDelegate {
    let atlas: TowerAtlas
    let searchField = NSSearchField()
    let categoryPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let countLabel = textLabel("", size: 11, color: Theme.muted)
    let roomList = NSStackView()
    let details = NSStackView()
    let detailPanel = PanelView(Theme.surface)
    private var rows: [RoomCatalogRow] = []
    private var availabilityLabel: NSTextField?
    private(set) var selection: RoomKind? = .office
    private var category: RoomCategory?
    private var stars = 1
    private var cash = 0
    private var building: RoomKind?
    var onBrowse: ((RoomKind?) -> Void)?
    var onBuild: ((RoomKind) -> Void)?

    init(atlas: TowerAtlas) {
        self.atlas = atlas
        super.init(frame: .zero)
        let heading = textLabel("Rooms", size: 19, weight: .semibold)
        searchField.placeholderString = "Search rooms"
        searchField.font = .systemFont(ofSize: 13)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityLabel("Search room catalog")
        categoryPicker.addItem(withTitle: "All categories")
        for category in RoomCatalog.categories { categoryPicker.addItem(withTitle: category.title) }
        categoryPicker.target = self; categoryPicker.action = #selector(changeCategory)
        categoryPicker.font = .systemFont(ofSize: 12)
        categoryPicker.setAccessibilityLabel("Room category")
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        roomList.orientation = .vertical; roomList.alignment = .leading; roomList.spacing = 2
        roomList.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(roomList)
        details.orientation = .vertical; details.alignment = .leading; details.spacing = 7
        details.translatesAutoresizingMaskIntoConstraints = false; detailPanel.addSubview(details)
        let divider = separator()
        for child in [heading, countLabel, searchField, categoryPicker, scroll, detailPanel, divider] {
            child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), heading.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), countLabel.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12), searchField.heightAnchor.constraint(equalToConstant: 28),
            categoryPicker.leadingAnchor.constraint(equalTo: searchField.leadingAnchor), categoryPicker.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            categoryPicker.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 7), categoryPicker.heightAnchor.constraint(equalToConstant: 26),
            scroll.topAnchor.constraint(equalTo: categoryPicker.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: detailPanel.topAnchor),
            detailPanel.leadingAnchor.constraint(equalTo: leadingAnchor), detailPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailPanel.bottomAnchor.constraint(equalTo: bottomAnchor), detailPanel.heightAnchor.constraint(equalToConstant: 180),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor), divider.trailingAnchor.constraint(equalTo: trailingAnchor), divider.topAnchor.constraint(equalTo: detailPanel.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            roomList.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 6), roomList.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -6),
            roomList.topAnchor.constraint(equalTo: document.topAnchor, constant: 2), roomList.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
            details.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 14), details.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor, constant: -14),
            details.topAnchor.constraint(equalTo: detailPanel.topAnchor, constant: 12), details.bottomAnchor.constraint(lessThanOrEqualTo: detailPanel.bottomAnchor, constant: -10)
        ])
        refreshRows()
    }
    required init?(coder: NSCoder) { fatalError() }

    func controlTextDidChange(_ obj: Notification) { refreshRows(notify: true) }
    @objc private func changeCategory() {
        let index = categoryPicker.indexOfSelectedItem-1
        category = RoomCatalog.categories.indices.contains(index) ? RoomCatalog.categories[index] : nil
        refreshRows(notify: true)
    }
    func focusSearch() { window?.makeFirstResponder(searchField) }
    func select(_ kind: RoomKind) {
        // Menu selections also reveal rooms outside the current search or category.
        if !RoomCatalog.search(query: searchField.stringValue, category: category).contains(where: { $0.kind == kind }) {
            searchField.stringValue = ""; category = nil; categoryPicker.selectItem(at: 0)
        }
        selection = kind; refreshRows()
        // Rows are recreated when browsing; resolve their frames before revealing
        // a menu selection so its title cannot end up above the viewport.
        layoutSubtreeIfNeeded()
        if let row = rows.first(where: { $0.room.kind == kind }) { row.scrollToVisible(row.bounds) }
        onBuild?(kind)
    }
    private func refreshRows(notify: Bool = false) {
        let results = RoomCatalog.search(query: searchField.stringValue, category: category)
        let oldSelection = selection
        if !results.contains(where: { $0.kind == selection }) { selection = results.first?.kind }
        for child in roomList.arrangedSubviews { roomList.removeArrangedSubview(child); child.removeFromSuperview() }
        rows = []
        countLabel.stringValue = "\(results.count) \(results.count == 1 ? "room" : "rooms")"
        for room in results {
            let row = RoomCatalogRow(room: room, atlas: atlas)
            row.onSelect = { [weak self] in self?.select(room.kind) }
            roomList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: roomList.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 54).isActive = true
            rows.append(row)
        }
        if results.isEmpty {
            let empty = textLabel("No matching rooms.\nTry another search or category.", size: 12, color: Theme.muted)
            roomList.addArrangedSubview(empty); empty.widthAnchor.constraint(equalTo: roomList.widthAnchor).isActive = true
            let clear = ActionButton("Clear filters") { [weak self] in
                guard let self else { return }
                self.searchField.stringValue = ""; self.category = nil; self.categoryPicker.selectItem(at: 0); self.refreshRows(notify: true)
            }
            roomList.addArrangedSubview(clear)
        }
        rebuildDetails(); refreshSelection()
        if notify && selection != oldSelection { onBrowse?(selection) }
    }
    private func rebuildDetails() {
        for child in details.arrangedSubviews { details.removeArrangedSubview(child); child.removeFromSuperview() }
        availabilityLabel = nil
        func add(_ child: NSView) { details.addArrangedSubview(child); child.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true }
        guard let kind = selection else { add(textLabel("Choose a room to see its details.", size: 13, color: Theme.muted)); return }
        let room = kind.definition
        add(textLabel(room.title, size: 18, weight: .semibold))
        let description = textLabel(room.detail, size: 12, color: Theme.muted)
        description.maximumNumberOfLines = 3; description.toolTip = room.detail; add(description)
        add(textLabel("\(room.width) cells wide\(room.capacity > 0 ? " · \(room.capacity) people" : " · Tower service")", size: 12))
        let income = room.dailyRent > 0 ? "$\(room.dailyRent.formatted())/day at full occupancy\n" : ""
        add(textLabel("\(income)$\(room.upkeep.formatted())/day upkeep", size: 12, color: Theme.muted))
        let availability = textLabel("", size: 11, color: Theme.muted); add(availability); availabilityLabel = availability
        refreshAvailability()
    }
    private func refreshAvailability() {
        guard let kind = selection else { return }
        let room = kind.definition
        let blocker = room.buildBlocker(stars: stars, cash: cash)
        let floors = kind.canBuildUnderground ? "Any floor" : "Above ground"
        availabilityLabel?.stringValue = blocker ?? (building == kind ? "\(floors) · Click or drag to build" : (kind.canBuildUnderground ? "Above ground or underground" : "Above ground only"))
        availabilityLabel?.isHidden = false
        availabilityLabel?.textColor = stars >= room.requiredStars && cash < room.cost ? .systemRed : Theme.muted
    }
    private func refreshSelection() {
        for row in rows {
            row.selected = selection == row.room.kind
            row.unlocked = stars >= row.room.requiredStars
            let selectionState = row.selected ? "Selected" : "Not selected"
            row.setAccessibilityValue(row.unlocked ? selectionState : "\(selectionState), Locked, level \(row.room.requiredStars) required")
            row.needsDisplay = true
        }
    }
    func update(stars: Int, cash: Int, building: RoomKind?) {
        let changed = self.stars != stars
        self.stars = stars; self.cash = cash; self.building = building
        if changed { refreshSelection() }
        refreshAvailability()
    }
}

/// A compact list row uses the actual room art, with text that remains readable
/// when there are dozens of room types. Locked rooms stay browsable.
final class RoomCatalogRow: NSButton {
    let room: RoomDefinition
    let atlas: TowerAtlas
    override var isFlipped: Bool { false }
    var onSelect: (() -> Void)?
    var selected = false
    var unlocked = true
    init(room: RoomDefinition, atlas: TowerAtlas) {
        self.room = room; self.atlas = atlas
        super.init(frame: .zero)
        title = room.title; isBordered = false
        setButtonType(.momentaryChange); focusRingType = .exterior
        target = self; action = #selector(activate)
        setAccessibilityLabel("\(room.title), $\(room.cost.formatted()), \(room.width) cells, unlocks at level \(room.requiredStars)")
        toolTip = "\(room.title) · $\(room.cost.formatted()) · \(room.width) cells\n\(room.detail)\nUnlocks at level \(room.requiredStars)."
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activate() { onSelect?() }
    override func draw(_ dirtyRect: NSRect) {
        if selected || isHighlighted {
            (selected ? Theme.selection : Theme.surface).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
        let preview = CGRect(x: 8, y: 8, width: 72, height: 38)
        Theme.previewSky.setFill(); NSBezierPath(roundedRect: preview, xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: preview).addClip()
        atlas.room(room.kind.rawValue, state: .open, in: preview.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.restoreGraphicsState()
        let titleStyle = NSMutableParagraphStyle(); titleStyle.lineBreakMode = .byTruncatingTail
        (room.title as NSString).draw(in: CGRect(x: 90, y: 28, width: bounds.width-100, height: 19), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Theme.ink, .paragraphStyle: titleStyle
        ])
        var subtitleX: CGFloat = 90
        if !unlocked {
            let level = "Level \(room.requiredStars)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: Theme.ink
            ]
            let textSize = level.size(withAttributes: attributes)
            let pill = CGRect(x: 90, y: 7, width: ceil(textSize.width) + 29, height: 20)
            Theme.muted.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [Theme.ink]))
            if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                lock.draw(in: CGRect(x: pill.minX + 7, y: pill.midY - 6, width: 9, height: 12))
            }
            level.draw(at: CGPoint(x: pill.minX + 21, y: pill.midY - textSize.height / 2), withAttributes: attributes)
            subtitleX = pill.maxX + 7
        }
        let subtitle = unlocked ? "$\(room.cost.formatted()) · \(room.width) cells" : "$\(room.cost.formatted())"
        (subtitle as NSString).draw(in: CGRect(x: subtitleX, y: 9, width: max(0, bounds.width-subtitleX-10), height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.muted, .paragraphStyle: titleStyle
        ])
    }
}
