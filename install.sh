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
    # Touchscreen input drivers
    xf86-input-libinput
    xf86-input-evdev
    # Safe GPU fallback
    xf86-video-vesa
    # App runtime
    gtk3
    webkit2gtk-4.1
    # Build tools
    gcc
    pkgconf
    python        # needed for source patching step
    git
    base-devel
    make
    # Fonts
    ttf-dejavu
    ttf-liberation
)

info "Installing packages: ${PKGS[*]}"
pacman -S --noconfirm --needed "${PKGS[@]}"
success "All packages installed"

# ── 3. (keyboard is now built into the HTML — no external keyboard needed) ───
info "Skipping external keyboard — using built-in HTML keyboard"
    success "Built-in keyboard ready"

# ── 4. Get the source ─────────────────────────────────────────────────────────
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

# ── 5. (keyboard is HTML-based, no kbd.sh needed)


# ── 6. Patch source — inject HTML on-screen keyboard ─────────────────────────
info "Patching source for on-screen keyboard..."

python3 - "$APP_DIR/pool_webkit.c" << 'PY2'
import sys
src = open(sys.argv[1]).read()

# The keyboard CSS+HTML+JS to inject just before </body>
kbd = """
<style>
#osk {
  display:none;
  position:fixed;
  bottom:0; left:0; right:0;
  height:35vh;
  background:#1a1a1a;
  border-top:2px solid #444;
  z-index:9999;
  display:none;
  flex-direction:column;
  user-select:none;
  -webkit-user-select:none;
}
#osk.osk-visible { display:flex; }
.osk-row {
  display:flex;
  flex:1;
  gap:3px;
  padding:3px;
}
.osk-key {
  flex:1;
  background:#2e2e2e;
  color:#fff;
  border:1px solid #555;
  border-radius:6px;
  font-size:clamp(12px,2.5vw,22px);
  font-family:sans-serif;
  font-weight:600;
  display:flex;
  align-items:center;
  justify-content:center;
  cursor:pointer;
  -webkit-tap-highlight-color:transparent;
  transition:background 0.08s;
}
.osk-key:active, .osk-key.osk-pressed { background:#555; }
.osk-key.osk-wide { flex:2; }
.osk-key.osk-wider { flex:3; }
.osk-key.osk-space { flex:6; background:#333; }
.osk-key.osk-action { background:#c47a00; color:#fff; }
.osk-key.osk-shift-active { background:#1a5c1a; }
</style>

<div id="osk">
  <div class="osk-row" id="osk-r1"></div>
  <div class="osk-row" id="osk-r2"></div>
  <div class="osk-row" id="osk-r3"></div>
  <div class="osk-row" id="osk-r4"></div>
</div>

<script>
(function(){
  var ROWS = [
    ['1','2','3','4','5','6','7','8','9','0',{l:'⌫',a:'backspace',cls:'osk-wide osk-action'}],
    ['q','w','e','r','t','y','u','i','o','p'],
    ['a','s','d','f','g','h','j','k','l',{l:'↵',a:'enter',cls:'osk-wide osk-action'}],
    [{l:'⇧',a:'shift',cls:'osk-wide'},'z','x','c','v','b','n','m',
     {l:'-',a:'-'},{l:'.',a:'.'}]
  ];

  var shifted = false;
  var osk = document.getElementById('osk');
  var activeInput = null;

  function buildRows(){
    ['osk-r1','osk-r2','osk-r3','osk-r4'].forEach(function(id, ri){
      var row = document.getElementById(id);
      row.innerHTML = '';
      ROWS[ri].forEach(function(k){
        var btn = document.createElement('div');
        btn.className = 'osk-key';
        if(typeof k === 'string'){
          btn.textContent = shifted ? k.toUpperCase() : k;
          btn.dataset.char = k;
          btn.dataset.action = 'char';
        } else {
          btn.textContent = k.l;
          btn.dataset.action = k.a;
          if(k.cls) k.cls.split(' ').forEach(function(c){ btn.classList.add(c); });
          if(k.a==='shift' && shifted) btn.classList.add('osk-shift-active');
        }
        // Use pointerdown so we fire before focus changes
        btn.addEventListener('pointerdown', function(e){
          e.preventDefault(); // critical — prevents focus leaving the input
          e.stopPropagation();
          handleKey(btn);
        });
        row.appendChild(btn);
      });
      // Add space bar to last row
      if(ri===3){
        var sp = document.createElement('div');
        sp.className = 'osk-key osk-space';
        sp.textContent = 'SPACE';
        sp.dataset.action = 'space';
        sp.addEventListener('pointerdown', function(e){
          e.preventDefault();
          e.stopPropagation();
          handleKey(sp);
        });
        row.appendChild(sp);
      }
    });
  }

  function handleKey(btn){
    if(!activeInput) return;
    var action = btn.dataset.action;
    if(action === 'char'){
      var ch = shifted ? btn.dataset.char.toUpperCase() : btn.dataset.char;
      insertAtCursor(activeInput, ch);
      if(shifted){ shifted=false; buildRows(); }
    } else if(action === 'backspace'){
      var v=activeInput.value, s=activeInput.selectionStart;
      if(s>0){
        activeInput.value = v.slice(0,s-1)+v.slice(activeInput.selectionEnd);
        activeInput.selectionStart = activeInput.selectionEnd = s-1;
      }
    } else if(action === 'enter'){
      hideOsk();
    } else if(action === 'shift'){
      shifted = !shifted;
      buildRows();
    } else if(action === 'space'){
      insertAtCursor(activeInput, ' ');
    } else {
      insertAtCursor(activeInput, action);
    }
  }

  function insertAtCursor(inp, ch){
    var s=inp.selectionStart, e=inp.selectionEnd;
    inp.value = inp.value.slice(0,s)+ch+inp.value.slice(e);
    inp.selectionStart = inp.selectionEnd = s+ch.length;
  }

  function showOsk(inp){
    activeInput = inp;
    osk.classList.add('osk-visible');
  }

  function hideOsk(){
    osk.classList.remove('osk-visible');
    if(activeInput){ activeInput.blur(); activeInput=null; }
  }

  buildRows();

  // Show when a name input is focused
  document.querySelectorAll('.pname').forEach(function(inp){
    inp.addEventListener('focus', function(){ showOsk(inp); });
  });

  // Hide when tapping outside keyboard and outside inputs
  document.addEventListener('pointerdown', function(e){
    if(!osk.contains(e.target) && !e.target.classList.contains('pname')){
      hideOsk();
    }
  });
})();
</script>
"""

