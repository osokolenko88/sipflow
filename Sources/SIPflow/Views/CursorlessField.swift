// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Поле введення номера без курсора.
///
/// Це справжнє `NSTextField`, а не текст із власним обробником клавіш: так
/// зберігається все, що очікується від поля — введення з клавіатури, вставка,
/// скасування, виділення. Прибрано лише миготливий курсор, який над клавіатурою
/// набору виглядає чужорідно.
struct CursorlessField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = HiddenCaretTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingHead
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            // Присвоєння тексту змушує поле виділити його повністю — саме тому
            // після натискання клавіші набраний номер підсвічувався. Ставимо
            // курсор у кінець, і виділення зникає.
            field.moveCaretToEnd()
        }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        if field.font != font { field.font = font }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CursorlessField

        init(_ parent: CursorlessField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submit() { parent.onSubmit() }
    }
}

/// Курсор малює редактор поля, тому робимо його прозорим щоразу,
/// коли поле стає активним.
private final class HiddenCaretTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .clear
        }
        // Поле, що стає активним, теж виділяє весь текст.
        moveCaretToEnd()
        return accepted
    }
}

extension NSTextField {
    /// Знімає виділення й ставить курсор після останнього символу.
    func moveCaretToEnd() {
        guard let editor = currentEditor() else { return }
        editor.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
    }
}
