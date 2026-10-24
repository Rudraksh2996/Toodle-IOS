import XCTest
@testable import ToodleCore
final class CoreTests: XCTestCase {
    func testFRIAndBoundaries() {
        XCTAssertEqual(FRICalculator.score(v:0.95,a:0.92,r:1),0.9445,accuracy:0.000001)
        for (score,band) in [(0.35,RiskBand.normal),(0.36,.advisory),(0.65,.advisory),(0.66,.warning),(0.85,.warning),(0.86,.critical),(0.35001,.advisory)] { XCTAssertEqual(RiskBand(score:score),band) }
    }
    func testRainCurveAndMemory() {
        for (rain,rate) in [(0.0,0.0),(2.5,0.35),(7.5,0.65),(15,0.85),(30,1),(50,1)] { XCTAssertEqual(FRICalculator.rainRate(rain),rate,accuracy:0.000001) }
        XCTAssertEqual(FRICalculator.effectiveRain(current:0,peak3h:2,total24h:36),6)
    }
    func testRollingWindowsAndEnsemble() {
        let w = WeatherSnapshot.rolling(times:(0..<30).map(String.init),precipitation:Array(repeating:1,count:30),probabilities:Array(repeating:80,count:30),currentTime:"23",currentRain:0)
        XCTAssertEqual(w.last1hMm,1); XCTAssertEqual(w.last3hMm,3); XCTAssertEqual(w.last6hMm,6); XCTAssertEqual(w.last24hMm,24); XCTAssertEqual(w.next6hPrecipMm,6); XCTAssertEqual(w.precipProbMax,80)
        var b = WeatherSnapshot(); b.rainMmH = 12; b.last24hMm = 48; b.tempC = 5
        let merged = WeatherSnapshot.merge(w,b); XCTAssertEqual(merged.rainMmH,12); XCTAssertEqual(merged.last24hMm,48); XCTAssertEqual(merged.tempC,w.tempC)
        XCTAssertEqual(WeatherSnapshot.rolling(times:[],precipitation:[],probabilities:[],currentTime:nil,currentRain:0).last24hMm,0)
    }
    func testSimulation() {
        XCTAssertEqual(SeedNodes.all.count,12); XCTAssertEqual(Set(SeedNodes.all.map(\.id)).count,12)
        for (stage,score) in zip(StormStage.allCases,[0.0625,0.3825,0.8415,0.9445]) {
            let nodes = StormSimulator.nodes(stage:stage); XCTAssertEqual(nodes[3].fri,score,accuracy:0.000001); XCTAssertEqual(nodes[3].history.count,60)
            XCTAssertTrue(nodes.allSatisfy { (0...1).contains($0.fri) })
        }
    }
    func testWireAdapters() throws {
        let nodes = try Wire.nodes(Data(#"{"items":[{"id":4,"lat":"28.7","lng":"77.1","v_pooling":0.8,"a_impedance":0.6}]}"#.utf8))
        XCTAssertEqual(nodes[0].id,"4"); XCTAssertEqual(nodes[0].lat,28.7); XCTAssertEqual(nodes[0].v,0.8)
        let a = try Wire.analysis(Data(#"{"success":true,"roadVerified":true,"flood_detected":true,"v_pooling":0.85,"blockageDetected":false,"labels":[{"Name":"Water","Confidence":99}]}"#.utf8))
        XCTAssertTrue(a.eligible(freshGeotag:true,mocked:false)); XCTAssertFalse(a.eligible(freshGeotag:false,mocked:false)); XCTAssertFalse(a.eligible(freshGeotag:true,mocked:true)); XCTAssertEqual(a.tags,["Water"])
        XCTAssertFalse(Analysis.demo.eligible(freshGeotag:true,mocked:false))
        let w = try Wire.weather(Data(#"{"data":[{"tempC":24,"next6hPrecipMm":[1,2,3,0,0,0]}]}"#.utf8)); XCTAssertEqual(w.next6hPrecipMm,6)
    }
    func testFixtures() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"analysis",withExtension:"json")); let analysis = try Wire.analysis(Data(contentsOf:url)); XCTAssertTrue(analysis.blockage); XCTAssertEqual(analysis.pooling,0.85)
    }
    func testOfflineClient() async throws {
        let client = MockAPIClient(); let (nodes,source) = try await client.nodes(); XCTAssertEqual(nodes.count,12); XCTAssertEqual(source,"Offline demo data")
        let response = try await client.dispatch(node:nodes[0],blockage:false); XCTAssertEqual(response.messageId,"Simulated")
    }
}
