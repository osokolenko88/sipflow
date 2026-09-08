// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SIPCore

/// Оформлення застосунку. `system` — слідувати за налаштуванням macOS.
enum AppearanceMode: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return L("Системна")
        case .light: return L("Світла")
        case .dark: return L("Темна")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var accounts: [SIPAccountConfig] = []
    /// Акаунт для вихідних дзвінків; nil — перший активний.
    var defaultAccountID: UUID?

    var logLevel = 3
    var sipPort = 0
    var echoCancellationTail = 200
    var enableVAD = false
    var clockRate = 16000
    /// STUN та ICE у pjsua глобальні, тому живуть поруч зі стеком, а не в акаунті.
    var stunServer = ""
    var iceEnabled = false
    var logToFile = false

    var captureDeviceID: Int32 = -1
    var playbackDeviceID: Int32 = -1
    var ringtoneEnabled = true
    var ringtoneID = Ringtone.fallback.id
    var ringtoneVolume = 0.6
    var doNotDisturb = false
    var autoAnswer = false
    var autoAnswerDelay = 3
    var showMenuBarIcon = true
    var appearance: AppearanceMode = .system
    var accent: AccentTheme = .blue

    /// `PCMU/8000/1` → пріоритет 0…255. Порожньо — лишаємо типові pjsip.
    var codecPriorities: [String: UInt8] = [:]

    var engineOptions: SIPEngineOptions {
        SIPEngineOptions(
            logLevel: logLevel,
            userAgent: "SIPflow/\(AppInfo.version) (macOS)",
            sipPort: sipPort,
            echoCancellationTail: echoCancellationTail,
            enableVAD: enableVAD,
            clockRate: clockRate,
            stunServer: stunServer,
            enableICE: iceEnabled
        )
    }

    var activeAccounts: [SIPAccountConfig] { accounts.filter(\.isActive) }

    func account(with id: UUID?) -> SIPAccountConfig? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    /// Акаунти самі по собі перезапуску не потребують — лише параметри стеку.
    var stackFingerprint: String {
        [
            String(logLevel), String(sipPort), String(echoCancellationTail),
            String(enableVAD), String(clockRate), stunServer, String(iceEnabled),
        ].joined(separator: "|")
    }

    /// Разом зі списком акаунтів визначає, чи є що застосовувати.
    var accountsFingerprint: String {
        accounts.map(\.registrationFingerprint).joined(separator: "\n")
    }

    private enum CodingKeys: String, CodingKey {
        case accounts, defaultAccountID, logLevel, sipPort, echoCancellationTail, enableVAD
        case clockRate, stunServer, iceEnabled, logToFile, captureDeviceID, playbackDeviceID
        case ringtoneEnabled, ringtoneID, ringtoneVolume, doNotDisturb, autoAnswer, autoAnswerDelay, showMenuBarIcon
        case appearance, accent
        case codecPriorities
        /// Формат до появи кількох акаунтів.
        case account
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let list = try container.decodeIfPresent([SIPAccountConfig].self, forKey: .accounts) {
            accounts = list
        } else if let legacy = try container.decodeIfPresent(SIPAccountConfig.self, forKey: .account) {
            accounts = [legacy]
        }
        defaultAccountID = try container.decodeIfPresent(UUID.self, forKey: .defaultAccountID)

        logLevel = try container.decodeIfPresent(Int.self, forKey: .logLevel) ?? logLevel
        sipPort = try container.decodeIfPresent(Int.self, forKey: .sipPort) ?? sipPort
        echoCancellationTail = try container.decodeIfPresent(Int.self, forKey: .echoCancellationTail) ?? echoCancellationTail
        enableVAD = try container.decodeIfPresent(Bool.self, forKey: .enableVAD) ?? enableVAD
        clockRate = try container.decodeIfPresent(Int.self, forKey: .clockRate) ?? clockRate
        stunServer = try container.decodeIfPresent(String.self, forKey: .stunServer) ?? stunServer
        iceEnabled = try container.decodeIfPresent(Bool.self, forKey: .iceEnabled) ?? iceEnabled
        logToFile = try container.decodeIfPresent(Bool.self, forKey: .logToFile) ?? logToFile

        captureDeviceID = try container.decodeIfPresent(Int32.self, forKey: .captureDeviceID) ?? captureDeviceID
        playbackDeviceID = try container.decodeIfPresent(Int32.self, forKey: .playbackDeviceID) ?? playbackDeviceID
        ringtoneEnabled = try container.decodeIfPresent(Bool.self, forKey: .ringtoneEnabled) ?? ringtoneEnabled
        ringtoneID = try container.decodeIfPresent(String.self, forKey: .ringtoneID) ?? ringtoneID
        ringtoneVolume = try container.decodeIfPresent(Double.self, forKey: .ringtoneVolume) ?? ringtoneVolume
        doNotDisturb = try container.decodeIfPresent(Bool.self, forKey: .doNotDisturb) ?? doNotDisturb
        autoAnswer = try container.decodeIfPresent(Bool.self, forKey: .autoAnswer) ?? autoAnswer
        autoAnswerDelay = try container.decodeIfPresent(Int.self, forKey: .autoAnswerDelay) ?? autoAnswerDelay
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        accent = try container.decodeIfPresent(AccentTheme.self, forKey: .accent) ?? accent
        codecPriorities = try container.decodeIfPresent([String: UInt8].self, forKey: .codecPriorities) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encodeIfPresent(defaultAccountID, forKey: .defaultAccountID)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(sipPort, forKey: .sipPort)
        try container.encode(echoCancellationTail, forKey: .echoCancellationTail)
        try container.encode(enableVAD, forKey: .enableVAD)
        try container.encode(clockRate, forKey: .clockRate)
        try container.encode(stunServer, forKey: .stunServer)
        try container.encode(iceEnabled, forKey: .iceEnabled)
        try container.encode(logToFile, forKey: .logToFile)
        try container.encode(captureDeviceID, forKey: .captureDeviceID)
        try container.encode(playbackDeviceID, forKey: .playbackDeviceID)
        try container.encode(ringtoneEnabled, forKey: .ringtoneEnabled)
        try container.encode(ringtoneID, forKey: .ringtoneID)
        try container.encode(ringtoneVolume, forKey: .ringtoneVolume)
        try container.encode(doNotDisturb, forKey: .doNotDisturb)
        try container.encode(autoAnswer, forKey: .autoAnswer)
        try container.encode(autoAnswerDelay, forKey: .autoAnswerDelay)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(accent, forKey: .accent)
        try container.encode(codecPriorities, forKey: .codecPriorities)
    }
}

