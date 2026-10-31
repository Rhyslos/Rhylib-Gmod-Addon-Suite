--[[
    Toolgun (server): placing and removing, checked against the
    permission and the player's own aim.

    Messages (all client -> server; the server traces the player's own aim)
      tool.place   String entry id, UInt 3 count (1-5), String name (named
                   entries, else ""), UInt 3 droid mode (1 guard, 2 patrol,
                   3 attack, 4 roam, 5 assault: to the side's assault point,
                   rhylib_droids D.assault), UInt 3 aggression for new squads (0 =
                   the global level, 1-5), Float turn (degrees added to
                   the facing, from the placement preview); rate 20/s. Several NPCs at
                   once become squads (rhylib_droids): count placements
                   D.MakeSquads, a preset one D.MakeSquad that keeps its
                   placed block (box); not in roam mode.
      tool.spawn   UInt 3 kind (1 prop, 2 entity, 3 npc, 4 vehicle, 5 weapon),
                   String name, UInt 6 skin, String bodygroups, String NPC
                   weapon, Float turn (degrees, the preview's, cl_40_ghost): a spawn-window thing at the aimed spot, through
                   sandbox's own spawn code (so the gamemode's spawn rules
                   and limits apply); full access only; rate 20/s
      tool.remove  empty; rate 20/s
      tool.perma   Bool: the Permanent tool on the aimed thing (on / off); rate 10/s
      tool.follow  empty: clone follow tool RMB; rate 10/s
      tool.save    empty: save every permanent thing again now; rate 1/s
      tool.give    empty: give me a toolgun (console rhylib_toolgun); rate 1/s
      tool.mode    UInt 2: 0 placing, 1 physgun mode (full access only);
                   rate 6/s (sv_20_grab.lua)
      tool.grabdist Int 4: mouse wheel steps while holding something in
                   physgun mode; rate 40/s (sv_20_grab.lua)
    Every message needs the toolgun in hand (except tool.give) and the
    permission (rhylib.toolgun, or the entry's own perm).

    Saved: Data "toolgun"/"keep_<SteamID64>" = true for !keeptoolgun.
    Chat: !toolgun or /toolgun, !keeptoolgun or /keeptoolgun.

    Physgun mode is built into the toolgun (sv_20_grab.lua): the toolgun
    keeps its own model and the beam comes out of it.

    Placing no longer saves anything: staff make a thing
    permanent with the Permanent tool (rhylib_core sh_62_perma.lua).
]]

local Tool = Rhylib.Tool

-- A notice to a player (core Rhylib.Notify), tagged [Rhy's Toolgun] unless
-- another tag is given.
local function note(ply, text, kind, tag)
    if IsValid(ply) then Rhylib.Notify(ply, text, kind or "info", tag or "Toolgun") end
end
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

-- Full access (rhylib.toolgun), or one of the entries' own permissions
-- (perm field): cb(true) for the first that passes.
local function anyAccess(ply, cb)
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if ok then return cb(true) end
        local perms = Tool.EntryPerms()
        local function try(i)
            if not IsValid(ply) then return end
            local p = perms[i]
            if not p then return cb(false) end
            Rhylib.Perms.Check(ply, p, function(ok2) if ok2 then cb(true) else try(i + 1) end end)
        end
        try(1)
    end)
end
-- Tool.AnyAccess(ply, cb(ok)): cb(true) if they have rhylib.toolgun or any
-- entry's perm (enough to hold the toolgun).
Tool.AnyAccess = anyAccess

-- Runs fn(full) if they may use this entry (full access, or the entry's perm).
local function allowedEntry(ply, e, fn)
    if not holding(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        if ok then return fn(true) end
        if e and e.perm then
            Rhylib.Perms.Check(ply, e.perm, function(ok2) if ok2 and IsValid(ply) then fn(false) end end)
        end
    end)
end

-- Mines are small and half buried: the nearest one to where you aim.
local function nearestMine(pos)
    local best, bestD = nil, 32 * 32
    for _, m in ipairs(ents.FindInSphere(pos, 32)) do
        if m.IsRhylibMine then
            local d = m:GetPos():DistToSqr(pos)
            if d < bestD then best, bestD = m, d end
        end
    end
    return best
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
    if not IsValid(ent) then return note(ply, "Aim at something", "bad", "Permanent") end
    local ok, msg = P.Set(ent, on)
    note(ply, msg, ok and "good" or "bad", "Permanent")
    ply:EmitSound(ok and "buttons/button14.wav" or "buttons/button10.wav", 60, ok and (on and 120 or 90) or 100)
end

Rhylib.Net.Register("tool.perma")
Rhylib.Net.Receive("tool.perma", function(ply)
    local on = net.ReadBool()
    allowed(ply, function() perma(ply, on) end)
end, { rate = 10, burst = 10 })

-- LMB with an entry: orders, presets, follow pick, own place functions,
-- or ents.Create of the entry's class (count of them in a ring), each
-- with an undo entry. Droids and clones stop at their caps.
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
        note(ply, string.format("%d %s%s: %s", n, what, n == 1 and "" or "s", D.MODE_NAMES[e.order] or e.order), "info", e.side == 1 and "Clones" or "Droids")
        ply:EmitSound("buttons/button14.wav", 60, n > 0 and 120 or 80)
        return
    end
    -- Preset squad (rhylib_droids D.SpawnPreset): a grid facing you, front row where you aim.
    if e.preset then
        if not (D and D.SpawnPreset) then return end
        local pyaw = (ply:GetPos() - tr.HitPos):Angle().y + (ply.rhylibToolRot or 0)
        local list, want = D.SpawnPreset(e.preset, tr.HitPos, pyaw, mode)
        -- (squads of squadSize, facing the way they were placed)
        -- (one squad that keeps the block it was placed in: box formation)
        if D.MakeSquad and #list > 1 and mode ~= "roam" then D.MakeSquad(list, { face = pyaw, aggro = Tool.PlaceAggro(ply), formation = "box", keep = true }) end
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
        if #list < want then note(ply, string.format("Placed %d of %d (limit reached or no room).", #list, want), "bad") end
        return
    end
    -- Follow tool: LMB picks clones (one you aim at, else all near the spot).
    if e.follow then
        if not (D and D.ToggleFollowPick) then return end
        local n = D.ToggleFollowPick(ply, tr)
        note(ply, string.format("%d picked. RMB: they follow you, or the player you aim at.", n), "info", "Clones")
        ply:EmitSound("buttons/button14.wav", 60, 120)
        return
    end
    local yaw = (ply:GetPos() - tr.HitPos):Angle().y + (ply.rhylibToolRot or 0)   -- facing you, turned as the preview
    -- Entries with their own placing (rhylib_eod minefields): e.place(ply, tr, count, yaw) -> list of entities.
    if e.place then
        local list = e.place(ply, tr, count, yaw) or {}
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
        return
    end
    local made = 0
    local placedNpcs = {}
    -- Droids and clones: stop at the cap instead of creating ones Initialize removes.
    local droid = D and D.Count and (e.class == "rhylib_b1" or scripted_ents.IsBasedOn(e.class, "rhylib_b1"))
    local clone = droid and D.CloneCount and (e.class == "rhylib_clone" or scripted_ents.IsBasedOn(e.class, "rhylib_clone"))
    for i = 1, count do
        if clone and D.CloneCount() >= D.Cfg("cloneMax") then
            if made == 0 then note(ply, "Clone limit reached (" .. D.Cfg("cloneMax") .. ").", "bad") end
            break
        elseif droid and not clone and D.Count() >= D.Cfg("maxActive") then
            if made == 0 then note(ply, "Droid limit reached (" .. D.Cfg("maxActive") .. ").", "bad") end
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
            if IsValid(ent) and droid then placedNpcs[#placedNpcs + 1] = ent end
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
    -- Several NPCs at once: a squad (roam keeps its pairs).
    if #placedNpcs > 1 and mode ~= "roam" and D and D.MakeSquads then
        D.MakeSquads(placedNpcs, { face = yaw, aggro = Tool.PlaceAggro(ply) })
    end
end

-- Tool.PlaceAggro(ply) -> the aggression the GM picked for new squads
-- (1-5), or nil = the global level. From tool.place.
function Tool.PlaceAggro(ply)
    return ply.rhylibPlaceAggro
end

-- The preview's turn (degrees) from the client: a real number, 0-360.
local function turn(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
    return v % 360
end

Rhylib.Net.Receive("tool.place", function(ply)
    local id = string.sub(net.ReadString(), 1, 32)
    local count = math.Clamp(net.ReadUInt(3), 1, 5)
    local name = string.sub(net.ReadString(), 1, 32)
    local mode = ({ "guard", "patrol", "attack", "roam", "assault" })[net.ReadUInt(3)] or "guard"
    local aggro = net.ReadUInt(3)
    ply.rhylibPlaceAggro = (aggro >= 1 and aggro <= 5) and aggro or nil
    ply.rhylibToolRot = turn(net.ReadFloat())
    local e = Tool.ById(id)
    if not e then return end
    if not e.count then count = 1 end
    allowedEntry(ply, e, function() place(ply, e, count, name, mode) end)
end, { rate = 20, burst = 20 })   -- (as fast as you click)

-- Spawning spawn-window things (sandbox gamemodes, DarkRP included).
local function markSpawned(ent)
    if not IsValid(ent) then return end
    ent.rhylibToolSpawned = true
    ent:SetNW2Bool("rhylib_toolSpawned", true)
end

-- (sandbox's Spawn_* functions don't all return the entity: catch it here)
for _, h in ipairs({ "PlayerSpawnedSENT", "PlayerSpawnedNPC", "PlayerSpawnedVehicle", "PlayerSpawnedSWEP" }) do
    Rhylib.Hook.Add(h, "toolgun.mark", function(ply, ent)
        if IsValid(ply) and ply.rhylibToolSpawning then
            markSpawned(ent)
            -- (turned as the preview showed: facing you, plus the turn)
            if IsValid(ent) and h ~= "PlayerSpawnedSWEP" then
                local a = ent:GetAngles()
                ent:SetAngles(Angle(a.p, ply:EyeAngles().y + 180 + (ply.rhylibToolRot or 0), a.r))
            end
        end
    end)
end

-- A model the way sandbox's gm_spawn does it (prop, ragdoll or effect),
-- but at the toolgun's spot.
local function spawnProp(ply, model, skin, body, tr)
    model = string.lower((string.gsub(model, "\\", "/")))
    if string.find(model, "%.[/\\]") then return end   -- (no ../ paths, as sandbox)
    if not util.IsValidModel(model) then return note(ply, "Not a model: " .. model, "bad") end
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
    ent:SetAngles(Angle(class == "prop_ragdoll" and -90 or 0, ply:EyeAngles().y + 180 + (ply.rhylibToolRot or 0), 0))
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
        return note(ply, "This gamemode has no sandbox spawning for " .. (KIND_NAMES[kind] or "that"), "bad")
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
    ply.rhylibToolRot = turn(net.ReadFloat())
    if kind < 1 or kind > 5 or name == "" then return end
    allowed(ply, function() spawnThing(ply, kind, name, skin, body, wep) end)
end, { rate = 20, burst = 20 })

-- Rhylib things and what the toolgun spawned (never players or map entities).
-- Returns a table with .class (and .ent when the parent is the one to
-- remove), or nil.
local function removable(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() or ent:CreatedByMap() then return nil end
    if ent.rhylibToolSpawned then return { class = ent:GetClass() } end
    local par = ent:GetParent()
    if IsValid(par) and par.rhylibToolSpawned then return { class = par:GetClass(), ent = par } end
    if ent.IsRhylibDroid or ent.IsRhylibClone or ent:GetClass() == "rhylib_b2_rocket" then return { class = ent:GetClass() } end
    -- Grapple ropes and ziplines (staff with the full toolgun only: no entry);
    -- a zipline's far end stands for its line.
    local cls = ent:GetClass()
    if cls == "rhylib_rope" or cls == "rhylib_zipline" then return { class = cls } end
    if cls == "rhylib_zipline_end" and IsValid(ent.zip) then return { class = "rhylib_zipline", ent = ent.zip } end
    return Tool.ByClass(cls)
end

Rhylib.Net.Receive("tool.remove", function(ply)
    if not holding(ply) then return end
    -- (limited access: only things of the entries they may place)
    local tr0 = aim(ply)
    local pre = removable(tr0.Entity) or (tr0.Hit and removable(nearestMine(tr0.HitPos)))
    allowedEntry(ply, pre and Tool.ByClass(pre.class) or nil, function(full)
        local tr = aim(ply)
        local ent = tr.Entity
        local e = removable(ent)
        if not e and tr.Hit then
            local m = nearestMine(tr.HitPos)
            if m then ent, e = m, removable(m) end
        end
        -- (gamemasters can't undo the permanent map setup)
        if e and not full and Rhylib.Perma and Rhylib.Perma.Is(IsValid(e.ent) and e.ent or ent) then
            note(ply, "That's part of the permanent map setup: ask an admin", "bad")
            return
        end
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
        -- (limited access: the permission came from the first trace's thing;
        -- the aim may have moved while the check ran, so it must be the same kind)
        if not full and not (pre and e.class == pre.class) then return end
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
        note(ply, n > 0 and string.format("%d now follow %s.", n, target == ply and "you" or target:Nick())
            or "Pick clones first (LMB).", n > 0 and "good" or "bad", "Clones")
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
        note(ply, "Saving every permanent thing on " .. game.GetMap(), "good")
    end)
end, { rate = 1, burst = 2 })

-- Getting one: console rhylib_toolgun (the client's command sends
-- tool.give), chat !toolgun or /toolgun, or the spawn menu (Weapons > Rhylib).
local function give(ply)
    if not IsValid(ply) then return end
    anyAccess(ply, function(ok)
        if not IsValid(ply) then return end
        if not ok then return note(ply, "You don't have permission for the toolgun", "bad") end
        if not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
        ply:SelectWeapon(CLASS)
    end)
end
-- Tool.Give(ply): give and select the toolgun (checks access).
Tool.Give = give

Rhylib.Net.Receive("tool.give", give, { rate = 1, burst = 2 })

-- !keeptoolgun: gives you one if you don't have it, and you get it again
-- after every respawn (saved per player; say it again to stop).
local function keepKey(ply) return "keep_" .. ply:SteamID64() end

-- Tool.KeepsToolgun(ply): true if they turned on !keeptoolgun (cached on
-- the player, read from Data once).
function Tool.KeepsToolgun(ply)
    if ply.rhylibKeepTool == nil then
        ply.rhylibKeepTool = not ply:IsBot() and Rhylib.Data.Get("toolgun", keepKey(ply)) == true or false
    end
    return ply.rhylibKeepTool
end

local function keepToolgun(ply)
    if not IsValid(ply) then return end
    anyAccess(ply, function(ok)
        if not IsValid(ply) then return end
        if not ok then return note(ply, "You don't have permission for the toolgun", "bad") end
        local on = not Tool.KeepsToolgun(ply)
        ply.rhylibKeepTool = on
        if on then
            Rhylib.Data.Set("toolgun", keepKey(ply), true)
            if ply:Alive() and not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
            note(ply, "You'll keep the toolgun after dying. Say !keeptoolgun again to stop.", "good")
        else
            Rhylib.Data.Delete("toolgun", keepKey(ply))
            note(ply, "You won't get the toolgun back after dying any more.")
        end
    end)
end

-- After the inventory hands weapons back and stows them (timer 0 / 0.1).
Rhylib.Hook.Add("PlayerSpawn", "toolgun.keep", function(ply)
    if ply:IsBot() or not Tool.KeepsToolgun(ply) then return end
    timer.Simple(0.5, function()
        if not (IsValid(ply) and ply:Alive()) or ply:HasWeapon(CLASS) then return end
        anyAccess(ply, function(ok)
            if ok and IsValid(ply) and ply:Alive() and not ply:HasWeapon(CLASS) then ply:Give(CLASS) end
        end)
    end)
end)

-- !toolgun / /toolgun and !keeptoolgun / /keeptoolgun (Rhylib.Command;
-- the access check is give / keepToolgun's own, so no perm here). The
-- console versions are rhylib_toolgun_give and rhylib_keeptoolgun (the
-- plain rhylib_toolgun console command is the client's, it sends tool.give).
Rhylib.Command.Add({
    name = "rhylib_toolgun_give", chat = { "toolgun" }, tag = "Toolgun",
    help = "Get Rhy's toolgun (staff)",
    fn = function(ply) give(ply) end,
})
Rhylib.Command.Add({
    name = "rhylib_keeptoolgun", chat = { "keeptoolgun" }, tag = "Toolgun",
    help = "Keep the toolgun after every respawn (say it again to stop)",
    fn = function(ply) keepToolgun(ply) end,
})
