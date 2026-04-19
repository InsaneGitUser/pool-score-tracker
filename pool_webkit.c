/*
 * 8-Ball Pool Tracker — Native Linux App (WebKitGTK)
 *
 * This wraps the original HTML/CSS/JS in a native GTK window using
 * WebKitGTK, giving pixel-perfect rendering with zero styling changes.
 *
 * Build:
 *   gcc pool_webkit.c -o pool_tracker \
 *       $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) \
 *       && ./pool_tracker
 *
 * Dependencies (Debian/Ubuntu):
 *   sudo apt install libwebkit2gtk-4.1-dev
 *
 * Dependencies (Fedora/RHEL):
 *   sudo dnf install webkit2gtk4.1-devel
 *
 * Dependencies (Arch):
 *   sudo pacman -S webkit2gtk
 */

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

/* ── The original HTML app, embedded as a C string literal ── */
static const char *HTML = R"HTML(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>8-Ball Pool Tracker</title>
<link href="https://fonts.googleapis.com/css2?family=Oswald:wght@400;600;700&family=Rajdhani:wght@500;700&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    min-height: 100vh;
    background: #1a1a2e;
    background-image:
      radial-gradient(ellipse at 20% 50%, rgba(14, 107, 53, 0.15) 0%, transparent 60%),
      radial-gradient(ellipse at 80% 50%, rgba(14, 107, 53, 0.15) 0%, transparent 60%);
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: 'Rajdhani', sans-serif;
    padding: 20px;
  }

  .table {
    background: #0d5c2a;
    border-radius: 22px;
    padding: 20px 18px 18px;
    border: 8px solid #5a3208;
    outline: 4px solid #9a6220;
    box-shadow: 0 0 0 2px #3a1f00, 0 30px 80px rgba(0,0,0,0.7);
    width: 100%;
    max-width: 680px;
    position: relative;
  }

  .table::before {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: 14px;
    background-image: repeating-linear-gradient(
      45deg,
      rgba(255,255,255,0.012) 0px,
      rgba(255,255,255,0.012) 1px,
      transparent 1px,
      transparent 8px
    );
    pointer-events: none;
  }

  .title {
    text-align: center;
    font-family: 'Oswald', sans-serif;
    color: #d4af6a;
    font-size: 26px;
    font-weight: 700;
    letter-spacing: 6px;
    margin-bottom: 16px;
    text-shadow: 0 2px 8px rgba(0,0,0,0.8);
  }

  .board {
    display: grid;
    grid-template-columns: 1fr 64px 1fr;
    gap: 10px;
    align-items: start;
    position: relative;
  }

  .pcard {
    background: rgba(0,0,0,0.45);
    border-radius: 14px;
    padding: 12px 10px 14px;
    border: 1px solid rgba(255,255,255,0.08);
  }

  .name-row {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 8px;
  }
  
  #eb8slot {
    cursor: default;
  }

  .pname {
    flex: 1;
    background: transparent;
    border: none;
    border-bottom: 1.5px solid rgba(255,255,255,0.25);
    color: #fff;
    font-size: 15px;
    font-weight: 700;
    font-family: 'Oswald', sans-serif;
    letter-spacing: 1px;
    outline: none;
    padding: 2px 0;
  }
  .pname::placeholder { color: rgba(255,255,255,0.28); }

  .tbtn {
    font-size: 10px;
    padding: 3px 9px;
    border-radius: 20px;
    border: 1px solid rgba(255,255,255,0.25);
    cursor: pointer;
    font-weight: 700;
    white-space: nowrap;
    font-family: 'Rajdhani', sans-serif;
    transition: all 0.15s;
  }
  .t-none { background: rgba(255,255,255,0.07); color: rgba(255,255,255,0.4); }
  .t-solid { background: #d4a017; color: #2a1800; border-color: #a07010; }
  .t-stripe { background: #e8e8e8; color: #222; border-color: #aaa; }

  .score-row {
    text-align: center;
    margin-bottom: 10px;
  }
  .score-num {
    font-family: 'Oswald', sans-serif;
    font-size: 36px;
    font-weight: 700;
    color: #ffd700;
    line-height: 1;
    text-shadow: 0 0 12px rgba(255,215,0,0.5);
  }
  .score-lbl {
    font-size: 10px;
    color: rgba(255,255,255,0.3);
    letter-spacing: 1px;
  }

  .balls-label {
    font-size: 10px;
    color: rgba(255,255,255,0.28);
    margin-bottom: 6px;
    letter-spacing: 0.5px;
  }

  .tray {
    position: relative;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .tray-bg {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    height: 38px;
    width: 100%;
    z-index: 1;
    pointer-events: none;
  }

  .balls-row {
    position: relative;
    z-index: 2;
    display: flex;
    align-items: center;
    width: 100%;
    justify-content: center;
    transform: translateY(3px);
  }

  .bwrap {
    position: relative;
    margin-left: -9px;
    cursor: pointer;
    transition: transform 0.13s;
    z-index: 1;
    flex-shrink: 0;
  }
  .bwrap:first-child { margin-left: 0; }
  .bwrap:hover { transform: none; }
  .bwrap.sunk { z-index: 0; }
  .bwrap.sunk canvas { opacity: 0.18; }

  .mid {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-top: 10px;
    gap: 6px;
  }
  .vs {
    font-family: 'Oswald', sans-serif;
    font-size: 14px;
    color: rgba(255,255,255,0.25);
    letter-spacing: 2px;
  }
  .e8wrap {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    margin-top: 4px;
  }
  .e8lbl {
    font-size: 10px;
    color: rgba(255,255,255,0.35);
    letter-spacing: 1px;
  }
  .e8slot {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    background: #3a3f44;
    box-shadow: inset 0 3px 8px rgba(0,0,0,0.8), inset 0 -1px 2px rgba(255,255,255,0.06);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: transform 0.13s;
  }
  .e8slot:hover { transform: scale(1.1); }

  @keyframes glow {
    0%,100% { box-shadow: inset 0 3px 8px rgba(0,0,0,0.8), 0 0 0 0 rgba(255,215,0,0); }
    50%      { box-shadow: inset 0 3px 8px rgba(0,0,0,0.8), 0 0 0 6px rgba(255,215,0,0.55); }
  }
  .pulse { animation: glow 1s infinite; }

  .nomsg {
    font-size: 11px;
    color: rgba(255,255,255,0.25);
    text-align: center;
    width: 100%;
    padding: 10px 0;
  }

  .sink-prompt {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    width: 100%;
  }
  .sink-prompt-lbl {
    font-size: 11px;
    color: #ffd700;
    font-weight: 700;
    letter-spacing: 1px;
  }

  .foot {
    display: flex;
    justify-content: center;
    margin-top: 12px;
  }
  .ngbtn {
    background: rgba(0,0,0,0.35);
    border: 1.5px solid rgba(255,255,255,0.2);
    color: rgba(255,255,255,0.55);
    padding: 7px 24px;
    border-radius: 30px;
    cursor: pointer;
    font-size: 13px;
    font-family: 'Oswald', sans-serif;
    letter-spacing: 2px;
    transition: all 0.15s;
  }
  .ngbtn:hover { color: #fff; border-color: rgba(255,255,255,0.5); background: rgba(0,0,0,0.5); }

  .wbar {
    display: none;
    text-align: center;
    background: rgba(0,0,0,0.6);
    border-radius: 12px;
    padding: 10px 16px;
    border: 2px solid #ffd700;
    margin-top: 10px;
  }
  .wbar.show { display: block; }
  .wtxt {
    font-family: 'Oswald', sans-serif;
    color: #ffd700;
    font-size: 20px;
    font-weight: 700;
    letter-spacing: 3px;
    text-shadow: 0 0 12px rgba(255,215,0,0.6);
  }
</style>
</head>
<body>

<div class="table">
  <div class="title">8 &bull; BALL POOL</div>
  <div class="board">

    <!-- Player 1 -->
    <div class="pcard">
      <div class="name-row">
        <input class="pname" id="p1name" placeholder="PLAYER 1" maxlength="13">
        <button class="tbtn t-none" id="p1tbtn" onclick="cycleType(1)">— PICK</button>
      </div>
      <div class="score-row">
        <div class="score-num" id="p1score">0</div>
        <div class="score-lbl">SUNK</div>
      </div>
      <div class="balls-label">TAP TO SINK</div>
      <div class="tray" id="p1tray"></div>
    </div>

    <!-- Center -->
    <div class="mid">
      <div class="vs">VS</div>
      <div class="e8wrap">
        <div class="e8slot" id="eb8slot">
          <canvas id="eb8c" width="42" height="42"></canvas>
        </div>
        <div class="e8lbl">8-BALL</div>
      </div>
    </div>

    <!-- Player 2 -->
    <div class="pcard">
      <div class="name-row">
        <input class="pname" id="p2name" placeholder="PLAYER 2" maxlength="13">
        <button class="tbtn t-none" id="p2tbtn" onclick="cycleType(2)">— PICK</button>
      </div>
      <div class="score-row">
        <div class="score-num" id="p2score">0</div>
        <div class="score-lbl">SUNK</div>
      </div>
      <div class="balls-label">TAP TO SINK</div>
      <div class="tray" id="p2tray"></div>
    </div>

  </div>
  <div class="wbar" id="wbar"><div class="wtxt" id="wtxt"></div></div>
  <div class="foot"><button class="ngbtn" onclick="resetGame()">NEW GAME</button></div>
</div>

<script>
const BD = {
  1:  { c:'#f5d000', n:'1',  s:false },
  2:  { c:'#1a3fc4', n:'2',  s:false },
  3:  { c:'#cc1a1a', n:'3',  s:false },
  4:  { c:'#7a1aa0', n:'4',  s:false },
  5:  { c:'#e05510', n:'5',  s:false },
  6:  { c:'#186e20', n:'6',  s:false },
  7:  { c:'#8b0000', n:'7',  s:false },
  9:  { c:'#f5d000', n:'9',  s:true  },
  10: { c:'#1a3fc4', n:'10', s:true  },
  11: { c:'#cc1a1a', n:'11', s:true  },
  12: { c:'#7a1aa0', n:'12', s:true  },
  13: { c:'#e05510', n:'13', s:true  },
  14: { c:'#186e20', n:'14', s:true  },
  15: { c:'#8b0000', n:'15', s:true  },
};
const SOL = [1,2,3,4,5,6,7];
const STR  = [9,10,11,12,13,14,15];
let types = [null, null];
let sunk  = [{}, {}];
let allSunk = [false, false];
let dead  = false;

function drawBall(canvas, num, isSunk) {
  const d = BD[num];
  const sz = canvas.width;
  const ctx = canvas.getContext('2d');
  const r = sz / 2, cx = r, cy = r;
  ctx.clearRect(0, 0, sz, sz);
  ctx.save();
  ctx.globalAlpha = isSunk ? 0.2 : 1;

  ctx.beginPath(); ctx.arc(cx, cy, r - 0.5, 0, Math.PI*2);
  ctx.fillStyle = '#1a1a1a'; ctx.fill();

  if (d.s) {
    ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2);
    ctx.fillStyle = 'white'; ctx.fill();

    ctx.save();
    ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2); ctx.clip();
    const sh = sz * 0.385;
    const sy = cy - sh / 2;
    ctx.fillStyle = d.c;
    ctx.fillRect(0, sy, sz, sh);
    ctx.restore();
  } else {
    ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2);
    ctx.fillStyle = d.c; ctx.fill();
  }

  const br = r * 0.37;
  ctx.beginPath(); ctx.arc(cx, cy, br, 0, Math.PI*2);
  ctx.fillStyle = 'white'; ctx.fill();

  const fs = d.n.length > 1 ? r * 0.33 : r * 0.42;
  ctx.font = `900 ${fs}px "Arial Black", Arial, sans-serif`;
  ctx.fillStyle = '#111';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(d.n, cx, cy + 0.5);

  ctx.save();
  ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2); ctx.clip();
  const grd = ctx.createRadialGradient(cx - r*0.28, cy - r*0.3, 0, cx, cy, r * 0.9);
  grd.addColorStop(0,   'rgba(255,255,255,0.62)');
  grd.addColorStop(0.3, 'rgba(255,255,255,0.10)');
  grd.addColorStop(1,   'rgba(0,0,0,0)');
  ctx.fillStyle = grd;
  ctx.fillRect(0, 0, sz, sz);
  ctx.restore();

  ctx.restore();
}

