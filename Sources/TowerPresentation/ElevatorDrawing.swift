import Foundation
import TowerCore

extension TowerScene {
    /// Show a grounded sample of a busy queue. Simulation passengers stay intact;
    /// overflowing the landing must not stack sprites above the corridor floor.
    public func waitingPosition(for person: Traveler, ordinal: Int, _ game: TowerState) -> CGPoint? {
        guard ordinal >= 0, ordinal < 8 else { return nil }
        let y = CGFloat(person.floor)*24+2.5
        guard let id = person.boardingElevatorID, let index = game.elevators.firstIndex(where: { $0.id == id }) else {
            return ordinal == 0 ? CGPoint(x: personX(person.x), y: y) : nil
        }
        let portal = elevatorLandingRect(index, floor: person.floor, game)
        let nextShaft = game.elevators.indices.filter { $0 != index }.map { elevatorFootprint($0,game) }
            .filter { $0.minX >= portal.maxX && $0.minY <= y && $0.maxY > y }.map(\.minX).min()
        // The widest standing civilian is 4.18pt at this scale. Give each person
        // a little breathing room and keep the outer body clear of the next bank.
        let right = min(spanRect(person.floor).maxX, nextShaft ?? .greatestFiniteMagnitude)-2.25
        let x = portal.midX+CGFloat(ordinal)*4.5
        guard x <= right else { return nil }
        return CGPoint(x: x, y: y)
    }

    public func elevatorCarRect(_ index: Int, _ game: TowerState) -> CGRect {
        let lift = game.elevators[index]
        return CGRect(x: shaftX(index)+1.5, y: CGFloat(lift.position)*24+1,
                      width: CGFloat(lift.kind.width)*8-3, height: 21)
    }

    public func elevatorLandingRect(_ index: Int, floor: Int, _ game: TowerState) -> CGRect {
        let lift = game.elevators[index]
        return CGRect(x: shaftX(index)+CGFloat(lift.kind.width)*8+0.5,
                      y: CGFloat(floor)*24+1, width: 7, height: 20)
    }

    func drawElevators(_ game: TowerState) {
        for i in game.elevators.indices {
            let lift = game.elevators[i], footprint = elevatorFootprint(i, game)
            let width = CGFloat(lift.kind.width)*8
            let shaft = CGRect(x: footprint.minX, y: footprint.minY, width: width, height: footprint.height)
            let atrium = game.lobbyHeight == 4 && lift.bottom <= 0 && lift.topFloor >= 0
            let glassTop: CGFloat = atrium ? 96 : 0
            if atrium {
                let basementHeight=max(0,-shaft.minY)
                fill(CGRect(x:footprint.minX,y:shaft.minY,width:footprint.width,height:basementHeight),0x35494E)
                fill(CGRect(x:shaft.minX,y:shaft.minY,width:shaft.width,height:basementHeight),0x172D36)
                let glass = CGRect(x: shaft.minX, y: 0, width: shaft.width, height: min(glassTop, shaft.maxY))
                fill(glass, color: SceneColor(hex: 0x345960, alpha: 0.22))
                // Glass replaces the opaque shaft wall throughout the atrium.
                fill(CGRect(x: shaft.minX, y: glassTop, width: width, height: max(0,shaft.maxY-glassTop)), 0x172D36)
                fill(CGRect(x: shaft.maxX, y: glassTop, width: 8, height: max(0,shaft.maxY-glassTop)), 0x35494E)
            } else {
                fill(footprint, 0x35494E); fill(shaft, 0x172D36)
            }
            for x in [shaft.minX, shaft.maxX-1] {
                fill(CGRect(x: x, y: shaft.minY, width: 1, height: shaft.height), 0x8C7751)
                fill(CGRect(x: x+0.25, y: shaft.minY, width: 0.25, height: shaft.height), 0xE0C998)
            }
            let car = elevatorCarRect(i, game)
            for x in [car.midX-1,car.midX+1] {
                fill(CGRect(x: x, y: car.maxY, width: 0.4, height: max(0,shaft.maxY-car.maxY)), 0x667A79)
            }
            for floor in lift.bottom...lift.topFloor where floor <= 0 || floor >= game.lobbyHeight {
                let y = CGFloat(floor)*24
                fill(CGRect(x: shaft.minX, y: y, width: 2, height: 1), 0xAC9972)
                fill(CGRect(x: shaft.maxX-2, y: y, width: 2, height: 1), 0xAC9972)
            }
            for floor in game.servedFloors(lift) {
                drawElevatorLanding(i, floor: floor, game)
            }
            pushClip(shaft)
            drawElevatorCar(i, game)
            popClip()
            // The corridor crosses in front of the cutaway shaft. Draw its
            // floor after the car/rails, but before the independently drawn people.
            // Express non-stop floors still have a corridor; the atrium void does not.
            for floor in lift.bottom...lift.topFloor where floor <= 0 || floor >= game.lobbyHeight {
                let y = CGFloat(floor)*24
                fill(CGRect(x: footprint.minX, y: y, width: footprint.width, height: 1), 0x65716C)
                fill(CGRect(x: footprint.minX, y: y+1, width: footprint.width, height: 1.5), floor == 0 ? 0xD2C8AF : 0xADB6AE)
                fill(CGRect(x: footprint.minX, y: y+2, width: footprint.width, height: 0.5), floor == 0 ? 0xF0DFB6 : 0xD4D8C8)
            }
            // A compact header identifies the bank without floating over rooms.
            let identifier = lift.kind == .express ? "E" : lift.kind == .wide ? "W" : "\(i+1)"
            fill(CGRect(x: shaft.minX, y: shaft.maxY-2, width: width, height: 2), 0xB69A65)
            label(identifier, at: CGPoint(x: shaft.maxX+2,y: shaft.maxY-8), size: 5, color: 0xEEE0BD)
        }
    }

