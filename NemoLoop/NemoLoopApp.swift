// NemoLoop/NemoLoopApp.swift
import SwiftUI

/// SwiftUI lifecycle entry — kept because `@NSApplicationDelegateAdaptor` is the
/// one wiring that reliably calls `applicationDidFinishLaunching` in this nib-less
/// app (a bare `@main` on the delegate or a hand-rolled `app.run()` both broke:
/// no delegate callback / status item parked off-screen). The body is the laziest
/// legal scene: `Settings` opens nothing at launch; everything user-facing lives
/// in the AppDelegate-owned menu-bar panel.
@main
struct NemoLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
