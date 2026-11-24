'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'kartbahn';
const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);

let menuData = null;
let tiers = [];
let currentSub = 'rating';
let lapTimer = null, bannerTimer = null, cdTimer = null;
let hudState = { outline: null, bounds: null, sectors: 3 };
let selPaint = null;

// Ungefähre Anzeigefarben der GTA-Lackierungen (nur für die Vorschau im Menü)
const PAINT_HEX = {
    yellow: '#ffcc00', black: '#111111', white: '#f5f5f5', red: '#dc2626', blue: '#2563eb', green: '#16a34a',
    silver: '#b8bec7', gold: '#d4a017', teal: '#2dd4bf', chrome: '#e5e7eb', purple: '#7c3aed'
};

// ===== Hilfen =====
function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).then((r) => r.json()).catch(() => ({}));
}

function fmt(ms) {
    if (ms === null || ms === undefined) return '--:--.---';
    ms = Math.max(0, Math.floor(ms));
    const m = Math.floor(ms / 60000);
    const s = Math.floor(ms / 1000) % 60;
    const r = ms % 1000;
    return `${m}:${String(s).padStart(2, '0')}.${String(r).padStart(3, '0')}`;
}

function fmtDelta(ms) {
    if (ms === null || ms === undefined) return '–';
    const sign = ms > 0 ? '+' : '−';
    return `${sign}${(Math.abs(ms) / 1000).toFixed(3)}`;
}