function draw8(canvas, isSunk, pulse) {
  const sz = canvas.width;
  const ctx = canvas.getContext('2d');
  const r = sz/2, cx = r, cy = r;
  ctx.clearRect(0, 0, sz, sz);
  ctx.save();
  ctx.globalAlpha = isSunk ? 0.2 : 1;

  ctx.beginPath(); ctx.arc(cx, cy, r - 0.5, 0, Math.PI*2);
  ctx.fillStyle = '#111'; ctx.fill();

  ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2);
  ctx.fillStyle = '#1c1c1c'; ctx.fill();

  const br = r * 0.38;
  ctx.beginPath(); ctx.arc(cx, cy, br, 0, Math.PI*2);
  ctx.fillStyle = 'white'; ctx.fill();

  ctx.font = `900 ${r * 0.45}px "Arial Black", Arial, sans-serif`;
  ctx.fillStyle = '#111';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText('8', cx, cy + 0.5);

  ctx.save();
  ctx.beginPath(); ctx.arc(cx, cy, r - 2, 0, Math.PI*2); ctx.clip();
  const grd = ctx.createRadialGradient(cx - r*0.28, cy - r*0.3, 0, cx, cy, r * 0.9);
  grd.addColorStop(0,   'rgba(255,255,255,0.55)');
  grd.addColorStop(0.3, 'rgba(255,255,255,0.08)');
  grd.addColorStop(1,   'rgba(0,0,0,0)');
  ctx.fillStyle = grd; ctx.fillRect(0,0,sz,sz);
  ctx.restore();
  ctx.restore();

  const slot = document.getElementById('eb8slot');
  if (pulse) slot.classList.add('pulse');
  else slot.classList.remove('pulse');
}

