import Foundation
#if canImport(AppKit)
import AppKit
#endif
import TowerCore

public enum RoomArtState: String, CaseIterable {
    case vacant, open, closed, damaged, destroyed, rebuilding

    public static func state(for room: Room, minute: Int) -> Self {
        if let incident = room.incident, incident.isActive {
            if incident.kind == .fire {
                if incident.stage == .repairing { return .rebuilding }
                if incident.severity >= 0.95 { return .destroyed }
                return .damaged
            }
            if incident.stage == .awaitingCleaning { return .damaged }
            if incident.stage == .cleaning { return .rebuilding }
        }
        if room.kind.capacity > 0 && room.occupancy == 0 { return .vacant }
        switch room.kind {
        case .office, .coworking: return (480..<1140).contains(minute) ? .open : .closed
        case .shop, .bookshop: return (480..<1320).contains(minute) ? .open : .closed
        case .restaurant: return (660..<1380).contains(minute) ? .open : .closed
        case .ramen: return (660..<1440).contains(minute) ? .open : .closed
        case .spa: return (540..<1380).contains(minute) ? .open : .closed
        case .cafe: return (360..<1200).contains(minute) ? .open : .closed
        case .arcade: return (600..<1440).contains(minute) ? .open : .closed
        case .fitness: return (300..<1380).contains(minute) ? .open : .closed
        case .observatory: return (540..<1380).contains(minute) ? .open : .closed
        case .garden: return (360..<1320).contains(minute) ? .open : .closed
        default: return .open
        }
    }
}

/// Source rectangles use integer pixels, independently of the simulation grid.
public final class TowerAtlas {
    public struct Frame: Decodable {
        public let sheet: String
        public let rect: [Int]
        public let referenceHeight: Int
        /// Body axis and sole baseline, in source pixels from the lower-left.
        public let footAnchor: [CGFloat]?
    }
    struct Manifest: Decodable { let frames: [String: Frame] }
    public let frames: [String: Frame]
    #if canImport(AppKit)
    private var images: [String: CGImage] = [:]
    #endif
    public let resourceURL: URL