enum AppInfo {
    static let version = "1.0"
    static let name = "SIPflow"

    /// Назва, під якою застосунок зберігав дані до переназви на SIPflow.
    private static let previousName = "Telephon"

    static var supportDirectory: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(name, isDirectory: true)

        // Переносимо теку зі старою назвою, щоб не втратити акаунти, контакти й журнал.
        let legacy = base.appendingPathComponent(previousName, isDirectory: true)
        if !manager.fileExists(atPath: directory.path), manager.fileExists(atPath: legacy.path) {
            try? manager.moveItem(at: legacy, to: directory)
        }

        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var logFile: URL { supportDirectory.appendingPathComponent("sipflow.log") }
}

/// Результат читання файлу налаштувань. Паролі тут ще порожні —
/// їх дістає `loadPasswords`, бо звернення до Keychain може блокуватися.
struct LoadedSettings {
    var settings: AppSettings
    /// Файл збережено версією з одним акаунтом — паролі лежать під старими ключами.
    var isLegacyFormat: Bool
}

/// Читання/запис налаштувань. Паролі ходять окремо через Keychain,
/// тож у JSON на диску їх немає.
enum SettingsStore {
    private static var url: URL { AppInfo.supportDirectory.appendingPathComponent("settings.json") }

    /// Доступ до Keychain серіалізовано й винесено з головного потоку: `SecItem*`
    /// може надовго зупинитися на системному діалозі підтвердження доступу
    /// (наприклад, коли підпис застосунку змінився після перезбірки).
    private static let keychainQueue = DispatchQueue(label: "com.sipflow.keychain")

    /// Швидке читання файлу — без Keychain, тож безпечне для головного потоку.
    static func load() -> LoadedSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return LoadedSettings(settings: AppSettings(), isLegacyFormat: false)
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let isLegacy = object?["accounts"] == nil && object?["account"] != nil
        return LoadedSettings(settings: settings, isLegacyFormat: isLegacy)
    }

    /// Дочитує паролі з Keychain у фоні й повертає доповнені налаштування на головну чергу.
    static func loadPasswords(for loaded: LoadedSettings, completion: @escaping (AppSettings) -> Void) {
        keychainQueue.async {
            var settings = loaded.settings
            for index in settings.accounts.indices {
                let account = settings.accounts[index]
                // У форматі з одним акаунтом пароль лежав під ключем `user@domain`.
                let key = loaded.isLegacyFormat ? legacyKey(for: account) : account.id.uuidString
                settings.accounts[index].password = Keychain.password(for: key)
            }

            if loaded.isLegacyFormat {
                let migrated = settings
                writeFile(migrated)
                for account in migrated.accounts {
                    Keychain.setPassword(account.password, for: account.id.uuidString)
                    // Старий запис прибираємо лише коли пароль справді перенесено.
                    if !account.password.isEmpty { Keychain.remove(legacyKey(for: account)) }
                }
            }

            let result = settings
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// `allowClearingPasswords: false` — доки паролі не прочитані з Keychain, порожнє
    /// значення означає «ще не завантажено», а не «користувач стер пароль».
    static func save(_ settings: AppSettings, allowClearingPasswords: Bool = true) {
        writeFile(settings)
        let accounts = settings.accounts
        keychainQueue.async {
            for account in accounts {
                if account.password.isEmpty, !allowClearingPasswords { continue }
                Keychain.setPassword(account.password, for: account.id.uuidString)
            }
        }
    }

    /// Пароль видаленого акаунта не має лишатися в Keychain.
    static func forget(_ account: SIPAccountConfig) {
        keychainQueue.async { Keychain.remove(account.id.uuidString) }
    }

    private static func writeFile(_ settings: AppSettings) {
        var stripped = settings
        for index in stripped.accounts.indices {
            stripped.accounts[index].password = ""
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stripped) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func legacyKey(for account: SIPAccountConfig) -> String {
        "\(account.effectiveAuthUser)@\(account.domain)"
    }
}
