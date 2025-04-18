check_and_clone() {
  if [ ! -d "$1" ]; then
    echo "$1 missing, cloning..."
    git clone https://github.com/dogebox-wg/$1.git
  else
    echo "$1 already exists, skipping"
  fi
}

if [ ! -f /etc/nixos/configuration.nix ]; then
  echo "This repository must be used inside a NixOS environment"
  exit 1
fi

pushd ..
  check_and_clone dogeboxd
  check_and_clone dkm
  check_and_clone dpanel
popd

# TODO:
# - check and update configuration.nix to include required stanzas
