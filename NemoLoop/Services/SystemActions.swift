// NemoLoop/Services/SystemActions.swift
import AppKit

extension SystemAction {
    /// Fires the system action. Everything here stays permission-free: the lock
    /// goes through SACLockScreenImmediate (dlsym'd — it moved between frameworks
    /// across macOS releases), the sleep paths through `pmset`, Mission Control
    /// through a synthetic control-up keystroke.
    func perform() {
        switch self {
        case .lockScreen: Self.lockScreenImmediate()
        case .sleepDisplays: Self.runTool("/usr/bin/pmset", ["displaysleepnow"])
        case .sleep: Self.runTool("/usr/bin/pmset", ["sleepnow"])
        case .missionControl: Self.postControlUpArrow()
        case .ocr: OcrSessionController.shared.handleOcrRequested()
        }
    }

    private static func lockScreenImmediate() {
        let frameNames = [
            "/System/Library/PrivateFrameworks/ScreenSaver.framework/ScreenSaver",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        ]
        for path in frameNames {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") {
                typealias LockFn = @convention(c) () -> Void
                unsafeBitCast(symbol, to: LockFn.self)()
                return
            }
        }
        NSLog("NemoLoop: SACLockScreenImmediate unavailable — lock screen action dropped")
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        try? process.run()
    }

    private static func postControlUpArrow() {
        // kVK_UpArrow (126) with control = the Mission Control shortcut; works
        // without fn regardless of the "use F1…" keyboard setting.
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 126, keyDown: keyDown)
            event?.flags = .maskControl
            event?.post(tap: .cghidEventTap)
        }
    }
}
