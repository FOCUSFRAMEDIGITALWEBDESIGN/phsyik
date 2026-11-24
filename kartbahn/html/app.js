'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'kartbahn';
const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);

let menuData = null;
let tiers = [];
let currentSub = 'rating';
let lapTimer = null, bannerTimer = null, cdTimer = null;

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
function openMenu() {
    $('#menu').classList.remove('hidden');
}

function closeMenu() {
    $('#menu').classList.add('hidden');
}

function switchTab(tab) {
    $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    $$('.page').forEach((p) => p.classList.add('hidden'));
    $(`#page-${tab}`).classList.remove('hidden');
    if (tab === 'ranking') loadRanking();
}

function renderDrive() {
    if (!menuData) return;
    const s = menuData.settings;
    const sess = menuData.session;
    const prizes = s.prizes.map((p, i) => `${i + 1}. ${money(p)}`).join(' · ');
    $('#drive-info').innerHTML = `
        <div class="chip">Startgebühr <b>${s.fee > 0 ? money(s.fee) : 'kostenlos'}</b></div>
        <div class="chip">Preisgeld <b>${s.fee > 0 || s.prizes[0] > 0 ? prizes : '–'}</b></div>
        <div class="chip">Fahrer <b>${s.minPlayers}–${s.maxPlayers}</b></div>
        <div class="chip">Dein Rating <b>${menuData.profile.rating}</b> ${tierBadge(menuData.profile.rating)}</div>`;

    const list = $('#track-list');
    if (!menuData.tracks.length) { list.innerHTML = '<div class="empty">Keine Strecken vorhanden.</div>'; return; }
    list.innerHTML = menuData.tracks.map((t) => {
        const lb = t.lobby;
        const inThis = sess && sess.trackId === t.id;
        let lobbyHtml = '';
        let raceBtn;
        if (lb && lb.state === 'lobby') {
            lobbyHtml = `<div class="lobby">Lobby offen: <b>${lb.count}/${lb.max}</b> Fahrer · ${lb.laps} Runden · Start in <b>${lb.timeLeft} s</b></div>`;
            raceBtn = inThis
                ? `<button class="btn danger" data-act="leave">Lobby verlassen</button>`
                : `<button class="btn primary" data-act="join" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>Beitreten</button>`;
        } else if (lb) {
            lobbyHtml = `<div class="lobby">Rennen läuft (${lb.count} Fahrer)</div>`;
            raceBtn = `<button class="btn primary" disabled>Rennen läuft</button>`;
        } else {
            raceBtn = `<span class="laps-select">Runden <input type="number" min="${s.minLaps}" max="${s.maxLaps}" value="${t.laps}" id="laps-${esc(t.id)}"></span>
                <button class="btn primary" data-act="join" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>Rennen starten</button>`;
        }
        return `<div class="track">
            <h3>${esc(t.name)} <small>${t.length} m · ${t.grid} Startplätze</small></h3>
            <div class="meta">
                <div class="rec">Rekord: <b class="mono">${fmt(t.record && t.record.time)}</b> ${t.record ? esc(t.record.name) : ''}</div>
                <div>Deine Bestzeit: <b class="mono">${fmt(t.pb)}</b></div>
                <div>Standard-Runden: <b>${t.laps}</b></div>
                <div>Zeitfahren: <b>${s.ttFee > 0 ? money(s.ttFee) : 'kostenlos'}</b></div>
            </div>
            ${lobbyHtml}
            <div class="actions">${raceBtn}
                <button class="btn ghost" data-act="tt" data-track="${esc(t.id)}" ${sess ? 'disabled' : ''}>Zeitfahren</button>
            </div>
        </div>`;
    }).join('');
}

function renderProfile() {
    if (!menuData) return;
    const p = menuData.profile;
    const t = tierOf(p.rating);
    const idx = tiers.indexOf(t);
    const next = tiers[idx + 1];
    const pct = next ? Math.min(100, Math.max(0, ((p.rating - t.min) / (next.min - t.min)) * 100)) : 100;
    const pbs = menuData.tracks.map((tr) => `<tr><td>${esc(tr.name)}</td><td class="mono">${fmt(tr.pb)}</td><td class="mono">${fmt(tr.record && tr.record.time)}</td></tr>`).join('');
    $('#profile-content').innerHTML = `
        <div class="profile-head">
            <div class="rating-big">${p.rating}</div>
            <div>
                <div style="font-size:20px;font-weight:700">${esc(p.name)}</div>
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
        <table><thead><tr><th>Strecke</th><th>Deine Bestzeit</th><th>Streckenrekord</th></tr></thead><tbody>${pbs}</tbody></table>`;
}

