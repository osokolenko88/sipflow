// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import SIPCore


/// Назва акаунта поруч із дзвінком має сенс лише коли акаунтів кілька.
private struct CallAccountBadge: View {
    @EnvironmentObject private var controller: PhoneController
    let call: SIPCallSnapshot

    var body: some View {
        if controller.settings.accounts.count > 1,
           let account = controller.settings.account(with: call.accountID) {
            Text(account.title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .lineLimit(1)
        }
    }
}

/// Картка вхідного дзвінка з відповіддю та відхиленням.
struct IncomingCallCard: View {
    @EnvironmentObject private var controller: PhoneController
    let call: SIPCallSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(color: .green, pulsing: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.title(for: call))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(call.remoteNumber.isEmpty ? L("Вхідний дзвінок") : call.remoteNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                CallAccountBadge(call: call)
            }

            HStack(spacing: 8) {
                Button {
                    controller.answer(call)
                } label: {
                    Label(L("Відповісти"), systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    controller.decline(call)
                } label: {
                    Label(L("Відхилити"), systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
    }
}

/// Активний або вихідний дзвінок: стан, таймер і керування.
struct ActiveCallCard: View {
    @EnvironmentObject private var controller: PhoneController
    let call: SIPCallSnapshot

    @State private var showTransfer = false
    @State private var transferTarget = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(color: statusColor, pulsing: !call.state.isTalking)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.title(for: call))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                CallAccountBadge(call: call)
            }

            HStack(spacing: 12) {
                CallActionButton(
                    symbol: call.isMuted ? "mic.slash.fill" : "mic.fill",
                    title: L("Мікрофон"),
                    tint: call.isMuted ? .orange : .primary,
                    isActive: call.isMuted,
                    isEnabled: call.state.isTalking
                ) { controller.toggleMute(call) }

                CallActionButton(
                    symbol: "pause.fill",
                    title: L("Утримання"),
                    tint: .blue,
                    isActive: call.isOnHold,
                    isEnabled: call.state.isTalking
                ) { controller.toggleHold(call) }

                CallActionButton(
                    symbol: "arrowshape.turn.up.right.fill",
                    title: L("Перевести"),
                    tint: .blue,
                    isEnabled: call.state.isTalking
                ) { showTransfer = true }
                .popover(isPresented: $showTransfer, arrowEdge: .bottom) {
                    transferForm
                }

                Spacer(minLength: 0)

                CallActionButton(symbol: "phone.down.fill", title: L("Завершити"), tint: .red, isActive: true) {
                    controller.hangUp(call)
                }
            }
        }
        .padding(12)
        .cardBackground()
    }

    private var transferForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Перевести дзвінок"))
                .font(.headline)
            TextField(L("Номер або SIP-адреса"), text: $transferTarget)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(performTransfer)

            if controller.calls.count > 1 {
                Divider()
                Text(L("Або з'єднати з дзвінком:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(controller.calls.filter { $0.id != call.id && $0.state.isTalking }) { other in
                    Button(other.title) {
                        controller.transfer(call, to: other.remoteURI)
                        showTransfer = false
                    }
                    .buttonStyle(.link)
                }
            }

            HStack {
                Spacer()
                Button(L("Скасувати")) { showTransfer = false }
                Button(L("Перевести"), action: performTransfer)
                    .buttonStyle(.borderedProminent)
                    .disabled(transferTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private func performTransfer() {
        let target = transferTarget.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        controller.transfer(call, to: target)
        transferTarget = ""
        showTransfer = false
    }

    private var statusColor: Color {
        if call.isOnHold || call.isHeldByRemote { return .orange }
        return call.state.isTalking ? .green : .blue
    }

    private var statusLine: String {
        if call.isOnHold { return "На утриманні · \(call.duration.callDurationText)" }
        if call.isHeldByRemote { return L("Утримано співрозмовником") }
        switch call.state {
        case .calling, .connecting: return L("Виклик…")
        case .early: return call.lastStatusCode == 180 ? L("Дзвінок…") : L("З'єднання…")
        case .confirmed: return "Розмова · \(call.duration.callDurationText)"
        case .incoming: return L("Вхідний")
        default: return call.lastStatusText
        }
    }
}
