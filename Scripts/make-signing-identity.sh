#!/usr/bin/env bash
# Створює самопідписаний сертифікат для підпису SIPflow.
#
# Навіщо: ad-hoc підпис змінюється при кожній перезбірці, тому macOS вважає
# нову збірку іншою програмою і щоразу перепитує доступ до пароля в Keychain.
# Зі сталим сертифікатом підпис лишається незмінним, і запит з'являється один раз.
set -euo pipefail

NAME="${SIGNING_IDENTITY:-SIPflow Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL="$(brew --prefix openssl@3 2>/dev/null)/bin/openssl"
[ -x "$OPENSSL" ] || OPENSSL=/usr/bin/openssl

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
    echo "Сертифікат «$NAME» вже існує — нічого робити не потрібно."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Генерація ключа та сертифіката"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME/O=SIPflow/C=UA" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# macOS не приймає PKCS#8 (`BEGIN PRIVATE KEY`), який пише OpenSSL 3,
# і не імпортує PKCS12 з його типовими алгоритмами — тож віддаємо ключ
# і сертифікат окремо, у традиційному форматі PKCS#1.
"$OPENSSL" rsa -in "$WORK/key.pem" -out "$WORK/key-rsa.pem" -traditional >/dev/null 2>&1

echo "==> Імпорт у в'язку login"
security import "$WORK/key-rsa.pem" -k "$KEYCHAIN" -t priv -f openssl -T /usr/bin/codesign >/dev/null
security import "$WORK/cert.pem" -k "$KEYCHAIN" -t cert -f openssl -T /usr/bin/codesign >/dev/null

echo "==> Позначення сертифіката довіреним для підпису коду"
echo "    (macOS попросить пароль вашого облікового запису)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | grep -F "$NAME" || true
echo "Готово. Наступні збірки підписуватимуться цим сертифікатом."
