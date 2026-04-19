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
    xorg-xrandr
    xf86-video-vesa      # safe fallback GPU driver (works on bare metal + VMs)

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

# ── 6. Global xinitrc — auto-detect resolution, launch app fullscreen ─────────
info "Writing /etc/X11/xinit/xinitrc..."
cat > /etc/X11/xinit/xinitrc << 'XINITRC'
#!/bin/sh
# Kiosk xinitrc — auto-detects display, forces fullscreen, launches pool tracker

# Disable screen blanking / DPMS
xset s off
xset -dpms
xset s noblank
# Auto-detect connected output and its highest available resolution,
# then apply it. Works on bare metal, VirtualBox, QEMU/KVM, etc.
OUTPUT=$(xrandr | awk '/ connected/{print $1; exit}')
MODE=$(xrandr | awk "/^$OUTPUT/{found=1; next} found && /^[[:space:]]+[0-9]/{print $1; exit}")
if [ -n "$OUTPUT" ] && [ -n "$MODE" ]; then
    xrandr --output "$OUTPUT" --mode "$MODE"
fi

# Hide the mouse cursor after 1 second of inactivity (needs unclutter if installed)
command -v unclutter &>/dev/null && unclutter -idle 1 -root &

# Launch the app — X exits when this process exits
XINITRC

# Append the binary path (it contains a variable so can't be in single-quoted heredoc)
echo "exec $APP_BIN" >> /etc/X11/xinit/xinitrc

chmod +x /etc/X11/xinit/xinitrc
success "xinitrc written"

# ── 7. getty autologin on tty1 — let systemd own tty1 normally ───────────────
info "Configuring getty autologin for $APP_USER on tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $APP_USER --noclear %I \$TERM
EOF
systemctl daemon-reload
success "getty autologin configured"

# ── 8. .bash_profile — startx fires on tty1 login, not SSH/other ttys ────────
info "Writing $APP_USER .bash_profile..."
cat > /home/$APP_USER/.bash_profile << 'PROFILE'
# Auto-start X only on tty1 (not SSH, not tty2, etc.)
if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    exec startx
fi
PROFILE
chown "$APP_USER:$APP_USER" /home/$APP_USER/.bash_profile
success ".bash_profile written"

# ── 9. Allow the kiosk user to run startx ────────────────────────────────────
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
echo -e "  xinitrc    :  ${CYAN}/etc/X11/xinit/xinitrc${NC}"
echo ""
echo -e "  ${YELLOW}Reboot to start the kiosk:${NC}  sudo reboot"
echo -e "  ${YELLOW}Exit the app:${NC}               Press Escape or Q  (drops back to tty1)"
echo -e "  ${YELLOW}Disable autologin:${NC}          rm /etc/systemd/system/getty@tty1.service.d/autologin.conf"
echo -e "  ${YELLOW}Switch to another tty:${NC}      Ctrl+Alt+F2"
echo ""
