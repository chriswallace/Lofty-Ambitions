import Foundation

public enum TenantScreening:String,Codable,CaseIterable,Sendable {
    case standard,thorough,strict
    public var title:String { rawValue.capitalized }
    public var moveInMultiplier:Double {
        switch self {case .standard:return 1;case .thorough:return 0.7;case .strict:return 0.4}
    }
    public var defaultRiskMultiplier:Double {
        switch self {case .standard:return 1;case .thorough:return 0.6;case .strict:return 0.3}
    }
}
public enum ApartmentDeposit:String,Codable,CaseIterable,Sendable {
    case none,oneMonth,twoMonths
    public var title:String {
        switch self {case .none:return "No deposit";case .oneMonth:return "1 month’s rent";case .twoMonths:return "2 months’ rent"}
    }
    public var moveInMultiplier:Double {
        switch self {case .none:return 1;case .oneMonth:return 0.85;case .twoMonths:return 0.65}
    }
    public var defaultRiskMultiplier:Double {
        switch self {case .none:return 1;case .oneMonth:return 0.8;case .twoMonths:return 0.6}
    }
}

extension Room {
    public var screeningPolicy:TenantScreening { screening ?? .standard }
    public var depositPolicy:ApartmentDeposit { depositRequirement ?? .none }
    public var applicantMoveInMultiplier:Double { screeningPolicy.moveInMultiplier * depositPolicy.moveInMultiplier }
    public var newTenantDefaultRisk:Double { screeningPolicy.defaultRiskMultiplier * depositPolicy.defaultRiskMultiplier }
    /// Existing saves represent tenants admitted under the original, standard policy.
    public var effectiveDefaultRisk:Double { tenantDefaultRisk ?? 1 }
}

extension TowerState {
    public mutating func setApartmentPolicy(_ id:Int,screening:TenantScreening,deposit:ApartmentDeposit) throws {
        guard let index=rooms.firstIndex(where:{$0.id==id}),rooms[index].kind.isApartment else {
            throw TowerError("Select an apartment to change its leasing requirements.")
        }
        rooms[index].screening=screening
        rooms[index].depositRequirement=deposit
        // Requirements apply to incoming tenants. Never rewrite existing tenant risk here.
    }

    func apartmentDefaults(_ room:Room,onDay day:Int) -> Bool {
        // Reproducible room/day draw; save/load and time chunking do not reroll a default.
        var draw=UInt64(truncatingIfNeeded:day) &* 0x9E3779B97F4A7C15 ^ UInt64(truncatingIfNeeded:room.id)
        draw=(draw ^ (draw >> 30)) &* 0xBF58476D1CE4E5B9
        draw=(draw ^ (draw >> 27)) &* 0x94D049BB133111EB
        draw ^= draw >> 31
        return Double(draw % 10000)/10000 < room.effectiveDefaultRisk
    }

    func validateApartmentPolicies() throws {
        for room in rooms {
            guard room.kind.isApartment else {
                guard room.screening == nil,room.depositRequirement == nil,room.tenantDefaultRisk == nil else {
                    throw TowerError("Leasing policies are only valid for apartments.")
                }
                continue
            }
            if let risk=room.tenantDefaultRisk {
                guard risk.isFinite,(0...1).contains(risk) else {throw TowerError("Invalid apartment tenant risk.")}
            }
        }
    }
}
