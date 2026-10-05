--[[
    Command orders on the server: giving one (K.IssueOrder, from the
    comlink), Field triage healing, handing out the comlink, Press
    forward against knockdowns. Shared state and numbers: sh_20_command.lua.
    Net skills.order (order index 3 bits, issuer) to everyone it reached.
]]

local K = Rhylib.Skills

Rhylib.Net.Register("skills.order")

local function cfg(k) return K.Cfg(k) end

-- Players being healed by Field triage: [ply] = true.
K.triage = K.triage or {}
-- Cooldowns by SteamID64, so leaving and rejoining doesn't reset them
-- (memory only; a map change does).
K.orderCd = K.orderCd or {}

Rhylib.Hook.Add("PlayerInitialSpawn", "skills.ordercd", function(ply)
    local t = K.orderCd[ply:SteamID64() or ""]
    if t and t > CurTime() then ply:SetNW2Float("rhylib_orderCd", t) end
end)

local function canReceive(p)
    if not (IsValid(p) and p:Alive()) or p.rhylibDown then return false end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and Med.IsDown(p) then return false end
    return true
end

-- Give this officer's order. Returns ok, reason.
function K.IssueOrder(ply)
    local o = K.OrderOf(ply)
    if not o then return false, "You have no command order" end
    if not canReceive(ply) then return false, "You can't give orders right now" end
    local ok, why = K.RankOk(ply, "commandRank")
    if not ok then return false, why end
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or MP.IsStunned(ply)) then return false, "You can't give orders right now" end
    local cd = K.OrderCooldown(ply)
    if cd > 0 then
        local s = math.ceil(cd)
        return false, string.format("Next order in %d:%02d", math.floor(s / 60), s % 60)
    end

    local now = CurTime()
    local untilT = now + cfg("commandTime")
    local from = ply:EyePos()
    local r2 = cfg("commandRadius") ^ 2
    local hit = {}
    local Med, A = Rhylib.Medical, Rhylib.Armor
    for _, p in ipairs(player.GetAll()) do
        local near = IsValid(p) and p:Alive() and p:GetPos():DistToSqr(ply:GetPos()) <= r2
        -- Field triage: downed players in reach get up at triageRevive of
        -- their max health (the heal and muted afflictions follow).
        if near and o.key == "triage" and Med and Med.IsDown and Med.IsDown(p) and Med.Revive
            and not util.TraceLine({ start = from, endpos = p:GetPos() + Vector(0, 0, 20), mask = MASK_SOLID_BRUSHONLY }).Hit then
            Med.Revive(p, math.max(1, p:GetMaxHealth() * cfg("triageRevive")), ply)
        end
        if near and canReceive(p)
            and (p == ply or not util.TraceLine({ start = from, endpos = p:EyePos(), mask = MASK_SOLID_BRUSHONLY }).Hit) then
            -- Hold fast: armour back to full (it stays after the order).
            if o.key == "hold" then
                local full = A and A.SpawnArmor and A.SpawnArmor(p) or 100
                if p:Armor() < full then p:SetArmor(full) end
            end
            hit[#hit + 1] = p
            p:SetNW2Int("rhylib_order", o.index)
            p:SetNW2Float("rhylib_orderEnd", untilT)
            -- Field triage mutes afflictions; another order ends that.
            p:SetNW2Float("rhylib_afflMute", o.key == "triage" and untilT or 0)
            if o.key == "triage" then K.triage[p] = true else K.triage[p] = nil end
        end
    end
    ply:SetNW2Float("rhylib_orderCd", now + cfg("commandCooldown"))
    K.orderCd[ply:SteamID64() or ""] = now + cfg("commandCooldown")
    ply:EmitSound("npc/combine_soldier/vo/on1.wav", 70, 110)

    Rhylib.Net.Start("skills.order")
    net.WriteUInt(o.index, 3)
    net.WriteEntity(ply)
    net.Send(hit)
    return true
end

-- Field triage: triageHeal health a second, in quarter-second steps.
timer.Create("Rhylib.Skills.Triage", 0.25, 0, function()
    if next(K.triage) == nil then return end
    local step = cfg("triageHeal") * 0.25
    for p in pairs(K.triage) do
        if not (IsValid(p) and K.OrderIs(p, "triage")) then
            K.triage[p] = nil
        elseif canReceive(p) and p:Health() < p:GetMaxHealth() then
            p.rhylibTriageAcc = (p.rhylibTriageAcc or 0) + step
            local whole = math.floor(p.rhylibTriageAcc)
            if whole >= 1 then
                p.rhylibTriageAcc = p.rhylibTriageAcc - whole
                p:SetHealth(math.min(p:GetMaxHealth(), p:Health() + whole))
            end
        end
    end
end)

-- Orders end on death and respawn (the officer's cooldown stays).
local function clearOrder(p)
    p:SetNW2Int("rhylib_order", 0)
    p:SetNW2Float("rhylib_orderEnd", 0)
    p:SetNW2Float("rhylib_afflMute", 0)
    K.triage[p] = nil
end
Rhylib.Hook.Add("PlayerSpawn", "skills.order", clearOrder)
Rhylib.Hook.Add("PlayerDeath", "skills.order", clearOrder)
Rhylib.Hook.Add("Rhylib.PlayerDowned", "skills.order", clearOrder)
Rhylib.Hook.Add("PlayerDisconnected", "skills.order", function(p) K.triage[p] = nil end)

-- Press forward: no explosion knockdowns (rhylib_weapons).
Rhylib.Hook.Add("Rhylib.CanKnockDown", "skills.press", function(p)
    if K.OrderIs(p, "press") then return false end
end)

-- The comlink: job gear for anyone with a command order (back after a
-- respawn if it was dropped; dropped by K.SetSkills when the skill goes).
function K.GiveCommlink(ply)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.AddItem and Inv.Count) or not K.OrderOf(ply) then return end
    local Items = Rhylib.Items
    if not (Items and Items.defs and Items.defs[K.COMMLINK]) then return end
    if Inv.Count(ply, K.COMMLINK) > 0 then return end
    Inv.AddItem(ply, K.COMMLINK, 1, { issued = true, loadout = true })
end

Rhylib.Hook.Add("PlayerSpawn", "skills.commlink", function(ply)
    timer.Simple(0.5, function()
        if IsValid(ply) and ply:Alive() then K.GiveCommlink(ply) end
    end)
end)
Rhylib.Hook.Add("Rhylib.SkillsChanged", "skills.commlink", function(ply)
    if ply:Alive() then K.GiveCommlink(ply) end
end)
