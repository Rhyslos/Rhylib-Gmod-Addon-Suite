--[[
    Toolgun (server): placing and removing, checked against the
    permission and the player's own aim.

    Messages
      tool.place   client: entry id, count 3 bits, name (named entries)
      tool.spawn   client: kind 3 bits (prop, entity, npc, vehicle, weapon),
                   name, skin 6 bits, bodygroups, NPC weapon: a spawn-window
                   thing at the aimed spot, through sandbox's own spawn code
                   (so the gamemode's spawn rules and limits apply)
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
    -- Droids: stop at the cap instead of creating ones Initialize removes.
    local D = Rhylib.Droids
    local droid = D and D.Count and (e.class == "rhylib_b1" or scripted_ents.IsBasedOn(e.class, "rhylib_b1"))
    for i = 1, count do
        if droid and D.Count() >= D.Cfg("maxActive") then
            if made == 0 then ply:ChatPrint("Droid limit reached (" .. D.Cfg("maxActive") .. ").") end
            break
        end
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

-- Spawning spawn-window things (sandbox gamemodes, DarkRP included).
local function markSpawned(ent)
    if not IsValid(ent) then return end
    ent.rhylibToolSpawned = true
    ent:SetNW2Bool("rhylib_toolSpawned", true)
end

-- (sandbox's Spawn_* functions don't all return the entity: catch it here)
for _, h in ipairs({ "PlayerSpawnedSENT", "PlayerSpawnedNPC", "PlayerSpawnedVehicle", "PlayerSpawnedSWEP" }) do
    Rhylib.Hook.Add(h, "toolgun.mark", function(ply, ent)
        if IsValid(ply) and ply.rhylibToolSpawning then markSpawned(ent) end
    end)
end

-- A model the way sandbox's gm_spawn does it (prop, ragdoll or effect),
-- but at the toolgun's spot.
local function spawnProp(ply, model, skin, body, tr)
    model = string.lower((string.gsub(model, "\\", "/")))
    if string.find(model, "%.[/\\]") then return end   -- (no ../ paths, as sandbox)
    if not util.IsValidModel(model) then return ply:ChatPrint("Not a model: " .. model) end
    local class, can, done, kind, clean
    if util.IsValidProp(model) then
        class, can, done, kind, clean = "prop_physics", "PlayerSpawnProp", "PlayerSpawnedProp", "Prop", "props"
    elseif util.IsValidRagdoll(model) then
        class, can, done, kind, clean = "prop_ragdoll", "PlayerSpawnRagdoll", "PlayerSpawnedRagdoll", "Ragdoll", "ragdolls"
    else
        class, can, done, kind, clean = "prop_effect", "PlayerSpawnEffect", "PlayerSpawnedEffect", "Effect", "effects"
    end
    -- (the same checks as sandbox's gm_spawn: prop protection, limits)
    if not hook.Run("PlayerSpawnObject", ply, model, skin) or not hook.Run(can, ply, model) then return end
    local ent = ents.Create(class)
    if not IsValid(ent) then return end
    ent:SetModel(model)
    ent:SetSkin(skin)
    ent:SetPos(tr.HitPos)
    -- (ragdolls lie down, as sandbox spawns them)
    ent:SetAngles(Angle(class == "prop_ragdoll" and -90 or 0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:Activate()
    if body ~= "" then
        ent:SetBodyGroups(body)
        if IsValid(ent.AttachedEntity) then ent.AttachedEntity:SetBodyGroups(body) end
    end
    -- Flush on the surface (as sandbox does; a ragdoll moves every part).
    local p = ent:NearestPoint(tr.HitPos - tr.HitNormal * 512)
    local off = tr.HitPos - p
    if class == "prop_ragdoll" then
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local ph = ent:GetPhysicsObjectNum(i)
            if IsValid(ph) then ph:SetPos(ph:GetPos() + off) end
        end
    else
        ent:SetPos(ent:GetPos() + off)
    end
    hook.Run(done, ply, model, ent)
    undo.Create(kind)
    undo.AddEntity(ent)
    undo.SetPlayer(ply)
    undo.Finish("Spawned " .. kind .. " (" .. model .. ")")
    ply:AddCleanup(clean, ent)
    markSpawned(ent)
    return ent
end

local KIND_NAMES = { "prop", "entity", "npc", "vehicle", "weapon" }

local function spawnThing(ply, kind, name, skin, body, wep)
    local tr = aim(ply)
    if not tr.Hit or tr.HitSky then return end
    if kind == 1 then
        if spawnProp(ply, name, skin, body, tr) then ply:EmitSound("buttons/button14.wav", 60, 110) end
        return
    end
    local fn = ({ Spawn_SENT, Spawn_NPC, Spawn_Vehicle, Spawn_Weapon })[kind - 1]
    if not isfunction(fn) then
        return ply:ChatPrint("This gamemode has no sandbox spawning for " .. (KIND_NAMES[kind] or "that"))
    end
    -- (only things the spawn menu lists)
    local lists = { "SpawnableEntities", "NPC", "Vehicles", "Weapon" }
    local entry = list.Get(lists[kind - 1])[name]
    if not entry or (kind == 5 and not entry.Spawnable) then return end
    ply.rhylibToolSpawning = true
    local ok, err
    if kind == 3 then
        ok, err = pcall(fn, ply, name, wep ~= "" and wep or nil, tr)
    else
        ok, err = pcall(fn, ply, name, tr)
    end
    ply.rhylibToolSpawning = nil
    if not ok then
        Rhylib.Warn("toolgun", "spawning %s failed: %s", name, tostring(err))
        return
    end
    ply:EmitSound("buttons/button14.wav", 60, 110)
end

Rhylib.Net.Receive("tool.spawn", function(ply)
    local kind = net.ReadUInt(3)
    local name = string.sub(net.ReadString(), 1, 260)
    local skin = net.ReadUInt(6)
    local body = string.sub(net.ReadString(), 1, 64)
    local wep = string.sub(net.ReadString(), 1, 64)
    if kind < 1 or kind > 5 or name == "" then return end
    allowed(ply, function() spawnThing(ply, kind, name, skin, body, wep) end)
end, { rate = 5, burst = 8 })

-- Rhylib things and what the toolgun spawned (never players or map entities).
local function removable(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() or ent:CreatedByMap() then return nil end
    if ent.rhylibToolSpawned then return { class = ent:GetClass() } end
    local par = ent:GetParent()
    if IsValid(par) and par.rhylibToolSpawned then return { class = par:GetClass(), ent = par } end
    if ent.IsRhylibDroid or ent:GetClass() == "rhylib_b2_rocket" then return { class = ent:GetClass() } end
    return Tool.ByClass(ent:GetClass())
end

Rhylib.Net.Receive("tool.remove", function(ply)
    allowed(ply, function()
        local ent = aim(ply).Entity
        local e = removable(ent)
        if not e then return end
        if IsValid(e.ent) then e.ent:Remove() else ent:Remove() end
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
