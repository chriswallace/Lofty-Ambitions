import Foundation

/// Blend the same registered skyline between four lighting states.
public enum CityLighting {
    public struct Layer: Equatable {
        public let key: String
        public let opacity: Double
    }

    public static func layers(at minute: Int) -> [Layer] {
        let time = ((minute % 1440) + 1440) % 1440
        let stops: [(Int, String)] = [(0,"night"),(300,"night"),(360,"sunrise"),(480,"day"),
                                      (960,"day"),(1080,"sunset"),(1200,"night"),(1440,"night")]
        for i in 0..<(stops.count-1) where time >= stops[i].0 && time < stops[i+1].0 {
            let (start, first) = stops[i], (end, second) = stops[i+1]
            let base = Layer(key:"city."+first,opacity:1)
            guard first != second, time > start else {return [base]}
            let fraction = Double(time-start)/Double(end-start)
            return [base,Layer(key:"city."+second,opacity:fraction)]
        }
        return [Layer(key:"city.night",opacity:1)]
    }
}
