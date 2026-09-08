import Foundation

// MARK: - Налаштування акаунта

public enum SIPTransport: String, Codable, CaseIterable, Sendable {
    case udp, tcp, tls

    public var title: String { rawValue.uppercased() }
    public var defaultPort: Int { self == .tls ? 5061 : 5060 }
}

public enum SRTPMode: String, Codable, CaseIterable, Sendable {
    case disabled, optional, mandatory

    public var title: String {
        switch self {
        case .disabled: return L("Вимкнено")
        case .optional: return L("Опційно")
        case .mandatory: return L("Обов'язково")
        }
    }
}

public enum DTMFMethod: String, Codable, CaseIterable, Sendable {
    case rfc2833, sipInfo, inband

    public var title: String {
        switch self {
        case .rfc2833: return "RFC 2833"
        case .sipInfo: return "SIP INFO"
        case .inband: return "In-band"
        }
    }
}

public struct SIPAccountConfig: Codable, Equatable, Sendable, Identifiable {
    /// Стабільний ідентифікатор акаунта: під ним зберігається пароль у Keychain
    /// і за ним зіставляються акаунти з тими, що вже додані в pjsua.
    public var id: UUID
    public var isEnabled: Bool
    public var displayName: String
    public var username: String
    public var domain: String
    public var password: String
    /// Порожній — використовується `username`.
    public var authUser: String
    /// Порожній — реєструємось на `domain`.
    public var registrar: String
    /// Вихідний проксі, напр. `sip:proxy.example.com:5060`.
    public var proxy: String
    public var transport: SIPTransport
    public var registerExpires: Int
    public var srtp: SRTPMode
    public var dtmf: DTMFMethod
    public var publishPresence: Bool
    public var voicemailNumber: String

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        displayName: String = "",
        username: String = "",
        domain: String = "",
        password: String = "",
        authUser: String = "",
        registrar: String = "",
        proxy: String = "",
        transport: SIPTransport = .udp,
        registerExpires: Int = 300,
        srtp: SRTPMode = .disabled,
        dtmf: DTMFMethod = .rfc2833,
        publishPresence: Bool = false,
        voicemailNumber: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.displayName = displayName
        self.username = username
        self.domain = domain
        self.password = password
        self.authUser = authUser
        self.registrar = registrar
        self.proxy = proxy
        self.transport = transport
        self.registerExpires = registerExpires
        self.srtp = srtp
        self.dtmf = dtmf
        self.publishPresence = publishPresence
        self.voicemailNumber = voicemailNumber
    }

    /// Кожне поле читається з запасним значенням, щоб файл налаштувань,
    /// збережений старішою версією, не ламав завантаження цілком.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? "",
            username: try container.decodeIfPresent(String.self, forKey: .username) ?? "",
            domain: try container.decodeIfPresent(String.self, forKey: .domain) ?? "",
            password: try container.decodeIfPresent(String.self, forKey: .password) ?? "",
            authUser: try container.decodeIfPresent(String.self, forKey: .authUser) ?? "",
            registrar: try container.decodeIfPresent(String.self, forKey: .registrar) ?? "",
            proxy: try container.decodeIfPresent(String.self, forKey: .proxy) ?? "",
            transport: try container.decodeIfPresent(SIPTransport.self, forKey: .transport) ?? .udp,
            registerExpires: try container.decodeIfPresent(Int.self, forKey: .registerExpires) ?? 300,
            srtp: try container.decodeIfPresent(SRTPMode.self, forKey: .srtp) ?? .disabled,
            dtmf: try container.decodeIfPresent(DTMFMethod.self, forKey: .dtmf) ?? .rfc2833,
            publishPresence: try container.decodeIfPresent(Bool.self, forKey: .publishPresence) ?? false,
            voicemailNumber: try container.decodeIfPresent(String.self, forKey: .voicemailNumber) ?? ""
        )
    }

    public var isConfigured: Bool {
        !username.trimmed.isEmpty && !domain.trimmed.isEmpty
    }

    /// Акаунт, який має сенс реєструвати.
    public var isActive: Bool { isEnabled && isConfigured }

    public var effectiveAuthUser: String {
        authUser.trimmed.isEmpty ? username.trimmed : authUser.trimmed
    }

    public var effectiveRegistrar: String {
        let host = registrar.trimmed.isEmpty ? domain.trimmed : registrar.trimmed
        return host.hasPrefix("sip:") || host.hasPrefix("sips:") ? host : "\(transport == .tls ? "sips" : "sip"):\(host)"
    }

    /// AOR у форматі `"Ім\'я" <sip:user@domain;transport=tcp>`.
    public var accountURI: String {
        let scheme = transport == .tls ? "sips" : "sip"
        var uri = "\(scheme):\(username.trimmed)@\(domain.trimmed)"
        if transport != .udp { uri += ";transport=\(transport.rawValue)" }
        let name = displayName.trimmed
        return name.isEmpty ? uri : "\"\(name)\" <\(uri)>"
    }

    /// Коротка назва для списків і заголовків.
    public var title: String {
        if !displayName.trimmed.isEmpty { return displayName.trimmed }
        if isConfigured { return "\(username.trimmed)@\(domain.trimmed)" }
        return L("Новий акаунт")
    }

    /// Поля, зміна яких потребує оновлення акаунта в pjsua.
    public var registrationFingerprint: String {
        [
            String(isEnabled), displayName, username, domain, password, authUser,
            registrar, proxy, transport.rawValue, String(registerExpires),
            srtp.rawValue, String(publishPresence),
        ].joined(separator: "|")
    }
}

// MARK: - Стан рушія та реєстрації

public enum SIPEngineState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed(String)
}

