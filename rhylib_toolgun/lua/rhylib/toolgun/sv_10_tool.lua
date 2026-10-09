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
      tool.perma   client: bool: the Permanent tool on the aimed thing (on / off)
      tool.save    client: save every permanent thing again now

    Placing no longer saves anything (owner 2026-10-09u): staff make a thing
    permanent with the Permanent tool (rhylib_core sh_62_perma.lua).
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

-- The Permanent tool: make the aimed thing permanent (or save its new
-- spot), or stop keeping it (rhylib_core Rhylib.Perma).
local function perma(ply, on)
    local P = Rhylib.Perma
    if not (P and P.Set) then return end
    local ent = Tool.PermaTarget(ply)
    if not IsValid(ent) then return ply:ChatPrint("[Permanent] Aim at something") end
    local ok, msg = P.Set(ent, on)
    ply:ChatPrint("[Permanent] " .. msg)
    ply:EmitSound(ok and "buttons/button14.wav" or "buttons/button10.wav", 60, ok and (on and 120 or 90) or 100)
end

Rhylib.Net.Register("tool.perma")
Rhylib.Net.Receive("tool.perma", function(ply)
    local on = net.ReadBool()
    allowed(ply, function() perma(ply, on) end)
end, { rate = 10, burst = 10 })

local function place(ply, e, count, name, mode)
    if e.perma then return perma(ply, true) end
    local tr = aim(ply)
    if not tr.Hit or tr.HitSky then return end
    local D = Rhylib.Droids
    -- An order brush: droids near the spot get the mode.
    if e.order then
        if not (D and D.PaintMode) then return end
        local n = D.PaintMode(tr.HitPos, e.order, e.side)
        local what = e.side == 1 and "clone" or "droid"
        ply:ChatPrint(string.format("[%s] %d %s%s: %s", e.side == 1 and "Clones" or "Droids", n, what, n == 1 and "" or "s", D.MODE_NAMES[e.order] or e.order))
        ply:EmitSound("buttons/button14.wav", 60, n > 0 and 120 or 80)
        return
    end
    -- Preset squad (rhylib_droids D.SpawnPreset): a grid facing you, front row where you aim.
    if e.preset then
        if not (D and D.SpawnPreset) then return end
        local list, want = D.SpawnPreset(e.preset, tr.HitPos, (ply:GetPos() - tr.HitPos):Angle().y, mode)
        if #list > 0 then
            undo.Create(e.name)
            for _, ent in ipairs(list) do
                ent.rhylibToolPlaced = true
                if ent.CPPISetOwner then ent:CPPISetOwner(ply) end
                undo.AddEntity(ent)
            end
            undo.SetPlayer(ply)
            undo.Finish()
            ply:EmitSound("buttons/button14.wav", 60, 110)
        end
        if #list < want then ply:ChatPrint(string.format("Placed %d of %d (limit reached or no room).", #list, want)) end
        return
    end
    -- Follow tool: LMB picks clones (one you aim at, else all near the spot).
    if e.follow then
        if not (D and D.ToggleFollowPick) then return end
        local n = D.ToggleFollowPick(ply, tr)
        ply:ChatPrint(string.format("[Clones] %d picked. RMB: they follow you, or the player you aim at.", n))
        ply:EmitSound("buttons/button14.wav", 60, 120)
        return
    end
    local yaw = (ply:GetPos() - tr.HitPos):Angle().y   -- facing you
    local made = 0
    -- Droids and clones: stop at the cap instead of creating ones Initialize removes.
    local droid = D and D.Count and (e.class == "rhylib_b1" or scripted_ents.IsBasedOn(e.class, "rhylib_b1"))
    local clone = droid and D.CloneCount and (e.class == "rhylib_clone" or scripted_ents.IsBasedOn(e.class, "rhylib_clone"))
    for i = 1, count do
        if clone and D.CloneCount() >= D.Cfg("cloneMax") then
            if made == 0 then ply:ChatPrint("Clone limit reached (" .. D.Cfg("cloneMax") .. ").") end
            break
        elseif droid and not clone and D.Count() >= D.Cfg("maxActive") then
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
            if e.marker then ent.MarkerKind, ent.MarkerSide = e.marker, e.side end
            ent:Spawn()
            ent:Activate()
            -- Sit on the surface: lift by how far the model reaches below its origin.
            if IsValid(ent) and not ent:IsNextBot() then
                local mins = ent:OBBMins()
                if mins.z < 0 then ent:SetPos(ent:GetPos() - Vector(0, 0, mins.z)) end
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:EnableMotion(false) end
            end
            -- (droids: the picked mode, then the latest markers)
            if IsValid(ent) and droid and D.ToolPlaced then D.ToolPlaced(ent, mode) end
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
        ply:EmitSound("buttons/button14.wav", 60, 110)
    end
end

Rhylib.Net.Receive("tool.place", function(ply)
    local id = string.sub(net.ReadString(), 1, 32)
    local count = math.Clamp(net.ReadUInt(3), 1, 5)
    local name = string.sub(net.ReadString(), 1, 32)
    local mode = ({ "guard", "patrol", "attack" })[net.ReadUInt(2)] or "guard"
    local e = Tool.ById(id)
    if not e then return end
    if not e.count then count = 1 end
    allowed(ply, function() place(ply, e, count, name, mode) end)
end, { rate = 20, burst = 20 })   -- (owner: as fast as you click)

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
end, { rate = 20, burst = 20 })

