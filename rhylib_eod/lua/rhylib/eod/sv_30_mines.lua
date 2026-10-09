--[[
    Mines (server): placing (toolgun entries), pressing (a 0.1 s check of
    every walking player's path since the last check), the presser who
    must hold still, detonation, chain reactions, the defusal steps (dig,
    safety pin(s) on the moving needle, lift), and marking from the
    mine scanner.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

for _, n in ipairs({ "eod.mineopen" }) do Net.Register(n) end

E.mines = E.mines or {}

local function walkOk(p) return IsValid(p) and p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP end
local function holdsTool(p)
    local w = p:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

function E.SetupMine(mine)
    local lap = mine.MineType == "lap"
    mine.eodm = {
        center = math.random(18, 82),
        width = lap and 10 or 16,
        period = lap and math.Rand(0.95, 1.25) or math.Rand(1.4, 1.9),
        ph = math.Rand(0, 6.283),
        armAt = CurTime() + 2,
    }
    E.mines[mine] = true
end

-- Toolgun: n mines around the aimed spot (spread 0 = exactly there),
-- lapShare = chance each is a LAP. Half buried. Returns the entities.
function E.PlaceMines(tr, n, spread, lapShare)
    local out, spots = {}, {}
    n = math.Clamp(n or 1, 1, 40)
    for i = 1, n do
        local pos, normal = tr.HitPos, tr.HitNormal
        if spread <= 0 then
            local down = util.TraceLine({ start = tr.HitPos + Vector(0, 0, 40), endpos = tr.HitPos - Vector(0, 0, 120), mask = MASK_SOLID_BRUSHONLY })
            if down.Hit and down.HitNormal.z > 0.7 then pos, normal = down.HitPos, down.HitNormal else pos = nil end
        else
            pos = nil
            for _ = 1, 8 do
                local a, r = math.Rand(0, 6.283), spread * math.sqrt(math.random())
                local try = tr.HitPos + Vector(math.cos(a) * r, math.sin(a) * r, 0)
                local down = util.TraceLine({ start = try + Vector(0, 0, 80), endpos = try - Vector(0, 0, 240), mask = MASK_SOLID_BRUSHONLY })
                if down.Hit and down.HitNormal.z > 0.7 then
                    local free = true
                    for _, s in ipairs(spots) do if s:DistToSqr(down.HitPos) < 70 * 70 then free = false break end end
                    if free then pos, normal = down.HitPos, down.HitNormal break end
                end
            end
        end
        if pos then
            spots[#spots + 1] = pos
            local lap = lapShare >= 1 or (lapShare > 0 and math.random() < lapShare)
            local ent = ents.Create(lap and "rhylib_eod_mine_lap" or "rhylib_eod_mine")
            if IsValid(ent) then
                ent:SetPos(pos)
                ent:SetAngles(Angle(0, math.random(0, 359), 0))
                ent:Spawn()
                -- half buried: the top third shows
                local mn, mx = ent:OBBMins(), ent:OBBMaxs()
                ent:SetPos(pos + normal * (-mn.z - (mx.z - mn.z) * 0.62))
                out[#out + 1] = ent
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- Detonation
--------------------------------------------------------------------------

function E.MineBoom(mine, cause)
    if not IsValid(mine) or mine.eodOver or mine:GetSafe() then return end
    mine.eodOver = true
    local pos = E.MineTop(mine) + mine:GetUp() * 8
    local lap = mine.MineType == "lap"
    local presser = mine:GetPresser()
    if IsValid(presser) then
        presser:SetNW2Entity("rhylib_onMine", NULL)
        local c = E.CAUSES[cause or "mine"] or E.CAUSES.mine
        E.Msg(presser, c[1] .. ": " .. c[3], true)
    end
    for p in pairs(mine.viewers or {}) do
        if IsValid(p) and p ~= presser then
            local c = E.CAUSES[cause or "mine"] or E.CAUSES.mine
            E.Msg(p, c[1] .. ": " .. c[2], true)
        end
    end
    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed, true, true)
    sound.Play("weapons/explosives_cannons_superlazers/sw_detonator_explosion.ogg", pos, 115, lap and 85 or 105)
    local r = E.Cfg(lap and "lapRadius" or "apRadius") or 260
    util.BlastDamage(mine, mine, pos, r, E.Cfg(lap and "lapDamage" or "apDamage") or 170)
    util.ScreenShake(pos, lap and 10 or 6, 120, 0.8, r * 2.5)
    util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), mine)
    hook.Run("Rhylib.Explosion", pos, E.Cfg("mineChain") or 140, 1, nil, mine, "mine")
    E.mines[mine] = nil
    E.KeepForNextMap(mine)
    mine:SetNoDraw(true)
    timer.Simple(0.1, function() if IsValid(mine) then mine:Remove() end end)
end

-- Explosions nearby set mines off (a moment later: chains ripple out).
Rhylib.Hook.Add("Rhylib.Explosion", "eod.mines", function(pos, reach, tier, attacker, inflictor, kind)
    if IsValid(attacker) and attacker.IsRhylibDroid then return end   -- (droids know their mines)
    local r2 = math.max(reach or 0, 60) ^ 2
    for m in pairs(E.mines) do
        if IsValid(m) and m ~= inflictor and not m.eodOver and not m:GetSafe() and m:GetPos():DistToSqr(pos) <= r2 then
            timer.Simple(math.Rand(0.08, 0.25), function() E.MineBoom(m, "mine") end)
        end
    end
end)

-- Shot (bolts, bullets, blasts that reach it): it goes off.
function E.MineShot(mine, dmg)
    if mine.eodOver or mine:GetSafe() or dmg:GetDamage() < 8 then return end
    if dmg:IsDamageType(DMG_BLAST) then return end   -- (blasts: the Rhylib.Explosion hook above, with its own reach)
    local a = dmg:GetAttacker()
    if IsValid(a) and a:IsPlayer() and holdsTool(a) then return end
    if IsValid(a) and a.IsRhylibDroid then return end   -- (droids don't shoot their own mines)
    timer.Simple(0, function() E.MineBoom(mine, "mine") end)
end

--------------------------------------------------------------------------
-- Pressing: every walking player's path since the last check
--------------------------------------------------------------------------

local function segDist2D(p, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.Clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0, 1) or 0
    local cx, cy = a.x + dx * t, a.y + dy * t
    return math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
end

local function press(mine, p)
    mine:SetPresser(p)
    mine.pressPos = p:GetPos()
    mine.pressAt = CurTime()
    p:SetVelocity(-p:GetVelocity())   -- (the click stops you; see E.MINE_GRACE)
    p:SetNW2Float("rhylib_mineAt", CurTime())
    p:SetNW2Entity("rhylib_onMine", mine)
    sound.Play("weapons/slam/mine_mode.wav", mine:GetPos(), 70, 90)
    E.Msg(p, "Click. You're standing on a mine: don't move. Someone with an EOD kit can dig it out and pin it.", true)
end

local function tick()
    if next(E.mines) == nil then return end
    local now = CurTime()
    local players = player.GetAll()
    -- walkers this tick: { ply, from, to }
    local walk = {}
    for _, p in ipairs(players) do
        local pos = p:GetPos()
        local from = p.eodMinePrev or pos
        local wasGround = p.eodMineGround
        p.eodMinePrev = pos
        p.eodMineGround = p:IsOnGround()
        -- (teleports, respawns, landings: only where they are now)
        if not wasGround or from:DistToSqr(pos) > 120 * 120 then from = pos end
        if walkOk(p) and p:IsOnGround() and not holdsTool(p) and not IsValid(p:GetNW2Entity("rhylib_onMine")) then
            walk[#walk + 1] = { p, from, pos }
        end
    end
    local D = Rhylib.Droids
    for m in pairs(E.mines) do
        if not IsValid(m) then
            E.mines[m] = nil
        elseif not m.eodOver and not m:GetSafe() then
            local mp = m:GetPos()
            local presser = m:GetPresser()
            if IsValid(presser) and now - m.pressAt < E.MINE_GRACE then
                -- (still in the click: where they come to rest counts)
                if presser:Alive() then m.pressPos = presser:GetPos() end
            elseif IsValid(presser) then
                -- whoever is on it must hold still
                local moved = presser:GetPos()
                if not presser:Alive() or presser:GetMoveType() == MOVETYPE_NOCLIP
                    or math.sqrt((moved.x - m.pressPos.x) ^ 2 + (moved.y - m.pressPos.y) ^ 2) > (E.Cfg("mineShift") or 16)
                    or (not presser:IsOnGround() and now - m.pressAt > 0.3) then
                    E.MineBoom(m, "mine")
                end
            elseif m.eodm and now >= m.eodm.armAt and not m:GetDug() then
                local trig = E.Cfg(m.MineType == "lap" and "lapTrigger" or "apTrigger") or 26
                for _, w in ipairs(walk) do
                    local p, from, to = w[1], w[2], w[3]
                    if math.abs(to.z - mp.z) < 40 and to:DistToSqr(mp) < 600 * 600 and segDist2D(mp, from, to) <= trig then
                        press(m, p)
                        -- (one presser; anyone else nearby is safe until it goes)
                        for i, x in ipairs(walk) do if x[1] == p then table.remove(walk, i) break end end
                        break
                    end
                end
                -- clone NPCs set it off at once (droids know their own mines)
                if not IsValid(m:GetPresser()) and D and D.clones then
                    for c in pairs(D.clones) do
                        if IsValid(c) and c:Health() > 0 then
                            local cp = c:GetPos()
                            if math.abs(cp.z - mp.z) < 40 and (cp.x - mp.x) ^ 2 + (cp.y - mp.y) ^ 2 <= trig * trig then
                                E.MineBoom(m, "mine")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end
timer.Create("Rhylib.EOD.Mines", 0.1, 0, function()
    local ok, err = pcall(tick)
    if not ok then ErrorNoHaltWithStack("[Rhylib] EOD mines: " .. tostring(err)) end
end)

-- Leaving the server or dying on it sets it off (the tick sees it too).
Rhylib.Hook.Add("PlayerDisconnected", "eod.mines", function(p)
    local m = p:GetNW2Entity("rhylib_onMine")
    if IsValid(m) and m.IsRhylibMine then E.MineBoom(m, "mine") end
end)

--------------------------------------------------------------------------
-- Defusing: E on a mine (the client finds it and asks), then the steps
--------------------------------------------------------------------------

local REACH = 110

local function nearMine(p, m)
    return IsValid(m) and m.IsRhylibMine and walkOk(p) and p:GetPos():DistToSqr(m:GetPos()) <= (REACH + 30) ^ 2
end

local function sendOpen(p, m)
    local d = m.eodm
    local w = d.width * (E.Skill(p, "eod_steady") and 1.4 or 1)
    Net.Start("eod.mineopen")
    net.WriteEntity(m)
    net.WriteUInt(d.center, 7)
    net.WriteFloat(w)
    net.WriteFloat(d.period)
    net.WriteFloat(d.ph)
    net.Send(p)
end

Net.Receive("eod.mineuse", function(p)
    local m = net.ReadEntity()
    if not (IsValid(m) and m.IsRhylibMine and m.eodm) or m.eodOver then return end
    if not nearMine(p, m) then return end
    m.viewers = m.viewers or {}
    m.viewers[p] = true
    sendOpen(p, m)
end, { rate = 6, burst = 6 })

-- 0 dig start, 1 dig done, 2 pin, 3 lift start, 4 lift done, 5 close
Net.Receive("eod.mineact", function(p)
    local m = net.ReadEntity()
    local op = net.ReadUInt(3)
    if not (IsValid(m) and m.IsRhylibMine and m.eodm) or m.eodOver then return end
    if op == 5 then if m.viewers then m.viewers[p] = nil end return end
    if not nearMine(p, m) then return end
    if m:GetPresser() == p then E.Msg(p, "You can't reach the fuse while you're standing on it", true) return end
    if not E.HasKit(p) then E.Msg(p, "You need an EOD kit", true) return end
    local now = CurTime()
    if op == 0 or op == 3 then
        p.eodMineHold = { m = m, op = op, t = now }
    elseif op == 1 then
        local h = p.eodMineHold
        p.eodMineHold = nil
        local need = (E.Cfg("mineDigTime") or 3) * (E.Skill(p, "eod_quick") and 0.6 or 1)
        if m:GetDug() or not h or h.m ~= m or h.op ~= 0 or now - h.t < need * 0.9 then return end
        m:SetDug(true)
        E.Msg(p, "Dug out: the fuse is showing. Push the safety pin in while the needle is in the zone.")
    elseif op == 2 then
        if not m:GetDug() or m:GetSafe() then return end
        local d = m.eodm
        local w = d.width * (E.Skill(p, "eod_steady") and 1.4 or 1)
        local n = E.MineNeedle(d.period, d.ph, now - math.min(0.25, p:Ping() / 1000))
        if math.abs(n - d.center) > w / 2 + 3 then
            E.MineBoom(m, "minepin")
            return
        end
        m:SetPins(m:GetPins() + 1)
        sound.Play("weapons/slam/mine_mode.wav", m:GetPos(), 60, 140)
        if m:GetPins() >= m:PinsNeeded() then
            m:SetSafe(true)
            local pr = m:GetPresser()
            if IsValid(pr) then
                pr:SetNW2Entity("rhylib_onMine", NULL)
                E.Msg(pr, "The mine is pinned: you can step off.")
            end
            m:SetPresser(NULL)
            E.Msg(p, "Pinned: the mine is safe. Lift it away.")
        else
            E.Msg(p, "First pin in. One more.")
        end
    elseif op == 4 then
        local h = p.eodMineHold
        p.eodMineHold = nil
        local need = E.Cfg("mineLiftTime") or 2
        if not m:GetSafe() or not h or h.m ~= m or h.op ~= 3 or now - h.t < need * 0.9 then return end
        E.mines[m] = nil
        E.KeepForNextMap(m)
        m:Remove()
        E.Msg(p, "Mine lifted and made safe")
    end
end, { rate = 10, burst = 10 })

--------------------------------------------------------------------------
-- Mine scanner: RMB marks a mine it shows (everyone then sees it)
--------------------------------------------------------------------------

Net.Receive("eod.minemark", function(p)
    local m = net.ReadEntity()
    if not (IsValid(m) and m.IsRhylibMine) or m.eodOver or not walkOk(p) then return end
    local w = p:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == E.SCANNER and w.GetOn and w:GetOn()) then return end
    local eye = p:EyePos()
    local mp = E.MineTop(m) + m:GetUp() * 2
    local range = E.Cfg("mineScanRange") or 700
    if eye:DistToSqr(mp) > (range + 60) ^ 2 then return end
    local dir = E.ScanDir and E.ScanDir(p) or p:GetAimVector()
    if dir:Dot((mp - eye):GetNormalized()) < math.cos(math.rad((E.Cfg("mineScanCone") or 22) + 6)) then return end
    if util.TraceLine({ start = eye, endpos = mp, mask = MASK_SOLID_BRUSHONLY }).Hit then return end
    m:SetMarked(not m:GetMarked())
    sound.Play("buttons/blip1.wav", p:GetPos(), 60, m:GetMarked() and 130 or 90)
end, { rate = 8, burst = 8 })
