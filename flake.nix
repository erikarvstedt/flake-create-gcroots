{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby.withPackages (p: with p; [ sqlite3 ]);
      in
        {
          packages.default = pkgs.runCommand "flake-create-gcroots" {
            buildInputs = [ ruby ];
          } ''
            dest=$out/bin/flake-create-gcroots
            install -D ${./main.rb} $dest
            patchShebangs $dest
          '';

          devShells.default = pkgs.mkShell {
            buildInputs = [ ruby ];
          };
        }
    );
}
