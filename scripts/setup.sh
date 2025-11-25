# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch|-b)
      FLAKE_BRANCH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: setup [--branch <branch-name>]"
      exit 1
      ;;
  esac
done

# Capture original user's HOME, username, and flake branch before privilege escalation
# Only capture if not already set (to preserve values passed through sudo)
ORIGINAL_HOME="${ORIGINAL_HOME:-$HOME}"
ORIGINAL_USER="${ORIGINAL_USER:-$USER}"
ORIGINAL_FLAKE_BRANCH="${ORIGINAL_FLAKE_BRANCH:-${FLAKE_BRANCH:-}}"

if [ "$EUID" -ne 0 ]; then
  echo "Script is not running as root. Attempting to escalate privileges with sudo..."
  # Pass original HOME, USER, and FLAKE_BRANCH as environment variables to the sudo command
  exec sudo env \
    ORIGINAL_HOME="$ORIGINAL_HOME" \
    ORIGINAL_USER="$ORIGINAL_USER" \
    ORIGINAL_FLAKE_BRANCH="$ORIGINAL_FLAKE_BRANCH" \
    "$0"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo
echo
echo "This is a destructive operation, we will be replacing your existing NixOS system configuration"
echo "with one that uses flakes, based on the productionised DogeboxOS flake."
echo "Continue (y/n)"

read -n 1 -s confirm

if [ "$confirm" != "y" ]; then
  echo "Aborting..."
  exit 1
fi

echo
echo
echo "Decide where you want to store your Dogebox configuration."
echo "Default is ${ORIGINAL_HOME}/data".
read -e -p "Enter path to Dogebox data directory [${ORIGINAL_HOME}/data]: " DOGEBOX_DATA

if [ -z "$DOGEBOX_DATA" ]; then
  DOGEBOX_DATA="${ORIGINAL_HOME}/data"
fi

DOGEBOX_DATA="$(realpath -m "$DOGEBOX_DATA")"
echo "Dogebox data will be stored at: $DOGEBOX_DATA"

echo
echo
echo "We need to know the location of your local dogeboxd repository."
read -e -p "Provide the path to the dogeboxd repository: " DOGEBOXD_PATH
DOGEBOXD_PATH="$(realpath "$DOGEBOXD_PATH" 2>/dev/null)"

# Validate dogeboxd path
if [ ! -d "$DOGEBOXD_PATH" ]; then
  echo "Error: Invalid path for dogeboxd repository: $DOGEBOXD_PATH"
  echo "Directory does not exist. Aborting..."
  exit 1
fi

# Check if flake.nix exists in the dogeboxd path
if [ ! -f "$DOGEBOXD_PATH/flake.nix" ]; then
  echo "Error: No flake.nix found in $DOGEBOXD_PATH"
  echo "This doesn't appear to be a dogeboxd repository. Expected to find 'flake.nix'. Aborting..."
  exit 1
fi

# Verify it's actually the dogeboxd flake by checking for dogeboxd-specific content
if ! grep -q "dogeboxdVendorHash\|packages.*dogeboxd" "$DOGEBOXD_PATH/flake.nix"; then
  echo "Error: The flake.nix at $DOGEBOXD_PATH doesn't appear to be a dogeboxd repository"
  echo "Expected to find 'dogeboxdVendorHash' or 'packages.dogeboxd' in the flake. Aborting..."
  exit 1
fi

echo "✓ Confirmed dogeboxd repository at $DOGEBOXD_PATH"

echo
echo
echo "We're going to move your existing non-flake configuration from /etc/nixos to /etc/nixos-dev"
echo "This means that your current system changes, if any, should still be applied."
echo "And that if you want to modify things, change /etc/nixos-dev, as /etc/nixos will be overriden on rebuilds."
echo "Continue? (y/n)"

read -n 1 -s confirm

if [ "$confirm" != "y" ]; then
  echo "Aborting..."
  exit 1
fi

sudo cp -r /etc/nixos /etc/nixos-dev

echo
echo
echo "Copied /etc/nixos to /etc/nixos-dev"

echo
echo
echo "Do you need a grub bootloader installed?"
echo "If you're running in Orbstack or another fancy VM manager, you probably want to answer NO."
echo "If you're in a fully-fledged VM manager (eg. VirtualBox, VMWare, Proxmox etc), you'll want to answer YES."
echo "Install bootloader? (y/n)"

