import Foundation
public enum APIError: Error, LocalizedError {
    case invalidURL, response(Int, String, Double), unavailable
    public var errorDescription: String? { switch self { case .invalidURL: "Enter a valid HTTPS API address."; case let .response(code, message, _): "\(code): \(message)"; case .unavailable: "Network unavailable. Delivery is unconfirmed; check before retrying." } }
}
public protocol APIClient: Sendable {
    func nodes() async throws -> ([Node], String)
    func weather(lat: Double, lng: Double) async throws -> WeatherSnapshot
    func analyze(image: Data, lat: Double?, lng: Double?, mocked: Bool) async throws -> Analysis
    func dispatch(node: Node, blockage: Bool) async throws -> DispatchResult
    func health() async throws -> HealthReport
    func sync(node: Node) async throws
}
public struct LiveAPIClient: APIClient {
    public let baseURL: String
    public init(baseURL: String) { self.baseURL = baseURL }
    func request(_ path: String, body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path), url.scheme == "https", url.host != nil else { throw APIError.invalidURL }
        var req = URLRequest(url: url, timeoutInterval: 8)
        if let body { req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw APIError.response(http.statusCode, obj["error"] as? String ?? "Service unavailable", obj["remainingSeconds"] as? Double ?? 0)
        }
        return (data, http)
    }
    public func nodes() async throws -> ([Node], String) {
        let (data, response) = try await request("/api/nodes")
        // The backend already includes live rain, pooling and impedance for each node.
        let liveNodes = try Wire.nodes(data)
        return (liveNodes, response.value(forHTTPHeaderField: "X-Data-Source") == "dynamodb" ? "Live" : "Offline demo data")
    }
    public func weather(lat: Double, lng: Double) async throws -> WeatherSnapshot {
        do { let (data, _) = try await request("/api/weather?latitude=\(lat)&longitude=\(lng)"); let nearest = SeedNodes.all.min { pow($0.lat-lat,2) + pow($0.lng-lng,2) < pow($1.lat-lat,2) + pow($1.lng-lng,2) }; return try Wire.weather(data, nodeID:nearest?.id) }
        catch { return try await OpenMeteoClient.fetch(lat: lat, lng: lng) }
    }
    public func analyze(image: Data, lat: Double?, lng: Double?, mocked: Bool) async throws -> Analysis {
        var body: [String: Any] = ["imageBase64": image.base64EncodedString(), "image": "data:image/jpeg;base64," + image.base64EncodedString(), "mocked": mocked]
        if let lat, let lng { body["latitude"] = lat; body["longitude"] = lng }
        let (data, _) = try await request("/api/analyze", body: body); return try Wire.analysis(data)
    }
    public func dispatch(node: Node, blockage: Bool) async throws -> DispatchResult {
        let (data, _) = try await request("/api/dispatch", body: ["nodeId":node.id,"nodeName":node.name,"fri":node.fri,"drainStatus":node.drainStatus,"action":node.band.action,"blockageDetected":blockage,"screenDetected":false])
        return try JSONDecoder().decode(DispatchResult.self, from: data)
    }
    public func sync(node: Node) async throws { _ = try await request("/api/nodes", body: ["nodeId":node.id,"fri":node.fri,"v_pooling":node.v,"a_impedance":node.a,"rain_rate":node.r,"r_rate":node.r,"drainStatus":node.drainStatus]) }
    public func health() async throws -> HealthReport {
        let (data, _) = try await request("/api/health")
        let o = try Wire.object(data); let checks = o["liveChecks"] as? [String:Any] ?? [:]
        return HealthReport(region: o["region"] as? String ?? "Unknown", dynamoDB: String(describing: checks["dynamoDb"] ?? "Unavailable"), sns: String(describing: checks["sns"] ?? "Unavailable"))
    }
}
public enum Wire {
    static func number(_ obj: [String:Any], _ keys: String..., fallback: Double = 0) -> Double { for k in keys { if let n = obj[k] as? Double { return n }; if let s = obj[k] as? String, let n = Double(s) { return n } }; return fallback }
    static func object(_ data: Data) throws -> [String:Any] { guard let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw APIError.unavailable }; return obj }
    public static func nodes(_ data: Data) throws -> [Node] {
        let raw = try JSONSerialization.jsonObject(with: data); let o = raw as? [String:Any] ?? [:]
        guard let list = (raw as? [[String:Any]]) ?? (o["nodes"] as? [[String:Any]]) ?? (o["data"] as? [[String:Any]]) ?? (o["items"] as? [[String:Any]]), !list.isEmpty else { throw APIError.unavailable }
        return list.enumerated().map { index, row in
            let id = row["id"].map { String(describing: $0) } ?? (row["PK"] as? String)?.replacingOccurrences(of: "NODE#", with: "") ?? "node-\(index + 1)"
            var n = Node(id: id, name: row["name"] as? String ?? "Node \(id)", lat: number(row,"lat",fallback:28.6139), lng:number(row,"lng",fallback:77.2090), region:row["region"] as? String ?? "Delhi NCR", drainType:row["drainType"] as? String ?? "Secondary Grate")
            n.v = number(row,"base_vPooling","v_pooling"); n.a = number(row,"base_aImpedance","a_impedance"); n.r = number(row,"rain_rate","r_rate")
            n.reportedFRI = row["fri"] as? Double; n.drainStatus = row["drainStatus"] as? String ?? "Monitoring"; return n
        }
    }
    public static func analysis(_ data: Data) throws -> Analysis {
        let outer = try object(data); guard outer["success"] as? Bool != false else { throw APIError.unavailable }
        let o = outer["data"] as? [String:Any] ?? outer
        let labels = o["labels"] as? [[String:Any]] ?? []
        return Analysis(valid: o["valid"] as? Bool ?? o["roadVerified"] as? Bool ?? false, flood: o["flood_detected"] as? Bool ?? false, pooling: number(o,"pooling_score","v_pooling"), blockage: o["blockageDetected"] as? Bool ?? false, blockageConfidence:number(o,"blockageConfidence"), tags: o["tags"] as? [String] ?? labels.compactMap { $0["name"] as? String ?? $0["Name"] as? String }, simulated:false)
    }
    public static func weather(_ data: Data, nodeID: String? = nil) throws -> WeatherSnapshot {
        let outer = try object(data)
        let rows = outer["data"] as? [[String:Any]]
        let matched = rows?.first { row in row["nodeId"].map { String(describing:$0) } == nodeID }
        let o = outer["data"] as? [String:Any] ?? matched ?? rows?.first ?? outer
        guard o["tempC"] != nil else { throw APIError.unavailable }
        var w = WeatherSnapshot()
        w.tempC = number(o,"tempC"); w.humidity = number(o,"humidity"); w.windKmh = number(o,"windKmh"); w.rainMmH = number(o,"rainMmH")
        w.last1hMm = number(o,"last1hMm"); w.last3hMm = number(o,"last3hMm"); w.last6hMm = number(o,"last6hMm"); w.last24hMm = number(o,"last24hMm")
        w.peakLast3hMmH = number(o,"peakLast3hMmH"); w.peakLast6hMmH = number(o,"peakLast6hMmH"); w.precipProbMax = number(o,"precipProbMax")
        w.forecast = o["next6hPrecipMm"] as? [Double] ?? []; w.next6hPrecipMm = w.forecast.isEmpty ? number(o,"next6hPrecipMm") : w.forecast.reduce(0,+)
        w.source = o["source"] as? String ?? "Live weather"; return w
    }
}
public enum OpenMeteoClient {
    public static func fetch(lat: Double, lng: Double) async throws -> WeatherSnapshot {
        async let best = model(lat:lat,lng:lng,gfs:false)
        async let gfs = model(lat:lat,lng:lng,gfs:true)
        let (a,b) = await (best,gfs)
        if let a, let b { return .merge(a,b) }; if let a { return a }; if let b { return b }; throw APIError.unavailable
    }
    static func model(lat: Double, lng: Double, gfs: Bool) async -> WeatherSnapshot? {
        guard let url = URL(string:"https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)&past_hours=24&forecast_hours=6&current=temperature_2m,relative_humidity_2m,precipitation,rain,wind_speed_10m&hourly=precipitation,precipitation_probability&timezone=auto" + (gfs ? "&models=gfs_seamless" : "")) else { return nil }
        do {
            let (data,response) = try await URLSession.shared.data(for:URLRequest(url:url,timeoutInterval:8))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let o = try Wire.object(data); let c = o["current"] as? [String:Any] ?? [:]; let h = o["hourly"] as? [String:Any] ?? [:]
            func values(_ key: String) -> [Double] { (h[key] as? [Any] ?? []).map { $0 as? Double ?? 0 } }
            var w = WeatherSnapshot.rolling(times:h["time"] as? [String] ?? [],precipitation:values("precipitation"),probabilities:values("precipitation_probability"),currentTime:c["time"] as? String,currentRain:Wire.number(c,"rain","precipitation"))
            w.tempC = Wire.number(c,"temperature_2m",fallback:28); w.humidity = Wire.number(c,"relative_humidity_2m",fallback:60); w.windKmh = Wire.number(c,"wind_speed_10m",fallback:10); w.source = gfs ? "Open-Meteo (GFS)" : "Open-Meteo (best match)"; return w
        } catch { return nil }
    }
}
public struct MockAPIClient: APIClient {
    public init() {}
    public func nodes() async throws -> ([Node],String) { (StormSimulator.nodes(stage:.clear),"Offline demo data") }
    public func weather(lat:Double,lng:Double) async throws -> WeatherSnapshot { WeatherSnapshot() }
    public func analyze(image:Data,lat:Double?,lng:Double?,mocked:Bool) async throws -> Analysis { .demo }
    public func dispatch(node:Node,blockage:Bool) async throws -> DispatchResult { DispatchResult(success:true,messageId:"Simulated",cooldownUntil:Date().timeIntervalSince1970 + 900) }
    public func health() async throws -> HealthReport { HealthReport(region:"Demo",dynamoDB:"Offline",sns:"Offline") }
    public func sync(node:Node) async throws {}
}