async function loadRanking() {
    const box = $('#ranking-content');
    const sel = $('#times-track');
    sel.classList.toggle('hidden', currentSub !== 'times');
    box.innerHTML = '<div class="empty">Lade …</div>';
    if (currentSub === 'rating') {
        const d = await post('getLeaderboard');
        const rows = d.rows || [];
        if (d.tiers) tiers = d.tiers;
        box.innerHTML = rows.length ? `<table><thead><tr><th>#</th><th>Fahrer</th><th>Stufe</th><th>Rating</th><th>Rennen</th><th>Siege</th><th>Podien</th></tr></thead><tbody>
            ${rows.map((r, i) => `<tr class="${menuData && r.identifier === menuData.profile.identifier ? 'me' : ''}"><td class="rank p${i + 1}">${i + 1}</td><td>${esc(r.name)}</td><td>${tierBadge(r.rating)}</td><td><b>${r.rating}</b></td><td>${r.races}</td><td>${r.wins}</td><td>${r.podiums}</td></tr>`).join('')}
            </tbody></table>` : '<div class="empty">Noch keine Rennen gefahren.</div>';
    } else if (currentSub === 'times') {
        if (!sel.options.length && menuData) {
            sel.innerHTML = menuData.tracks.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join('');
        }
        const d = await post('getTrackTimes', { track: sel.value });
        const rows = d.rows || [];
        box.innerHTML = rows.length ? `<table><thead><tr><th>#</th><th>Fahrer</th><th>Bestzeit</th><th>Abstand</th><th>Runden</th></tr></thead><tbody>
            ${rows.map((r, i) => `<tr class="${menuData && r.identifier === menuData.profile.identifier ? 'me' : ''}"><td class="rank p${i + 1}">${i + 1}</td><td>${esc(r.name)}</td><td class="mono">${fmt(r.best)}</td><td class="mono">${i ? '+' + (((r.best - rows[0].best) / 1000).toFixed(3)) : '–'}</td><td>${r.laps}</td></tr>`).join('')}
            </tbody></table>` : '<div class="empty">Noch keine Zeiten auf dieser Strecke.</div>';
    } else {
        const d = await post('getRecent');
        const rows = d.rows || [];
        box.innerHTML = rows.length ? rows.map((r) => {
            const date = new Date(r.ts * 1000).toLocaleString('de-DE');
            const res = (r.results || []).map((x) => `${x.dnf ? 'DNF' : x.place + '.'} ${esc(x.name)} ${x.dnf ? '' : '(' + fmt(x.time) + ')'} ${delta(x.delta)}`).join(' · ');
            return `<div class="race-card"><h4>${esc(r.trackName)} – ${r.laps} Runden <small>${date}</small></h4><div class="res">${res}</div></div>`;
        }).join('') : '<div class="empty">Noch keine Rennen.</div>';
    }
}

// ===== HUD =====
function showHud(d) {
    $('#hud').classList.toggle('hidden', !d.show);
    if (!d.show) { $('#hud-table').innerHTML = ''; return; }
    $('#hud-track').textContent = `${d.trackName} · ${d.type === 'race' ? 'Rennen' : 'Zeitfahren'}`;
    $('#hud-pos-wrap').classList.toggle('hidden', d.type !== 'race');
    $('#hud-total-wrap').classList.toggle('hidden', d.type !== 'race');
    $('#hud-table').classList.toggle('hidden', d.type !== 'race');
    $('#hud-pb').textContent = fmt(d.pb);
    $('#hud-record').textContent = fmt(d.record);
    $('#hud-best').textContent = fmt(null);
}

function hudTick(d) {
    $('#hud-speed').textContent = d.speed;
    $('#hud-lap').textContent = d.type === 'race' ? `${d.lap}/${d.laps}` : `${d.lap}`;
    $('#hud-cp').textContent = `${d.cp}/${d.cps}`;
    if (d.lapTime !== null && d.lapTime !== undefined) $('#hud-laptime').textContent = fmt(d.lapTime);
    if (d.total !== null && d.total !== undefined) $('#hud-total').textContent = fmt(d.total);
    $('#hud-best').textContent = fmt(d.best);
    $('#hud-pb').textContent = fmt(d.pb);
    $('#hud-record').textContent = fmt(d.record);
    if (d.pos) { $('#hud-pos').textContent = d.pos; $('#hud-count').textContent = `/${d.count}`; }
}

