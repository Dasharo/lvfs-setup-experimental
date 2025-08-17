{
  description = "A flake for rust project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    dream2nix.url = "github:nix-community/dream2nix";
    nixpkgs.follows = "dream2nix/nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      dream2nix,
      nix2container,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/lvfs_container.nix
      ];

      systems = nixpkgs.lib.systems.flakeExposed;
      perSystem =
        { pkgs, inputs', ... }:
        let
          llvm = pkgs.llvmPackages_latest;
          stdenv = pkgs.stdenvAdapters.overrideCC llvm.stdenv llvm.clangUseLLVM;
          mkShell = pkgs.mkShell.override { inherit stdenv; };
          package = dream2nix.lib.evalModules {
            packageSets.nixpkgs = pkgs;
            modules = [
              ./nix/lvfs.nix
              {
                paths.projectRoot = ./.;
                paths.projectRootFile = "flake.nix";
                paths.package = ./.;
              }
            ];
          };
        in
        {
          _module.args.pkgs = inputs'.nixpkgs.legacyPackages;

          devShells.default = mkShell {
            # Include dependencies for LVFS, these become importable by python.
            inputsFrom = [ package.devShell ];
            env.LD_LIBRARY_PATH = "${pkgs.gnutls.out}/lib";
            env.LVFS_APP_PATH = package;
            env.FLASK_APP = "${package}/lvfs/__init__.py";
          };
          packages.default = package;
        };
    };
}
