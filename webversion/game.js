'use strict';

// =====================================================================
//  AeroDuel — combate de biplanos 2D (contra o bot ou online 1v1)
// =====================================================================

// ---------- Constantes do mundo e da física ----------
const W = 384, H = 216;          // tamanho lógico do mundo (o ecrã escala)
const GROUND = 196;              // y do chão
const PLANE_Y = GROUND - 4;      // y do centro de um avião pousado
const G = 55;                    // gravidade
const THRUST = 60;               // força do motor
const DRAG = 0.75;               // atrito do ar (vel. máx. nivelada = THRUST / DRAG = 80)
const STALL = 26;                // abaixo desta velocidade o avião entra em perda
const TAKEOFF = 40;              // velocidade mínima para descolar
const TURN = 3.0;                // velocidade de rotação (rad/s)
const BULLET_SPEED = 170, BULLET_LIFE = 1.1, FIRE_CD = 0.2;
const MAX_HP = 3;
const WIN_SCORE = 10;
const RESPAWN_TIME = 2.5;
const HANGAR_X = [36, W - 36];
const WALK_SPEED = 16;

// ---------- Rede ----------
const SNAP_HZ = 25;              // snapshots por segundo enviados pelo anfitrião
const INTERP = 0.09;             // atraso de interpolação no convidado (s)
const PILOT_STATES = ['free', 'chute', 'ground'];

const COLORS = [
  { body: '#2f6fd6', wing: '#9cc3ff', chute: '#e8f1ff', name: 'azul' },
  { body: '#d63a2f', wing: '#ffb19c', chute: '#fff0ea', name: 'vermelho' },
];
const GOOD = '#9cff9c', BAD = '#ffb19c', WARN = '#fff6c2';

const DIFFS = {
  facil:   { reaction: 0.35, noise: 0.30, cone: 0.10, range: 110, trigger: 0.35, huntPilots: false },
  normal:  { reaction: 0.18, noise: 0.14, cone: 0.14, range: 140, trigger: 0.7,  huntPilots: true },
  dificil: { reaction: 0.08, noise: 0.05, cone: 0.18, range: 170, trigger: 1.0,  huntPilots: true },
};

// ---------- Utilitários ----------
const rand = (a, b) => a + Math.random() * (b - a);
const wrapX = x => ((x % W) + W) % W;
const dxWrap = (from, to) => { let d = to - from; if (d > W / 2) d -= W; if (d < -W / 2) d += W; return d; };
const norm = a => { while (a > Math.PI) a -= 2 * Math.PI; while (a <= -Math.PI) a += 2 * Math.PI; return a; };
const angDiff = (from, to) => norm(to - from);
const dist2 = (x1, y1, x2, y2) => { const dx = dxWrap(x1, x2), dy = y2 - y1; return dx * dx + dy * dy; };
const r1 = v => Math.round(v * 10) / 10;
const r2 = v => Math.round(v * 100) / 100;
const $ = id => document.getElementById(id);

// ---------- Som (WebAudio, sem ficheiros) ----------
const sfx = (() => {
  let ac = null, noiseBuf = null, muted = false;
  function init() {
    if (ac) { if (ac.state === 'suspended') ac.resume(); return; }
    try {
      ac = new (window.AudioContext || window.webkitAudioContext)();
      noiseBuf = ac.createBuffer(1, ac.sampleRate * 0.8, ac.sampleRate);
      const d = noiseBuf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    } catch (e) { ac = null; }
  }
  function tone(freq, dur, type, vol, slide) {
    if (!ac || muted) return;
    const t = ac.currentTime, o = ac.createOscillator(), g = ac.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq + slide), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(ac.destination);
    o.start(t); o.stop(t + dur);
  }
  function noise(dur, vol, freq) {
    if (!ac || muted) return;
    const t = ac.currentTime, s = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain();
    s.buffer = noiseBuf;
    f.type = 'lowpass'; f.frequency.value = freq;
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f).connect(g).connect(ac.destination);
    s.start(t); s.stop(t + dur);
  }
  return {
    init,
    toggle() { muted = !muted; return muted; },
    shoot: mine => tone(mine ? 900 : 640, 0.05, 'square', mine ? 0.03 : 0.015, -350),
    hit: () => noise(0.15, 0.2, 2500),
    boom: () => { noise(0.7, 0.4, 700); tone(90, 0.5, 'sine', 0.2, -50); },
    eject: () => tone(320, 0.2, 'triangle', 0.08, 400),
    chute: () => tone(520, 0.15, 'sine', 0.05, -200),
    land: () => tone(200, 0.08, 'triangle', 0.05, -60),
    repair: () => { tone(600, 0.08, 'square', 0.03, 0); setTimeout(() => tone(900, 0.1, 'square', 0.03, 0), 90); },
    win: () => [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => tone(f, 0.18, 'square', 0.04, 0), i * 130)),
    lose: () => [400, 330, 260].forEach((f, i) => setTimeout(() => tone(f, 0.25, 'triangle', 0.06, 0), i * 180)),
  };
})();

// ---------- Estado do jogo ----------
let planes = [], pilots = [], bullets = [], particles = [];
let sides = [];
let state = 'menu';             // menu | playing | paused | over
let mode = 'demo';              // demo (bots no menu) | solo (contra o bot) | host | guest
let me = 0;                     // lado controlado neste ecrã (0 azul, 1 vermelho)
let difficulty = 'normal';
let time = 0;
let nextId = 1;
const playerInput = { left: false, right: false, fire: false, eject: false };
const remoteInput = { left: false, right: false, fire: false, eject: false };   // controlos do convidado, no anfitrião

const clouds = Array.from({ length: 6 }, (_, i) => ({ x: i * 70 + rand(0, 40), y: rand(18, 90), s: rand(0.7, 1.4), v: rand(2, 5) }));
const trees = [110, 128, 190, 255, 270];

const botInput = () => ({ left: false, right: false, fire: false, eject: false });

function newSide(id, isBot, input) {
  return { id, isBot, score: 0, ctrl: null, respawn: 0, input, bot: { t: 0, noise: 0, ejectT: 0 } };
}

function resetWorld(kind) {
  planes = []; pilots = []; bullets = []; particles = [];
  nextId = 1;
  sides = [
    newSide(0, kind === 'demo', kind === 'demo' ? botInput() : playerInput),
    newSide(1, kind === 'demo' || kind === 'solo', kind === 'host' ? remoteInput : botInput()),
  ];
  spawnPlane(sides[0]);
  spawnPlane(sides[1]);
}

