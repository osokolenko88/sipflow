# SIPflow

***English** · [Українська](README.uk.md)*

A SIP softphone for macOS with an iPhone-style dialler — round keys with letters,
a large green call button, and a Recents list that shows missed calls in red.
Built on [pjsip](https://www.pjsip.org/), the same stack MicroSIP uses, with a
SwiftUI interface.

## Features

- Multiple SIP accounts at once: add, remove, enable/disable, pick the default for outgoing calls
- Registration over UDP / TCP / TLS, with separate auth ID, registrar, outbound proxy, STUN and ICE
- Incoming and outgoing calls, several calls at a time
- In-call control: mute, hold, DTMF, blind and attended transfer
- Phone book with search, favourites, click-to-call and one-click adding from history.
  Names from the book are substituted into the call card, history and notifications
- Call history (incoming / outgoing / missed) with redial
- Missed calls stay visible after you step away: a menu bar icon with a counter,
  a Dock badge, and a notification with a “Call back” action
- Microphone and speaker selection, echo cancellation and codec priorities
- SRTP (optional or mandatory), Do Not Disturb, auto answer
- A floating incoming-call panel with Answer / Decline when the window is
  minimised or the app is in the background
- A live pjsip log window for diagnostics

## Installation

### Building from source — the primary route

A locally built app **is never quarantined** and launches without any Gatekeeper
dialogs. You need the Command Line Tools; the full Xcode is not required:

```sh
brew install pjproject
git clone https://github.com/osokolenko88/sipflow && cd sipflow
./Scripts/make-signing-identity.sh   # once
./Scripts/build.sh
open build/SIPflow.app
```

`make-signing-identity.sh` creates a self-signed “SIPflow Local Signing”
certificate in your login keychain. The step is optional but recommended:
without it the build is signed ad-hoc, and such a signature changes on every
rebuild — macOS then treats each build as a different program and keeps asking
again for microphone access and for the Keychain password. With a stable
certificate the designated requirement stays put:

```
designated => identifier "com.sipflow.app" and certificate root = H"…"
```

### Homebrew — more convenient, with one manual step

```sh
brew tap osokolenko88/sipflow
brew install --cask sipflow
xattr -dr com.apple.quarantine /Applications/SIPflow.app
```

The third line is needed once. The app is signed with a self-signed certificate
and is not notarized, so Gatekeeper refuses a downloaded archive. The
`--no-quarantine` flag is gone — Homebrew 6 removed it.

Only a Developer ID with notarization can remove this step, and that means paid
Apple Developer Program membership. For an open-source project, building from
source is both cheaper and cleaner.

### Requirements

- macOS 15 or newer
- **Apple Silicon only**: Homebrew ships pjproject as `arm64`. Intel support
  would require building pjsip from source for x86_64 and producing a universal
  binary.

## Licence

**GPL-3.0-or-later** — see [`LICENSE`](LICENSE).
Copyright (C) 2026 Oleg Sokolenko.

Every source file carries a short `SPDX-License-Identifier` tag, so the licence
travels with the file even if it is copied out of the project.

Version 3 is not an arbitrary pick: PJSIP allows “GPLv2 or later”, but OpenSSL 3
is under Apache 2.0, which is incompatible with GPLv2. Since the app links both,
GPLv3 is the only consistent option. Details in
[`Resources/ACKNOWLEDGEMENTS.md`](Resources/ACKNOWLEDGEMENTS.md).

## Releasing

```sh
./Scripts/release.sh
```

The script builds the app, **verifies that it does not depend on libraries
outside the system ones** (otherwise the archive would not run on someone else's
machine), packages the `.app` with `ditto` so the signature survives, computes
the sha256 and refreshes the ready-made cask in
[`Distribution/homebrew-sipflow`](Distribution/homebrew-sipflow).

OpenSSL is linked statically precisely for that reason: otherwise the app would
demand Homebrew at the hard-coded path `/opt/homebrew/opt/openssl@3`.

The official `homebrew-cask` will not take a project like this yet: a
self-submission there needs 90 forks, 90 watchers and 225 stars. A personal tap
works immediately with no requirements at all.

### Icon

Assembled by [`Scripts/make-icon.swift`](Scripts/make-icon.swift): a gradient
plate plus the `phone-incoming-fill` glyph from
[Phosphor Icons](https://phosphoricons.com) (MIT). The source SVG, the rendered
PNG and the licence text live in `Resources/icon`, so the build needs no SVG
renderer.

SF Symbols are deliberately not used in the icon: Apple's licence permits them
in application interfaces but forbids them in icons, logos and trademarks.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CPJSIP` | Bridging module for the pjsip headers |
| `Sources/SIPCore` | Wrapper over pjsua: accounts, calls, audio devices, codecs |
| `Sources/SIPflow` | The app: SwiftUI interface, settings, history |
| `Scripts` | Bundle assembly and icon generation |

Every pjsua call goes through a single dedicated thread (`PJWorker`) registered
with pjlib; events come back to the interface on the main queue.

## Diagnostics

Settings → Advanced → “Write SIP log to file” records the full packet exchange
into `sipflow.log` next to the settings (log level 4 or higher required). The
same stream is visible in the Log tab. The app writes the file itself rather
than using pjsua's writer: that one opens the file without truncating and never
flushes, so records from different runs end up mixed together.

## Application data

`~/Library/Application Support/SIPflow/` — `settings.json` and `history.json`.
The SIP password is kept in the Keychain, not in the settings file.

## Interface language

The app follows the system language: Ukrainian, English, Russian. The
translation keys are the Ukrainian strings themselves, which keeps the code
readable and means a missing translation shows meaningful text rather than an
identifier.

Translations live in `Resources/{uk,en,ru}.lproj/Localizable.strings` and are
copied into the bundle at build time. SwiftUI only localises literals passed
directly (`Text("Набір")`), so all text goes through `L()` from
[`Localization.swift`](Sources/SIPCore/Localization.swift) — otherwise strings
coming from the models would stay untranslated.

To try another language without changing system settings:

```sh
open build/SIPflow.app --args -AppleLanguages '("en")'
```

## Ringtones

Fifteen tunes that the app **synthesises itself** — from classic telephone
cadences of different countries to marimba, bell and arpeggio. Each is described
as a sequence of tones with an envelope
([`Ringtone.swift`](Sources/SIPflow/Models/Ringtone.swift)), and the sound is
computed sample by sample
([`RingtoneSynth.swift`](Sources/SIPflow/Models/RingtoneSynth.swift)).

This avoids both licensing questions about someone else's recordings and
megabytes of audio in the repository. The synthesis is kept separate from the
player and free of AVFoundation, so the same code can be run offline and checked.

Selection and preview: Settings → Audio → Ringtone.

## Appearance

Settings → Advanced → Interface:

- **Colour** — eleven accent colours (blue, cyan, teal, green, yellow, orange,
  red, pink, purple, indigo, graphite). Switches live, without a restart.
  Semantic colours never change: green “answer”, red “decline” and red for
  missed calls carry meaning, not styling.
- **Appearance** — System / Light / Dark. Applied at the application level
  (`NSApp.appearance`), so it covers the settings window and the call panel too.

The dialler field is an `NSTextField` with a transparent caret
([`CursorlessField`](Sources/SIPflow/Views/CursorlessField.swift)) rather than a
label with a custom key handler: this removes the blinking bar above the keypad
while keeping everything expected of a field — typing, pasting, undo, selection.

The call button behaves like a phone's: it dials when the field has a number and
inserts the last dialled number when it is empty.

## Multiple accounts

Accounts are added and removed on the live pjsip stack: adding a second account
does not drop active calls on the first. Removing one unregisters it
(`REGISTER … Expires: 0`) and deletes its password from the Keychain. The stack
is restarted only when global parameters change — port, STUN/ICE, sample rate,
echo cancellation or log level.

One transport is created per type and shared between accounts. If a fixed local
port is configured, TLS listens on the next one, because it cannot share a port
with TCP.

## The floating incoming-call panel

When the window is minimised, closed or the app is in the background, an
incoming call appears as the app's own panel in the top-right corner — with the
caller's name and Answer / Decline buttons. It floats above other windows, never
steals focus from whatever the operator is working in, and disappears as soon as
the call is answered or ends.

It is deliberately an app window rather than a system banner. System
notifications proved unreliable for calls: macOS accepts them through the API
without any error and may still not put them on screen — because of a Focus
mode, the alert style or a revoked permission. For an incoming call such a
silent failure is unacceptable, so the panel depends on neither permissions nor
Do Not Disturb.

System notifications remain where they fit — for missed calls.

The foreground state is captured before the app starts drawing attention to
itself: `NSApp.requestUserAttention` makes the app active, and a check performed
after it wrongly concluded that the window was already on screen.

## When the client is “online” but nothing comes in

Two states look perfectly healthy from the outside while incoming calls never
arrive. The app now recognises and reports both:

- **The server did not store our binding.** A `200 OK` comes back for the
  REGISTER, but our address is not among the stored Contacts — which happens
  when the account's limit of simultaneous registrations is used up by sessions
  that have not expired yet. The app compares its own address (the NAT port from
  `received`/`rport` in the Via) against the list in the response, reports
  “Online, but incoming calls will not arrive”, and retries every 30 seconds
  until a slot frees up.
- **Registration was rejected**, for example with `403 Forbidden` for the same
  reason. pjsua's default behaviour is to stay silent for five minutes before
  trying again; here the first retry goes out after 8 seconds, then every 30.

Every launch of the app occupies one registration on the server for about five
minutes, even if the process was killed. Frequent restarts during development
can exhaust the provider's limit.

## Missed calls

A banner disappears on its own, so whoever stepped away from the computer will
not see it. Three independent channels report a missed call instead:

1. **The menu bar icon** next to the clock — always present, shows the
   registration state, and turns red with a counter when calls are missed. Its
   menu lists the missed calls with times, dials one on click, and offers
   “Mark as seen”.
2. **The Dock badge** — a red circle with the count, like unread mail. The Dock
   tile is drawn by our own code (`DockBadgeView`): the stock
   `NSDockTile.badgeLabel` displayed nothing in this build although it accepted
   the value without error. Visible whenever the Dock is on screen — with
   auto-hide enabled, the Dock has to be revealed first.
3. **A missed-call notification** with a “Call back” action. Unlike the incoming
   banner, it stays in Notification Center.

The first two channels do not depend on notification permissions. The counter
clears when the operator opens the History tab or chooses “Mark as seen”.

Numbers are matched by their last nine digits, so `380955158408`, `0955158408`
and `+38 (095) 515-84-08` are the same contact.

## Current limitations

- No BLF/presence and no SIP chat
- No Opus codec: the Homebrew build of the library ships without it
- Without a stable certificate the ad-hoc signature changes on every rebuild,
  and macOS asks again for microphone access and the Keychain password. Until
  the prompt is answered the account does not register — the header says so
  explicitly and the indicator turns red
