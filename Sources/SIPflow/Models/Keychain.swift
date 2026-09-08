// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// Пароль SIP-акаунта тримаємо в Keychain, а не у файлі налаштувань.
enum Keychain {
    private static let service = "com.sipflow.sip"
    /// Служба, під якою паролі зберігалися до переназви на SIPflow.
    private static let previousService = "com.telephon.sip"

    static func password(for account: String) -> String {
        guard !account.isEmpty else { return "" }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        return legacyPassword(for: account)
    }

    /// Пароль, збережений під старою назвою застосунку. Знайшовши його,
    /// одразу переносимо під нову службу.
    private static func legacyPassword(for account: String) -> String {
        var query = baseQuery(account: account)
        query[kSecAttrService as String] = previousService
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        let password = String(decoding: data, as: UTF8.self)
        setPassword(password, for: account)
        return password
    }

    @discardableResult
    static func setPassword(_ password: String, for account: String) -> Bool {
        guard !account.isEmpty else { return false }
        let query = baseQuery(account: account)

        guard !password.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return true
        }

        let data = Data(password.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ account: String) {
        guard !account.isEmpty else { return }
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
