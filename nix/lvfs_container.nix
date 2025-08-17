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
          export FLASK_APP="${self'.packages.default}/lvfs/__init__.py"
          cd ${self'.packages.default}
          env -0 | ${lib.getExe pkgs.jq} -Rrs 'split("\u0000") | map(split("=")) | map(select(.[0] != null)) | map({(.[0]): (.[1:] | join("="))}) | add' > $out
        '';
      };
      envFileWithContext = builtins.readFile envFile;
      envWhitelist = [
        "PATH"
        "PYTHONPATH"
        "FLASK_APP"
      ];
      # fromJSON can't accept string with context, drop the context here,
      # we recover it down below after processing JSON.
      env = builtins.fromJSON (builtins.unsafeDiscardStringContext envFileWithContext);
      env' = lib.mapAttrs (
        k: v:
        # Recover the context, required so that all dependencies are properly
        # propagated to the container.
        builtins.appendContext v (builtins.getContext envFileWithContext)
      ) env;
      filteredEnv = lib.filterAttrs (k: v: lib.elem k envWhitelist) env' // {
        LD_LIBRARY_PATH = "${pkgs.gnutls.out}/lib";
        # See the comment in lvfs.nix
        LVFS_INSTANCE_PATH = "/data";
      };
      gunicornConfig = pkgs.writeTextFile {
        name = "gunicorn.py";
        # Basically same as upstream gunicorn.py but without `user` and `group` options
        # because of 2 reasons:
        # - for development it may be desirable to run as same user that invokes docker
        # - changing user/group typically requires root privilege inside container
        #   which won't be the case if container is already running as different
        #   user (such as when using Docker's -u option).
        text = ''
          chdir = "${self'.packages.default}"
          wsgi_app = "wsgi:app"
          workers = 8
          worker_class = "gevent"
          timeout = 2400
          bind = "[::0]:5000"
          loglevel = "info"
          accesslog = "-"
          x_forwarded_for_header = True
        '';
      };
      lvfsInit = pkgs.writeShellScript "lvfs-init" ''
        set -euo pipefail

        mkdir -p /data/{certs,downloads,shards,uploads,mirror}

        if [ $# -ne 0 ]; then
          exec "$@"
        fi

        LVFS_DB_SERVER="''${LVFS_DB_SERVER:-sqlite:///lvfs.db}"
        if echo "$LVFS_DB_SERVER" | grep -qE '^sqlite://'; then
          path="$LVFS_INSTANCE_PATH/''${LVFS_DB_SERVER#sqlite://}"
          if ! [ -e "$path" ]; then
            echo "initializing new sqlite database at $path"
            flask initdb
            flask db stamp
            echo "DB init done"
          fi
        fi

        echo "upgrading database"
        flask db upgrade

        echo "ensuring setting defaults"
        flask settings-create

        gunicorn --config ${gunicornConfig} wsgi:app
      '';
    in
    {
      packages.container-lvfs = nix2container.buildImage {
        name = "lvfs";
        tag = "latest";
        config = {
          # Set workdir to lvfs-website location so that Flask-Migrate works.
          WorkingDir = env'.PWD;
          Env = lib.mapAttrsToList (n: v: "${n}=${v}") filteredEnv;
          entrypoint = [
            "${lib.getExe pkgs.bash}"
            "-i"
            lvfsInit
          ];
        };
      };
    };
}
