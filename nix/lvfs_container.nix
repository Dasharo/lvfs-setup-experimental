{ ... }:
{
  perSystem =
    {
      lib,
      self',
      inputs',
      pkgs,
      ...
    }:
    let
      inherit (inputs'.nix2container.packages) nix2container;
      envFile = pkgs.stdenvNoCC.mkDerivation {
        name = "env";
        phases = [ "buildPhase" ];
        nativeBuildInputs = [ self'.packages.default ];
        buildInputs = [ self'.packages.default ];
        buildPhase = ''
          set -e
          export FLASK_APP="$(python -c 'import importlib.util; print(importlib.util.find_spec("lvfs").origin, end="")')"
          env -0 | ${lib.getExe pkgs.jq} -Rrs 'split("\u0000") | map(split("=")) | map(select(.[0] != null)) | map({(.[0]): (.[1:] | join("="))}) | add' > $out
        '';
      };
      envFileWithContext = builtins.readFile envFile;
      envWhitelist = [
        "PATH"
        "PYTHONPATH"
        "FLASK_APP"
      ];
      env = lib.filterAttrs (k: v: lib.elem k envWhitelist) (
        # fromJSON can't accept string with context, drop the context here,
        # we recover it down below after processing JSON.
        builtins.fromJSON (builtins.unsafeDiscardStringContext envFileWithContext)
      );
      env' =
        lib.mapAttrs (
          k: v:
          # Recover the context, required so that all dependencies are properly
          # propagated to the container.
          builtins.appendContext v (builtins.getContext envFileWithContext)
        ) env
        // {
          LD_LIBRARY_PATH = "${pkgs.gnutls.out}/lib";
        };
      lvfsInit = pkgs.writeShellScript "lvfs-init" ''
        set -euo pipefail

        mkdir -p /data/{certs,downloads,shards,uploads,mirror}

        if [ $# -ne 0 ]; then
          exec "$@"
        fi

        LVFS_DB_SERVER="''${LVFS_DB_SERVER:-sqlite:///data/lvfs.db}"
        if "$LVFS_DB_SERVER" | grep -qE '^sqlite://'; then
          path="''${LVFS_DB_SERVER#sqlite://}"
          echo "===== path $path"
          if ! [ -e "$path" ]; then
            echo "initializing new sqlite database"
            touch "$path"
            flask initdb
            flask db stamp
            flask db upgrade
          fi
        fi

        echo "upgrading database"
        # flask db upgrade

        echo "ensuring setting defaults"
        flask settings-create
      '';
    in
    {
      packages.container-lvfs = nix2container.buildImage {
        name = "lvfs";
        tag = "latest";
        config = {
          Env = lib.mapAttrsToList (n: v: "${n}=${v}") env';
          entrypoint = [
            "${lib.getExe pkgs.bash}"
            "-i"
            lvfsInit
          ];
        };
      };
    };
}
