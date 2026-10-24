import Foundation
public struct WeatherSnapshot: Codable, Sendable {
    public var tempC: Double = 28
    public var humidity: Double = 60
    public var rainMmH: Double = 0
    public var windKmh: Double = 10
    public var last1hMm: Double = 0
    public var last3hMm: Double = 0
    public var last6hMm: Double = 0
    public var last24hMm: Double = 0
    public var peakLast3hMmH: Double = 0
    public var peakLast6hMmH: Double = 0
    public var next6hPrecipMm: Double = 0
    public var precipProbMax: Double = 0
    public var forecast: [Double] = []
    public var source: String = "Offline demo data"
    public var effectiveRainMmH: Double { FRICalculator.effectiveRain(current: rainMmH, peak3h: peakLast3hMmH, total24h: last24hMm) }
    public var rRate: Double { FRICalculator.rainRate(effectiveRainMmH) }
    public init() {}
    public static func rolling(times: [String], precipitation: [Double], probabilities: [Double], currentTime: String?, currentRain: Double) -> WeatherSnapshot {
        let index = times.firstIndex(of: currentTime ?? "") ?? max(0, times.count - 6)
        func slice(_ hours: Int) -> [Double] { Array(precipitation.dropFirst(max(0, index - hours + 1)).prefix(max(0, min(hours, index + 1)))).map { $0.isFinite ? $0 : 0 } }
        func round(_ n: Double) -> Double { (n * 100).rounded() / 100 }
        var w = WeatherSnapshot(); w.rainMmH = currentRain
        w.last1hMm = round(slice(1).reduce(0,+)); w.last3hMm = round(slice(3).reduce(0,+))
        w.last6hMm = round(slice(6).reduce(0,+)); w.last24hMm = round(slice(24).reduce(0,+))
        w.peakLast3hMmH = round(slice(3).max() ?? 0); w.peakLast6hMmH = round(slice(6).max() ?? 0)
        w.forecast = Array(precipitation.dropFirst(index + 1).prefix(6)).map { $0.isFinite ? $0 : 0 }
        w.next6hPrecipMm = round(w.forecast.reduce(0,+)); w.precipProbMax = probabilities.dropFirst(index + 1).prefix(6).max() ?? 0
        return w
    }
    public static func merge(_ a: WeatherSnapshot, _ b: WeatherSnapshot) -> WeatherSnapshot {
        var w = a
        for key in [\WeatherSnapshot.rainMmH, \.last1hMm, \.last3hMm, \.last6hMm, \.last24hMm, \.peakLast3hMmH, \.peakLast6hMmH, \.next6hPrecipMm, \.precipProbMax] { w[keyPath: key] = max(a[keyPath: key], b[keyPath: key]) }
        w.forecast = (0..<max(a.forecast.count,b.forecast.count)).map { max($0 < a.forecast.count ? a.forecast[$0] : 0, $0 < b.forecast.count ? b.forecast[$0] : 0) }
        w.source = "Open-Meteo (best match + GFS)"; return w
    }
}