-- Rhylib things and what the toolgun spawned (never players or map entities).
local function removable(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() or ent:CreatedByMap() then return nil end
    if ent.rhylibToolSpawned then return { class = ent:GetClass() } end
    local par = ent:GetParent()
    if IsValid(par) and par.rhylibToolSpawned then return { class = par:GetClass(), ent = par } end
    if ent.IsRhylibDroid or ent.IsRhylibClone or ent:GetClass() == "rhylib_b2_rocket" then return { class = ent:GetClass() } end
    return Tool.ByClass(ent:GetClass())
end

Rhylib.Net.Receive("tool.remove", function(ply)
    allowed(ply, function()
        local tr = aim(ply)
        local ent = tr.Entity
        local e = removable(ent)
        -- Droid markers aren't solid: the nearest one to where you aim.
        if not e and tr.Hit then
            local best, bestD = nil, 80 * 80
            for _, m in ipairs(ents.FindByClass("rhylib_droid_marker")) do
                local d = m:GetPos():DistToSqr(tr.HitPos)
                if d < bestD then best, bestD = m, d end
            end
            if best then ent, e = best, { class = best:GetClass() } end
        end
        if not e then return end
        -- (a permanent thing is saved again without it)
        local P = Rhylib.Perma
        local victim = IsValid(e.ent) and e.ent or ent
        if P and P.Forget then P.Forget(victim) else victim:Remove() end
        ply:EmitSound("buttons/button15.wav", 60, 100)
    end)
end, { rate = 20, burst = 20 })

-- Follow tool RMB: the picked clones follow the player aimed at, else you.
Rhylib.Net.Register("tool.follow")
Rhylib.Net.Receive("tool.follow", function(ply)
    allowed(ply, function()
        local D = Rhylib.Droids
        if not (D and D.AssignFollow) then return end
        local tr = aim(ply)
        local target = IsValid(tr.Entity) and tr.Entity:IsPlayer() and tr.Entity or ply
        local L = Rhylib.Lying
        if IsValid(tr.Entity) and L and L.Owner and IsValid(L.Owner(tr.Entity)) then target = L.Owner(tr.Entity) end
        local n = D.AssignFollow(ply, target)
        ply:ChatPrint(n > 0 and string.format("[Clones] %d now follow %s.", n, target == ply and "you" or target:Nick())
            or "[Clones] Pick clones first (LMB).")
        ply:EmitSound("buttons/button14.wav", 60, n > 0 and 110 or 80)
    end)
end, { rate = 10, burst = 10 })

Rhylib.Net.Receive("tool.save", function(ply)
    allowed(ply, function()
        -- Every permanent thing again (positions may have moved).
        local P = Rhylib.Perma
        if not P then return end
        local seen = {}
        for class, fn in pairs(P.savers) do
            if not seen[fn] then seen[fn] = true P.Save(class) end
        end
        P.Save("")   -- (the plain list)
        ply:ChatPrint("Saving every permanent thing on " .. game.GetMap())
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

-- !keeptoolgun: gives you one if you don't have it, and you get it again
-- after every respawn (saved per player; say it again to stop).
local function keepKey(ply) return "keep_" .. ply:SteamID64() end

function Tool.KeepsToolgun(ply)
    if ply.rhylibKeepTool == nil then
        ply.rhylibKeepTool = not ply:IsBot() and Rhylib.Data.Get("toolgun", keepKey(ply)) == true or false
    end
    return ply.rhylibKeepTool
end

local function keepToolgun(ply)
    if not IsValid(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        if not ok then return ply:ChatPrint("You don't have permission for the toolgun") end
        local on = not Tool.KeepsToolgun(ply)
        ply.rhylibKeepTool = on
        if on then
            Rhylib.Data.Set("toolgun", keepKey(ply), true)
            if ply:Alive() and not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
            ply:ChatPrint("[Toolgun] You'll keep the toolgun after dying. Say !keeptoolgun again to stop.")
        else
            Rhylib.Data.Delete("toolgun", keepKey(ply))
            ply:ChatPrint("[Toolgun] You won't get the toolgun back after dying any more.")
        end
    end)
end

-- After the inventory hands weapons back and stows them (timer 0 / 0.1).
Rhylib.Hook.Add("PlayerSpawn", "toolgun.keep", function(ply)
    if ply:IsBot() or not Tool.KeepsToolgun(ply) then return end
    timer.Simple(0.5, function()
        if not (IsValid(ply) and ply:Alive()) or ply:HasWeapon(CLASS) then return end
        Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
            if ok and IsValid(ply) and ply:Alive() and not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
        end)
    end)
end)

Rhylib.Hook.Add("PlayerSay", "toolgun.chat", function(ply, text)
    local t = string.lower(string.Trim(text or ""))
    if t == "!toolgun" or t == "/toolgun" then
        give(ply)
        return ""
    end
    if t == "!keeptoolgun" or t == "/keeptoolgun" then
        keepToolgun(ply)
        return ""
    end
end, -50)