function render(p) {
  const pi = p - 1;
  const type = types[pi];
  const tray = document.getElementById(`p${p}tray`);
  tray.innerHTML = '';
  
  document.getElementById(`p${p}score`).textContent =
    Object.values(sunk[pi]).filter(Boolean).length;

  if (allSunk[pi] && !dead) {
    const wrap = document.createElement('div');
    wrap.className = 'sink-prompt';
    const slot = document.createElement('div');
    slot.className = 'e8slot pulse';
    slot.style.cssText = 'width:38px;height:38px;background:#3a3f44;box-shadow:inset 0 3px 8px rgba(0,0,0,.8);display:flex;align-items:center;justify-content:center;cursor:pointer;border-radius:50%';
    slot.onclick = () => sink8(p);
    const c = document.createElement('canvas'); c.width = 30; c.height = 30;
    draw8(c, false, false);
    slot.appendChild(c);
    const lbl = document.createElement('div');
    lbl.className = 'sink-prompt-lbl'; lbl.textContent = 'SINK THE 8!';
    wrap.appendChild(slot); wrap.appendChild(lbl);
    tray.appendChild(wrap);
    return;
  }

  if (!type) {
    const m = document.createElement('div');
    m.className = 'nomsg'; m.textContent = 'set type above';
    tray.appendChild(m); return;
  }

  const bg = document.createElement('canvas');
  bg.className = 'tray-bg';
  bg.height = 44;

  const row = document.createElement('div');
  row.className = 'balls-row';

  const nums = type === 'solid' ? SOL : STR;
  requestAnimationFrame(() => drawTrayBG(bg, nums.length));

  nums.forEach((num, i) => {
    const isSunkB = !!sunk[pi][num];

    const wrap = document.createElement('div');
    wrap.className = 'bwrap' + (isSunkB ? ' sunk' : '');
    wrap.style.zIndex = nums.length - i;

    const c = document.createElement('canvas');
    c.width = 38; c.height = 38;
    drawBall(c, num, isSunkB);
    wrap.appendChild(c);
    wrap.onclick = () => toggleBall(p, num);
    row.appendChild(wrap);
  });
  
  tray.appendChild(row);
  tray.appendChild(bg);
}

