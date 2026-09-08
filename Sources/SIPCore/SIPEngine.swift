// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CPJSIP

public struct SIPEngineOptions: Equatable, Sendable {
    /// 0 — тиша, 5 — усе. Відповідає рівням логування pjsip.
    public var logLevel: Int
    public var userAgent: String
    /// 0 — довільний вільний порт.
    public var sipPort: Int
    public var echoCancellationTail: Int
    public var enableVAD: Bool
    public var clockRate: Int
    public var maxCalls: Int
    /// STUN і ICE налаштовуються на рівні стеку, а не окремого акаунта.
    public var stunServer: String
    public var enableICE: Bool

    public init(
        logLevel: Int = 3,
        userAgent: String = "SIPflow/1.0",
        sipPort: Int = 0,
        echoCancellationTail: Int = 200,
        enableVAD: Bool = false,
        clockRate: Int = 16000,
        maxCalls: Int = 8,
        stunServer: String = "",
        enableICE: Bool = false
    ) {
        self.logLevel = logLevel
        self.userAgent = userAgent
        self.sipPort = sipPort
        self.echoCancellationTail = echoCancellationTail
        self.enableVAD = enableVAD
        self.clockRate = clockRate
        self.maxCalls = maxCalls
        self.stunServer = stunServer
        self.enableICE = enableICE
    }
}

public final class SIPEngine {
    public static let shared = SIPEngine()

    /// Викликається на головній черзі.
    public var onEvent: ((SIPEvent) -> Void)?

    private let worker = PJWorker()
    private let lock = NSLock()

    private var _state: SIPEngineState = .stopped
    private var _registrations: [UUID: RegistrationState] = [:]
    private var _calls: [Int32: SIPCallSnapshot] = [:]
    private var _accounts: [SIPAccountConfig] = []
    private var _defaultAccount: UUID?

    /// Відповідність між нашими UUID і ідентифікаторами акаунтів у pjsua.
    private var accountIDs: [UUID: pjsua_acc_id] = [:]
    /// Транспорт створюється по одному на тип і перевикористовується акаунтами.
    private var transports: [SIPTransport: pjsua_transport_id] = [:]
    private var options = SIPEngineOptions()
    /// Скільки разів поспіль намагалися перереєструватися після відкинутої прив'язки.
    private var rebindAttempts: [UUID: Int] = [:]

    private init() {}

    // MARK: - Стан

    public var state: SIPEngineState { lock.withLock { _state } }
    public var calls: [SIPCallSnapshot] {
        lock.withLock { _calls.values.sorted { $0.createdAt < $1.createdAt } }
    }
    public var accounts: [SIPAccountConfig] { lock.withLock { _accounts } }
    public var registrations: [UUID: RegistrationState] { lock.withLock { _registrations } }
    public var isRunning: Bool { state == .running }

    public func registration(of accountID: UUID) -> RegistrationState {
        lock.withLock { _registrations[accountID] ?? .unregistered }
    }

    /// Акаунт, з якого йдуть вихідні дзвінки за замовчуванням.
    public var defaultAccount: UUID? { lock.withLock { _defaultAccount } }

    private func config(of accountID: UUID) -> SIPAccountConfig? {
        lock.withLock { _accounts.first { $0.id == accountID } }
    }

    // MARK: - Життєвий цикл

    /// Піднімає стек і реєструє передані акаунти.
    public func start(accounts: [SIPAccountConfig], options: SIPEngineOptions) {
        worker.async { [weak self] in
            guard let self else { return }
            if self.state != .stopped { self.performStop() }
            self.lock.withLock {
                self._accounts = accounts
                self.options = options
            }
            self.update(state: .starting)
            do {
                try self.performStart()
                self.update(state: .running)
                self.performApplyAccounts(accounts)
            } catch {
                self.performStop()
                self.update(state: .failed(error.localizedDescription))
                self.emit(.failure(error.localizedDescription))
            }
        }
    }

    public func stop() {
        worker.async { [weak self] in
            guard let self else { return }
            self.performStop()
            self.update(state: .stopped)
        }
    }

    /// Зупинка з очікуванням: `pjsua_destroy` знімає реєстрацію і чекає на
    /// відповідь сервера, тому при виході цю роботу не можна лишати асинхронною —
    /// процес завершиться раніше, ніж піде REGISTER з Expires: 0.
    public func stopAndWait(timeout: TimeInterval = 4) {
        let finished = DispatchSemaphore(value: 0)
        worker.async { [weak self] in
            self?.performStop()
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + timeout)
        update(state: .stopped)
    }

