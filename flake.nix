{
  description = "Rigflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # Build straight from this working tree (edition 2024 → needs a recent
        # rustc, which nixos-unstable provides), rather than a pinned release.
        commonArgs = {
          version = "0.1.4";
          src = self;
          cargoLock.lockFile = ./Cargo.lock;
          # Server tests want hardware / the network; skip during the build.
          doCheck = false;
        };

        rigflow-server = pkgs.rustPlatform.buildRustPackage (
          commonArgs
          // {
            pname = "rigflow-server";
            cargoBuildFlags = [
              "-p"
              "rigflow-server"
            ];
            nativeBuildInputs = [ pkgs.pkg-config ];
            # rusb / libusb1-sys links libusb-1.0 via pkg-config.
            buildInputs = [ pkgs.libusb1 ];
          }
        );

        rigflow-probe = pkgs.rustPlatform.buildRustPackage (
          commonArgs
          // {
            pname = "rigflow-probe";
            cargoBuildFlags = [
              "-p"
              "rigflow-probe"
            ];
          }
        );

        # winit/eframe dlopen these at runtime, so a `cargo run` of the client
        # needs them on LD_LIBRARY_PATH (they are not link-time deps).
        clientRuntimeLibs = with pkgs; [
          libGL
          libxkbcommon
          wayland
          vulkan-loader

          libX11
          libXcursor
          libXrandr
          libXi
          libxcb
        ];

        rigflow-client = pkgs.rustPlatform.buildRustPackage (
          commonArgs
          // {
            pname = "rigflow-client";
            cargoBuildFlags = [
              "-p"
              "rigflow-client"
            ];
            nativeBuildInputs = [ pkgs.pkg-config ];
            # alsa-sys links libasound via pkg-config; the rest are dlopen'd.
            buildInputs = [ pkgs.alsa-lib ] ++ clientRuntimeLibs;
          }
        );
      in
      {
        packages = {
          inherit rigflow-server rigflow-client rigflow-probe;
          default = rigflow-server;
        };

        # `nix develop` → a shell with the toolchain + native deps so
        # `cargo test`, `cargo build`, `cargo clippy` all work against the tree.
        devShells.default = pkgs.mkShell {
          inputsFrom = [
            rigflow-server
            rigflow-client
          ];
          nativeBuildInputs = with pkgs; [
            pkg-config
            cargo
            rustc
            rustfmt
            clippy
          ];
          LD_LIBRARY_PATH = lib.makeLibraryPath clientRuntimeLibs;
        };
      }
    );
}
