#!/usr/bin/env bash

set -euo pipefail

if [ -e "secrets" ]; then
    echo "\"secrets\" directory already exists, refusing to override" >&2
    exit 1
fi

mkdir secrets
# This is taken from https://flask.palletsprojects.com/en/stable/config/#SECRET_KEY
# Internally, secrets/secret_key is fed to Flask as SECRET_KEY.
# HACK: Other keys are specific to LVFS and seem to be undocumented so I assumed
# they should be created the same way.
python3 -c 'import secrets; print(secrets.token_hex(), end="")' > secrets/secret_key
python3 -c 'import secrets; print(secrets.token_hex(), end="")' > secrets/secret_addr_salt
python3 -c 'import secrets; print(secrets.token_hex(), end="")' > secrets/secret_vendor_salt