    /// Додає, оновлює та видаляє акаунти на живому стеку — без перезапуску pjsip,
    /// щоб зміна одного акаунта не рвала дзвінки на інших.
    public func applyAccounts(_ accounts: [SIPAccountConfig]) {
        worker.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else {
                self.lock.withLock { self._accounts = accounts }
                return
            }
            self.performApplyAccounts(accounts)
        }
    }

    public func setDefaultAccount(_ accountID: UUID?) {
        worker.async { [weak self] in
            guard let self else { return }
            self.lock.withLock { self._defaultAccount = accountID }
            guard let accountID, let pjID = self.accountIDs[accountID] else { return }
            pjsua_acc_set_default(pjID)
        }
    }

    /// Перереєстрація: конкретного акаунта або всіх одразу.
    public func refreshRegistration(accountID: UUID? = nil, renew: Bool = true) {
        worker.async { [weak self] in
            guard let self else { return }
            let targets = accountID.map { [$0] } ?? Array(self.accountIDs.keys)
            for target in targets {
                guard let pjID = self.accountIDs[target] else { continue }
                pjsua_acc_set_registration(pjID, renew ? pjTrue : pjFalse)
            }
        }
    }

    private func performStart() throws {
        activeEngine = self
        try pjTry("pjsua_create") { pjsua_create() }

        let pool = CStringPool()

        var config = pjsua_config()
        pjsua_config_default(&config)
        config.max_calls = UInt32(max(1, min(options.maxCalls, Int(PJSUA_MAX_CALLS))))
        config.user_agent = pool.str(options.userAgent)
        config.cb.on_incoming_call = telephonOnIncomingCall
        config.cb.on_call_state = telephonOnCallState
        config.cb.on_call_media_state = telephonOnCallMediaState
        config.cb.on_reg_state2 = telephonOnRegState

        let stun = options.stunServer.trimmed
        if !stun.isEmpty {
            config.stun_srv_cnt = 1
            config.stun_srv.0 = pool.str(stun)
        }

        var logging = pjsua_logging_config()
        pjsua_logging_config_default(&logging)
        logging.console_level = UInt32(max(0, min(options.logLevel, 5)))
        logging.level = UInt32(max(0, min(options.logLevel, 5)))
        logging.cb = telephonOnLog

        var media = pjsua_media_config()
        pjsua_media_config_default(&media)
        media.clock_rate = UInt32(options.clockRate)
        media.snd_clock_rate = UInt32(options.clockRate)
        media.ec_tail_len = UInt32(options.echoCancellationTail)
        media.no_vad = options.enableVAD ? pjFalse : pjTrue
        media.enable_ice = options.enableICE ? pjTrue : pjFalse

        try pjTry("pjsua_init") { pjsua_init(&config, &logging, &media) }
        try pjTry("pjsua_start") { pjsua_start() }
    }

    private func performStop() {
        for (_, pjID) in accountIDs {
            pjsua_acc_set_registration(pjID, pjFalse)
            pjsua_acc_del(pjID)
        }
        accountIDs.removeAll()
        transports.removeAll()
        pjsua_call_hangup_all()
        pjsua_destroy()
        activeEngine = nil

        let cleared: [UUID] = lock.withLock {
            _calls.removeAll()
            let ids = Array(_registrations.keys)
            _registrations.removeAll()
            return ids
        }
        for id in cleared { emit(.registration(account: id, state: .unregistered)) }
    }

    /// Транспорти створюються на вимогу: по одному на тип, спільні для акаунтів.
    private func transport(for kind: SIPTransport) throws -> pjsua_transport_id {
        if let existing = transports[kind] { return existing }

        var config = pjsua_transport_config()
        pjsua_transport_config_default(&config)
        // TCP і TLS не можуть слухати той самий порт, тому TLS зміщуємо на наступний.
        config.port = UInt32(options.sipPort == 0 ? 0 : options.sipPort + (kind == .tls ? 1 : 0))

        let type: pjsip_transport_type_e
        switch kind {
        case .udp: type = PJSIP_TRANSPORT_UDP
        case .tcp: type = PJSIP_TRANSPORT_TCP
        case .tls: type = PJSIP_TRANSPORT_TLS
        }

        var identifier: pjsua_transport_id = -1
        try pjTry("pjsua_transport_create(\(kind.title))") {
            pjsua_transport_create(type, &config, &identifier)
        }
        transports[kind] = identifier
        return identifier
    }

    /// Звіряє бажаний список акаунтів із тим, що вже живе в pjsua.
    private func performApplyAccounts(_ accounts: [SIPAccountConfig]) {
        let previous = lock.withLock { _accounts }
        lock.withLock { _accounts = accounts }

        let wanted = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })

        for (id, pjID) in accountIDs where wanted[id]?.isActive != true {
            pjsua_acc_set_registration(pjID, pjFalse)
            pjsua_acc_del(pjID)
            accountIDs[id] = nil
            // Стан знятого акаунта повідомляємо востаннє й прибираємо, щоб у таблиці
            // не лишалося записів про акаунти, яких більше немає.
            emit(.registration(account: id, state: .unregistered))
            lock.withLock { _registrations[id] = nil }
        }

        for account in accounts where account.isActive {
            do {
                if let pjID = accountIDs[account.id] {
                    guard previousByID[account.id]?.registrationFingerprint != account.registrationFingerprint else { continue }
                    try modifyAccount(account, pjID: pjID)
                } else {
                    try addAccount(account)
                }
            } catch {
                emit(.failure("\(account.title): \(error.localizedDescription)"))
                update(registration: .failed(code: 0, reason: error.localizedDescription), for: account.id)
            }
        }

        applyDefaultAccount(accounts)
    }

    private func addAccount(_ account: SIPAccountConfig) throws {
        try withAccountConfig(account) { config in
            var pjID: pjsua_acc_id = -1
            update(registration: .registering, for: account.id)
            try pjTry("pjsua_acc_add(\(account.title))") { pjsua_acc_add(config, pjFalse, &pjID) }
            accountIDs[account.id] = pjID
        }
    }

    private func modifyAccount(_ account: SIPAccountConfig, pjID: pjsua_acc_id) throws {
        try withAccountConfig(account) { config in
            update(registration: .registering, for: account.id)
            try pjTry("pjsua_acc_modify(\(account.title))") { pjsua_acc_modify(pjID, config) }
        }
    }

    /// `pjsua_acc_config` містить самопосилальні голови списків заголовків
    /// (`reg_hdr_list`, `sub_hdr_list`), які `pjsua_acc_config_default` ініціалізує
    /// адресою самої структури. Копіювання такої структури засобами Swift лишає ці
    /// вказівники на мертвій пам'яті й валить pjsip під час клонування заголовків,
    /// тому конфігурацію тримаємо за стабільною адресою в купі й нікуди не копіюємо.
    private func withAccountConfig(_ account: SIPAccountConfig, _ body: (UnsafeMutablePointer<pjsua_acc_config>) throws -> Void) throws {
        let pool = CStringPool()
        let config = UnsafeMutablePointer<pjsua_acc_config>.allocate(capacity: 1)
        defer { config.deallocate() }

        pjsua_acc_config_default(config)
        try fill(config, from: account, pool: pool)
        try body(config)
    }

    /// Заповнює конфігурацію на місці — структура нікуди не копіюється.
    private func fill(_ config: UnsafeMutablePointer<pjsua_acc_config>, from account: SIPAccountConfig, pool: CStringPool) throws {
        config.pointee.id = pool.str(account.accountURI)
        config.pointee.reg_uri = pool.str(account.effectiveRegistrar)
        config.pointee.reg_timeout = UInt32(max(30, account.registerExpires))
        // Типові 300 с означають, що після відмови (напр. 403, коли на сервері
        // вичерпано ліміт одночасних реєстрацій) застосунок мовчить 5 хвилин.
        // Перша спроба — швидка, далі помірний інтервал із розкидом, щоб не
        // довбати сервер синхронно з іншими клієнтами.
        config.pointee.reg_first_retry_interval = 8
        config.pointee.reg_retry_interval = 30
        config.pointee.reg_retry_random_interval = 10
        config.pointee.transport_id = try transport(for: account.transport)
        config.pointee.publish_enabled = account.publishPresence ? pjTrue : pjFalse

        // Сталий ідентифікатор пристрою (RFC 5626). Без нього pjsip генерує новий
        // на кожен запуск, і реєстратор накопичує прив'язки від усіх минулих
        // сеансів — вхідний виклик тоді може піти на давно закрите з'єднання.
        config.pointee.use_rfc5626 = 1
        config.pointee.rfc5626_instance_id = pool.str("<urn:uuid:\(account.id.uuidString.lowercased())>")

        let proxy = account.proxy.trimmed
        if !proxy.isEmpty {
            config.pointee.proxy_cnt = 1
            config.pointee.proxy.0 = pool.str(proxy.hasPrefix("sip:") || proxy.hasPrefix("sips:") ? proxy : "sip:\(proxy)")
        }

        if !account.password.isEmpty || !account.effectiveAuthUser.isEmpty {
            config.pointee.cred_count = 1
            config.pointee.cred_info.0.realm = pool.str("*")
            config.pointee.cred_info.0.scheme = pool.str("digest")
            config.pointee.cred_info.0.username = pool.str(account.effectiveAuthUser)
            config.pointee.cred_info.0.data_type = Int32(PJSIP_CRED_DATA_PLAIN_PASSWD.rawValue)
            config.pointee.cred_info.0.data = pool.str(account.password)
        }

        switch account.srtp {
        case .disabled: config.pointee.use_srtp = PJMEDIA_SRTP_DISABLED
        case .optional: config.pointee.use_srtp = PJMEDIA_SRTP_OPTIONAL
        case .mandatory: config.pointee.use_srtp = PJMEDIA_SRTP_MANDATORY
        }
        config.pointee.srtp_secure_signaling = 0
    }

    /// Тримає типовий акаунт валідним: якщо обраний зник, беремо перший активний.
    private func applyDefaultAccount(_ accounts: [SIPAccountConfig]) {
        let current = lock.withLock { _defaultAccount }
        let resolved: UUID? = {
            if let current, accountIDs[current] != nil { return current }
            return accounts.first { accountIDs[$0.id] != nil }?.id
        }()

        lock.withLock { _defaultAccount = resolved }
        if let resolved, let pjID = accountIDs[resolved] {
            pjsua_acc_set_default(pjID)
        }
    }

    // MARK: - Дзвінки

    /// Набирає номер або повний SIP URI з указаного акаунта (типовий, якщо не задано).
    public func makeCall(to input: String, from accountID: UUID? = nil) throws {
        guard isRunning else { throw SIPError.message(L("Стек не запущено")) }
        guard let source = accountID ?? defaultAccount, let account = config(of: source) else {
            throw SIPError.message(L("Немає активного акаунта"))
        }
        guard let pjID = worker.sync({ self.accountIDs[source] }) else {
            throw SIPError.message(L("%@: акаунт не підключено", account.title))
        }
        guard let uri = SIPURI.make(from: input, domain: account.domain, transport: account.transport) else {
            throw SIPError.message(L("Некоректний номер або URI"))
        }

        try worker.syncThrowing {
            let pool = CStringPool()
            var destination = pool.str(uri)
            var settings = pjsua_call_setting()
            pjsua_call_setting_default(&settings)
            settings.aud_cnt = 1
            settings.vid_cnt = 0
            var callID: pjsua_call_id = -1
            try pjTry("pjsua_call_make_call") {
                pjsua_call_make_call(pjID, &destination, &settings, nil, nil, &callID)
            }
        }
    }

    public func answer(callID: Int32, code: Int = 200) {
        // Позначаємо одразу: між нашим 200 OK і переходом сесії в CONNECTING
        // pjsip ще якийсь час повідомляє стан EARLY.
        if code >= 200 { mutateCall(callID) { $0.isAnswering = true } }
        worker.async {
            var settings = pjsua_call_setting()
            pjsua_call_setting_default(&settings)
            settings.aud_cnt = 1
            settings.vid_cnt = 0
            pjsua_call_answer2(callID, &settings, UInt32(code), nil, nil)
        }
    }

    /// 486 Busy Here — «Відхилити», 603 Decline — глобальна відмова.
    public func hangup(callID: Int32, code: Int = 0) {
        worker.async { pjsua_call_hangup(callID, UInt32(code), nil, nil) }
    }

    public func hangupAll() {
        worker.async { pjsua_call_hangup_all() }
    }

    public func setHold(_ hold: Bool, callID: Int32) {
        worker.async { [weak self] in
            let status: pj_status_t
            if hold {
                status = pjsua_call_set_hold(callID, nil)
            } else {
                status = pjsua_call_reinvite(callID, UInt32(PJSUA_CALL_UNHOLD.rawValue), nil)
            }
            guard status == 0 else {
                self?.emit(.failure(SIPError(status: status, context: hold ? L("Утримання") : L("Зняття з утримання")).description))
                return
            }
            self?.mutateCall(callID) { $0.isOnHold = hold }
        }
    }

    public func setMuted(_ muted: Bool, callID: Int32) {
        worker.async { [weak self] in
            var info = pjsua_call_info()
            guard pjsua_call_get_info(callID, &info) == 0, info.conf_slot != -1 else { return }
            // Рівень сигналу, що передається в порт дзвінка, тобто те, що чує співрозмовник.
            pjsua_conf_adjust_tx_level(info.conf_slot, muted ? 0 : 1)
            self?.mutateCall(callID) { $0.isMuted = muted }
        }
    }

    public func sendDTMF(_ digits: String, callID: Int32) {
        // Спосіб передачі DTMF залежить від акаунта, через який іде дзвінок.
        let method = callAccount(callID).map(\.dtmf) ?? .rfc2833
        worker.async {
            let pool = CStringPool()
            var param = pjsua_call_send_dtmf_param()
            pjsua_call_send_dtmf_param_default(&param)
            param.digits = pool.str(digits)
            switch method {
            case .rfc2833: param.method = PJSUA_DTMF_METHOD_RFC2833
            case .sipInfo, .inband: param.method = PJSUA_DTMF_METHOD_SIP_INFO
            }
            pjsua_call_send_dtmf(callID, &param)
        }
    }

    /// Сліпий перевід: дзвінок іде на `destination`, наш канал звільняється.
    public func transfer(callID: Int32, to destination: String) throws {
        let account = callAccount(callID) ?? defaultAccount.flatMap { config(of: $0) } ?? SIPAccountConfig()
        guard let uri = SIPURI.make(from: destination, domain: account.domain, transport: account.transport) else {
            throw SIPError.message(L("Некоректний номер для переводу"))
        }
        worker.async { [weak self] in
            let pool = CStringPool()
            var target = pool.str(uri)
            let status = pjsua_call_xfer(callID, &target, nil)
            if status != 0 {
                self?.emit(.failure(SIPError(status: status, context: L("Перевід дзвінка")).description))
            }
        }
    }

    /// Перевід із консультацією: `callID` з'єднується зі співрозмовником `otherCallID`.
    public func transfer(callID: Int32, replacing otherCallID: Int32) {
        worker.async { [weak self] in
            let status = pjsua_call_xfer_replaces(callID, otherCallID, 0, nil)
            if status != 0 {
                self?.emit(.failure(SIPError(status: status, context: L("Перевід із консультацією")).description))
            }
        }
    }

    /// Акаунт, через який іде дзвінок, за його знімком.
    private func callAccount(_ callID: Int32) -> SIPAccountConfig? {
        guard let accountID = lock.withLock({ _calls[callID]?.accountID }) else { return nil }
        return config(of: accountID)
    }

    // MARK: - Аудіопристрої

    public func audioDevices() -> [AudioDevice] {
        worker.sync {
            guard self.isRunning else { return [] }
            var count = UInt32(64)
            var buffer = [pjmedia_aud_dev_info](repeating: pjmedia_aud_dev_info(), count: Int(count))
            guard pjsua_enum_aud_devs(&buffer, &count) == 0 else { return [] }
            return (0..<Int(count)).map { AudioDevice(index: Int32($0), info: buffer[$0]) }
        }
    }

    public func currentAudioDevices() -> (capture: Int32, playback: Int32) {
        worker.sync {
            var capture: Int32 = -1
            var playback: Int32 = -1
            guard self.isRunning, pjsua_get_snd_dev(&capture, &playback) == 0 else { return (-1, -1) }
            return (capture, playback)
        }
    }

    public func setAudioDevices(capture: Int32, playback: Int32) {
        worker.async { [weak self] in
            let status = pjsua_set_snd_dev(capture, playback)
            if status != 0 {
                self?.emit(.failure(SIPError(status: status, context: L("Вибір аудіопристрою")).description))
            } else {
                self?.emit(.audioDevicesChanged)
            }
        }
    }

    /// Перечитує список пристроїв ОС — потрібне після під'єднання гарнітури.
    public func refreshAudioDevices() {
        worker.async { [weak self] in
            guard self?.isRunning == true else { return }
            pjmedia_aud_dev_refresh()
            self?.emit(.audioDevicesChanged)
        }
    }

    // MARK: - Кодеки

    public func codecs() -> [SIPCodec] {
        worker.sync {
            guard self.isRunning else { return [] }
            var count = UInt32(64)
            var buffer = [pjsua_codec_info](repeating: pjsua_codec_info(), count: Int(count))
            guard pjsua_enum_codecs(&buffer, &count) == 0 else { return [] }
            return (0..<Int(count)).map { SIPCodec(info: buffer[$0]) }
        }
    }

    public func setCodecPriority(_ codecID: String, priority: UInt8) {
        worker.async {
            let pool = CStringPool()
            var identifier = pool.str(codecID)
            pjsua_codec_set_priority(&identifier, priority)
        }
    }

    // MARK: - Внутрішнє

    fileprivate func update(state newState: SIPEngineState) {
        lock.withLock { _state = newState }
        emit(.engineState(newState))
    }

    fileprivate func update(registration newValue: RegistrationState, for accountID: UUID) {
        lock.withLock { _registrations[accountID] = newValue }
        emit(.registration(account: accountID, state: newValue))
    }

    /// Повторює реєстрацію після невдачі, не чекаючи повного терміну.
    ///
    /// Потрібне і коли сервер відкинув прив'язку мовчки, і коли він відповів
    /// відмовою на кшталт 403: pjsip вважає 4xx остаточною помилкою і сам більше
    /// не пробує, а на практиці це часто тимчасово — наприклад, на акаунті
    /// вичерпано ліміт одночасних реєстрацій, і місце звільниться за кілька хвилин.
    private func scheduleRebind(for accountID: UUID) {
        let attempt = (rebindAttempts[accountID] ?? 0) + 1
        guard attempt <= 30 else { return }
        rebindAttempts[accountID] = attempt

        // Перша спроба швидка, далі інтервал зростає до хвилини.
        let delay: TimeInterval = attempt == 1 ? 10 : (attempt < 5 ? 30 : 60)
        worker.asyncAfter(seconds: delay) { [weak self] in
            guard let self, self.accountIDs[accountID] != nil else { return }
            let state = self.registration(of: accountID)
            // Успішна реєстрація скидає лічильник — тоді повторювати нема чого.
            guard state.isWarning || state.isFailed else { return }
            self.emit(.log(level: 3, message: L("Повторна спроба зареєструватися (%@)", String(attempt))))
            self.refreshRegistration(accountID: accountID)
        }
    }

    /// Звіряє адресу, яку ми зареєстрували, зі списком прив'язок у відповіді сервера.
    /// Свою публічну адресу беремо з Via відповіді (`received`/`rport`) — саме її
    /// pjsip підставляє в Contact після перезапису під NAT.
    private func verifyBinding(
        _ parameters: UnsafeMutablePointer<pjsip_regc_cbparam>?
    ) -> (isBound: Bool, ourAddress: String, serverContacts: Int) {
        guard let parameters else { return (true, "", 0) }
        let count = Int(parameters.pointee.contact_cnt)
        guard count > 0,
              let via = parameters.pointee.rdata?.pointee.msg_info.via
        else { return (true, "", count) }

        let received = pjString(via.pointee.recvd_param)
        let rport = Int(via.pointee.rport_param)
        // Без NAT сервер не повертає received/rport — тоді звіряти нема з чим.
        guard !received.isEmpty, rport > 0 else { return (true, "", count) }

        // Зіставляємо за портом NAT: він унікальний для нашого з'єднання, тоді як
        // хост у збереженій прив'язці сервер може переписати на свій розсуд.
        let ourAddress = "\(received):\(rport)"
        var isBound = false
        withUnsafePointer(to: &parameters.pointee.contact) { tuple in
            tuple.withMemoryRebound(to: UnsafeMutablePointer<pjsip_contact_hdr>?.self, capacity: count) { headers in
                for index in 0..<count {
                    guard let header = headers[index] else { continue }
                    if Self.contact(printHeader(header), usesPort: rport) { isBound = true; return }
                }
            }
        }
        return (isBound, ourAddress, count)
    }

    private static func contact(_ contact: String, usesPort port: Int) -> Bool {
        var remainder = Substring(contact)
        let marker = ":\(port)"
        while let range = remainder.range(of: marker) {
            let next = remainder[range.upperBound...].first
            if next == nil || !next!.isNumber { return true }
            remainder = remainder[range.upperBound...]
        }
        return false
    }

    private func printHeader(_ header: UnsafeMutablePointer<pjsip_contact_hdr>) -> String {
        var buffer = [CChar](repeating: 0, count: 512)
        let written = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            pjsip_hdr_print_on(UnsafeMutableRawPointer(header), pointer.baseAddress, pj_size_t(pointer.count - 1))
        }
        guard written > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Зворотне зіставлення ідентифікатора pjsua з нашим UUID.
    fileprivate func accountUUID(for pjID: pjsua_acc_id) -> UUID? {
        accountIDs.first { $0.value == pjID }?.key
    }

    fileprivate func emit(_ event: SIPEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    /// Створює або оновлює знімок дзвінка з даних pjsua і повідомляє про зміну.
    fileprivate func syncCall(id: Int32, isIncomingHint: Bool = false) {
        var info = pjsua_call_info()
        guard pjsua_call_get_info(id, &info) == 0 else { return }

        let remoteURI = pjString(info.remote_info)
        var snapshot = lock.withLock { _calls[id] }
            ?? SIPCallSnapshot(id: id, remoteURI: remoteURI, isIncoming: isIncomingHint || info.role == PJSIP_ROLE_UAS)
        snapshot.accountID = accountUUID(for: info.acc_id)

        if !remoteURI.isEmpty, snapshot.remoteURI != remoteURI {
            snapshot.remoteURI = remoteURI
            let parsed = SIPURI.parse(remoteURI)
            snapshot.remoteNumber = parsed.user
            snapshot.remoteDisplayName = parsed.displayName
        }

        snapshot.state = SIPCallState(invState: info.state)
        snapshot.lastStatusCode = Int(info.last_status.rawValue)
        snapshot.lastStatusText = pjString(info.last_status_text)
        snapshot.hasAudio = info.media_status == PJSUA_CALL_MEDIA_ACTIVE
        snapshot.isHeldByRemote = info.media_status == PJSUA_CALL_MEDIA_REMOTE_HOLD
        if info.media_status == PJSUA_CALL_MEDIA_LOCAL_HOLD { snapshot.isOnHold = true }

        if snapshot.state == .confirmed, snapshot.connectedAt == nil {
            snapshot.connectedAt = Date()
        }

        if snapshot.state == .disconnected {
            snapshot.endedAt = Date()
            lock.withLock { _calls[id] = nil }
            emit(.callEnded(snapshot))
        } else {
            let isNew = lock.withLock { _calls.updateValue(snapshot, forKey: id) == nil }
            emit(isNew && snapshot.isIncoming ? .incomingCall(snapshot) : .callUpdated(snapshot))
        }
    }

    fileprivate func mutateCall(_ id: Int32, _ change: (inout SIPCallSnapshot) -> Void) {
        let updated: SIPCallSnapshot? = lock.withLock {
            guard var snapshot = _calls[id] else { return nil }
            change(&snapshot)
            _calls[id] = snapshot
            return snapshot
        }
        if let updated { emit(.callUpdated(updated)) }
    }

    fileprivate func handleRegistration(
        pjID: pjsua_acc_id,
        code: Int,
        reason: String,
        expiration: Int,
        renew: Bool,
        parameters: UnsafeMutablePointer<pjsip_regc_cbparam>?
    ) {
        guard let accountID = accountUUID(for: pjID) else { return }
        let newValue: RegistrationState
        if code / 100 == 2 {
            if renew, expiration > 0 {
                // 200 OK ще не означає, що нас справді зареєстровано: сервер може
                // мовчки не зберегти прив'язку (напр. коли ліміт зайнятий старими,
                // ще не простроченими реєстраціями). Вхідні тоді просто не доходять.
                let binding = verifyBinding(parameters)
                newValue = binding.isBound
                    ? .registered(expiresIn: expiration)
                    : .notBound(contacts: binding.serverContacts)
                if binding.isBound { rebindAttempts[accountID] = nil }
                if !binding.isBound {
                    emit(.log(level: 2, message: L("Сервер не зберіг нашу адресу %@; у нього %@ інших прив'язок. Вхідні дзвінки не надходитимуть, доки старі не спливуть.", binding.ourAddress, String(binding.serverContacts))))
                    scheduleRebind(for: accountID)
                }
            } else {
                newValue = .unregistered
            }
        } else if code == 0 {
            newValue = .failed(code: 0, reason: reason.isEmpty ? L("Сервер не відповідає") : reason)
            scheduleRebind(for: accountID)
        } else {
            newValue = .failed(code: code, reason: reason)
            scheduleRebind(for: accountID)
        }
        update(registration: newValue, for: accountID)
    }
}

