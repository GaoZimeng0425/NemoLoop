import Testing
import Foundation
@testable import NemoLoop

struct SlotActionMigrationTests {
    @Test func pluginCasesRoundTrip() throws {
        let actions: [SlotAction] = [.plugin("media"),
                                     .pluginOp(pluginID: "system", opID: "lockScreen"),
                                     .app(URL(filePath: "/Applications/Safari.app"))]
        let data = try JSONEncoder().encode(actions)
        let decoded = try JSONDecoder().decode([SlotAction].self, from: data)
        #expect(decoded == actions)
    }

    /// The old synthesized Codable wraps associated values as {"case":{"_0":value}} —
    /// the explicit encoder must replicate that byte for byte.
    @Test func explicitEncodingMatchesSynthesizedShape() throws {
        let encoded = String(data: try JSONEncoder().encode(SlotAction.plugin("media")), encoding: .utf8)
        #expect(encoded == #"{"plugin":{"_0":"media"}}"#)

        // Two nested keys here, and JSONEncoder's key order is unspecified
        // (it rerolls per process launch — the old synthesized encoder used
        // the same writer, so readers never depended on order). Assert the
        // decoded shape instead of raw bytes to keep this deterministic.
        let opObject = try JSONSerialization.jsonObject(with: try JSONEncoder()
            .encode(SlotAction.pluginOp(pluginID: "system", opID: "ocr"))) as? [String: [String: String]]
        #expect(opObject?["pluginOp"] == ["pluginID": "system", "opID": "ocr"])
    }

    @Test func legacySystemJSONStillDecodes() throws {
        // Task 1 keeps the .system case: synthesized-era on-disk data must
        // still decode unchanged.
        let json = #"{"system":{"_0":"lockScreen"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SlotAction.self, from: json)
        #expect(decoded == .system(.lockScreen))
    }

    @Test func legacyAppJSONStillDecodes() throws {
        // The most numerous legacy shape on disk: app slots use the same
        // nested _0 form. The synthesized encoder wrote URL.absoluteString,
        // so real payloads carry the file:// scheme (a bare path never
        // decoded to a file URL, even before the explicit Codable).
        let json = #"{"app":{"_0":"file:///Applications/Safari.app"}}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(SlotAction.self, from: json)
                == .app(URL(filePath: "/Applications/Safari.app")))
    }

    @Test func identityForPluginCases() {
        #expect(SlotAction.plugin("media").identity == "plugin:media")
        #expect(SlotAction.pluginOp(pluginID: "system", opID: "ocr").identity
                == "pluginOp:system:ocr")
    }

    @Test func childLimitDependsOnAction() {
        #expect(SlotEntry.childLimit(for: .plugin("media")) == SlotEntry.maxPluginChildren)
        #expect(SlotEntry.childLimit(for: .pluginOp(pluginID: "system", opID: "ocr"))
                == SlotEntry.maxManualChildren)
        #expect(SlotEntry.childLimit(for: .app(URL(filePath: "/A.app")))
                == SlotEntry.maxManualChildren)
        #expect(SlotEntry.childLimit(for: nil) == SlotEntry.maxManualChildren)
    }

    @Test func entryInitTruncatesToActionLimit() {
        let nineOps = (0..<9).map { SlotAction.pluginOp(pluginID: "media", opID: "op\($0)") }
        let entry = SlotEntry(action: .plugin("media"), children: nineOps)
        #expect(entry.children.count == SlotEntry.maxPluginChildren)

        let five = (0..<5).map { SlotAction.pluginOp(pluginID: "media", opID: "op\($0)") }
        let manual = SlotEntry(action: .pluginOp(pluginID: "media", opID: "play"), children: five)
        #expect(manual.children.count == SlotEntry.maxManualChildren)
    }
}