    private func drawElevatorLanding(_ index: Int, floor: Int, _ game: TowerState) {
        let lift = game.elevators[index], r = elevatorLandingRect(index, floor: floor, game)
        let atLanding = abs(lift.position-Double(floor)) < 0.001
        let time = lift.doorTime ?? 0
        let open: CGFloat = atLanding && lift.doorsOpen ? (reducedMotion ? 1 : (time >= 7 || time <= 2 ? 0.5 : 1)) : 0
        let queued = game.activeTravelers.contains { $0.phase == .waiting && $0.floor == floor && $0.boardingElevatorID == lift.id }
        fill(r, 0xB79C66)
        fill(r.insetBy(dx: 0.75,dy: 1), 0x182D34)
        let doors = CGRect(x: r.minX+1,y: r.minY+1,width: r.width-2,height: r.height-4)
        let leaf = doors.width/2*(1-open)
        for x in [doors.minX,doors.maxX-leaf] {
            fill(CGRect(x: x,y: doors.minY,width: leaf,height: doors.height), 0x758D8B)
            if leaf > 0.5 { fill(CGRect(x: x+0.25,y: doors.minY,width: 0.25,height: doors.height), 0xC6DBCD) }
        }
        fill(CGRect(x: r.midX-0.75,y: r.maxY-2,width: 1.5,height: 0.75), open > 0 ? 0x8BE5C9 : queued ? 0xECCA7F : 0x657F7C)
        fill(CGRect(x: r.minX,y: r.minY,width: r.width,height: 1), 0xE0C68C)
        if floor == 0 && game.lobbyHeight == 4 {
            fill(CGRect(x: r.minX-0.5,y: r.maxY,width: r.width+1,height: 2), 0xDAC99E)
            fill(CGRect(x: r.minX,y: r.maxY,width: r.width,height: 0.5), 0x6A593B)
        }
    }

    private func drawElevatorCar(_ index: Int, _ game: TowerState) {
        let lift = game.elevators[index], r = elevatorCarRect(index,game)
        // Detailed empty cabin artwork, independent occupants, then subtle glass.
        drawImage("panoramicCar.\(lift.kind == .standard ? 0 : 1)", in: r)
        let inside = CGRect(x: r.minX+1.5,y: r.minY+3,width: r.width-3,height: 14)
        if game.minute < 360 || game.minute >= 1140 {
            fill(inside, color: SceneColor(hex:0x183039,alpha:0.28))
        }
        let riders = Array(game.activeTravelers.filter { $0.elevatorID == lift.id && $0.phase == .riding }.prefix(lift.kind.width*2))
        pushClip(inside)
        for (j, person) in riders.enumerated() {
            let spacing = (inside.width-2)/CGFloat(max(1,riders.count))
            self.person(at: CGPoint(x: inside.minX+1+spacing*(CGFloat(j)+0.5),y: inside.minY), id: person.id, waiting: false)
        }
        fill(inside, color: SceneColor(hex: 0x9BE1DB,alpha: 0.08))
        popClip()
    }
}
