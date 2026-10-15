{
  description = "jj-conflict-highlight.nvim - highlight jujutsu conflicts in neovim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          jj-conflict-highlight-nvim = pkgs.vimUtils.buildVimPlugin {
            pname = "jj-conflict-highlight.nvim";
            version = "unstable";
            src = self;
            # makes the build fail if the plugin cannot be required
            nvimRequireCheck = "jj_conflict_highlight";
          };
          default = self.packages.${system}.jj-conflict-highlight-nvim;
        });

      apps = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          # Test drive: `nix run .#` creates a jj repository with real
          # conflicts and opens it in an isolated Neovim with only
          # jj-conflict-highlight loaded (no user config, no other plugins).
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "jj-conflict-highlight-demo" ''
              set -eu
              export PATH="${pkgs.lib.getBin pkgs.jujutsu}/bin:$PATH"
              demo="''${XDG_RUNTIME_DIR:-/tmp}/jj-conflict-highlight-demo"
              rm -rf "$demo"
              mkdir -p "$demo"
              cd "$demo"
              sh ${self}/scripts/create_conflict.sh
              exec ${pkgs.lib.getExe pkgs.neovim} --noplugin \
                -u ${pkgs.writeText "jj-conflict-highlight-init.lua" ''
                  vim.opt.rtp:prepend("${self.packages.${system}.jj-conflict-highlight-nvim}")
                  require("jj_conflict_highlight").setup({})
                ''} testrepo/fruits.txt
            ''}";
          };

          # Run the headless test suite against the flake source.
          test = {
            type = "app";
            program = "${pkgs.writeShellScript "jj-conflict-highlight-test" ''
              exec ${pkgs.lib.getExe pkgs.neovim} --headless -l ${self}/tests/test.lua
            ''}";
          };
        });

      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              lua-language-server
              stylua
              neovim # run tests: nvim --headless -l tests/test.lua
              jujutsu # jj: create a test repo with conflicts: scripts/create_conflict.sh
            ];
          };
        });
    };
}