function spawnPlane(side) {
  const right = side.id === 0;
  const p = {
    kind: 'plane', id: nextId++, side,
    x: HANGAR_X[side.id] + (right ? 8 : -8), y: PLANE_Y,
    a: right ? 0 : Math.PI, speed: 0, fallVy: 0,
    hp: MAX_HP, onGround: true, stalled: false, falling: false, manned: true,
    cd: 0.4, spin: 0, smokeT: 0, hitT: 0, prop: 0, dead: false,
  };
  planes.push(p);
  side.ctrl = p;
  side.respawn = 0;
  return p;
}

// ---------- Efeitos (som, partículas, mensagens) ----------
// Tudo o que se vê ou ouve num instante passa por fx(): corre aqui e, se
// formos o anfitrião, segue para o convidado no próximo snapshot.
let netEvents = [];
function fx(name, ...args) {
  runFx(name, args);
  if (mode === 'host') netEvents.push([name, ...args]);
}

function runFx(name, a) {
  const playing = state === 'playing';
  switch (name) {
    case 'boom': explosion(a[0], a[1]); sfx.boom(); if (a[2] === me && playing) vibrate(150); break;
    case 'hit': puff(a[0], a[1], '#ffe680', 6, 50, 0.25, 1.2, 0); sfx.hit(); if (a[2] === me && playing) vibrate(40); break;
    case 'blood': puff(a[0], a[1], '#b0182b', 10, 40, 0.5, 1.2, 60); sfx.hit(); break;
    case 'tear': puff(a[0], a[1], COLORS[a[2]].chute, 8, 30, 0.6, 1.5, 20); showMsg('tear', a[2]); break;
    case 'dust': puff(a[0], a[1], '#a58a5c', 3, 20, 0.3, 1, 40); break;
    case 'shoot': sfx.shoot(a[0] === me && mode !== 'demo'); break;
    case 'eject': sfx.eject(); break;
    case 'chute': sfx.chute(); break;
    case 'land': if (a[0] === me) sfx.land(); break;
    case 'repair': if (a[0] === me) { sfx.repair(); showMsg('repair', a[0]); } break;
    case 'newPlane': showMsg('newPlane', a[0]); break;
    case 'msg': showMsg(a[0], a[1]); break;
    case 'over': showOver(a[0]); break;
  }
}

function foeName() { return mode === 'solo' || mode === 'demo' ? 'Bot' : 'Rival'; }

function msgFor(kind, side) {
  const mine = side === me, foe = foeName();
  switch (kind) {
    case 'planeCrew': return mine ? [`Caíste com o avião! ${foe} +2`, BAD] : ['Avião e piloto inimigos abatidos! +2', GOOD];
    case 'plane': return mine ? [`Perdeste o avião! ${foe} +1`, BAD] : ['Avião inimigo destruído! +1', GOOD];
    case 'pilot': return mine ? [`O teu piloto foi abatido! ${foe} +1`, BAD] : ['Piloto inimigo eliminado! +1', GOOD];
    case 'tear': return mine ? ['Paraquedas rasgado!', WARN] : ['Rasgaste o paraquedas!', WARN];
    case 'repair': return mine ? ['Avião reparado!', GOOD] : null;
    case 'newPlane': return mine ? ['Novo avião!', COLORS[me].wing] : null;
  }
  return null;
}

let flashTimer = 0;
function showMsg(kind, side) {
  if (state !== 'playing') return;
  const m = msgFor(kind, side);
  if (!m) return;
  const el = $('flash');
  el.textContent = m[0];
  el.style.color = m[1];
  el.classList.add('show');
  flashTimer = 1.6;
}

function award(loser, pts, kind) {
  const winner = sides[1 - loser.id];
  winner.score += pts;
  if (mode === 'demo') {                    // demonstração do menu: recomeça sozinha
    if (winner.score >= WIN_SCORE) sides.forEach(s => (s.score = 0));
    return;
  }
  if (state !== 'playing') return;
  fx('msg', kind, loser.id);
  if (winner.score >= WIN_SCORE) endGame(winner);
}

// ---------- Ações ----------
function crashPlane(p) {
  if (p.dead) return;
  p.dead = true;
  fx('boom', r1(p.x), r1(Math.min(p.y, GROUND - 2)), p.side.id);
  if (p.manned) {
    p.side.ctrl = null;
    p.side.respawn = RESPAWN_TIME;
    award(p.side, 2, 'planeCrew');
  } else {
    award(p.side, 1, 'plane');
  }
}

function hitPlane(p) {
  p.hp--;
  p.hitT = 0.12;
  fx('hit', r1(p.x), r1(p.y), p.side.id);
  if (p.hp <= 0 && !p.falling) {
    p.falling = true;
    p.stalled = false;
    p.spin = (Math.random() < 0.5 ? -1 : 1) * rand(1.5, 3);
    if (p.onGround) crashPlane(p);
  }
}

function eject(p) {
  if (!p.manned || p.dead || p.onGround) return;
  p.manned = false;
  if (!p.falling) { p.falling = true; p.spin = rand(-1, 1); }
  const pl = {
    kind: 'pilot', id: nextId++, side: p.side,
    x: p.x, y: p.y - 4,
    vx: Math.cos(p.a) * p.speed * 0.4,
    vy: Math.sin(p.a) * p.speed * 0.4 - 45,
    state: 'free', torn: false, t: 0, walk: 0, face: 1, dead: false,
  };
  pilots.push(pl);
  p.side.ctrl = pl;
  fx('eject');
}

function killPilot(pl) {
  if (pl.dead) return;
  pl.dead = true;
  fx('blood', r1(pl.x), r1(pl.y));
  pl.side.ctrl = null;
  pl.side.respawn = RESPAWN_TIME;
  award(pl.side, 1, 'pilot');
}

function tearChute(pl) {
  pl.state = 'free';
  pl.torn = true;
  fx('tear', r1(pl.x), r1(pl.y - 10), pl.side.id);
}

function vibrate(ms) { if (navigator.vibrate) try { navigator.vibrate(ms); } catch (e) { /* ignorar */ } }

// ---------- Partículas ----------
function puff(x, y, color, n, spd, life, size, grav) {
  for (let i = 0; i < n; i++) {
    const a = rand(0, Math.PI * 2), s = rand(0.2, 1) * spd;
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life, max: life, color, size: size * rand(0.7, 1.3), grav });
  }
}
function explosion(x, y) {
  puff(x, y, '#ffd23f', 16, 70, 0.5, 2, 30);
  puff(x, y, '#ff7b25', 16, 50, 0.7, 2.6, 15);
  puff(x, y, '#555', 12, 25, 1.4, 3.2, -12);
}

