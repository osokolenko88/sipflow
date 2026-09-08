import Foundation

/// Переклад рядка за його українським текстом.
///
/// Ключами навмисно є самі українські рядки, а не абстрактні ідентифікатори:
/// код лишається читабельним, а якщо перекладу немає, користувач бачить
/// осмислений текст, а не `settings.audio.device.title`.
///
/// SwiftUI перекладає літерали у `Text`, `Button` і подібних сам; ця функція
/// потрібна там, куди він не дістає — у моделях, меню AppKit і сповіщеннях.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Переклад із підстановкою значень.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
