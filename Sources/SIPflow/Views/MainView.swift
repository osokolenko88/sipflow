import SwiftUI
import SIPCore

enum MainTab: String, CaseIterable, Identifiable {
    case dialer, history, contacts, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dialer: return L("Набір")
        case .contacts: return L("Контакти")
        case .history: return L("Останні")
        case .log: return L("Лог")
        }
    }

    var symbol: String {
        switch self {
        case .dialer: return "circle.grid.3x3.fill"
        case .contacts: return "person.crop.circle.fill"
        case .history: return "clock.fill"
        case .log: return "text.alignleft"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var controller: PhoneController
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MainTab = .dialer

    var body: some View {
        VStack(spacing: 0) {
            AccountHeader()
            Divider()

            if controller.hasCalls {
                VStack(spacing: 8) {
                    ForEach(controller.calls) { call in
                        if call.isRinging {
                            IncomingCallCard(call: call)
                        } else {
                            ActiveCallCard(call: call)
                        }
                    }
                }
                .padding(10)
                Divider()
            }

            Group {
                switch tab {
                case .dialer: DialerView()
                case .contacts: ContactsView()
                case .history: HistoryView()
                case .log: LogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Оператор побачив список пропущених — лічильник більше не потрібен.
            .onChange(of: tab) { if tab == .history { controller.markMissedAsSeen() } }

            Divider()
            tabBar
        }
        .frame(minWidth: Theme.windowWidth, minHeight: Theme.windowHeight)
        .tint(controller.accentColor)
        .onAppear { controller.showMainWindow = { openWindow(id: "main") } }
        .alert(L("Помилка"), isPresented: Binding(
            get: { controller.lastError != nil },
            set: { if !$0 { controller.lastError = nil } }
        )) {
            Button("OK") { controller.lastError = nil }
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 17))
                            if item == .history, controller.unseenMissedCount > 0 {
                                Text("\(controller.unseenMissedCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.red))
                                    .offset(x: 10, y: -6)
                            }
                        }
                        Text(item.title)
                            .font(.system(size: 10, weight: tab == item ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 5)
                    .foregroundStyle(tab == item ? controller.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
    }
}

/// Шапка зі станом акаунта. Коли акаунтів кілька — тут же обирається той,
/// з якого йдуть вихідні дзвінки.
struct AccountHeader: View {
    @EnvironmentObject private var controller: PhoneController
    @Environment(\.openSettings) private var openSettings

    private var accounts: [SIPAccountConfig] { controller.settings.accounts }
    private var current: SIPAccountConfig? { controller.currentAccount }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: dotColor, pulsing: isPending)

            if accounts.count > 1 {
                accountPicker
            } else {
                summary
            }

            Spacer()

            Toggle(isOn: $controller.settings.doNotDisturb) {
                Image(systemName: controller.settings.doNotDisturb ? "moon.fill" : "moon")
            }
            .toggleStyle(.button)
            .help(L("Не турбувати — вхідні відхиляються з 486 Busy"))
            .onChange(of: controller.settings.doNotDisturb) { controller.persist() }

            Button {
                controller.reregister()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L("Перереєструвати всі акаунти"))
            .disabled(controller.settings.activeAccounts.isEmpty)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L("Налаштування"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(current?.title ?? L("Акаунт не налаштовано"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(controller.statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var accountPicker: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    controller.setDefaultAccount(account)
                } label: {
                    let mark = account.id == current?.id ? "● " : "○ "
                    Text("\(mark)\(account.title) — \(controller.registration(of: account).title)")
                }
                .disabled(!account.isActive)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(current?.title ?? L("Акаунт не налаштовано"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(controller.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("Акаунт для вихідних дзвінків"))
    }

    private var isPending: Bool {
        if controller.isWaitingForKeychain { return true }
        if controller.engineState == .starting { return true }
        guard let current else { return false }
        return controller.registration(of: current) == .registering
    }

    private var dotColor: Color {
        if controller.isWaitingForKeychain { return .red }
        if case .failed = controller.engineState { return .red }
        guard let current else { return .secondary }
        let state = controller.registration(of: current)
        if case .failed = state { return .red }
        if state.isWarning { return .orange }
        if state.isRegistered { return .green }
        return isPending ? .orange : .secondary
    }
}