// fumo de um avião danificado (só visual, cada ecrã gera o seu)
function emitSmoke(p, dt) {
  p.smokeT -= dt;
  if (p.smokeT > 0 || (p.hp >= MAX_HP && !p.falling)) return;
  p.smokeT = p.falling ? 0.03 : p.hp === 1 ? 0.07 : 0.16;
  const dark = p.falling || p.hp === 1;
  particles.push({ x: p.x - Math.cos(p.a) * 6, y: p.y - Math.sin(p.a) * 6, vx: rand(-4, 4), vy: rand(-8, -2),
    life: 1.1, max: 1.1, color: dark ? '#333' : '#999', size: rand(2, 3.5), grav: -4 });
  if (p.falling && Math.random() < 0.5)
    particles.push({ x: p.x, y: p.y, vx: rand(-6, 6), vy: rand(-6, 0), life: 0.3, max: 0.3, color: '#ff8a25', size: 2, grav: 0 });
}

// ---------- Atualização: avião ----------
function updatePlane(p, dt) {
  const inp = p.manned && p.side.ctrl === p ? p.side.input : null;
  const flying = inp && !p.falling;   // pode ser controlado

  p.hitT = Math.max(0, p.hitT - dt);
  p.cd -= dt;
  if (flying) p.prop += dt * 45;

  // rotação
  if (flying) {
    let turn = (inp.right ? 1 : 0) - (inp.left ? 1 : 0);
    if (p.stalled) turn *= 0.4;
    p.a += turn * TURN * dt;
  }
  if (p.falling) p.a += p.spin * dt;
  p.a = norm(p.a);

  // velocidade: motor - atrito + gravidade ao longo da trajetória
  const engine = flying ? THRUST : 0;
  p.speed += (engine - DRAG * p.speed + (p.onGround ? 0 : G * Math.sin(p.a))) * dt;
  if (p.onGround && !flying) p.speed -= 30 * dt;
  p.speed = Math.max(0, p.speed);

  if (p.onGround) {
    // no chão só se pode levantar o nariz e só com velocidade suficiente
    const level = Math.cos(p.a) >= 0 ? 0 : Math.PI;
    if (Math.sin(p.a) < -0.02 && p.speed >= TAKEOFF) {
      p.onGround = false;
    } else {
      p.a = level;
      p.y = PLANE_Y;
    }
    // reparação ao passar pelo próprio hangar
    if (p.manned && p.hp < MAX_HP && Math.abs(dxWrap(p.x, HANGAR_X[p.side.id])) < 16) {
      p.hp = MAX_HP;
      fx('repair', p.side.id);
    }
  } else if (!p.falling) {
    if (!p.stalled && p.speed < STALL) p.stalled = true;
    if (p.stalled) {
      // perda: o avião cai e o nariz desce sozinho
      p.fallVy = Math.min(p.fallVy + G * 0.8 * dt, 70);
      const d = angDiff(p.a, Math.PI / 2);
      p.a = norm(p.a + Math.sign(d) * Math.min(Math.abs(d), 1.5 * dt));
      if (p.speed > STALL + 12 && Math.sin(p.a) > 0.4) p.stalled = false;
    } else {
      p.fallVy = Math.max(0, p.fallVy - 50 * dt);
    }
  } else {
    p.fallVy = Math.min(p.fallVy + G * dt, 110);
  }

  // movimento
  p.x = wrapX(p.x + Math.cos(p.a) * p.speed * dt);
  if (!p.onGround) p.y += Math.sin(p.a) * p.speed * dt + p.fallVy * dt;

  // teto
  if (p.y < 6) {
    p.y = 6;
    if (!p.falling) { p.stalled = true; p.speed = Math.min(p.speed, STALL - 4); }
  }

  // contacto com o chão: aterrar ou despenhar
  if (!p.onGround && p.y >= PLANE_Y) {
    if (!p.falling && !p.stalled && p.fallVy < 20 && Math.abs(Math.sin(p.a)) < 0.3) {
      p.onGround = true;
      p.y = PLANE_Y;
      p.a = Math.cos(p.a) >= 0 ? 0 : Math.PI;
      fx('land', p.side.id);
    } else {
      crashPlane(p);
      return;
    }
  }

  emitSmoke(p, dt);

  // disparar
  if (flying && inp.fire && p.cd <= 0) {
    p.cd = FIRE_CD;
    const c = Math.cos(p.a), s = Math.sin(p.a), v = BULLET_SPEED + p.speed * 0.5;
    bullets.push({ id: nextId++, x: wrapX(p.x + c * 8), y: p.y + s * 8, vx: c * v, vy: s * v, life: BULLET_LIFE, owner: p.side });
    fx('shoot', p.side.id);
  }

  // saltar de paraquedas
  if (inp && inp.eject) eject(p);
}

// ---------- Atualização: piloto ----------
function updatePilot(pl, dt) {
  const inp = pl.side.ctrl === pl ? pl.side.input : null;
  const dir = inp ? (inp.right ? 1 : 0) - (inp.left ? 1 : 0) : 0;
  pl.t += dt;

  if (pl.state === 'free') {
    pl.vy += G * dt;
    pl.vx *= 1 - 0.5 * dt;
    if (!pl.torn && pl.t > 0.6) { pl.state = 'chute'; fx('chute'); }
  } else if (pl.state === 'chute') {
    pl.vx += (dir * 22 - pl.vx) * 2 * dt;
    pl.vy += (16 - pl.vy) * 3 * dt;
  }

  if (pl.state !== 'ground') {
    pl.x = wrapX(pl.x + pl.vx * dt);
    pl.y += pl.vy * dt;
    if (pl.y >= GROUND - 3) {
      pl.y = GROUND - 3;
      if (pl.state === 'chute' || pl.vy < 50) { pl.state = 'ground'; pl.vx = pl.vy = 0; }
      else killPilot(pl);
    }
  } else {
    pl.walk = dir;
    if (dir) pl.face = dir;
    pl.x = wrapX(pl.x + dir * WALK_SPEED * dt);
    if (Math.abs(dxWrap(pl.x, HANGAR_X[pl.side.id])) < 5) {
      pl.dead = true;                       // entrou no hangar
      spawnPlane(pl.side);
      fx('newPlane', pl.side.id);
    }
  }
}

