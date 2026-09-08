#!/usr/bin/env bash
# SIPflow — SIP-софтфон для macOS
# Copyright (C) 2026 Oleg Sokolenko
# SPDX-License-Identifier: GPL-3.0-or-later

# Пакує SIPflow.app для випуску й оновлює файл каска Homebrew.
#
# Використання:
#   GITHUB_OWNER=ваш-логін ./Scripts/release.sh
#
# На виході: dist/SIPflow-<версія>.zip, його sha256 і готовий Casks/sipflow.rb.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OWNER="${GITHUB_OWNER:-OWNER}"
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

  depends_on macos: ">= :sequoia"
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

echo
echo "версія:  $VERSION"
echo "архів:   $ARCHIVE ($(du -h "$ARCHIVE" | awk '{print $1}'))"
echo "sha256:  $SHA"
echo "каск:    ${CASK#$ROOT/}"
echo
echo "Далі:"
echo "  1. Створіть реліз v$VERSION на GitHub і додайте до нього архів."
echo "  2. Скопіюйте теку Distribution/homebrew-sipflow у репозиторій"
echo "     github.com/$OWNER/homebrew-$REPO і запуште."
echo "  3. Встановлення: brew tap $OWNER/$REPO && brew install --cask sipflow"
echo "     Далі один раз: xattr -dr com.apple.quarantine /Applications/SIPflow.app"
