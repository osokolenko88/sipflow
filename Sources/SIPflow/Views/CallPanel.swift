// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SIPCore
import SwiftUI

/// Власне спливаюче вікно вхідного дзвінка.
///
/// Системний банер сюди не годиться як основний канал: macOS може прийняти
/// сповіщення без помилки й не вивести його на екран — через режим фокусування,
/// налаштування стилю або відкликаний дозвіл. Для дзвінка така мовчазна відмова
/// неприпустима, тому показуємо власну панель: вона не залежить ні від дозволів,
/// ні від «Не турбувати», і не забирає фокус у програми, з якою працює оператор.
/// Вікно без рамки за замовчуванням не може стати ключовим, і елементи керування
/// в ньому можуть не реагувати. Дозволяємо це явно — стиль `.nonactivatingPanel`
/// усе одно не дає застосунку забрати фокус.
private final class FloatingCallPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CallPanelController {
    var onAnswer: ((Int32) -> Void)?
    var onDecline: ((Int32) -> Void)?

    private var panel: NSPanel?
    private var shownCallID: Int32?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(call: SIPCallSnapshot, name: String, account: String?) {
        let content = CallPanelView(
            name: name,
            number: call.remoteNumber,
            account: account,
            onAnswer: { [weak self] in self?.onAnswer?(call.id) },
            onDecline: { [weak self] in self?.onDecline?(call.id) }
        )

        if let panel, shownCallID == call.id {
            (panel.contentView as? NSHostingView<CallPanelView>)?.rootView = content
            return
        }

        hide()
        let hosting = NSHostingView(rootView: content)
        let size = NSSize(width: 320, height: 116)

        // Без рамки й заголовка: панель має виглядати як сповіщення, а не як вікно.
        let panel = FloatingCallPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        panel.setContentSize(size)

        position(panel, size: size)
        // orderFrontRegardless показує вікно, не роблячи застосунок активним.
        panel.orderFrontRegardless()

        self.panel = panel
        shownCallID = call.id
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        shownCallID = nil
    }

    /// Правий верхній кут головного екрана, під рядком меню — там, де користувач
    /// звик бачити системні сповіщення.
    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - size.width - 16,
            y: frame.maxY - size.height - 16
        )
        panel.setFrameOrigin(origin)
    }
}

struct CallPanelView: View {
    let name: String
    let number: String
    let account: String?
    let onAnswer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                StatusDot(color: .green, pulsing: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: onAnswer) {
                    Label(L("Відповісти"), systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: onDecline) {
                    Label(L("Відхилити"), systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(14)
        .frame(width: 320, height: 116)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var subtitle: String {
        let parts = [number == name ? "" : number, account].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? L("Вхідний дзвінок") : parts.joined(separator: " · ")
    }
}
