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
APP_USER="${SUDO_USER:-pool}"
APP_DIR="/opt/pool_tracker"
APP_BIN="$APP_DIR/pool_tracker"
SRC_URL="https://raw.githubusercontent.com/InsaneGitUser/pool-score-tracker/main/pool_webkit.c"
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
    # Minimal X server
    xorg-server
    xorg-xinit
    xorg-xrandr

    # Input drivers — both for maximum touchscreen compatibility
    xf86-input-libinput   # modern capacitive screens (recommended)
    xf86-input-evdev      # older/resistive screens fallback

    # Safe fallback GPU driver
    xf86-video-vesa

    # GTK + WebKitGTK runtime
    gtk3
    webkit2gtk-4.1

    # Build tools
    gcc
    pkgconf

    # On-screen keyboard (kiosk-friendly, no desktop needed)
    wvkbd

    # Fonts
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

# ── 4. Patch the HTML to add on-screen keyboard trigger ───────────────────────
# We inject JS into the C source that calls a Python helper script via
# webkit's custom URI scheme when a name input is focused/blurred.
# The helper launches/kills wvkbd-mobintl on the host side.
info "Patching source for on-screen keyboard..."

# Write the keyboard launcher helper
cat > "$APP_DIR/kbd.sh" << 'KBD'
#!/bin/bash
# kbd.sh show|hide — manages wvkbd for the kiosk
PIDFILE=/tmp/wvkbd.pid

show() {
    if ! kill -0 "$(cat $PIDFILE 2>/dev/null)" 2>/dev/null; then
        DISPLAY=:0 wvkbd-mobintl --hidden --landscape -L 280 &
        echo $! > $PIDFILE
    fi
}

hide() {
    if kill -0 "$(cat $PIDFILE 2>/dev/null)" 2>/dev/null; then
        kill "$(cat $PIDFILE)" 2>/dev/null
        rm -f $PIDFILE
    fi
}

case "$1" in
    show) show ;;
    hide) hide ;;
esac
KBD
chmod +x "$APP_DIR/kbd.sh"

# ── 5. Compile ────────────────────────────────────────────────────────────────
info "Compiling..."
gcc "$APP_DIR/pool_webkit.c" \
    -o "$APP_BIN" \
    $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) \
    -O2
success "Compiled → $APP_BIN"

# ── 6. Set ownership ──────────────────────────────────────────────────────────
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod +x "$APP_BIN"

