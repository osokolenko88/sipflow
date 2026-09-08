import AppKit
import SIPCore

/// Іконка біля годинника. Її головна робота — показати пропущений виклик тому,
/// хто відходив від комп'ютера: банер до того часу вже зникне, а лічильник тут
/// і значок у Dock лишаються, доки оператор їх не перегляне.
@MainActor
final class StatusBarController: NSObject {
    var missedCalls: () -> [CallRecord] = { [] }
    var statusText: () -> String = { "" }
    var onCallBack: ((CallRecord) -> Void)?
    var onMarkSeen: (() -> Void)?
    var onOpen: (() -> Void)?

    private var item: NSStatusItem?
    private var missedCount = 0
    private var isOnline = false

    var isInstalled: Bool { item != nil }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(openMenu)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        refreshButton()
    }

    func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    func update(missedCount: Int, isOnline: Bool) {
        self.missedCount = missedCount
        self.isOnline = isOnline
        refreshButton()
    }

    @objc private func openMenu() {}

    private func refreshButton() {
        guard let button = item?.button else { return }

        let symbol: String
        if missedCount > 0 {
            symbol = "phone.arrow.down.left.fill"
        } else {
            symbol = isOnline ? "phone.fill" : "phone.down.fill"
        }

        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SIPflow")
        if missedCount > 0 {
            // Пропущений має впадати в око, тож значок і цифра — червоні.
            // Кольоровий символ вимагає вимкнути шаблонний режим, інакше macOS
            // перефарбує його під колір рядка меню.
            image = image?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
        button.imagePosition = missedCount > 0 ? .imageLeading : .imageOnly

        if missedCount > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(missedCount)",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                ]
            )
            button.toolTip = L("SIPflow — пропущених: %@", String(missedCount))
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "SIPflow — \(statusText())"
        }
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let missed = missedCalls()
        if missed.isEmpty {
            let empty = NSMenuItem(title: L("Пропущених немає"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: L("Пропущені: %@", String(missed.count)), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for record in missed.prefix(8) {
                let time = record.startedAt.formatted(date: .omitted, time: .shortened)
                let item = NSMenuItem(
                    title: "\(record.title) — \(time)",
                    action: #selector(callBack(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = record
                item.image = NSImage(systemSymbolName: "phone.arrow.up.right", accessibilityDescription: nil)
                menu.addItem(item)
            }

            menu.addItem(.separator())
            let seen = NSMenuItem(title: L("Позначити переглянутими"), action: #selector(markSeen), keyEquivalent: "")
            seen.target = self
            menu.addItem(seen)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: L("Показати SIPflow"), action: #selector(openApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: L("Вийти"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func callBack(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? CallRecord else { return }
        onCallBack?(record)
    }

    @objc private func markSeen() { onMarkSeen?() }

    @objc private func openApp() { onOpen?() }
}
