-- Summoner's Los Santos: a League-style lane across the Sandy Shores runway.
-- Order (blue) and Void (red) minion waves march to the enemy turret and nexus; the champion casts Q W E R.
Lol = Lol or {}
Sigf._killer = Sigf._killer or {}

local BLUE, RED = { 70, 170, 255 }, { 255, 70, 45 }
local COL = { blue = BLUE, red = RED }
local function foe(team) return team == 'blue' and 'red' or 'blue' end

local stage = Sigf.Stage()
local DEMO = stage == 'demo'
local PLAYER_HERO = DEMO or stage == ''
local WAVE_SEC = DEMO and 13 or 24
local LANE_NEXUS, LANE_TURRET = 40.0, 17.0

local S = {}                      -- structures
local M = {}                      -- minions: ped -> info
local C = {}                      -- champions: team -> info
local beams, projs, domes, dashes, meteors, rings, bursts = {}, {}, {}, {}, {}, {}, {}
local L                           -- lane layout
local match = { over = false, t0 = 0, wave = 0, kills = { blue = 0, red = 0 }, running = false }
local hud = { gold = 300, xp = 0, lv = 1, mul = 1.0, items = 0 }
Lol.hud = hud

local ITEMS = {
	{ 350, 'Long Sword', 0.15 }, { 650, 'Lich Staff', 0.2 }, { 950, 'Infinity Orb', 0.25 },
	{ 1300, 'Void Staff', 0.25 }, { 1700, 'Archmage Hat', 0.3 }, { 2200, 'Trinity Force', 0.35 },
}

-- ---------- small helpers ----------
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function flat(v) return vector3(v.x, v.y, 0.0) end
local function norm2(v)
	local f = flat(v)
	local l = #f
	if l < 0.001 then return vector3(1.0, 0.0, 0.0) end
	return f / l
end

local function gz(x, y, hint)
	local ok, z = GetGroundZFor_3dCoord(x, y, hint + 40.0, false)
	return ok and z or hint
end

local function pt(t, lat)
	local x, y = L.c.x + L.dir.x * t + L.side.x * (lat or 0), L.c.y + L.dir.y * t + L.side.y * (lat or 0)
	return vector3(x, y, gz(x, y, L.c.z))
end

local function banner(text, col, sec) Sigf.Nui({ banner = text, color = col or '#f0e6d2', sec = sec or 3 }) end

local function alive(ped) return ped and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) end

-- A real GTA explosion, unless the player stands close: a blast knocks the player flat, so only the smoke shows then.
local function boom(pos, kind, opts)
	if #(GetEntityCoords(PlayerPedId()) - pos) > 12.0 then Sigf.Explode(pos, kind, opts)
	else Sigf.Fx('core', 'exp_grd_grenade_lod', pos, { scale = 1.6 }) end
end

-- ---------- gold, level, shop ----------
local function addGold(n, at)
	hud.gold = hud.gold + n
	if at then Sigf.Text3D('+' .. n .. 'g', at + vector3(0, 0, 1.2), 1.3, { color = { 255, 212, 90 }, scale = 0.5 }) end
	local it = ITEMS[hud.items + 1]
	if it and hud.gold >= it[1] then
		hud.gold = hud.gold - it[1]
		hud.items = hud.items + 1
		hud.mul = hud.mul + it[3]
		banner('ITEM PURCHASED: ' .. it[2]:upper(), '#ffd45a', 3)
	end
end

local function addXp()
	hud.xp = hud.xp + 1
	local lv = math.min(9, 1 + math.floor(hud.xp / 3))
	if lv > hud.lv then
		hud.lv = lv
		hud.mul = hud.mul + 0.08
		banner('LEVEL UP!  LEVEL ' .. lv, '#7aff9a', 2.5)
		local c = C.blue
		if c and alive(c.ped) then
			local p = GetEntityCoords(c.ped)
			Sigf.Light(p + vector3(0, 0, 1.0), { 120, 255, 150 }, 10.0, 6.0, 0.8)
		end
	end
end

-- ---------- damage ----------
local function popText(p, dmg, col)
	Sigf.Text3D(tostring(math.floor(dmg)), p + vector3(0, 0, 1.5), 0.9, { color = col or { 255, 255, 255 }, scale = 0.55 })
end

-- Hurt a ped; credits the attacker when it dies. Armour (the Aegis shield) soaks first.
local function hurt(ped, dmg, by, col)
	if not alive(ped) or ped == PlayerPedId() then return end
	local eff = GetEntityHealth(ped) - 100 + GetPedArmour(ped)
	popText(GetEntityCoords(ped), dmg, col)
	if eff - dmg <= 0 then
		Sigf._killer[ped] = by
		SetEntityHealth(ped, 0)
	else
		ApplyDamageToPed(ped, math.floor(dmg), true)
	end
end

local function knock(ped, dir, force)
	if not alive(ped) or ped == PlayerPedId() then return end
	SetPedToRagdoll(ped, 900, 900, 0, false, false, false)
	SetEntityVelocity(ped, dir.x * force, dir.y * force, 3.5)
end

local function destroyStruct(s) end   -- defined below

local function hurtStruct(s, dmg, col)
	if not s.alive or match.over then return end
	if s.kind == 'nexus' and S.turret and S.turret[s.team] and S.turret[s.team].alive then
		if GetGameTimer() > (s.warnAt or 0) then
			s.warnAt = GetGameTimer() + 2500
			Sigf.Text3D('SHIELDED: DESTROY THE TURRET', s.pos + vector3(0, 0, 11.5), 1.8, { color = { 200, 200, 255 }, scale = 0.6 })
		end
		return
	end
	s.hp = s.hp - dmg
	s.hitAt = GetGameTimer()
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], s.pos + vector3(0, 0, 2.5 + math.random() * 2), { scale = 1.5 })
	if s.hp <= 0 then destroyStruct(s) end
end

