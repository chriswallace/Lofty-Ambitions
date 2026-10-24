import Foundation
import TowerCore

/// View-only state: the overlay always describes the controller's cached allocation.
public struct SceneCoverageMark {
    public enum State { case covered, partial, missing, inactive, vacant, venue }
    public let state: State
    public let label: String
    public let detail: String
    public var color: Int {
        switch state {
        case .covered: return 0x267D69
        case .partial: return 0x8B5C10
        case .missing: return 0xBA4A44
        case .inactive, .vacant: return 0x677480
        case .venue: return 0x376AA5
        }
    }
}


extension SceneCoverageMark {
    public static func mark(for room:Room,service:NeighborhoodService,allocation serviceCoverage:NeighborhoodCoverage)->SceneCoverageMark? {
        if let venue = serviceCoverage.venues[room.id], venue.service == service {
            return SceneCoverageMark(state: venue.operational ? .venue : .inactive,
                label: venue.operational ? "\(Int(venue.served.rounded()))/\(venue.capacity)" : "Closed",
                detail: venue.operational ? "Serving \(Int(venue.served.rounded())) of \(venue.capacity) neighbors" : "Service unavailable · restore access or resolve the incident")
        }
        guard room.kind.needsNeighborhoodServices else { return nil }
        guard let amount = serviceCoverage.rooms[room.id]?[service] else {
            return SceneCoverageMark(state: .inactive, label: "Paused", detail: "Demand paused · restore access or resolve the incident")
        }
        if room.people == 0 {
            return SceneCoverageMark(state: .vacant, label: "Empty", detail: "Empty · estimated \(amount.percent)% coverage at full occupancy")
        }
        return SceneCoverageMark(state: !amount.isShort ? .covered : amount.served < 0.000001 ? .missing : .partial,
            label: "\(amount.percent)%", detail: "\(amount.percent)% covered · \(amount.explanation.lowercased())")
    }
}
