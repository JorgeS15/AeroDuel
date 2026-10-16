'use strict';

// =====================================================================
//  AeroDuel — protótipo 2D de combate de biplanos (1 jogador vs bot)
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

const COLORS = [
  { body: '#2f6fd6', wing: '#9cc3ff', chute: '#e8f1ff' },
  { body: '#d63a2f', wing: '#ffb19c', chute: '#fff0ea' },
];

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
let difficulty = 'normal';
let time = 0;
const playerInput = { left: false, right: false, fire: false, eject: false };

const clouds = Array.from({ length: 6 }, (_, i) => ({ x: i * 70 + rand(0, 40), y: rand(18, 90), s: rand(0.7, 1.4), v: rand(2, 5) }));
const trees = [110, 128, 190, 255, 270];

function newSide(id, isBot) {
  return {
    id, isBot, score: 0, ctrl: null, respawn: 0,
    input: isBot ? { left: false, right: false, fire: false, eject: false } : playerInput,
    bot: { t: 0, noise: 0, ejectT: 0 },
  };
}

function resetWorld(humanPlays) {
  planes = []; pilots = []; bullets = []; particles = [];
  sides = [newSide(0, !humanPlays), newSide(1, true)];
  spawnPlane(sides[0]);
  spawnPlane(sides[1]);
}

function spawnPlane(side) {
  const right = side.id === 0;
  const p = {
    kind: 'plane', side,
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

// ---------- Pontuação e mensagens ----------
let flashTimer = 0;
function flash(text, color) {
  if (state !== 'playing') return;
  const el = $('flash');
  el.textContent = text;
  el.style.color = color || '#fff';
  el.classList.add('show');
  flashTimer = 1.6;
}

function award(loser, pts, text) {
  const winner = sides[1 - loser.id];
  winner.score += pts;
  if (state !== 'playing') {               // modo demonstração do menu
    if (winner.score >= WIN_SCORE) sides.forEach(s => (s.score = 0));
    return;
  }
  flash(text, winner.id === 0 ? '#9cff9c' : '#ffb19c');
  if (winner.score >= WIN_SCORE) endGame(winner);
}

// ---------- Ações ----------
function crashPlane(p) {
  if (p.dead) return;
  p.dead = true;
  explosion(p.x, Math.min(p.y, GROUND - 2));
  sfx.boom();
  if (p.side.id === 0 && state === 'playing') vibrate(150);
  if (p.manned) {
    p.side.ctrl = null;
    p.side.respawn = RESPAWN_TIME;
    award(p.side, 2, p.side.id === 1 ? 'Avião e piloto inimigos abatidos! +2' : 'Caíste com o avião! Bot +2');
  } else {
    award(p.side, 1, p.side.id === 1 ? 'Avião inimigo destruído! +1' : 'Perdeste o avião! Bot +1');
  }
}

function hitPlane(p) {
  p.hp--;
  p.hitT = 0.12;
  puff(p.x, p.y, '#ffe680', 6, 50, 0.25, 1.2, 0);
  sfx.hit();
  if (p.side.id === 0 && state === 'playing') vibrate(40);
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
    kind: 'pilot', side: p.side,
    x: p.x, y: p.y - 4,
    vx: Math.cos(p.a) * p.speed * 0.4,
    vy: Math.sin(p.a) * p.speed * 0.4 - 45,
    state: 'free', torn: false, t: 0, walk: 0, face: 1, dead: false,
  };
  pilots.push(pl);
  p.side.ctrl = pl;
  sfx.eject();
}

function killPilot(pl) {
  if (pl.dead) return;
  pl.dead = true;
  puff(pl.x, pl.y, '#b0182b', 10, 40, 0.5, 1.2, 60);
  sfx.hit();
  pl.side.ctrl = null;
  pl.side.respawn = RESPAWN_TIME;
  award(pl.side, 1, pl.side.id === 1 ? 'Piloto inimigo eliminado! +1' : 'O teu piloto foi abatido! Bot +1');
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
      if (p.side.id === 0) { sfx.repair(); flash('Avião reparado!', '#9cff9c'); }
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
      if (p.side.id === 0) sfx.land();
    } else {
      crashPlane(p);
      return;
    }
  }

  // fumo quando danificado
  p.smokeT -= dt;
  if (p.smokeT <= 0 && (p.hp < MAX_HP || p.falling)) {
    p.smokeT = p.falling ? 0.03 : p.hp === 1 ? 0.07 : 0.16;
    const dark = p.falling || p.hp === 1;
    particles.push({ x: p.x - Math.cos(p.a) * 6, y: p.y - Math.sin(p.a) * 6, vx: rand(-4, 4), vy: rand(-8, -2),
      life: 1.1, max: 1.1, color: dark ? '#333' : '#999', size: rand(2, 3.5), grav: -4 });
    if (p.falling && Math.random() < 0.5)
      particles.push({ x: p.x, y: p.y, vx: rand(-6, 6), vy: rand(-6, 0), life: 0.3, max: 0.3, color: '#ff8a25', size: 2, grav: 0 });
  }

  // disparar
  if (flying && inp.fire && p.cd <= 0) {
    p.cd = FIRE_CD;
    const c = Math.cos(p.a), s = Math.sin(p.a), v = BULLET_SPEED + p.speed * 0.5;
    bullets.push({ x: wrapX(p.x + c * 8), y: p.y + s * 8, vx: c * v, vy: s * v, life: BULLET_LIFE, owner: p.side });
    sfx.shoot(p.side.id === 0 && !p.side.isBot);
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
    if (!pl.torn && pl.t > 0.6) { pl.state = 'chute'; sfx.chute(); }
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
      if (pl.side.id === 0) flash('Novo avião!', '#9cc3ff');
    }
  }
}

