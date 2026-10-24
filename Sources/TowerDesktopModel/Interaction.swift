import Foundation
import TowerCore
import TowerSession

public enum DesktopTool: Equatable {
    case inspect, delete, floor, room(RoomKind), elevator(ElevatorKind), relocate(Int,ElevatorKind)
    public var title:String {
        switch self {
        case .inspect:return "Inspect / edit"
        case .delete:return "Delete · select a room or shaft"
        case .floor:return "Floor · drag to build or extend"
        case .room(let kind):return "Build \(kind.title) · click or drag a row"
        case .elevator(let kind):return "\(kind.title) · drag vertically"
        case .relocate:return "Relocate shaft · drag its new service range"
        }
    }
}

/// Pointer gestures become the same validated commands used by replay and both OS builds.
public final class DesktopInteraction {
    public let session:TowerSession
    public var tool:DesktopTool = .inspect
    public var selectedRoom:Int?
    public var selectedElevator:Int?
    public init(session:TowerSession) {self.session=session}
    public func cancel() {tool = .inspect;selectedRoom=nil;selectedElevator=nil}
    public func elevator(at floor:Int,slot:Int)->Int? {
        session.game.elevators.first { lift in
            floor >= lift.bottom && floor <= lift.topFloor && (lift.column.map{slot >= $0 && slot < $0+lift.footprintWidth} ?? false)
        }?.id
    }
    public func drag(from:(floor:Int,slot:Int),to:(floor:Int,slot:Int),hitElevatorID:Int?=nil) throws {
        switch tool {
        case .inspect:
            selectedElevator=hitElevatorID ?? elevator(at:to.floor,slot:to.slot)
            selectedRoom=selectedElevator == nil ? session.game.room(at:to.floor,slot:to.slot)?.id : nil
        case .delete:
            if let id=hitElevatorID ?? elevator(at:to.floor,slot:to.slot) {_ = try session.requestDemolition(.elevator(id))}
            else if let room=session.game.room(at:to.floor,slot:to.slot) {_ = try session.requestDemolition(.room(room.id))}
            else {throw TowerError("Select an occupied room or elevator shaft.")}
        case .floor:try session.execute(.constructFloor(floor:from.floor,from:from.slot,to:to.slot))
        case .room(let kind):
            if from == to {try session.execute(.build(kind,floor:from.floor,slot:from.slot))}
            else {try session.execute(.buildRow(kind,floor:from.floor,from:from.slot,to:to.slot))}
        case .elevator(let kind):
            let range=serviceRange(from.floor,to.floor)
            try session.execute(.addElevator(kind,column:from.slot,from:range.0,to:range.1))
        case .relocate(let id,_):
            let range=serviceRange(from.floor,to.floor)
            try session.execute(.relocateElevator(id,column:from.slot,from:range.0,to:range.1))
            tool = .inspect;selectedElevator=id
        }
    }
    private func serviceRange(_ a:Int,_ b:Int)->(Int,Int) {
        let g=session.game
        var lower=max(g.bottomFloor,min(a,b)),upper=min(g.topFloor,max(a,b))
        if a == b {lower=min(0,lower);upper=max(0,upper);if lower == upper && g.topFloor>=g.lobbyHeight {upper=g.lobbyHeight}}
        if lower>0 && lower<g.lobbyHeight {lower=0}
        if upper>0 && upper<g.lobbyHeight {upper=g.lobbyHeight}
        return(lower,upper)
    }
}

public struct DesktopModalFocus {
    public private(set) var acceptsReturn=false
    public init() {}
    public mutating func begin() {acceptsReturn=false}
    public mutating func selectContinue() {acceptsReturn=true}
    public mutating func selectCancel() {acceptsReturn=false}
    public mutating func toggle() {acceptsReturn.toggle()}
}

public enum DesktopPersistence {
    public static func finishSession(_ session:TowerSession,autosaveURL:URL,store:TowerSaveStore,autosaveBlocked:Bool) throws {
        if session.hasUnsavedChanges {_ = try store.preserve(session.game)}
        if !autosaveBlocked {try session.autosave(to:autosaveURL,store:store)}
    }
}

public enum DesktopPaths {
    public static func applicationData()->URL {
        #if os(Windows)
        if let local=ProcessInfo.processInfo.environment["LOCALAPPDATA"] {return URL(fileURLWithPath:local).appendingPathComponent("LoftyAmbitions",isDirectory:true)}
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local/LoftyAmbitions",isDirectory:true)
        #else
        // Developer portable frontend is isolated from the native Mac application's saves.
        return (FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("LoftyAmbitionsDesktop",isDirectory:true)
        #endif
    }
}