function esc(str) {
    return String(str ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function money(v) { return `${Number(v || 0).toLocaleString('de-DE')} $`; }

function tierOf(rating, list) {
    list = list || tiers;
    let t = list[0] || { name: '-', color: '#888', min: 0 };
    for (const x of list) if (rating >= x.min) t = x;
    return t;
}

function tierBadge(rating, list) {
    const t = tierOf(rating, list);
    return `<span class="tier" style="color:${t.color}">${esc(t.name)}</span>`;
}

function delta(d) {
    if (d > 0) return `<span class="plus">+${d}</span>`;
    if (d < 0) return `<span class="minus">${d}</span>`;
    return '<span>±0</span>';
}

// ===== Benachrichtigungen =====
function notify(text, kind) {
    const el = document.createElement('div');
    el.className = `note ${kind || 'info'}`;
    el.textContent = text;
    $('#notify').appendChild(el);
    setTimeout(() => el.remove(), kind === 'record' ? 8000 : 5000);
}

function banner(text, kind) {
    const el = $('#banner');
    el.textContent = text;
    el.className = kind === 'error' ? 'error' : '';
    clearTimeout(bannerTimer);
    bannerTimer = setTimeout(() => el.classList.add('hidden'), 1800);
}

// ===== Menü =====
function openMenu() { $('#menu').classList.remove('hidden'); }
function closeMenu() { $('#menu').classList.add('hidden'); }

function switchTab(tab) {
    $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    $$('.page').forEach((p) => p.classList.add('hidden'));
    $(`#page-${tab}`).classList.remove('hidden');
    $('#top-title').textContent = { drive: 'Fahren', ranking: 'Rangliste', profile: 'Profil' }[tab];
    if (tab === 'ranking') loadRanking();
}

function modeOptions() {
    return (menuData.modes || []).map((m) => `<option value="${esc(m.id)}">${esc(m.label)}${m.ranked ? ' (Rating)' : ''}</option>`).join('');
}

// Mini-Streckenumriss als SVG (für die Karten)
function trackSvg(outline, start) {
    if (!outline || outline.length < 3) return '';
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const [x, y] of outline) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
    const w = maxX - minX || 1, h = maxY - minY || 1, sc = Math.min(280 / w, 120 / h);
    const pr = (x, y) => `${(10 + (x - minX) * sc).toFixed(1)},${(10 + (maxY - y) * sc).toFixed(1)}`;
    const pts = outline.map(([x, y]) => pr(x, y)).join(' ');
    const [sx, sy] = pr(start[0], start[1]).split(',');
    return `<svg viewBox="0 0 ${20 + w * sc} ${20 + h * sc}" preserveAspectRatio="xMaxYMid meet">
        <polygon points="${pts}" fill="none" stroke="rgba(255,204,0,.15)" stroke-width="12" stroke-linejoin="round"/>
        <polygon points="${pts}" fill="none" stroke="#ffcc00" stroke-width="3" stroke-linejoin="round"/>
        <circle cx="${sx}" cy="${sy}" r="6" fill="#fff" stroke="#111" stroke-width="2"/></svg>`;
}

function renderHead() {
    if (!menuData) return;
    const p = menuData.profile;
    const t = tierOf(p.rating);
    const initials = String(p.name || '?').split(' ').map((x) => x[0]).join('').slice(0, 2).toUpperCase();
    $('#head-profile').innerHTML = `<span>${esc(p.name)}</span>${tierBadge(p.rating)}<span class="r">${p.rating}</span>
        <span class="avatar" style="background:${t.color}">${esc(initials)}</span>`;
    const s = menuData.settings;
    $('#side-foot').innerHTML = `Framework: <b>${esc(s.framework || 'standalone')}</b><br>Strecken: <b>${menuData.tracks.length}</b>`;
}

function renderDrive() {
    if (!menuData) return;
    renderHead();
    const s = menuData.settings;
    const sess = menuData.session;
    const prizes = s.prizes.map((p, i) => `${i + 1}. ${money(p)}`).join(' · ');
    $('#drive-info').innerHTML = `
        <div class="chip">Startgebühr <b>${s.fee > 0 ? money(s.fee) : 'kostenlos'}</b></div>
        <div class="chip">Preisgeld <b>${s.fee > 0 || s.prizes[0] > 0 ? prizes : '–'}</b></div>
        <div class="chip">Fahrer <b>${s.minPlayers}–${s.maxPlayers}</b></div>
        <div class="chip acc">Modi <b>${(menuData.modes || []).length}</b></div>`;

    let html = '';
    // 13) Laufende Rennen zum Zuschauen
    if (s.spectate && menuData.running && menuData.running.length && !sess) {
        html += menuData.running.map((r) => `<div class="running"><span class="live"></span><span class="mode-tag">${esc(r.modeLabel)}</span>
            <b>${esc(r.trackName)}</b><span style="color:var(--muted)">${r.count} Fahrer · läuft</span>
            <button class="btn ghost" data-act="spectate" data-id="${r.id}" style="margin-left:auto">Zuschauen</button></div>`).join('');
    }

    if (!menuData.tracks.length) { $('#track-list').innerHTML = html + '<div class="empty">Keine Strecken vorhanden.</div>'; return; }
    html += menuData.tracks.map((t) => {
        const lb = t.lobby;
        const inThis = sess && sess.trackId === t.id;
        let lobbyHtml = '';
        let raceBtn;
        if (lb && lb.state === 'lobby') {
            const racers = (lb.racers || []).map((r) => `<span>${esc(r.name)} · ${r.rating}</span>`).join('');
            lobbyHtml = `<div class="lobby"><div class="lobby-top"><span class="mode-tag">${esc(lb.modeLabel)}</span>
                <span>${lb.mode === 'elim' ? 'Runden = Fahrer − 1' : lb.laps + ' Runden'} · Start in <b>${lb.timeLeft} s</b></span>
                <span class="count">${lb.count}/${lb.max}</span></div>
                <div class="racers">${racers}</div>`;
            raceBtn = inThis
                ? `<button class="btn danger" data-act="leave">Lobby verlassen</button>`
                : `<button class="btn primary" data-act="join" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>Beitreten</button>`;
            // 18) Wetten
            if (s.bets && !inThis && lb.racers && lb.racers.length) {
                const mine = lb.bets && lb.bets.mine;
                lobbyHtml += `<div class="bet">Wettpool <b style="color:var(--accent)">${money(lb.bets ? lb.bets.pool : 0)}</b>
                    ${mine ? `· Deine Wette: <b>${money(mine.amount)}</b>` : `
                    <select class="inp" id="bet-target-${esc(t.id)}">${lb.racers.map((r) => `<option value="${r.src}">${esc(r.name)}</option>`).join('')}</select>
                    <input class="inp" type="number" min="${s.betMin}" max="${s.betMax}" value="${s.betMin}" id="bet-amount-${esc(t.id)}">
                    <button class="btn ghost" data-act="bet" data-track="${esc(t.id)}">Wetten</button>`}</div>`;
            }
            lobbyHtml += '</div>';
        } else if (lb) {
            lobbyHtml = `<div class="lobby"><span class="mode-tag">${esc(lb.modeLabel)}</span>Rennen läuft (${lb.count} Fahrer)</div>`;
            raceBtn = s.spectate && !sess
                ? `<button class="btn ghost" data-act="spectate" data-id="${lb.id}">Zuschauen</button>`
                : `<button class="btn primary" disabled>Rennen läuft</button>`;
        } else {
            raceBtn = `<select class="inp" id="mode-${esc(t.id)}">${modeOptions()}</select>
                <span class="laps-select">Runden <input type="number" min="${s.minLaps}" max="${s.maxLaps}" value="${t.laps}" id="laps-${esc(t.id)}"></span>
                <button class="btn primary" data-act="join" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>Rennen starten</button>`;
        }
        const ghostSel = s.ghost ? `<select class="inp" id="ghost-${esc(t.id)}" title="Ghost">
            <option value="pb">Ghost: eigene Bestzeit</option><option value="record">Ghost: Streckenrekord</option><option value="none">Ohne Ghost</option></select>` : '';
        const live = lb && lb.state !== 'lobby';
        return `<div class="track">
            <div class="thumb">
                <div class="badge">${live ? '<span class="live">LIVE</span>' : ''}${lb && lb.state === 'lobby' ? '<span>LOBBY OFFEN</span>' : ''}${t.raised ? '<span>ANGEHOBEN</span>' : ''}</div>
                ${trackSvg(t.outline, t.start)}
                <div class="t-name"><h3>${esc(t.name)}</h3><small>${t.length} m · ${t.grid} Startplätze · ${t.laps} Runden</small></div>
            </div>
            <div class="track-body">
                <div class="times">
                    <div class="rec"><label>Streckenrekord</label><b class="mono">${fmt(t.record && t.record.time)}</b><small>${t.record ? esc(t.record.name) : ''}</small></div>
                    <div class="pb"><label>Deine Bestzeit</label><b class="mono">${fmt(t.pb)}</b></div>
                </div>
                ${lobbyHtml}
                <div class="actions">${raceBtn}</div>
                <div class="actions">${ghostSel}<span class="grow"></span>
                    <button class="btn ghost" data-act="tt" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>⏱ Zeitfahren${s.ttFee > 0 ? ' · ' + money(s.ttFee) : ''}</button>
                </div>
            </div>
        </div>`;
    }).join('');
    $('#track-list').innerHTML = html;
}

function renderProfile() {
    if (!menuData) return;
    const p = menuData.profile;
    const t = tierOf(p.rating);
    const idx = tiers.indexOf(t);
    const next = tiers[idx + 1];
    const pct = next ? Math.min(100, Math.max(0, ((p.rating - t.min) / (next.min - t.min)) * 100)) : 100;
    const pbs = menuData.tracks.map((tr) => `<tr><td>${esc(tr.name)}</td><td class="mono">${fmt(tr.pb)}</td><td class="mono">${fmt(tr.record && tr.record.time)}</td></tr>`).join('');
    const custom = menuData.custom || { paint: 'yellow', number: 0 };
    if (!selPaint) selPaint = custom.paint;
    const peak = p.peak_rating || p.rating;
    const paints = (menuData.paints || []).map((x) => {
        const locked = peak < x.min;
        return `<div class="paint ${x.id === selPaint ? 'sel' : ''} ${locked ? 'locked' : ''}" data-paint="${esc(x.id)}" data-locked="${locked ? 1 : 0}">
            <i style="background:${PAINT_HEX[x.id] || '#888'}"></i>${esc(x.name)}${locked ? `<br><small>ab ${x.min}</small>` : ''}</div>`;
    }).join('');
    const unlocked = menuData.unlocked || {};
    const achs = (menuData.achievements || []).map((a) => `<div class="ach ${unlocked[a.code] ? 'on' : ''}"><b>${esc(a.name)}</b><small>${esc(a.desc)}</small></div>`).join('');
    const doneCount = Object.keys(unlocked).length;

    $('#profile-content').innerHTML = `
        <div class="profile-head">
            <div class="rating-big">${p.rating}</div>
            <div>
                <div class="pname">${esc(p.name)}</div>
                <div>${tierBadge(p.rating)} <span style="color:var(--muted);font-size:12px">Höchst-Rating ${p.peak_rating}</span></div>
                <div class="tier-bar"><div style="width:${pct}%;background:${t.color}"></div></div>
                <div style="color:var(--muted);font-size:11px;margin-top:4px">${next ? `Nächste Stufe: ${esc(next.name)} ab ${next.min}` : 'Höchste Stufe erreicht'}</div>
            </div>
        </div>
        <div class="stats">
            <div class="stat"><label>Rennen</label><span>${p.races}</span></div>
            <div class="stat"><label>Siege</label><span>${p.wins}</span></div>
            <div class="stat"><label>Podien</label><span>${p.podiums}</span></div>
            <div class="stat"><label>DNFs</label><span>${p.dnfs}</span></div>
            <div class="stat"><label>Runden</label><span>${p.laps}</span></div>
            <div class="stat"><label>Siegquote</label><span>${p.races ? Math.round((p.wins / p.races) * 100) : 0} %</span></div>
            <div class="stat"><label>Preisgeld</label><span>${money(p.prize_money)}</span></div>
            <div class="stat"><label>Höchst-Rating</label><span>${p.peak_rating}</span></div>
        </div>
        <table><thead><tr><th>Strecke</th><th>Deine Bestzeit</th><th>Streckenrekord</th></tr></thead><tbody>${pbs}</tbody></table>

        <div class="section-title">Kart-Design</div>
        <div class="paints">${paints}</div>
        <div class="actions" style="margin-top:10px">
            <span class="laps-select">Startnummer <input type="number" min="0" max="99" value="${custom.number || 0}" id="kart-number"></span>
            <span style="color:var(--muted);font-size:12px">0 = Startplatz</span>
            <button class="btn primary" data-act="saveCustom">Speichern</button>
        </div>

        <div class="section-title">Erfolge (${doneCount}/${(menuData.achievements || []).length})</div>
        <div class="achs">${achs}</div>`;
}

async function loadRanking() {
    const box = $('#ranking-content');
    const sel = $('#times-track');
    sel.classList.toggle('hidden', currentSub !== 'times');
    box.innerHTML = '<div class="empty">Lade …</div>';
    const meId = menuData && menuData.profile.identifier;
    if (currentSub === 'rating') {
        const d = await post('getLeaderboard');
        const rows = d.rows || [];
        if (d.tiers) tiers = d.tiers;
        box.innerHTML = rows.length ? `<table><thead><tr><th>#</th><th>Fahrer</th><th>Stufe</th><th>Rating</th><th>Rennen</th><th>Siege</th><th>Podien</th></tr></thead><tbody>
            ${rows.map((r, i) => `<tr class="${r.identifier === meId ? 'me' : ''}"><td class="rank p${i + 1}">${i + 1}</td><td>${esc(r.name)}</td><td>${tierBadge(r.rating)}</td><td><b>${r.rating}</b></td><td>${r.races}</td><td>${r.wins}</td><td>${r.podiums}</td></tr>`).join('')}
            </tbody></table>` : '<div class="empty">Noch keine Rennen gefahren.</div>';
    } else if (currentSub === 'season') {
        const d = await post('getSeason');
        const rows = d.rows || [];
        const prizes = (d.prizes || []).map((p, i) => `${i + 1}. ${money(p)}`).join(' · ');
        const last = d.last && d.last.results && d.last.results[0]
            ? `<div class="chip">Letzter Meister (${esc(d.last.season)}): <b>${esc(d.last.results[0].name)}</b> mit ${d.last.results[0].points} Punkten</div>` : '';
        box.innerHTML = `<div class="info-row"><div class="chip">Saison <b>${esc(d.season || '')}</b> · nur Ranked-Rennen</div>
            ${prizes ? `<div class="chip">Saison-Preisgeld <b>${prizes}</b></div>` : ''}${last}</div>` +
            (rows.length ? `<table><thead><tr><th>#</th><th>Fahrer</th><th>Punkte</th><th>Rennen</th><th>Siege</th></tr></thead><tbody>
            ${rows.map((r, i) => `<tr class="${r.identifier === meId ? 'me' : ''}"><td class="rank p${i + 1}">${i + 1}</td><td>${esc(r.name)}</td><td><b>${r.points}</b></td><td>${r.races}</td><td>${r.wins}</td></tr>`).join('')}
            </tbody></table>` : '<div class="empty">Diese Woche noch keine Ranked-Rennen.</div>');
    } else if (currentSub === 'times') {
        if (!sel.options.length && menuData) {
            sel.innerHTML = menuData.tracks.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
        }
        const d = await post('getTrackTimes', { track: sel.value });
        const rows = d.rows || [];
        box.innerHTML = rows.length ? `<table><thead><tr><th>#</th><th>Fahrer</th><th>Bestzeit</th><th>Abstand</th><th>Runden</th></tr></thead><tbody>
            ${rows.map((r, i) => `<tr class="${r.identifier === meId ? 'me' : ''}"><td class="rank p${i + 1}">${i + 1}</td><td>${esc(r.name)}</td><td class="mono">${fmt(r.best)}</td><td class="mono">${i ? '+' + (((r.best - rows[0].best) / 1000).toFixed(3)) : '–'}</td><td>${r.laps}</td></tr>`).join('')}
            </tbody></table>` : '<div class="empty">Noch keine Zeiten auf dieser Strecke.</div>';
    } else {
        const d = await post('getRecent');
        const rows = d.rows || [];
        box.innerHTML = rows.length ? rows.map((r) => {
            const date = new Date(r.ts * 1000).toLocaleString('de-DE');
            const res = (r.results || []).map((x) => `${x.dnf ? 'DNF' : x.place + '.'} ${esc(x.name)} ${x.dnf || x.out ? '' : '(' + fmt(x.time) + ')'} ${delta(x.delta)}`).join(' · ');
            return `<div class="race-card"><h4><span>${r.modeLabel ? `<span class="mode-tag">${esc(r.modeLabel)}</span>` : ''}${esc(r.trackName)} – ${r.laps} Runden</span> <small>${date}</small></h4><div class="res">${res}</div></div>`;
        }).join('') : '<div class="empty">Noch keine Rennen.</div>';
    }
}

// ===== 12) Minimap =====
function setOutline(outline) {
    const svg = $('#minimap');
    if (!outline || !outline.length) { svg.classList.add('hidden'); hudState.bounds = null; return; }
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const [x, y] of outline) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
    const size = Math.max(maxX - minX, maxY - minY) || 1;
    hudState.bounds = { minX, minY, maxX, maxY, size };
    const pts = outline.map(([x, y]) => project(x, y).join(',')).join(' ');
    const [sx, sy] = project(outline[0][0], outline[0][1]);
    svg.innerHTML = `<polygon points="${pts}" fill="none" stroke="#3a3f4b" stroke-width="9" stroke-linejoin="round"/>
        <polygon points="${pts}" fill="none" stroke="#9aa0ad" stroke-width="2" stroke-linejoin="round"/>
        <rect x="${sx - 4}" y="${sy - 4}" width="8" height="8" fill="#fff"/><g id="mm-dots"></g>`;
    svg.classList.remove('hidden');
}