# ── 7. Silence boot (GRUB) ───────────────────────────────────────────────────
info "Silencing boot messages in /etc/default/grub..."
if [[ -f /etc/default/grub ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 rd.systemd.show_status=false vt.global_cursor_default=0"/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
    success "GRUB updated — boot will be silent"
else
    warn "/etc/default/grub not found — skipping (systemd-boot?)"
fi

# ── 8. Global xinitrc ────────────────────────────────────────────────────────
info "Writing /etc/X11/xinit/xinitrc..."
cat > /etc/X11/xinit/xinitrc << 'XINITRC'
#!/bin/sh
# Kiosk xinitrc

xset s off
xset -dpms
xset s noblank

# Auto-detect and apply highest resolution
OUTPUT=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
MODE=$(xrandr 2>/dev/null | awk "/^$OUTPUT/{found=1; next} found && /^[[:space:]]+[0-9]/{print $1; exit}")
if [ -n "$OUTPUT" ] && [ -n "$MODE" ]; then
    xrandr --output "$OUTPUT" --mode "$MODE" 2>/dev/null
fi

# Hide cursor after 1s idle
command -v unclutter &>/dev/null && unclutter -idle 1 -root &

XINITRC

echo "exec $APP_BIN" >> /etc/X11/xinit/xinitrc
chmod +x /etc/X11/xinit/xinitrc
success "xinitrc written"

# ── 9. getty autologin ────────────────────────────────────────────────────────
info "Configuring getty autologin for $APP_USER on tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $APP_USER --noclear --skip-login --nonewline --noissue %I \$TERM
EOF
systemctl daemon-reload
success "getty autologin configured"

# ── 10. Silence issue files ───────────────────────────────────────────────────
truncate -s 0 /etc/issue
truncate -s 0 /etc/issue.net 2>/dev/null || true
success "/etc/issue cleared"

# ── 11. .bash_profile ─────────────────────────────────────────────────────────
info "Writing $APP_USER .bash_profile..."
cat > /home/$APP_USER/.bash_profile << 'PROFILE'
if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    clear
    exec startx >/tmp/startx.log 2>&1
fi
PROFILE
chown "$APP_USER:$APP_USER" /home/$APP_USER/.bash_profile

touch /home/$APP_USER/.hushlogin
chown "$APP_USER:$APP_USER" /home/$APP_USER/.hushlogin
success ".bash_profile + .hushlogin written"

# ── 12. WebKit custom URI handler wrapper ─────────────────────────────────────
# The app calls pool://keyboard/show and pool://keyboard/hide via JS
# We handle this by patching the C source at compile time with a
# URI scheme handler that shells out to kbd.sh.
# Since the binary is already compiled above we need to inject this
# into the source BEFORE compile. Re-patch and recompile now.
info "Injecting keyboard URI handler into source and recompiling..."

# We insert a uri-scheme handler registration and callback into the C source.
# Strategy: find the line where we call webkit_web_view_load_html and insert before it.
HANDLER_CODE=$(cat << 'CEOF'

/* ── On-screen keyboard via custom URI scheme pool://keyboard/show|hide ── */
static void
kbd_uri_cb(WebKitURISchemeRequest *req, gpointer data)
{
    (void)data;
    const char *uri = webkit_uri_scheme_request_get_uri(req);
    /* uri is like "pool://keyboard/show" or "pool://keyboard/hide" */
    const char *action = strrchr(uri, '/');
    if (action) {
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "/opt/pool_tracker/kbd.sh %s &", action + 1);
        system(cmd);
    }
    /* Return empty response so WebKit doesn't show an error */
    GInputStream *stream = g_memory_input_stream_new_from_data("", 0, NULL);
    webkit_uri_scheme_request_finish(req, stream, 0, "text/plain");
    g_object_unref(stream);
}

CEOF
)

# Inject handler code before main, register scheme inside main
python3 - "$APP_DIR/pool_webkit.c" << 'PY'
import sys, re

src = open(sys.argv[1]).read()

handler = """
/* ── On-screen keyboard via custom URI scheme pool://keyboard/show|hide ── */
static void
kbd_uri_cb(WebKitURISchemeRequest *req, gpointer data)
{
    (void)data;
    const char *uri = webkit_uri_scheme_request_get_uri(req);
    const char *action = strrchr(uri, '/');
    if (action) {
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "/opt/pool_tracker/kbd.sh %s &", action + 1);
        system(cmd);
    }
    GInputStream *stream = g_memory_input_stream_new_from_data("", 0, NULL);
    webkit_uri_scheme_request_finish(req, stream, 0, "text/plain");
    g_object_unref(stream);
}
"""

register = '    /* Register pool:// URI scheme for on-screen keyboard */\n    WebKitWebContext *wk_ctx = webkit_web_view_get_context(webview);\n    webkit_web_context_register_uri_scheme(wk_ctx, "pool", kbd_uri_cb, NULL, NULL);\n\n'

# Insert handler function before on_key_press or main
src = src.replace('/* ── Key handler', handler + '\n/* ── Key handler', 1)

# Insert registration just before webkit_web_view_load_html
src = src.replace('    webkit_web_view_load_html(', register + '    webkit_web_view_load_html(', 1)

# Add #include <stdlib.h> for system() after the webkit include
src = src.replace('#include <webkit2/webkit2.h>', '#include <webkit2/webkit2.h>\n#include <stdlib.h>', 1)

open(sys.argv[1], 'w').write(src)
print("Patched OK")
PY

# Also inject the JS focus/blur listeners into the HTML string in the C source
python3 - "$APP_DIR/pool_webkit.c" << 'PY'
import sys

src = open(sys.argv[1]).read()

# JS to inject — listens for focus/blur on .pname inputs and calls pool://keyboard/show|hide
js = """
<script>
// On-screen keyboard trigger
document.querySelectorAll('.pname').forEach(function(inp) {
  inp.addEventListener('focus', function() {
    fetch('pool://keyboard/show').catch(function(){});
  });
  inp.addEventListener('blur', function() {
    setTimeout(function() { fetch('pool://keyboard/hide').catch(function(){}); }, 200);
  });
});
</script>
"""

# Insert just before closing </body>
src = src.replace('</body>', js + '</body>', 1)
open(sys.argv[1], 'w').write(src)
print("JS injected OK")
PY

# Recompile with the patched source
gcc "$APP_DIR/pool_webkit.c" \
    -o "$APP_BIN" \
    $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) \
    -O2
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod +x "$APP_BIN"
success "Recompiled with keyboard support"

# ── 13. Groups ────────────────────────────────────────────────────────────────
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
echo -e "  Keyboard   :  ${CYAN}wvkbd-mobintl (appears on name field focus)${NC}"
echo -e "  startx log :  ${CYAN}/tmp/startx.log${NC}"
echo ""
echo -e "  ${YELLOW}Reboot to start the kiosk:${NC}  sudo reboot"
echo -e "  ${YELLOW}Exit the app:${NC}               Press Escape or Q"
echo -e "  ${YELLOW}Disable autologin:${NC}          rm /etc/systemd/system/getty@tty1.service.d/autologin.conf"
echo -e "  ${YELLOW}Switch to another tty:${NC}      Ctrl+Alt+F2"
echo ""
