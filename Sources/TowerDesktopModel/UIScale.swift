import Foundation

/// Display policy is independent of SDL so resize and preference behavior can
/// be checked without a graphics device. Zero selects the readable default.
public struct DesktopUIScale: Codable, Equatable {
    public private(set) var requested:Double
    public static let choices:[Double]=[0,1,1.25,1.5,1.75,2]
    public init(requested:Double=0) {self.requested=Self.choices.contains(requested) ? requested:0}
    public mutating func cycle() {
        requested=Self.choices[((Self.choices.firstIndex(of:requested) ?? 0)+1)%Self.choices.count]
    }
    public func factor(width:Double,height:Double,contentScale:Double)->Double {
        guard width.isFinite,height.isFinite,width>0,height>0 else{return 1}
        let available=max(1,floor(min(width/1080,height/650)*4)/4)
        let resolution=floor(min(width/1600,height/900)*4)/4
        let display=contentScale.isFinite ? contentScale:1
        let automatic=max(1.25,min(2,max(display,resolution)))
        let desired=Self.choices.contains(requested) && requested>0 ? requested:automatic
        return min(available,desired)
    }
}
