// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import AppKit
import SwiftUI
import Combine
import Foundation
import SIPCore

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: Int
    let message: String
}

@MainActor
final class PhoneController: ObservableObject {
    @Published var settings: AppSettings
    @Published private(set) var engineState: SIPEngineState = .stopped
    @Published private(set) var registrations: [UUID: RegistrationState] = [:]
    @Published private(set) var calls: [SIPCallSnapshot] = []
    @Published private(set) var audioDevices: [AudioDevice] = []
    @Published private(set) var codecs: [SIPCodec] = []
    @Published private(set) var logs: [LogEntry] = []
    @Published var lastError: String?
    /// Читання Keychain затягнулося — майже напевно на екрані висить системний
    /// запит доступу. Без відповіді на нього акаунт не зареєструється, тому про
    /// це треба сказати прямо, а не мовчати.
    @Published private(set) var isWaitingForKeychain = false
    /// Набраний номер у полі введення.
    @Published var dialInput = ""

    let history = CallHistoryStore()
    let contacts = ContactStore()

    private let engine = SIPEngine.shared
    private let ringer = Ringer()
    private let notifier = CallNotifier()
    private let logWriter = LogFileWriter(url: AppInfo.logFile)
    private let statusBar = StatusBarController()
    private let callPanel = CallPanelController()
    private let dockBadge = DockBadgeView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    /// Дія відкриття головного вікна; підставляє MainView, бо лише вона має доступ
    /// до середовища SwiftUI.
    var showMainWindow: (() -> Void)?
    private var appliedStackFingerprint = ""
    private var appliedAccountsFingerprint = ""
    private var durationTimer: Timer?
    private var autoAnswerWork: DispatchWorkItem?
    private var applyWork: DispatchWorkItem?
    private let loaded: LoadedSettings
    /// Доки паролі не прочитані з Keychain, зберігати їх назад не можна —
    /// інакше порожні значення затерли б справжні.
    private var credentialsLoaded = false
    /// Остання показана кількість — щоб не смикати Dock і журнал без потреби.
    private var shownMissedCount = -1
    /// Запит уваги з `.criticalRequest` змушує значок у Dock стрибати, доки його
    /// не скасувати або доки застосунок не стане активним. Тримаємо токен, щоб
    /// зупинити стрибання, коли дзвінок завершився.
    private var attentionRequest: Int?
    private let maxLogEntries = 2000

