--[[
    Republic mines (server; EOD Republic mines / Minefield skills).
    Planting (rhylib_rep_mine weapon), the limit per player, droids setting
    them off (a 0.1 s check, droids only), the blast (droids only), and
    picking your own back up (E, the client finds it and asks).
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

E.repMines = E.repMines or {}

local function limit(ply)
    return E.Skill(ply, "eod_minefield") and (E.Cfg("repLimitField") or 6) or (E.Cfg("repLimit") or 3)
end

function E.RepCount(ply)
    local n = 0
    for m in pairs(E.repMines) do
        if IsValid(m) and m:GetPlanter() == ply then n = n + 1 end
    end
    return n
end

function E.RepCanPlace(ply, pos)
    local max = limit(ply)
    if E.RepCount(ply) >= max then
        return false, "You have " .. max .. " mines out: pick one up first (E on it)"
    end
    for m in pairs(E.repMines) do
        if IsValid(m) and m:GetPos():DistToSqr(pos) < 40 * 40 then return false, "There's a mine right there already" end
    end
    return true
end

-- Plant one where tr hit (the weapon checked the ground). Returns the mine.
function E.RepPlace(ply, tr, issued)
    local ok, why = E.RepCanPlace(ply, tr.HitPos)
    if not ok then E.Msg(ply, why, true) return nil end
    local m = ents.Create("rhylib_rep_mine_planted")
    if not IsValid(m) then return nil end
    m:SetPos(tr.HitPos)
    m:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    m:Spawn()
    m:SetPlanter(ply)
    m:SetWide(E.Skill(ply, "eod_minefield"))
    m.repIssued = issued or nil   -- (an armoury mine stays issued when picked back up)
    -- half buried (top third shows)
    local mn, mx = m:OBBMins(), m:OBBMaxs()
    m:SetPos(tr.HitPos + tr.HitNormal * (-mn.z - (mx.z - mn.z) * 0.62))
    sound.Play("weapons/slam/mine_mode.wav", tr.HitPos, 65, 110)
    E.Msg(ply, string.format("Mine planted (%d / %d out). Only droids set it off.", E.RepCount(ply), limit(ply)))
    return m
end

function E.RepBoom(m)
    if not IsValid(m) or m.repOver then return end
    m.repOver = true
    local pos = m:WorldSpaceCenter() + Vector(0, 0, 8)
    local planter = m:GetPlanter()
    local attacker = IsValid(planter) and planter or m
    local r = (E.Cfg("repRadius") or 280) * (m:GetWide() and (E.Cfg("repFieldRadius") or 1.3) or 1)
    local dmg = E.Cfg("repDamage") or 260
    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed, true, true)
    sound.Play("weapons/explosives_cannons_superlazers/sw_detonator_explosion.ogg", pos, 110, 100)
    util.ScreenShake(pos, 6, 120, 0.8, r * 2)
    util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), m)
    -- droids only (players and clones aren't touched)
    local D = Rhylib.Droids
    for d in pairs(D and D.active or {}) do
        if IsValid(d) and d.IsRhylibDroid and not d.Training and d:Health() > 0 then
            local c = d:WorldSpaceCenter()
            local dist = c:Distance(pos)
            if dist <= r and not util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Hit then
                local info = DamageInfo()
                info:SetDamage(dmg * (1 - 0.6 * dist / r))
                info:SetDamageType(DMG_BLAST)
                info:SetAttacker(attacker)
                info:SetInflictor(m)
                info:SetDamagePosition(c)
                info:SetDamageForce((c - pos):GetNormalized() * 8000)
                d:TakeDamageInfo(info)
            end
        end
    end
    hook.Run("Rhylib.Explosion", pos, E.Cfg("mineChain") or 140, 1, IsValid(planter) and planter or nil, m, "repmine")
    E.repMines[m] = nil
    m:SetNoDraw(true)
    timer.Simple(0.1, function() if IsValid(m) then m:Remove() end end)
end

-- Droids walking onto one.
local function tick()
    if next(E.repMines) == nil then return end
    local D = Rhylib.Droids
    if not (D and D.active and next(D.active)) then return end
    local now = CurTime()
    local trig = E.Cfg("repTrigger") or 45
    local t2 = trig * trig
    for m in pairs(E.repMines) do
        if not IsValid(m) then
            E.repMines[m] = nil
        elseif not m.repOver and now >= (m.armAt or 0) then
            local mp = m:GetPos()
            for d in pairs(D.active) do
                if IsValid(d) and d.IsRhylibDroid and not d.Training and d:Health() > 0 then
                    local dp = d:GetPos()
                    if math.abs(dp.z - mp.z) < 60 and (dp.x - mp.x) ^ 2 + (dp.y - mp.y) ^ 2 <= t2 then
                        E.RepBoom(m)
                        break
                    end
                end
            end
        end
    end
end
timer.Create("Rhylib.EOD.RepMines", 0.1, 0, function()
    local ok, err = pcall(tick)
    if not ok then ErrorNoHaltWithStack("[Rhylib] EOD Republic mines: " .. tostring(err)) end
end)

-- E on your own mine: back into the inventory.
Net.Receive("eod.reppick", function(p)
    local m = net.ReadEntity()
    if not (IsValid(m) and m.IsRepMine) or m.repOver or m:GetPlanter() ~= p or not p:Alive() then return end
    if p:GetPos():DistToSqr(m:GetPos()) > 160 * 160 then return end
    local Inv = Rhylib.Inventory
    if Inv and Inv.AddItem then
        if (Inv.AddItem(p, E.RMINE, 1, m.repIssued and { issued = true } or nil) or 0) > 0 then E.Msg(p, "Couldn't take the mine back (no room?)", true) return end
    else
        p:Give(E.RMINE)
    end
    E.repMines[m] = nil
    m.repOver = true
    m:Remove()
    sound.Play("weapons/slam/mine_mode.wav", p:GetPos(), 60, 90)
    E.Msg(p, string.format("Mine picked up (%d / %d out)", E.RepCount(p), limit(p)))
end, { rate = 6, burst = 6 })

-- Someone who leaves takes their mines with them.
Rhylib.Hook.Add("PlayerDisconnected", "eod.repmines", function(p)
    for m in pairs(E.repMines) do
        if IsValid(m) and m:GetPlanter() == p then m:Remove() end
    end
end)
