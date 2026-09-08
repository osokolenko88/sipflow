// SIPflow — SIP-софтфон для macOS
// Copyright (C) 2026 Oleg Sokolenko
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SIPCore

/// Рингтон описується як послідовність тонів, а не як аудіофайл: застосунок
/// синтезує звук сам. Так немає ні ліцензійних питань до чужих записів,
/// ні мегабайтів у репозиторії, а гучність і каденція лишаються керованими.
struct Ringtone: Identifiable, Hashable {
    /// Огинаюча гучності всередині одного тону.
    enum Envelope: Hashable {
        /// Рівний тон — класичні телефонні гудки.
        case flat
        /// Різка атака й спад — щипок, дзвіночок.
        case decay
        /// М'які наростання й затухання.
        case soft
    }

    /// Тембр визначає, наскільки «телефонним» звучить тон. Чиста синусоїда
    /// схожа на сигнал сповіщення; насичений і дзвоновий тембри дають ту саму
    /// різкість і тривалість, що в справжнього дзвінка.
    enum Timbre: Hashable {
        /// Синусоїда.
        case pure
        /// Непарні гармоніки — теплий, «язичковий» звук електричного дзвінка.
        case rich
        /// Негармонійні призвуки справжнього дзвона.
        case bell
    }

    struct Step: Hashable {
        var frequencies: [Double]
        var duration: Double
        var gap: Double = 0
        var envelope: Envelope = .flat
        var timbre: Timbre = .pure
        /// Частота тремоло в герцах — «деренчання» старих апаратів.
        var tremolo: Double?
        /// Перемикання між першими двома частотами, разів на секунду.
        /// Саме ця трель робить звук упізнаваним телефонним дзвінком.
        var warble: Double?
        /// Кінцева частота ковзання — тон плавно повзе від першої до неї.
        var glide: Double?
    }

    let id: String
    let name: String
    let steps: [Step]
    /// Тиша перед наступним повтором.
    let pause: Double
    /// Вирівнювання гучності між мелодіями: дзвонові тембри з довгим затуханням
    /// звучать помітно тихіше за рівні тони, хоча пік у них однаковий.
    var gain: Double = 1

    var cycleDuration: Double {
        steps.reduce(0) { $0 + $1.duration + $1.gap } + pause
    }
}

