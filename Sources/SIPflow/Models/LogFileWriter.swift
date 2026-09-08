// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Пише лог pjsip у файл. Власний записувач, а не `pjsua_logging_config.log_filename`,
/// бо pjsua відкриває файл без обрізання і не робить flush — у результаті в ньому
/// перемішуються записи різних запусків, і розбирати такий лог неможливо.
final class LogFileWriter {
    private let url: URL
    private let queue = DispatchQueue(label: "com.sipflow.log")
    private var handle: FileHandle?
    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(url: URL) {
        self.url = url
    }

    var isOpen: Bool { handle != nil }

    /// Починає новий файл: кожен запуск має власний, чистий лог.
    func open() {
        queue.async { [self] in
            guard handle == nil else { return }
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            write(line: "=== SIPflow \(AppInfo.version) — \(Date().formatted()) ===")
        }
    }

    func close() {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
        }
    }

    func append(level: Int, message: String) {
        queue.async { [self] in
            guard handle != nil else { return }
            write(line: "\(formatter.string(from: Date())) [\(level)] \(message)")
        }
    }

    /// Виклики лише з `queue`.
    private func write(line: String) {
        guard let handle, let data = (line + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }
}