public enum RegistrationState: Equatable, Sendable {
    case unregistered
    case registering
    case registered(expiresIn: Int)
    /// Сервер відповів 200 OK, але нашої адреси серед збережених прив'язок немає.
    /// Вихідні дзвінки працюють, вхідні — ні, і зовні це виглядає як «все гаразд».
    case notBound(contacts: Int)
    case failed(code: Int, reason: String)

    public var isRegistered: Bool {
        switch self {
        case .registered, .notBound: return true
        default: return false
        }
    }

    /// Стан, у якому вхідні дзвінки не дійдуть.
    public var isWarning: Bool { if case .notBound = self { return true }; return false }

    public var isFailed: Bool { if case .failed = self { return true }; return false }

    public var title: String {
        switch self {
        case .unregistered: return L("Не зареєстровано")
        case .registering: return L("Реєстрація…")
        case .registered: return L("Онлайн")
        case .notBound: return L("Онлайн, але вхідні не надходитимуть")
        case let .failed(code, reason): return L("Помилка %@: %@", String(code), reason)
        }
    }
}

// MARK: - Дзвінок

public enum SIPCallState: String, Equatable, Sendable {
    case idle, calling, incoming, early, connecting, confirmed, disconnected

    public var isActive: Bool { self != .idle && self != .disconnected }
    public var isTalking: Bool { self == .confirmed }
}

public struct SIPCallSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int32
    /// Акаунт, через який іде дзвінок; nil, поки pjsua його не повідомила.
    public var accountID: UUID?
    public var remoteURI: String
    public var remoteNumber: String
    public var remoteDisplayName: String
    public var isIncoming: Bool
    public var state: SIPCallState
    public var lastStatusCode: Int
    public var lastStatusText: String
    public var createdAt: Date
    public var connectedAt: Date?
    public var endedAt: Date?
    public var isMuted: Bool
    /// Ми вже надіслали 200 OK на вхідний виклик і чекаємо підтвердження.
    public internal(set) var isAnswering: Bool
    public var isOnHold: Bool
    public var isHeldByRemote: Bool
    public var hasAudio: Bool

    init(id: Int32, remoteURI: String, isIncoming: Bool) {
        self.id = id
        self.accountID = nil
        self.remoteURI = remoteURI
        let parsed = SIPURI.parse(remoteURI)
        self.remoteNumber = parsed.user
        self.remoteDisplayName = parsed.displayName
        self.isIncoming = isIncoming
        self.state = isIncoming ? .incoming : .calling
        self.lastStatusCode = 0
        self.lastStatusText = ""
        self.createdAt = Date()
        self.connectedAt = nil
        self.endedAt = nil
        self.isMuted = false
        self.isAnswering = false
        self.isOnHold = false
        self.isHeldByRemote = false
        self.hasAudio = false
    }

    /// Вхідний виклик, на який ще не відповіли. Перевіряти `state == .incoming`
    /// недостатньо: pjsip переводить сесію в EARLY одразу після нашого 180 Ringing,
    /// тому цей стан тримається лічені мілісекунди.
    public var isRinging: Bool {
        isIncoming && !isAnswering && (state == .incoming || state == .early)
    }

    /// Ім'я для показу: display name, інакше номер, інакше сирий URI.
    public var title: String {
        if !remoteDisplayName.isEmpty { return remoteDisplayName }
        if !remoteNumber.isEmpty { return remoteNumber }
        return remoteURI
    }

    public var subtitle: String {
        remoteDisplayName.isEmpty ? "" : remoteNumber
    }

    public var duration: TimeInterval {
        guard let connectedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(connectedAt)
    }
}

// MARK: - Події рушія

public enum SIPEvent: Sendable {
    case engineState(SIPEngineState)
    case registration(account: UUID, state: RegistrationState)
    case incomingCall(SIPCallSnapshot)
    case callUpdated(SIPCallSnapshot)
    case callEnded(SIPCallSnapshot)
    case audioDevicesChanged
    case log(level: Int, message: String)
    case failure(String)
}

// MARK: - Розбір URI

public enum SIPURI {
    /// Витягує display name та user-частину з `"Ім'я" <sip:user@host>`.
    public static func parse(_ raw: String) -> (displayName: String, user: String, host: String) {
        var value = raw.trimmed
        var displayName = ""

        if let open = value.firstIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            displayName = String(value[value.startIndex..<open]).trimmed
            value = String(value[value.index(after: open)..<close])
        }
        displayName = displayName.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))

        for prefix in ["sips:", "sip:", "tel:"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        // Відкидаємо параметри (`;transport=tcp`) та заголовки (`?subject=`).
        value = value.components(separatedBy: ";")[0].components(separatedBy: "?")[0]

        let parts = value.components(separatedBy: "@")
        let user = parts.count > 1 ? parts[0] : value
        let host = parts.count > 1 ? parts[1] : ""
        return (displayName, user, host)
    }

    /// Перетворює введене користувачем на повний SIP URI.
    public static func make(from input: String, domain: String, transport: SIPTransport) -> String? {
        let value = input.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("sip:") || value.hasPrefix("sips:") { return value }

        let scheme = transport == .tls ? "sips" : "sip"
        if value.contains("@") { return "\(scheme):\(value)" }

        let host = domain.trimmed
        guard !host.isEmpty else { return nil }
        // Прибираємо форматування набраного номера, лишаючи те, що приймає SIP.
        let allowed = CharacterSet(charactersIn: "+*#0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ._-")
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
        guard !cleaned.isEmpty else { return nil }

        var uri = "\(scheme):\(cleaned)@\(host)"
        if transport != .udp { uri += ";transport=\(transport.rawValue)" }
        return uri
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
