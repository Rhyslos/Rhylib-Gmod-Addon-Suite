--[[
    Permanent things (2026-10-09u, owner: what the toolgun places isn't
    saved any more; staff make things permanent on purpose with the
    toolgun's "Permanent" tool, and !cleanup wipes everything else).

    A permanent entity has NW2Bool rhylib_perma (`P.Is`). Saving:
      - Rhylib fixtures (armouries, med bay, jail, computers, beacons, spawn
        points, jammers) keep their own savers, which now only save the
        permanent ones; each addon registers them with
        P.Register({ classes }, saveFn) and marks what it loads (P.Mark).
      - Anything else (props, ragdolls, other addons' entities) goes in a
        plain list: Data "perma"/<map> = { { c, m, p, a, s, mat, col, cg,
        fz, bg } }, spawned again at InitPostEntity +1 s and after a map
        cleanup (P.SaveGeneric / P.LoadGeneric).
    P.Set(ply, ent, on) is what the tool calls; P.Forget(ent) removes one
    and saves without it.
]]

Rhylib.Perma = Rhylib.Perma or {}
local P = Rhylib.Perma

P.NW = "rhylib_perma"

function P.Is(e)
    return IsValid(e) and e:GetNW2Bool(P.NW, false)
end

if CLIENT then return end

P.savers = P.savers or {}   -- [class] = function() return count end

-- An addon's own saver for its classes (it saves only P.Is entities).
function P.Register(classes, fn)
    for _, c in ipairs(classes) do P.savers[c] = fn end
end

function P.Mark(e, on)
    if not IsValid(e) then return end
    on = on and true or false
    if e:GetNW2Bool(P.NW, false) ~= on then e:SetNW2Bool(P.NW, on) end
    e.rhylibPerma = on or nil
end

-- Never kept by the plain list: players, NPCs, carried weapons, vehicles
-- (they need their vehicle script), loose inventory items (their data),
-- hands/viewmodels, ropes and lying bodies.
local SKIP = { gmod_hands = true, predicted_viewmodel = true, viewmodel = true, rhylib_rope = true,
    rhylib_world_item = true, gmod_gamerules = true, physgun_beam = true,
    rhylib_grenade = true, rhylib_he_planted = true, rhylib_b2_rocket = true }   -- (live explosives)

function P.Why(e)
    if not IsValid(e) or e:IsWorld() then return "Aim at something" end
    if e:IsPlayer() then return "Players can't be made permanent" end
    if e:CreatedByMap() then return "That's part of the map already" end
    if P.savers[e:GetClass()] then return nil end
    if e:IsNPC() or e:IsNextBot() then return "NPCs aren't kept (place them again each time)" end
    if e:IsVehicle() then return "Vehicles can't be made permanent" end
    if e:IsWeapon() and IsValid(e:GetOwner()) then return "Someone is holding that" end
    if SKIP[e:GetClass()] or e:GetNW2Bool("rhylib_lyingRag", false) then return "That can't be made permanent" end
    local par = e:GetParent()
    if IsValid(par) then return "That's attached to something else" end
    return nil
end

local function vec(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end
local function ang(t) return Angle(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end

local function bodygroups(e)
    local s = {}
    for i = 0, e:GetNumBodyGroups() - 1 do s[#s + 1] = string.format("%x", math.min(e:GetBodygroup(i), 15)) end
    return table.concat(s)
end

-- Every physics object frozen (ragdolls have one per limb).
local function freezeAll(e)
    for i = 0, math.max(e:GetPhysicsObjectCount(), 1) - 1 do
        local ph = e:GetPhysicsObjectNum(i)
        if IsValid(ph) then ph:EnableMotion(false) end
    end
end
P.FreezeAll = freezeAll

function P.SaveGeneric()
    local rows = {}
    for _, e in ipairs(ents.GetAll()) do
        if P.Is(e) and not P.savers[e:GetClass()] and not P.Why(e) then
            -- (a prop_effect shows its model on AttachedEntity; its own is a stand-in)
            local src = IsValid(e.AttachedEntity) and e.AttachedEntity or e
            local p, a, c = e:GetPos(), e:GetAngles(), e:GetColor()
            local ph = e:GetPhysicsObject()
            local row = {
                c = e:GetClass(), m = src:GetModel(), p = { p.x, p.y, p.z }, a = { a.p, a.y, a.r },
                s = src:GetSkin(), mat = e:GetMaterial(), col = { c.r, c.g, c.b, c.a }, rm = e:GetRenderMode(),
                cg = e:GetCollisionGroup(), fz = not (IsValid(ph) and ph:IsMotionEnabled()), bg = bodygroups(src),
            }
            -- Ragdolls: every limb's place, so they come back in the same pose.
            local n = e:GetPhysicsObjectCount()
            if n > 1 then
                row.b = {}
                for i = 0, n - 1 do
                    local bp = e:GetPhysicsObjectNum(i)
                    if IsValid(bp) then
                        local q, r = bp:GetPos(), bp:GetAngles()
                        row.b[i + 1] = { q.x, q.y, q.z, r.p, r.y, r.r }
                    end
                end
            end
            rows[#rows + 1] = row
        end
    end
    Rhylib.Data.Set("perma", game.GetMap(), rows)
    return #rows
end

function P.LoadGeneric()
    local rows = Rhylib.Data.Get("perma", game.GetMap())
    if not istable(rows) then return end
    -- (loaded twice, e.g. a cleanup before the first load: no doubles)
    P.loading = true
    for _, e in ipairs(ents.GetAll()) do
        if P.Is(e) and not P.savers[e:GetClass()] then e:Remove() end
    end
    P.loading = nil
    local n = 0
    for _, r in ipairs(rows) do
        local ok, err = pcall(function()
            if not (isstring(r.c) and istable(r.p) and istable(r.a)) then return end
            if P.savers[r.c] then return end   -- (its own addon spawns those)
            local e = ents.Create(r.c)
            if not IsValid(e) then return end
            local isProp = string.sub(r.c, 1, 5) == "prop_"
            if isProp and isstring(r.m) and r.m ~= "" then e:SetModel(r.m) end
            e:SetPos(vec(r.p))
            e:SetAngles(ang(r.a))
            e:Spawn()
            e:Activate()
            -- (scripted entities pick their own model; only change a different one)
            if not isProp and isstring(r.m) and r.m ~= "" and e:GetModel() ~= r.m and util.IsValidModel(r.m) then e:SetModel(r.m) end
            if r.s then e:SetSkin(r.s) end
            if isstring(r.mat) and r.mat ~= "" then e:SetMaterial(r.mat) end
            if istable(r.col) then e:SetColor(Color(r.col[1] or 255, r.col[2] or 255, r.col[3] or 255, r.col[4] or 255)) end
            if r.rm then e:SetRenderMode(r.rm) end
            if r.cg then e:SetCollisionGroup(r.cg) end
            local look = IsValid(e.AttachedEntity) and e.AttachedEntity or e
            if look ~= e and r.s then look:SetSkin(r.s) end
            if isstring(r.bg) and r.bg ~= "" then look:SetBodyGroups(r.bg) end
            if istable(r.b) then
                for i = 0, e:GetPhysicsObjectCount() - 1 do
                    local bp, t = e:GetPhysicsObjectNum(i), r.b[i + 1]
                    if IsValid(bp) and istable(t) then
                        bp:SetPos(Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0))
                        bp:SetAngles(Angle(tonumber(t[4]) or 0, tonumber(t[5]) or 0, tonumber(t[6]) or 0))
                        bp:Wake()
                    end
                end
            end
            if r.fz then freezeAll(e) end
            -- (so the toolgun's RMB can remove it)
            e.rhylibToolSpawned = true
            e:SetNW2Bool("rhylib_toolSpawned", true)
            P.Mark(e, true)
            n = n + 1
        end)
        if not ok then Rhylib.Warn("core", "permanent %s didn't load: %s", tostring(r.c), tostring(err)) end
    end
    if n > 0 then Rhylib.Print("core", "Placed %d permanent things on %s", n, game.GetMap()) end
end

-- What exists right after the map loads (incl. point_template spawns,
-- which aren't CreatedByMap) counts as the map for !cleanup.
local function tagMap()
    for _, e in ipairs(ents.GetAll()) do
        if not e:IsPlayer() and not e:IsWeapon() and not P.Is(e) then e.rhylibMapish = true end
    end
end
P.TagMap = tagMap

Rhylib.Hook.Add("InitPostEntity", "core.perma", function()
    timer.Simple(0.5, tagMap)
    timer.Simple(1, P.LoadGeneric)
end)
Rhylib.Hook.Add("PreCleanupMap", "core.perma", function() P.cleaning = true end)
Rhylib.Hook.Add("PostCleanupMap", "core.perma", function()
    P.cleaning = nil
    tagMap()
    P.LoadGeneric()
end)
Rhylib.Hook.Add("ShutDown", "core.perma", function() P.closing = true end)

-- A permanent thing gone some other way (undo, remover, broken): saved
-- without it. Not during a map cleanup or shutdown (they come back).
Rhylib.Hook.Add("EntityRemoved", "core.perma", function(e)
    if P.cleaning or P.closing or P.loading or not e.rhylibPerma then return end
    local class = e:GetClass()
    timer.Simple(0, function() P.Save(class) end)
end)

-- Save what a class belongs to (its addon's saver, or the plain list), a
-- moment later so several changes save once.
local pending = {}
function P.Save(class)
    pending[P.savers[class] or P.SaveGeneric] = true
    timer.Create("Rhylib.Perma.Save", 0.3, 1, function()
        for fn in pairs(pending) do
            local ok, err = pcall(fn)
            if not ok then Rhylib.Warn("core", "saving permanent things failed: %s", tostring(err)) end
        end
        pending = {}
    end)
end

-- The tool: make permanent (or save its new spot), or stop keeping it.
-- Returns a message for the player.
function P.Set(ent, on)
    local why = P.Why(ent)
    if why then return false, why end
    local was = P.Is(ent)
    P.Mark(ent, on)
    if on then freezeAll(ent) end
    P.Save(ent:GetClass())
    local name = ent.PrintName and ent.PrintName ~= "" and ent.PrintName or ent:GetClass()
    if on then return true, was and (name .. ": saved where it is now") or (name .. " is permanent now (comes back every map load)") end
    return true, was and (name .. " is no longer permanent (gone after the next map change)") or (name .. " wasn't permanent")
end

-- Removing a permanent thing for good: gone, and saved without it.
function P.Forget(ent)
    if not IsValid(ent) then return end
    ent:Remove()   -- (EntityRemoved saves without it)
end
