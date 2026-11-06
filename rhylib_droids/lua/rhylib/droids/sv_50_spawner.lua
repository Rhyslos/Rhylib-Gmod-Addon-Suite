--[[
    Droid and clone spawner settings (server; the entities are
    entities/rhylib_droid_spawner.lua and rhylib_clone_spawner.lua).

    D.Spawner.Open(ply, spawner): an admin (permission rhylib.toolgun)
    pressed E on it: net droids.spawner (server -> that admin): Entity,
    String preset, UInt 10 total, UInt 7 alive cap, UInt 10 interval
    seconds, UInt 3 mode (1 patrol, 2 roam, 3 attack, 4 guard), Bool
    running, UInt 4 preset count, then that many Strings (the presets of
    its side: droid ones, or for a clone spawner the clone ones).

    Net droids.spawnerset (client -> server, the window's Apply): the same
    fields without the preset list. Checked: permission, a valid spawner
    within 600 units, a preset of its side, total 1-1000, cap 1-100, interval
    5-600, a known mode. Rate 2/s.
]]

local D = Rhylib.Droids
D.Spawner = D.Spawner or {}
local SP = D.Spawner

SP.MODES = { "patrol", "roam", "attack", "guard" }
local MODE_IDX = { patrol = 1, roam = 2, attack = 3, guard = 4 }

Rhylib.Net.Register("droids.spawner")

-- The presets a spawner may send, sorted.
local function presets(ent)
    local out = {}
    for name, pr in pairs(D.PRESETS or {}) do
        if ent:PresetOk(pr) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

local function perm(ply, cb)
    if Rhylib.Perms and Rhylib.Perms.Check then
        Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok) if ok then cb() end end)
    elseif ply:IsAdmin() then
        cb()
    end
end

function SP.Open(ply, ent)
    if not (IsValid(ply) and IsValid(ent) and ent.cfg) then return end
    perm(ply, function()
        if not (IsValid(ply) and IsValid(ent)) then return end
        local c = ent.cfg
        Rhylib.Net.Start("droids.spawner")
        net.WriteEntity(ent)
        net.WriteString(c.preset)
        net.WriteUInt(math.Clamp(c.total, 0, 1023), 10)
        net.WriteUInt(math.Clamp(c.cap, 0, 127), 7)
        net.WriteUInt(math.Clamp(c.interval, 0, 1023), 10)
        net.WriteUInt(MODE_IDX[c.mode] or 1, 3)
        net.WriteBool(ent:GetRunning())
        local list = presets(ent)
        net.WriteUInt(math.min(#list, 15), 4)
        for i = 1, math.min(#list, 15) do net.WriteString(list[i]) end
        net.Send(ply)
    end)
end

Rhylib.Net.Receive("droids.spawnerset", function(ply)
    local ent = net.ReadEntity()
    local preset = net.ReadString()
    local total, cap, interval = net.ReadUInt(10), net.ReadUInt(7), net.ReadUInt(10)
    local mode = SP.MODES[net.ReadUInt(3)]
    local running = net.ReadBool()
    if not (IsValid(ent) and (ent:GetClass() == "rhylib_droid_spawner" or ent:GetClass() == "rhylib_clone_spawner") and ent.ApplyConfig) then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > 600 * 600 then return end
    local pr = D.PRESETS and D.PRESETS[preset]
    if not ent:PresetOk(pr) or not mode then return end
    if total < 1 or total > 1000 or cap < 1 or cap > 100 or interval < 5 or interval > 600 then return end
    perm(ply, function()
        if not IsValid(ent) then return end
        ent:ApplyConfig({ preset = preset, total = total, cap = cap, interval = interval, mode = mode }, running)
        Rhylib.Notify(ply, string.format("Spawner: %s, %d in all, %d alive at most, every %d s, %s%s", preset, total, cap, interval, mode,
            running and "" or " (stopped)"), "good", "Droids")
    end)
end, { rate = 2, burst = 2 })
