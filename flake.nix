{
  description = "Dialect: a Scheme programming environment for Apple Watch";

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
    # Apple Silicon only. Building for watchOS needs Xcode, so there is no Linux devshell worth
    # having, and nixpkgs builds xcodegen for aarch64-darwin alone. Claiming more systems than
    # this only fails `nix flake check` on the ones that are not real.
    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Swift tooling (swift-format, clang-format, xcodebuild, simctl) deliberately
        # comes from the active Xcode toolchain rather than from nixpkgs as it has to
        # match the SDK we build against, and the Makefile resolves it via `xcrun`.
        devShells.default = pkgs.mkShell {
          name = "dialect";
          packages = with pkgs; [
            xcodegen # Generates Dialect.xcodeproj from project.yml
            python3 # Runs utils/reflow-comments
            ruff # Formats and lints utils/reflow-comments
            dprint # Markdown, JSON, TOML, YAML
            nixfmt # Nix
            shfmt # Shell
            shellcheck # Lints shell, standalone and inside workflow run: blocks
            actionlint # Lints GitHub Actions workflows
            gnumake
          ];
        };

        formatter = pkgs.nixfmt;
      }
    );
}