// ---------- Bot ----------
function botThink(side, dt) {
  const inp = side.input, b = side.bot, D = DIFFS[difficulty];
  inp.left = inp.right = inp.fire = inp.eject = false;
  const me = side.ctrl;
  if (!me) return;

  if (me.kind === 'pilot') {
    if (me.state === 'free') return;
    const d = dxWrap(me.x, HANGAR_X[side.id]);
    if (Math.abs(d) > 1) { if (d < 0) inp.left = true; else inp.right = true; }
    return;
  }

  const p = me;
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

// ---------- Ciclo principal de atualização ----------
function update(dt) {
  time += dt;
  for (const c of clouds) c.x = (c.x + c.v * dt) % (W + 60);

  for (const s of sides) if (s.isBot) botThink(s, dt);

  for (const p of planes) if (!p.dead) updatePlane(p, dt);
  for (const pl of pilots) if (!pl.dead) updatePilot(pl, dt);

  // balas
  for (const b of bullets) {
    b.x = wrapX(b.x + b.vx * dt);
    b.y += b.vy * dt;
    b.life -= dt;
    if (b.y >= GROUND) { b.life = 0; puff(b.x, GROUND, '#a58a5c', 3, 20, 0.3, 1, 40); continue; }
    if (b.y < -10) { b.life = 0; continue; }
    for (const p of planes) {
      if (p.dead || p.falling || p.side === b.owner) continue;
      if (dist2(b.x, b.y, p.x, p.y) < 36) { hitPlane(p); b.life = 0; break; }
    }
    if (b.life <= 0) continue;
    for (const pl of pilots) {
      if (pl.dead || pl.side === b.owner) continue;
      if (dist2(b.x, b.y, pl.x, pl.y) < 12) { killPilot(pl); b.life = 0; break; }
      if (pl.state === 'chute' && dist2(b.x, b.y, pl.x, pl.y - 10) < 40) {
        pl.state = 'free'; pl.torn = true; b.life = 0;
        puff(pl.x, pl.y - 10, COLORS[pl.side.id].chute, 8, 30, 0.6, 1.5, 20);
        if (state === 'playing') flash(pl.side.id === 0 ? 'Paraquedas rasgado!' : 'Rasgaste o paraquedas!', '#fff6c2');
        break;
      }
    }
  }

  // aviões contra pilotos e contra aviões
  for (const p of planes) {
    if (p.dead) continue;
    for (const pl of pilots) {
      if (pl.dead || pl.side === p.side) continue;
      if (dist2(p.x, p.y, pl.x, pl.y) < 36) killPilot(pl);
      else if (pl.state === 'chute' && dist2(p.x, p.y, pl.x, pl.y - 10) < 49) { pl.state = 'free'; pl.torn = true; }
    }
  }
  const alive = planes.filter(p => !p.dead && !p.falling);
  if (alive.length === 2 && alive[0].side !== alive[1].side && dist2(alive[0].x, alive[0].y, alive[1].x, alive[1].y) < 64) {
    for (const p of alive) { p.hp = 0; hitPlane(p); }
  }

  // partículas
  for (const q of particles) {
    q.vy += q.grav * dt;
    q.x += q.vx * dt; q.y += q.vy * dt;
    q.life -= dt;
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
  particles = particles.filter(q => q.life > 0);
  if (particles.length > 600) particles.splice(0, particles.length - 600);

  if (flashTimer > 0) { flashTimer -= dt; if (flashTimer <= 0) $('flash').classList.remove('show'); }
}

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
  const fx = id === 0 ? x + 9 : x - 9;
  ctx.fillStyle = '#444'; ctx.fillRect(fx, GROUND - 27, 0.8, 16);
  ctx.fillStyle = c.body;
  ctx.fillRect(fx + 0.8, GROUND - 27 + Math.sin(time * 6 + id) * 0.6, 5, 3);
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
  const hp = s => (s.ctrl && s.ctrl.kind === 'plane' ? '■'.repeat(Math.max(0, s.ctrl.hp)) + '□'.repeat(MAX_HP - Math.max(0, s.ctrl.hp)) : '');
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
  const s = sides[0], c = s.ctrl;
  if (!c) return s.respawn > 0 ? `Novo avião em ${Math.ceil(s.respawn)}…` : '';
  if (c.kind === 'pilot') {
    if (c.state === 'ground') return 'Corre até ao hangar azul!';
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

function startGame() {
  sfx.init();
  resetWorld(true);
  state = 'playing';
  time = 0;
  lastHud = '';
  $('goal').textContent = WIN_SCORE;
  show('menu', false); show('over', false); show('pause', false);
  show('hud', true); show('topbtns', true);
  show('touch', isTouch);
  if (isTouch) {
    const el = document.documentElement;
    if (!document.fullscreenElement && el.requestFullscreen) {
      el.requestFullscreen().then(() => screen.orientation && screen.orientation.lock && screen.orientation.lock('landscape').catch(() => {})).catch(() => {});
    }
  }
}

function endGame(winner) {
  state = 'over';
  const won = winner.id === 0;
  $('overTitle').textContent = won ? '🏆 Ganhaste!' : '💥 Perdeste!';
  $('overScore').textContent = `Tu ${sides[0].score} — ${sides[1].score} Bot`;
  won ? sfx.win() : sfx.lose();
  setTimeout(() => { if (state === 'over') { show('over', true); show('touch', false); } }, 900);
}

function goMenu() {
  state = 'menu';
  resetWorld(false);
  show('over', false); show('pause', false); show('hud', false); show('topbtns', false); show('touch', false);
  $('hint').textContent = '';
  $('flash').classList.remove('show');
  show('menu', true);
}

function setPaused(on) {
  if (on && state === 'playing') { state = 'paused'; show('pause', true); }
  else if (!on && state === 'paused') { state = 'playing'; show('pause', false); }
}

// ---------- Entrada: teclado ----------
const KEYMAP = {
  ArrowLeft: 'left', KeyA: 'left',
  ArrowRight: 'right', KeyD: 'right',
  Space: 'fire', KeyJ: 'fire', KeyZ: 'fire',
};
addEventListener('keydown', e => {
  if (KEYMAP[e.code]) { playerInput[KEYMAP[e.code]] = true; e.preventDefault(); }
  if ((e.code === 'KeyE' || e.code === 'KeyK' || e.code === 'KeyX') && !e.repeat) playerInput.eject = true;
  if (e.code === 'KeyP' || e.code === 'Escape') setPaused(state === 'playing');
  if (e.code === 'Enter' && state === 'menu') startGame();
});
addEventListener('keyup', e => { if (KEYMAP[e.code]) playerInput[KEYMAP[e.code]] = false; });
addEventListener('blur', () => { playerInput.left = playerInput.right = playerInput.fire = false; setPaused(true); });
document.addEventListener('visibilitychange', () => { if (document.hidden) setPaused(true); });

// ---------- Entrada: ecrã tátil ----------
const isTouch = 'ontouchstart' in window || matchMedia('(pointer: coarse)').matches;

function bindHold(id, key) {
  const el = $(id);
  const on = e => { e.preventDefault(); el.setPointerCapture && el.setPointerCapture(e.pointerId); playerInput[key] = true; el.classList.add('on'); sfx.init(); };
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
$('play').addEventListener('click', startGame);
$('again').addEventListener('click', startGame);
$('toMenu').addEventListener('click', goMenu);
$('quit').addEventListener('click', goMenu);
$('resume').addEventListener('click', () => setPaused(false));
$('btnPause').addEventListener('click', () => setPaused(true));
$('btnSound').addEventListener('click', e => { sfx.init(); e.currentTarget.textContent = sfx.toggle() ? '🔇' : '🔊'; });

// ---------- Arranque ----------
let last = performance.now();
function frame(now) {
  const dt = Math.min(1 / 30, (now - last) / 1000);
  last = now;
  if (state === 'playing' || state === 'menu' || state === 'over') update(dt);
  updateHud();
  render();
  requestAnimationFrame(frame);
}

resize();
goMenu();
requestAnimationFrame(frame);

// Ganchos para testes automáticos
window.__game = { get state() { return state; }, get sides() { return sides; }, get planes() { return planes; }, get pilots() { return pilots; }, update, startGame, setDifficulty: d => (difficulty = d) };
