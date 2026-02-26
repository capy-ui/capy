{
  description = "capy - Cross-platform Zig GUI library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {  nixpkgs, flake-utils, zig-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        zigPkg = pkgs.zigpkgs."0.15.2";

        inherit (pkgs) lib stdenv;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Core development tools
            zigPkg
            pkgs.gnumake
            pkgs.pkg-config
            # pkgs.zls  # TODO: re-enable when ZLS is compatible with current Zig version
            pkgs.git
          ]
          ++ lib.optionals stdenv.isLinux [
            # GTK and related libraries for Linux backend
            pkgs.gtk3
            pkgs.gtk4
            pkgs.glib
            pkgs.cairo
            pkgs.pango
            pkgs.gdk-pixbuf

            # OpenGL/Graphics
            pkgs.libGL
            pkgs.libGLU
            pkgs.mesa

            # Audio libraries
            pkgs.alsa-lib
            pkgs.pipewire

            # Android development (optional)
            pkgs.android-tools

            # Linux debugging tools
            pkgs.gdb
            pkgs.valgrind
            pkgs.strace
          ]
          ++ lib.optionals stdenv.isDarwin [
            pkgs.apple-sdk
            pkgs.libiconv
          ];

          shellHook = ''
            # Zig doesn't recognize Nix's -fmacro-prefix-map C flags; suppress warnings
            unset NIX_CFLAGS_COMPILE
            echo "Capy Development Environment"
            echo "Zig version: $(zig version)"
            echo ""
            echo "Available commands:"
            echo "  zig build              - Build the project"
            echo "  zig build test         - Run tests"
            echo "  zig build <example>    - Build and run specific example"
            echo ""
          '' + lib.optionalString stdenv.isLinux ''
            # Set up pkg-config paths for GTK
            export PKG_CONFIG_PATH="${pkgs.gtk3}/lib/pkgconfig:${pkgs.gtk4}/lib/pkgconfig:$PKG_CONFIG_PATH"

            # Set up library paths
            export LD_LIBRARY_PATH="${lib.makeLibraryPath [
              pkgs.gtk3
              pkgs.gtk4
              pkgs.libGL
              pkgs.mesa
              pkgs.alsa-lib
            ]}:$LD_LIBRARY_PATH"
          '' + lib.optionalString stdenv.isDarwin ''
            # macOS-specific environment setup
            # Frameworks are found automatically via the SDK
          '';
        };
      });
}
