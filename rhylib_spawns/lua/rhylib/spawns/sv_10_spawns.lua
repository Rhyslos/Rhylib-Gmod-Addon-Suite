--[[
    Spawn points (server): the respawn choice while dead, putting players
    there on spawn, staff edits, event teleports, saving per map.

    Network:
      spawn.list   to a dead player: the points they may pick + their pick
      spawn.pick   client: entity index (0 = default)
      spawn.edit   to staff: open the edit menu for a point
      spawn.set    staff: point, op 3 bits (0 rename, 1 battalion, 2 event
                   on/off, 3 teleport everyone here), text for 0/1
]]

local S = Rhylib.Spawns
local Data = Rhylib.Data

Rhylib.Net.Register("spawn.list")
Rhylib.Net.Register("spawn.edit")

Rhylib.PLACEMENT_CLASSES = Rhylib.PLACEMENT_CLASSES or {}
Rhylib.PLACEMENT_CLASSES[S.POINT] = true
Rhylib.PLACEMENT_CLASSES[S.EVENT] = true

local function isStaff(ply, fn)
    Rhylib.Perms.Check(ply, "rhylib.spawns.admin", function(ok) if ok then fn() end end)
end

--------------------------------------------------------------------------
-- Respawn choice
--------------------------------------------------------------------------

S.pick = S.pick or {}   -- [ply] = chosen point (nil = default)

-- Where this player respawns: their pick if still allowed, else the default.
function S.Target(ply)
    local opts = S.Options(ply)
    local pick = S.pick[ply]
    if IsValid(pick) then
        for _, o in ipairs(opts) do
            if o.ent == pick then return pick end
        end
    end
    return opts[1] and opts[1].ent or nil
end

