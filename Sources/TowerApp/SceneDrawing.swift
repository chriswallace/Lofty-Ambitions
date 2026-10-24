import AppKit
import TowerCore
import TowerArt
import TowerPresentation

extension TowerView {
    func prepareScene(_ game:TowerState) {
        scene.scale=scale;scene.panX=pan.x;scene.panY = -pan.y
        scene.ambientElapsed=cloudSeconds
        scene.reducedMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scene.configure(game:game,width:bounds.width,height:bounds.height)
    }
    /// AppKit only translates portable pixel commands to native drawing calls.
    func drawSharedScene(_ game:TowerState) {
        prepareScene(game)
        scene.interpolatesMotion=false
        scene.coverage=nil // Native interactive coverage labels and reach guides are overlaid below.
        let commands=scene.render(game:game,width:bounds.width,height:bounds.height,elapsed:spriteClock.elapsed)
        drawSceneCommands(commands)
    }
    func drawSceneCommands(_ commands:[SceneCommand]) {
        guard let ctx=NSGraphicsContext.current?.cgContext else{return}
        func rect(_ r:SceneRect)->CGRect {CGRect(x:r.x,y:bounds.height-r.y-r.height,width:r.width,height:r.height)}
        func color(_ rgba:UInt32)->NSColor {NSColor(srgbRed:Double((rgba>>24)&255)/255,green:Double((rgba>>16)&255)/255,blue:Double((rgba>>8)&255)/255,alpha:Double(rgba&255)/255)}
        ctx.saveGState()
        for command in commands {
            switch command {
            case let .fill(r,c):color(c).setFill();rect(r).fill()
            case let .line(x1,y1,x2,y2,c):
                color(c).setStroke();let path=NSBezierPath();path.move(to:CGPoint(x:x1,y:bounds.height-y1));path.line(to:CGPoint(x:x2,y:bounds.height-y2));path.lineWidth=max(0.25,scale);path.stroke()
            case let .image(key,source,destination,flipped,opacity):
                let image:CGImage?
                if key.hasPrefix("cloud."),let seed=UInt64(key.dropFirst(6)) {
                    let k=NSNumber(value:seed)
                    if let cached=cloudTextures.object(forKey:k) {image=cached}
                    else {let cloud=CloudTexture.image(seed:seed);cloudTextures.setObject(cloud,forKey:k,cost:cloud.bytesPerRow*cloud.height);image=cloud}
                } else if let source {image=atlas.image(key)?.cropping(to:source.cgRect)}
                else {image=atlas.image(key)}
                guard let image else{continue}
                let r=rect(destination);ctx.saveGState();ctx.setAlpha(opacity);ctx.interpolationQuality = .none
                if flipped {ctx.translateBy(x:r.minX+r.maxX,y:0);ctx.scaleBy(x:-1,y:1)}
                ctx.draw(image,in:r);ctx.restoreGState()
            case let .text(text,x,y,size,c):
                (text as NSString).draw(at:CGPoint(x:x,y:bounds.height-y-size),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:.regular),.foregroundColor:color(c)])
            case let .clip(r):
                ctx.restoreGState();ctx.saveGState();ctx.clip(to:bounds)
                if let r {ctx.clip(to:rect(r))}
            }
        }
        ctx.restoreGState()
    }
    func elevatorFootprint(_ index:Int,_ game:TowerState)->CGRect {prepareScene(game);return scene.elevatorFootprint(index,game)}
    func elevatorCarRect(_ index:Int,_ game:TowerState)->CGRect {prepareScene(game);return scene.elevatorCarRect(index,game)}
    func elevatorLandingRect(_ index:Int,floor:Int,_ game:TowerState)->CGRect {prepareScene(game);return scene.elevatorLandingRect(index,floor:floor,game)}
    func waitingPosition(for person:Traveler,ordinal:Int,_ game:TowerState)->CGPoint? {prepareScene(game);return scene.waitingPosition(for:person,ordinal:ordinal,game)}
    func grandLobbyComposition(_ game:TowerState,in rect:CGRect)->LobbyComposition {prepareScene(game);return scene.grandLobbyComposition(game,in:rect)}
    func travelerMotionTargets(_ game:TowerState)->[ActorMotion.Target] {prepareScene(game);return scene.travelerMotionTargets(game)}
    func synchronizeTravelerMotion(_ game:TowerState) {prepareScene(game);scene.synchronizeTravelerMotion(game)}
}

private extension SceneRect {
    var cgRect:CGRect {CGRect(x:x,y:y,width:width,height:height)}
}
