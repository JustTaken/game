{
  description = "Vulkan application in zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        glfw
        kakoune
        lldb
        vulkan-loader
        vulkan-headers
        pkg-config
        shaderc
        emacs29

        (callPackage ./nix-builds/zig.nix {})
      ];
    };
  };
}
