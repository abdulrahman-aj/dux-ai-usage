{
  description = "Dev shell for dux-ai-usage: Python with pytest and ruff.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      each = nixpkgs.lib.genAttrs systems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          devShell = pkgs.mkShell {
            packages = [
              (pkgs.python3.withPackages (ps: [ ps.pytest ]))
              pkgs.ruff
            ];
          };
        });
    in {
      devShells = nixpkgs.lib.mapAttrs (system: v: { default = v.devShell; }) each;
    };
}
