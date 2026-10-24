import AppKit
import TowerCore

extension GameController {
    func addServiceDetails(for room: Room, _ add: (NSView) -> Void) {
        if let amounts = serviceCoverage.rooms[room.id] {
            add(separator())
            add(textLabel(room.people == 0 ? "Service for future tenants" : "Neighborhood services", size: 14, weight: .bold))
            for service in NeighborhoodService.allCases {
                guard let amount = amounts[service] else { continue }
                add(textLabel("\(service.title) · \(amount.percent)%", size: 13, weight: .medium))
                let meter = NSProgressIndicator()
                meter.style = .bar; meter.isIndeterminate = false
                meter.minValue = 0; meter.maxValue = 1; meter.doubleValue = amount.ratio
                meter.setAccessibilityLabel("\(service.title) coverage: \(amount.percent) percent")
                add(meter)
                add(textLabel(amount.explanation, size: 11, color: Theme.muted))
                if amount.isShort {
                    add(serviceBuildButton(service, near: room.id))
                }
            }
            add(textLabel(room.people == 0 ? "Estimated for a full room using spare capacity. Empty rooms reserve no service." : "Shortages reduce happiness and limit occupancy. Add service nearby as the neighborhood grows.", size: 11, color: Theme.muted))
        } else if room.kind.needsNeighborhoodServices {
            add(separator())
            add(textLabel("Neighborhood services paused", size: 14, weight: .bold))
            add(textLabel("Restore access or resolve this room’s incident to resume service demand.", size: 11, color: Theme.muted))
        }
        if let venue = serviceCoverage.venues[room.id] {
            add(separator()); add(textLabel("\(venue.service.title) service", size: 14, weight: .bold))
            add(textLabel(venue.operational ? "Serving \(Int(venue.served.rounded())) / \(venue.capacity) neighbors" : "Service unavailable", size: 13, weight: .medium))
            add(textLabel("Reaches \(venue.service.floorRange) floors above and below, within \(venue.service.horizontalRange) cells horizontally. Requires lobby access.", size: 11, color: Theme.muted))
            if !venue.operational {
                add(textLabel("Restore access or resolve the incident to reopen service.", size: 11, color: Theme.muted))
            }
        }
    }

    func serviceBuildButton(_ service: NeighborhoodService, near roomID: Int) -> ActionButton {
        ActionButton("Add \(service == .food ? "food" : "shops") nearby", symbol: service.symbol, action: { [weak self] in
            guard let self, let room = self.game.rooms.first(where: { $0.id == roomID }) else { return }
            self.setCoverageOverlay(service)
            self.revealRoom(roomID)
            self.roomBrowser.select(service.defaultRoom)
            guard self.selectedKind == service.defaultRoom else { return }
            self.message("Place a \(service.defaultRoom.title.lowercased()) near floor \(TowerState.floorLabel(room.floor)). Reach: ±\(service.floorRange) floors, \(service.horizontalRange) cells horizontally.")
        })
    }

    func addServiceSummary(_ add: (NSView) -> Void, shortagesOnly: Bool) {
        add(textLabel("Neighborhood services", size: 15, weight: .bold))
        let floors = serviceCoverage.floors.keys.sorted()
        let shortFloors = floors.filter { floor in NeighborhoodService.allCases.contains { serviceCoverage.floors[floor]?[$0]?.isShort == true } }
        if floors.isEmpty {
            add(textLabel("Food and shop demand starts when homes and workplaces fill up.", size: 12, color: Theme.muted))
        } else if shortFloors.isEmpty {
            add(textLabel("All occupied neighborhoods have food and shops within reach.", size: 12, color: Theme.muted))
        } else {
            add(textLabel("\(shortFloors.count) \(shortFloors.count == 1 ? "floor needs" : "floors need") more service", size: 12, weight: .medium))
        }
        for floor in shortagesOnly ? shortFloors : floors {
            add(textLabel("Floor \(TowerState.floorLabel(floor))", size: 13, weight: .bold))
            for service in NeighborhoodService.allCases {
                guard let amount = serviceCoverage.floors[floor]?[service] else { continue }
                add(textLabel("\(service.title) · \(amount.percent)% covered", size: 12))
                if amount.isShort {
                    let missing = Int(ceil(amount.demand - amount.served - 0.000001))
                    add(textLabel("\(missing) neighbors need more \(service == .food ? "food service" : "shopping service").", size: 11, color: Theme.muted))
                    let affected = game.rooms.filter { $0.floor == floor && serviceCoverage.rooms[$0.id]?[service]?.isShort == true }
                        .sorted { a, b in
                            let ar = serviceCoverage.rooms[a.id]?[service]?.ratio ?? 1, br = serviceCoverage.rooms[b.id]?[service]?.ratio ?? 1
                            return ar == br ? a.id < b.id : ar < br
                        }
                    if let room = affected.first { add(serviceBuildButton(service, near: room.id)) }
                }
            }
            add(separator())
        }
    }
}
