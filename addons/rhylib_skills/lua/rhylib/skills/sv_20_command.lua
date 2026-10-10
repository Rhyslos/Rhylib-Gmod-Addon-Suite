--[[
    Command orders on the server: giving one (K.IssueOrder, from the
    comlink), Field triage healing, handing out the comlink, Press
    forward against knockdowns. Shared state and numbers: sh_20_command.lua.
    Net skills.order (order index 3 bits, issuer entity) to everyone it reached.
    Also: Reinforcements (K.CallReinforcements -> rhylib_droids
    D.CallSquad) and the squad wheel (net skills.squad: option index 3
    bits into K.SQUAD_OPS -> rhylib_droids D.SquadOrder).
    Cooldowns are kept by SteamID64 in memory (K.orderCd, K.reinfCd), not
    saved: a map change resets them.
]]

local K = Rhylib.Skills

Rhylib.Net.Register("skills.order")

local function cfg(k) return K.Cfg(k) end

-- Players being healed by Field triage: [ply] = true.
K.triage = K.triage or {}
-- Cooldowns by SteamID64, so leaving and rejoining doesn't reset them
-- (memory only; a map change does).
K.orderCd = K.orderCd or {}

K.reinfCd = K.reinfCd or {}

Rhylib.Hook.Add("PlayerInitialSpawn", "skills.ordercd", function(ply)
    local t = K.orderCd[ply:SteamID64() or ""]
    if t and t > CurTime() then ply:SetNW2Float("rhylib_orderCd", t) end
    local r = K.reinfCd[ply:SteamID64() or ""]
    if r and r > CurTime() then ply:SetNW2Float("rhylib_reinfCd", r) end
end)

local function canReceive(p)
    if not (IsValid(p) and p:Alive()) or p.rhylibDown then return false end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and Med.IsDown(p) then return false end
    return true
end