// ---------- Bot ----------
function botThink(side, dt) {
  const inp = side.input, b = side.bot, D = DIFFS[difficulty];
  inp.left = inp.right = inp.fire = inp.eject = false;
  const meCtrl = side.ctrl;
  if (!meCtrl) return;

  if (meCtrl.kind === 'pilot') {
    if (meCtrl.state === 'free') return;
    const d = dxWrap(meCtrl.x, HANGAR_X[side.id]);
    if (Math.abs(d) > 1) { if (d < 0) inp.left = true; else inp.right = true; }
    return;
  }

  const p = meCtrl;
  if (p.falling) {
    b.ejectT += dt;
    if (b.ejectT > D.reaction + 0.2) inp.eject = true;
    return;
  }
  b.ejectT = 0;

  const facing = Math.cos(p.a) >= 0 ? 1 : -1;
  const up = facing > 0 ? -0.55 : Math.PI + 0.55;
  let desired, aim = null, dist = Infinity;
  b.t -= dt;

  if (p.onGround) {
    desired = p.speed > TAKEOFF + 15 ? (facing > 0 ? -0.35 : Math.PI + 0.35) : (facing > 0 ? 0 : Math.PI);
  } else if (p.stalled) {
    desired = Math.PI / 2;
  } else {
    // escolher alvo
    const t = sides[1 - side.id].ctrl;
    let tx, ty, tvx = 0, tvy = 0, valid = false;
    if (t && !t.dead) {
      if (t.kind === 'plane' && !t.falling) {
        tx = t.x; ty = t.y;
        tvx = Math.cos(t.a) * t.speed;
        tvy = t.onGround ? 0 : Math.sin(t.a) * t.speed + t.fallVy;
        valid = true;
      } else if (t.kind === 'pilot' && D.huntPilots) {
        tx = t.x; ty = t.y;
        tvx = t.state === 'ground' ? t.walk * WALK_SPEED : t.vx;
        tvy = t.state === 'ground' ? 0 : t.vy;
        valid = true;
      }
    }
    if (valid) {
      let dx = dxWrap(p.x, tx), dy = ty - p.y;
      dist = Math.hypot(dx, dy);
      const tt = dist / (BULLET_SPEED + p.speed * 0.5);   // apontar para onde o alvo vai estar
      dx += tvx * tt; dy += tvy * tt;
      aim = Math.atan2(dy, dx);
      if (b.t <= 0) { b.t = D.reaction; b.noise = rand(-D.noise, D.noise); }
      desired = aim + b.noise;
    } else {
      desired = Math.atan2((70 - p.y) * 0.5, 60 * facing);   // patrulhar a meia altura
    }

    const alt = GROUND - p.y;
    // não mergulhar a pique perto do chão
    if (alt < 90 && Math.sin(desired) > 0.45) desired = Math.atan2(0.45, Math.cos(desired) >= 0 ? 0.89 : -0.89);
    // evitar entrar em perda
    if (p.speed < STALL + 10 && Math.sin(desired) < -0.25) desired = Math.atan2(-0.1, facing);
    // muito baixo: subir
    if (alt < 50 && Math.sin(p.a) > -0.15) desired = up;
  }

  const d = angDiff(p.a, desired);
  if (Math.abs(d) > 0.05) { if (d > 0) inp.right = true; else inp.left = true; }
  if (aim !== null && dist < D.range && Math.abs(angDiff(p.a, aim)) < D.cone && Math.random() < D.trigger) inp.fire = true;
}

// ---------- Ciclo de simulação (sozinho ou anfitrião) ----------
function updateAmbient(dt) {
  for (const c of clouds) c.x = (c.x + c.v * dt) % (W + 60);
  for (const q of particles) {
    q.vy += q.grav * dt;
    q.x += q.vx * dt; q.y += q.vy * dt;
    q.life -= dt;
  }
  particles = particles.filter(q => q.life > 0);
  if (particles.length > 600) particles.splice(0, particles.length - 600);
  if (flashTimer > 0) { flashTimer -= dt; if (flashTimer <= 0) $('flash').classList.remove('show'); }
}

function update(dt) {
  time += dt;

  for (const s of sides) if (s.isBot) botThink(s, dt);

  for (const p of planes) if (!p.dead) updatePlane(p, dt);
  for (const pl of pilots) if (!pl.dead) updatePilot(pl, dt);

  // balas
  for (const b of bullets) {
    b.x = wrapX(b.x + b.vx * dt);
    b.y += b.vy * dt;
    b.life -= dt;
    if (b.y >= GROUND) { b.life = 0; fx('dust', r1(b.x), GROUND); continue; }
    if (b.y < -10) { b.life = 0; continue; }
    for (const p of planes) {
      if (p.dead || p.falling || p.side === b.owner) continue;
      if (dist2(b.x, b.y, p.x, p.y) < 36) { hitPlane(p); b.life = 0; break; }
    }
    if (b.life <= 0) continue;
    for (const pl of pilots) {
      if (pl.dead || pl.side === b.owner) continue;
      if (dist2(b.x, b.y, pl.x, pl.y) < 12) { killPilot(pl); b.life = 0; break; }
      if (pl.state === 'chute' && dist2(b.x, b.y, pl.x, pl.y - 10) < 40) { tearChute(pl); b.life = 0; break; }
    }
  }

  // aviões contra pilotos e contra aviões
  for (const p of planes) {
    if (p.dead) continue;
    for (const pl of pilots) {
      if (pl.dead || pl.side === p.side) continue;
      if (dist2(p.x, p.y, pl.x, pl.y) < 36) killPilot(pl);
      else if (pl.state === 'chute' && dist2(p.x, p.y, pl.x, pl.y - 10) < 49) tearChute(pl);
    }
  }
  const alive = planes.filter(p => !p.dead && !p.falling);
  if (alive.length === 2 && alive[0].side !== alive[1].side && dist2(alive[0].x, alive[0].y, alive[1].x, alive[1].y) < 64) {
    for (const p of alive) { p.hp = 0; hitPlane(p); }
  }

  // novos aviões
  for (const s of sides) {
    if (!s.ctrl && s.respawn > 0) {
      s.respawn -= dt;
      if (s.respawn <= 0) spawnPlane(s);
    }
    s.input.eject = false;
  }

  planes = planes.filter(p => !p.dead);
  pilots = pilots.filter(p => !p.dead);
  bullets = bullets.filter(b => b.life > 0);

  updateAmbient(dt);
}

// ---------- Rede: anfitrião ----------
let snapT = 0, hostLastEj = 0;

function makeSnapshot() {
  const flags = p => (p.onGround ? 1 : 0) | (p.stalled ? 2 : 0) | (p.falling ? 4 : 0) | (p.manned ? 8 : 0) | (p.hitT > 0 ? 16 : 0);
  const snap = {
    t: 's',
    tm: Math.round(time * 1000) / 1000,
    sc: sides.map(s => s.score),
    rs: sides.map(s => r1(s.respawn)),
    c: sides.map(s => (s.ctrl ? s.ctrl.id : 0)),
    P: planes.map(p => [p.id, p.side.id, r1(p.x), r1(p.y), r2(p.a), p.hp, flags(p), r1(p.speed), r1(p.fallVy)]),
    L: pilots.map(l => [l.id, l.side.id, r1(l.x), r1(l.y), PILOT_STATES.indexOf(l.state), l.torn ? 1 : 0, l.walk, l.face, r1(l.vx), r1(l.vy)]),
    B: bullets.map(b => [b.id, b.owner.id, r1(b.x), r1(b.y)]),
    ev: netEvents,
  };
  netEvents = [];
  return snap;
}

