// swift-tools-version:6.0
import PackageDescription
import Foundation

// MicroSIP-подібний софтфон для macOS.
// pjsip встановлюється через Homebrew (`brew install pjproject`), а імена статичних
// бібліотек містять суфікс триплета (напр. `-aarch64-apple-darwin24.6.0`), тому
// список `-l` прапорців визначаємо під час обчислення маніфеста, а не хардкодимо.

let fm = FileManager.default

let pjPrefix: String = {
    for candidate in ["/opt/homebrew/opt/pjproject", "/usr/local/opt/pjproject"] {
        if fm.fileExists(atPath: candidate + "/include/pjsua-lib/pjsua.h") { return candidate }
    }
    fatalError("pjproject не знайдено. Виконайте: brew install pjproject")
}()

let pjInclude = pjPrefix + "/include"
let pjLib = pjPrefix + "/lib"

/// Порядок лінкування статичних бібліотек pjsip має значення: залежні йдуть перед базовими.
let pjLibraryOrder = [
    "pjsua", "pjsip-ua", "pjsip-simple", "pjsip", "pjmedia-codec", "pjmedia-videodev",
    "pjmedia-audiodev", "pjmedia", "pjnath", "pjlib-util", "srtp", "resample",
    "gsmcodec", "speex", "ilbccodec", "g7221codec", "yuv", "webrtc", "pj",
]

let availableLibraries: [String: String] = {
    var map: [String: String] = [:]
    for file in (try? fm.contentsOfDirectory(atPath: pjLib)) ?? [] {
        guard file.hasPrefix("lib"), file.hasSuffix(".a") else { continue }
        let full = String(file.dropFirst(3).dropLast(2))          // libpjsua-<triple>.a -> pjsua-<triple>
        // Знімаємо суфікс триплета, щоб зіставити з базовим іменем.
        for base in pjLibraryOrder where full == base || full.hasPrefix(base + "-") {
            if map[base] == nil || map[base]!.count > full.count { map[base] = full }
        }
    }
    return map
}()

let pjLinkFlags: [String] = ["-L" + pjLib] + pjLibraryOrder.compactMap { base in
    availableLibraries[base].map { "-l" + $0 }
}

let opensslPrefix: String = {
    for candidate in ["/opt/homebrew/opt/openssl@3", "/usr/local/opt/openssl@3"] {
        if fm.fileExists(atPath: candidate + "/lib") { return candidate }
    }
    return "/usr/lib"
}()

let systemFrameworks = [
    "CoreAudio", "CoreServices", "AudioUnit", "AudioToolbox", "Foundation",
    "AppKit", "AVFoundation", "CoreGraphics", "QuartzCore", "CoreVideo",
    "CoreMedia", "Metal", "MetalKit", "VideoToolbox",
].flatMap { ["-framework", $0] }

/// OpenSSL лінкуємо статично, вказуючи `.a` напряму: інакше лінкер бере `.dylib`,
/// і застосунок починає вимагати Homebrew за жорстким шляхом
/// `/opt/homebrew/opt/openssl@3/lib` — на чужому Mac він просто не запуститься.
let opensslLibraries: [String] = {
    let staticLibraries = [opensslPrefix + "/lib/libssl.a", opensslPrefix + "/lib/libcrypto.a"]
    if staticLibraries.allSatisfy({ fm.fileExists(atPath: $0) }) { return staticLibraries }
    return ["-L" + opensslPrefix + "/lib", "-lssl", "-lcrypto"]
}()

let pjLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(pjLinkFlags + opensslLibraries + systemFrameworks)
]

/// Прапорці препроцесора мають збігатися з тими, з якими зібрано сам pjsip,
/// інакше розкладка структур у заголовках розійдеться з бібліотекою.
let pjCFlags: [String] = [
    "-I" + pjInclude,
    "-DPJ_AUTOCONF=1",
    "-DPJ_IS_BIG_ENDIAN=0",
    "-DPJ_IS_LITTLE_ENDIAN=1",
]

let package = Package(
    name: "SIPflow",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "SIPflow", targets: ["SIPflow"]),
    ],
    targets: [
        .systemLibrary(name: "CPJSIP", path: "Sources/CPJSIP"),
        .target(
            name: "SIPCore",
            dependencies: ["CPJSIP"],
            swiftSettings: [.unsafeFlags(pjCFlags.flatMap { ["-Xcc", $0] })],
            linkerSettings: pjLinkerSettings
        ),
        .executableTarget(
            name: "SIPflow",
            dependencies: ["SIPCore"],
            swiftSettings: [.unsafeFlags(pjCFlags.flatMap { ["-Xcc", $0] })],
            linkerSettings: pjLinkerSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
