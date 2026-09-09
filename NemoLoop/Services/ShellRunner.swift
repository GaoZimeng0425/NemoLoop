// NemoLoop/Services/ShellRunner.swift
import Foundation

/// Command execution abstraction, existing purely for testability:
/// plugins never spawn Process themselves. Nonisolated on purpose — spawning
/// a subprocess touches no UI state, so any context (test or MainActor op)
/// can hold and drive a runner.
nonisolated protocol ShellRunning: AnyObject {
    func run(executable: String, arguments: [String]) throws
}

nonisolated final class ProcessShellRunner: ShellRunning {
    func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        try process.run()
    }
}
