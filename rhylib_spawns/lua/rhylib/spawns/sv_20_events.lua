--[[
    Event tools (server): respawn tickets, medic zones, objective markers
    (sh_20_events.lua explains them).

    Command rhylib_tickets / !tickets (perm rhylib.spawns.admin):
      !tickets            how many are left (and whether they're on)
      !tickets on [n]     switch them on with n (default ticketsStart)
      !tickets off        switch them off (everyone respawns as normal)
      !tickets add <n>    add n (a negative n takes some away)
      !tickets set <n>    set the pool to n
    Someone who dies, leaves and rejoins is still owed (S.ticketDue).
    Staff with rhylib.spawns.admin (game masters, admins) never use or
    wait for a ticket.
    Medic zones only revive someone downed outside a zone and brought in.
    Respawning: PlayerDeath marks a death while tickets are on;
    PlayerDeathThink ("spawns.tickets") holds a marked player dead while
    the pool is empty; PlayerSpawn spends one for a marked player.
    S.SetTickets(n), S.AddTickets(n), S.SetTicketsOn(on) (server).

    Medic zones: timer Rhylib.Spawns.MedicZones (0.5 s).
    Objective markers: net spawn.objedit (server -> staff: Entity, open the
    edit menu), spawn.objset (staff: Entity, op UInt 2: 0 rename + String,
    1 battalion + String, 2 shown while jammed on / off; rate 4/s).
]]

local S = Rhylib.Spawns

Rhylib.Net.Register("spawn.objedit")

local function isStaff(ply, fn)
    Rhylib.Perms.Check(ply, "rhylib.spawns.admin", function(ok) if ok then fn() end end)
end

--------------------------------------------------------------------------
-- Respawn tickets
--------------------------------------------------------------------------

-- Owed a ticket (died while tickets are on): ply.rhylibTicketDue, NW2Bool
-- rhylib_ticketDue (the client's "wait for staff" line), and
-- S.ticketDue["s" .. SteamID64] so leaving and rejoining doesn't skip it.
S.ticketDue = S.ticketDue or {}
local function sidOf(ply) return "s" .. (ply:SteamID64() or "") end
local function setDue(ply, on)
    ply.rhylibTicketDue = on or nil
    S.ticketDue[sidOf(ply)] = on or nil
    ply:SetNW2Bool("rhylib_ticketDue", on and true or false)
end

function S.SetTickets(n)
    n = math.max(0, math.floor(tonumber(n) or 0))
    local was = S.Tickets()
    SetGlobal2Int("rhylib_tickets", n)
    if S.TicketsOn() and n == 0 and was > 0 then
        Rhylib.Notify(true, "Respawn tickets are out: whoever dies now stays dead", "bad", "Spawns")
    end
end

function S.AddTickets(n) S.SetTickets(S.Tickets() + (tonumber(n) or 0)) end

function S.SetTicketsOn(on, n)
    SetGlobal2Bool("rhylib_tickets_on", on and true or false)
    if on then
        S.SetTickets(n or Rhylib.Config.Get("spawns", "ticketsStart"))
        Rhylib.Notify(true, "Respawn tickets are on: " .. S.Tickets() .. " for everyone. Each respawn after a death uses one", "info", "Spawns")
    else
        S.ticketDue = {}
        for _, p in ipairs(player.GetAll()) do setDue(p, false) end
        Rhylib.Notify(true, "Respawn tickets are off: respawning as normal", "info", "Spawns")
    end
end

-- (staff running the event, perm rhylib.spawns.admin: game masters and
-- admins, always respawn and use no ticket)
Rhylib.Hook.Add("PlayerDeath", "spawns.tickets", function(ply)
    if not S.TicketsOn() then return end
    setDue(ply, true)
    isStaff(ply, function() if IsValid(ply) then setDue(ply, false) end end)
end)

-- (out of tickets: stay dead)
Rhylib.Hook.Add("PlayerDeathThink", "spawns.tickets", function(ply)
    if ply.rhylibTicketDue and S.TicketsOn() and S.Tickets() <= 0 then return false end
end, -10)

-- A respawn after a death spends one; someone who died, left and came
-- back is still owed (S.ticketDue by SteamID): with none left, they're
-- put back down dead.
Rhylib.Hook.Add("PlayerSpawn", "spawns.tickets", function(ply)
    if not ply.rhylibTicketDue and not S.ticketDue[sidOf(ply)] then return end
    if not S.TicketsOn() then setDue(ply, false) return end
    if S.Tickets() <= 0 then
        ply.rhylibTicketDue = true
        timer.Simple(0, function() if IsValid(ply) and ply:Alive() then ply:KillSilent() end end)
        return
    end
    setDue(ply, false)
    S.SetTickets(S.Tickets() - 1)
end, -10)

Rhylib.Command.Add({
    name = "rhylib_tickets", chat = { "tickets" }, perm = "rhylib.spawns.admin", tag = "Spawns",
    args = "[on <n> | off | add <n> | set <n>]", help = "Respawn tickets for an event: one shared pool, each respawn after a death uses one",
    fn = function(ply, args)
        local op = string.lower(args[1] or "")
        local n = tonumber(args[2] or "")
        if op == "" then
            return S.TicketsOn() and ("Respawn tickets are on: " .. S.Tickets() .. " left") or "Respawn tickets are off (!tickets on <n>)", "info"
        elseif op == "on" then
            S.SetTicketsOn(true, n)
        elseif op == "off" then
            S.SetTicketsOn(false)
        elseif op == "add" and n then
            S.AddTickets(n)
            return "Respawn tickets: " .. S.Tickets() .. " left", "good"
        elseif op == "set" and n then
            S.SetTickets(n)
            return "Respawn tickets: " .. S.Tickets() .. " left", "good"
        else
            return "Usage: !tickets [on <n> | off | add <n> | set <n>]", "bad"
        end
    end,
})

--------------------------------------------------------------------------
-- Medic zones
--------------------------------------------------------------------------

S.medicZones = S.medicZones or {}

timer.Create("Rhylib.Spawns.MedicZones", 0.5, 0, function()
    if not next(S.medicZones) then return end
    local r = math.max(50, Rhylib.Config.Get("spawns", "medicZoneRadius"))
    local r2 = r * r
    local regen = math.max(0, Rhylib.Config.Get("spawns", "medicZoneRegen")) * 0.5
    local Med = Rhylib.Medical
    local zones = {}
    for z in pairs(S.medicZones) do
        if IsValid(z) then zones[#zones + 1] = z:GetPos() else S.medicZones[z] = nil end
    end
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() then
            local pos, inside = p:GetPos(), false
            for _, zp in ipairs(zones) do
                if zp:DistToSqr(pos) <= r2 and math.abs(zp.z - pos.z) < 200 then inside = true break end
            end
            -- (downed: noted once whether it happened inside a zone; only
            -- someone downed outside and brought in gets up here, so
            -- going down in a zone neither farms tickets nor skips the
            -- fight)
            local down = Med and Med.IsDown and Med.IsDown(p)
            if down and p.rhylibZoneDownIn == nil then p.rhylibZoneDownIn = inside end
            if not down then p.rhylibZoneDownIn = nil end
            if inside then
                if down and p.rhylibZoneDownIn == false and Med.Revive then
                    p.rhylibZoneDownIn = nil
                    Med.Revive(p, p:GetMaxHealth(), nil)
                    if Med.ClearInjuries then Med.ClearInjuries(p) end
                    if Med.Cure then Med.Cure(p) end
                    p:SetHealth(p:GetMaxHealth())
                    local msg = "Medic zone: you're back on your feet"
                    if S.TicketsOn() then
                        S.AddTickets(1)
                        msg = msg .. " (+1 respawn ticket, " .. S.Tickets() .. " left)"
                    end
                    Rhylib.Notify(p, msg, "good", "Spawns")
                elseif regen > 0 and p:Health() < p:GetMaxHealth() then
                    p.rhylibZoneHp = (p.rhylibZoneHp or 0) + regen
                    local add = math.floor(p.rhylibZoneHp)
                    if add >= 1 then
                        p.rhylibZoneHp = p.rhylibZoneHp - add
                        p:SetHealth(math.min(p:GetMaxHealth(), p:Health() + add))
                    end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Objective markers: the staff edit menu
--------------------------------------------------------------------------

function S.OpenObjectiveEdit(ply, ent)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    isStaff(ply, function()
        Rhylib.Net.Start("spawn.objedit")
        net.WriteEntity(ent)
        net.Send(ply)
    end)
end

Rhylib.Net.Receive("spawn.objset", function(ply)
    local ent = net.ReadEntity()
    local op = net.ReadUInt(2)
    local text = (op == 0 or op == 1) and string.sub(string.Trim(net.ReadString()), 1, 40) or nil
    if not (IsValid(ent) and ent:GetClass() == S.OBJECTIVE) then return end
    isStaff(ply, function()
        if not IsValid(ent) then return end
        if op == 0 then
            ent:SetBeaconName(text ~= "" and text or "Objective")
        elseif op == 1 then
            ent:SetBattalion(text)
        elseif op == 2 then
            ent:SetShowJammed(not ent:GetShowJammed())
        end
    end)
end, { rate = 4, burst = 4 })