function hostTick(dt) {
  snapT -= dt;
  if (snapT > 0) return;
  snapT = 1 / SNAP_HZ;
  Net.send(makeSnapshot());
}

function hostReceive(m) {
  if (m.t !== 'in') return;
  remoteInput.left = !!(m.k & 1);
  remoteInput.right = !!(m.k & 2);
  remoteInput.fire = !!(m.k & 4);
  if (m.e !== hostLastEj) { hostLastEj = m.e; remoteInput.eject = true; }
}

// ---------- Rede: convidado ----------
// O convidado não simula nada: guarda os snapshots e desenha um pouco
// atrás do mais recente, interpolando entre os dois que o rodeiam.
let guestBuf = [], renderT = 0, lastKey = -1, ejectCount = 0, inputT = 0;
const guestCosmetic = new Map();   // fumo e hélice por avião

function decodeSnapshot(s) {
  return {
    tm: s.tm, sc: s.sc, rs: s.rs, c: s.c,
    P: new Map(s.P.map(a => [a[0], {
      kind: 'plane', id: a[0], side: sides[a[1]], x: a[2], y: a[3], a: a[4], hp: a[5],
      onGround: !!(a[6] & 1), stalled: !!(a[6] & 2), falling: !!(a[6] & 4), manned: !!(a[6] & 8), hitT: a[6] & 16 ? 1 : 0,
      speed: a[7], fallVy: a[8], smokeT: 0, prop: 0,
    }])),
    L: new Map(s.L.map(a => [a[0], {
      kind: 'pilot', id: a[0], side: sides[a[1]], x: a[2], y: a[3], state: PILOT_STATES[a[4]], torn: !!a[5],
      walk: a[6], face: a[7], vx: a[8], vy: a[9],
    }])),
    B: new Map(s.B.map(a => [a[0], { id: a[0], owner: sides[a[1]], x: a[2], y: a[3] }])),
  };
}

function guestReceive(m) {
  if (m.t === 'start') { startGuest(); return; }
  if (m.t !== 's' || mode !== 'guest') return;
  const last = guestBuf[guestBuf.length - 1];
  if (last && m.tm < last.tm) guestBuf = [];          // o anfitrião recomeçou
  guestBuf.push(decodeSnapshot(m));
  if (guestBuf.length > 40) guestBuf.shift();
  sides.forEach((s, i) => (s.score = m.sc[i]));
  for (const e of m.ev) runFx(e[0], e.slice(1));
}

function lerpSet(A, B, k, withAngle) {
  const out = [];
  for (const [id, b] of B) {
    const a = A.get(id);
    if (!a || a === b) { out.push(Object.assign({}, b)); continue; }
    const o = Object.assign({}, b);
    o.x = wrapX(a.x + dxWrap(a.x, b.x) * k);
    o.y = a.y + (b.y - a.y) * k;
    if (withAngle) o.a = norm(a.a + angDiff(a.a, b.a) * k);
    out.push(o);
  }
  return out;
}

function guestFrame(dt) {
  time += dt;
  updateAmbient(dt);
  if (!guestBuf.length) return;

  const target = guestBuf[guestBuf.length - 1].tm - INTERP;
  renderT += dt;
  if (Math.abs(renderT - target) > 0.3) renderT = target;
  else renderT += (target - renderT) * Math.min(1, dt * 2);
  while (guestBuf.length >= 2 && guestBuf[1].tm <= renderT) guestBuf.shift();

  const A = guestBuf[0], B = guestBuf[1] || A;
  const k = B.tm > A.tm ? Math.max(0, Math.min(1, (renderT - A.tm) / (B.tm - A.tm))) : 1;
  planes = lerpSet(A.P, B.P, k, true);
  pilots = lerpSet(A.L, B.L, k, false);
  bullets = lerpSet(A.B, B.B, k, false);

  sides.forEach((s, i) => {
    s.respawn = B.rs[i];
    s.ctrl = planes.find(p => p.id === B.c[i]) || pilots.find(p => p.id === B.c[i]) || null;
  });

  for (const p of planes) {
    let c = guestCosmetic.get(p.id);
    if (!c) { c = { smokeT: 0, prop: 0 }; guestCosmetic.set(p.id, c); }
    p.smokeT = c.smokeT;
    emitSmoke(p, dt);
    c.smokeT = p.smokeT;
    if (p.manned && !p.falling) c.prop += dt * 45;
    p.prop = c.prop;
  }
  if (guestCosmetic.size > 40) {
    for (const id of guestCosmetic.keys()) if (!planes.some(p => p.id === id)) guestCosmetic.delete(id);
  }
}

function guestSendInput(dt) {
  if (playerInput.eject) { ejectCount++; playerInput.eject = false; }
  const key = (playerInput.left ? 1 : 0) | (playerInput.right ? 2 : 0) | (playerInput.fire ? 4 : 0);
  inputT -= dt;
  if (key !== lastKey || inputT <= 0 || ejectCount !== guestSendInput.lastEj) {
    Net.send({ t: 'in', k: key, e: ejectCount });
    lastKey = key;
    guestSendInput.lastEj = ejectCount;
    inputT = 0.1;
  }
}
guestSendInput.lastEj = 0;

// ---------- Desenho ----------
const canvas = $('game');
const ctx = canvas.getContext('2d');
let pxScale = 1;

function resize() {
  const scale = Math.min(innerWidth / W, innerHeight / H);
  const cssW = Math.floor(W * scale), cssH = Math.floor(H * scale);
  const stage = $('stage');
  stage.style.width = cssW + 'px';
  stage.style.height = cssH + 'px';
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(cssW * dpr);
  canvas.height = Math.round(cssH * dpr);
  canvas.style.width = cssW + 'px';
  canvas.style.height = cssH + 'px';
  pxScale = canvas.width / W;
}
addEventListener('resize', resize);

// desenha nas posições x, x-W e x+W para o mundo dar a volta
function wrapped(x, margin, fn) {
  fn(x);
  if (x < margin) fn(x + W);
  if (x > W - margin) fn(x - W);
}

