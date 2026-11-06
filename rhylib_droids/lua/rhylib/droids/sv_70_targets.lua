--[[
    Event targets (server; the entity is entities/rhylib_event_target.lua).

    Nets
      droids.etedit  server -> staff: Entity, then the settings (as below):
                     E on a placed one with the toolgun out opens its window.
      droids.etset   client -> server: Entity, String name, String model,
                     Float scale, UInt 17 health, Bool explode, UInt 11
                     radius (units). Checked: rhylib.toolgun, within 600
                     units, the toolgun in hand. Applies it (full health
                     again) and saves it again when permanent. Rate 2/s.
      droids.etlost  server -> everyone: String name. "Objective lost"
                     plate (one destroyed).
    The toolgun's entry (rhylib_toolgun "event_target", field eventTarget)
    sends the same fields with tool.place for each new one.

    Saved: Placements "droids_targets" (Data "droids_targets" / <map>):
    permanent ones with their name, model, scale, health, explode and
    radius; back at full health after a map change.
    D.EventTargetLost(ent), D.OpenEventTarget(ply, ent), D.CleanTargetCfg(c).
]]

local D = Rhylib.Droids

Rhylib.Net.Register("droids.etedit")
Rhylib.Net.Register("droids.etlost")

-- D.CleanTargetCfg(c) -> c with every field in range (net or saved row).
local function num(v, def)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return def end
    return v
end
function D.CleanTargetCfg(c)
    c = istable(c) and c or {}
    local model = isstring(c.model) and string.sub(c.model, 1, 200) or D.Cfg("etModel")
    return {
        name = string.sub(tostring(c.name or D.Cfg("etName")), 1, 32),
        model = model,
        scale = math.Clamp(num(c.scale, 1), 0.5, 3),
        health = math.Clamp(math.floor(num(c.health, 800)), 1, 100000),
        explode = c.explode and true or false,
        radius = math.Clamp(math.floor(num(c.radius, 300)), 16, 2000),
    }
end

D.TargetPlaces = Rhylib.Perma.Placements("droids_targets", {
    classes = { "rhylib_event_target" },
    dataModule = "droids_targets",
    save = function(e)
        local c = e.Config and e:Config() or {}
        return { name = c.name, model = c.model, scale = c.scale, hp = c.health, ex = c.explode or nil, r = c.radius }
    end,
    load = function(e, row)
        if e.ApplyConfig then
            e:ApplyConfig(D.CleanTargetCfg({ name = row.name, model = row.model, scale = row.scale, health = row.hp, explode = row.ex, radius = row.r }), true)
        end
    end,
    command = "rhylib_eventtarget_save",
    perm = "rhylib.toolgun",
})

-- D.EventTargetLost(ent): everyone gets the "Objective lost" plate.
function D.EventTargetLost(ent)
    if not IsValid(ent) then return end
    Rhylib.Net.Start("droids.etlost")
    net.WriteString(ent:GetTargetName())
    net.Broadcast()
end

local function writeCfg(c)
    net.WriteString(c.name or "")
    net.WriteString(c.model or "")
    net.WriteFloat(c.scale or 1)
    net.WriteUInt(math.Clamp(c.health or 1, 1, 100000), 17)
    net.WriteBool(c.explode and true or false)
    net.WriteUInt(math.Clamp(c.radius or 300, 16, 2000), 11)
end

local function holdsTool(ply)
    local w = IsValid(ply) and ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

local function allowed(ply, cb)
    if Rhylib.Perms and Rhylib.Perms.Check then
        Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok) if ok then cb() end end)
    elseif ply:IsAdmin() then cb() end
end

-- D.OpenEventTarget(ply, ent): staff with the toolgun out get its window.
function D.OpenEventTarget(ply, ent)
    if not (IsValid(ply) and IsValid(ent) and holdsTool(ply)) then return end
    allowed(ply, function()
        if not (IsValid(ply) and IsValid(ent)) then return end
        Rhylib.Net.Start("droids.etedit")
        net.WriteEntity(ent)
        writeCfg(ent:Config())
        net.Send(ply)
    end)
end

Rhylib.Net.Receive("droids.etset", function(ply)
    local ent = net.ReadEntity()
    local c = { name = net.ReadString(), model = net.ReadString(), scale = net.ReadFloat(), health = net.ReadUInt(17),
        explode = net.ReadBool(), radius = net.ReadUInt(11) }
    if not (IsValid(ent) and ent:GetClass() == "rhylib_event_target" and ent.ApplyConfig and not ent.broken) then return end
    if not holdsTool(ply) or ply:GetPos():DistToSqr(ent:GetPos()) > 600 * 600 then return end
    allowed(ply, function()
        if not (IsValid(ent) and not ent.broken) then return end
        ent:ApplyConfig(D.CleanTargetCfg(c))
        if Rhylib.Perma and Rhylib.Perma.Is and Rhylib.Perma.Is(ent) and D.TargetPlaces then D.TargetPlaces:Save() end
        Rhylib.Notify(ply, "Event target set: " .. ent:GetTargetName(), "good", "Event target")
    end)
end, { rate = 2, burst = 3 })

-- Cap: placing past etMax removes the new one.
Rhylib.Hook.Add("OnEntityCreated", "droids.et.cap", function(ent)
    if not (IsValid(ent) and ent:GetClass() == "rhylib_event_target") then return end
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        local n = 0
        for t in pairs(D.eventTargets or {}) do if IsValid(t) and t ~= ent then n = n + 1 end end
        if n >= D.Cfg("etMax") and not ent.rhylibPlacement then
            local owner = ent.CPPIGetOwner and ent:CPPIGetOwner() or ent.rhylibPlacer
            if IsValid(owner) and owner:IsPlayer() then Rhylib.Notify(owner, "Event target limit reached (" .. D.Cfg("etMax") .. ").", "bad", "Event target") end
            ent:Remove()
        end
    end)
end)