-- ---------- queries ----------
local function foes(team, pos, radius)
	local out = {}
	for ped, m in pairs(M) do
		if m.team ~= team and alive(ped) then
			local p = GetEntityCoords(ped)
			local d = #(p - pos)
			if d <= radius then out[#out + 1] = { ped = ped, pos = p, d = d, champ = false } end
		end
	end
	local c = C[foe(team)]
	if c and alive(c.ped) then
		local p = GetEntityCoords(c.ped)
		local d = #(p - pos)
		if d <= radius then out[#out + 1] = { ped = c.ped, pos = p, d = d, champ = true } end
	end
	return out
end

local function allies(team, pos, radius)
	local out = {}
	for ped, m in pairs(M) do
		if m.team == team and alive(ped) and #(GetEntityCoords(ped) - pos) <= radius then out[#out + 1] = ped end
	end
	local c = C[team]
	if c and alive(c.ped) and #(GetEntityCoords(c.ped) - pos) <= radius then out[#out + 1] = c.ped end
	return out
end

local function targetStruct(team)
	local t = S.turret and S.turret[foe(team)]
	if t and t.alive then return t end
	local n = S.nexus and S.nexus[foe(team)]
	if n and n.alive then return n end
end

-- ---------- structures ----------
local skinned = {}
-- The generated models carry their painted texture by name: swap it in from mod/img at run time.
local function skin(model)
	if skinned[model] then return end
	skinned[model] = true
	Sigf.LoadModel(model)
	local txd = CreateRuntimeTxd('lol_' .. model)
	CreateRuntimeTextureFromImage(txd, 'skin', 'img/tex_' .. model:sub(6) .. '.png')
	AddReplaceTexture(model, model .. '_image_0', 'lol_' .. model, 'skin')
end

local function mkStruct(team, kind, t)
	local p = pt(t, 0)
	skin('sigf_' .. kind .. '_' .. team)
	local ent = Sigf.Prop('sigf_' .. kind .. '_' .. team, p, { ground = true, heading = team == 'blue' and 270.0 or 90.0 })
	local max = kind == 'nexus' and (DEMO and 700 or 1800) or (DEMO and 420 or 1000)
	local s = { team = team, kind = kind, ent = ent, pos = p, hp = max, max = max, alive = true,
		r = kind == 'nexus' and 4.6 or 3.0, top = kind == 'nexus' and 10.5 or 7.5 }
	S[#S + 1] = s
	S[kind] = S[kind] or {}
	S[kind][team] = s
	return s
end

function destroyStruct(s)
	s.alive = false
	local p = s.pos
	local big = s.kind == 'nexus'
	if big then Sigf.Slowmo(0.4, 2.6) Sigf.Shake(0.6) Sigf.Sound('nexus_boom', nil, { volume = 1.0 }) end
	for i = 0, big and 4 or 2 do
		Sigf.After(i * 0.35, function()
			local q = p + vector3(math.random(-3, 3), math.random(-3, 3), 1.0 + i * 0.9)
			boom(q, 4, { scale = 0.7, shake = big and 1.2 or 0.7 })
			Sigf.Fx('core', 'exp_grd_molotov', q, { scale = 1.4 })
			Sigf.Light(q, COL[s.team], 20.0, 12.0, 0.6)
		end)
	end
	Sigf.After(big and 3.4 or 1.2, function()
		Sigf.Remove(s.ent)
		s.rubble = Sigf.Fx('core', 'fire_petroltank_truck', p + vector3(0, 0, 0.3), { loop = true, scale = 1.4, life = 30 })
	end)
	local mine = s.team == 'blue'
	if big then
		match.over = true
		Lol.Finish(not mine)
	else
		banner(mine and 'YOUR TURRET HAS BEEN DESTROYED' or 'ENEMY TURRET DESTROYED', mine and '#ff7a5a' or '#7ac8ff', 3.5)
		if not mine then addGold(250, C.blue and alive(C.blue.ped) and GetEntityCoords(C.blue.ped) or p) end
	end
end

-- ---------- minions ----------
local KINDS = {
	warrior = { blue = 's_m_m_movspace_01', red = 's_m_m_movalien_01', weapon = 'WEAPON_BAT', health = 130, acc = 30 },
	caster  = { blue = 's_m_m_hazmatworker_01', red = 'u_m_y_zombie_01', weapon = 'WEAPON_PISTOL', health = 90, acc = 35 },
	super   = { blue = 'u_m_y_juggernaut_02', red = 'u_m_y_juggernaut_01', weapon = 'WEAPON_COMBATMG', health = 380, acc = 20, armor = 40 },
}

local function spawnMinion(team, kind, t, lat)
	local k = KINDS[kind]
	local p = pt(t, lat)
	local toward = team == 'blue' and L.dir or L.dir * -1.0
	local buffed = match.buff and match.buff.team == team and GetGameTimer() < match.buff.to
	local ped = Sigf.Ped(k[team], p + vector3(0, 0, 0.6), { enemy = team == 'red', weapon = k.weapon, health = k.health * (buffed and 2 or 1),
		armor = (k.armor or 0) + (buffed and 40 or 0), accuracy = k.acc, fight = false, heading = GetHeadingFromVector_2d(toward.x, toward.y), life = 240 })
	if not ped then return end
	SetPedKeepTask(ped, true)
	SetPedFleeAttributes(ped, 0, false)
	SetPedCombatAttributes(ped, 46, true)
	SetPedCombatRange(ped, 2)
	M[ped] = { team = team, kind = kind, born = GetGameTimer(), max = k.health * (buffed and 2 or 1) + (k.armor or 0) + (buffed and 40 or 0), buffed = buffed }
end

local function spawnWave()
	if match.over then return end
	match.wave = match.wave + 1
	local n = match.wave
	local super = n % 3 == 0
	Sigf.Sound('wave_horn', nil, { volume = 0.35 })
	banner(n == 1 and 'MINIONS HAVE SPAWNED' or ('MINION WAVE ' .. n), '#f0e6d2', 2.5)
	for _, team in ipairs({ 'blue', 'red' }) do
		local base = team == 'blue' and -(LANE_NEXUS - 9.0) or (LANE_NEXUS - 9.0)
		local step = team == 'blue' and 1.0 or -1.0
		local order = { 'warrior', 'warrior', 'warrior', 'caster', 'caster' }
		if super or (match.buff and match.buff.team == team and GetGameTimer() < match.buff.to) then order[#order + 1] = 'super' end
		for i, kind in ipairs(order) do
			Sigf.After((i - 1) * 0.6, function()
				if not match.over then spawnMinion(team, kind, base + step * (i % 2) * 1.5, ((i - 1) % 3 - 1) * 2.2) end
			end)
		end
	end
end

local function minionTick(ped, m)
	local now = GetGameTimer()
	if IsPedDeadOrDying(ped, true) then return end
	local p = GetEntityCoords(ped)
	local list = foes(m.team, p, 18.0)
	local best
	for _, f in ipairs(list) do if not best or f.d < best.d then best = f end end
	if best then
		if m.tgt ~= best.ped or now > (m.cmd or 0) then
			m.tgt, m.cmd, m.state = best.ped, now + 3000, 'fight'
			TaskCombatPed(ped, best.ped, 0, 16)
		end
		return
	end
	local st = targetStruct(m.team)
	if st then
		local d = #(flat(p) - flat(st.pos))
		if d < 15.0 then
			if m.state ~= 'siege' then
				m.state = 'siege'
				m.cmd = 0
			end
			if now > (m.cmd or 0) then
				m.cmd = now + 1500
				TaskShootAtCoord(ped, st.pos.x, st.pos.y, st.pos.z + 2.5, 1500, GetHashKey('FIRING_PATTERN_BURST_FIRE'))
			end
			hurtStruct(st, (m.kind == 'super' and 20 or 8) * 0.5, COL[m.team])
			beams[#beams + 1] = { a = p + vector3(0, 0, 1.2), b = st.pos + vector3(math.random() - 0.5, math.random() - 0.5, 2.5), col = COL[m.team], to = now + 120 }
		elseif m.state ~= 'march' or now > (m.cmd or 0) then
			m.state, m.cmd = 'march', now + 4000
			TaskGoToCoordAnyMeans(ped, st.pos.x, st.pos.y, st.pos.z, 2.6, 0, false, 786603, 0.0)
		end
	end
end

local function drawMinionFeet() end

-- ---------- champions ----------
local function champStart(team)
	local c = C[team] or { team = team, ready = { q = 0, w = 0, e = 0, r = 0 }, kills = 0 }
	C[team] = c
	return c
end

local CD = { q = 3.0, w = 8.0, e = 5.0, r = DEMO and 9.0 or 18.0 }
Lol.CD = CD

local function spawnChampion(team)
	local c = champStart(team)
	local base = team == 'blue' and -(LANE_NEXUS - 8.0) or (LANE_NEXUS - 8.0)
	if team == 'blue' and PLAYER_HERO then base = -13.0 end
	local p = pt(base, 0)
	if team == 'blue' and PLAYER_HERO then
		c.ped, c.isPlayer, c.name = PlayerPedId(), true, 'AURELIA'
		SetEntityCoords(c.ped, p.x, p.y, p.z + 1.0, false, false, false, false)
		SetEntityHeading(c.ped, GetHeadingFromVector_2d(L.dir.x, L.dir.y))
		return c
	end
	local model = team == 'blue' and 'u_m_y_rsranger_01' or 'u_m_y_imporage'
	local ped = Sigf.Ped(model, p + vector3(0, 0, 0.6), { enemy = team == 'red', weapon = team == 'blue' and 'WEAPON_CARBINERIFLE' or 'WEAPON_ASSAULTSHOTGUN',
		health = 380, armor = 60, accuracy = 40, fight = false, life = 0 })
	if not ped then return end
	c.ped, c.isPlayer, c.name = ped, false, team == 'blue' and 'AURELIA' or 'VOIDREAVER'
	SetPedKeepTask(ped, true)
	Sigf.Light(p + vector3(0, 0, 1.0), COL[team], 10.0, 8.0, 0.8)
	return c
end

-- ---------- abilities ----------
local function aimDir(c, aim)
	local p = GetEntityCoords(c.ped)
	if aim then return norm2(aim - p) end
	if c.isPlayer and DEMO == false then
		local r = GetGameplayCamRot(2)
		local h = math.rad(r.z)
		return vector3(-math.sin(h), math.cos(h), 0.0)
	end
	local f = GetEntityForwardVector(c.ped)
	return norm2(f)
end

local function faceDir(c, d)
	SetEntityHeading(c.ped, GetHeadingFromVector_2d(d.x, d.y))
end

local function ready(c, k)
	return GetGameTimer() >= c.ready[k]
end

local function spend(c, k)
	c.ready[k] = GetGameTimer() + math.floor(CD[k] * 1000)
	if c.isPlayer then Sigf.Nui({ cast = k }) end
end

local function dmgMul(c) return c.isPlayer and hud.mul or (1.0 + (c.lv or 0) * 0.05) end

function Lol.Q(c, aim)
	if not alive(c.ped) or not ready(c, 'q') then return false end
	spend(c, 'q')
	Sigf.Sound('q_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local d = aimDir(c, aim)
	faceDir(c, d)
	local from = GetEntityCoords(c.ped) + vector3(0, 0, 0.2) + d * 0.8
	projs[#projs + 1] = { c = c, pos = from, dir = d, dist = 0.0, max = 44.0, speed = 34.0, hit = {}, trail = {}, col = COL[c.team], dmg = 85 * dmgMul(c) }
	Sigf.Light(from, COL[c.team], 8.0, 6.0, 0.25)
	return true
end

function Lol.W(c)
	if not alive(c.ped) or not ready(c, 'w') then return false end
	spend(c, 'w')
	Sigf.Sound('w_cast', GetEntityCoords(c.ped), { range = 70.0, volume = 0.8 })
	local p = GetEntityCoords(c.ped)
	domes[#domes + 1] = { c = c, to = GetGameTimer() + 4500, born = GetGameTimer(), col = COL[c.team] }
	for _, ped in ipairs(allies(c.team, p, 9.0)) do
		SetPedArmour(ped, math.min(100, GetPedArmour(ped) + 45))
		local mx = GetEntityMaxHealth(ped)
		SetEntityHealth(ped, math.min(mx, GetEntityHealth(ped) + 40))
		Sigf.Text3D('+40', GetEntityCoords(ped) + vector3(0, 0, 0.8), 1.0, { color = { 110, 255, 140 }, scale = 0.5 })
	end
	Sigf.Light(p + vector3(0, 0, 1), COL[c.team], 12.0, 6.0, 1.0)
	return true
end

function Lol.E(c, aim, dist)
	if not alive(c.ped) or not ready(c, 'e') then return false end
	spend(c, 'e')
	Sigf.Sound('e_dash', GetEntityCoords(c.ped), { range = 70.0, volume = 0.7 })
	local d = aimDir(c, aim)
	faceDir(c, d)
	local a = GetEntityCoords(c.ped)
	dashes[#dashes + 1] = { c = c, a = a, d = d, len = dist or 13.0, t = 0.0, hit = {}, col = COL[c.team], last = a }
	return true
end

function Lol.R(c, aim)
	if not alive(c.ped) or not ready(c, 'r') then return false end
	spend(c, 'r')
	Sigf.Sound('r_cast', nil, { volume = 0.7 })
	Sigf.LoadModel('prop_rock_1_a')
	local p = GetEntityCoords(c.ped)
	local d = aimDir(c, aim)
	faceDir(c, d)
	local tgt = aim or (p + d * 16.0)
	tgt = vector3(tgt.x, tgt.y, gz(tgt.x, tgt.y, p.z))
	rings[#rings + 1] = { pos = tgt, t0 = GetGameTimer(), warm = 1100, col = COL[c.team], c = c }
	banner(c.isPlayer and 'STARFALL!' or (c.name .. ' CASTS STARFALL'), c.isPlayer and '#ffb347' or '#ff6a50', 2.0)
	return true
end

local function meteorImpact(c, pos)
	boom(pos, 0, { scale = 0.0, shake = 0.4 })
	Sigf.Fx('core', 'exp_grd_molotov', pos, { scale = 0.7 })
	Sigf.Light(pos + vector3(0, 0, 1.5), { 255, 140, 40 }, 16.0, 10.0, 0.5)
	local mul = dmgMul(c)
	for _, f in ipairs(foes(c.team, pos, 5.5)) do
		hurt(f.ped, 150 * mul, c.ped, { 255, 160, 60 })
		knock(f.ped, norm2(f.pos - pos), 7.0)
	end
	for _, s in ipairs(S) do
		if s.alive and s.team ~= c.team and #(flat(s.pos) - flat(pos)) < 6.0 + s.r then hurtStruct(s, 45 * mul, { 255, 160, 60 }) end
	end
end

-- ---------- the frame: draws and moves every effect ----------
local function sphere(p, r, col, a)
	if #(p - GetFinalRenderedCamCoord()) < 2.6 then return end
	DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, r, col[1], col[2], col[3], a, false, false, 2, false, nil, nil, false)
end

local function bar(p, frac, w, col)
	frac = math.max(0.0, math.min(1.0, frac))
	SetDrawOrigin(p.x, p.y, p.z, 0)
	DrawRect(0.0, 0.0, w + 0.002, 0.0105, 0, 0, 0, 200)
	DrawRect(-(w * (1 - frac)) / 2, 0.0, w * frac, 0.0075, col[1], col[2], col[3], 235)
	ClearDrawOrigin()
end

local function frame(dt)
	local now = GetGameTimer()
	local hero = C.blue and C.blue.ped
	-- structures: glow, beam of light, health bar
	for _, s in ipairs(S) do
		if s.alive then
			local c = COL[s.team]
			local flash = (s.hitAt and now - s.hitAt < 150) and 1.0 or 0.0
			DrawLightWithRange(s.pos.x, s.pos.y, s.pos.z + s.top - 1.0, c[1], c[2], c[3], 16.0 + flash * 8, 5.0 + flash * 6)
			DrawMarker(1, s.pos.x, s.pos.y, s.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.7, 70.0, c[1], c[2], c[3], 28, false, false, 2, false, nil, nil, false)
			DrawMarker(1, s.pos.x, s.pos.y, s.pos.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s.r * 2.6, s.r * 2.6, 0.2, c[1], c[2], c[3], 90, false, false, 2, false, nil, nil, false)
			bar(s.pos + vector3(0, 0, s.top + 1.2), s.hp / s.max, s.kind == 'nexus' and 0.09 or 0.07, c)
		end
	end
	-- minions: team ring and health bar
	for ped, m in pairs(M) do
		if alive(ped) then
			local p = GetEntityCoords(ped)
			local c = COL[m.team]
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.15, c[1], c[2], c[3], 150, false, false, 2, false, nil, nil, false)
			DrawLightWithRange(p.x, p.y, p.z + 0.5, c[1], c[2], c[3], 3.0, 1.3)
			local hp = (GetEntityHealth(ped) - 100 + GetPedArmour(ped)) / m.max
			bar(p + vector3(0, 0, 1.15), hp, m.kind == 'super' and 0.05 or 0.034, c)
		end
	end
	-- champions: bar and ring
	for team, c in pairs(C) do
		if c.ped and alive(c.ped) and not c.isPlayer then
			local p = GetEntityCoords(c.ped)
			local col = COL[team]
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.8, 1.8, 0.2, col[1], col[2], col[3], 190, false, false, 2, false, nil, nil, false)
			DrawLightWithRange(p.x, p.y, p.z + 1.0, col[1], col[2], col[3], 5.0, 2.5)
			bar(p + vector3(0, 0, 1.3), (GetEntityHealth(c.ped) - 100 + GetPedArmour(c.ped)) / 440.0, 0.07, col)
		elseif c.isPlayer and alive(c.ped) then
			local p = GetEntityCoords(c.ped)
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.8, 1.8, 0.2, 90, 255, 150, 190, false, false, 2, false, nil, nil, false)
		end
	end
	-- turret / minion beams
	for i = #beams, 1, -1 do
		local b = beams[i]
		if now > b.to then table.remove(beams, i)
		else
			for o = -1, 1 do DrawLine(b.a.x + o * 0.03, b.a.y, b.a.z, b.b.x + o * 0.03, b.b.y, b.b.z, b.col[1], b.col[2], b.col[3], 255) end
			sphere(b.b, 0.5, b.col, 160)
		end
	end
	-- Q: starbolt
	for i = #projs, 1, -1 do
		local q = projs[i]
		local step = q.speed * dt
		q.pos = q.pos + q.dir * step
		q.dist = q.dist + step
		table.insert(q.trail, 1, q.pos)
		if #q.trail > 9 then q.trail[10] = nil end
		local done = q.dist > q.max
		for _, f in ipairs(foes(q.c.team, q.pos, 2.4)) do
			if not q.hit[f.ped] then
				q.hit[f.ped] = true
				hurt(f.ped, q.dmg, q.c.ped, { 120, 210, 255 })
				knock(f.ped, q.dir, 6.0)
				Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], f.pos + vector3(0, 0, 0.8), { scale = 1.8 })
				Sigf.Fx(Sigf.FX.blood[1], Sigf.FX.blood[2], f.pos + vector3(0, 0, 0.9), { scale = 1.0 })
				Sigf.Shake(0.15, 'SMALL_EXPLOSION_SHAKE')
			end
		end
		for _, s in ipairs(S) do
			if s.alive and s.team ~= q.c.team and #(flat(s.pos) - flat(q.pos)) < s.r + 1.0 then
				hurtStruct(s, q.dmg * 0.9, q.col)
				Sigf.Fx('core', 'exp_grd_grenade', q.pos, { scale = 1.0 })
				done = true
			end
		end
		local c = q.col
		sphere(q.pos, 0.16, { 255, 255, 255 }, 255)
		sphere(q.pos, 0.3, c, 150)
		for k, tp in ipairs(q.trail) do sphere(tp, 0.28 - k * 0.022, c, math.max(10, 120 - k * 12)) end
		DrawLightWithRange(q.pos.x, q.pos.y, q.pos.z, c[1], c[2], c[3], 10.0, 8.0)
		if done then table.remove(projs, i) end
	end
	-- W: aegis dome
	for i = #domes, 1, -1 do
		local d = domes[i]
		if now > d.to or not alive(d.c.ped) then table.remove(domes, i)
		else
			local p = GetEntityCoords(d.c.ped)
			local age = math.min(1.0, (now - d.born) / 250)
			local pulse = 1.0 + math.sin(now / 120.0) * 0.04
			local fade = math.min(1.0, (d.to - now) / 600)
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0 * age, 6.0 * age, 0.1, d.col[1], d.col[2], d.col[3], math.floor(90 * fade), false, false, 2, true, nil, nil, false)
			DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.2 * age, 3.2 * age, 2.4, d.col[1], d.col[2], d.col[3], math.floor(80 * fade), false, false, 2, false, nil, nil, false)
			for k = 0, 3 do
				local r = (3.4 - math.abs(k - 1.2) * 0.45) * age * pulse
				DrawMarker(1, p.x, p.y, p.z - 0.9 + k * 0.62, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, r, r, 0.22, 190, 235, 255, math.floor(210 * fade), false, false, 2, false, nil, nil, false)
			end
			DrawLightWithRange(p.x, p.y, p.z + 1, d.col[1], d.col[2], d.col[3], 8.0, 4.0 * fade)
		end
	end
	-- E: phase dash (a burst of speed along the lane)
	for i = #dashes, 1, -1 do
		local d = dashes[i]
		d.t = d.t + dt / 0.28
		local k = math.min(1.0, d.t)
		if alive(d.c.ped) then
			local np = GetEntityCoords(d.c.ped)
			local sp = d.len / 0.28
			SetEntityVelocity(d.c.ped, d.d.x * sp, d.d.y * sp, 0.0)
			Sigf.Fx('core', 'ent_dst_gen_gobstop', np - vector3(0, 0, 0.8), { scale = 0.8 })
			for _, f in ipairs(foes(d.c.team, np, 2.6)) do
				if not d.hit[f.ped] then
					d.hit[f.ped] = true
					hurt(f.ped, 35 * dmgMul(d.c), d.c.ped, { 190, 255, 220 })
					knock(f.ped, d.d, 6.0)
				end
			end
			if not d.ring then d.ring = true bursts[#bursts + 1] = { p = np - vector3(0, 0, 0.9), to = now + 700, col = d.col, r = 5.0, ring = true } end
		end
		if k >= 1.0 then table.remove(dashes, i) end
	end
	for i = #bursts, 1, -1 do
		local b = bursts[i]
		if now > b.to then table.remove(bursts, i)
		else
			local f = (b.to - now) / 700.0
			DrawMarker(1, b.p.x, b.p.y, b.p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, b.r * (1.2 - f), b.r * (1.2 - f), 0.12, b.col[1], b.col[2], b.col[3], math.floor(150 * f), false, false, 2, false, nil, nil, false)
		end
	end
	-- R: starfall (telegraph, then meteors)
	for i = #rings, 1, -1 do
		local r = rings[i]
		local age = now - r.t0
		if age < r.warm then
			local f = age / r.warm
			DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0, 17.0, 0.3, 255, 90, 30, math.floor(70 + 90 * f), false, false, 2, false, nil, nil, false)
			DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0 * f, 17.0 * f, 0.4, 255, 200, 80, 120, false, false, 2, true, nil, nil, false)
		else
			if not r.fired then
				r.fired = true
				for k = 1, 11 do
					local a, rad = math.random() * 6.283, math.sqrt(math.random()) * 7.0
					local tp = r.pos + vector3(math.cos(a) * rad, math.sin(a) * rad, 0.0)
					if k <= 2 then tp = r.pos + vector3(math.random() - 0.5, math.random() - 0.5, 0) * 2.0 end
					meteors[#meteors + 1] = { c = r.c, tgt = tp, t0 = now + k * 140, fall = 650 }
				end
			end
			if age > r.warm + 2200 then table.remove(rings, i)
			else DrawMarker(1, r.pos.x, r.pos.y, r.pos.z + 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 17.0, 17.0, 0.3, 255, 90, 30, 60, false, false, 2, false, nil, nil, false) end
		end
	end
	for i = #meteors, 1, -1 do
		local m = meteors[i]
		if now >= m.t0 then
			local f = (now - m.t0) / m.fall
			if not m.ent and not m.failed then
				m.ent = Sigf.Prop('prop_rock_1_a', m.tgt + vector3(-10, 0, 45), { collision = false, life = 4 })
				if m.ent then
					SetEntityLodDist(m.ent, 500)
					m.fx = Sigf.Fx('core', 'ent_sht_flame', m.ent, { loop = true, scale = 3.0, life = 3 })
					m.fx2 = Sigf.Fx('core', 'exp_grd_molotov_lod', m.ent, { loop = true, scale = 1.0, life = 3 })
				else m.failed = true end
			end
			local p = vector3(m.tgt.x - 10.0 * (1 - f), m.tgt.y, m.tgt.z + 45.0 * (1 - f) * (1 - f) + 0.5)
			if m.ent and DoesEntityExist(m.ent) then SetEntityCoordsNoOffset(m.ent, p.x, p.y, p.z, false, false, false) end
			if f >= 1.0 then
				if m.fx then Sigf.StopFx(m.fx) end
				if m.fx2 then Sigf.StopFx(m.fx2) end
				if m.ent then Sigf.Remove(m.ent) end
				meteorImpact(m.c, m.tgt)
				table.remove(meteors, i)
			else
				DrawLightWithRange(p.x, p.y, p.z, 255, 140, 40, 14.0, 9.0)
			end
		end
	end
	if C.blue and C.blue.isPlayer then
		local me = PlayerPedId()
		-- the demo player never dies (the stage's invincibility does not hold against blasts and fire)
		SetPlayerInvincible(PlayerId(), true)
		SetEntityInvincible(me, true)
		SetEntityProofs(me, true, true, true, true, true, true, true, true)
		if GetEntityHealth(me) < GetEntityMaxHealth(me) and IsPedDeadOrDying(me, true) == false then SetEntityHealth(me, GetEntityMaxHealth(me)) end
		if IsPedRagdoll(me) then
			Lol.ragAt = Lol.ragAt or now
			if now - Lol.ragAt > 700 then
				SetPedCanRagdoll(me, true)
				ClearPedTasksImmediately(me)
				Lol.ragAt = nil
				SetTimeout(300, function() SetPedCanRagdoll(PlayerPedId(), false) end)
			end
		else Lol.ragAt = nil end
	end
	-- the player's own gunfire hurts the enemy turret and nexus it aims at
	if C.blue and C.blue.isPlayer and IsPedShooting(PlayerPedId()) then
		local me = GetEntityCoords(PlayerPedId())
		local f = GetEntityForwardVector(PlayerPedId())
		for _, s in ipairs(S) do
			if s.alive and s.team == 'red' then
				local to = s.pos - me
				if #to < 45.0 and #to > 0.1 and dot(norm2(to), norm2(f)) > 0.9 then hurtStruct(s, 3.5 * hud.mul, { 255, 255, 255 }) end
			end
		end
	end
end

-- ---------- turret AI ----------
local function turretTick()
	local now = GetGameTimer()
	for _, s in ipairs(S) do
		if s.alive and s.kind == 'turret' then
			local top = s.pos + vector3(0, 0, s.top - 0.5)
			local list = foes(s.team, s.pos, 24.0)
			local best
			for _, f in ipairs(list) do
				local w = f.d + (f.champ and 8.0 or 0.0)     -- minions first, like the real thing
				if not best or w < best.w then best = f best.w = w end
			end
			if best then
				beams[#beams + 1] = { a = top, b = best.pos + vector3(0, 0, 1.0), col = COL[s.team], to = now + 260 }
				Sigf.Light(top, COL[s.team], 10.0, 8.0, 0.25)
				Sigf.Sound('turret_zap', top, { range = 70.0, volume = 0.5 })
				Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], best.pos + vector3(0, 0, 1.0), { scale = 1.5 })
				hurt(best.ped, best.champ and 25 or 48, nil, COL[s.team])
				knock(best.ped, norm2(best.pos - s.pos), 2.5)
			end
		end
	end
end

-- ---------- champion brains ----------
local function frontAlly(team)
	local best, bx
	for ped, m in pairs(M) do
		if m.team == team and alive(ped) then
			local p = GetEntityCoords(ped)
			local x = dot(p - L.c, L.dir) * (team == 'blue' and 1 or -1)
			if not bx or x > bx then best, bx = p, x end
		end
	end
	return best
end

local function think(c)
	if not alive(c.ped) or c.isPlayer then return end
	local now = GetGameTimer()
	local ped = c.ped
	local p = GetEntityCoords(ped)
	local list = foes(c.team, p, 34.0)
	local best
	for _, f in ipairs(list) do if not best or f.d < best.d then best = f end end
	local st = targetStruct(c.team)
	local sd = st and #(flat(p) - flat(st.pos)) or 1e9
	local hp = (GetEntityHealth(ped) - 100) / 380.0
	if hp < 0.5 and Lol.W(c) then return end
	if best then
		if best.d < 30.0 then Lol.Q(c, best.pos) end
		if #list >= 3 and best.d < 25.0 and not (DEMO and c.team == 'red') then Lol.R(c, best.pos) end
		if best.d > 15.0 and math.random() < 0.3 then Lol.E(c, best.pos, 9.0) end
		if c.tgt ~= best.ped or now > (c.cmd or 0) then
			c.tgt, c.cmd = best.ped, now + 2500
			TaskCombatPed(ped, best.ped, 0, 16)
		end
	elseif st and sd < 30.0 then
		if sd < 24.0 then if not DEMO then Lol.R(c, st.pos) end Lol.Q(c, st.pos) end
		if sd > 17.0 then
			if now > (c.cmd or 0) then
				c.cmd = now + 2500
				TaskGoToCoordAnyMeans(ped, st.pos.x, st.pos.y, st.pos.z, 2.0, 0, false, 786603, 0.0)
			end
		else
			if now > (c.cmd or 0) then
				c.cmd = now + 1500
				TaskShootAtCoord(ped, st.pos.x, st.pos.y, st.pos.z + 2.5, 1500, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
			end
			hurtStruct(st, 6 * dmgMul(c), COL[c.team])
			beams[#beams + 1] = { a = p + vector3(0, 0, 1.3), b = st.pos + vector3(0, 0, 2.5), col = COL[c.team], to = now + 150 }
		end
	else
		local fa = frontAlly(c.team)
		local goal = fa or pt(c.team == 'blue' and -LANE_TURRET - 5.0 or LANE_TURRET + 5.0, 0)
		if #(p - goal) > 6.0 and now > (c.cmd or 0) then
			c.cmd = now + 2000
			TaskGoToCoordAnyMeans(ped, goal.x, goal.y, goal.z, 2.0, 0, false, 786603, 0.0)
		end
	end
end

-- ---------- match flow ----------
local function cleanup()
	for ped in pairs(M) do Sigf.Remove(ped) end
	M = {}
	for _, s in ipairs(S) do Sigf.Remove(s.ent) if s.rubble then Sigf.StopFx(s.rubble) end end
	S = {}
	for team, c in pairs(C) do if c.ped and not c.isPlayer then Sigf.Remove(c.ped) end end
	C = {}
	projs, domes, dashes, meteors, rings, beams, bursts = {}, {}, {}, {}, {}, {}, {}
end

function Lol.Finish(blueWins)
	local blue = C.blue
	banner(blueWins and 'THE ENEMY NEXUS HAS BEEN DESTROYED' or 'YOUR NEXUS HAS BEEN DESTROYED', blueWins and '#ffd45a' or '#ff6a50', 4)
	if blueWins then Sigf.After(2.0, function() Sigf.Sound('victory', nil, { volume = 0.8 }) end) end
	local nx = S.nexus and (blueWins and S.nexus.red or S.nexus.blue)
	if nx then
		local look = nx.pos + vector3(0, 0, 5.0)
		if DEMO then Sigf.Cinematic(nx.pos + vector3(blueWins and -15.0 or 15.0, 12.0, 6.0), look, 6.0, 55.0)
		else Sigf.Focus(look, 7) Lol.focusUntil = GetGameTimer() + 7000 end
	end
	Sigf.After(1.8, function()
		Sigf.Nui({ ['end'] = blueWins and 'VICTORY' or 'DEFEAT', sec = 9 })
		Sigf.PostFx(blueWins and 'SuccessMichael' or 'DeathFailOut', 3)
	end)
	-- the loser's minions fall
	local loser = blueWins and 'red' or 'blue'
	for ped, m in pairs(M) do
		if m.team == loser and alive(ped) then
			Sigf.After(math.random() * 2.5, function() if alive(ped) then Sigf.Fx('core', 'exp_grd_grenade', GetEntityCoords(ped), { scale = 0.8 }) SetEntityHealth(ped, 0) end end)
		end
	end
	Sigf.After(16.0, function() Lol.NewMatch() end)
end

function Lol.NewMatch()
	cleanup()
	match = { over = false, t0 = GetGameTimer(), wave = 0, kills = { blue = 0, red = 0 }, running = true }
	hud.gold, hud.xp, hud.lv, hud.mul, hud.items = 300, 0, 1, 1.0, 0
	Sigf.Battle({ enabled = false, center = L.c })
	mkStruct('blue', 'nexus', -LANE_NEXUS)
	mkStruct('red', 'nexus', LANE_NEXUS)
	mkStruct('blue', 'turret', -LANE_TURRET)
	mkStruct('red', 'turret', LANE_TURRET)
	spawnChampion('blue')
	spawnChampion('red')
	Sigf.Focus(L.c, 4)
	Sigf.After(1.0, function() banner('WELCOME TO SUMMONER\'S LOS SANTOS', '#ffd45a', 3.5) end)
	local mine = match
	local function loop()
		Sigf.After(WAVE_SEC, function()
			if match == mine and not mine.over then spawnWave() loop() end
		end)
	end
	Sigf.After(DEMO and 1.2 or 5.0, function() if match == mine then spawnWave() loop() end end)
end

-- ---------- start ----------
local function startup()
	local c = Sigf.Arena()
	L = { c = c, dir = vector3(1, 0, 0), side = vector3(0, 1, 0) }
	Lol.L = L
	Sigf.Frame(frame, 'lol_frame')
	Sigf.Every(0.5, function()
		if not match.running then return end
		for ped, m in pairs(M) do
			if not DoesEntityExist(ped) then M[ped] = nil
			elseif IsPedDeadOrDying(ped, true) then
				m.deadAt = m.deadAt or GetGameTimer()
				if GetGameTimer() - m.deadAt > 4500 then Sigf.Remove(ped) M[ped] = nil end
			else
				Sigf.Safe('minion', minionTick, ped, m)
			end
		end
		if not match.over then
			for _, c2 in pairs(C) do Sigf.Safe('think', think, c2) end
		end
	end, 'lol_minions')
	Sigf.Every(1.2, function() if match.running and not match.over then turretTick() end end, 'lol_turrets')
	-- champion respawn and camera
	Sigf.Every(1.0, function()
		if not match.running then return end
		local now0 = GetGameTimer()
		if not DEMO and not match.over and now0 - match.t0 > 50000 and now0 - (match.baronAt or match.t0) > 60000 then
			match.baronAt = now0
			local team = match.kills.blue <= match.kills.red and 'blue' or 'red'
			match.buff = { team = team, to = now0 + 55000 }
			banner((team == 'blue' and 'ORDER' or 'VOID') .. ' HAS SLAIN BARON NASHOR!', team == 'blue' and '#7ac8ff' or '#ff7a5a', 4)
			Sigf.Text3D('EMPOWERED MINIONS', (team == 'blue' and pt(-LANE_NEXUS + 8, 0) or pt(LANE_NEXUS - 8, 0)) + vector3(0, 0, 3), 5, { color = COL[team], scale = 0.8 })
		end
		for team, ch in pairs(C) do
			if not ch.isPlayer and ch.ped and IsPedDeadOrDying(ch.ped, true) and not match.over then
				ch.deadAt = ch.deadAt or GetGameTimer()
				if GetGameTimer() - ch.deadAt > 7000 then
					Sigf.Remove(ch.ped)
					ch.deadAt = nil
					spawnChampion(team)
				end
			end
		end
		if not DEMO and GetGameTimer() > (Lol.focusUntil or 0) then
			local sum, n = vector3(0, 0, 0), 0
			for ped, m in pairs(M) do if alive(ped) then sum = sum + GetEntityCoords(ped) n = n + 1 end end
			if n > 0 then Sigf.Focus(sum / n, 3) else Sigf.Focus(L.c, 3) end
		end
	end, 'lol_misc')
	Sigf.Every(0.15, function()
		if not match.running then return end
		local c1 = C.blue
		local cd, cdm = {}, {}
		local now = GetGameTimer()
		for k, v in pairs(CD) do
			cdm[k] = v
			cd[k] = c1 and math.max(0, (c1.ready[k] - now) / 1000.0) or 0
		end
		local nb, nr = S.nexus and S.nexus.blue, S.nexus and S.nexus.red
		local hp = 100
		if c1 and c1.ped and alive(c1.ped) then
			hp = c1.isPlayer and 100 or ((GetEntityHealth(c1.ped) - 100) / 3.8)
		end
		Sigf.Nui({ hud = {
			nb = nb and math.max(0, nb.hp) or 0, nbm = nb and nb.max or 1, nr = nr and math.max(0, nr.hp) or 0, nrm = nr and nr.max or 1,
			tb = (S.turret and S.turret.blue and S.turret.blue.alive) and 1 or 0, tr = (S.turret and S.turret.red and S.turret.red.alive) and 1 or 0,
			kb = match.kills.blue, kr = match.kills.red, t = (now - match.t0) / 1000.0,
			keys = (PLAYER_HERO and not DEMO) and 'QZXC' or 'QWER', gold = math.floor(hud.gold), lv = hud.lv, name = (c1 and c1.name) or 'AURELIA', hp = hp, cd = cd, cdm = cdm } })
	end, 'lol_hud')
end

Sigf.OnKill(function(ped, killer)
	local m = M[ped]
	if not m then
		local c = C.red
		local cb = C.blue
		if cb and not cb.isPlayer and ped == cb.ped then
			match.kills.red = match.kills.red + 3
			banner(match.fb and 'YOUR CHAMPION WAS SLAIN' or 'FIRST BLOOD FOR THE VOID!', '#ff7a5a', 2.5)
			match.fb = true
			return
		end
		if c and ped == c.ped then
			match.kills.blue = match.kills.blue + 3
			banner(match.fb and 'ENEMY CHAMPION SLAIN' or 'FIRST BLOOD!', '#ffd45a', 2.5)
			match.fb = true
			addGold(300, GetEntityCoords(ped))
		end
		return
	end
	local mine = m.team == 'red'
	match.kills[mine and 'blue' or 'red'] = match.kills[mine and 'blue' or 'red'] + 1
	local p = GetEntityCoords(ped)
	Sigf.Fx(Sigf.FX.sparks[1], Sigf.FX.sparks[2], p + vector3(0, 0, 0.8), { scale = 1.4 })
	if mine and (killer == PlayerPedId() or (C.blue and killer == C.blue.ped)) then
		addGold(m.kind == 'super' and 60 or 21, p)
		addXp()
	end
end)

-- player controls (the player is the champion at home and in the demo)
local function playerCast(k)
	local c = C.blue
	if not (c and c.isPlayer) then return end
	if k == 'q' then Lol.Q(c) elseif k == 'w' then Lol.W(c) elseif k == 'e' then Lol.E(c) else Lol.R(c) end
end
RegisterCommand('lol_q', function() playerCast('q') end, false)
RegisterCommand('lol_w', function() playerCast('w') end, false)
RegisterCommand('lol_e', function() playerCast('e') end, false)
RegisterCommand('lol_r', function() playerCast('r') end, false)
RegisterKeyMapping('lol_q', 'Summoner: Q Starbolt', 'keyboard', 'Q')
RegisterKeyMapping('lol_w', 'Summoner: W Aegis', 'keyboard', 'Z')
RegisterKeyMapping('lol_e', 'Summoner: E Phase Dash', 'keyboard', 'X')
RegisterKeyMapping('lol_r', 'Summoner: R Starfall', 'keyboard', 'C')

-- In the recorded demo the match starts with the recording, so the demo steps and the match stay in step.
local recSeen, started = false, false
local function begin()
	if started then return end
	started = true
	Lol.NewMatch()
end
RegisterNetEvent('sigf:rec', function() recSeen = true if L then begin() end end)
Sigf.After(1.5, function()
	startup()
	if not DEMO or recSeen then begin() end
end)
if DEMO then Sigf.After(150, begin) end

-- for demo.lua
function Lol.AimEnemy(team)
	local c = C[team or 'blue']
	if not c or not alive(c.ped) then return L.c + L.dir * 20.0 end
	local p = GetEntityCoords(c.ped)
	local list = foes(c.team, p, 40.0)
	local best
	for _, f in ipairs(list) do
		local ahead = dot(f.pos - p, L.dir) * (c.team == 'blue' and 1 or -1)
		if ahead > -2.0 and (not best or f.d < best.d) then best = f end
	end
	if best then return best.pos end
	local st = targetStruct(c.team)
	return st and st.pos or (L.c + L.dir * 20.0)
end
function Lol.Champ(team) return C[team or 'blue'] end
function Lol.Struct(kind, team) return S[kind] and S[kind][team] end
function Lol.HurtStruct(s, dmg) if s then hurtStruct(s, dmg, { 255, 255, 255 }) end end
function Lol.Match() return match end
function Lol.LookAtPoint(p)
	local me = PlayerPedId()
	local d = norm2(p - GetEntityCoords(me))
	SetEntityHeading(me, GetHeadingFromVector_2d(d.x, d.y))
end

