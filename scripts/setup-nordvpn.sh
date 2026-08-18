#!/usr/bin/env bash

# Guided NordVPN CLI setup for the provider panel. Keep privileged package and service
# changes visible in a terminal; the QML button only launches this script.

set -u

heading() {
    printf '\n\033[1m%s\033[0m\n' "$1"
}

fail() {
    printf '\nError: %s\n' "$1" >&2
    exit 1
}

heading "NordVPN setup"

if command -v nordvpn >/dev/null 2>&1; then
    printf 'The NordVPN CLI is already installed. Return to Ambxst and press Refresh.\n'
    exit 0
fi

if [[ ! -r /etc/os-release ]]; then
    fail "Could not identify this Linux distribution."
fi

# shellcheck disable=SC1091
source /etc/os-release
distribution="${ID:-unknown} ${ID_LIKE:-}"

if [[ " $distribution " != *" arch "* && " $distribution " != *" cachyos "* ]]; then
    fail "The guided installer currently supports Arch-based systems only. See https://nordvpn.com/download/linux/ for this distribution."
fi

aur_helper=""
for candidate in paru yay; do
    if command -v "$candidate" >/dev/null 2>&1; then
        aur_helper="$candidate"
        break
    fi
done

[[ -n "$aur_helper" ]] || fail "Install an AUR helper (paru or yay), then try again."

printf 'This will:\n'
printf '  • install the nordvpn-bin AUR package with %s\n' "$aur_helper"
printf '  • enable and start nordvpnd\n'
printf '  • add %s to the nordvpn group\n' "$USER"
printf '\nYour password may be requested. No NordVPN credentials are handled by this script.\n\n'
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { printf 'Cancelled.\n'; exit 0; }

heading "Installing NordVPN"
"$aur_helper" -S --needed nordvpn-bin || fail "The nordvpn-bin package did not install."

heading "Enabling the NordVPN service"
sudo systemctl enable --now nordvpnd || fail "Could not enable and start nordvpnd."

heading "Granting access to NordVPN"
sudo usermod -aG nordvpn "$USER" || fail "Could not add $USER to the nordvpn group."

heading "Installation complete"
printf 'A new login session is required before Ambxst can use the nordvpn group.\n'
printf 'After signing back in, open VPN → NordVPN and press Log in. Ambxst will open\n'
printf 'NordVPN authentication in your browser; you will not need to copy commands.\n\n'
read -r -p "Reboot now? [y/N] " reboot_answer
if [[ "$reboot_answer" =~ ^[Yy]$ ]]; then
    systemctl reboot
else
    printf 'Reboot or log out when convenient, then finish login from the NordVPN panel.\n'
fi
