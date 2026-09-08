#!/usr/bin/env bash
# SIPflow — SIP-софтфон для macOS
# Copyright (C) 2026 Oleg Sokolenko
# SPDX-License-Identifier: GPL-3.0-or-later

# Пакує SIPflow.app для випуску й оновлює файл каска Homebrew.
#
# Використання:
#   ./Scripts/release.sh              # зібрати, спакувати, оновити каск
#   ./Scripts/release.sh --publish    # плюс залити реліз на GitHub і запушити тап
#
# Без --publish нічого назовні не йде: скрипт лише готує архів і файли.
#
# Каск обовʼязково має відповідати саме тому архіву, що лежить у релізі:
# кожна збірка дає новий підпис, отже новий sha256. Тому копіювання каска
# в репозиторій тапу автоматизоване — вручну про це легко забути, і тоді
# Homebrew відмовиться встановлювати через розбіжність контрольної суми.
set -euo pipefail

PUBLISH=false
[ "${1:-}" = "--publish" ] && PUBLISH=true

cd "$(dirname "$0")/.."
ROOT="$PWD"
OWNER="${GITHUB_OWNER:-osokolenko88}"
REPO="${GITHUB_REPO:-sipflow}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")
APP="$ROOT/build/SIPflow.app"
DIST="$ROOT/dist"
ARCHIVE="$DIST/SIPflow-$VERSION.zip"

echo "==> Збірка версії $VERSION"
"$ROOT/Scripts/build.sh" >/dev/null

echo "==> Перевірка залежностей"
# Застосунок має бути самодостатнім: посилання на Homebrew зробили б архів
# непрацездатним на чужій машині.
EXTERNAL=$(otool -L "$APP/Contents/MacOS/SIPflow" | tail -n +2 | awk '{print $1}' \
    | grep -v "^/System/\|^/usr/lib/" || true)
if [ -n "$EXTERNAL" ]; then
    echo "Застосунок залежить від бібліотек поза системою:" >&2
    echo "$EXTERNAL" >&2
    exit 1
fi
echo "    зовнішніх залежностей немає"

echo "==> Архів"
rm -rf "$DIST"
mkdir -p "$DIST"
# ditto, а не zip: зберігає підпис і структуру бандла.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')

echo "==> Файл каска"
CASK="$ROOT/Distribution/homebrew-sipflow/Casks/sipflow.rb"
cat > "$CASK" <<CASKEOF
cask "sipflow" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$OWNER/$REPO/releases/download/v#{version}/SIPflow-#{version}.zip"
  name "SIPflow"
  desc "SIP softphone for macOS"
  homepage "https://github.com/$OWNER/$REPO"

  depends_on macos: :sequoia
  depends_on arch: :arm64

  app "SIPflow.app"

  zap trash: [
    "~/Library/Application Support/SIPflow",
    "~/Library/Preferences/com.sipflow.app.plist",
    "~/Library/Saved Application State/com.sipflow.app.savedState",
  ]

  caveats <<~EOS
    SIPflow is signed with a self-signed certificate and is not notarized,
    so macOS quarantines it and Gatekeeper refuses the first launch.

    Clear the quarantine flag once after installing:
      xattr -dr com.apple.quarantine /Applications/SIPflow.app

    Alternatively build from source — a locally built app is never
    quarantined and needs no extra step.
  EOS
end
CASKEOF

# Репозиторій тапу — окремий, бо Homebrew вимагає префікс homebrew- у назві.
TAP="${TAP_PATH:-$ROOT/../homebrew-$REPO}"
if [ -d "$TAP/Casks" ]; then
    echo "==> Синхронізація тапу"
    cp "$CASK" "$TAP/Casks/sipflow.rb"
    if git -C "$TAP" diff --quiet -- Casks/sipflow.rb; then
        echo "    каск не змінився"
    else
        git -C "$TAP" add Casks/sipflow.rb
        git -C "$TAP" commit -q -s -m "SIPflow $VERSION" \
            -m "Контрольна сума архіву, доданого до релізу v$VERSION."
        echo "    закомічено в $(cd "$TAP" && pwd)"
    fi
else
    echo "==> Репозиторій тапу не знайдено ($TAP) — каск лишився тільки в проєкті"
fi

if [ "$PUBLISH" = true ]; then
    echo "==> Публікація релізу v$VERSION"
    if gh release view "v$VERSION" >/dev/null 2>&1; then
        gh release upload "v$VERSION" "$ARCHIVE" --clobber
        echo "    архів оновлено в наявному релізі"
    else
        gh release create "v$VERSION" "$ARCHIVE" --title "SIPflow $VERSION" --generate-notes
    fi
    if [ -d "$TAP/.git" ]; then
        git -C "$TAP" push -q origin main && echo "    тап запушено"
    fi
fi

echo
echo "версія:  $VERSION"
echo "архів:   $ARCHIVE ($(du -h "$ARCHIVE" | awk '{print $1}'))"
echo "sha256:  $SHA"
echo "каск:    ${CASK#$ROOT/}"
echo
if [ "$PUBLISH" = true ]; then
    echo "Опубліковано: https://github.com/$OWNER/$REPO/releases/tag/v$VERSION"
else
    echo "Нічого назовні не надіслано. Щоб опублікувати:"
    echo "  ./Scripts/release.sh --publish"
fi
