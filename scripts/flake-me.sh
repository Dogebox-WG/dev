if [ "$EUID" -ne 0 ]; then
  echo "Script is not running as root. Attempting to escalate privileges with sudo..."
  exec sudo "$0" "$@"
fi

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

if [ "$confirm" = "y" ]; then
  flake="aarch64-bootloader"
else
  flake="aarch64"
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

# We need to run with `--impure` as we might have files
# outside of our flake that must be included in /etc/nixos-dev.
sudo nixos-rebuild switch --flake github:dogebox-wg/dev/flake-me#$flake -L --impure

echo
echo
echo "Done."