function toggleBall(p, num) {
  if (dead) return;
  const pi = p - 1;
  sunk[pi][num] = !sunk[pi][num];
  allSunk[pi] = Object.values(sunk[pi]).filter(Boolean).length >= 7;
  render(p); update8();
}

function update8() {
  const pulse = (allSunk[0] || allSunk[1]) && !dead;
  const c = document.getElementById('eb8c');
  draw8(c, dead, pulse);
}

function sink8(player) {
  if (dead) return;
  dead = true;
  update8();

  const p1 = document.getElementById('p1name').value || 'Player 1';
  const p2 = document.getElementById('p2name').value || 'Player 2';

  let w = '';
  if (player === 1 && allSunk[0]) w = p1;
  else if (player === 2 && allSunk[1]) w = p2;

  document.getElementById('wbar').classList.add('show');
  document.getElementById('wtxt').textContent =
    w ? `${w.toUpperCase()} WINS!` : '8-BALL SUNK — CHECK THE RULES!';
}

function drawTrayBG(canvas, count) {
  const ctx = canvas.getContext('2d');
  const w = canvas.width = canvas.offsetWidth;
  const h = canvas.height = canvas.offsetHeight;
  if (w === 0) return;
  ctx.clearRect(0, 0, w, h);

  const r = 19;
  const overlap = 9;
  const spacing = (r * 2) - overlap;
  const totalWidth = spacing * (count - 1) + r * 2;
  const startX = (w - totalWidth) / 2 + r;
  const cy = h / 2;

  ctx.fillStyle = '#3a3f44';
  ctx.beginPath();
  for (let i = 0; i < count; i++) {
    const cx = startX + i * spacing;
    ctx.moveTo(cx + r, cy);
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
  }
  ctx.fill();
}