extension Ringtone {
    /// Кожна мелодія — це сплеск на 1,5–2,5 секунди й пауза. Саме тривалість
    /// і насиченість відрізняють дзвінок від короткого сигналу сповіщення.
    static let all: [Ringtone] = [
        Ringtone(
            id: "classic", name: L("Класичний"),
            steps: [Step(frequencies: [425], duration: 1.0, timbre: .rich)],
            pause: 3.0, gain: 1.18
        ),
        Ringtone(
            id: "american", name: L("Американський"),
            steps: [Step(frequencies: [440, 480], duration: 2.0, timbre: .rich)],
            pause: 3.5, gain: 1.30
        ),
        Ringtone(
            id: "british", name: L("Британський"),
            steps: [
                Step(frequencies: [400, 450], duration: 0.4, gap: 0.2, timbre: .rich),
                Step(frequencies: [400, 450], duration: 0.4, timbre: .rich),
            ],
            pause: 2.0, gain: 1.56
        ),
        Ringtone(
            id: "japanese", name: L("Японський"),
            steps: [Step(frequencies: [400], duration: 1.0, timbre: .rich, tremolo: 16)],
            pause: 2.0, gain: 1.61
        ),
        Ringtone(
            id: "vintage", name: L("Старий апарат"),
            steps: [Step(frequencies: [800, 1000], duration: 1.4, timbre: .rich, warble: 20)],
            pause: 2.0, gain: 0.92
        ),
        Ringtone(
            id: "trill", name: L("Трель"),
            steps: [Step(frequencies: [700, 900], duration: 1.6, timbre: .rich, warble: 10)],
            pause: 2.2, gain: 0.90
        ),
        Ringtone(
            id: "office", name: L("Офісний"),
            steps: [
                Step(frequencies: [1400, 1800], duration: 0.5, gap: 0.15, timbre: .rich),
                Step(frequencies: [1400, 1800], duration: 0.5, gap: 0.15, timbre: .rich),
                Step(frequencies: [1400, 1800], duration: 0.5, timbre: .rich),
            ],
            pause: 2.0, gain: 1.28
        ),
        Ringtone(
            id: "rising", name: L("Наростання"),
            steps: [
                Step(frequencies: [500], duration: 0.7, gap: 0.15, glide: 1100),
                Step(frequencies: [500], duration: 0.7, gap: 0.15, glide: 1100),
                Step(frequencies: [500], duration: 0.7, glide: 1100),
            ],
            pause: 2.0, gain: 0.55
        ),
        Ringtone(
            id: "chimes", name: L("Куранти"),
            steps: [
                Step(frequencies: [784], duration: 0.7, envelope: .decay, timbre: .bell),
                Step(frequencies: [659], duration: 0.7, envelope: .decay, timbre: .bell),
                Step(frequencies: [587], duration: 0.7, envelope: .decay, timbre: .bell),
                Step(frequencies: [440], duration: 1.1, envelope: .decay, timbre: .bell),
            ],
            pause: 2.0, gain: 2.60
        ),
        Ringtone(
            id: "marimba", name: L("Маримба"),
            steps: [
                Step(frequencies: [523], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [659], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [784], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [659], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [523], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [659], duration: 0.28, envelope: .decay, timbre: .rich),
                Step(frequencies: [784], duration: 0.5, envelope: .decay, timbre: .rich),
            ],
            pause: 1.6, gain: 1.88
        ),
        Ringtone(
            id: "arpeggio", name: L("Арпеджіо"),
            steps: [
                Step(frequencies: [523], duration: 0.26, envelope: .decay, timbre: .bell),
                Step(frequencies: [659], duration: 0.26, envelope: .decay, timbre: .bell),
                Step(frequencies: [784], duration: 0.26, envelope: .decay, timbre: .bell),
                Step(frequencies: [1047], duration: 0.26, envelope: .decay, timbre: .bell),
                Step(frequencies: [784], duration: 0.26, envelope: .decay, timbre: .bell),
                Step(frequencies: [659], duration: 0.5, envelope: .decay, timbre: .bell),
            ],
            pause: 1.8, gain: 2.56
        ),
        Ringtone(
            id: "melody", name: L("Мелодія"),
            steps: [
                Step(frequencies: [659], duration: 0.3, envelope: .decay, timbre: .bell),
                Step(frequencies: [784], duration: 0.3, envelope: .decay, timbre: .bell),
                Step(frequencies: [880], duration: 0.45, envelope: .decay, timbre: .bell),
                Step(frequencies: [784], duration: 0.3, envelope: .decay, timbre: .bell),
                Step(frequencies: [659], duration: 0.3, envelope: .decay, timbre: .bell),
                Step(frequencies: [587], duration: 0.3, envelope: .decay, timbre: .bell),
                Step(frequencies: [659], duration: 0.6, envelope: .decay, timbre: .bell),
            ],
            pause: 1.6, gain: 2.36
        ),
        Ringtone(
            id: "calm", name: L("Спокійний"),
            steps: [
                Step(frequencies: [440, 554], duration: 1.2, gap: 0.1, envelope: .soft, timbre: .rich),
                Step(frequencies: [523, 659], duration: 1.2, envelope: .soft, timbre: .rich),
            ],
            pause: 2.5, gain: 1.59
        ),
        Ringtone(
            id: "digital", name: L("Цифровий"),
            steps: [
                Step(frequencies: [1046, 1318], duration: 0.25, gap: 0.12, timbre: .rich),
                Step(frequencies: [1046, 1318], duration: 0.25, gap: 0.12, timbre: .rich),
                Step(frequencies: [1318, 1568], duration: 0.4, timbre: .rich),
            ],
            pause: 1.8, gain: 1.48
        ),
        Ringtone(
            id: "urgent", name: L("Тривога"),
            steps: [
                Step(frequencies: [900, 1200], duration: 0.5, gap: 0.1, timbre: .rich, warble: 8),
                Step(frequencies: [900, 1200], duration: 0.5, gap: 0.1, timbre: .rich, warble: 8),
                Step(frequencies: [900, 1200], duration: 0.5, timbre: .rich, warble: 8),
            ],
            pause: 1.2, gain: 0.83
        ),
    ]

    static let fallback = all[0]

    static func named(_ id: String) -> Ringtone {
        all.first { $0.id == id } ?? fallback
    }

    /// Зворотний гудок вихідного виклику — не налаштовується, це службовий сигнал.
    static let ringback = Ringtone(
        id: "ringback", name: L("Зворотний гудок"),
        steps: [Step(frequencies: [425], duration: 1.0)], pause: 4.0
    )
}
