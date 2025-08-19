#!/usr/bin/env bash

set -euo pipefail

# Updated by Nix when packaging this script as Nix package
_openssl=openssl

usage() {
    echo "Usage: mktestkey.sh [options]" >&2
    echo "    -h This help message." >&2
    echo "    -k Private key output file." >&2
    echo "    -c Certificate output file." >&2
    exit 1
}

while getopts "hk:c:" o; do
    case "$o" in
    k) privkey_output="$OPTARG" ;;
    c) certificate_output="$OPTARG" ;;
    *) usage ;;
    esac
done
shift $((OPTIND-1))
[ $# -eq 0 ] || usage
[ -n "${privkey_output+x}" ] || usage
[ -n "${certificate_output+x}" ] || usage

tempdir="$(mktemp --tmpdir --directory mktestkey-XXXXXXXXXXXX)"
cleanup() {
    rm -rf "$tempdir"
}
trap cleanup EXIT

cat > "$tempdir/openssl.ini" <<EOF
[req]
default_bits = 2048
distinguished_name = dn
x509_extensions = v3_req
prompt = yes

[dn]
CN = Common Name
CN_default = LVFS test signing key

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

openssl req -x509 -new -noenc -config "$tempdir/openssl.ini" \
    -keyout "$privkey_output" -out "$certificate_output" \
