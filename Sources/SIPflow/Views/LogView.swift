import SwiftUI
import SIPCore

/// Живий журнал pjsip — аналог вікна логів у MicroSIP, потрібен для діагностики SIP.
struct LogView: View {
    @EnvironmentObject private var controller: PhoneController
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(controller.logs) { entry in
                            Text(entry.message)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: controller.logs.count) {
                    guard autoScroll, let last = controller.logs.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Divider()
            HStack {
                Toggle(L("Автопрокрутка"), isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button(L("Скопіювати")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.logs.map(\.message).joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(.link)
                Button(L("Очистити")) { controller.clearLogs() }
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 0, 1: return .red
        case 2: return .orange
        case 3: return .primary
        default: return .secondary
        }
    }
}
