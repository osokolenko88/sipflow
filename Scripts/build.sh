#!/usr/bin/env bash
# SIPflow — SIP-софтфон для macOS
# Copyright (C) 2026 Oleg Sokolenko
# SPDX-License-Identifier: GPL-3.0-or-later

# Збирає SIPflow.app: SwiftPM-бінарник + bundle + іконка + ad-hoc підпис.
# Повний Xcode не потрібен, достатньо Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/SIPflow.app"

if ! command -v brew >/dev/null || [ ! -d "$(brew --prefix)/opt/pjproject" ]; then
    echo "Потрібен pjsip: brew install pjproject" >&2
    exit 1
fi

echo "==> Компіляція ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$ROOT/.build/$CONFIG/SIPflow"

echo "==> Складання bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/SIPflow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Ліцензії сторонніх компонентів мають їхати разом із застосунком.
cp "$ROOT/Resources/ACKNOWLEDGEMENTS.md" "$APP/Contents/Resources/"
# Переклади: без них застосунок лишиться україномовним на будь-якій системі.
for lproj in "$ROOT"/Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
done
cp "$ROOT/Resources/icon/PHOSPHOR-LICENSE.txt" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Іконка"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET/icon_1024.png"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$ICONSET/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done
rm "$ICONSET/icon_1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "==> Підпис"
# Сталий сертифікат дає незмінний підпис між збірками, тому macOS не скидає
# ні дозвіл на мікрофон, ні доступ до пароля в Keychain. Якщо його немає,
# лишається ad-hoc — застосунок працюватиме, але дозволи питатимуться щоразу.
# Порядок пошуку: змінна середовища, потім сертифікат із очікуваною назвою,
# потім будь-який локальний сертифікат для підпису. `SIGNING_IDENTITY=-`
# примусово дає ad-hoc.
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    if security find-identity -v -p codesigning | grep -qF "SIPflow Local Signing"; then
        IDENTITY="SIPflow Local Signing"
    else
        IDENTITY=$(security find-identity -v -p codesigning \
            | sed -n 's/.*"\(.*Local Signing\)".*/\1/p' | head -1)
    fi
fi

if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    IDENTITY="-"
    echo "    підпис ad-hoc — він змінюється щозбірки, тому macOS щоразу"
    echo "    перепитуватиме доступ до мікрофона й пароля в Keychain."
    echo "    Сталий сертифікат: ./Scripts/make-signing-identity.sh"
else
    echo "    сертифікат: $IDENTITY"
fi

codesign --force --deep --sign "$IDENTITY" \
    --entitlements "$ROOT/Resources/SIPflow.entitlements" \
    "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --verbose=1 "$APP"

echo
echo "Готово: $APP"
echo "Запуск:  open '$APP'"
