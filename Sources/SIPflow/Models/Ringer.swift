// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Foundation

/// Синтезує рингтон за його описом. Звук рахується на льоту, семпл за семплом,
/// тому жодних аудіофайлів не потрібно, а гучність і вибір мелодії міняються
/// без перезавантаження чогось.
final class Ringer {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44_100

    private var frame: Int64 = 0
    private var synth = RingtoneSynth(ringtone: .fallback)
    private let lock = NSLock()

    /// Ідентифікатор мелодії, що звучить зараз; nil — тиша.
    private(set) var playing: String?

    /// Повторний виклик із тією самою мелодією нічого не перезапускає.
    func start(_ ringtone: Ringtone, volume: Double, amplitude: Double = 0.30) {
        guard playing != ringtone.id else { return }
        stop()

        lock.withLock {
            self.synth = RingtoneSynth(
                ringtone: ringtone,
                amplitude: amplitude,
                volume: max(0, min(volume, 1)),
                sampleRate: sampleRate
            )
            self.frame = 0
        }
        playing = ringtone.id

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Стан читаємо один раз на буфер: блокування на кожному семплі
            // в реальночасовому потоці аудіо неприпустиме.
            let (synth, start) = self.lock.withLock { (self.synth, self.frame) }
            for index in 0..<Int(frameCount) {
                let value = Float(synth.sample(at: start &+ Int64(index)))
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[index] = value
                }
            }
            self.lock.withLock { self.frame &+= Int64(frameCount) }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node

        do {
            try engine.start()
        } catch {
            cleanUp()
            playing = nil
        }
    }

    func stop() {
        guard sourceNode != nil else {
            playing = nil
            return
        }
        engine.stop()
        cleanUp()
        playing = nil
    }

    private func cleanUp() {
        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
    }

}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
