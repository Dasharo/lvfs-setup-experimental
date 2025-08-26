#!/usr/bin/env bash

set -euo pipefail

# Updated by Nix when packaging this script as Nix package
# _jcat_cmd=""
_fwupdtool=fwupdtool

usage() {
    echo "Usage: mkupdate.sh [options]" >&2
    echo "    -h This help message." >&2
    echo "    -v Firmware version." >&2
    echo "    -k Path to private key file used for signing" >&2
    echo "    -c Path to certificate file used for signing" >&2
    echo "    -o Output file." >&2
    exit 1
}

die() {
    [ $# -ne 0 ] && echo "$@"
    exit 1
}

while getopts "hv:o:k:c:" o; do
    case "$o" in
    o) output="$OPTARG" ;;
    v) version="$OPTARG" ;;
    k) privkey_path="$OPTARG" ;;
    c) cert_path="$OPTARG" ;;
    *) usage ;;
    esac
done
shift $((OPTIND-1))
[ $# -eq 0 ] || usage
[ -n "${output+x}" ] || usage
[ -n "${version+x}" ] || usage
[ -n "${privkey_path+x}" ] && [ -z "${cert_path+x}" ] && usage
[ -n "${cert_path+x}" ] && [ -z "${privkey_path+x}" ] && usage

if [ -n "${privkey_path+x}" ]; then
    privkey_path_abs="$(readlink -f "$privkey_path")"
fi

if [ -n "${cert_path+x}" ]; then
    cert_path_abs="$(readlink -f "$cert_path")"
fi

date="$(date +%Y-%m-%d)"
firmware_filename="fakedevice.bin"
have_jcat=0

jcat() {
    if [ -z "${_jcat_cmd+x}" ]; then
        _jcat_cmd="$(which jcat 2>/dev/null || true)"

        if [ -z "${_jcat_cmd}" ]; then
            _jcat_cmd="$(which jcat-tool 2>/dev/null || true)"

            if [ -z "${_jcat_cmd}" ] && which nix 2>/dev/null >&2; then
                _jcat_cmd="$(nix build -L --no-link --print-out-paths nixpkgs#libjcat.bin)/bin/jcat-tool"
            fi
        fi
    fi

    "$_jcat_cmd" "$@"
}

tempdir="$(mktemp --tmpdir --directory mkupdate-XXXXXXXXXXXX)"
cleanup() {
    rm -rf "$tempdir"
}
trap cleanup EXIT

echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || die "Invalid version \"$version\""
IFS="." read -r version_major version_minor version_patch <<< "$version"
version_component_check() {
  if ! [[ "$1" =~ ^[0-9]+$ ]] || (( $1 > 255 )); then
    die "Invalid version \"$version\""
  fi
}
version_component_check "$version_major"
version_component_check "$version_minor"
version_component_check "$version_patch"

printf "0x%x%02x00%02x" "$version_major" "$version_minor" "$version_patch" > "$tempdir/$firmware_filename"

sha1sum="$(sha1sum "$tempdir/$firmware_filename" | awk '{ print $1 }')"
sha256sum="$(sha256sum "$tempdir/$firmware_filename" | awk '{ print $1 }')"

cat > "$tempdir/firmware.metainfo.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="firmware">
  <id>org.fwupd.fakedevice.firmware</id>
  <name>FakeDevice</name>
  <summary>Firmware for the ACME Corp Integrated Webcam</summary>
  <description>
    <p>Updating the firmware on your webcam device improves performance and adds new features.</p>
  </description>
  <provides>
    <firmware type="flashed">b585990a-003e-5270-89d5-3705a17f9a43</firmware>
  </provides>
  <url type="homepage">http://www.acme.com/</url>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-2.0+</project_license>
  <developer_name>LVFS</developer_name>
  <categories>
    <category>X-Device</category>
  </categories>
  <custom>
    <value key="LVFS::DeviceIntegrity">unsigned</value>
    <value key="LVFS::VersionFormat">triplet</value>
    <value key="LVFS::UpdateProtocol">com.acme.test</value>
  </custom>
  <releases>
    <release version="$version" date="$date" urgency="medium">
      <checksum type="sha1" filename="$firmware_filename" target="content">$sha1sum</checksum>
      <checksum type="sha256" filename="$firmware_filename" target="content">$sha256sum</checksum>
      <description>
        <p>Experimental update served straight from a custom LVFS-like instance.</p>
      </description>
      <url type="source">https://github.com/fwupd/fwupd/tree/main/data/installed-tests</url>
      <artifacts>
        <artifact type="source">
          <filename>$firmware_filename</filename>
          <checksum type="sha1">$sha1sum</checksum>
          <checksum type="sha256">$sha256sum</checksum>
        </artifact>
      </artifacts>
    </release>
  </releases>
</component>
EOF

files_to_sign=(
    "$firmware_filename"
    firmware.metainfo.xml
)

if [ -n "${privkey_path+x}" ]; then
    pushd "$tempdir" >/dev/null
    for file in "${files_to_sign[@]}"; do
        jcat self-sign "$tempdir/firmware.jcat" "$file" --kind sha1
        jcat self-sign "$tempdir/firmware.jcat" "$file" --kind sha256
        jcat sign "$tempdir/firmware.jcat" "$file" "$cert_path_abs" "$privkey_path_abs"
    done
    popd >/dev/null

    have_jcat=1
fi

(
destdir="$PWD"
if [[ "$output" =~ ^/ ]]; then
  output_fixed="$output"
else
  output_fixed="$destdir/$output"
fi

cd "$tempdir"
args=(
    "$output_fixed"
    "$firmware_filename"
    firmware.metainfo.xml
)
if [ "$have_jcat" -ne 0 ]; then
    args+=("firmware.jcat")
fi
"$_fwupdtool" build-cabinet "${args[@]}"
)