read -n 1 -s confirm

arch="$(uname -m)"
if [ "$arch" = "aarch64" ]; then
  base_flake="aarch64"
elif [ "$arch" = "x86_64" ]; then
  base_flake="x86_64"
else
  echo "Unsupported architecture: $arch"
  exit 1
fi

if [ "$confirm" = "y" ]; then
  flake="${base_flake}-bootloader"
else
  flake="${base_flake}"
fi

echo
echo
echo "Going to nixos-rebuild and switch to DogeboxOS."
echo "Continue? (y/n)"

read -n 1 -s confirm

if [ "$confirm" != "y" ]; then
  echo "Aborting..."
  exit 1
fi

CONFIG_FILE="/etc/nixos-dev/configuration.nix"
echo "Adding dogeboxd security wrappers to $CONFIG_FILE"

# Check if security wrappers are already present
if grep -q "security.wrappers.dbx" "$CONFIG_FILE"; then
  echo "Security wrappers already present in configuration.nix, skipping..."
else
  # Add 'lib' to the function parameters if not already present
  if ! grep -q "{ config, pkgs, lib" "$CONFIG_FILE"; then
    sudo sed -i.bak 's/{ config, pkgs, modulesPath/{ config, pkgs, lib, modulesPath/g' "$CONFIG_FILE"
    echo "Added 'lib' to configuration.nix imports"
  fi
  
  # Create a temporary file with the security wrappers block
  TEMP_WRAPPERS=$(mktemp)
  cat > "$TEMP_WRAPPERS" << EOF
  security.wrappers.dbx = lib.mkForce {
    source = "DOGEBOXD_PATH_PLACEHOLDER/build/dbx";
    owner = "$ORIGINAL_USER";
    group = "users";
  };
 
  security.wrappers.dogeboxd = lib.mkForce {
    source = "DOGEBOXD_PATH_PLACEHOLDER/build/dogeboxd";
    capabilities = "cap_net_bind_service=+ep";
    owner = "$ORIGINAL_USER";
    group = "users";
  };
 
  security.wrappers._dbxroot = lib.mkForce {
    source = "DOGEBOXD_PATH_PLACEHOLDER/build/_dbxroot";
    owner = "root";
    group = "root";
    setuid = true;
  };

EOF
  
  # Add experimental features if not already present
  if ! grep -q "nix.settings.experimental-features" "$CONFIG_FILE"; then
    cat >> "$TEMP_WRAPPERS" << 'EOF'
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

EOF
    echo "Will add nix experimental features"
  fi
  
  # Replace the placeholder with the actual path
  sed -i.bak "s|DOGEBOXD_PATH_PLACEHOLDER|$DOGEBOXD_PATH|g" "$TEMP_WRAPPERS"
  
  # Insert the wrappers block before the 'imports =' line using awk
  sudo awk -v wrappers="$(cat $TEMP_WRAPPERS)" '
    /imports =/ && !inserted {
      print wrappers
      inserted = 1
    }
    { print }
  ' "$CONFIG_FILE" > "${CONFIG_FILE}.new"
  
  sudo mv "${CONFIG_FILE}.new" "$CONFIG_FILE"
  rm -f "$TEMP_WRAPPERS"
  
  echo "Added security wrappers to configuration.nix"
fi

echo "Setting override for dogebox data directory"
echo $DOGEBOX_DATA > /etc/nixos-dev/datapath

# Build the flake URL with optional branch
if [ -n "$ORIGINAL_FLAKE_BRANCH" ]; then
  FLAKE_URL="github:dogebox-wg/dev/${ORIGINAL_FLAKE_BRANCH}#${flake}"
  echo "Using flake branch: $ORIGINAL_FLAKE_BRANCH"
else
  FLAKE_URL="github:dogebox-wg/dev#${flake}"
fi

# We need to run with `--impure` as we might have files
# outside of our flake that must be included in /etc/nixos-dev.
echo "Running: nixos-rebuild switch --flake $FLAKE_URL -L --impure"
sudo nixos-rebuild switch --flake "$FLAKE_URL" -L --impure

echo
echo
echo "Done."
