nix develop \
  --override-input dogeboxd "path:$(realpath ../dogeboxd)" \
  --override-input dkm "path:$(realpath ../dkm)" \
  --override-input dpanel "path:$(realpath ../dpanel)"
