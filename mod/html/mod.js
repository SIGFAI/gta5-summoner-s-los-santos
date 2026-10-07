// Summoner's Los Santos HUD: ability bar, nexus bars, scoreboard, announcements.
(function () {
  const root = document.getElementById('mod');
  root.innerHTML = `
    <div id="lol-top">
      <div class="side blue"><div class="nx"><div class="fill" id="nxb"></div><span id="nxbt"></span></div><div class="pips" id="pipb"></div></div>
      <div class="mid"><div class="score"><b id="kb">0</b><i>ORDER</i><em id="tm">0:00</em><i>VOID</i><b id="kr">0</b></div></div>
      <div class="side red"><div class="nx"><div class="fill" id="nxr"></div><span id="nxrt"></span></div><div class="pips" id="pipr"></div></div>
    </div>
    <div id="lol-banner"></div>
    <div id="lol-end"></div>
    <div id="lol-bar">
      <div class="champ"><div class="nm" id="cn">AURELIA</div><div class="lv" id="lv">LV 1</div>
        <div class="hp"><div class="fill" id="hpf"></div></div><div class="gold"><span class="coin"></span><b id="gd">500</b></div></div>
      <div class="abil" id="ab"></div>
    </div>`;
  const keys = ['q', 'w', 'e', 'r'];
  const names = { q: 'STARBOLT', w: 'AEGIS', e: 'PHASE', r: 'STARFALL' };
  const ab = document.getElementById('ab');
  for (const k of keys) {
    const d = document.createElement('div');
    d.className = 'slot'; d.id = 'sl' + k;
    d.innerHTML = `<img src="../../img/icon_${k}.png"><div class="cdv" id="cd${k}"></div><div class="cdt" id="ct${k}"></div><div class="key">${k.toUpperCase()}</div><div class="an">${names[k]}</div>`;
    ab.appendChild(d);
  }
  const $ = (id) => document.getElementById(id);
  const pips = (id, n, max) => {
    const el = $(id);
    if (el.childElementCount !== max) { el.innerHTML = ''; for (let i = 0; i < max; i++) el.appendChild(document.createElement('span')); }
    [...el.children].forEach((c, i) => c.className = i < n ? 'on' : '');
  };
  let bannerT, endT;
  window.addEventListener('sigfmod', (e) => {
    const m = e.detail || {};
    if (m.hud) {
      const h = m.hud;
      $('nxb').style.width = (100 * h.nb / h.nbm) + '%'; $('nxbt').textContent = Math.max(0, Math.ceil(h.nb)) + '';
      $('nxr').style.width = (100 * h.nr / h.nrm) + '%'; $('nxrt').textContent = Math.max(0, Math.ceil(h.nr)) + '';
      pips('pipb', h.tb, 1); pips('pipr', h.tr, 1);
      $('kb').textContent = h.kb; $('kr').textContent = h.kr;
      const s = Math.floor(h.t); $('tm').textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
      if (h.keys) keys.forEach((k, i) => { $('sl' + k).querySelector('.key').textContent = h.keys[i]; });
      $('gd').textContent = h.gold; $('lv').textContent = 'LV ' + h.lv; $('cn').textContent = h.name;
      $('hpf').style.width = Math.max(0, Math.min(100, h.hp)) + '%';
      for (const k of keys) {
        const c = h.cd[k], mx = h.cdm[k];
        const dv = $('cd' + k), tt = $('ct' + k), sl = $('sl' + k);
        if (c > 0.05) { dv.style.height = (100 * c / mx) + '%'; tt.textContent = c >= 10 ? Math.ceil(c) : c.toFixed(1); sl.classList.remove('ready'); }
        else { dv.style.height = '0%'; tt.textContent = ''; sl.classList.add('ready'); }
      }
    }
    if (m.cast) { const sl = $('sl' + m.cast); sl.classList.remove('pop'); void sl.offsetWidth; sl.classList.add('pop'); }
    if (m.banner) {
      const b = $('lol-banner'); b.textContent = m.banner; b.style.color = m.color || '#f0e6d2';
      b.classList.add('in'); clearTimeout(bannerT); bannerT = setTimeout(() => b.classList.remove('in'), (m.sec || 3) * 1000);
    }
    if (m.end) {
      const el = $('lol-end'); el.textContent = m.end; el.className = 'in ' + (m.end === 'VICTORY' ? 'win' : 'lose');
      clearTimeout(endT); endT = setTimeout(() => el.className = '', (m.sec || 8) * 1000);
    }
  });
})();
