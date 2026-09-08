import SwiftUI

enum Theme {
    static let windowWidth: CGFloat = 400
    static let windowHeight: CGFloat = 660
    static let corner: CGFloat = 10

    /// Розміри взяті з набирача iPhone: клавіші — кола однакового діаметра,
    /// проміжки між ними трохи менші за половину діаметра.
    static let keySize: CGFloat = 68
    static let keySpacing: CGFloat = 22
    static let callButtonSize: CGFloat = 62
}

/// Кругла клавіша набору: цифра, під нею — літери, як на телефоні.
struct KeypadButton: View {
    let digit: String
    let letters: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isPressed ? 0.22 : 0.09))
                VStack(spacing: 0) {
                    Text(digit)
                        .font(.system(size: 30, weight: .regular, design: .default))
                        .foregroundStyle(.primary)
                    if !letters.isEmpty {
                        Text(letters)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                    }
                }
                .offset(y: letters.isEmpty ? 0 : -1)
            }
            .frame(width: Theme.keySize, height: Theme.keySize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

/// Велика кругла кнопка виклику.
struct CircleCallButton: View {
    var symbol = "phone.fill"
    var tint: Color = .green
    var size: CGFloat = Theme.callButtonSize
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(tint)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Кругла кнопка керування розмовою — мікрофон, утримання, перевід.
struct CallActionButton: View {
    let symbol: String
    let title: String
    var tint: Color = .primary
    var isActive = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isActive ? tint.opacity(0.9) : Color.primary.opacity(0.09))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isActive ? Color.white : tint)
                }
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 4)
                    .scaleEffect(animate ? 1.8 : 1)
                    .opacity(animate ? 0 : 1)
            )
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

extension View {
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
