// NemoLoop/App/AppDelegate.swift
import AppKit

/// Owns the long-lived stores and wires the two user surfaces — the summon
/// ring (hotkey-driven) and the menu-bar panel (status item + pop-up panel).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()
    let appearanceStore = AppearanceStore()
    let runningAppsService = RunningAppsService()
    let ringController = RingWindowController()
    let ringViewModel = RingViewModel()
    let settingsWindowController = SettingsWindowController()
    private var hotkeyService: HotkeyService?
    private var menuBarController: MenuBarPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let service = HotkeyService(store: sliceStore,
                                    runningApps: runningAppsService,
                                    controller: ringController,
                                    viewModel: ringViewModel,
                                    appearanceStore: appearanceStore)
        service.register()
        self.hotkeyService = service

        let controller = MenuBarPanelController(
            sliceStore: sliceStore,
            runningApps: runningAppsService,
            appearanceStore: appearanceStore,
            isRingVisible: { [weak service] in service?.isRingVisible ?? false },
            summonRing: { [weak service] in service?.summonLauncher() },
            releaseRing: { [weak service] in service?.releaseRing() },
            openSettings: { [weak self] in
                guard let self else { return }
                self.settingsWindowController.show(store: self.sliceStore,
                                                   appearance: self.appearanceStore)
            })
        controller.install()
        self.menuBarController = controller
    }
}
