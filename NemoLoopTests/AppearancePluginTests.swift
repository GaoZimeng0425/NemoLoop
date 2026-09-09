// NemoLoopTests/AppearancePluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct AppearancePluginTests {
    private final class RecordingRunner: ShellRunning {
        var calls: [(String, [String])] = []
        func run(executable: String, arguments: [String]) throws {
            calls.append((executable, arguments))
        }
    }

    @Test func opFiresOsascriptToggle() throws {
        let runner = RecordingRunner()
        let plugin = AppearancePlugin(runner: runner)
        #expect(plugin.id == "appearance")
        #expect(plugin.status == .ready)

        let op = plugin.operations.first!
        #expect(op.id == "toggleDarkMode")
        #expect(op.displayName == "Toggle Appearance")

        op.perform()
        #expect(runner.calls.count == 1)
        let (exe, args) = runner.calls[0]
        #expect(exe == "/usr/bin/osascript")
        #expect(args.count == 2)
        #expect(args[0] == "-e")
        #expect(args[1].contains("set dark mode to not dark mode"))
    }

    @Test func performFailureDoesNotCrash() throws {
        final class ExplodingRunner: ShellRunning {
            func run(executable: String, arguments: [String]) throws { throw URLError(.badURL) }
        }
        let plugin = AppearancePlugin(runner: ExplodingRunner())
        plugin.operations.first!.perform()   // error swallowed inside the op and NSLogged
    }
}
