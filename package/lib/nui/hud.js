// SIGF overlay: messages from the bricks (SendNUIMessage) -> captions, overlay image, sounds, music, mod events.
const sounds = new Map();
let music = null;
const handlers = {
  text(m) {
    const el = document.createElement('div');
    el.className = 'caption' + (m.font === 'body' ? ' body' : '');
    el.textContent = m.text;
    el.style.top = ((m.y ?? 0.2) * 100) + 'vh';
    el.style.fontSize = (m.size ?? 64) + 'px';
    el.style.color = m.color ?? '#fff';
    // Same height = replace the previous caption there.
    for (const old of document.querySelectorAll('#captions .caption')) if (old.style.top === el.style.top) old.remove();
    document.getElementById('captions').appendChild(el);
    requestAnimationFrame(() => el.classList.add('in'));
    setTimeout(() => { el.classList.remove('in'); setTimeout(() => el.remove(), 300); }, (m.sec ?? 3) * 1000);
  },
  overlay(m) {
    const el = document.getElementById('overlay');
    el.style.transition = 'none';
    el.style.backgroundImage = `url(../../${m.src})`;
    el.style.opacity = m.opacity ?? 0.85;
    setTimeout(() => { el.style.transition = `opacity ${m.fade ?? 0.6}s`; el.style.opacity = 0; }, (m.sec ?? 1.5) * 1000);
  },
  sound(m) {
    const a = new Audio(`../../${m.src}`);
    a.volume = Math.max(0, Math.min(1, m.volume ?? 1));
    a.loop = !!m.loop;
    if (m.rate) { a.preservesPitch = false; a.playbackRate = m.rate; }
    a.play().catch(() => {});
    sounds.set(m.id, a);
    a.onended = () => sounds.delete(m.id);
  },
  stopsound(m) { const a = sounds.get(m.id); if (a) { a.pause(); sounds.delete(m.id); } },
  music(m) {
    if (music) { music.pause(); music = null; }
    if (!m.src) return;
    music = new Audio(`../../${m.src}`);
    music.loop = true;
    music.volume = m.volume ?? 0.5;
    music.play().catch(() => {});
  },
  mod(m) { window.dispatchEvent(new CustomEvent('sigfmod', { detail: m.data })); },
};
window.sigfHandlers = handlers;   // guest.js adds its own
window.addEventListener('message', (e) => {
  const m = e.data;
  if (!m || !m.t) return;
  const h = handlers[m.t];
  if (h) try { h(m); } catch (err) { console.error('sigf hud', m.t, err); }
});