function standings(rows, me) {
    $('#hud-table').innerHTML = rows.map((r) => `<div class="row ${r.src === me ? 'me' : ''}">
        <span class="p">${r.dnf ? '–' : r.pos}</span><span class="n">${esc(r.name)}</span>
        <span class="s">${r.dnf ? 'DNF' : r.finished ? fmt(r.time) : 'R' + r.lap}</span></div>`).join('');
}

function countdown(v) {
    const el = $('#countdown');
    el.classList.remove('hidden', 'go');
    void el.offsetWidth; // Animation neu starten
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
        const mine = d.results.find((r) => r.src === d.me) || {};
        const t = d.tiers || tiers;
        box.innerHTML = `
            <div class="res-top">
                <div class="stat"><label>Position</label><span class="big">${mine.dnf ? 'DNF' : mine.place + '.'}</span></div>
                <div class="stat"><label>Gesamtzeit</label><span class="mono">${fmt(mine.time)}</span></div>
                <div class="stat"><label>Beste Runde</label><span class="mono">${fmt(mine.best)}</span></div>
                <div class="stat"><label>Rating</label><span>${mine.newRating} ${delta(mine.delta)}</span></div>
                <div class="stat"><label>Preisgeld</label><span>${money(mine.prize)}</span></div>
            </div>
            <div style="color:var(--muted);margin-bottom:8px">${esc(d.trackName)} · ${d.laps} Runden</div>
            <table><thead><tr><th>#</th><th>Fahrer</th><th>Zeit</th><th>Beste Runde</th><th>Rating</th><th>+/-</th><th>Preisgeld</th></tr></thead><tbody>
            ${d.results.map((r) => `<tr class="${r.src === d.me ? 'me' : ''}"><td class="rank p${r.dnf ? 0 : r.place}">${r.dnf ? 'DNF' : r.place}</td><td>${esc(r.name)}</td>
                <td class="mono">${r.dnf ? '–' : fmt(r.time)}</td><td class="mono">${fmt(r.best)}</td>
                <td>${r.newRating} ${tierBadge(r.newRating, t)}</td><td>${delta(r.delta)}</td><td>${r.prize ? money(r.prize) : '–'}</td></tr>`).join('')}
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
    const b = e.target.closest('button');
    if (!b) return;
    if (b.classList.contains('tab')) return switchTab(b.dataset.tab);
    if (b.classList.contains('sub')) {
        currentSub = b.dataset.sub;
        $$('.sub').forEach((x) => x.classList.toggle('active', x === b));
        return loadRanking();
    }
    const act = b.dataset.act;
    if (act === 'join') {
        const inp = document.getElementById(`laps-${b.dataset.track}`);
        b.disabled = true;
        await post('joinRace', { track: b.dataset.track, laps: inp ? Number(inp.value) : null });
    } else if (act === 'leave') {
        await post('leaveLobby');
    } else if (act === 'tt') {
        b.disabled = true;
        await post('startTT', { track: b.dataset.track });
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
            renderDrive();
            renderProfile();
            break;
        case 'hud': showHud(d); break;
        case 'hudTick': hudTick(d); break;
        case 'standings': standings(d.rows, d.me); break;
        case 'countdown': countdown(d.value); break;
        case 'lap': lapFlash(d); break;
        case 'banner': banner(d.text, d.kind); $('#banner').classList.remove('hidden'); break;
        case 'notify': notify(d.text, d.kind); break;
        case 'record': notify(d.text, 'record'); break;
        case 'result': closeMenu(); showResult(d.data); break;
    }
});

// Lobby-Countdown im Menü lokal herunterzählen
setInterval(() => {
    if (!menuData || $('#menu').classList.contains('hidden')) return;
    let changed = false;
    for (const t of menuData.tracks) {
        if (t.lobby && t.lobby.state === 'lobby' && t.lobby.timeLeft > 0) { t.lobby.timeLeft--; changed = true; }
    }
    if (changed && !$('#page-drive').classList.contains('hidden') && !document.activeElement.matches('input')) renderDrive();
}, 1000);
