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
          version = "0.14.0-dev.2577+271452d22";
          
          src = pkgs.fetchurl {
            url = "https://pkg.machengine.org/zig/zig-linux-x86_64-${version}.tar.xz";
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
            echo "  zig build run          - Build and run examples"
            echo "  zig build test         - Run tests"
            echo "  zig build -Dexample=X  - Build specific example"
            echo ""
            echo "Examples:"
            echo "  zig build -Dexample=demo run"
            echo "  zig build -Dexample=calculator run"
            echo "  zig build -Dexample=notepad run"
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

          # Environment variables for development
          CAPY_DEV = "1";
        };
      });
}
