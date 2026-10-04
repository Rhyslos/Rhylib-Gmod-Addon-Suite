--[[
    Toolgun (server): placing and removing, checked against the
    permission and the player's own aim.

    Messages
      tool.place   client: entry id, count 3 bits, name (named entries)
      tool.remove  client
      tool.save    client: run every placement save now
]]

local Tool = Rhylib.Tool
local CLASS = "rhylib_toolgun"

local function holding(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == CLASS
end

-- Runs fn(ply) if they may use the toolgun and are holding it.
local function allowed(ply, fn)
    if not holding(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if ok and IsValid(ply) then fn() end
    end)
end

local function aim(ply)
    local start = ply:GetShootPos()
    return util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * Tool.RANGE, filter = ply, mask = MASK_SOLID })
end

-- Saves run once, a moment after the last change (one per command).
local pendingSaves = {}
local function queueSave(cmd)
    if not cmd then return end
    pendingSaves[cmd] = true
    timer.Create("Rhylib.Tool.Save", 0.5, 1, function()
        for c in pairs(pendingSaves) do game.ConsoleCommand(c .. "\n") end
        pendingSaves = {}
    end)
end

local function place(ply, e, count, name)
    local tr = aim(ply)
    if not tr.Hit or tr.HitSky then return end
    local yaw = (ply:GetPos() - tr.HitPos):Angle().y   -- facing you
    local made = 0
    for i = 1, count do
        local pos = tr.HitPos
        if count > 1 then
            -- A small ring around the spot.
            local a = (i / count) * math.pi * 2
            local r = 45 + count * 6
            pos = pos + Vector(math.cos(a) * r, math.sin(a) * r, 0)
            local down = util.TraceLine({ start = pos + Vector(0, 0, 40), endpos = pos - Vector(0, 0, 120), mask = MASK_SOLID })
            if down.Hit then pos = down.HitPos end
        end
        local ent = ents.Create(e.class)
        if IsValid(ent) then
            ent:SetPos(pos + tr.HitNormal * 2)
            ent:SetAngles(Angle(0, yaw, 0))
            if e.named and ent.SetBeaconName then ent:SetBeaconName(name ~= "" and name or "Beacon") end
            ent:Spawn()
            ent:Activate()
            -- Sit on the surface: lift by how far the model reaches below its origin.
            if IsValid(ent) and not ent:IsNextBot() then
                local mins = ent:OBBMins()
                if mins.z < 0 then ent:SetPos(ent:GetPos() - Vector(0, 0, mins.z)) end
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:EnableMotion(false) end
            end
            if IsValid(ent) then
                ent.rhylibToolPlaced = true
                if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
                undo.Create(e.name)
                undo.AddEntity(ent)
                undo.SetPlayer(ply)
                undo.Finish()
                made = made + 1
            end
        end
    end
    if made > 0 then
        queueSave(e.save)
        ply:EmitSound("buttons/button14.wav", 60, 110)
    end
end

Rhylib.Net.Receive("tool.place", function(ply)
    local id = string.sub(net.ReadString(), 1, 32)
    local count = math.Clamp(net.ReadUInt(3), 1, 5)
    local name = string.sub(net.ReadString(), 1, 32)
    local e = Tool.ById(id)
    if not e then return end
    if not e.count then count = 1 end
    allowed(ply, function() place(ply, e, count, name) end)
end, { rate = 4, burst = 6 })

-- Rhylib things only (never players or map entities).
local function removable(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() or ent:CreatedByMap() then return nil end
    if ent.IsRhylibDroid or ent:GetClass() == "rhylib_b2_rocket" then return { class = ent:GetClass() } end
    return Tool.ByClass(ent:GetClass())
end

Rhylib.Net.Receive("tool.remove", function(ply)
    allowed(ply, function()
        local ent = aim(ply).Entity
        local e = removable(ent)
        if not e then return end
        ent:Remove()
        queueSave(e.save)
        ply:EmitSound("buttons/button15.wav", 60, 100)
    end)
end, { rate = 4, burst = 6 })

Rhylib.Net.Receive("tool.save", function(ply)
    allowed(ply, function()
        local seen = {}
        for _, e in ipairs(Tool.Entries()) do
            if e.save and not seen[e.save] then
                seen[e.save] = true
                queueSave(e.save)
            end
        end
        ply:ChatPrint("Saving every placement on " .. game.GetMap())
    end)
end, { rate = 1, burst = 2 })

-- Getting one: console rhylib_toolgun (the client's command sends
-- tool.give), chat !toolgun or /toolgun, or the spawn menu (Weapons > Rhylib).
local function give(ply)
    if not IsValid(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        if not ok then return ply:ChatPrint("You don't have permission for the toolgun") end
        if not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
        ply:SelectWeapon(CLASS)
    end)
end
Tool.Give = give

Rhylib.Net.Receive("tool.give", give, { rate = 1, burst = 2 })

Rhylib.Hook.Add("PlayerSay", "toolgun.chat", function(ply, text)
    local t = string.lower(string.Trim(text or ""))
    if t == "!toolgun" or t == "/toolgun" then
        give(ply)
        return ""
    end
end, -50)
