// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Малює іконку застосунку в Dock разом із лічильником пропущених.
///
/// Штатний `NSDockTile.badgeLabel` у цій збірці не відображається, тому плитку
/// малюємо самі: так значок гарантовано з'являється й має саме той вигляд,
/// що потрібен — червоне коло з кількістю, як у поштових клієнтів.
final class DockBadgeView: NSView {
    var count = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        guard count > 0 else { return }
        drawBadge(text: count > 99 ? "99+" : String(count))
    }

    private func drawBadge(text: String) {
        let side = bounds.width
        let height = side * 0.30
        let font = NSFont.systemFont(ofSize: height * 0.62, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = max(height, size.width + height * 0.55)

        let badge = NSRect(
            x: bounds.maxX - width - side * 0.04,
            y: bounds.maxY - height - side * 0.04,
            width: width,
            height: height
        )

        let path = NSBezierPath(roundedRect: badge, xRadius: height / 2, yRadius: height / 2)
        NSColor.systemRed.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = max(1, side * 0.012)
        path.stroke()

        let origin = NSPoint(
            x: badge.midX - size.width / 2,
            y: badge.midY - size.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