function drawBackground() {
  const sky = ctx.createLinearGradient(0, 0, 0, GROUND);
  sky.addColorStop(0, '#4ea8f0');
  sky.addColorStop(1, '#cdeeff');
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, W, H);

  ctx.fillStyle = '#fff6c2';
  ctx.beginPath(); ctx.arc(300, 34, 12, 0, Math.PI * 2); ctx.fill();

  ctx.fillStyle = '#ffffffd0';
  for (const c of clouds) {
    const x = c.x - 30, y = c.y, s = c.s;
    ctx.beginPath();
    ctx.arc(x, y, 7 * s, 0, Math.PI * 2);
    ctx.arc(x + 8 * s, y - 4 * s, 8 * s, 0, Math.PI * 2);
    ctx.arc(x + 17 * s, y, 7 * s, 0, Math.PI * 2);
    ctx.fill();
  }

  // colinas
  ctx.fillStyle = '#8cc98a';
  ctx.beginPath();
  ctx.moveTo(0, GROUND);
  for (let x = 0; x <= W; x += 4) ctx.lineTo(x, GROUND - 16 - 9 * Math.sin(x * 0.03) - 5 * Math.sin(x * 0.071 + 1));
  ctx.lineTo(W, GROUND);
  ctx.fill();

  // árvores
  for (const x of trees) {
    ctx.fillStyle = '#6b4a2b'; ctx.fillRect(x - 0.7, GROUND - 6, 1.4, 6);
    ctx.fillStyle = '#3e8a3a';
    ctx.beginPath(); ctx.arc(x, GROUND - 8, 4, 0, Math.PI * 2); ctx.fill();
  }

  for (let i = 0; i < 2; i++) drawHangar(i);

  // chão
  ctx.fillStyle = '#5fae4a'; ctx.fillRect(0, GROUND, W, 3);
  ctx.fillStyle = '#8b6b3d'; ctx.fillRect(0, GROUND + 3, W, H - GROUND - 3);
  ctx.fillStyle = '#7a5d33';
  for (let x = 4; x < W; x += 16) ctx.fillRect(x, GROUND + 8 + (x % 3) * 3, 3, 1.5);
}

function drawHangar(id) {
  const x = HANGAR_X[id], c = COLORS[id];
  ctx.fillStyle = '#d8c69c'; ctx.fillRect(x - 11, GROUND - 11, 22, 11);
  ctx.fillStyle = c.body;
  ctx.beginPath(); ctx.moveTo(x - 13, GROUND - 11); ctx.lineTo(x, GROUND - 18); ctx.lineTo(x + 13, GROUND - 11); ctx.closePath(); ctx.fill();
  ctx.fillStyle = '#3b2f22'; ctx.fillRect(x - 6, GROUND - 8, 12, 8);
  // bandeira
  const fx0 = id === 0 ? x + 9 : x - 9;
  ctx.fillStyle = '#444'; ctx.fillRect(fx0, GROUND - 27, 0.8, 16);
  ctx.fillStyle = c.body;
  ctx.fillRect(fx0 + 0.8, GROUND - 27 + Math.sin(time * 6 + id) * 0.6, 5, 3);
}

function drawPlane(p) {
  const c = COLORS[p.side.id];
  wrapped(p.x, 10, x => {
    ctx.save();
    ctx.translate(x, p.y);
    ctx.rotate(p.a);
    if (Math.cos(p.a) < 0) ctx.scale(1, -1);   // nunca de pernas para o ar quando vai para a esquerda
    const flashing = p.hitT > 0;
    // cauda e fuselagem
    ctx.fillStyle = flashing ? '#fff' : c.body;
    ctx.fillRect(-7, -4.5, 2, 3.5);
    ctx.fillRect(-6, -1.5, 12, 3);
    // asas
    ctx.fillStyle = flashing ? '#fff' : c.wing;
    ctx.fillRect(-2, -5, 6.5, 1.4);
    ctx.fillRect(-2, 1.5, 6.5, 1.4);
    ctx.fillRect(-7.5, -0.5, 3, 1);
    // suportes
    ctx.fillStyle = '#5a4630';
    ctx.fillRect(-1, -3.6, 0.6, 5.1);
    ctx.fillRect(3, -3.6, 0.6, 5.1);
    // rodas
    ctx.fillStyle = '#222';
    ctx.beginPath(); ctx.arc(1.5, 4, 1.1, 0, Math.PI * 2); ctx.fill();
    // piloto
    if (p.manned) { ctx.fillStyle = '#f2c79b'; ctx.fillRect(-3.4, -3.2, 1.8, 1.8); ctx.fillStyle = '#6b4a2b'; ctx.fillRect(-3.4, -3.4, 1.8, 0.7); }
    // motor e hélice
    ctx.fillStyle = '#333'; ctx.fillRect(5, -1.6, 1.6, 3.2);
    const ph = p.manned && !p.falling ? Math.abs(Math.sin(p.prop)) * 4 + 0.6 : 3.5;
    ctx.fillStyle = '#e8e8e8'; ctx.fillRect(6.6, -ph, 0.8, ph * 2);
    ctx.restore();
  });
}

function drawPilot(pl) {
  const c = COLORS[pl.side.id];
  wrapped(pl.x, 10, x => {
    const y = pl.y;
    if (pl.state === 'chute') {
      ctx.strokeStyle = '#0006'; ctx.lineWidth = 0.4;
      ctx.beginPath();
      ctx.moveTo(x - 7, y - 10); ctx.lineTo(x, y - 2);
      ctx.moveTo(x + 7, y - 10); ctx.lineTo(x, y - 2);
      ctx.moveTo(x, y - 17); ctx.lineTo(x, y - 2);
      ctx.stroke();
      ctx.fillStyle = c.chute;
      ctx.beginPath(); ctx.arc(x, y - 10, 7, Math.PI, 0); ctx.closePath(); ctx.fill();
      ctx.fillStyle = c.body;
      ctx.beginPath(); ctx.moveTo(x - 2.3, y - 10); ctx.arc(x, y - 10, 7, Math.PI * 1.33, Math.PI * 1.67); ctx.closePath(); ctx.fill();
    }
    // corpo
    ctx.fillStyle = c.body; ctx.fillRect(x - 1, y - 2, 2, 3);
    ctx.fillStyle = '#f2c79b'; ctx.fillRect(x - 1, y - 4, 2, 2);
    // pernas
    ctx.fillStyle = '#333';
    const step = pl.state === 'ground' && pl.walk ? Math.sin(time * 18) * 0.7 : 0;
    ctx.fillRect(x - 1 + step, y + 1, 0.8, 2);
    ctx.fillRect(x + 0.2 - step, y + 1, 0.8, 2);
    // braços a abanar em queda livre
    if (pl.state === 'free') { ctx.fillStyle = c.body; ctx.fillRect(x - 2.5, y - 2.5 + Math.sin(time * 30), 1, 1); ctx.fillRect(x + 1.5, y - 2.5 - Math.sin(time * 30), 1, 1); }
  });
}

