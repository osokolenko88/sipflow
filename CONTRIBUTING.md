# Contributing to SIPflow

***English** · [Українська](CONTRIBUTING.uk.md)*

Thanks for looking. This is a small project, so the rules are short.

## Before you start: the registration limit

Most SIP providers cap how many simultaneous registrations one account may
have — often three. **Every launch of the app occupies one slot for about five
minutes, even if you kill the process.** Rebuild and relaunch a few times in a
row and your account stops registering with `403 Forbidden`, or the server
returns `200 OK` while quietly not storing your binding at all.

The app detects both states and retries on its own, but during development it
is worth restarting sparingly. If the account suddenly goes offline after a
rebuild, check in this order:

1. A pending Keychain prompt (look for a `SecurityAgent` window)
2. The registration limit — `sipflow.log` will show it
3. Only then suspect the SIP code

## Building

```sh
brew install pjproject
./Scripts/make-signing-identity.sh   # once, avoids repeated Keychain prompts
./Scripts/build.sh
```

`swift build` alone is enough for compiling; the script is only needed to
assemble the `.app` bundle. See the [README](README.md) for details.

## Signing off your commits

Every commit needs a `Signed-off-by` line — the
[Developer Certificate of Origin](https://developercertificate.org). It is a
statement that you wrote the code, or otherwise have the right to submit it
under the project's licence. It transfers nothing to anyone:

```sh
git commit -s -m "Your message"
```

Please note that the project is **GPL-3.0-or-later** and cannot change licence
easily: each contributor keeps the copyright to their own lines, so relicensing
would require everyone's agreement. Contribute only code you are happy to see
stay under the GPL.

## What is most welcome

- **New interface languages.** The infrastructure is in place: copy
  `Resources/uk.lproj/Localizable.strings`, translate the values, and add the
  code to `CFBundleLocalizations` in `Resources/Info.plist`. Keys are the
  Ukrainian strings themselves.
- **Ringtones.** Each is a sequence of tones with an envelope in
  `Sources/SIPflow/Models/Ringtone.swift` — no audio files involved.
- **Bug fixes**, especially ones you can reproduce with a log.

Larger changes — a different SIP stack, video, BLF/presence — are worth opening
an issue about first, so the work does not go to waste.

## Code style

- Comments explain **why**, not what. If a line needs a comment to say what it
  does, the line usually wants rewriting instead.
- The codebase carries a fair amount of hard-won knowledge about macOS and
  pjsip behaving unexpectedly. When you work around such a thing, say so in a
  comment — the next person will not have to rediscover it.
- Match the surrounding code rather than introducing a new style.

## Reporting a bug

Enable Settings → Advanced → “Write SIP log to file”, set the log level to 4,
reproduce the problem, and attach the relevant part of
`~/Library/Application Support/SIPflow/sipflow.log`.

**Remove anything private first** — the log contains full SIP messages,
including your number, your provider and your contacts.
