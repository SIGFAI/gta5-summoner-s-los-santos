-- Demo: the player is the champion Aurelia; the match starts with the recording (client.lua).
local function hero() return Lol.Champ('blue') end
local function cap(text, sec) Sigf.Text(text, sec or 4, { y = 0.27, size = 52, color = '#ffe08a' }) end
local function nexusPos() local n = Lol.Struct('nexus', 'red') return n and n.pos or Sigf.Arena() end

Sigf.Demo(0.5, function() Sigf.Text("SUMMONER'S LOS SANTOS", 4, { y = 0.27, size = 76, color = '#ffd45a' }) end)
Sigf.Demo(4.5, function() cap('Minion waves march down the lane to the enemy nexus', 5) end)

-- Q: a piercing skillshot through the clash
Sigf.Demo(11.5, function()
	cap('Q  STARBOLT: a skillshot that pierces the whole wave', 4)
	local h = hero()
	if h then Lol.Q(h, Lol.AimEnemy()) end
end)
Sigf.Demo(15.0, function()
	local h = hero()
	if h then Lol.Q(h, Lol.AimEnemy()) end
end)

-- W and E
Sigf.Demo(18.0, function()
	cap('W  AEGIS: a shield dome that heals allies', 3.5)
	local h = hero()
	if h then Lol.W(h) end
end)
Sigf.Demo(22.0, function()
	cap('E  PHASE: dash through the enemy line', 3)
	local h = hero()
	if h then Lol.E(h, GetEntityCoords(h.ped) + Lol.L.dir * 10.0, 12.0) end
end)

-- R: starfall on the enemy turret
Sigf.Demo(25.0, function()
	cap('R  STARFALL: meteors with real GTA explosions', 4)
	local h, t = hero(), Lol.Struct('turret', 'red')
	if h and t then Lol.R(h, t.pos) end
end)
Sigf.Demo(31.0, function()
	local t = Lol.Struct('turret', 'red')
	if t and t.alive then Lol.HurtStruct(t, 9999) end
	cap('The turret falls: the nexus is exposed', 3.5)
	Sigf.Pilot(false)
	local n = nexusPos()
	TaskGoToCoordAnyMeans(PlayerPedId(), n.x - 15.0, n.y, n.z, 2.0, 0, false, 786603, 0.0)
end)

-- the push on the nexus: the player's own carbine hurts it too
Sigf.Demo(35.0, function()
	cap('Destroy the Nexus to win!', 4)
	local n = nexusPos()
	Lol.LookAtPoint(n)
	Sigf.Shoot(4.0, n + vector3(0, 0, 3.0))
end)
Sigf.Demo(37.0, function()
	local h = hero()
	if h then Lol.R(h, nexusPos()) end
end)
Sigf.Demo(42.0, function()
	local n = Lol.Struct('nexus', 'red')
	if n and n.alive then Lol.HurtStruct(n, 9999) end
end)
Sigf.Demo(52.0, function() Sigf.Pilot(true) end)
Sigf.Demo(56.0, function() cap('Next match: a new wave marches out', 4) end)