function project(x, y) {
    const b = hudState.bounds;
    const pad = 16, scale = (200 - pad * 2) / b.size;
    const ox = (200 - (b.maxX - b.minX) * scale) / 2, oy = (200 - (b.maxY - b.minY) * scale) / 2;
    return [Math.round(ox + (x - b.minX) * scale), Math.round(200 - (oy + (y - b.minY) * scale))]; // Y nach oben
}

function drawDots(dots) {
    const g = document.getElementById('mm-dots');
    if (!g || !hudState.bounds || !dots) return;
    const teams = hudState.teamColors || [];
    g.innerHTML = dots.slice().sort((a, b) => a[2] - b[2]).map((d) => {
        const [x, y] = project(d[0], d[1]);
        let col = '#e5e7eb', r = 4;
        if (d[2] === 1) { col = '#ffcc00'; r = 6; }
        else if (d[2] === 2) col = 'rgba(255,255,255,.45)';
        else if (d[3] && teams[d[3] - 1]) col = teams[d[3] - 1];
        return `<circle cx="${x}" cy="${y}" r="${r}" fill="${col}" stroke="#000" stroke-width="1.5"/>`;
    }).join('');
}

// ===== HUD =====
function showHud(d) {
    $('#hud').classList.toggle('hidden', !d.show);
    if (!d.show) {
        $('#hud-table').innerHTML = '';
        ['#hud-boost', '#hud-item', '#hud-slip', '#hud-shield', '#hud-ghost', '#minimap'].forEach((s) => $(s).classList.add('hidden'));
        return;
    }
    const race = d.type === 'race';
    $('#hud-track').textContent = `${d.trackName} · ${race ? (d.modeLabel || 'Rennen') : 'Zeitfahren'}`;
    $('#hud-pos-wrap').classList.toggle('hidden', !race);
    $('#hud-total-wrap').classList.toggle('hidden', !race);
    $('#hud-table').classList.toggle('hidden', !race);
    $('#hud-pb').textContent = fmt(d.pb);
    $('#hud-record').textContent = fmt(d.record);
    $('#hud-best').textContent = fmt(null);
    $('#hud-delta').textContent = '–';
    $('#hud-delta').className = 'mono';
    const team = $('#hud-team');
    team.classList.toggle('hidden', !d.team);
    if (d.team) { team.textContent = d.team.name; team.style.color = d.team.hex; }
    hudState.sectors = d.sectors || 3;
    $('#hud-sectors').innerHTML = Array.from({ length: hudState.sectors }, (_, i) => `<div id="sec-${i + 1}">S${i + 1}</div>`).join('');
    $('#hud-boost').classList.toggle('hidden', !d.boost);
    $('#hud-item').classList.toggle('hidden', !d.items);
    $('#hud-item-name').textContent = '–';
    $('#hud-ghost').classList.add('hidden');
    setOutline(d.outline);
}