    init() {
        let loaded = SettingsStore.load()
        settings = loaded.settings
        self.loaded = loaded
        engine.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    // MARK: - Похідний стан

    var activeCall: SIPCallSnapshot? {
        calls.first { $0.state.isTalking && !$0.isOnHold } ?? calls.first { $0.state.isTalking }
    }

    var incomingCall: SIPCallSnapshot? {
        calls.first { $0.isRinging }
    }

    var outgoingCall: SIPCallSnapshot? {
        calls.first { !$0.isIncoming && ($0.state == .calling || $0.state == .early || $0.state == .connecting) }
    }

    var hasCalls: Bool { !calls.isEmpty }

    // MARK: - Телефонна книга

    /// Ім'я абонента: спершу телефонна книга, далі те, що прислав сервер.
    func displayName(forNumber number: String, fallback: String = "") -> String {
        if let contact = contacts.contact(forNumber: number) { return contact.displayName }
        if !fallback.isEmpty { return fallback }
        return number
    }

    func title(for call: SIPCallSnapshot) -> String {
        displayName(forNumber: call.remoteNumber, fallback: call.remoteDisplayName.isEmpty ? call.remoteURI : call.remoteDisplayName)
    }

    func title(for record: CallRecord) -> String {
        displayName(forNumber: record.number, fallback: record.displayName)
    }

    func isKnown(_ number: String) -> Bool { contacts.contact(forNumber: number) != nil }

    /// Створює контакт із номера, який уже є в журналі.
    func addContact(fromRecord record: CallRecord) -> Contact {
        Contact(name: record.displayName, number: record.number)
    }

    // MARK: - Пропущені

    var unseenMissedCount: Int { history.unseenMissed.count }

    func markMissedAsSeen() {
        guard unseenMissedCount > 0 else { return }
        history.markMissedAsSeen()
        notifier.withdrawMissed()
        refreshMissedIndicators()
    }

    /// Значок у Dock і в рядку меню — щоб пропущене було видно з будь-якого місця системи.
    func refreshMissedIndicators() {
        let count = unseenMissedCount
        guard count != shownMissedCount else { return }
        shownMissedCount = count
        // Цифра на іконці в Dock — так само, як непрочитані листи в Пошті.
        let tile = NSApp.dockTile
        tile.badgeLabel = nil
        dockBadge.count = count
        tile.contentView = dockBadge
        tile.display()
        onMissedCountChanged?(count)
        appendAppLog(count > 0 ? L("Пропущених: %@", String(count)) : L("Пропущених немає"))
    }

    /// Видалення записів теж міняє кількість непереглянутих, тому йде через контролер.
    func delete(_ record: CallRecord) {
        history.remove(record)
        refreshMissedIndicators()
    }

    func clearHistory() {
        history.removeAll()
        refreshMissedIndicators()
    }

    /// Викликається, коли змінюється кількість непереглянутих пропущених.
    var onMissedCountChanged: ((Int) -> Void)?

    // MARK: - Рядок меню

    private func setUpCallPanel() {
        callPanel.onAnswer = { [weak self] callID in
            guard let self, let call = self.calls.first(where: { $0.id == callID }) else { return }
            self.answer(call)
            self.raiseWindow()
        }
        callPanel.onDecline = { [weak self] callID in
            guard let self, let call = self.calls.first(where: { $0.id == callID }) else { return }
            self.decline(call)
        }
    }

    /// Дзвінок відзвонив — значок у Dock має перестати стрибати.
    private func stopAttentionRequest() {
        guard let request = attentionRequest else { return }
        NSApp.cancelUserAttentionRequest(request)
        attentionRequest = nil
    }

    /// Панель потрібна, лише поки дзвінок дзвонить і його не видно у вікні застосунку.
    private func refreshCallPanel() {
        guard let ringing = calls.first(where: { $0.isRinging }), !notifier.isInForeground else {
            callPanel.hide()
            stopAttentionRequest()
            return
        }
        callPanel.show(
            call: ringing,
            name: title(for: ringing),
            account: settings.accounts.count > 1 ? settings.account(with: ringing.accountID)?.title : nil
        )
    }

    private func setUpStatusBar() {
        statusBar.missedCalls = { [weak self] in self?.history.unseenMissed ?? [] }
        statusBar.statusText = { [weak self] in self?.statusText ?? "" }
        statusBar.onCallBack = { [weak self] record in
            guard let self else { return }
            self.markMissedAsSeen()
            self.raiseWindow()
            self.dial(record.number.isEmpty ? record.uri : record.number)
        }
        statusBar.onMarkSeen = { [weak self] in self?.markMissedAsSeen() }
        statusBar.onOpen = { [weak self] in self?.raiseWindow() }
        onMissedCountChanged = { [weak self] count in
            guard let self else { return }
            self.statusBar.update(missedCount: count, isOnline: self.isOnline)
        }
        applyMenuBarSetting()
    }

    /// Акцентний колір інтерфейсу. Читається з налаштувань, тож зміна діє одразу.
    var accentColor: Color { settings.accent.color }

    /// Оформлення задається на рівні застосунку, тож охоплює і панель дзвінка,
    /// і вікно налаштувань.
    func applyAppearance() {
        NSApp.appearance = settings.appearance.appearance
        persist()
    }

    func applyMenuBarSetting() {
        if settings.showMenuBarIcon {
            statusBar.install()
        } else {
            statusBar.remove()
        }
        refreshMissedIndicators()
    }

    /// Акаунт, з якого йдуть вихідні дзвінки.
    var currentAccount: SIPAccountConfig? {
        settings.account(with: settings.defaultAccountID) ?? settings.activeAccounts.first
    }

    func registration(of account: SIPAccountConfig) -> RegistrationState {
        registrations[account.id] ?? .unregistered
    }

    var onlineAccounts: [SIPAccountConfig] {
        settings.activeAccounts.filter { registration(of: $0).isRegistered }
    }

    var statusText: String {
        if isWaitingForKeychain { return L("Підтвердіть запит Keychain — інакше акаунт не підключиться") }
        if !credentialsLoaded, !settings.accounts.isEmpty { return L("Читання Keychain…") }
        switch engineState {
        case .stopped: return settings.activeAccounts.isEmpty ? L("Акаунт не налаштовано") : L("Вимкнено")
        case .starting: return L("Підключення…")
        case .failed(let message): return message
        case .running:
            let active = settings.activeAccounts
            if active.isEmpty { return L("Акаунт не налаштовано") }
            if active.count == 1 { return registration(of: active[0]).title }
            return L("%@ з %@ онлайн", String(onlineAccounts.count), String(active.count))
        }
    }

    var isOnline: Bool { engineState == .running && !onlineAccounts.isEmpty }

    /// Чи можна дзвонити просто зараз із поточного акаунта.
    var canDial: Bool {
        guard engineState == .running, let account = currentAccount else { return false }
        return registration(of: account).isRegistered
    }

    // MARK: - Життєвий цикл

    func start() {
        if settings.logToFile { logWriter.open() }
        requestMicrophoneAccess()
        startDurationTimer()
        setUpNotifications()
        setUpStatusBar()
        setUpCallPanel()
        NSApp.appearance = settings.appearance.appearance
        // Після перезапуску значок і лічильник мають відновитися.
        refreshMissedIndicators()
        SettingsStore.loadPasswords(for: loaded) { [weak self] stored in
            guard let self else { return }
            // Вливаємо лише паролі: користувач міг щось змінити, поки Keychain думав.
            for account in stored.accounts where !account.password.isEmpty {
                guard let index = self.settings.accounts.firstIndex(where: { $0.id == account.id }),
                      self.settings.accounts[index].password.isEmpty else { continue }
                self.settings.accounts[index].password = account.password
            }
            self.credentialsLoaded = true
            self.isWaitingForKeychain = false
            self.applySettings()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.credentialsLoaded, !self.settings.accounts.isEmpty else { return }
            self.isWaitingForKeychain = true
        }
    }

    private func setUpNotifications() {
        notifier.onLog = { [weak self] message in self?.appendAppLog(message) }
        notifier.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .callBack(let number):
                self.raiseWindow()
                self.markMissedAsSeen()
                self.dial(number)
            case .open:
                self.raiseWindow()
            }
        }
        notifier.prepare()
    }

    /// Піднімає головне вікно — з банера сповіщення або з клацання по значку в Dock.
    func raiseWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            showMainWindow?()
        }
    }

    /// Зберігає налаштування; доки паролі не прочитані, порожні значення в Keychain не пишемо.
    func persist() {
        SettingsStore.save(settings, allowClearingPasswords: credentialsLoaded)
    }

    func shutdown() {
        autoAnswerWork?.cancel()
        applyWork?.cancel()
        durationTimer?.invalidate()
        callPanel.hide()
        statusBar.remove()
        logWriter.close()
        ringer.stop()
        stopAttentionRequest()
        engine.stopAndWait()
    }

    /// Відкладене застосування: у формах налаштувань зміна приходить на кожне
    /// натискання клавіші, а перезапуск стеку посеред набору тексту неприпустимий.
    func scheduleApply(after delay: TimeInterval = 0.8) {
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applySettings() }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Зберігає налаштування і, якщо змінилися параметри стеку, перепіднімає pjsip.
    func applySettings() {
        applyWork?.cancel()
        persist()
        if settings.logToFile { logWriter.open() } else { logWriter.close() }

        let stackFingerprint = settings.stackFingerprint
        let accountsFingerprint = settings.accountsFingerprint
        let stackChanged = stackFingerprint != appliedStackFingerprint
        appliedStackFingerprint = stackFingerprint
        appliedAccountsFingerprint = accountsFingerprint

        guard !settings.activeAccounts.isEmpty else {
            engine.stop()
            return
        }

        if stackChanged || engineState == .stopped {
            engine.start(accounts: settings.accounts, options: settings.engineOptions)
        } else {
            // Акаунти додаються й видаляються на живому стеку, щоб не рвати активні дзвінки.
            engine.applyAccounts(settings.accounts)
            applyAudioSettings()
        }
        engine.setDefaultAccount(settings.defaultAccountID ?? currentAccount?.id)
    }

    // MARK: - Керування акаунтами

    @discardableResult
    func addAccount() -> SIPAccountConfig {
        let account = SIPAccountConfig()
        settings.accounts.append(account)
        if settings.defaultAccountID == nil { settings.defaultAccountID = account.id }
        persist()
        return account
    }

    func update(_ account: SIPAccountConfig) {
        guard let index = settings.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        settings.accounts[index] = account
        applySettings()
    }

    func remove(_ account: SIPAccountConfig) {
        settings.accounts.removeAll { $0.id == account.id }
        registrations[account.id] = nil
        if settings.defaultAccountID == account.id {
            settings.defaultAccountID = settings.activeAccounts.first?.id
        }
        // Пароль видаленого акаунта не має лишатися в Keychain.
        SettingsStore.forget(account)
        applySettings()
    }

    func setDefaultAccount(_ account: SIPAccountConfig) {
        settings.defaultAccountID = account.id
        persist()
        engine.setDefaultAccount(account.id)
    }

    func reregister(_ account: SIPAccountConfig? = nil) {
        engine.refreshRegistration(accountID: account?.id)
    }

    // MARK: - Дії з дзвінками

    func dial(_ input: String? = nil) {
        let target = (input ?? dialInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        do {
            try engine.makeCall(to: target, from: currentAccount?.id)
            dialInput = ""
        } catch {
            lastError = error.localizedDescription
        }
    }

    func answer(_ call: SIPCallSnapshot) {
        autoAnswerWork?.cancel()
        ringer.stop()
        engine.answer(callID: call.id)
    }

    /// 486 Busy Here — стандартна відмова, за якою сервер може перекинути на голосову пошту.
    func decline(_ call: SIPCallSnapshot) {
        autoAnswerWork?.cancel()
        ringer.stop()
        engine.hangup(callID: call.id, code: 486)
    }

    func hangUp(_ call: SIPCallSnapshot) {
        engine.hangup(callID: call.id)
    }

    func hangUpAll() {
        engine.hangupAll()
    }

    func toggleHold(_ call: SIPCallSnapshot) {
        engine.setHold(!call.isOnHold, callID: call.id)
    }

    func toggleMute(_ call: SIPCallSnapshot) {
        engine.setMuted(!call.isMuted, callID: call.id)
    }

    func sendDTMF(_ digit: String, call: SIPCallSnapshot) {
        engine.sendDTMF(digit, callID: call.id)
    }

    func transfer(_ call: SIPCallSnapshot, to destination: String) {
        do {
            try engine.transfer(callID: call.id, to: destination)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Останній набраний номер — його підставляє кнопка виклику при порожньому полі.
    var lastDialedNumber: String? {
        history.records.first { $0.direction == .outgoing && !$0.number.isEmpty }?.number
    }

    func redial(_ record: CallRecord) {
        dial(record.number.isEmpty ? record.uri : record.number)
    }

    // MARK: - Аудіо та кодеки

    func refreshDevices() {
        engine.refreshAudioDevices()
        audioDevices = engine.audioDevices()
        codecs = engine.codecs()
    }

    func applyAudioSettings() {
        guard engine.isRunning else { return }
        let current = engine.currentAudioDevices()
        let capture = settings.captureDeviceID >= 0 ? settings.captureDeviceID : current.capture
        let playback = settings.playbackDeviceID >= 0 ? settings.playbackDeviceID : current.playback
        if capture != current.capture || playback != current.playback {
            engine.setAudioDevices(capture: capture, playback: playback)
        }
        for (codecID, priority) in settings.codecPriorities {
            engine.setCodecPriority(codecID, priority: priority)
        }
        codecs = engine.codecs()
    }

    func setCodecPriority(_ codec: SIPCodec, priority: UInt8) {
        settings.codecPriorities[codec.id] = priority
        engine.setCodecPriority(codec.id, priority: priority)
        codecs = engine.codecs()
        persist()
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - Прослуховування рингтона

    var previewingRingtone: String? { ringer.playing }

    /// Програє мелодію в налаштуваннях, щоб її було чути до першого дзвінка.
    func previewRingtone(_ ringtone: Ringtone) {
        guard !hasCalls else { return }
        if ringer.playing == ringtone.id {
            ringer.stop()
        } else {
            ringer.stop()
            ringer.start(ringtone, volume: settings.ringtoneVolume)
        }
        objectWillChange.send()
    }

    func stopPreview() {
        guard !hasCalls else { return }
        ringer.stop()
        objectWillChange.send()
    }

    // MARK: - Обробка подій рушія

    private func handle(_ event: SIPEvent) {
        switch event {
        case .engineState(let state):
            engineState = state
            if state == .running {
                refreshDevices()
                applyAudioSettings()
            }

        case let .registration(account, state):
            registrations[account] = state
            statusBar.update(missedCount: unseenMissedCount, isOnline: isOnline)

        case .incomingCall(let call):
            calls = engine.calls
            handleIncoming(call)
            refreshRingtone()
            refreshCallPanel()

        case .callUpdated:
            calls = engine.calls
            refreshRingtone()
            refreshCallPanel()

        case .callEnded(let call):
            calls = engine.calls
            autoAnswerWork?.cancel()
            refreshRingtone()
            refreshCallPanel()
            record(call)

        case .audioDevicesChanged:
            audioDevices = engine.audioDevices()

        case .log(let level, let message):
            append(level: level, message: message)
            logWriter.append(level: level, message: message)

        case .failure(let message):
            lastError = message
        }
    }

    private func handleIncoming(_ call: SIPCallSnapshot) {
        if settings.doNotDisturb {
            engine.hangup(callID: call.id, code: 486)
            return
        }

        appendAppLog("Вхідний дзвінок від \(title(for: call)) — \(notifier.foregroundDetails)")
        // Значок у Dock підстрибує; фокус не забираємо — про дзвінок повідомляє
        // власна панель, яка з'являється поверх інших вікон.
        if attentionRequest == nil {
            attentionRequest = NSApp.requestUserAttention(.criticalRequest)
        }

        if settings.autoAnswer {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.calls.contains(where: { $0.id == call.id && $0.isRinging }) else { return }
                self.answer(call)
            }
            autoAnswerWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(max(0, settings.autoAnswerDelay)), execute: work)
        }
    }

    private var hasTalkingCall: Bool { calls.contains { $0.state.isTalking } }

    /// Рішення про звук приймаємо за всім списком дзвінків, а не за окремим:
    /// інакше оновлення активної розмови глушило б дзвінок другого виклику.
    private func refreshRingtone() {
        guard settings.ringtoneEnabled else {
            ringer.stop()
            return
        }

        if calls.contains(where: { $0.isRinging }), !hasTalkingCall {
            ringer.start(Ringtone.named(settings.ringtoneID), volume: settings.ringtoneVolume)
            return
        }

        // Зворотний гудок — лише поки віддалена сторона не надіслала ранню медіа.
        let waitingForAnswer = calls.contains {
            !$0.isIncoming && ($0.state == .calling || $0.state == .early) && !$0.hasAudio
        }
        if waitingForAnswer {
            // Зворотний гудок тихіший — він не має заглушати ранню медіа.
            ringer.start(.ringback, volume: settings.ringtoneVolume, amplitude: 0.13)
            return
        }

        ringer.stop()
    }

    private func record(_ call: SIPCallSnapshot) {
        let direction: CallDirection
        if call.isIncoming {
            direction = call.connectedAt == nil ? .missed : .incoming
        } else {
            direction = .outgoing
        }
        let record = CallRecord(
            direction: direction,
            number: call.remoteNumber,
            displayName: call.remoteDisplayName,
            uri: call.remoteURI,
            startedAt: call.createdAt,
            duration: call.duration,
            statusText: call.lastStatusText,
            isSeen: direction != .missed
        )
        history.add(record)

        guard direction == .missed else { return }
        refreshMissedIndicators()
        notifier.notifyMissed(record, name: title(for: record))
    }

    /// Повідомлення самого застосунку — у те саме вікно логів і той самий файл,
    /// що й трафік pjsip: розбираючи проблему, зручно бачити їх поруч.
    private func appendAppLog(_ message: String) {
        append(level: 3, message: message)
        logWriter.append(level: 3, message: message)
    }

    private func append(level: Int, message: String) {
        logs.append(LogEntry(date: Date(), level: level, message: message))
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
    }

    /// Оновлює тривалість активної розмови раз на секунду.
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.calls.contains(where: { $0.state.isTalking }) else { return }
                self.objectWillChange.send()
            }
        }
    }

    private func requestMicrophoneAccess() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
}
