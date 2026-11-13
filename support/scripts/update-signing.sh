#!/bin/sh
# Quick Send update signing (ECDSA P-256). Background updates install a release
# only if SHA256SUMS.txt carries a valid signature from this key.
#
#   support/scripts/update-signing.sh genkey ~/secure/quicksend-update.pem
#       Creates the private key (keep it OUTSIDE the repository, back it up) and
#       prints the public key to configure as the QS_UPDATE_PUBLIC_KEY variable.
#   support/scripts/update-signing.sh pubkey ~/secure/quicksend-update.pem
#   support/scripts/update-signing.sh sign ~/secure/quicksend-update.pem dist/SHA256SUMS.txt
#       Writes dist/SHA256SUMS.txt.sig and verifies it.
set -eu
cmd=${1:-}; key=${2:-}
[ -n "$cmd" ] && [ -n "$key" ] || { sed -n '2,11p' "$0"; exit 2; }
pubkey() { openssl ec -in "$key" -pubout -outform DER 2>/dev/null | base64 -w0; echo; }
case "$cmd" in
  genkey)
    [ ! -e "$key" ] || { echo "$key exists, refusing to overwrite" >&2; exit 1; }
    (umask 077 && openssl ecparam -name prime256v1 -genkey -noout -out "$key")
    echo "Private key: $key (never commit it; store the PEM as the QS_UPDATE_SIGNING_KEY secret)"
    printf 'QS_UPDATE_PUBLIC_KEY='; pubkey ;;
  pubkey) pubkey ;;
  sign)
    sums=${3:?SHA256SUMS.txt path}
    openssl dgst -sha256 -sign "$key" -out "$sums.sig" "$sums"
    tmp=$(mktemp); openssl ec -in "$key" -pubout -out "$tmp" 2>/dev/null
    openssl dgst -sha256 -verify "$tmp" -signature "$sums.sig" "$sums"; rm -f "$tmp" ;;
  *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