function hudTick(d) {
    $('#hud-speed').textContent = d.speed;
    // Tacho-Bogen füllen, Vollausschlag bei 130 km/h
    const gl = $('#gauge-arc').getTotalLength ? $('#gauge-arc').getTotalLength() : 377;
    const arc = Math.min(1, d.speed / 130) * gl;
    $('#gauge-arc').style.strokeDasharray = `${arc.toFixed(1)} 999`;
    $('#hud-lap').textContent = d.type === 'race' ? `${d.lap}/${d.laps}` : `${d.lap}`;
    $('#hud-cp').textContent = `${d.cp}/${d.cps}`;
    if (d.lapTime !== null && d.lapTime !== undefined) $('#hud-laptime').textContent = fmt(d.lapTime);
    if (d.total !== null && d.total !== undefined) $('#hud-total').textContent = fmt(d.total);
    $('#hud-best').textContent = fmt(d.best);
    $('#hud-pb').textContent = fmt(d.pb);
    $('#hud-record').textContent = fmt(d.record);
    if (d.pos) { $('#hud-pos').textContent = d.pos; $('#hud-count').textContent = `/${d.count}`; }
    drawDots(d.dots);
}

function split(d) {
    const el = $('#hud-delta');
    if (d.delta !== null && d.delta !== undefined) {
        el.textContent = fmtDelta(d.delta);
        el.className = 'mono ' + (d.delta > 0 ? 'pos-delta' : 'neg-delta');
    }
    if (d.sector) {
        if (d.sector === 1) for (let i = 2; i <= hudState.sectors; i++) { const s = $(`#sec-${i}`); if (s) { s.className = ''; s.textContent = `S${i}`; } }
        const s = $(`#sec-${d.sector}`);
        if (s) { s.className = d.color; s.textContent = fmt(d.sectorTime).replace(/^0:/, ''); }
    }
}

