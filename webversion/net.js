'use strict';

// =====================================================================
//  Ligação online 1 contra 1 com PeerJS (WebRTC)
//  O anfitrião cria uma sala com um código de 4 letras; o convidado
//  liga-se a esse código. Depois disso os dados vão diretamente de um
//  telemóvel para o outro.
// =====================================================================

const Net = (() => {
  const PREFIX = 'aeroduel-v1-';
  const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // sem 0/O e 1/I
  const params = new URLSearchParams(location.search);
  let peer = null, conn = null, handlers = {}, role = null, joinTimer = 0, retries = 0;

  const newCode = () => Array.from({ length: 4 }, () => ALPHABET[Math.floor(Math.random() * ALPHABET.length)]).join('');
  const normCode = s => (s || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);

  // ?peerhost=localhost:9000 usa um PeerServer próprio em vez do servidor público do PeerJS
  function peerOptions() {
    const o = { debug: 0 };
    const h = params.get('peerhost');
    if (h) {
      const [host, port] = h.split(':');
      Object.assign(o, { host, port: Number(port) || 443, path: '/', secure: !/^(localhost|127\.|192\.168\.|10\.)/.test(host) });
    }
    return o;
  }

  function errText(e) {
    switch (e && e.type) {
      case 'peer-unavailable': return 'Sala não encontrada. Confirma o código.';
      case 'browser-incompatible': return 'Este browser não suporta jogo online.';
      case 'network': case 'server-error': case 'socket-error': case 'socket-closed':
        return 'Sem ligação ao servidor. Verifica a internet.';
      default: return 'Erro de ligação' + (e && e.type ? ` (${e.type})` : '') + '.';
    }
  }

  function close() {
    clearTimeout(joinTimer);
    const c = conn, p = peer;
    conn = null; peer = null; handlers = {}; role = null;
    try { if (c) c.close(); } catch (e) { /* ignorar */ }
    try { if (p) p.destroy(); } catch (e) { /* ignorar */ }
  }

  function fail(msg) {
    const h = handlers;
    close();
    if (h.onClose) h.onClose(msg);
  }

  function attach(c) {
    conn = c;
    c.on('open', () => { clearTimeout(joinTimer); if (handlers.onOpen) handlers.onOpen(); });
    c.on('data', d => {
      if (conn !== c) return;
      if (d && d.t === 'full') return fail('A sala já está cheia.');
      if (handlers.onData) handlers.onData(d);
    });
    c.on('close', () => { if (conn === c) fail('O adversário saiu do jogo.'); });
    c.on('error', () => { if (conn === c) fail('A ligação falhou.'); });
  }

  function startHost() {
    const code = newCode();
    peer = new Peer(PREFIX + code, peerOptions());
    peer.on('open', () => { if (handlers.onCode) handlers.onCode(code); });
    peer.on('connection', c => {
      if (conn) {                                   // só um adversário por sala
        c.on('open', () => { c.send({ t: 'full' }); setTimeout(() => c.close(), 300); });
        return;
      }
      attach(c);
    });
    peer.on('error', e => {
      if (e.type === 'unavailable-id' && retries++ < 5) {   // código já em uso: tentar outro
        const p = peer; peer = null;
        try { p.destroy(); } catch (err) { /* ignorar */ }
        startHost();
      } else if (!(conn && conn.open)) {          // depois de ligados, só conta a ligação direta
        fail(errText(e));
      }
    });
  }

  function host(h) {
    close();
    handlers = h; role = 'host'; retries = 0;
    if (!window.Peer) return fail('O PeerJS não carregou. Verifica a ligação à internet.');
    startHost();
  }

  function join(rawCode, h) {
    close();
    handlers = h; role = 'guest';
    const code = normCode(rawCode);
    if (code.length !== 4) return fail('O código tem 4 caracteres.');
    if (!window.Peer) return fail('O PeerJS não carregou. Verifica a ligação à internet.');
    peer = new Peer(peerOptions());
    peer.on('open', () => attach(peer.connect(PREFIX + code, { reliable: true, serialization: 'json' })));
    peer.on('error', e => { if (!(conn && conn.open)) fail(errText(e)); });
    joinTimer = setTimeout(() => { if (!(conn && conn.open)) fail('Não foi possível ligar à sala.'); }, 15000);
  }

  function send(msg) {
    if (conn && conn.open) {
      try { conn.send(msg); } catch (e) { /* a ligação vai fechar e avisar */ }
    }
  }

  return {
    host, join, send, close, normCode,
    get role() { return role; },
    get connected() { return !!(conn && conn.open); },
  };
})();
