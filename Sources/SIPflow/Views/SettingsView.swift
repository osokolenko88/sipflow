import SwiftUI
import SIPCore

struct SettingsView: View {
    @EnvironmentObject private var controller: PhoneController

    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem { Label(L("Акаунти"), systemImage: "person.2") }
            AudioSettingsView()
                .tabItem { Label(L("Аудіо"), systemImage: "speaker.wave.2") }
            CodecSettingsView()
                .tabItem { Label(L("Кодеки"), systemImage: "waveform") }
            AdvancedSettingsView()
                .tabItem { Label(L("Додатково"), systemImage: "gearshape.2") }
        }
        .frame(width: 640, height: 470)
        .tint(controller.accentColor)
    }
}

/// Палітра акцентних кольорів. Зміна застосовується одразу — застосунок
/// перезапускати не потрібно.
struct AccentPicker: View {
    @EnvironmentObject private var controller: PhoneController

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AccentTheme.allCases) { theme in
                Button {
                    controller.settings.accent = theme
                    controller.persist()
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                                .opacity(controller.settings.accent == theme ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .help(theme.title)
            }
        }
    }
}

// MARK: - Акаунти

struct AccountsSettingsView: View {
    @EnvironmentObject private var controller: PhoneController
    @State private var selection: UUID?
    @State private var draft = SIPAccountConfig()
    @State private var confirmDelete = false

    private var accounts: [SIPAccountConfig] { controller.settings.accounts }
    private var selected: SIPAccountConfig? { accounts.first { $0.id == selection } }
    private var isDirty: Bool { selected.map { $0 != draft } ?? false }

    var body: some View {
        HStack(spacing: 0) {
            accountList
            Divider()
            detail
        }
        .onAppear { if selection == nil { select(accounts.first) } }
        .confirmationDialog(
            "Видалити акаунт «\(selected?.title ?? "")»?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(L("Видалити"), role: .destructive) { deleteSelected() }
            Button(L("Скасувати"), role: .cancel) {}
        } message: {
            Text(L("Акаунт буде знято з реєстрації, а його пароль — видалено з Keychain."))
        }
    }

    // MARK: Список

