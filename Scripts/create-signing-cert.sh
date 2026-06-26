#!/bin/bash
#
# Creates a persistent self-signed code-signing identity in a DEDICATED keychain
# with a known password, so `codesign` can use it non-interactively (no GUI
# "Always Allow" prompt). macOS ties Accessibility/Calendar grants to the signing
# identity — a stable identity means grants survive reinstalls.
#
# Run once. Idempotent. Not trusted by Gatekeeper (fine for a local personal app).

set -euo pipefail
CERT_NAME="Quack Local Signing"
KEYCHAIN="$HOME/Library/Keychains/quack-signing.keychain-db"
KC_PASS="quack"

# Already set up and usable?
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ '$CERT_NAME' already exists in $KEYCHAIN — nothing to do."
    exit 0
fi

# Remove any earlier copy from the login keychain (from a prior attempt).
security delete-identity -c "$CERT_NAME" >/dev/null 2>&1 || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass:"$KC_PASS" 2>/dev/null

# Dedicated keychain with a known password.
security create-keychain -p "$KC_PASS" "$KEYCHAIN" 2>/dev/null || true
security set-keychain-settings "$KEYCHAIN"                 # no auto-lock
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$KC_PASS" -A -T /usr/bin/codesign
# Allow codesign/Apple tools to use the key without prompting.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
# Add to the search list so codesign can find the identity.
EXISTING="$(security list-keychains -d user | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//')"
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo "✓ Created '$CERT_NAME' in $KEYCHAIN (codesign-ready, no prompts)."