src = src.replace('</body>', kbd + '</body>', 1)
open(sys.argv[1], 'w').write(src)
print("Patched OK")
PY2


# ── 7. Compile ────────────────────────────────────────────────────────────────
info "Compiling..."
gcc "$APP_DIR/pool_webkit.c" \
    -o "$APP_BIN" \
    $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) \
    -O2
success "Compiled → $APP_BIN"

# ── 8. Set ownership ──────────────────────────────────────────────────────────
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod +x "$APP_BIN"

# ── 9. Silence boot (GRUB) ───────────────────────────────────────────────────
info "Silencing boot messages..."
if [[ -f /etc/default/grub ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 rd.systemd.show_status=false vt.global_cursor_default=0"/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
    success "GRUB updated"
else
    warn "/etc/default/grub not found — skipping"
fi

# ── 10. Global xinitrc ────────────────────────────────────────────────────────
info "Writing /etc/X11/xinit/xinitrc..."
cat > /etc/X11/xinit/xinitrc << 'XINITRC'
#!/bin/sh
xset s off
xset -dpms
xset s noblank

OUTPUT=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
MODE=$(xrandr 2>/dev/null | awk "/^$OUTPUT/{found=1; next} found && /^[[:space:]]+[0-9]/{print $1; exit}")
if [ -n "$OUTPUT" ] && [ -n "$MODE" ]; then
    xrandr --output "$OUTPUT" --mode "$MODE" 2>/dev/null
fi

command -v unclutter &>/dev/null && unclutter -idle 1 -root &
XINITRC

echo "exec $APP_BIN" >> /etc/X11/xinit/xinitrc
chmod +x /etc/X11/xinit/xinitrc
success "xinitrc written"

# ── 11. getty autologin ───────────────────────────────────────────────────────
info "Configuring getty autologin for $APP_USER on tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $APP_USER --noclear --skip-login --nonewline --noissue %I \$TERM
EOF
systemctl daemon-reload
success "getty autologin configured"

# ── 12. Silence issue files ───────────────────────────────────────────────────
truncate -s 0 /etc/issue
truncate -s 0 /etc/issue.net 2>/dev/null || true

# ── 13. .bash_profile + .hushlogin ───────────────────────────────────────────
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

# ── 14. Groups ────────────────────────────────────────────────────────────────
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
echo -e "  Keyboard   :  ${CYAN}svkbd (appears when tapping name fields)${NC}"
echo -e "  startx log :  ${CYAN}/tmp/startx.log${NC}"
echo ""
echo -e "  ${YELLOW}Reboot to start the kiosk:${NC}  sudo reboot"
echo -e "  ${YELLOW}Exit the app:${NC}               Press Escape or Q"
echo -e "  ${YELLOW}Disable autologin:${NC}          rm /etc/systemd/system/getty@tty1.service.d/autologin.conf"
echo -e "  ${YELLOW}Switch to another tty:${NC}      Ctrl+Alt+F2"
echo ""
