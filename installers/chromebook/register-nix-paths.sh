nix-store --load-db < /nix-path-registration
touch /etc/NIXOS
nix-env -p /nix/var/nix/profiles/system --set /run/current-system
rm /nix-path-registration
