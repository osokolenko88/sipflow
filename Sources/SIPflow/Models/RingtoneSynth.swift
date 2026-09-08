// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Обчислення звуку рингтона. Винесено з програвача окремо й без залежності
/// від AVFoundation — щоб той самий код можна було прогнати офлайн і послухати
/// результат, не запускаючи застосунок.
struct RingtoneSynth {
    var ringtone: Ringtone
    var amplitude: Double = 0.30
    var volume: Double = 1
    var sampleRate: Double = 44_100

    /// Один семпл: знаходимо місце в циклі мелодії й рахуємо тон відповідного кроку.
    func sample(at index: Int64) -> Double {
        let cycle = ringtone.cycleDuration
        guard cycle > 0 else { return 0 }

        var position = (Double(index) / sampleRate).truncatingRemainder(dividingBy: cycle)
        for step in ringtone.steps {
            if position < step.duration {
                return tone(step, at: position) * amplitude * volume * ringtone.gain
            }
            position -= step.duration
            if position < step.gap { return 0 }
            position -= step.gap
        }
        return 0
    }

    private func tone(_ step: Ringtone.Step, at time: Double) -> Double {
        let envelope = amplitudeEnvelope(step, at: time)
        var value = waveform(step, at: time)

        if let tremolo = step.tremolo {
            value *= 0.55 + 0.45 * sin(2 * .pi * tremolo * time)
        }
        return value * envelope
    }

    private func amplitudeEnvelope(_ step: Ringtone.Step, at time: Double) -> Double {
        switch step.envelope {
        case .flat:
            // М'які фронти прибирають клацання на межах тону.
            let fade = min(0.02, step.duration / 4)
            return max(0, min(1, min(time / fade, (step.duration - time) / fade)))
        case .decay:
            return exp(-3.0 * time / step.duration)
        case .soft:
            return sin(.pi * time / step.duration)
        }
    }

    private func waveform(_ step: Ringtone.Step, at time: Double) -> Double {
        // Трель: тон стрибає між двома частотами — класична ознака дзвінка.
        if let warble = step.warble, step.frequencies.count >= 2 {
            let half = 1 / (2 * warble)
            let index = Int(time / half) % 2
            return partials(of: step.frequencies[index], timbre: step.timbre, at: time)
        }

        // Ковзання: частота повзе від першої до кінцевої, тому фазу інтегруємо.
        if let glide = step.glide, let start = step.frequencies.first {
            let rate = (glide - start) / step.duration
            let phase = 2 * .pi * (start * time + rate * time * time / 2)
            return sin(phase)
        }

        var sum = 0.0
        var weights = 0.0
        for (order, frequency) in step.frequencies.enumerated() {
            let weight = 1 / Double(order + 1)
            sum += weight * partials(of: frequency, timbre: step.timbre, at: time)
            weights += weight
        }
        return weights > 0 ? sum / weights : 0
    }

    /// Призвуки понад основним тоном. Саме вони відрізняють «пік» від дзвінка.
    private func partials(of frequency: Double, timbre: Ringtone.Timbre, at time: Double) -> Double {
        switch timbre {
        case .pure:
            return sin(2 * .pi * frequency * time)
        case .rich:
            // Непарні гармоніки, що спадають, — наближення до прямокутної хвилі.
            var sum = 0.0
            var weights = 0.0
            for order in stride(from: 1, through: 7, by: 2) {
                let weight = 1 / Double(order)
                sum += weight * sin(2 * .pi * frequency * Double(order) * time)
                weights += weight
            }
            return sum / weights
        case .bell:
            // Негармонійні співвідношення справжнього дзвона; вищі призвуки
            // згасають швидше за основний тон.
            let ratios = [1.0, 2.76, 5.40, 8.93]
            let weights = [1.0, 0.6, 0.38, 0.22]
            var sum = 0.0
            for (index, ratio) in ratios.enumerated() {
                let decay = exp(-Double(index + 1) * 1.6 * time)
                sum += weights[index] * decay * sin(2 * .pi * frequency * ratio * time)
            }
            return sum / weights.reduce(0, +)
        }
    }
}
