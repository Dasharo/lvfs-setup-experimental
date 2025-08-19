#!/usr/bin/env python3

from argparse import ArgumentParser
from lxml import etree as ET
from cabarchive import CabArchive
from hashlib import sha1, sha256
from io import IOBase
from typing import cast, List
from shutil import which
import sys
import os
import subprocess


# Updated by nix when packaging this script
JCAT_PATH = None


def url_for_file(base_url: str, digest: bytes):
    hexdigest = digest.hex()
    return f"{base_url}/{hexdigest[:2]}/{hexdigest[2:]}"


def write_to_ca_store(store_path: str, digest: bytes, data: bytes):
    hexdigest = digest.hex()
    dir = f"{store_path}/{hexdigest[:2]}"
    full_path = f"{dir}/{hexdigest[2:]}"

    os.makedirs(dir, exist_ok=True)
    with open(full_path, "wb") as f:
        f.write(data)
        f.flush()


def process_fw_file(base_url: str, store_path: str, path: str) -> ET.Element:
    with open(path, "rb") as file:
        data = file.read()

    h1 = sha1(data)
    h256 = sha256(data)
    url = url_for_file(base_url, h256.digest())

    cab = CabArchive(data)

    # Inject URL to .cab files into firmware manifest.
    component = ET.fromstring(cab["firmware.metainfo.xml"].buf)
    releases = component.find("releases")

    for release in releases.findall("release"):
        location = ET.Element("location")
        location.text = url
        release.insert(0, location)

        # This is also required for fwupd to pickup update.
        artifacts = release.find("artifacts")
        artifact_cab = ET.Element("artifact", {"type": "binary"})

        artifact_cab.append(location)

        sha1_node = ET.Element("checksum", {"type": "sha1"})
        sha1_node.text = h1.hexdigest()
        artifact_cab.append(sha1_node)

        sha256_node = ET.Element("checksum", {"type": "sha256"})
        sha256_node.text = h256.hexdigest()
        artifact_cab.append(sha256_node)

        artifacts.append(artifact_cab)

    write_to_ca_store(store_path, h256.digest(), data)

    return component


def jcat(args: List[str], **kwargs):
    global JCAT_PATH

    if JCAT_PATH is None:
        JCAT_PATH = which("jcat")

        if JCAT_PATH is None:
            JCAT_PATH = which("jcat-tool")

            if JCAT_PATH is None and which("nix") is not None:
                JCAT_PATH = (
                    subprocess.run(
                        [
                            "nix",
                            "build",
                            "-L",
                            "--no-link",
                            "--print-out-paths",
                            "nixpkgs#libjcat.bin",
                        ],
                        stdin=sys.stdin,
                        stderr=sys.stderr,
                        stdout=subprocess.PIPE,
                        check=True,
                    )
                    .stdout[:-1]
                    .decode()
                ) + "/bin/jcat-tool"

    if JCAT_PATH is None:
        raise RuntimeError('no "jcat" or "jcat-tool" installed')

    all_args = []
    all_args.append(JCAT_PATH)
    all_args.extend(args)
    subprocess.run(all_args, check=True, stderr=sys.stderr, stdout=sys.stderr, **kwargs)


def main():
    parser = ArgumentParser()
    parser.add_argument("--store", type=str, required=True)
    parser.add_argument("--base-url", type=str, default="http://localhost:8080")
    parser.add_argument("--key", type=str, help="Private key used for signing")
    parser.add_argument("--cert", type=str, help="Certificate used for signing")
    parser.add_argument("file", nargs="+")
    args = parser.parse_args()

    if args.key and not args.cert:
        print("--key requires --cert", file=sys.stderr)
        sys.exit(1)

    if args.cert and not args.key:
        print("--cert requires --key", file=sys.stderr)
        sys.exit(1)

    if args.key:
        key_absolute = os.path.realpath(args.key)

    if args.cert:
        cert_absolute = os.path.realpath(args.cert)

    os.makedirs(args.store, exist_ok=True)

    metadata_path = f"{args.store}/firmware.xml.zst"
    compressor = subprocess.Popen(
        ["zstd", "-q", "-19", "-f", "-o", metadata_path],
        stderr=sys.stderr,
        stdin=subprocess.PIPE,
    )
    stdin = cast(IOBase, compressor.stdin)
    stdin.write(
        b"""<?xml version='1.0' encoding='utf-8'?><components origin="lvfs" version="0.9">"""
    )

    for file in args.file:
        component = process_fw_file(args.base_url, args.store, file)
        stdin.write(ET.tostring(component))

    stdin.write(b"""</components>""")
    stdin.close()

    code = compressor.wait()
    if code != 0:
        raise RuntimeError(f"zstd returned with error code {code}")

    if args.key:
        for kind in ["sha1", "sha256"]:
            jcat(
                [
                    "self-sign",
                    "firmware.xml.zst.jcat",
                    "firmware.xml.zst",
                    "--kind",
                    kind,
                ],
                cwd=args.store,
            )

        jcat(
            [
                "sign",
                "firmware.xml.zst.jcat",
                "firmware.xml.zst",
                cert_absolute,
                key_absolute,
            ],
            cwd=args.store,
        )


if __name__ == "__main__":
    main()
