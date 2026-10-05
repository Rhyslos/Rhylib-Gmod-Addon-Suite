--[[
    Bot load test (towards the 80-player target). Server console or a
    superadmin:

        rhylib_loadtest <bots> [fire 0/1] [droids]
            adds bots up to <bots> load bots in total (each a real player
            slot: start the server with enough maxplayers, e.g. 82), gives
            them a battalion trooper job (bots have no character, so
            they'd stay cadets) and a rifle through the inventory with test ammo and lets them roam, sprint, jump,
            and fire bursts (fire 1, the default). [droids] spawns that many
            droids around them (within the droid limit; needs rhylib_droids),
            so bolts, damage, downing and respawns all get exercised.
        rhylib_loadtest_stop
            kicks the load bots and removes the load droids.

    Watch it on the Staff > Profiler page (or rhylib_profile_report).
    Bots run no client code, so this measures the server and bandwidth,
    not anyone's FPS. Load bots respawn 5 s after dying.
]]

Rhylib.LoadTest = Rhylib.LoadTest or {}
local LT = Rhylib.LoadTest

LT.fire = LT.fire ~= false
LT.droids = LT.droids or {}   -- [droid] = true

local GUNS = { "rhylib_dc15a", "rhylib_dc15s", "rhylib_westarm5", "rhylib_dp23" }

function LT.Bots()
    local out = {}
    for _, p in ipairs(player.GetBots()) do
        if p.rhylibLoadBot then out[#out + 1] = p end
    end
    return out
end

function LT.Count() return #LT.Bots() end

-- A battalion trooper job for the bot (DarkRP jobs with a `battalion`, not
-- MP, medic or commander; lowest minRank), spread over the battalions.
-- Bots have no roster character, so they'd stay cadets otherwise.
local function trooperJobs()
    local best = {}
    for t, j in pairs(RPExtraTeams or {}) do
        if isstring(j.battalion) and j.battalion ~= "" and not j.mp and not j.medic and not j.commander then
            -- (minRank is a rank prefix like "PVT"; rhylib_roster turns it into a number)
            local R = Rhylib.Roster
            local rank = (j.minRank and R and R.RankIndex and R.RankIndex(j.minRank)) or 0
            local b = best[j.battalion]
            if not b or rank < b.rank then best[j.battalion] = { team = t, rank = rank } end
        end
    end
    local out = {}
    for _, b in pairs(best) do out[#out + 1] = b.team end
    table.sort(out)
    return out
end

local function enlist(p, i)
    if not (IsValid(p) and p.changeTeam) then return end
    local jobs = trooperJobs()
    if #jobs == 0 then return end
    local t = jobs[(i - 1) % #jobs + 1]
    if p:Team() ~= t then p:changeTeam(t, true, true) end
end

local function pickGun(p)
    for _, class in ipairs(GUNS) do
        if weapons.GetStored(class) then return class end
    end
end

-- Full auto, so a held trigger fires a burst, not one shot.
local function draw(p, class)
    if not (IsValid(p) and p:Alive()) then return end
    p:SelectWeapon(class)
    local w = p:GetWeapon(class)
    if IsValid(w) and w.FireModes and w.SetFireMode then
        for i, m in ipairs(w.FireModes) do
            if m == "auto" then w:SetFireMode(i) break end
        end
    end
end

local function arm(p)
    if not (IsValid(p) and p:Alive()) then return end
    p:SetNW2Bool("rhylib_infammo", true)   -- (test ammo: no reloading)
    local class = pickGun(p)
    if not class then return end
    local Inv = Rhylib.Inventory
    if Inv and Inv.AddItem and Inv.Count and Rhylib.Items and Rhylib.Items.defs[class] then
        -- Through the inventory (weight, weapon state), like a real player;
        -- the inventory stows guns on spawn, so it's drawn a moment later.
        if Inv.Count(p, class) < 1 then Inv.AddItem(p, class, 1, { issued = true }) end
    elseif not p:HasWeapon(class) then
        p:Give(class)
    end
    timer.Simple(0.2, function() draw(p, class) end)
end

Rhylib.Hook.Add("PlayerSpawn", "loadtest.arm", function(p)
    if not p.rhylibLoadBot then return end
    -- (after the spawn points' own placement, which runs a tick later)
    timer.Simple(0.3, function() if LT.Place then LT.Place(p) end end)
    timer.Simple(0.5, function() arm(p) end)
end)

-- Load bots don't hurt each other (owner: they shot each other down and
-- most lay downed or dead). Bolts still fly, trace and hit; only the
-- damage between load bots is dropped, before armour and medical. Droids
-- still hurt them, so the damage code gets used once droids are added.
Rhylib.Hook.Add("EntityTakeDamage", "loadtest.nofriendly", function(ent, dmg)
    if not (ent.rhylibLoadBot and ent:IsPlayer()) then return end
    local a = dmg:GetAttacker()
    if IsValid(a) and a.rhylibLoadBot then return true end
end, -1300)

-- Movement and firing, made up per bot (the server runs bots' commands).
Rhylib.Hook.Add("StartCommand", "loadtest.drive", function(p, cmd)
    if not p.rhylibLoadBot then return end
    local b = p.rhylibLoad
    if not b then
        b = { yaw = math.Rand(-180, 180), pitch = 0, nextTurn = 0, fireUntil = 0, nextFire = CurTime() + math.Rand(1, 4), stuckAt = 0 }
        p.rhylibLoad = b
    end
    local now = CurTime()
    if now > b.nextTurn then
        b.yaw = b.yaw + math.Rand(-90, 90)
        b.pitch = math.Rand(-8, 4)
        b.sprint = math.random() < 0.3
        b.nextTurn = now + math.Rand(2, 6)
    end
    -- Turn round when stuck against something.
    if p:GetVelocity():Length2DSqr() < 400 then
        if b.stuckAt == 0 then b.stuckAt = now elseif now - b.stuckAt > 1 then
            b.yaw = b.yaw + 180
            b.stuckAt = 0
        end
    else
        b.stuckAt = 0
    end
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetViewAngles(Angle(b.pitch, b.yaw, 0))
    local firing = LT.fire and now < b.fireUntil
    if firing then
        cmd:SetForwardMove(p:GetWalkSpeed() * 0.5)
        -- (pressed every other command: semi-auto guns need the trigger let go)
        b.pull = not b.pull
        if b.pull then cmd:SetButtons(IN_ATTACK) end
    else
        cmd:SetForwardMove(p:GetRunSpeed())
        if b.sprint then cmd:SetButtons(IN_SPEED) end
        if math.random() < 0.004 then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP)) end
        if LT.fire and now > b.nextFire then
            b.fireUntil = now + math.Rand(0.4, 1.6)
            b.nextFire = b.fireUntil + math.Rand(1.5, 5)
        end
    end
end)

-- Dead load bots come back after 5 s (no client to press a key).
timer.Create("Rhylib.LoadTest.Respawn", 1, 0, function()
    for _, p in ipairs(player.GetBots()) do
        -- (fell out of the map: back in near someone)
        if p.rhylibLoadBot and p:Alive() and not util.IsInWorld(p:GetPos()) then LT.Place(p) end
        if p.rhylibLoadBot and not p:Alive() then
            p.rhylibDeadAt = p.rhylibDeadAt or CurTime()
            if CurTime() - p.rhylibDeadAt > 5 then
                p.rhylibDeadAt = nil
                p:Spawn()
            end
        end
    end
end)

-- A spot on the ground near a position (navmesh if there is one).
local function spotNear(pos)
    if navmesh and navmesh.Find then
        local areas = navmesh.Find(pos, 1500, 150, 150)
        if areas and #areas > 0 then return areas[math.random(#areas)]:GetRandomPoint() end
    end
    local try = pos + Vector(math.Rand(-600, 600), math.Rand(-600, 600), 64)
    local tr = util.TraceLine({ start = try, endpos = try - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or nil
end

-- Somewhere in the map to put a stray bot near: a human, else an
-- in-world load bot.
local function anchor(skip)
    for _, h in ipairs(player.GetHumans()) do
        if h:Alive() and util.IsInWorld(h:GetPos()) then return h:GetPos() end
    end
    for _, b in ipairs(LT.Bots()) do
        if b ~= skip and b:Alive() and util.IsInWorld(b:GetPos()) then return b:GetPos() end
    end
end

-- A free standing spot (player hull fits) near pos, or nil.
local function freeSpot(p, pos)
    for _ = 1, 8 do
        local spot = spotNear(pos)
        if spot and util.IsInWorld(spot + Vector(0, 0, 40)) then
            local tr = util.TraceHull({ start = spot + Vector(0, 0, 4), endpos = spot + Vector(0, 0, 4),
                mins = p:OBBMins(), maxs = p:OBBMaxs(), mask = MASK_PLAYERSOLID, filter = p })
            if not tr.Hit then return spot + Vector(0, 0, 4) end
        end
    end
end

-- Spread a bot out from its spawn (80 on one spawn point stack up, and the
-- unstick pushed some under the map), or rescue one that's out of the world.
function LT.Place(p)
    if not (IsValid(p) and p:Alive()) then return end
    local base = p:GetPos()
    if not util.IsInWorld(base) then base = anchor(p) end
    if not base then return end
    local spot = freeSpot(p, base)
    if spot then
        p:SetPos(spot)
        p:SetVelocity(-p:GetVelocity())
    end
end

local function addDroids(n, say)
    local D = Rhylib.Droids
    if not (D and scripted_ents.GetStored("rhylib_b1")) then return say("rhylib_droids isn't installed: no droids") end
    local bots = LT.Bots()
    if #bots == 0 then return end
    local made = 0
    for _ = 1, n do
        if D.Count and D.Cfg and D.Count() >= D.Cfg("maxActive") then break end
        local pos = spotNear(bots[math.random(#bots)]:GetPos())
        if pos then
            local e = ents.Create(math.random() < 0.8 and "rhylib_b1" or "rhylib_b2")
            if IsValid(e) then
                e:SetPos(pos + Vector(0, 0, 4))
                e:SetAngles(Angle(0, math.Rand(-180, 180), 0))
                e:Spawn()
                LT.droids[e] = true
                made = made + 1
            end
        end
    end
    say(string.format("[Rhylib] Load test: %d droids spawned (limit %s)", made, D.Cfg and tostring(D.Cfg("maxActive")) or "?"))
end

local function allowed(ply)
    return not IsValid(ply) or ply:IsSuperAdmin()
end

concommand.Add("rhylib_loadtest", function(ply, _, args)
    local say = function(msg) if IsValid(ply) then ply:ChatPrint(msg) end print(msg) end
    if not allowed(ply) then return say("Only superadmins (or the server console) can run the load test") end
    local want = math.Clamp(tonumber(args[1]) or 0, 0, 128)
    LT.fire = args[2] ~= "0"
    local have = LT.Count()
    local made = 0
    for i = have + 1, want do
        local p = player.CreateNextBot("LoadBot " .. i)
        if not IsValid(p) then
            say(string.format("[Rhylib] Load test: the server is full (maxplayers %d). Start it with more slots.", game.MaxPlayers()))
            break
        end
        p.rhylibLoadBot = true
        -- (its first spawn ran before the flag was set; a job change
        -- respawns it, which arms it again through the spawn hook)
        local n = i
        timer.Simple(0.5, function()
            enlist(p, n)
            arm(p)
        end)
        made = made + 1
    end
    say(string.format("[Rhylib] Load test: %d load bots (%d new), firing %s. rhylib_loadtest_stop ends it.",
        LT.Count(), made, LT.fire and "on" or "off"))
    local droids = tonumber(args[3]) or 0
    if droids > 0 then timer.Simple(2, function() addDroids(math.min(droids, 200), say) end) end
end)

concommand.Add("rhylib_loadtest_stop", function(ply)
    local say = function(msg) if IsValid(ply) then ply:ChatPrint(msg) end print(msg) end
    if not allowed(ply) then return end
    local n = 0
    for _, p in ipairs(LT.Bots()) do
        p:Kick("Load test over")
        n = n + 1
    end
    local d = 0
    for e in pairs(LT.droids) do
        if IsValid(e) then
            e:Remove()
            d = d + 1
        end
    end
    LT.droids = {}
    say(string.format("[Rhylib] Load test stopped: %d bots kicked, %d droids removed", n, d))
end)