    public init(root: URL? = nil) throws {
        resourceURL = root ?? TowerResources.url
        frames = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: resourceURL.appendingPathComponent("atlas.json"))).frames
        #if canImport(AppKit)
        var sheets: [String: CGImage] = [:]
        for (key, frame) in frames {
            let url = resourceURL.appendingPathComponent("Sheets").appendingPathComponent(frame.sheet)
            if sheets[frame.sheet] == nil {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw NSError(domain: "TowerAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing artwork: \(url.path)"])
                }
                sheets[frame.sheet] = image
            }
            let sheet = sheets[frame.sheet]!
            guard frame.rect.count == 4, frame.rect[0] >= 0, frame.rect[1] >= 0, frame.rect[2] > 0, frame.rect[3] > 0,
                  frame.rect[0] + frame.rect[2] <= sheet.width, frame.rect[1] + frame.rect[3] <= sheet.height,
                  frame.referenceHeight > 0 else {
                throw NSError(domain: "TowerAtlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid artwork bounds: \(key)"])
            }
            if let anchor = frame.footAnchor, anchor.count != 2 || anchor.contains(where: { !$0.isFinite }) {
                throw NSError(domain: "TowerAtlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid actor anchor: \(key)"])
            }
            let r = CGRect(x: frame.rect[0], y: frame.rect[1], width: frame.rect[2], height: frame.rect[3])
            images[key] = sheet.cropping(to: r)
        }
        #else
        var sizes: [String: (Int, Int)] = [:]
        for (key, frame) in frames {
            if sizes[frame.sheet] == nil {
                let bytes = [UInt8](try Data(contentsOf: resourceURL.appendingPathComponent("Sheets").appendingPathComponent(frame.sheet)))
                guard bytes.count >= 24, Array(bytes.prefix(8)) == [137,80,78,71,13,10,26,10] else {
                    throw NSError(domain: "TowerAtlas", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid PNG: \(frame.sheet)"])
                }
                func integer(_ offset: Int) -> Int { bytes[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) } }
                sizes[frame.sheet] = (integer(16), integer(20))
            }
            let size = sizes[frame.sheet]!
            guard frame.rect.count == 4, frame.rect[0] >= 0, frame.rect[1] >= 0, frame.rect[2] > 0, frame.rect[3] > 0,
                  frame.rect[0]+frame.rect[2] <= size.0, frame.rect[1]+frame.rect[3] <= size.1, frame.referenceHeight > 0,
                  frame.footAnchor.map({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) ?? true else {
                throw NSError(domain: "TowerAtlas", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid artwork bounds: \(key)"])
            }
        }
        #endif
    }

    #if canImport(AppKit)
    public func image(_ key: String) -> CGImage? { images[key] }

    public func draw(_ key: String, in rect: CGRect, flipped: Bool = false) {
        guard let image = images[key], let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        if flipped { ctx.translateBy(x: rect.minX + rect.maxX, y: 0); ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    /// Keep feet on the floor and retain one scale across all poses in an action row.
    public func actor(_ key: String, feet: CGPoint, height: CGFloat = 11, flipped: Bool = false) {
        guard let rect = actorRect(key, feet: feet, height: height, flipped: flipped) else { return }
        draw(key, in: rect, flipped: flipped)
    }

    #endif

    /// Registration keeps changing crop widths and transparent padding out of locomotion.
    public func actorRect(_ key: String, feet: CGPoint, height: CGFloat = 11, flipped: Bool = false) -> CGRect? {
        guard let frame = frames[key] else { return nil }
        let factor = height / CGFloat(frame.referenceHeight)
        let size = CGSize(width: CGFloat(frame.rect[2]) * factor, height: CGFloat(frame.rect[3]) * factor)
        let anchor = frame.footAnchor ?? [CGFloat(frame.rect[2]) / 2, 0]
        let x = (flipped ? CGFloat(frame.rect[2]) - anchor[0] : anchor[0]) * factor
        return CGRect(x: feet.x - x, y: feet.y - anchor[1] * factor, width: size.width, height: size.height)
    }

    /// Map furniture anchors through the same three-slice stretch used to draw the room.
    public func roomPoint(_ point: CGPoint, name: String, in rect: CGRect) -> CGPoint {
        guard let frame = frames["room.\(name).open"] else { return CGPoint(x:rect.minX+point.x*rect.width,y:rect.minY+point.y*rect.height) }
        let w = CGFloat(frame.rect[2]), h = CGFloat(frame.rect[3]), factor = rect.height / h
        let left = min(w*0.12,h*0.2), right = min(w*0.22,h*0.9)
        let dl = left*factor, dr = right*factor, x = point.x*w
        let mapped: CGFloat
        if rect.width <= dl+dr { mapped = point.x*rect.width }
        else if x < left { mapped = x*factor }
        else if x > w-right { mapped = rect.width-(w-x)*factor }
        else { mapped = dl+(x-left)/(w-left-right)*(rect.width-dl-dr) }
        return CGPoint(x:rect.minX+mapped,y:rect.minY+point.y*rect.height)
    }

    public struct RoomSlice {
        /// Pixel coordinates relative to the atlas frame, from its top-left.
        public let source: CGRect
        public let destination: CGRect
    }

    /// One shared three-slice layout for native catalog previews and both world renderers.
    public func roomSlices(_ key:String, in rect:CGRect)->[RoomSlice] {
        guard let frame=frames[key] else{return []}
        let w=CGFloat(frame.rect[2]),h=CGFloat(frame.rect[3]),factor=rect.height/h
        let left=min(w*0.12,h*0.2),right=min(w*0.22,h*0.9),dl=left*factor,dr=right*factor
        guard rect.width>dl+dr else{return [RoomSlice(source:CGRect(x:0,y:0,width:w,height:h),destination:rect)]}
        return [(0,left,rect.minX,dl),(left,w-left-right,rect.minX+dl,rect.width-dl-dr),(w-right,right,rect.maxX-dr,dr)].map {sx,sw,dx,dw in
            RoomSlice(source:CGRect(x:sx.rounded(),y:0,width:sw.rounded(),height:h),destination:CGRect(x:dx,y:rect.minY,width:dw,height:rect.height))
        }
    }

    #if canImport(AppKit)
    /// Side caps retain their natural aspect ratio, including the back-wall door.
    public func room(_ name:String,state:RoomArtState,in rect:CGRect) {
        let key="room.\(name).\(state.rawValue)"
        guard let image=images[key],let ctx=NSGraphicsContext.current?.cgContext else{return}
        ctx.saveGState();ctx.interpolationQuality = .none;ctx.clip(to:rect)
        for slice in roomSlices(key,in:rect) {
            guard let part=image.cropping(to:slice.source) else{continue}
            ctx.draw(part,in:slice.destination)
        }
        ctx.restoreGState()
    }

    #endif
}

/// Artwork is resolved from the packaged resources, independently of the process directory.
public enum TowerResources {
    public static var url: URL { Bundle.module.resourceURL! }
}
