#!/usr/bin/env bash
# =============================================================================
# 8-Ball Pool Tracker — Kiosk Installer
# Arch Linux bare-metal: installs minimal X, compiles the app, boots straight in
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Must run as root ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run this script as root (sudo ./install_pool_kiosk.sh)"

# ── Config ────────────────────────────────────────────────────────────────────
APP_USER="${SUDO_USER:-pool}"          # user that will run the kiosk session
APP_DIR="/opt/pool_tracker"
APP_BIN="$APP_DIR/pool_tracker"
SRC_URL="https://raw.githubusercontent.com/InsaneGitUser/pool-score-tracker/main/pool_webkit.c"
# If you don't have a URL yet, place pool_webkit.c beside this script instead.
LOCAL_SRC="$(dirname "$(realpath "$0")")/pool_webkit.c"

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   8-Ball Pool Tracker — Kiosk Installer  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}\n"

# ── 1. Ensure the kiosk user exists ──────────────────────────────────────────
info "Checking kiosk user: $APP_USER"
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$APP_USER"
    success "Created user $APP_USER"
else
    success "User $APP_USER already exists"
fi

# ── 2. Sync pacman & install packages ────────────────────────────────────────
info "Syncing package databases..."
pacman -Sy --noconfirm

PKGS=(
    # Minimal X server (no display manager, no desktop)
    xorg-server
    xorg-xinit
    xorg-xrandr          # optional: rotate/resolution tweaks at startup
    xf86-video-vesa      # safe fallback GPU driver (works on anything)

    # GTK + WebKitGTK (the app's runtime)
    gtk3
    webkit2gtk-4.1

    # Build tools
    gcc
    pkgconf

    # Fonts (so the app doesn't look broken)
    ttf-dejavu
    ttf-liberation
)

info "Installing packages: ${PKGS[*]}"
pacman -S --noconfirm --needed "${PKGS[@]}"
success "All packages installed"

# ── 3. Get the source ─────────────────────────────────────────────────────────
mkdir -p "$APP_DIR"
info "Fetching pool_webkit.c..."

if [[ -f "$LOCAL_SRC" ]]; then
    cp "$LOCAL_SRC" "$APP_DIR/pool_webkit.c"
    success "Copied local source: $LOCAL_SRC"
elif curl -fsSL "$SRC_URL" -o "$APP_DIR/pool_webkit.c" 2>/dev/null; then
    success "Downloaded source from $SRC_URL"
else
    die "No source found. Either:\n  • Put pool_webkit.c next to this script, OR\n  • Set SRC_URL at the top of this script to your raw file URL"
fi

# ── 4. Compile ────────────────────────────────────────────────────────────────
info "Compiling..."
gcc "$APP_DIR/pool_webkit.c" \
    -o "$APP_BIN" \
    $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) \
    -O2
success "Compiled → $APP_BIN"

# ── 5. Set ownership ──────────────────────────────────────────────────────────
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod +x "$APP_BIN"

# ── 6. Global xinitrc — just launch the pool app, nothing else ───────────────
info "Writing /etc/X11/xinit/xinitrc..."
cat > /etc/X11/xinit/xinitrc << EOF
#!/bin/sh
# Kiosk xinitrc — starts the pool tracker and exits X when it closes

# Disable screen blanking / DPMS
xset s off
xset -dpms
xset s noblank

# Hide the mouse cursor after 1 second of inactivity (needs unclutter if installed)
command -v unclutter &>/dev/null && unclutter -idle 1 -root &

# Launch the app — X exits when this process exits
exec $APP_BIN
EOF
chmod +x /etc/X11/xinit/xinitrc
success "xinitrc written"

# ── 7. systemd service — startx as the kiosk user on boot ────────────────────
info "Writing systemd service..."
cat > /etc/systemd/system/pool-kiosk.service << EOF
[Unit]
Description=8-Ball Pool Tracker Kiosk
After=systemd-user-sessions.service
After=network.target

[Service]
Type=simple
User=$APP_USER
PAMName=login
Environment=XDG_SESSION_TYPE=x11
Environment=DISPLAY=:0

# startx wraps xinit which reads /etc/X11/xinit/xinitrc
ExecStart=/usr/bin/startx -- :0 vt1

# Restart automatically if the app crashes (remove if you'd rather it stays off)
Restart=on-failure
RestartSec=3

# Give the GPU a moment on first boot
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pool-kiosk.service
success "pool-kiosk.service enabled"

# ── 8. Disable getty on tty1 so our service owns it cleanly ──────────────────
info "Masking getty@tty1 (our service owns tty1)..."
systemctl mask getty@tty1.service
success "getty@tty1 masked"

# ── 9. Allow the kiosk user to run startx without a tty login ────────────────
# startx/Xorg needs the user to be in the 'input' and 'video' groups
info "Adding $APP_USER to input and video groups..."
usermod -aG input,video "$APP_USER"
success "Groups updated"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Installation complete!${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  App binary :  ${CYAN}$APP_BIN${NC}"
echo -e "  Kiosk user :  ${CYAN}$APP_USER${NC}"
echo -e "  Service    :  ${CYAN}pool-kiosk.service${NC}"
echo -e "  xinitrc    :  ${CYAN}/etc/X11/xinit/xinitrc${NC}"
echo ""
echo -e "  ${YELLOW}Reboot to start the kiosk:${NC}  sudo reboot"
echo -e "  ${YELLOW}Stop the kiosk:${NC}             sudo systemctl stop pool-kiosk"
echo -e "  ${YELLOW}Disable on boot:${NC}            sudo systemctl disable pool-kiosk"
echo -e "  ${YELLOW}Exit the app:${NC}               Press Escape or Q"
echo ""
