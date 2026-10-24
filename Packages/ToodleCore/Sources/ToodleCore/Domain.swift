import Foundation

public enum RiskBand: String, Codable, CaseIterable, Sendable {
    case normal = "NORMAL", advisory = "ADVISORY", warning = "WARNING", critical = "CRITICAL"
    public init(score: Double) { self = score <= 0.35 ? .normal : score <= 0.65 ? .advisory : score <= 0.85 ? .warning : .critical }
    public var hex: UInt32 { switch self { case .normal: 0x22c55e; case .advisory: 0xf59e0b; case .warning: 0xf97316; case .critical: 0xef4444 } }
    public var action: String { switch self {
    case .normal: "Monitor routine telemetry."
    case .advisory: "Increase polling frequency. Dispatch municipal inspection if sustained."
    case .warning: "Prepare maintenance crews. Alert local traffic authorities."
    case .critical: "Dispatch Hydro-Jet Truck to Clear Ingress Grate."
    } }
}
public enum FRICalculator {
    public static func score(v: Double, a: Double, r: Double) -> Double { 0.55 * v + 0.35 * a + 0.10 * r }
    public static func rainRate(_ mm: Double) -> Double {
        if mm <= 0 { return 0 }; if mm <= 2.5 { return mm / 2.5 * 0.35 }
        if mm <= 7.5 { return 0.35 + (mm - 2.5) / 5 * 0.3 }
        if mm <= 15 { return 0.65 + (mm - 7.5) / 7.5 * 0.2 }
        if mm <= 30 { return 0.85 + (mm - 15) / 15 * 0.15 }; return 1
    }
    public static func effectiveRain(current: Double, peak3h: Double, total24h: Double) -> Double { (max(current, peak3h, total24h / 6) * 100).rounded() / 100 }
}
public struct Node: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var lat: Double
    public var lng: Double
    public var region: String
    public var drainType: String
    public var v: Double = 0.25
    public var a: Double = 0.30
    public var r: Double = 0
    public var reportedFRI: Double? = nil
    public var drainStatus: String = "Monitoring"
    public var history: [Double] = []
    public var fri: Double { reportedFRI ?? FRICalculator.score(v: v, a: a, r: r) }
    public var band: RiskBand { RiskBand(score: fri) }
    public init(id: String, name: String, lat: Double, lng: Double, region: String, drainType: String) {
        self.id = id; self.name = name; self.lat = lat; self.lng = lng; self.region = region; self.drainType = drainType
        if id == "4" { v = 0.7; a = 0.65 }
    }
}
public enum StormStage: String, CaseIterable, Sendable {
    case clear = "Clear", rain = "Moderate", choke = "Drain Choke", storm = "Storm"
    public var minute: Int { switch self { case .clear: 0; case .rain: 15; case .choke: 40; case .storm: 60 } }
}
public enum StormSimulator {
    public static func nodes(stage: StormStage) -> [Node] {
        SeedNodes.all.enumerated().map { i, seed in
            var n = seed
            let x = Double((i * 37 + 19) % 100) / 100
            let y = Double((i * 53 + 31) % 100) / 100
            let target = n.id == "4"
            var base = 0.1; var volatility = 0.05
            switch stage {
            case .clear: n.v = target ? 0.05 : x * 0.1; n.a = target ? 0.1 : y * 0.15; n.r = 0; n.drainStatus = "Unobstructed Flow (2.5–8 kHz)"
            case .rain: n.v = target ? 0.35 : x * 0.4; n.a = target ? 0.4 : y * 0.3; n.r = 0.5; base = 0.4; volatility = 0.1; n.drainStatus = "Partial Siltation (1.2–3 kHz)"
            case .choke: n.v = target ? 0.88 : x * 0.6; n.a = target ? 0.85 : y * 0.5; n.r = 0.6; base = target ? 0.85 : 0.6; volatility = 0.15; n.drainStatus = target ? "Severe Choke (850Hz Gurgle)" : "Elevated Impedance"
            case .storm: n.v = target ? 0.95 : x * 0.8 + 0.2; n.a = target ? 0.92 : y * 0.7 + 0.3; n.r = 1; base = target ? 0.95 : 0.8; volatility = 0.1; n.drainStatus = target ? "Total Submersion Failure (Silent)" : "Critical Impedance"
            }
            n.history = (0..<60).map { max(0, min(1, base + (Double(($0 * 17 + i * 7) % 100) / 100 - 0.5) * volatility)) }
            return n
        }
    }
}
public struct Analysis: Codable, Sendable {
    public var valid: Bool
    public var flood: Bool
    public var pooling: Double
    public var blockage: Bool
    public var blockageConfidence: Double
    public var tags: [String]
    public var simulated: Bool
    public func eligible(freshGeotag: Bool, mocked: Bool) -> Bool { valid && ((flood && pooling >= 0.7) || blockage) && freshGeotag && !mocked && !simulated }
    public static let demo = Analysis(valid: true, flood: true, pooling: 0.85, blockage: true, blockageConfidence: 92, tags: ["Water", "Drain", "Demo"], simulated: true)
}
public struct DispatchResult: Codable, Sendable { public var success: Bool; public var messageId: String?; public var cooldownUntil: Double? }
public struct HealthReport: Codable, Sendable { public var region: String; public var dynamoDB: String; public var sns: String }