function cycleType(p) {
  const pi = p - 1;
  const other = pi === 0 ? 1 : 0;

  const order = [null, 'solid', 'stripe'];
  types[pi] = order[(order.indexOf(types[pi]) + 1) % 3];

  sunk[pi] = {};
  allSunk[pi] = false;

  if (types[pi] === 'solid') types[other] = 'stripe';
  else if (types[pi] === 'stripe') types[other] = 'solid';
  else types[other] = null;

  sunk[other] = {};
  allSunk[other] = false;

  [1, 2].forEach(pn => {
    const idx = pn - 1;
    const btn = document.getElementById(`p${pn}tbtn`);
    btn.className = 'tbtn';
    if (types[idx] === 'solid') {
      btn.className += ' t-solid';
      btn.textContent = 'SOLIDS';
    } else if (types[idx] === 'stripe') {
      btn.className += ' t-stripe';
      btn.textContent = 'STRIPES';
    } else {
      btn.className += ' t-none';
      btn.textContent = '— PICK';
    }
  });

  render(1);
  render(2);
  update8();
}

function resetGame() {
  types = [null,null]; sunk = [{},{}]; allSunk = [false,false]; dead = false;
  [1,2].forEach(p => {
    const b = document.getElementById(`p${p}tbtn`);
    b.className = 'tbtn t-none'; b.textContent = '— PICK';
  });
  document.getElementById('wbar').classList.remove('show');
  document.getElementById('eb8slot').classList.remove('pulse');
  render(1); render(2); update8();
}

document.getElementById('p1score').textContent = '0';
document.getElementById('p2score').textContent = '0';
render(1); render(2); update8();
</script>
</body>
</html>
)HTML";

/* ── Main ── */
int main(int argc, char *argv[])
{
    gtk_init(&argc, &argv);

    /* Window */
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "8-Ball Pool Tracker");
    gtk_window_fullscreen(GTK_WINDOW(window));
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
    g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    /* WebView */
    WebKitWebView *webview = WEBKIT_WEB_VIEW(webkit_web_view_new());

    /* Settings: enable JS, smooth scrolling, hardware acceleration */
    WebKitSettings *settings = webkit_web_view_get_settings(webview);
    webkit_settings_set_enable_javascript(settings, TRUE);
    webkit_settings_set_enable_smooth_scrolling(settings, TRUE);
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS);

    /* Disable right-click context menu (feels more native) */
    g_signal_connect(webview, "context-menu",
                     G_CALLBACK(gtk_true), NULL);

    /* Load the embedded HTML */
    webkit_web_view_load_html(webview, HTML, NULL);

    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(webview));
    gtk_widget_show_all(window);

    gtk_main();
    return 0;
}