function S.SendList(ply)
    local opts = S.Options(ply)
    local pos = ply:GetPos()
    local target = S.Target(ply)
    Rhylib.Net.Start("spawn.list")
    net.WriteBool(true)
    local n = math.min(#opts, 40)
    net.WriteUInt(n, 6)
    for i = 1, n do
        local e = opts[i].ent
        net.WriteUInt(e:EntIndex(), 13)
        net.WriteString(e:GetBeaconName())
        net.WriteBool(opts[i].event or false)
        net.WriteUInt(math.min(math.floor(e:GetPos():Distance(pos) * 0.019), 65535), 16)   -- (metres)
    end
    net.WriteUInt(IsValid(target) and target:EntIndex() or 0, 13)
    net.Send(ply)
end

local function closeList(ply)
    Rhylib.Net.Start("spawn.list")
    net.WriteBool(false)
    net.Send(ply)
end

Rhylib.Hook.Add("PlayerDeath", "spawns.list", function(ply)
    -- (a moment later, so the death screen is up)
    timer.Simple(0.5, function()
        if IsValid(ply) and not ply:Alive() and #S.Options(ply) > 0 then S.SendList(ply) end
    end)
end)

Rhylib.Net.Receive("spawn.pick", function(ply)
    local idx = net.ReadUInt(13)
    if ply:Alive() then return end
    local e = idx > 0 and Entity(idx) or nil
    S.pick[ply] = S.IsPoint(e) and e or nil
    S.SendList(ply)   -- (shows the new pick)
end, { rate = 5, burst = 5 })

-- On spawn: onto the point (a tick later, after the gamemode placed them;
-- admin revives and jail move them again after this).
Rhylib.Hook.Add("PlayerSpawn", "spawns.place", function(ply)
    closeList(ply)
    local MP = Rhylib.MP
    if MP and MP.IsJailed and MP.IsJailed(ply) then return end
    local e = S.Target(ply)
    S.pick[ply] = nil
    if not IsValid(e) then return end
    timer.Simple(0, function()
        if not (IsValid(ply) and IsValid(e) and ply:Alive()) then return end
        ply:SetPos(e:SpawnPos())
        ply:SetEyeAngles(Angle(0, e:GetAngles().y, 0))
        local L = Rhylib.Lying
        if L and L.Unstick then L.Unstick(ply) end
    end)
end)

Rhylib.Hook.Add("PlayerDisconnected", "spawns.pick", function(ply) S.pick[ply] = nil end)

-- Points changed (event on/off, removed): the dead get a fresh list.
function S.RefreshDead()
    for _, p in ipairs(player.GetAll()) do
        if not p:Alive() then
            if #S.Options(p) > 0 then S.SendList(p) else closeList(p) end
        end
    end
end

--------------------------------------------------------------------------
-- Staff edits and event teleports
--------------------------------------------------------------------------

function S.OpenEdit(ply, ent)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    isStaff(ply, function()
        Rhylib.Net.Start("spawn.edit")
        net.WriteEntity(ent)
        net.Send(ply)
    end)
end

-- Everyone alive (not jailed) around the point, a ring at a time.
function S.TeleportAll(ent)
    local base = ent:SpawnPos()
    local MP = Rhylib.MP
    local i = 0
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and not (MP and MP.IsJailed and MP.IsJailed(p)) then
            if p:InVehicle() then p:ExitVehicle() end
            local ring = math.ceil(i / 8)
            local a = math.rad((i % 8) * 45 + ring * 20)
            local pos = base + Vector(math.cos(a), math.sin(a), 0) * 44 * ring
            local tr = util.TraceHull({ start = base + Vector(0, 0, 4), endpos = pos + Vector(0, 0, 4), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = player.GetAll() })
            p:SetPos(tr.HitPos)
            p:SetVelocity(-p:GetVelocity())
            p:SetEyeAngles(Angle(0, ent:GetAngles().y, 0))
            local L = Rhylib.Lying
            if L and L.Unstick then L.Unstick(p) end
            i = i + 1
        end
    end
    return i
end

local function setEvent(ent, on, by)
    ent:SetActive(on)
    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint(on and ("Event spawn \"" .. ent:GetBeaconName() .. "\" is open: you can respawn there") or ("Event spawn \"" .. ent:GetBeaconName() .. "\" closed"))
    end
    S.RefreshDead()
end

Rhylib.Net.Receive("spawn.set", function(ply)
    local ent = net.ReadEntity()
    local op = net.ReadUInt(3)
    local text = (op == 0 or op == 1) and string.sub(string.Trim(net.ReadString()), 1, 40) or nil
    if not S.IsPoint(ent) then return end
    isStaff(ply, function()
        if not IsValid(ent) then return end
        if op == 0 then
            ent:SetBeaconName(text ~= "" and text or (ent.Event and "Event" or "Spawn"))
        elseif op == 1 and not ent.Event then
            ent:SetBattalion(text)
        elseif op == 2 and ent.Event then
            setEvent(ent, not ent:GetActive(), ply)
            return
        elseif op == 3 then
            local n = S.TeleportAll(ent)
            ply:ChatPrint("Teleported " .. n .. " players to " .. ent:GetBeaconName())
            return
        else
            return
        end
        S.Save()
        S.RefreshDead()
    end)
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Saving per map (Data "spawns"/map); event spawns come back switched off
--------------------------------------------------------------------------

function S.Save()
    local rows = {}
    for _, class in ipairs({ S.POINT, S.EVENT }) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if (not Rhylib.Perma or Rhylib.Perma.Is(e)) then   -- (only permanent ones, 2026-10-09u)
                local p, a = e:GetPos(), e:GetAngles()
                rows[#rows + 1] = { class = class, name = e:GetBeaconName(), bn = e:GetBattalion(), pos = { p.x, p.y, p.z }, yaw = a.y }
            end
        end
    end
    Data.Set("spawns", game.GetMap(), rows)
    return #rows
end

function S.Load()
    for _, class in ipairs({ S.POINT, S.EVENT }) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    local rows = Data.Get("spawns", game.GetMap())
    if not istable(rows) then return end
    for _, row in ipairs(rows) do
        if (row.class == S.POINT or row.class == S.EVENT) and istable(row.pos) then
            local e = ents.Create(row.class)
            if IsValid(e) then
                e:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
                e:SetAngles(Angle(0, row.yaw or 0, 0))
                e:Spawn()
                e:SetBeaconName(tostring(row.name or "Spawn"))
                e:SetBattalion(tostring(row.bn or ""))
                if Rhylib.Perma then Rhylib.Perma.Mark(e, true) end
            end
        end
    end
end

if Rhylib.Perma and Rhylib.Perma.Register then Rhylib.Perma.Register({ S.POINT, S.EVENT }, S.Save) end
Rhylib.Hook.Add("InitPostEntity", "spawns.load", function() timer.Simple(1, S.Load) end)
Rhylib.Hook.Add("PostCleanupMap", "spawns.load", S.Load)
Rhylib.Hook.Add("EntityRemoved", "spawns.removed", function(ent)
    if S.IsPoint(ent) then timer.Simple(0, S.RefreshDead) end
end)

concommand.Add("rhylib_spawns_save", function(ply)
    local function reply(msg)
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
    end
    if not IsValid(ply) then
        reply("Saved " .. S.Save() .. " spawn points for " .. game.GetMap())
        return
    end
    isStaff(ply, function() reply("Saved " .. S.Save() .. " spawn points for " .. game.GetMap()) end)
end)
