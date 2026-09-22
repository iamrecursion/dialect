{
  description = "Dialect — a Scheme programming environment for Apple Watch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Swift tooling (swift-format, clang-format, xcodebuild, simctl) deliberately
        # comes from the active Xcode toolchain rather than from nixpkgs: it has to
        # match the SDK we build against, and the Makefile resolves it via `xcrun`.
        devShells.default = pkgs.mkShell {
          name = "dialect";
          packages = with pkgs; [
            dprint # Markdown, JSON, TOML, YAML
            nixfmt # Nix
            shfmt # Shell
            gnumake
          ];
        };

        formatter = pkgs.nixfmt;
      }
    );
}