// MARK: - Колбеки pjsua
//
// pjsua приймає лише C-функції без контексту, тож активний рушій тримаємо
// у файловій змінній. Одночасно існує рівно один екземпляр стеку.

private var activeEngine: SIPEngine?

private func telephonOnIncomingCall(_ accountID: pjsua_acc_id, _ callID: pjsua_call_id, _ rdata: UnsafeMutablePointer<pjsip_rx_data>?) {
    guard let engine = activeEngine else { return }
    // 180 Ringing, щоб абонент чув зворотний гудок, поки користувач вирішує.
    pjsua_call_answer(callID, 180, nil, nil)
    engine.syncCall(id: callID, isIncomingHint: true)
}

private func telephonOnCallState(_ callID: pjsua_call_id, _ event: UnsafeMutablePointer<pjsip_event>?) {
    activeEngine?.syncCall(id: callID)
}

private func telephonOnCallMediaState(_ callID: pjsua_call_id) {
    guard let engine = activeEngine else { return }
    var info = pjsua_call_info()
    guard pjsua_call_get_info(callID, &info) == 0 else { return }
    if info.media_status == PJSUA_CALL_MEDIA_ACTIVE, info.conf_slot != -1 {
        // Порт 0 — звукова карта: з'єднуємо її з портом дзвінка в обидва боки.
        pjsua_conf_connect(info.conf_slot, 0)
        pjsua_conf_connect(0, info.conf_slot)
    }
    engine.syncCall(id: callID)
}