function render() {
  ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
  drawBackground();

  for (const q of particles) {
    ctx.globalAlpha = Math.max(0, q.life / q.max);
    ctx.fillStyle = q.color;
    const s = q.size * (0.5 + 0.5 * q.life / q.max);
    ctx.fillRect(q.x - s / 2, q.y - s / 2, s, s);
  }
  ctx.globalAlpha = 1;

  for (const b of bullets) {
    ctx.fillStyle = b.owner.id === 0 ? '#fff38a' : '#ffcf8a';
    ctx.fillRect(b.x - 1, b.y - 0.6, 2, 1.2);
  }
  for (const p of planes) drawPlane(p);
  for (const pl of pilots) drawPilot(pl);
}

// ---------- HUD ----------
let lastHud = '';
function updateHud() {
  if (state !== 'playing' && state !== 'paused') return;
  const hp = s => (s && s.ctrl && s.ctrl.kind === 'plane' ? '■'.repeat(Math.max(0, s.ctrl.hp)) + '□'.repeat(MAX_HP - Math.max(0, s.ctrl.hp)) : '');
  const hint = playerHint();
  const key = [sides[0].score, sides[1].score, hp(sides[0]), hp(sides[1]), hint].join('|');
  if (key === lastHud) return;
  lastHud = key;
  $('score0').textContent = sides[0].score;
  $('score1').textContent = sides[1].score;
  $('hp0').textContent = hp(sides[0]);
  $('hp1').textContent = hp(sides[1]);
  $('hint').textContent = hint;
}

function playerHint() {
  if (mode === 'guest' && !guestBuf.length) return 'A receber o jogo…';
  const s = sides[me], c = s.ctrl;
  if (!c) return s.respawn > 0 ? `Novo avião em ${Math.ceil(s.respawn)}…` : '';
  if (c.kind === 'pilot') {
    if (c.state === 'ground') return `Corre até ao hangar ${COLORS[me].name}!`;
    if (c.state === 'chute') return 'Guia o paraquedas com ↺ ↻';
    return c.torn ? 'O paraquedas rasgou-se!' : '';
  }
  if (c.falling) return 'Estás a cair! SALTA!';
  if (c.stalled) return 'Perda de velocidade! Aponta o nariz para baixo';
  if (c.onGround && c.speed < TAKEOFF) return 'A ganhar velocidade…';
  if (c.onGround) return 'Puxa o nariz para cima para descolar';
  return '';
}

// ---------- Estados ----------
function show(id, on) { $(id).classList.toggle('hidden', !on); }

function enterPlaying() {
  state = 'playing';
  time = 0;
  lastHud = '';
  flashTimer = 0;
  $('flash').classList.remove('show');
  $('goal').textContent = WIN_SCORE;
  const names = { solo: ['TU', 'BOT'], host: ['TU', 'RIVAL'], guest: ['RIVAL', 'TU'] }[mode];
  $('name0').textContent = names[0];
  $('name1').textContent = names[1];
  ['menu', 'over', 'pause', 'lobby'].forEach(id => show(id, false));
  show('hud', true); show('topbtns', true);
  show('btnPause', mode === 'solo');
  show('touch', isTouch);
  lastNetRx = performance.now();
}

function startGame(kind) {
  sfx.init();
  mode = kind;
  me = 0;
  resetWorld(kind);
  remoteInput.left = remoteInput.right = remoteInput.fire = remoteInput.eject = false;
  hostLastEj = 0;
  netEvents = [];
  snapT = 0;
  enterPlaying();
  if (kind === 'host') Net.send({ t: 'start', v: 1 });
}

function startGuest() {
  sfx.init();
  mode = 'guest';
  me = 1;
  planes = []; pilots = []; bullets = []; particles = [];
  sides = [newSide(0, false, botInput()), newSide(1, false, playerInput)];
  guestBuf = []; renderT = 0; guestCosmetic.clear();
  lastKey = -1; ejectCount = 0; guestSendInput.lastEj = 0;
  enterPlaying();
}

function endGame(winner) {
  fx('over', winner.id);
}

function showOver(winnerId) {
  state = 'over';
  const won = winnerId === me;
  $('overTitle').textContent = won ? '🏆 Ganhaste!' : '💥 Perdeste!';
  $('overScore').textContent = `Tu ${sides[me].score} — ${sides[1 - me].score} ${foeName()}`;
  show('again', mode !== 'guest');
  show('waitHost', mode === 'guest');
  if (won) sfx.win(); else sfx.lose();
  setTimeout(() => { if (state === 'over') { show('over', true); show('touch', false); } }, 900);
}

function goMenu(note) {
  Net.send({ t: 'bye' });
  Net.close();
  mode = 'demo';
  me = 0;
  state = 'menu';
  resetWorld('demo');
  ['over', 'pause', 'hud', 'topbtns', 'touch', 'lobby'].forEach(id => show(id, false));
  $('hint').textContent = '';
  $('flash').classList.remove('show');
  $('menuNote').textContent = note || '';
  show('menu', true);
}

function setPaused(on) {
  if (mode !== 'solo') return;            // online não há pausa
  if (on && state === 'playing') { state = 'paused'; show('pause', true); }
  else if (!on && state === 'paused') { state = 'playing'; show('pause', false); }
}

function goFullscreen() {
  if (!isTouch) return;
  const el = document.documentElement;
  if (document.fullscreenElement || !el.requestFullscreen) return;
  el.requestFullscreen()
    .then(() => screen.orientation && screen.orientation.lock && screen.orientation.lock('landscape').catch(() => {}))
    .catch(() => {});
}

// ---------- Sala online ----------
const NET_TIMEOUT = 5000;        // ms sem notícias do adversário = ligação perdida
let roomCode = '';
let lastNetRx = 0;

function lobbyStatus(text, isError) {
  const el = $('lobbyStatus');
  el.textContent = text;
  el.classList.toggle('error', !!isError);
}

function netHandlers(extra) {
  return Object.assign({
    onOpen() {
      if (Net.role === 'host') startGame('host');
      else lobbyStatus('Ligado! À espera do anfitrião…');
    },
    onData(m) {
      lastNetRx = performance.now();
      if (m && m.t === 'bye') { goMenu('O adversário saiu do jogo.'); return; }
      if (Net.role === 'host') hostReceive(m);
      else guestReceive(m);
    },
    onClose(msg) {
      if (state === 'menu' && !$('lobby').classList.contains('hidden')) lobbyStatus(msg, true);
      else goMenu(msg);
    },
  }, extra);
}