function standings(rows, me, teamColors) {
    $('#hud-table').innerHTML = rows.map((r) => {
        const dot = teamColors && teamColors[r.src] ? `<i class="team-dot" style="background:${teamColors[r.src]}"></i>` : '';
        const status = r.dnf ? 'DNF' : r.out ? 'RAUS' : r.finished ? fmt(r.time) : 'R' + r.lap;
        return `<div class="row ${r.src === me ? 'me' : ''}"><span class="p">${r.dnf ? '–' : r.pos}</span>
            <span class="n">${dot}${esc(r.name)}</span><span class="s">${status}</span></div>`;
    }).join('');
    // Teamfarben auch für die Minimap
    const colors = [];
    for (const r of rows) if (r.team && teamColors && teamColors[r.src]) colors[r.team - 1] = teamColors[r.src];
    hudState.teamColors = colors;
}

function countdown(v) {
    const el = $('#countdown');
    el.classList.remove('hidden', 'go');
    el.textContent = v;
    if (v === 'GO') el.classList.add('go');
    el.style.animation = 'none'; void el.offsetWidth; el.style.animation = '';
    clearTimeout(cdTimer);
    cdTimer = setTimeout(() => el.classList.add('hidden'), v === 'GO' ? 1200 : 950);
}

function lapFlash(d) {
    const el = $('#lapflash');
    const labels = { pb: 'Persönliche Bestzeit', record: 'Neuer Streckenrekord', invalid: 'Ungültige Runde', normal: `Runde ${d.lap}` };
    el.className = d.kind;
    el.innerHTML = `<small>${labels[d.kind]}</small><span class="mono">${fmt(d.time)}</span>`;
    clearTimeout(lapTimer);
    lapTimer = setTimeout(() => el.classList.add('hidden'), 3500);
}

