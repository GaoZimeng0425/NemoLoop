// NemoLoopTests/SystemPluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct SystemPluginTests {
    @Test func exposesFiveSystemOpsWithStableIDs() {
        let plugin = SystemPlugin()
        #expect(plugin.id == "system")
        #expect(plugin.status == .ready)
        #expect(plugin.operations.map(\.id)
                == ["lockScreen", "sleepDisplays", "sleep", "missionControl", "ocr"])
        #expect(plugin.operations.map(\.displayName)
                == ["Lock Screen", "Sleep Displays", "Sleep", "Mission Control", "OCR"])
    }

    @Test func sharedRegistryShipsSystemRegistered() {
        #expect(PluginRegistry.shared.plugin(id: "system") != nil)
    }
}
