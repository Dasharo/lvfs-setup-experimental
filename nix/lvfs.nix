{
  config,
  dream2nix,
  ...
}:
let
  inherit (config) deps;
in
{
  imports = [
    dream2nix.modules.dream2nix.pip
  ];

  name = "lvfs";
  version = "git";

  deps =
    { nixpkgs, ... }:
    {
      inherit (nixpkgs) fetchFromGitLab gnutls;
      python = nixpkgs.python312;
    };

  mkDerivation = {
    src = deps.fetchFromGitLab {
      owner = "fwupd";
      repo = "lvfs-website";
      rev = "ed377f14b8e51d8bbe6edd57d2aa2201622bf732";
      hash = "sha256-jrSQwxZcyBxy+wZ8spRUL+MPr1JXozOdBzVGjOt7GNg=";
    };
    # Upstream is not configurable enough. Use custom config module which takes
    # parameters through env variables and docker's secrets.
    postPatch = ''
      cp ${./flaskapp.cfg} lvfs/flaskapp.cfg

      # Flask has concept of instance path which is used for storing data and Flask-SQLAlchemy
      # treats all paths as relative to instance path. By default instance path is set to
      # app module location which in this case is path pointing somewhere to Nix store.
      # This results in confusing errors when trying to create SQLite database at /data/lvfs.db
      # as the path becomes invalid after prepending instance path.
      substituteInPlace lvfs/__init__.py \
        --replace-fail 'app: Flask = Flask(__name__)' 'app: Flask = Flask(__name__, instance_path=os.environ.get("LVFS_INSTANCE_PATH", None))'
    '';
    preConfigure = ''
      cat >> pyproject.toml <<EOF
      [project]
      name = "lvfs"
      version = "1.0"

      [tool.setuptools]
      include-package-data = true

      [tool.setuptools.packages.find]
      where = ["."]
      include = [
        "lvfs", "lvfs.*",
        "jcat", "pkgversion"
      ]

      [tool.setuptools.package-data]
      lvfs = ["**/*"]
      EOF
    '';
    nativeCheckInputs = [ deps.gnutls.out ];
    preBuild = ''
      export "LD_LIBRARY_PATH=${deps.gnutls.out}/lib:$LD_LIBRARY_PATH"
    '';
  };
  buildPythonPackage = {
    pyproject = true;
    pythonImportsCheck = [ "lvfs" ];
  };
  pip = {
    requirementsFiles = [ "${config.mkDerivation.src}/requirements.txt" ];
    flattenDependencies = true;
  };
}
