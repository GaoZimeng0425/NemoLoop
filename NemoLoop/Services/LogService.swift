// NemoLoop/Services/LogService.swift
import CocoaLumberjackSwift

/// File + OS logging (CocoaLumberjack), ported from NemoNotch's LogService.
/// NSLog is invisible here: the app's output never reaches the unified log
/// and `open` discards stderr, so the only reliable trail is this file log
/// at ~/.NemoLoop/logs (daily rollover, 7 files kept, LOCAL timezone — the
/// library default formatter pins UTC and reads 8h off from Console).
final class LogService {
    nonisolated(unsafe) static let shared = LogService()
    private let fileLogger: DDFileLogger

    private init() {
        let logDir = NSHomeDirectory() + "/.NemoLoop/logs"

        let fm = FileManager.default
        if !fm.fileExists(atPath: logDir) {
            try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        DDLog.add(DDOSLogger.sharedInstance)

        let logFileManager = DDLogFileManagerDefault(logsDirectory: logDir)
        logFileManager.maximumNumberOfLogFiles = 7
        fileLogger = DDFileLogger(logFileManager: logFileManager)
        fileLogger.rollingFrequency = 60 * 60 * 24
        let localTimestamp = DateFormatter()
        localTimestamp.dateFormat = "yyyy/MM/dd HH:mm:ss:SSS"
        localTimestamp.timeZone = .current
        fileLogger.logFormatter = DDLogFileFormatterDefault(dateFormatter: localTimestamp)
        DDLog.add(fileLogger)

        #if DEBUG
            dynamicLogLevel = .all
        #else
            dynamicLogLevel = .info
        #endif
    }
}

extension LogService {
    nonisolated static func debug(_ message: String, category: String = "App") {
        DDLogDebug("[\(category)] \(message)")
    }

    nonisolated static func info(_ message: String, category: String = "App") {
        DDLogInfo("[\(category)] \(message)")
    }

    nonisolated static func warn(_ message: String, category: String = "App") {
        DDLogWarn("[\(category)] \(message)")
    }

    nonisolated static func error(_ message: String, category: String = "App") {
        DDLogError("[\(category)] \(message)")
    }
}
