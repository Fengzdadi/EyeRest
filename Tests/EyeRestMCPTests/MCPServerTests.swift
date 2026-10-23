import EyeRestCore
import Foundation
import Testing
@testable import EyeRestMCP

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// A server over a fresh, empty data folder, with a fixed clock.
private final class Fixture {
    let store = ActivityStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("EyeRestMCPTests-\(UUID().uuidString)"))
    var running = true
    lazy var server = MCPServer(store: store, version: "test", now: { now }, isRunning: { [unowned self] _ in running })

    deinit { try? FileManager.default.removeItem(at: store.directory) }

    /// Sends a request and returns the parsed response.
    func send(_ method: String, _ params: [String: Any] = [:], id: Int = 1) -> [String: Any] {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let line = String(decoding: try! JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let response = server.handle(line)!
        return try! JSONSerialization.jsonObject(with: Data(response.utf8)) as! [String: Any]
    }

    /// Calls a tool and returns its structured output.
    func call(_ tool: String, _ arguments: [String: Any] = [:]) -> [String: Any] {
        let result = send("tools/call", ["name": tool, "arguments": arguments])["result"] as! [String: Any]
        #expect(result["isError"] as? Bool == false)
        return result["structuredContent"] as! [String: Any]
    }

    func writeStatus(state: String, nextBreakAt: Date? = nil) throws {
        try store.writeStatus(StatusSnapshot(
            state: state, nextBreakAt: nextBreakAt, workMinutes: 20, breakSeconds: 20,
            longBreakEvery: 3, longBreakMinutes: 5, pid: 42, updatedAt: now))
    }
}

struct Protocol {
    @Test func initializeAgreesOnAVersion() {
        let fixture = Fixture()
        let known = fixture.send("initialize", ["protocolVersion": "2025-06-18"])["result"] as! [String: Any]
        #expect(known["protocolVersion"] as? String == "2025-06-18")
        #expect((known["serverInfo"] as? [String: Any])?["name"] as? String == "eyerest")

        let unknown = fixture.send("initialize", ["protocolVersion": "1999-01-01"])["result"] as! [String: Any]
        #expect(unknown["protocolVersion"] as? String == MCPServer.protocolVersions[0])
    }

    @Test func notificationsGetNoResponse() {
        let fixture = Fixture()
        #expect(fixture.server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func listsThreeReadOnlyTools() {
        let tools = (Fixture().send("tools/list")["result"] as! [String: Any])["tools"] as! [[String: Any]]
        #expect(tools.map { $0["name"] as! String } == ["get_status", "get_today", "get_history"])
        #expect(tools.allSatisfy { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true })
    }

    @Test func errorsUseJSONRPCCodes() {
        let fixture = Fixture()
        let unknownTool = fixture.send("tools/call", ["name": "pause_breaks"])["error"] as! [String: Any]
        #expect(unknownTool["code"] as? Int == -32602)
        let unknownMethod = fixture.send("resources/list")["error"] as! [String: Any]
        #expect(unknownMethod["code"] as? Int == -32601)
        let garbage = try! JSONSerialization.jsonObject(with: Data(fixture.server.handle("not json")!.utf8)) as! [String: Any]
        #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
    }
}

struct Tools {
    @Test func statusWhenTheAppIsNotRunning() throws {
        let fixture = Fixture()
        #expect(fixture.call("get_status")["running"] as? Bool == false)

        try fixture.writeStatus(state: "working", nextBreakAt: now.addingTimeInterval(750))
        fixture.running = false  // a status file left behind by a crash
        #expect(fixture.call("get_status")["running"] as? Bool == false)
    }

    @Test func statusWhileWorking() throws {
        let fixture = Fixture()
        try fixture.writeStatus(state: "working", nextBreakAt: now.addingTimeInterval(750))
        let status = fixture.call("get_status")
        #expect(status["running"] as? Bool == true)
        #expect(status["state"] as? String == "working")
        #expect(status["nextBreakInSeconds"] as? Int == 750)
        #expect(status["description"] as? String == "Working. Next break in 12m.")
    }

    @Test func todaySumsTheLog() throws {
        let fixture = Fixture()
        try fixture.store.append([
            ActivityRecord(kind: .active, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1200)),
            ActivityRecord(kind: .breakFinished, start: now.addingTimeInterval(-1190), long: true),
            ActivityRecord(kind: .breakSkipped, start: now.addingTimeInterval(-600), long: false),
        ])
        let today = fixture.call("get_today")
        #expect(today["screenSeconds"] as? Int == 2400)
        #expect(today["screenTime"] as? String == "40m")
        #expect(today["breaksFinished"] as? Int == 1)
        #expect(today["longBreaksFinished"] as? Int == 1)
        #expect(today["breaksSkipped"] as? Int == 1)
        #expect(today["trackingSince"] != nil)
    }

    @Test func todayWithNoLogOmitsTrackingSince() {
        let today = Fixture().call("get_today")
        #expect(today["screenSeconds"] as? Int == 0)
        #expect(today["trackingSince"] == nil)
    }

    @Test func historyDefaultsToAWeekAndIsCapped() {
        let fixture = Fixture()
        #expect((fixture.call("get_history")["days"] as! [Any]).count == 7)
        #expect((fixture.call("get_history", ["days": 500])["days"] as! [Any]).count == 90)
        #expect((fixture.call("get_history", ["days": 0])["days"] as! [Any]).count == 1)
    }

    @Test func durationsReadNaturally() {
        #expect(MCPServer.duration(45) == "45s")
        #expect(MCPServer.duration(750) == "12m")
        #expect(MCPServer.duration(7500) == "2h 05m")
    }
}
