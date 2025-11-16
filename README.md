# jj-conflict.nvim
A plugin to visualise jujutsu conflicts in neovim

This plugin is inspired by [git-conflicts.nvim](https://github.com/akinsho/git-conflict.nvim)

## Installation

### Packagememanagers

```lua
-- packer.nvim
use {'Spiegie/jj-conflict.nvim', tag = "*", config = function()
  require('jj-conflict').setup()
end}

-- lazy.nvim
{'Spiegie/jj-conflict.nvim', version = "*", config = true}
```

### NixOS

for nixos you need to build the plugin, because its not in the packages.
reference: [https://ryantm.github.io/nixpkgs/languages-frameworks/vim/](https://ryantm.github.io/nixpkgs/languages-frameworks/vim/)
```nix
{ config, pkgs, ... }:

let
  jj-conflict-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "jj-conflict";
    src = pkgs.fetchFromGitHub {
      owner = "Spiegie";
      repo = "jj-conflict.nvim";
      rev = "main"; # use tags here because main can break. for development you can use the branchname.
      hash = "<hash>"; # get sha by using `nix-prefetch-url https://github.com/Spiegie/jj-conflict.nvim/<rev>` <rev> is the branchname or the tag
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
            jj-conflict-nvim # custom package
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
{pkgs, lib, config, ...}:
let
  jj-conflict-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "jj-conflict";
    src = pkgs.fetchFromGitHub {
      owner = "Spiegie";
      repo = "jj-conflict.nvim";
      rev = "main"; # use tags here because main can break. for development you can use the branchname.
      hash = "<hash>"; # get sha by using `nix-prefetch-url https://github.com/Spiegie/jj-conflict.nvim/<rev>` <rev> is the branchname or the tag
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
      jj-conflict-nvim # custom package
    ];
  };
  # ...
}
```
with this nixos approach you still have to require and setup the plugin. In my case (I use a very unpure approach):
```lua ~/.config/nvim/after/plugins/jj-conflict.lua
require('jj-conflict').setup()
```

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
