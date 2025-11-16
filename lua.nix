
with import <nixpkgs-unstable> {};

stdenv.mkDerivation {
  name = "lua-env";
  nativeBuildInputs = [
    lua
  ];
  buildInputs = [
  ];
  
}
    