// ===== Ergebnis =====
function showResult(d) {
    const box = $('#result-content');
    if (d.type === 'race') {
        const mine = d.results.find((r) => r.src === d.me);
        const t = d.tiers || tiers;
        const teamList = d.teamList || [];
        let teamHtml = '';
        if (d.teams) {
            teamHtml = `<div class="res-top">${d.teams.map((sc, i) => `<div class="stat"><label style="color:${teamList[i] ? teamList[i].hex : '#fff'}">${esc(teamList[i] ? teamList[i].name : 'Team ' + (i + 1))}</label><span class="big">${sc}</span></div>`).join('')}</div>`;
        }
        const top = mine ? `
            <div class="res-top">
                <div class="stat"><label>Position</label><span class="big">${mine.dnf ? 'DNF' : mine.place + '.'}</span></div>
                <div class="stat"><label>Gesamtzeit</label><span class="mono">${mine.out ? 'ausgeschieden' : fmt(mine.time)}</span></div>
                <div class="stat"><label>Beste Runde</label><span class="mono">${fmt(mine.best)}</span></div>
                <div class="stat"><label>Rating</label><span>${mine.newRating} ${d.ranked ? delta(mine.delta) : ''}</span></div>
                <div class="stat"><label>Preisgeld</label><span>${money(mine.prize)}</span></div>
            </div>` : '';
        box.innerHTML = `${top}${teamHtml}
            <div style="color:var(--muted);margin-bottom:8px"><span class="mode-tag">${esc(d.modeLabel || 'Rennen')}</span>${esc(d.trackName)} · ${d.laps} Runden${d.ranked ? '' : ' · ohne Rating-Wertung'}</div>
            <table><thead><tr><th>#</th><th>Fahrer</th><th>Zeit</th><th>Beste Runde</th><th>Rating</th><th>+/-</th>${d.ranked ? '<th>Saison</th>' : ''}<th>Preisgeld</th></tr></thead><tbody>
            ${d.results.map((r) => {
                const dot = r.team && teamList[r.team - 1] ? `<i class="team-dot" style="background:${teamList[r.team - 1].hex}"></i>` : '';
                return `<tr class="${r.src === d.me ? 'me' : ''}"><td class="rank p${r.dnf ? 0 : r.place}">${r.dnf ? 'DNF' : r.place}</td><td>${dot}${esc(r.name)}</td>
                <td class="mono">${r.dnf ? '–' : r.out ? 'raus' : fmt(r.time)}</td><td class="mono">${fmt(r.best)}</td>
                <td>${r.newRating} ${tierBadge(r.newRating, t)}</td><td>${delta(r.delta)}</td>${d.ranked ? `<td>+${r.season || 0}</td>` : ''}<td>${r.prize ? money(r.prize) : '–'}</td></tr>`;
            }).join('')}
            </tbody></table>`;
    } else {
        const laps = d.laps || [];
        box.innerHTML = `
            <div class="res-top">
                <div class="stat"><label>Gefahrene Runden</label><span class="big">${laps.length}</span></div>
                <div class="stat"><label>Beste Runde</label><span class="mono">${fmt(d.best)}</span></div>
                <div class="stat"><label>Persönliche Bestzeit</label><span class="mono">${fmt(d.pb)}</span></div>
                <div class="stat"><label>Streckenrekord</label><span class="mono">${fmt(d.record && d.record.time)}</span></div>
            </div>
            <div style="color:var(--muted);margin-bottom:8px">${esc(d.trackName)} · Zeitfahren</div>
            <table><thead><tr><th>Runde</th><th>Zeit</th><th>Status</th></tr></thead><tbody>
            ${laps.map((l, i) => `<tr><td>${i + 1}</td><td class="mono">${fmt(l.time)}</td><td>${l.valid ? '<span class="plus">gültig</span>' : '<span class="minus">ungültig</span>'}</td></tr>`).join('') || '<tr><td colspan="3" class="empty">Keine Runden</td></tr>'}
            </tbody></table>`;
    }
    $('#result').classList.remove('hidden');
}

