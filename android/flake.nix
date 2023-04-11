{
  description = "My Android project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    devshell.url = "github:numtide/devshell";
    flake-utils.url = "github:numtide/flake-utils";
    android.url = "github:tadfisher/android-nixpkgs";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, devshell, flake-utils, android, zig }:
    {
      overlay = final: prev: {
        inherit (self.packages.${final.system}) android-sdk zig;
      };
    }
    //
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            devshell.overlays.default
            self.overlay
          ];
        };
      in
      {
        packages = {
          zig = zig.packages.${system}.master;
          android-sdk = android.sdk.${system} (sdkPkgs: with sdkPkgs; [
            # Useful packages for building and testing.
            build-tools-33-0-1
            cmdline-tools-latest
            platform-tools
            platforms-android-21
            ndk-25-1-8937393
          ]);
        };

        devShell = import ./devshell.nix { inherit pkgs; };
      }
    );
}
