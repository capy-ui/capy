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

        # The project requires exactly this Zig version (2024.11.0-mach)
        zigPkg = pkgs.stdenv.mkDerivation rec {
          pname = "zig";
          version = "0.14.1";
          
          src = pkgs.fetchurl {
            url = "https://ziglang.org/download/${version}/zig-x86_64-linux-${version}.tar.xz";
            sha256 = "sha256-e+ar3r+pcMYTjRZbNI0EZOhPFvUx5xyyDA4FL64djI0=";
          };
          
          installPhase = ''
            mkdir -p $out/bin
            cp zig $out/bin/
            chmod +x $out/bin/zig
            
            mkdir -p $out/lib
            cp -r lib/* $out/lib/
          '';
          
          dontFixup = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core development tools
            zigPkg
            
            # Build tools
            gnumake
            pkg-config
            
            # GTK and related libraries for Linux backend
            gtk3
            gtk4
            glib
            cairo
            pango
            gdk-pixbuf
            
            # Android development (optional)
            android-tools
            
            # OpenGL/Graphics
            libGL
            libGLU
            mesa
            
            # Audio libraries
            alsa-lib
            pipewire
            
            # Development utilities
            gdb
            valgrind
            strace
            
            # Code formatting and linting
            zls # Zig Language Server
            
            # Version control
            git
          ];

          shellHook = ''
            echo "🎨 Capy Development Environment"
            echo "Zig version: $(zig version)"
            echo ""
            echo "Available commands:"
            echo "  zig build              - Build the project"
            echo "  zig build test         - Run tests"
            echo "  zig build <example>    - Build and run specific example"
            echo ""
            echo "Examples:"
            echo "  zig build 300-buttons"
            echo "  zig build abc"
            echo "  zig build balls"
            echo "  zig build border-layout"
            echo "  zig build calculator"
            echo "  zig build colors"
            echo "  zig build demo"
            echo "  zig build dev-tools"
            echo "  zig build dummy-installer"
            echo "  zig build entry"
            echo "  zig build fade"
            echo "  zig build foo_app"
            echo "  zig build graph"
            echo "  zig build hacker-news"
            echo "  zig build many-counters"
            echo "  zig build media-player"
            echo "  zig build notepad"
            echo "  zig build osm-viewer"
            echo "  zig build slide-viewer"
            echo "  zig build tabs"
            echo "  zig build test-backend"
            echo "  zig build time-feed"
            echo "  zig build totp"
            echo "  zig build transition"
            echo "  zig build weather"
            echo ""
            
            # Set up pkg-config paths for GTK
            export PKG_CONFIG_PATH="${pkgs.gtk3}/lib/pkgconfig:${pkgs.gtk4}/lib/pkgconfig:$PKG_CONFIG_PATH"
            
            # Set up library paths
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
              pkgs.gtk3
              pkgs.gtk4
              pkgs.libGL
              pkgs.mesa
              pkgs.alsa-lib
            ]}:$LD_LIBRARY_PATH"
          '';
        };
      });
}
