# Serving firmware over http

This directory contains 3 tools

- `mktestkey.sh` - simple tool to generate test key and certificate using
  OpenSSL.
- `mkupdate.sh` - simple tool that builds optionally signed cabinet image fwupd's
  fake webcam (see below for details). This is not a general-purpose tool as it
  cannot build update packages for any devices but can be easily adapted.
- `build_fwstore.sh` - builds content-addressed store containing firmware images
  and generates metadata allowing firmware to be served over HTTP.

## Building and serving firmware

Enter following commands

```shell
nix run ..#mktestkey -- -k key.pem -c cert.pem
nix run ..#mkupdate -- -v 1.2.5 -k key.pem -c cert.pem -o firmware.cab
nix run ..#build-fwstore -- --store store --base-url 'http://localhost:8000' --cert cert.pem --key key.pem firmware.cab
```

You can serve this over HTTP using virtually any server by setting content root
to store directory.

```shell
store/
├── 36
│   └── 715b4670d0a5c5acb6b0584a0120def318e14fbb49af5352052a16caf3a91a
├── firmware.xml.zst
└── firmware.xml.zst.jcat
```

For testing purposes you may use Python's built-in HTTP server:

```shell
cd store
python3 -m http.server 8000
```

> Note: `--base-url` will need to be changed when serving to the public.

## Testing with fwupd

Start by enabling test devices in fwupd, this will enable an internal fake
camera used for testing update process. To do it, open `/etc/fwupd/fwupd.conf`
and add

```ini
[fwupd]
TestDevices=true
```

Copy certificate generate in previous step to `/etc/pki/fwupd/` to make it
trusted.

```shell
cp cert.pem /etc/pki/fwupd/Test-Cert.pem
```

Create `/etc/fwupd/remotes.d/custom.conf`:

```ini
[fwupd Remote]
Enabled=true
Title=Custom LVFS
MetadataURI=http://localhost:8000/firmware.xml.zst
OrderBefore=lvfs
```

Restart fwupd service for changes to take effect:

```shell
systemctl restart fwupd
```

Refresh repositories

```shell
Updating custom
Downloading?             [***************************************]
Updating lvfs
Downloading?             [********************                   ]
```

Get list of updates

```shell
fwupdmgr get-updates b585990a-003e-5270-89d5-3705a17f9a43
Selected device: Integrated Webcam™
Gigabyte Technology Co., Ltd. A520 AORUS ELITE
│
└─Integrated Webcam™:
  │   Device ID:          08d460be0f1f9f128413f816022a6439e0078018
  │   Summary:            Fake webcam
  │   Current version:    1.2.2
  │   Minimum Version:    1.2.0
  │   Bootloader Version: 0.1.2
  │   Vendor:             ACME Corp. (USB:0x046D)
  │   GUID:               b585990a-003e-5270-89d5-3705a17f9a43
  │   Device Flags:       • Updatable
  │                       • System requires external power source
  │                       • Supported on remote server
  │                       • Cryptographic hash verification is available
  │                       • Unsigned Payload
  │                       • Can tag for emulation
  │   Device Requests:    • Message
  │ 
  ├─FakeDevice Device Update:
  │     New version:      1.2.5
  │     Remote ID:        custom
  │     Summary:          Firmware for the ACME Corp Integrated Webcam
  │     License:          GPL-2.0+
  │     Urgency:          Medium
  │     Source:           https://github.com/fwupd/fwupd/tree/main/data/installed-tests
  │     Vendor:           LVFS
  │     Release Flags:    • Trusted metadata
  │                       • Is upgrade
  │     Description:      
  │     Experimental update served straight from a custom LVFS-like instance.
  │     Checksum:         36715b4670d0a5c5acb6b0584a0120def318e14fbb49af5352052a16caf3a91a
  │   
  └─FakeDevice Device Update:
        New version:      1.2.4
        Remote ID:        lvfs
        Release ID:       81488
        Summary:          Firmware for the ACME Corp Integrated Webcam
        License:          GPL-2.0+
        Size:             10 bytes
        Created:          2024-01-21
        Urgency:          Medium
          Tested:         2025-07-15
          Distribution:   chromeos 139
          Old version:    1.2.2
          Version[fwupd]: 2.0.10
          Tested:         2025-06-10
          Distribution:   chromeos 138
          Old version:    1.2.2
          Version[fwupd]: 2.0.10
          Tested:         2025-06-10
          Distribution:   chromeos 139
          Old version:    1.2.2
          Version[fwupd]: 2.0.10
          Tested:         2024-03-09
          Distribution:   chromeos 124
          Old version:    1.2.2
          Version[fwupd]: 1.9.13
        Source:           https://github.com/fwupd/fwupd/tree/main/data/installed-tests
        Vendor:           LVFS
        Release Flags:    • Trusted metadata
                          • Is upgrade
        Description:      
        Fixes another bug with the flux capacitor to prevent time going backwards.
        Checksum:         a92d4f433e925ea8e4a10d25dfa58e64ba1e68d07ee963605a2ccbaa2e3185aa
```

