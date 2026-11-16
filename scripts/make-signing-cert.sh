#!/bin/bash
# Creates a self-signed code-signing certificate in your login keychain.
# Signing every build with the same certificate lets macOS keep the app's Accessibility and
# Input Monitoring permissions across rebuilds (an ad-hoc signature changes on every build).
# The certificate only signs this app; it is not trusted by the system for anything else.
set -euo pipefail

NAME="${1:-Wacom Bamboo Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "Certificate \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# The system LibreSSL writes a PKCS#12 that `security import` accepts; OpenSSL 3 from Homebrew does not.
OPENSSL=/usr/bin/openssl
PASS="$($OPENSSL rand -hex 16)"

cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
$OPENSSL pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "Created certificate \"$NAME\" in the login keychain."
