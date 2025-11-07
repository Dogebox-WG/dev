# TODO:
# - check and update configuration.nix to include required stanzas

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

# Determine if we're being run from inside a cloned version
# of the dev flake, or if we're running from a github: remote flake.
# TODO: Be smarter about this.
IS_CWD_GIT_REPO=$(git rev-parse --is-inside-work-tree 2>/dev/null)

if [ "$IS_CWD_GIT_REPO" == "true" ]; then
  # Assume we're inside a cloned version of this repo.
  pushd ..
fi

check_and_clone dogeboxd
check_and_clone dkm
check_and_clone dpanel

if [ "$IS_CWD_GIT_REPO" == "true" ]; then
  popd
fi

