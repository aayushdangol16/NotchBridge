#!/bin/bash
# One-time, optional: creates a self-signed code-signing certificate "NotchBridge Local Signing" in your
# login keychain. build-app.sh then signs with it, so the app keeps the same identity across rebuilds and
# macOS stops re-asking for Calendar / Camera / Local Network permission after every build.
#
# It only affects apps you sign with it (just NotchBridge). Remove it any time in Keychain Access
# (login keychain › My Certificates › "NotchBridge Local Signing").
set -euo pipefail

NAME="NotchBridge Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="notchbridge-$RANDOM"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS" -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS"

security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo
echo "Created \"$NAME\". Rebuild with ./build-app.sh --install."
echo "macOS will ask for permissions one last time; after that they stick across rebuilds."
