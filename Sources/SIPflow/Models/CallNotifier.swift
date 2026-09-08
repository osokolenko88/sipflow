// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SIPCore
import UserNotifications


/// Системне сповіщення про вхідний виклик — для випадку, коли вікно згорнуте
/// або застосунок у фоні й картки дзвінка користувач не бачить.
final class CallNotifier: NSObject {
    enum Action {
        case callBack(String)
        case open
    }

    /// Викликається на головній черзі.
    var onAction: ((Action) -> Void)?
    /// Повідомлення для журналу застосунку.
    var onLog: ((String) -> Void)?

    private static let missedCategoryID = "missed-call"
    private static let callBackID = "call-back"

    /// Орієнтуємось на фактичне налаштування банерів, а не на `authorizationStatus`:
    /// macOS повертає для застосунків із ad-hoc підписом `denied`, хоча банери
    /// при цьому справно доставляються.
    /// Стан дозволу не кешуємо: користувач може увімкнути сповіщення в Системних
    /// параметрах уже після запуску застосунку, і закешоване «заборонено»
    /// назавжди лишило б його без банерів.

    /// У процесі без bundle звернення до центру сповіщень аварійно завершує застосунок,
    /// тому доступ завжди через цю перевірку.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func prepare() {
        guard let center else { return }
        center.delegate = self

        let callBack = UNNotificationAction(identifier: Self.callBackID, title: L("Передзвонити"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.missedCategoryID,
                actions: [callBack],
                intentIdentifiers: [],
                options: []
            )
        ])

        // Запит на дозвіл потрібен, щоб застосунок з'явився в системних параметрах
        // і користувач побачив звичний запит під час першого запуску.
        center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error {
                    self?.onLog?(L("Запит дозволу на сповіщення відхилено системою: %@", error.localizedDescription))
                } else if !granted {
                    self?.onLog?(L("Сповіщення не дозволені — увімкніть їх у Системних параметрах → Сповіщення → SIPflow"))
                }
            }
        }
        // Банер про дзвінок, який тривав під час минулого запуску, лишається
        // в центрі сповіщень і вже не має сенсу — прибираємо його на старті.
        center.removeAllDeliveredNotifications()
    }

    /// Сповіщення про пропущений виклик. На відміну від банера про вхідний,
    /// воно лишається в центрі сповіщень — саме його побачить оператор,
    /// повернувшись до комп'ютера.
    func notifyMissed(_ record: CallRecord, name: String) {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                let authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                guard authorized, settings.alertSetting == .enabled else { return }

                let content = UNMutableNotificationContent()
                content.title = L("Пропущений дзвінок")
                content.subtitle = name
                content.body = record.startedAt.formatted(date: .omitted, time: .shortened)
                content.categoryIdentifier = Self.missedCategoryID
                content.userInfo = ["number": record.number]

                let request = UNNotificationRequest(
                    identifier: "missed-\(record.id.uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request) { error in
                    guard let error else { return }
                    DispatchQueue.main.async {
                        self?.onLog?(L("Не вдалося показати сповіщення про пропущений: %@", error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Прибирає сповіщення про пропущені — коли оператор їх переглянув.
    func withdrawMissed() {
        center?.getDeliveredNotifications { [weak self] delivered in
            let identifiers = delivered
                .filter { $0.request.content.categoryIdentifier == Self.missedCategoryID }
                .map(\.request.identifier)
            guard !identifiers.isEmpty else { return }
            self?.center?.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    /// Розгорнутий стан для журналу — щоб було видно, чому ухвалено таке рішення.
    var foregroundDetails: String {
        let visible = NSApp.windows.filter { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
        return "активний=\(NSApp.isActive), видимих вікон=\(visible.count)"
    }

    /// Вікно застосунку на екрані й він активний — оператор бачить картку дзвінка.
    var isInForeground: Bool {
        guard NSApp.isActive else { return false }
        return NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
    }

    private static func identifier(for callID: Int32) -> String { "call-\(callID)" }
}

extension CallNotifier: UNUserNotificationCenterDelegate {
    /// Викликається в довільному потоці, тому дію передаємо на головну чергу.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.actionIdentifier

        DispatchQueue.main.async { [weak self] in
            defer { completionHandler() }
            guard let self else { return }
            switch identifier {
            case Self.callBackID:
                if let number = response.notification.request.content.userInfo["number"] as? String {
                    self.onAction?(.callBack(number))
                }
            case UNNotificationDefaultActionIdentifier:
                self.onAction?(.open)
            default:
                break
            }
        }
    }
}