function openLobby(kind, code) {
  sfx.init();
  $('menuNote').textContent = '';
  show('menu', false);
  show('lobby', true);
  show('hostBox', kind === 'host');
  show('joinBox', kind === 'join');
  $('lobbyTitle').textContent = kind === 'host' ? 'Criar sala' : 'Entrar numa sala';
  lobbyStatus('');
  if (kind === 'host') {
    roomCode = '';
    $('roomCode').textContent = '····';
    lobbyStatus('A criar a sala…');
    Net.host(netHandlers({
      onCode(c) { roomCode = c; $('roomCode').textContent = c; lobbyStatus('À espera do adversário…'); },
    }));
  } else {
    $('joinCode').value = Net.normCode(code);
    setTimeout(() => $('joinCode').focus(), 50);
  }
}

function joinRoom() {
  const code = Net.normCode($('joinCode').value);
  $('joinCode').value = code;
  if (code.length !== 4) { lobbyStatus('O código tem 4 caracteres.', true); return; }
  goFullscreen();
  lobbyStatus('A ligar…');
  Net.join(code, netHandlers({}));
}

async function shareRoom() {
  if (!roomCode) return;
  const url = location.href.split('#')[0] + '#' + roomCode;
  const text = `Joga comigo no AeroDuel! Código da sala: ${roomCode}`;
  if (navigator.share) {
    try { await navigator.share({ title: 'AeroDuel', text, url }); return; }
    catch (e) { if (e && e.name === 'AbortError') return; }
  }
  try { await navigator.clipboard.writeText(url); lobbyStatus('Link copiado! Envia-o ao teu adversário.'); }
  catch (e) { lobbyStatus(url); }
}

// ---------- Entrada: teclado ----------
const KEYMAP = {
  ArrowLeft: 'left', KeyA: 'left',
  ArrowRight: 'right', KeyD: 'right',
  Space: 'fire', KeyJ: 'fire', KeyZ: 'fire',
};
addEventListener('keydown', e => {
  if (e.target && e.target.tagName === 'INPUT') {
    if (e.key === 'Enter') joinRoom();
    return;
  }
  if (KEYMAP[e.code]) { playerInput[KEYMAP[e.code]] = true; e.preventDefault(); }
  if ((e.code === 'KeyE' || e.code === 'KeyK' || e.code === 'KeyX') && !e.repeat) playerInput.eject = true;
  if (e.code === 'KeyP' || e.code === 'Escape') setPaused(state === 'playing');
  if (e.code === 'Enter' && state === 'menu' && !$('menu').classList.contains('hidden')) startGame('solo');
});
addEventListener('keyup', e => { if (KEYMAP[e.code]) playerInput[KEYMAP[e.code]] = false; });
addEventListener('blur', () => { playerInput.left = playerInput.right = playerInput.fire = false; setPaused(true); });
document.addEventListener('visibilitychange', () => { if (document.hidden) setPaused(true); });

// ---------- Entrada: ecrã tátil ----------
const isTouch = 'ontouchstart' in window || matchMedia('(pointer: coarse)').matches;

function bindHold(id, key) {
  const el = $(id);
  const on = e => { e.preventDefault(); if (el.setPointerCapture) el.setPointerCapture(e.pointerId); playerInput[key] = true; el.classList.add('on'); sfx.init(); };
  const off = e => { e.preventDefault(); playerInput[key] = false; el.classList.remove('on'); };
  el.addEventListener('pointerdown', on);
  el.addEventListener('pointerup', off);
  el.addEventListener('pointercancel', off);
  el.addEventListener('lostpointercapture', off);
  el.addEventListener('contextmenu', e => e.preventDefault());
}
bindHold('bLeft', 'left');
bindHold('bRight', 'right');
bindHold('bFire', 'fire');
(() => {
  const el = $('bEject');
  el.addEventListener('pointerdown', e => { e.preventDefault(); playerInput.eject = true; el.classList.add('on'); });
  const off = () => el.classList.remove('on');
  el.addEventListener('pointerup', off);
  el.addEventListener('pointercancel', off);
  el.addEventListener('contextmenu', e => e.preventDefault());
})();

// ---------- Botões dos menus ----------
document.querySelectorAll('.diff button').forEach(btn => btn.addEventListener('click', () => {
  difficulty = btn.dataset.d;
  document.querySelectorAll('.diff button').forEach(b => b.classList.toggle('sel', b === btn));
}));
$('play').addEventListener('click', () => { goFullscreen(); startGame('solo'); });
$('btnHost').addEventListener('click', () => { goFullscreen(); openLobby('host'); });
$('btnJoin').addEventListener('click', () => openLobby('join'));
$('btnJoinGo').addEventListener('click', joinRoom);
$('btnShare').addEventListener('click', shareRoom);
$('btnLobbyCancel').addEventListener('click', () => goMenu());
$('again').addEventListener('click', () => startGame(mode === 'host' ? 'host' : 'solo'));
$('toMenu').addEventListener('click', () => goMenu());
$('quit').addEventListener('click', () => goMenu());
$('resume').addEventListener('click', () => setPaused(false));
$('btnPause').addEventListener('click', () => setPaused(true));
$('btnSound').addEventListener('click', e => { sfx.init(); e.currentTarget.textContent = sfx.toggle() ? '🔇' : '🔊'; });

// ---------- Arranque ----------
let last = performance.now();
function frame(now) {
  const dt = Math.min(1 / 30, (now - last) / 1000);
  last = now;
  if (mode === 'guest') {
    guestFrame(dt);
    if (state === 'playing' || state === 'over') guestSendInput(dt);
  } else if (state !== 'paused') {
    update(dt);
    if (mode === 'host') hostTick(dt);
  }
  if ((mode === 'host' || mode === 'guest') && now - lastNetRx > NET_TIMEOUT) goMenu('Perdeu-se a ligação ao adversário.');
  updateHud();
  render();
  requestAnimationFrame(frame);
}

addEventListener('pagehide', () => Net.send({ t: 'bye' }));

resize();
goMenu();
requestAnimationFrame(frame);

// link com código de sala (ex.: .../index.html#K7QF) abre logo o ecrã para entrar
if (/^#[A-Za-z0-9]{4}$/.test(location.hash)) openLobby('join', location.hash.slice(1));

// Ganchos para testes automáticos
window.__game = {
  get state() { return state; }, get mode() { return mode; }, get sides() { return sides; },
  get planes() { return planes; }, get pilots() { return pilots; },
  update, startGame, setDifficulty: d => (difficulty = d),
};
