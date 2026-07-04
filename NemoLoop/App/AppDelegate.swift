// NemoLoop/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()
    let runningAppsService = RunningAppsService()
    let ringController = RingWindowController()
    let ringViewModel = RingViewModel()
    let settingsWindowController = SettingsWindowController()
    private var hotkeyService: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let service = HotkeyService(store: sliceStore,
                                    runningApps: runningAppsService,
                                    controller: ringController,
                                    viewModel: ringViewModel)
        service.register()
        self.hotkeyService = service
    }
}