    private var accountList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(accounts) { account in
                    HStack(spacing: 6) {
                        StatusDot(color: color(for: account))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(subtitle(for: account))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if account.id == controller.currentAccount?.id, accounts.count > 1 {
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .help(L("Типовий акаунт для вихідних дзвінків"))
                        }
                    }
                    .tag(account.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 2) {
                Button {
                    let account = controller.addAccount()
                    select(account)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .help(L("Додати акаунт"))

                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help(L("Видалити акаунт"))

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 200)
        .onChange(of: selection) { select(selected) }
    }

    // MARK: Форма

    @ViewBuilder
    private var detail: some View {
        if selected == nil {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(L("Додайте SIP-акаунт кнопкою «+»"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Toggle(L("Увімкнений"), isOn: $draft.isEnabled)
                        TextField(L("Ім\'я для показу"), text: $draft.displayName)
                        TextField(L("Користувач"), text: $draft.username)
                        TextField(L("Домен / сервер"), text: $draft.domain)
                        SecureField(L("Пароль"), text: $draft.password)
                    }

                    Section(L("Додаткові параметри")) {
                        TextField("Auth ID", text: $draft.authUser, prompt: Text(L("як користувач")))
                        TextField("Registrar", text: $draft.registrar, prompt: Text(L("як домен")))
                        TextField(L("Вихідний проксі"), text: $draft.proxy, prompt: Text(L("не використовується")))
                        Picker(L("Транспорт"), selection: $draft.transport) {
                            ForEach(SIPTransport.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker(L("Шифрування медіа"), selection: $draft.srtp) {
                            ForEach(SRTPMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("DTMF", selection: $draft.dtmf) {
                            ForEach(DTMFMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        TextField(L("Термін реєстрації, с"), value: $draft.registerExpires, format: .number)
                        Toggle(L("Публікувати присутність (PUBLISH)"), isOn: $draft.publishPresence)
                    }
                }
                .formStyle(.grouped)

                Divider()
                footer
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let selected {
                StatusDot(color: color(for: selected))
                Text(controller.registration(of: selected).title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let selected, selected.isActive, selected.id != controller.currentAccount?.id {
                Button(L("Зробити типовим")) { controller.setDefaultAccount(selected) }
            }
            Button(L("Скинути")) { select(selected) }
                .disabled(!isDirty)
            Button(L("Застосувати")) {
                controller.update(draft)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isDirty)
        }
        .padding(12)
    }

    // MARK: Дії

    private func select(_ account: SIPAccountConfig?) {
        selection = account?.id
        draft = account ?? SIPAccountConfig()
    }

    private func deleteSelected() {
        guard let selected else { return }
        let remaining = accounts.filter { $0.id != selected.id }
        controller.remove(selected)
        select(remaining.first)
    }

    private func subtitle(for account: SIPAccountConfig) -> String {
        guard account.isConfigured else { return L("не налаштовано") }
        guard account.isEnabled else { return L("вимкнено") }
        return controller.registration(of: account).title
    }

    private func color(for account: SIPAccountConfig) -> Color {
        guard account.isActive else { return .secondary }
        let state = controller.registration(of: account)
        if case .failed = state { return .red }
        if state.isWarning { return .orange }
        if state.isRegistered { return .green }
        return .orange
    }
}

// MARK: - Аудіо

struct AudioSettingsView: View {
    @EnvironmentObject private var controller: PhoneController

    private var inputs: [AudioDevice] { controller.audioDevices.filter(\.isInput) }
    private var outputs: [AudioDevice] { controller.audioDevices.filter(\.isOutput) }

    var body: some View {
        Form {
            Section(L("Пристрої")) {
                Picker(L("Мікрофон"), selection: $controller.settings.captureDeviceID) {
                    Text(L("Системний типовий")).tag(Int32(-1))
                    ForEach(inputs) { Text($0.name).tag($0.id) }
                }
                Picker(L("Динаміки"), selection: $controller.settings.playbackDeviceID) {
                    Text(L("Системний типовий")).tag(Int32(-1))
                    ForEach(outputs) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Button(L("Оновити список")) { controller.refreshDevices() }
                    Spacer()
                    Text(controller.audioDevices.isEmpty ? L("Стек не запущено") : "\(controller.audioDevices.count) пристроїв")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("Дзвінок")) {
                Toggle(L("Відтворювати дзвінок і зворотний гудок"), isOn: $controller.settings.ringtoneEnabled)

                HStack(spacing: 8) {
                    Picker(L("Мелодія"), selection: $controller.settings.ringtoneID) {
                        ForEach(Ringtone.all) { ringtone in
                            Text(ringtone.name).tag(ringtone.id)
                        }
                    }
                    Button {
                        controller.previewRingtone(Ringtone.named(controller.settings.ringtoneID))
                    } label: {
                        Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.borderless)
                    .help(isPreviewing ? L("Зупинити") : L("Прослухати"))
                    .disabled(controller.hasCalls)
                }

                HStack {
                    Text(L("Гучність"))
                    Slider(value: $controller.settings.ringtoneVolume, in: 0...1)
                }
            }
            .disabled(!controller.settings.ringtoneEnabled)

            Section(L("Обробка")) {
                Toggle(L("Придушення тиші (VAD)"), isOn: $controller.settings.enableVAD)
                TextField(L("Хвіст ехоподавлення, мс"), value: $controller.settings.echoCancellationTail, format: .number)
                Picker(L("Частота дискретизації"), selection: $controller.settings.clockRate) {
                    Text(L("8 кГц")).tag(8000)
                    Text(L("16 кГц")).tag(16000)
                    Text(L("32 кГц")).tag(32000)
                    Text(L("44,1 кГц")).tag(44100)
                }
                Text(L("Зміна параметрів обробки перезапускає стек."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: controller.settings) { controller.scheduleApply() }
        .onChange(of: controller.settings.ringtoneID) {
            // Мелодію змінили під час прослуховування — одразу вмикаємо нову.
            guard isPreviewing || controller.previewingRingtone != nil else { return }
            controller.previewRingtone(Ringtone.named(controller.settings.ringtoneID))
        }
        .onAppear { controller.refreshDevices() }
        .onDisappear { controller.stopPreview() }
    }

    private var isPreviewing: Bool {
        controller.previewingRingtone == controller.settings.ringtoneID
    }
}

// MARK: - Кодеки

struct CodecSettingsView: View {
    @EnvironmentObject private var controller: PhoneController

    var body: some View {
        VStack(spacing: 0) {
            if controller.codecs.isEmpty {
                Text(L("Список доступний після запуску стеку"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(controller.codecs.sorted { $0.priority > $1.priority }) { codec in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { codec.isEnabled },
                                // 128 — типовий «увімкнений» пріоритет pjsip, 0 — вимкнено.
                                set: { controller.setCodecPriority(codec, priority: $0 ? 128 : 0) }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(codec.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(codec.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Stepper(value: Binding(
                                get: { Int(codec.priority) },
                                set: { controller.setCodecPriority(codec, priority: UInt8(max(0, min(255, $0)))) }
                            ), in: 0...255, step: 8) {
                                Text("\(codec.priority)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            Divider()
            Text(L("Вищий пріоритет — кодек пропонується раніше в SDP."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }
}

// MARK: - Додатково

struct AdvancedSettingsView: View {
    @EnvironmentObject private var controller: PhoneController

    var body: some View {
        Form {
            Section(L("Мережа")) {
                TextField(L("Локальний SIP-порт"), value: $controller.settings.sipPort, format: .number)
                Text(L("0 — будь-який вільний порт. Для TLS використовується наступний порт, бо з TCP вони не можуть слухати один."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L("STUN-сервер"), text: $controller.settings.stunServer, prompt: Text("stun.example.com:3478"))
                Toggle(L("Використовувати ICE"), isOn: $controller.settings.iceEnabled)
            }

            Section(L("Інтерфейс")) {
                LabeledContent(L("Колір")) { AccentPicker() }

                Picker(L("Оформлення"), selection: $controller.settings.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: controller.settings.appearance) { controller.applyAppearance() }

                Toggle(L("Значок у рядку меню"), isOn: $controller.settings.showMenuBarIcon)
                    .onChange(of: controller.settings.showMenuBarIcon) { controller.applyMenuBarSetting() }
                Text(L("Показує стан акаунта і кількість пропущених дзвінків біля годинника."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Дзвінки")) {
                Toggle(L("Не турбувати"), isOn: $controller.settings.doNotDisturb)
                Toggle(L("Автовідповідь"), isOn: $controller.settings.autoAnswer)
                TextField(L("Затримка автовідповіді, с"), value: $controller.settings.autoAnswerDelay, format: .number)
                    .disabled(!controller.settings.autoAnswer)
            }

            Section(L("Діагностика")) {
                Picker(L("Рівень логів"), selection: $controller.settings.logLevel) {
                    ForEach(0...5, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle(L("Записувати SIP-лог у файл"), isOn: $controller.settings.logToFile)
                Text(L("Повний обмін пакетами пишеться у sipflow.log поруч із налаштуваннями. Потрібен рівень логів 4 або вище."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("Дані застосунку")) {
                    Button(L("Показати у Finder")) {
                        let target = controller.settings.logToFile ? AppInfo.logFile : AppInfo.supportDirectory
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: controller.settings) { controller.scheduleApply() }
    }
}
