// NemoLoopTests/ActionResolverTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ActionResolverTests {
    @Test func namesResolveThroughRegistryWithFallback() {
        // The shared registry ships the System plugin; names must resolve even
        // while disabled — the dim rule says disabled plugins stay browsable.
        #expect(ActionResolver.name(for: .pluginOp(pluginID: "system", opID: "lockScreen"))
                == "Lock Screen")
        #expect(ActionResolver.name(for: .plugin("system")) == "System")
        #expect(ActionResolver.name(for: .pluginOp(pluginID: "ghost", opID: "x")) == "ghost/x")
        #expect(ActionResolver.symbolName(for: .pluginOp(pluginID: "system", opID: "ocr"))
                == "doc.text.viewfinder")
        #expect(ActionResolver.symbolName(for: .app(URL(filePath: "/A.app"))) == nil)
    }
}
