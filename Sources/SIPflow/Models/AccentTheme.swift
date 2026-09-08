import SwiftUI
import SIPCore

/// Кольорова тема інтерфейсу. Впливає на акцент: активну вкладку, посилання,
/// кнопки й позначки. Смислові кольори — зелений «відповісти», червоний
/// «відхилити», червоний для пропущених — лишаються незмінними: вони несуть
/// значення, а не оформлення.
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case blue, cyan, teal, green, yellow, orange, red, pink, purple, indigo, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return L("Синій")
        case .cyan: return L("Блакитний")
        case .teal: return L("Бірюзовий")
        case .green: return L("Зелений")
        case .yellow: return L("Жовтий")
        case .orange: return L("Помаранчевий")
        case .red: return L("Червоний")
        case .pink: return L("Рожевий")
        case .purple: return L("Фіолетовий")
        case .indigo: return L("Індиго")
        case .graphite: return L("Графітовий")
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .cyan: return .cyan
        case .teal: return .teal
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .indigo: return .indigo
        case .graphite: return .gray
        }
    }
}
