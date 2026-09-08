import SwiftUI
import SIPCore

struct ContactsView: View {
    @EnvironmentObject private var controller: PhoneController
    @State private var query = ""
    @State private var editing: Contact?
    @State private var pendingDeletion: Contact?

    private var results: [Contact] { controller.contacts.search(query) }
    private var favorites: [Contact] { results.filter(\.isFavorite) }
    private var others: [Contact] { results.filter { !$0.isFavorite } }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            if controller.contacts.contacts.isEmpty {
                placeholder(
                    symbol: "person.crop.circle.badge.plus",
                    text: L("Телефонна книга порожня"),
                    hint: L("Додайте контакт кнопкою «+» або з журналу дзвінків")
                )
            } else if results.isEmpty {
                placeholder(symbol: "magnifyingglass", text: L("Нічого не знайдено"), hint: "")
            } else {
                List {
                    if !favorites.isEmpty {
                        Section(L("Обрані")) {
                            ForEach(favorites) { row(for: $0) }
                        }
                    }
                    if !others.isEmpty {
                        Section(favorites.isEmpty ? "" : L("Усі")) {
                            ForEach(others) { row(for: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button {
                    editing = Contact()
                } label: {
                    Label(L("Додати"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(L("%lld контактів", controller.contacts.contacts.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact) { saved in
                if controller.contacts.contacts.contains(where: { $0.id == saved.id }) {
                    controller.contacts.update(saved)
                } else {
                    controller.contacts.add(saved)
                }
            }
        }
        .confirmationDialog(
            "Видалити «\(pendingDeletion?.displayName ?? "")»?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Видалити"), role: .destructive) {
                if let pendingDeletion { controller.contacts.remove(pendingDeletion) }
                pendingDeletion = nil
            }
            Button(L("Скасувати"), role: .cancel) { pendingDeletion = nil }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("Пошук за іменем або номером"), text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func row(for contact: Contact) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(controller.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(contact.initials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(controller.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(contact.number)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                controller.dial(contact.number)
            } label: {
                Image(systemName: "phone.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.green)
            .help(L("Подзвонити"))
            .disabled(!controller.canDial)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { controller.dial(contact.number) }
        .contextMenu {
            Button(L("Подзвонити")) { controller.dial(contact.number) }
            Button(contact.isFavorite ? L("Прибрати з обраних") : L("Додати в обрані")) {
                controller.contacts.toggleFavorite(contact)
            }
            Button(L("Скопіювати номер")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(contact.number, forType: .string)
            }
            Divider()
            Button(L("Редагувати")) { editing = contact }
            Button(L("Видалити"), role: .destructive) { pendingDeletion = contact }
        }
    }

    private func placeholder(symbol: String, text: String, hint: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
            if !hint.isEmpty {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Вікно створення та редагування контакту.
struct ContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Contact
    private let onSave: (Contact) -> Void

    init(contact: Contact, onSave: @escaping (Contact) -> Void) {
        _draft = State(initialValue: contact)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField(L("Ім'я"), text: $draft.name)
                TextField(L("Номер"), text: $draft.number)
                TextField(L("Примітка"), text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
                Toggle(L("Обраний"), isOn: $draft.isFavorite)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(L("Скасувати")) { dismiss() }
                Button(L("Зберегти")) {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}