You can see two versions of firmware: `1.2.5` and `1.2.4`, `1.2.5` comes from
our repository (see `Remote ID` field).

Run the update

```shell
╔══════════════════════════════════════════════════════════════════════════════╗
║ Upgrade Integrated Webcam™ from 1.2.2 to 1.2.5?                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Experimental update served straight from a custom LVFS-like instance.        ║
║                                                                              ║
║ Integrated Webcam™ and all connected devices may not be usable while         ║
║ updating.                                                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝
Perform operation? [Y|n]: Y
Waiting…                 [***************************************]
Successfully installed firmware
Devices with no available firmware updates:
 • DT01ACA100
 • GIGABYTE
 • GIGABYTE
 • KEK CA
 • SSD 980 1TB
 • Windows UEFI CA
```

You can also check HTTP server logs to see firmware was accessed:

```ignore
127.0.0.1 - - [19/Aug/2025 19:31:43] "GET /firmware.xml.zst.jcat HTTP/1.1" 200 -
127.0.0.1 - - [19/Aug/2025 19:31:43] "GET /firmware.xml.zst HTTP/1.1" 200 -
127.0.0.1 - - [19/Aug/2025 19:31:50] "GET /firmware.xml.zst.jcat HTTP/1.1" 200 -
127.0.0.1 - - [19/Aug/2025 19:32:19] "GET /firmware.xml.zst.jcat HTTP/1.1" 200 -
127.0.0.1 - - [19/Aug/2025 19:32:25] "GET /firmware.xml.zst.jcat HTTP/1.1" 200 -
127.0.0.1 - - [19/Aug/2025 19:36:01] "GET /36/715b4670d0a5c5acb6b0584a0120def318e14fbb49af5352052a16caf3a91a HTTP/1.1" 200 -
```

## Repository updates

fwupdmgr will refuse to update repositories without `--force` flag:

```ignore
Metadata is up to date; use --force to refresh again.
```

LVFS uses `max-age` to set duration for which metadata is valid. I don't know
for how long is metadata valid by default (assuming it ever expires).

```shell
curl -sS -D - https://cdn.fwupd.org/downloads/firmware.xml.zst -o /dev/null

HTTP/2 200 
content-type: application/zstd
server: gunicorn
content-disposition: attachment; filename=firmware.xml.zst
cache-control: public, max-age=14400
accept-ranges: bytes
age: 6485
date: Tue, 19 Aug 2025 17:38:57 GMT
via: 1.1 varnish
x-served-by: cache-fra-eddf8230022-FRA
x-cache: HIT
x-cache-hits: 0
content-length: 1653087
```

As setting HTTP headers is specific to web server implementation it is omitted
from this document.