function closeResult() {
    $('#result').classList.add('hidden');
    post('closeResult');
}

// ===== Events =====
document.addEventListener('click', async (e) => {
    const paint = e.target.closest('.paint');
    if (paint) {
        if (paint.dataset.locked === '1') return;
        selPaint = paint.dataset.paint;
        $$('.paint').forEach((p) => p.classList.toggle('sel', p === paint));
        return;
    }
    const b = e.target.closest('button');
    if (!b) return;
    if (b.classList.contains('tab')) return switchTab(b.dataset.tab);
    if (b.classList.contains('sub')) {
        currentSub = b.dataset.sub;
        $$('.sub').forEach((x) => x.classList.toggle('active', x === b));
        return loadRanking();
    }
    const act = b.dataset.act;
    const track = b.dataset.track;
    if (act === 'join') {
        const inp = document.getElementById(`laps-${track}`);
        const mode = document.getElementById(`mode-${track}`);
        b.disabled = true;
        await post('joinRace', { track, laps: inp ? Number(inp.value) : null, mode: mode ? mode.value : null });
    } else if (act === 'leave') {
        await post('leaveLobby');
    } else if (act === 'tt') {
        const g = document.getElementById(`ghost-${track}`);
        b.disabled = true;
        await post('startTT', { track, ghost: g ? g.value : 'pb' });
    } else if (act === 'bet') {
        await post('placeBet', {
            track,
            target: Number(document.getElementById(`bet-target-${track}`).value),
            amount: Number(document.getElementById(`bet-amount-${track}`).value)
        });
    } else if (act === 'spectate') {
        await post('spectate', { id: Number(b.dataset.id) });
    } else if (act === 'saveCustom') {
        await post('saveCustom', { paint: selPaint, number: Number($('#kart-number').value) });
    }
});

