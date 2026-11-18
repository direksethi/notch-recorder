#!/bin/bash
# Optional. Creates a self-signed code-signing identity in a dedicated
# keychain on this Mac, so every build carries the same signature and macOS
# keeps the Screen Recording and Microphone permissions between builds.
# Without it, builds are ad-hoc signed and macOS may ask for the permissions
# again after each rebuild.
#
# Run on the Mac. Then build with:
#   CODESIGN_IDENTITY="Notch Recorder Local Signing" scripts/make-app.sh
#
# Environment:
#   KEYCHAIN_PASS_FILE  file holding the keychain password; created with a
#                       random password when missing
#                       (default ~/.config/notch-recorder/build-keychain.pass)
set -euo pipefail

PASS_FILE="${KEYCHAIN_PASS_FILE:-$HOME/.config/notch-recorder/build-keychain.pass}"
IDENTITY="Notch Recorder Local Signing"
KEYCHAIN="notch-recorder-build.keychain-db"
KC="$HOME/Library/Keychains/$KEYCHAIN"

mkdir -p "$(dirname "$PASS_FILE")"
if [ ! -f "$PASS_FILE" ]; then
  (umask 077; openssl rand -hex 24 > "$PASS_FILE")
fi
KC_PASS=$(cat "$PASS_FILE")

# codesign only finds identities in keychains on the user search list.
add_to_search_list() {
  local current
  current=$(security list-keychains -d user | tr -d '"' | xargs)
  # shellcheck disable=SC2086
  case " $current " in *" $KC "*) ;; *) security list-keychains -d user -s $current "$KC" ;; esac
}
if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$IDENTITY"; then
  add_to_search_list
  echo "identity already present"
  exit 0
fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" >/dev/null 2>&1
# The .p12 only exists inside the temporary folder, so its password is a formality.
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$IDENTITY" -out "$WORK/id.p12" -passout pass:transfer >/dev/null 2>&1
[ -f "$KC" ] || security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P transfer -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
add_to_search_list
security find-identity -p codesigning "$KC"
