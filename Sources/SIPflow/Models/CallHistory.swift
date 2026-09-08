import Foundation
import SIPCore

enum CallDirection: String, Codable, CaseIterable {
    case incoming, outgoing, missed

    var title: String {
        switch self {
        case .incoming: return L("Вхідні")
        case .outgoing: return L("Вихідні")
        case .missed: return L("Пропущені")
        }
    }

    var symbol: String {
        switch self {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        case .missed: return "arrow.down.left"
        }
    }
}

struct CallRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var direction: CallDirection
    var number: String
    var displayName: String
    var uri: String
    var startedAt: Date
    var duration: TimeInterval
    var statusText: String
    /// Пропущений уже показано користувачеві — лічильник його не рахує.
    var isSeen: Bool = false

    init(
        id: UUID = UUID(),
        direction: CallDirection,
        number: String,
        displayName: String,
        uri: String,
        startedAt: Date,
        duration: TimeInterval,
        statusText: String,
        isSeen: Bool = false
    ) {
        self.id = id
        self.direction = direction
        self.number = number
        self.displayName = displayName
        self.uri = uri
        self.startedAt = startedAt
        self.duration = duration
        self.statusText = statusText
        self.isSeen = isSeen
    }

    /// Записи, збережені до появи лічильника пропущених, вважаємо переглянутими.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            direction: try container.decodeIfPresent(CallDirection.self, forKey: .direction) ?? .incoming,
            number: try container.decodeIfPresent(String.self, forKey: .number) ?? "",
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
            uri: try container.decodeIfPresent(String.self, forKey: .uri) ?? "",
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date(),
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0,
            statusText: try container.decodeIfPresent(String.self, forKey: .statusText) ?? "",
            isSeen: try container.decodeIfPresent(Bool.self, forKey: .isSeen) ?? true
        )
    }

    var title: String { displayName.isEmpty ? number : displayName }
    var wasAnswered: Bool { duration > 0 }
}

/// Журнал дзвінків у JSON поруч із налаштуваннями.
@MainActor
final class CallHistoryStore: ObservableObject {
    @Published private(set) var records: [CallRecord] = []

    private let limit = 500
    private var url: URL { AppInfo.supportDirectory.appendingPathComponent("history.json") }

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([CallRecord].self, from: data) {
            records = decoded
        }
    }

    func add(_ record: CallRecord) {
        records.insert(record, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        persist()
    }

    func remove(_ record: CallRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func removeAll() {
        records.removeAll()
        persist()
    }

    /// Пропущені, яких оператор ще не бачив.
    var unseenMissed: [CallRecord] { records.filter { $0.direction == .missed && !$0.isSeen } }

    func markMissedAsSeen() {
        guard records.contains(where: { $0.direction == .missed && !$0.isSeen }) else { return }
        for position in records.indices where records[position].direction == .missed {
            records[position].isSeen = true
        }
        persist()
    }

    func records(for direction: CallDirection?) -> [CallRecord] {
        guard let direction else { return records }
        return records.filter { $0.direction == direction }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension TimeInterval {
    /// `01:23` або `1:02:03` для довгих розмов.
    var callDurationText: String {
        let total = Int(rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
