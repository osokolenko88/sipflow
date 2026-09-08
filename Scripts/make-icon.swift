#!/usr/bin/env swift
// Малює іконку застосунку і складає AppIcon.icns.
//
// Гліф — `phone-incoming-fill` із набору Phosphor Icons (MIT), його вихідний SVG
// і текст ліцензії лежать поруч у Resources/icon. SF Symbols тут навмисно не
// використовуються: ліцензія Apple дозволяє їх в інтерфейсі застосунку, але
// забороняє в іконках, логотипах і торгових марках.
import AppKit
import Foundation

let size: CGFloat = 1024
let root = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let glyphURL = root.appendingPathComponent("Resources/icon/phone-incoming-fill.png")

guard let glyph = NSImage(contentsOf: glyphURL) else {
    FileHandle.standardError.write(Data("Не знайдено гліф: \(glyphURL.path)\n".utf8))
    exit(1)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Підкладка — заокруглений квадрат із градієнтом.
let plate = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.06, dy: size * 0.06)
let squircle = NSBezierPath(roundedRect: plate, xRadius: size * 0.2, yRadius: size * 0.2)
NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.56, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.29, blue: 0.74, alpha: 1),
])!.draw(in: squircle, angle: -90)

// Гліф чорний на прозорому — перефарбовуємо в білий через маску.
let white = NSImage(size: glyph.size)
white.lockFocus()
NSColor.white.set()
NSRect(origin: .zero, size: glyph.size).fill()
glyph.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
white.unlockFocus()

let side = plate.width * 0.64
let target = NSRect(
    x: plate.midX - side / 2,
    y: plate.midY - side / 2,
    width: side,
    height: side
)
white.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Не вдалося відрендерити іконку\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try png.write(to: URL(fileURLWithPath: output))
