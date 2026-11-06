{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Foundry only: nixos-26.05 ships forge 1.7.1, which predates the latest forge-std.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      flake-utils,
      rust-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
        unstable = nixpkgs-unstable.legacyPackages.${system};

        rustToolchain = pkgs.rust-bin.stable."1.98.0".default.override {
          extensions = [
            "rust-src"
            "llvm-tools"
          ];
          targets = [ "wasm32-unknown-unknown" ];
        };
      in
      {
        devShells = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              rustToolchain
              rust-analyzer
              unstable.foundry
              solc

              circom
              nodejs_24
              pnpm
              just
              (python3.withPackages (ps: [ ps.matplotlib ]))
            ];

            shellHook = "export FOUNDRY_SOLC=${pkgs.solc}/bin/solc";
          };
        };
      }
    );
}
