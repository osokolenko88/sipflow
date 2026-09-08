// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Порівняння телефонних номерів. `380955158408`, `0955158408` і `+38 (095) 515-84-08`
/// для користувача — той самий абонент, тож зіставляємо за останніми цифрами.
enum PhoneNumber {
    static let significantDigits = 9

    static func digits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = digits(lhs)
        let right = digits(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        // Порівнюємо хвости: код країни чи міжміський префікс може бути відсутній.
        let length = min(significantDigits, min(left.count, right.count))
        guard length >= 5 else { return false }
        return left.suffix(length) == right.suffix(length)
    }
}

struct Contact: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var number: String
    var note: String
    var isFavorite: Bool

    init(id: UUID = UUID(), name: String = "", number: String = "", note: String = "", isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.number = number
        self.note = note
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            number: try container.decodeIfPresent(String.self, forKey: .number) ?? "",
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
            isFavorite: try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        )
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !number.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? number : trimmed
    }

    /// Ініціали для аватарки-заглушки.
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "#" : letters.joined().uppercased()
    }
}

@MainActor
final class ContactStore: ObservableObject {
    @Published private(set) var contacts: [Contact] = []

    private var url: URL { AppInfo.supportDirectory.appendingPathComponent("contacts.json") }
    /// Пошук імені за номером трапляється на кожен дзвінок і на кожен рядок журналу,
    /// тому тримаємо готовий покажчик за нормалізованим хвостом номера.
    private var index: [String: Contact] = [:]

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        rebuildIndex()
    }

    func add(_ contact: Contact) {
        contacts.append(contact)
        sortAndPersist()
    }

    func update(_ contact: Contact) {
        guard let position = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[position] = contact
        sortAndPersist()
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        sortAndPersist()
    }

    func toggleFavorite(_ contact: Contact) {
        var updated = contact
        updated.isFavorite.toggle()
        update(updated)
    }

    /// Контакт за номером; nil — незнайомий абонент.
    func contact(forNumber number: String) -> Contact? {
        let key = normalizedKey(number)
        guard !key.isEmpty else { return nil }
        if let exact = index[key] { return exact }
        return contacts.first { PhoneNumber.matches($0.number, number) }
    }

    func search(_ query: String) -> [Contact] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return contacts }
        let digits = PhoneNumber.digits(trimmed)
        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(trimmed)
                || contact.note.localizedCaseInsensitiveContains(trimmed)
                || (!digits.isEmpty && PhoneNumber.digits(contact.number).contains(digits))
        }
    }

    private func sortAndPersist() {
        contacts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        rebuildIndex()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(contacts) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func rebuildIndex() {
        index = [:]
        for contact in contacts {
            let key = normalizedKey(contact.number)
            guard !key.isEmpty else { continue }
            index[key] = contact
        }
    }

    private func normalizedKey(_ number: String) -> String {
        let digits = PhoneNumber.digits(number)
        guard digits.count >= 5 else { return digits }
        return String(digits.suffix(PhoneNumber.significantDigits))
    }
}