private func telephonOnRegState(_ accountID: pjsua_acc_id, _ info: UnsafeMutablePointer<pjsua_reg_info>?) {
    guard let engine = activeEngine, let parameters = info?.pointee.cbparam?.pointee else { return }
    engine.handleRegistration(
        pjID: accountID,
        code: Int(parameters.code),
        reason: pjString(parameters.reason),
        expiration: Int(parameters.expiration),
        renew: info?.pointee.renew != 0,
        parameters: info?.pointee.cbparam
    )
}

private func telephonOnLog(_ level: Int32, _ data: UnsafePointer<CChar>?, _ length: Int32) {
    guard let engine = activeEngine else { return }
    let message = pjString(data, length: length).trimmingCharacters(in: .newlines)
    guard !message.isEmpty else { return }
    engine.emit(.log(level: Int(level), message: message))
}

// MARK: - Допоміжні перетворення

extension SIPCallState {
    init(invState: pjsip_inv_state) {
        switch invState {
        case PJSIP_INV_STATE_CALLING: self = .calling
        case PJSIP_INV_STATE_INCOMING: self = .incoming
        case PJSIP_INV_STATE_EARLY: self = .early
        case PJSIP_INV_STATE_CONNECTING: self = .connecting
        case PJSIP_INV_STATE_CONFIRMED: self = .confirmed
        case PJSIP_INV_STATE_DISCONNECTED: self = .disconnected
        default: self = .idle
        }
    }
}

public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let driver: String
    public let inputCount: Int
    public let outputCount: Int

    init(index: Int32, info: pjmedia_aud_dev_info) {
        self.id = index
        self.name = cString(info.name)
        self.driver = cString(info.driver)
        self.inputCount = Int(info.input_count)
        self.outputCount = Int(info.output_count)
    }

    public var isInput: Bool { inputCount > 0 }
    public var isOutput: Bool { outputCount > 0 }
}

public struct SIPCodec: Identifiable, Hashable, Sendable {
    public let id: String
    public let priority: UInt8
    public let description: String

    init(info: pjsua_codec_info) {
        self.id = pjString(info.codec_id)
        self.priority = info.priority
        self.description = pjString(info.desc)
    }

    /// `PCMU/8000/1` → `PCMU`.
    public var displayName: String { id.components(separatedBy: "/").first ?? id }
    public var isEnabled: Bool { priority > 0 }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
