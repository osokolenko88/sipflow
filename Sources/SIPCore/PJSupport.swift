import Foundation
import CPJSIP

// MARK: - Рядки

/// Утримує C-рядки живими, доки pjsip не скопіює їх у свій пул.
/// pj_str_t не володіє пам'яттю, тож пул має пережити виклик pjsua_*.
final class CStringPool {
    private var allocations: [UnsafeMutablePointer<CChar>] = []

    func str(_ value: String) -> pj_str_t {
        guard let pointer = strdup(value) else { return pj_str_t() }
        allocations.append(pointer)
        return pj_str_t(ptr: pointer, slen: pj_ssize_t(strlen(pointer)))
    }

    deinit { allocations.forEach { free($0) } }
}

func pjString(_ value: pj_str_t) -> String {
    guard let pointer = value.ptr, value.slen > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(value.slen)), as: UTF8.self)
}

/// Фіксовані `char name[N]` імпортуються як кортежі — читаємо їх до першого нуля.
func cString<T>(_ tuple: T) -> String {
    var value = tuple
    return withUnsafeBytes(of: &value) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
}

func pjString(_ buffer: UnsafePointer<CChar>?, length: Int32) -> String {
    guard let buffer, length > 0 else { return "" }
    return String(decoding: UnsafeRawBufferPointer(start: buffer, count: Int(length)), as: UTF8.self)
}

// MARK: - Булеві значення pjlib

/// PJ_TRUE/PJ_FALSE імпортуються як `pj_constants_`, а поля структур мають тип `pj_bool_t`.
let pjTrue: pj_bool_t = 1
let pjFalse: pj_bool_t = 0

// MARK: - Помилки

public struct SIPError: LocalizedError, CustomStringConvertible {
    public let status: pj_status_t
    public let context: String

    public var errorDescription: String? { description }
    public var description: String {
        status == 0 ? context : "\(context): \(SIPError.message(for: status)) [\(status)]"
    }

    static func message(for status: pj_status_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let text = buffer.withUnsafeMutableBufferPointer { pointer -> String in
            let result = pj_strerror(status, pointer.baseAddress, pj_size_t(pointer.count))
            return pjString(result)
        }
        return text.isEmpty ? "unknown pjsip error" : text
    }

    /// Помилка без коду pjsip — для суто прикладних умов.
    public static func message(_ text: String) -> SIPError { SIPError(status: 0, context: text) }
}

@discardableResult
func pjTry(_ context: String, _ body: () -> pj_status_t) throws -> pj_status_t {
    let status = body()
    guard status == 0 else { throw SIPError(status: status, context: context) }
    return status
}

// MARK: - Робочий потік

/// Усі виклики pjsua мають іти з одного зареєстрованого в pjlib потоку.
/// GCD-черга для цього не годиться: вона мігрує між потоками ОС, а кожен
/// новий потік довелося б окремо реєструвати в pjlib і тримати його дескриптор живим.
final class PJWorker: NSObject {
    /// NSObject, бо блок передається через `perform(_:on:with:)`.
    private final class Box: NSObject {
        let work: () -> Void
        init(_ work: @escaping () -> Void) { self.work = work }
    }

    private var thread: Thread!
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        let thread = Thread { [ready] in
            Thread.current.name = "com.sipflow.pjsua"
            let runLoop = RunLoop.current
            runLoop.add(Port(), forMode: .default)
            ready.signal()
            while !Thread.current.isCancelled {
                runLoop.run(mode: .default, before: .distantFuture)
            }
        }
        thread.stackSize = 1 << 20
        thread.qualityOfService = .userInitiated
        thread.name = "com.sipflow.pjsua"
        self.thread = thread
        thread.start()
        ready.wait()
    }

    var isCurrent: Bool { Thread.current === thread }

    @objc private func execute(_ box: Any) { (box as? Box)?.work() }

    func async(_ work: @escaping () -> Void) {
        if isCurrent { work(); return }
        perform(#selector(execute(_:)), on: thread, with: Box(work), waitUntilDone: false)
    }

    func sync<T>(_ work: @escaping () -> T) -> T {
        if isCurrent { return work() }
        var result: T!
        let done = DispatchSemaphore(value: 0)
        perform(#selector(execute(_:)), on: thread, with: Box({
            result = work()
            done.signal()
        }), waitUntilDone: false)
        done.wait()
        return result
    }

    func syncThrowing<T>(_ work: @escaping () throws -> T) throws -> T {
        try sync { Result(catching: work) }.get()
    }

    func asyncAfter(seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.async(work)
        }
    }

    func stop() {
        thread.cancel()
        async {}  // розбудити run loop, щоб він побачив скасування
    }
}