-- K.IssueOrder(ply): give this officer's order to themselves and everyone
-- alive and not downed within K.OrderRadius in sight (brush trace from the
-- eyes), plus the whole radio squad with Chain of command. Checks the
-- skill, rank, cooldown, cuffs/stun. Returns ok, reason. Server only;
-- the comlink's left click calls it.
-- Example: local ok, why = Rhylib.Skills.IssueOrder(ply)  if not ok then Rhylib.Skills.Note(ply, why, true) end
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
    local len = K.OrderTime(ply)
    local untilT = now + len
    local from = ply:EyePos()
    local r2 = K.OrderRadius(ply) ^ 2
    -- Chain of command: the whole radio squad, wherever they are.
    local chain = {}
    if K.Has(ply, "chain_command") and K.SquadMembers then
        for _, p in ipairs(K.SquadMembers(ply)) do chain[p] = true end
    end
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
        local reach = near and (p == ply or not util.TraceLine({ start = from, endpos = p:EyePos(), mask = MASK_SOLID_BRUSHONLY }).Hit)
        if canReceive(p) and (reach or chain[p]) then
            -- Hold fast: armour back to full (it stays after the order).
            if o.key == "hold" then
                local full = A and A.SpawnArmor and A.SpawnArmor(p) or 100
                if p:Armor() < full then p:SetArmor(full) end
            end
            hit[#hit + 1] = p
            p:SetNW2Int("rhylib_order", o.index)
            p:SetNW2Float("rhylib_orderEnd", untilT)
            p:SetNW2Float("rhylib_orderLen", len)
            -- Field triage mutes afflictions; another order ends that.
            p:SetNW2Float("rhylib_afflMute", o.key == "triage" and untilT or 0)
            if o.key == "triage" then K.triage[p] = true else K.triage[p] = nil end
        end
    end
    local cdLen = K.OrderCooldownTime(ply)
    ply:SetNW2Float("rhylib_orderCd", now + cdLen)
    K.orderCd[ply:SteamID64() or ""] = now + cdLen
    ply:EmitSound("npc/combine_soldier/vo/on1.wav", 70, 110)

    Rhylib.Net.Start("skills.order")
    net.WriteUInt(o.index, 3)
    net.WriteEntity(ply)
    net.Send(hit)
    return true
end

-- Reinforcements (Commander capstone, 2026-10-06az): a clone squad
-- (rhylib_droids D.CallSquad) around the officer. Returns true and the
-- number of clones that came, or false and the reason. The cooldown is
-- only spent if at least one clone came. Server only.
function K.CallReinforcements(ply)
    if not K.HasReinforcements(ply) then return false, "You haven't learned Reinforcements" end
    if not canReceive(ply) then return false, "You can't call reinforcements right now" end
    local ok, why = K.RankOk(ply, "commandRank")
    if not ok then return false, why end
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or MP.IsStunned(ply)) then return false, "You can't call reinforcements right now" end
    -- (comms jammer, rhylib_radio: the call can't get out)
    if ply.rhylibJammed then return false, "Comms are jammed here: you can't call reinforcements" end
    local cd = K.ReinfCooldown(ply)
    if cd > 0 then
        local s = math.ceil(cd)
        return false, string.format("Reinforcements ready in %d:%02d", math.floor(s / 60), s % 60)
    end
    local D = Rhylib.Droids
    if not (D and D.CallSquad) then return false, "Reinforcements aren't available on this server" end
    local squad = cfg("reinfSquad")
    if not istable(squad) or #squad == 0 then return false, "No reinforcements are set up (skills reinfSquad)" end
    local made = D.CallSquad(ply, squad, cfg("reinfLife"))
    if made == 0 then return false, "No room for reinforcements here, or the clone limit is reached" end
    local untilT = CurTime() + cfg("reinfCooldown")
    ply:SetNW2Float("rhylib_reinfCd", untilT)
    K.reinfCd[ply:SteamID64() or ""] = untilT
    ply:EmitSound("npc/combine_soldier/vo/affirmative.wav", 70, 105)
    return true, made
end

-- Squad orders (comlink R wheel, 2026-10-06be): Commander officers order
-- the clones following them (rhylib_droids D.SquadOrder). Each order also
-- runs its hand-signal chat command (config squadSignals, 2026-10-06bf).
-- Default mode "hooks" calls the PlayerSay hooks but not the gamemode's own
-- PlayerSay (DarkRP's prints the line in local chat: owner, 2026-10-06bh).
local function signal(ply, op)
    local map = cfg("squadSignals")
    local cmd = istable(map) and map[op]
    if not isstring(cmd) or cmd == "" then return end
    local mode = cfg("squadSignalMode")
    if mode == "say" then
        ply:ConCommand("say " .. cmd)
    elseif mode == "gamemode" then
        hook.Run("PlayerSay", ply, cmd, false)
    else
        for name, fn in pairs(hook.GetTable().PlayerSay or {}) do
            if isstring(name) then
                local ok, err = pcall(fn, ply, cmd, false)
                if not ok then ErrorNoHalt("[Rhylib] squad signal hook " .. name .. ": " .. tostring(err) .. "\n") end
            elseif IsValid(name) then
                pcall(fn, name, ply, cmd, false)
            end
        end
    end
end

-- (0.4 s rate limit per player on top of the net rate limit; the comlink
-- must be in hand)
Rhylib.Net.Receive("skills.squad", function(ply)
    local op = K.SQUAD_OPS[net.ReadUInt(3)]
    if not op then return end
    if (ply.rhylibSquadNext or 0) > CurTime() then return end
    ply.rhylibSquadNext = CurTime() + 0.4
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_commlink") then return end
    if not canReceive(ply) then return K.Note(ply, "You can't give orders right now", true) end
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or (MP.IsStunned and MP.IsStunned(ply))) then
        return K.Note(ply, "You can't give orders right now", true)
    end
    local D = Rhylib.Droids
    if not (D and D.SquadOrder) then return end
    if not K.CanCommandSquad(ply) then return K.Note(ply, "Only Commander officers (or officers with Reinforcements) give squad orders", true) end
    local ok, why = K.RankOk(ply, "commandRank")
    if not ok then return K.Note(ply, why, true) end
    local msg = D.SquadOrder(ply, op)
    local failed = msg and string.sub(msg, 1, 3) == "No "
    if msg then K.Note(ply, msg, failed) end
    if not failed then signal(ply, op) end
end)

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

-- K.GiveCommlink(ply): the comlink as job gear (issued + loadout) for
-- anyone with a command order (back after a respawn if it was dropped;
-- dropped by K.SetSkills when the skill goes). Needs rhylib_inventory.
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
