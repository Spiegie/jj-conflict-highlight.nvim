{
  description = "jj-conflict-highlight.nvim - highlight jujutsu conflicts in neovim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The plugin built from this repository, the way a user would install it.
      # nvimRequireCheck makes the build fail if the plugin cannot be required.
      plugin = pkgs.vimUtils.buildVimPlugin {
        pname = "jj-conflict-highlight.nvim";
        version = self.shortRev or "dev";
        src = self;
        nvimRequireCheck = "jj_conflict_highlight";
      };

      # Neovim with only this plugin installed and set up.
      neovim = pkgs.wrapNeovim pkgs.neovim-unwrapped {
        configure = {
          customRC = "lua require('jj_conflict_highlight').setup()";
          packages.jjConflictHighlight.start = [ plugin ];
        };
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          lua
          neovim # run tests: nvim --headless -l tests/test.lua
          stylua
          jj # create a test repo with conflicts: scripts/create_conflict.sh
        ];
        shellHook = ''
          echo "jj-conflict-highlight.nvim"
          echo "  run tests:  nvim --headless -l tests/test.lua"
          echo "  try plugin: nix run .#demo"
        '';
      };

      packages.${system} = {
        default = neovim;
        inherit neovim;
      };

      apps.${system} = {
        default = self.apps.${system}.demo;

        # Run the headless test suite against the flake source.
        test = {
          type = "app";
          program = "${pkgs.writeShellScript "jj-conflict-highlight-test" ''
            exec ${pkgs.neovim}/bin/nvim --headless -l ${self}/tests/test.lua
          ''}";
        };

        # Create a real conflicted jj repository and open it in neovim with
        # the plugin installed. Neovim runs isolated from the user's config
        # so only this plugin is loaded.
        demo = {
          type = "app";
          program = "${pkgs.writeShellScript "jj-conflict-highlight-demo" ''
            set -eu
            export PATH="${pkgs.jj}/bin:$PATH"
            demo="''${XDG_RUNTIME_DIR:-/tmp}/jj-conflict-highlight-demo"
            rm -rf "$demo"
            mkdir -p "$demo"
            cd "$demo"
            sh ${self}/scripts/create_conflict.sh
            export XDG_CONFIG_HOME="$demo/xdg/config"
            export XDG_DATA_HOME="$demo/xdg/data"
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
            exec ${neovim}/bin/nvim testrepo/fruits.txt
          ''}";
        };
      };
    };
}
