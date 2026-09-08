// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import SIPCore

/// «Останні» — журнал у стилі iPhone: два фільтри, пропущені червоним,
/// час праворуч і кнопка подробиць.
struct HistoryView: View {
    @EnvironmentObject private var controller: PhoneController
    @State private var showMissedOnly = false
    @State private var newContact: Contact?
    @State private var details: CallRecord?

    private var records: [CallRecord] {
        controller.history.records(for: showMissedOnly ? .missed : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showMissedOnly) {
                Text(L("Усі")).tag(false)
                Text(L("Пропущені")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if records.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(showMissedOnly ? L("Пропущених немає") : L("Журнал порожній"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(records) { record in
                        HistoryRow(
                            record: record,
                            title: controller.title(for: record),
                            onDetails: { details = record }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { controller.redial(record) }
                        .contextMenu {
                            Button(L("Подзвонити")) { controller.redial(record) }
                            if !controller.isKnown(record.number), !record.number.isEmpty {
                                Button(L("Додати в контакти")) { newContact = controller.addContact(fromRecord: record) }
                            }
                            Button(L("Скопіювати номер")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.number, forType: .string)
                            }
                            Divider()
                            Button(L("Видалити"), role: .destructive) { controller.delete(record) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text(L("%lld записів", records.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Очистити")) { controller.clearHistory() }
                    .buttonStyle(.link)
                    .disabled(controller.history.records.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .sheet(item: $newContact) { contact in
            ContactEditor(contact: contact) { controller.contacts.add($0) }
        }
        .popover(item: $details, arrowEdge: .leading) { record in
            CallDetailsView(record: record, title: controller.title(for: record))
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var controller: PhoneController
    let record: CallRecord
    let title: String
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.direction.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(record.direction == .missed ? Color.red : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: isNew ? .semibold : .regular))
                        .foregroundStyle(record.direction == .missed ? Color.red : Color.primary)
                        .lineLimit(1)
                    if isNew {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onDetails) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.accentColor)
            .help(L("Подробиці дзвінка"))
        }
        .padding(.vertical, 3)
    }

    private var isNew: Bool { record.direction == .missed && !record.isSeen }

    private var subtitle: String {
        let day = record.startedAt.formatted(date: .abbreviated, time: .omitted)
        switch record.direction {
        case .incoming: return "Вхідний · \(day)"
        case .outgoing: return "Вихідний · \(day)"
        case .missed: return "Пропущений · \(day)"
        }
    }
}

/// Подробиці дзвінка — те, що на iPhone відкривається кнопкою «i».
private struct CallDetailsView: View {
    @EnvironmentObject private var controller: PhoneController
    let record: CallRecord
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if title != record.number, !record.number.isEmpty {
                Text(record.number)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            row(L("Тип"), record.direction.title)
            row(L("Час"), record.startedAt.formatted(date: .abbreviated, time: .standard))
            row(L("Тривалість"), record.wasAnswered ? record.duration.callDurationText : "—")
            if !record.statusText.isEmpty { row(L("Стан"), record.statusText) }

            Divider()

            HStack {
                Button(L("Подзвонити")) { controller.redial(record) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button(L("Видалити"), role: .destructive) { controller.delete(record) }
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .multilineTextAlignment(.trailing)
        }
    }
}