$('#btn-close').addEventListener('click', () => post('close'));
$('#btn-result-close').addEventListener('click', closeResult);
$('#times-track').addEventListener('change', loadRanking);

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!$('#result').classList.contains('hidden')) return closeResult();
    if (!$('#menu').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    switch (d.action) {
        case 'open': openMenu(); break;
        case 'close': closeMenu(); break;
        case 'menuData':
            menuData = d.data;
            tiers = d.data.tiers || tiers;
            if (!document.activeElement || !document.activeElement.matches('input, select')) {
                renderDrive();
                renderProfile();
            }
            break;
        case 'hud': showHud(d); break;
        case 'hudTick': hudTick(d); break;
        case 'split': split(d); break;
        case 'dots': drawDots(d.dots); break;
        case 'standings': standings(d.rows, d.me, d.teamColors); break;
        case 'countdown': countdown(d.value); break;
        case 'lap': lapFlash(d); break;
        case 'banner': banner(d.text, d.kind); break;
        case 'notify': notify(d.text, d.kind); break;
        case 'record': notify(d.text, 'record'); break;
        case 'result': closeMenu(); showResult(d.data); break;
        case 'boost':
            $('#hud-boost').classList.toggle('hidden', !d.enabled);
            $('#hud-boost-fill').style.width = `${Math.max(0, Math.min(100, d.charge))}%`;
            break;
        case 'boostActive': $('#hud-boost').classList.toggle('active', d.on); break;
        case 'slip': $('#hud-slip').classList.toggle('hidden', !d.on); break;
        case 'shield':
            $('#hud-shield').classList.remove('hidden');
            setTimeout(() => $('#hud-shield').classList.add('hidden'), d.ms);
            break;
        case 'item':
            $('#hud-item').classList.toggle('hidden', !d.enabled);
            $('#hud-item-name').textContent = d.item || '–';
            break;
        case 'ghost':
            $('#hud-ghost').classList.remove('hidden');
            $('#hud-ghost').textContent = `👻 Ghost: ${d.name || ''} · ${fmt(d.time)}`;
            break;
        case 'spectate':
            $('#spectate').classList.toggle('hidden', !d.on);
            if (d.on) {
                $('#spec-track').textContent = d.trackName;
                $('#hud').classList.remove('hidden');
                ['.hud-main', '.hud-speed', '#hud-item'].forEach((s) => $(s).classList.add('hidden'));
                setOutline(d.outline);
            } else {
                ['.hud-main', '.hud-speed'].forEach((s) => $(s).classList.remove('hidden'));
            }
            break;
        case 'spectateName':
            $('#spec-name').textContent = d.name;
            $('#spec-idx').textContent = `${d.idx}/${d.total}`;
            break;
        case 'podium':
            $('#podium').classList.toggle('hidden', !d.on);
            if (d.on) [1, 2, 3].forEach((i) => { $(`#pod-${i}`).textContent = d.names[i - 1] || '–'; });
            break;
    }
});

// Lobby-Countdown im Menü lokal herunterzählen
setInterval(() => {
    if (!menuData || $('#menu').classList.contains('hidden')) return;
    let changed = false;
    for (const t of menuData.tracks) {
        if (t.lobby && t.lobby.state === 'lobby' && t.lobby.timeLeft > 0) { t.lobby.timeLeft--; changed = true; }
    }
    if (changed && !$('#page-drive').classList.contains('hidden') && !document.activeElement.matches('input, select')) renderDrive();
}, 1000);
