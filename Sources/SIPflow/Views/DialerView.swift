// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import SIPCore
import SwiftUI

/// Набирач у стилі «Телефона» з iPhone: поле номера, клавіатура з літерами,
/// велика зелена кнопка виклику і стирання праворуч від неї.
struct DialerView: View {
    @EnvironmentObject private var controller: PhoneController

    private let keys: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", ""),
    ]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Theme.keySize), spacing: Theme.keySpacing), count: 3)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            display
                .padding(.bottom, 6)

            LazyVGrid(columns: columns, spacing: Theme.keySpacing) {
                ForEach(keys, id: \.0) { key in
                    KeypadButton(digit: key.0, letters: key.1) { press(key.0) }
                }
            }

            actions
                .padding(.top, Theme.keySpacing)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Введений номер — поле без курсора: миготлива риска над клавіатурою
    /// набору виглядає чужорідно, але саме поле лишається повноцінним.
    private var display: some View {
        CursorlessField(
            text: $controller.dialInput,
            fontSize: controller.dialInput.count > 16 ? 20 : 30,
            onSubmit: { controller.dial() }
        )
        .frame(height: 44)
        .contextMenu {
            Button(L("Вставити")) { paste() }
            Button(L("Скопіювати")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.dialInput, forType: .string)
            }
            .disabled(controller.dialInput.isEmpty)
            Divider()
            Button(L("Очистити")) { controller.dialInput = "" }
                .disabled(controller.dialInput.isEmpty)
        }
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        controller.dialInput.append(contentsOf: text.filter { !$0.isNewline && !$0.isWhitespace })
    }

    private var actions: some View {
        HStack(spacing: 0) {
            // Порожня комірка ліворуч тримає кнопку виклику точно по центру.
            Color.clear.frame(width: Theme.keySize, height: Theme.keySize)

            Spacer(minLength: 0)

            CircleCallButton(isEnabled: controller.canDial) { call() }
                .help(callButtonHint)
                .keyboardShortcut(.return, modifiers: [])

            Spacer(minLength: 0)

            Button {
                if !controller.dialInput.isEmpty { controller.dialInput.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.keySize, height: Theme.keySize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(controller.dialInput.isEmpty ? 0 : 1)
            .disabled(controller.dialInput.isEmpty)
            .help(L("Стерти символ"))
        }
        .frame(width: Theme.keySize * 3 + Theme.keySpacing * 2)
    }

    private var hasInput: Bool {
        !controller.dialInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var callButtonHint: String {
        if !controller.canDial { return L("Акаунт не зареєстровано") }
        return hasInput ? L("Подзвонити") : L("Підставити останній набраний номер")
    }

    /// Як на телефоні: порожнє поле — кнопка підставляє останній набраний номер,
    /// заповнене — дзвонить.
    private func call() {
        if hasInput {
            controller.dial()
        } else if let last = controller.lastDialedNumber {
            controller.dialInput = last
        }
    }

    /// Під час розмови клавіатура працює як DTMF-набирач, а не як поле вводу.
    private func press(_ digit: String) {
        if let call = controller.activeCall, call.state.isTalking {
            controller.sendDTMF(digit, call: call)
        } else {
            controller.dialInput.append(digit)
        }
    }
}
