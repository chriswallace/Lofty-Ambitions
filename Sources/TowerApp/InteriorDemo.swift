import TowerCore

extension GameController {
    /// Disposable visual fixture; screenshot-exit launches never write autosaves.
    func setupInteriorDemo() throws {
        game = .newGame(scenerySeed:20260929)
        game.cash = 1_000_000; game.earnedStars = 4; speed = 0
        game.floorSpans = [0:FloorSpan(0,36)]
        for _ in 0..<3 { try game.addFloor() }
        for style in RoomStyle.allCases {
            let office = try game.build(.office,floor:1,slot:style.rawValue*9)
            try game.setRoomStyle(office,style:style)
            let apartment = try game.build(.apartment,floor:2,slot:style.rawValue*4)
            try game.setRoomStyle(apartment,style:style)
        }
        try game.build(.luxuryApartment,floor:2,slot:12)
        try game.build(.luxuryApartment,floor:3,slot:0)
        try game.build(.luxuryApartment,floor:3,slot:12)
        try game.addElevator(.standard,at:33,from:0,to:3)
        for i in game.rooms.indices where game.rooms[i].kind.capacity > 0 { game.rooms[i].occupancy = 1 }
        game.minute = 720
        roomBrowser.select(.office)
        selectedKind = nil
        selectedRoom = game.rooms.first { $0.kind == .office && $0.effectiveStyle == .two }?.id
        updateUI(rebuildInspector:true)
    }
}
