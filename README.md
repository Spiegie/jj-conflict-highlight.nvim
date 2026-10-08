# jj-conflict-highlight.nvim
A plugin to visualise jujutsu conflicts in neovim

This plugin is inspired by [git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim)

This Plugin focuses on the Highlight part. For more functionality use Plugins like [jj.nvim](https://github.com/NicolasGB/jj.nvim)

## Status
Plugin should work for jj default conflict markers (snapshot style), jj diff conflict markers and git style conflict markers

still early work

## Requirements
- neovim >= 0.8
- (optional) [jj](https://jj-vcs.github.io/jj/latest/) to create the conflicts in the first place

## Installation

### Package managers

```lua
-- packer.nvim
use {'Spiegie/jj-conflict-highlight.nvim',
    tag = "*",
    config = function()
        require('jj_conflict_highlight').setup()
    end,
}

-- lazy.nvim
{'Spiegie/jj-conflict-highlight.nvim',
    version = "*",
    config = function()
        require("jj_conflict_highlight").setup({})
    end,
}
```

### NixOS

for nixos you need to build the plugin, because its not in the packages.
reference: [https://ryantm.github.io/nixpkgs/languages-frameworks/vim/](https://ryantm.github.io/nixpkgs/languages-frameworks/vim/)
```nix
{ config, pkgs, ... }:

let
  jj-conflict-highlight-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "jj-conflict-highlight";
    src = pkgs.fetchFromGitHub {
      owner = "Spiegie";
      repo = "jj-conflict-highlight.nvim";
      rev = "main"; # use tags here because main can break. for development you can use the branchname.
      hash = "<hash>"; # get sha by using `nix-prefetch-url https://github.com/Spiegie/jj-conflict-highlight.nvim/<rev> --refresh` <rev> is the branchname or the tag
    };
  };
in
{
  environment.systemPackages = [
    (
      pkgs.neovim.override {
        configure = {
          packages.myPlugins = with pkgs.vimPlugins; {
          start = [
            vim-go # already packaged plugin
            jj-conflict-highlight-nvim # custom package
          ];
          opt = [];
        };
        # ...
      };
     }
    )
  ];
}
```
or in my case (I'm using Home-manager)

```nix
{pkgs, config, ...}:
let
  jj-conflict-highlight-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "jj-conflict-highlight";
    src = pkgs.fetchFromGitHub {
      owner = "Spiegie";
      repo = "jj-conflict-highlight.nvim";
      rev = "main"; # use tags here because main can break. for development you can use the branchname.
      hash = "<hash>"; # get sha by using `nix-prefetch-url https://github.com/Spiegie/jj-conflict-highlight.nvim/<rev> --refresh` <rev> is the branchname or the tag
    };
  };
in
{
  # ...
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraConfig = ''
      luafile ~/.my_config/nvim/require_spiegie.lua
    '';
    plugins = with pkgs.vimPlugins; [
      # ...
      vim-go # already packaged plugin
      jj-conflict-highlight-nvim # custom package
    ];
  };
  # ...
}
```
with this nixos approach you still have to require and setup the plugin. In my case (I use a very unpure approach):
```lua ~/.config/nvim/after/plugins/jj-conflict-highlight.lua
require('jj_conflict_highlight').setup()
```

## Configuration

`setup()` accepts an optional `highlights` table. Each key names a role and
each value the highlight group the plugin should derive its background color
from. The plugin defines one highlight group per role:

| Role      | Highlight group       | Used for                                            | Default source |
|-----------|-----------------------|-----------------------------------------------------|----------------|
| current   | `JjConflictCurrent`   | base and diff regions, git "ours" side              | `DiffText`     |
| incoming  | `JjConflictIncoming`  | git "theirs" side                                   | `DiffAdd`      |
| ancestor  | `JjConflictAncestor`  | all marker lines, git common ancestor                | `DiffChange`   |
| diff      | `JjConflictDiff`      | snapshot regions (the jj conflict sides)           | follows incoming |
| snapshot  | `JjConflictSnapshot` | reserved                                            | `DiffSnapshot` |
| base      | `JjConflictBase`      | reserved                                            | `DiffBase`     |

If a source group has no background color (or does not exist, as with the
`DiffSnapshot` and `DiffBase` defaults), a built-in fallback color is used.
All groups are defined with `default = true`, so a colorscheme can override
them directly, and they are re-derived automatically after a colorscheme
switch.

```lua
require('jj_conflict_highlight').setup({
  highlights = {
    current = 'DiffText',
    incoming = 'DiffAdd',
    ancestor = 'DiffChange',
  },
})
```

The plugin exposes a few functions on top of the automatic highlighting:

- `require('jj_conflict_highlight').highlight(bufnr)` re-parses a buffer and
  (re)applies all conflict highlights.
- `require('jj_conflict_highlight').clear(bufnr)` removes all highlights from
  a buffer. They stay off until the buffer contents change again.

Both default to the current buffer.

## Testing

The test suite runs headlessly with neovim:

```sh
nvim --headless -l tests/test.lua
```

It exits with a non-zero status when a test fails. The parser
(`lua/jj_conflict_highlight/parse.lua`) is pure Lua, so it can also be
exercised with any Lua 5.1 compatible interpreter.

To try the plugin against real conflicts, generate a test repository with
jj (requires the `jj` binary):

```sh
scripts/create_conflict.sh
```

### With the flake

The flake packages the plugin and provides apps to test it:

```sh
nix run           # demo: create a real conflicted jj repo and open it in an
                  # isolated neovim with only this plugin installed
nix run .#test    # run the headless test suite
nix develop       # dev shell with neovim, stylua and jj
```

`nix build .#neovim` builds a neovim wrapper with the plugin installed and
set up, the way a user would get it. The build fails if the plugin cannot be
required (`nvimRequireCheck`).

Note that flakes only see files tracked by git: `git add` new files before
building, and expect a `dirty tree` warning while changes are uncommitted.

## 🤝 Contributing

Thanks for your interest in contributing! This project is still in its early stages, and as a solo and first time maintainer I don't always have a lot of time to work on it. That said, contributions of all kinds are very welcome.

### ✔️ How You Can Help

- Open issues for bugs, suggestions, improvements, or questions
- Submit pull requests for fixes, enhancements, or documentation updates
- Share ideas for future features or project direction

### 📬 Response Time

Please note that my availability may be limited. I may not be able to respond immediately, but I will read everything and appreciate all contributions. 

### 🌟 Code of Conduct

Please be respectful, constructive, and kind.
