// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import SIPCore

@main
struct SIPflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = PhoneController()

    var body: some Scene {
        Window("SIPflow", id: "main") {
            MainView()
                .environmentObject(controller)
                .onAppear {
                    appDelegate.controller = controller
                    controller.start()
                }
        }
        .defaultSize(width: Theme.windowWidth, height: Theme.windowHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("Дзвінок")) {
                Button(L("Відповісти")) {
                    if let call = controller.incomingCall { controller.answer(call) }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(controller.incomingCall == nil)

                Button(L("Відхилити")) {
                    if let call = controller.incomingCall { controller.decline(call) }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(controller.incomingCall == nil)

                Divider()

                Button(L("Подзвонити")) { controller.dial() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button(L("Завершити дзвінок")) {
                    if let call = controller.activeCall ?? controller.calls.first { controller.hangUp(call) }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!controller.hasCalls)

                Button(L("Завершити всі")) { controller.hangUpAll() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!controller.hasCalls)
                Divider()
                Button(L("Перереєструватися")) { controller.reregister() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(controller)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: PhoneController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Застосунок живе далі без вікон, тому клац по значку в Dock має його повертати.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        MainActor.assumeIsolated { controller?.raiseWindow() }
        return true
    }

    /// Коректно кладемо трубку й знімаємо реєстрацію до виходу.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { controller?.shutdown() }
    }
}
