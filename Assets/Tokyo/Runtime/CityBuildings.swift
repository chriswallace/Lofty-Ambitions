import Foundation
// Foundation supplies portable CGPoint, CGSize and CGRect.

public enum CityBuildings {
    public enum Rarity: String, CaseIterable {
        case common, uncommon, rare, landmark
        public var weight: Int {
            switch self { case .common: return 60; case .uncommon: return 36; case .rare: return 12; case .landmark: return 5 }
        }
    }
    public struct Style {
        public let name: String
        public let floors: CGFloat
        public let rarity: Rarity
        init(_ name: String, _ floors: CGFloat, _ rarity: Rarity) {
            self.name = name; self.floors = floors; self.rarity = rarity
        }
    }
    public static let styles: [Style] = [
        .init("Cream apartments",8,.common), .init("Teal office",6,.common),
        .init("Brick ramen shop",4,.common), .init("Tiled office",10,.common),
        .init("Roof garden cafe",3,.common), .init("Stairwell apartments",7,.common),
        .init("Charcoal hotel",9,.common), .init("Pink apartments",6,.common),
        .init("Laundromat apartments",4,.common), .init("Aqua walk-up",5,.common),
        .init("Warehouse bike shop",3,.common), .init("Sunshade office",6,.common),
        .init("Vintage cinema",5,.uncommon), .init("Department store",6,.uncommon),
        .init("Railway station",3,.uncommon), .init("Capsule hotel",7,.uncommon),
        .init("Hospital",6,.uncommon), .init("University library",4,.uncommon),
        .init("Civic clock tower",6,.rare), .init("Art Deco office",9,.rare),
        .init("Botanical conservatory",4,.rare), .init("Garden terraces",9,.rare),
        .init("Pagoda",6,.landmark), .init("Observation tower",15,.landmark)
    ]
}
