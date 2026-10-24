// Disposable promotional capture harness. Uses production simulation and renderer.
// Does not read or write player saves, and does not change the shipped game.
import AppKit
import TowerCore
import TowerArt

@main struct PromoCapture {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let stillOnly = CommandLine.arguments.contains("--stills")
        let requestedScene: Int? = CommandLine.arguments.firstIndex(of: "--scene").flatMap { index in
            CommandLine.arguments.count > index+1 ? Int(CommandLine.arguments[index+1]) : nil
        }
        let c = GameController()
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:1920,height:1080),styleMask:[],backing:.buffered,defer:false)
        window.appearance = NSAppearance(named:.aqua)
        window.contentViewController = c
        c.view.setFrameSize(NSSize(width:1920,height:1080))
        c.view.layoutSubtreeIfNeeded()
        c.timer?.invalidate(); c.autosaveBlocked = true; c.speed = 1
        c.setFocusMode(true)
        c.view.layoutSubtreeIfNeeded()
        let v = c.gameView!
        v.frame = NSRect(x:0,y:0,width:1920,height:1080)

        func populated(_ floors: Int = 10, grand: Bool = false) throws -> TowerState {
            var g = TowerState.newGame(scenerySeed:20260920)
            g.cash = 8_000_000; g.earnedStars = 5; g.minute = 760
            for _ in 0..<floors { try g.addFloor() }
            try g.addElevator(.wide,at:30,from:0,to:floors)
            try g.addElevator(.standard,at:61,from:0,to:floors)
            let rows: [[RoomKind]] = [
                [.ramen,.shop,.cafe,.bookshop],
                [.office,.office,.coworking],
                [.apartment,.apartment,.luxuryApartment],
                [.hotel,.hotel,.housekeeping],
                [.arcade,.fitness,.spa],
                [.restaurant,.shop,.bookshop],
                [.office,.coworking,.office],
                [.luxuryApartment,.apartment,.apartment],
                [.hotel,.hotel,.housekeeping],
                [.garden,.observatory,.cafe]
            ]
            for floor in 1...floors {
                let kinds=rows[(floor-1)%rows.count]
                for start in [0,35] {
                    let limit = start == 0 ? 30 : 61
                    var slot=start; var n=0
                    while slot<limit {
                        var kind=kinds[n%kinds.count]
                        if slot+kind.width>limit {
                            guard limit-slot>=4 else {break}
                            kind = .apartment
                        }
                        try g.build(kind,floor:floor,slot:slot)
                        slot += kind.width; n += 1
                    }
                }
            }
            if grand { try g.upgradeLobby() }
            for i in g.rooms.indices where g.rooms[i].kind.capacity>0 {g.rooms[i].occupancy=0.9;g.rooms[i].happiness=0.88}
            for r in g.rooms where r.kind.capacity>0 {
                for _ in 0..<2 { try? g.requestTrip(roomID:r.id,from:0,to:r.floor) }
            }
            g.advance(minutes:4)
            return g
        }

        let base = try populated()
        var basement = try populated(5)
        try basement.excavateBasement(); try basement.excavateBasement()
        try basement.relocateElevator(basement.elevators[0].id,at:30,from:-2,to:5)
        try basement.relocateElevator(basement.elevators[1].id,at:61,from:-2,to:5)
        for floor in [-1,-2] {
            var slot=0
            for kind:RoomKind in floor == -1 ? [.ramen,.bookshop,.cafe] : [.spa,.bookshop] {
                try basement.build(kind,floor:floor,slot:slot);slot += kind.width
            }
            slot=35
            for kind:RoomKind in floor == -1 ? [.arcade,.cafe] : [.housekeeping,.cafe] {
                if slot+kind.width<=61 {try basement.build(kind,floor:floor,slot:slot);slot += kind.width}
            }
        }
        for i in basement.rooms.indices where basement.rooms[i].kind.capacity>0 {basement.rooms[i].occupancy=0.92}
        basement.minute=1100
        var chaos=try populated(5)
        if let room=chaos.rooms.first(where:{$0.kind == .office && $0.floor==2 && $0.slot==44}) {
            try chaos.triggerIncident(.fire,roomID:room.id)
            try chaos.respond(to:room.id,action:.dispatchFireDepartment)
        }
        if let room=chaos.rooms.first(where:{$0.kind == .hotel}) {try chaos.triggerIncident(.party,roomID:room.id)}
        chaos.advance(minutes:35)
        let landmark=try populated(13,grand:true)

        func render() -> NSBitmapImageRep {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1920,pixelsHigh:1080,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:1920*4,bitsPerPixel:32)!
            bitmap.size=NSSize(width:1920,height:1080)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            v.draw(v.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        func png(_ bitmap:NSBitmapImageRep,_ path:URL) throws {
            try bitmap.representation(using:.png,properties:[:])!.write(to:path)
        }
        let scenes=["01-city-in-a-tower","02-build-it-up","03-little-lives","04-elevator-rush","05-underground","06-pleasant-chaos","07-skyline-ambition"]
        for (scene,name) in scenes.enumerated() {
            if let requestedScene, requestedScene != scene+1 {continue}
            c.game = scene == 4 ? basement : scene == 5 ? chaos : scene == 6 ? landmark : base
            c.serviceCoverage=c.game.neighborhoodCoverage
            c.selectedKind=nil;c.selectedRoom=nil;c.coverageOverlay=nil
            v.spriteClock=SpriteAnimationClock();v.travelerMotion=ActorMotion();v.cloudSeconds=120
            var building = TowerState.newGame(scenerySeed:20260920)
            building.cash=8_000_000;building.earnedStars=5;building.minute=780
            let process=Process();let pipe=Pipe()
            if !stillOnly {
                process.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
                process.arguments=["-y","-hide_banner","-loglevel","error","-f","rawvideo","-pix_fmt","rgba","-s","1920x1080","-r","30","-i","pipe:0","-an","-c:v","libx264","-preset","fast","-crf","17","-pix_fmt","yuv420p",root.appendingPathComponent("source/\(name).mp4").path]
                process.standardInput=pipe;try process.run()
            }
            let frames=stillOnly ? 1 : 120
            for frame in 0..<frames {
                try autoreleasepool {
                    let t=stillOnly ? 0.55 : Double(frame)/119
                    if scene==1 {
                        let desired=1+Int(t*9)
                        while building.topFloor<desired {
                            try building.addFloor()
                            if building.topFloor == 1 {try building.addElevator(.wide,at:30,from:0,to:1)}
                            else {try building.extendElevators()}
                            for room in base.rooms where room.floor == building.topFloor && room.kind != .lobby {
                                if room.slot+room.kind.width<=61 {_ = try? building.build(room.kind,floor:room.floor,slot:room.slot)}
                            }
                            for i in building.rooms.indices where building.rooms[i].kind.capacity>0 {building.rooms[i].occupancy=0.75}
                        }
                        c.game=building
                    }
                    if frame%3==0 && scene != 1 {c.game.advance(minutes:1)}
                    v.spriteClock.advance(seconds:1.0/30,isRunning:true)
                    v.travelerMotion.advance(seconds:1.0/30,isRunning:true)
                    v.cloudSeconds += 1.0/30
                    switch scene {
                    case 0: v.scale=3.0+0.12*t;v.pan=CGPoint(x:210,y:25)
                    case 1: v.scale=2.9;v.pan=CGPoint(x:220,y:10)
                    case 2: v.scale=5.6;v.pan=CGPoint(x:130-250*t,y:-350)
                    case 3: v.scale=6.2;v.pan=CGPoint(x:210,y:-260-300*t)
                    case 4: v.scale=4.6;v.pan=CGPoint(x:210,y:300+35*t)
                    case 5: v.scale=4.8;v.pan=CGPoint(x:-630,y:35)
                    default: v.scale=2.1-0.1*t;v.pan=CGPoint(x:210,y:5)
                    }
                    let bitmap=render()
                    if frame == (stillOnly ? 0 : 65) {
                        let camera=v.pan
                        if scene != 5 {v.pan.x=0}
                        try png(render(),root.appendingPathComponent("screenshots/\(name).png"))
                        v.pan=camera
                    }
                    if !stillOnly {try pipe.fileHandleForWriting.write(contentsOf:Data(bytes:bitmap.bitmapData!,count:bitmap.bytesPerRow*bitmap.pixelsHigh))}
                }
            }
            if !stillOnly {try pipe.fileHandleForWriting.close();process.waitUntilExit();precondition(process.terminationStatus==0)}
            print("Captured \(name)");fflush(stdout)
        }
        if requestedScene != nil {return}
        // A native interface screenshot complements clean Focus-mode captures.
        c.game=base;c.setFocusMode(false);c.selectedKind=nil;c.updateUI(rebuildInspector:true)
        c.view.layoutSubtreeIfNeeded();v.fitTower()
        let bitmap=c.view.bitmapImageRepForCachingDisplay(in:c.view.bounds)!
        c.view.cacheDisplay(in:c.view.bounds,to:bitmap)
        try png(bitmap,root.appendingPathComponent("screenshots/08-building-interface.png"))
        print("Capture complete; player saves untouched.")
    }
}
