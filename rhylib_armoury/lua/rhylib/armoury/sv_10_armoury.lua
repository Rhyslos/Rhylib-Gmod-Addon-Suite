--[[
    Armoury, server side: the storage behind each armoury entity, locker
    claiming and locking, crate filling, and saving where admins placed
    everything on each map.

    Admin commands (permission rhylib.armoury.admin):
      rhylib_armoury_save        keep every armoury, cabinet, locker and
                                 crate on this map where they are now
      rhylib_crate_refill [all]  refill the crate you're looking at (or all)
      rhylib_locker_unclaim      free the locker you're looking at
]]

local A = Rhylib.Armoury
local Config = Rhylib.Config

Rhylib.Perms.Register("rhylib.armoury.admin", "admin", "Save armoury placements, refill supply crates, unclaim lockers")
Rhylib.Net.Register("armoury.prompt")

local function Inv() return Rhylib.Inventory end

--------------------------------------------------------------------------
-- Storage for each kind
--------------------------------------------------------------------------

-- Every Rhylib gun, biggest first so the shelf packs neatly (or the config
-- list). training: the training copies instead (rhylib_training).
A.FIRST_WEAPONS = { "rhylib_dc15a", "rhylib_dc15s" }

local function weaponStock(training)
    local list = Config.Get("armoury", training and "trainingWeapons" or "weapons")
    if istable(list) and #list > 0 then return list end
    local Items = Rhylib.Items
    Items.EnsureReady()
    -- Role gear lives in the specialist armouries.
    local roleItem = {}
    local roles = Config.Get("armoury", "roles")
    if istable(roles) then
        for _, r in pairs(roles) do
            for _, kind in ipairs({ "weapons", "gear" }) do
                if istable(r[kind]) then for _, id in ipairs(r[kind]) do roleItem[id] = true end end
            end
        end
    end
    local out = {}
    for id, def in pairs(Items.defs) do
        if def.weapon and not roleItem[id] then
            local swep = weapons.Get(def.weapon)
            if swep and swep.IsRhylib and swep.Spawnable and not swep.NoArmoury and (swep.Training and true or false) == (training and true or false) then
                out[#out + 1] = id
            end
        end
    end
    -- The standard rifles first (owner), then biggest first.
    local first = A.FIRST_WEAPONS or {}
    local function rank(id)
        local base = string.gsub(id, "_training$", "")
        for i, f in ipairs(first) do if f == base then return i end end
        return #first + 1
    end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local da, db = Items.defs[a], Items.defs[b]
        if da.w * da.h ~= db.w * db.h then return da.w * da.h > db.w * db.h end
        return da.name < db.name
    end)
    return out
end

local function ammoStock(training)
    local out = {}
    for _, id in ipairs(training and A.TRAINING_AMMO_STOCK or A.AMMO_STOCK) do
        if Rhylib.Items.defs[id] then out[#out + 1] = id end
    end
    return out
end

-- Gear cabinet stock for one player: the config list, plus what other
-- modules add for them (rhylib_gear: parts their model shows and they may take).
local function gearStock(ply)
    local out = {}
    for _, id in ipairs(Config.Get("armoury", "gearStock") or {}) do
        if Rhylib.Items.defs[id] then out[#out + 1] = id end
    end
    hook.Run("Rhylib.GearStock", out)
    if IsValid(ply) then hook.Run("Rhylib.GearStockFor", ply, out) end
    return out
end

-- One depot per distinct stock list, picked when someone opens it.
local function gearVariant(storage, ply)
    local stock = gearStock(ply)
    local key = table.concat(stock, ",")
    local sub = storage.subs[key]
    if not sub then
        -- (takes back any gear part, even one you can't draw any more)
        local back = {}
        for _, id in ipairs(gearStock()) do back[id] = true end
        hook.Run("Rhylib.GearReturnable", back)
        sub = Inv().NewStorage(storage.ent, { kind = "depot", w = 6, title = "Gear cabinet", stock = stock, returnable = back })
        storage.subs[key] = sub
    end
    return sub
end

function A.FillCrate(ent, storage)
    storage.items = {}
    if ent.CrateMag then
        Inv().StorageAdd(storage, ent.CrateMag, 999, { fill = 1 })
        return
    end
    local list = ent.CrateStock and Config.Get("armoury", ent.CrateStock)
    if not istable(list) then return end
    Rhylib.Items.EnsureReady()
    for _, row in ipairs(list) do
        local def = istable(row) and Rhylib.Items.defs[row[1]]
        if def and not hook.Run("Rhylib.ItemDisabled", row[1]) then Inv().StorageAdd(storage, row[1], tonumber(row[2]) or 1, def.fill and { fill = 1 } or {}) end
    end
end

-- Specialist stock for a set of roles (only items that exist).
local function roleStock(roles, kind)
    local cfg = Config.Get("armoury", "roles")
    local out, seen = {}, {}
    if not istable(cfg) then return out end
    Rhylib.Items.EnsureReady()
    for _, r in ipairs(roles) do
        local list = istable(cfg[r]) and cfg[r][kind]
        if istable(list) then
            for _, id in ipairs(list) do
                -- (hook Rhylib.ItemDisabled: e.g. field items under the simplified medical system)
                if not seen[id] and Rhylib.Items.defs[id] and not hook.Run("Rhylib.ItemDisabled", id) then seen[id] = true out[#out + 1] = id end
            end
        end
    end
    return out
end

-- One depot per set of roles, made when someone with that set opens it.
-- Items the player may not hold yet (skill-locked, e.g. the CG riot shield
-- until Riot shield is learned) are left out, so learning a skill makes them
-- appear (owner 2026-10-09).
local function specVariant(storage, ply)
    local roles = A.Roles(ply)
    local all = roleStock(roles, storage.specKind)
    local I = Inv()
    local stock = {}
    for _, id in ipairs(all) do
        if not (I and I.MayHold) or I.MayHold(ply, id) then stock[#stock + 1] = id end
    end
    local key = table.concat(roles, "+") .. "|" .. table.concat(stock, ",")
    local sub = storage.subs[key]
    if not sub then
        if #stock == 0 then
            ply:PrintMessage(HUD_PRINTCENTER, "Nothing here for your role")
            return nil
        end
        sub = Inv().NewStorage(storage.ent, { kind = "depot", w = 6, title = storage.title, stock = stock })
        storage.subs[key] = sub
    end
    return sub
end

--------------------------------------------------------------------------
-- Training deposit: one storage per player (sub-storage by SteamID),
-- loaded again on every open (another deposit may have changed it).
-- Data "train_dep"/sid = { rows, left = seconds of online time left }.
-- A.deposits[sid] = seconds left, for online players with gear stored.
--------------------------------------------------------------------------

A.deposits = A.deposits or {}

local function depositRead(sid)
    local d = Rhylib.Data.Get("train_dep", sid)
    if istable(d) and d.rows then return d.rows, d.left end
end

local function depositTitle(sid)
    local left = A.deposits[sid]
    if not left then return "Training deposit" end
    local m = math.ceil(left / 60)
    return string.format("Training deposit · %s left", m >= 60 and string.format("%dh %02dm", math.floor(m / 60), m % 60) or (m .. " min"))
end

-- (the window shows the time left: sent again when it changes)
local function retitle(sid, storage)
    local t = depositTitle(sid)
    if storage.title == t then return end
    storage.title = t
    if IsValid(storage.ent) then Inv().RefreshStorage(storage.ent) end
end

local function depositSave(sid, storage)
    if next(storage.items) == nil then
        Rhylib.Data.Delete("train_dep", sid)
        A.deposits[sid] = nil
        retitle(sid, storage)
        return
    end
    -- (a new trip starts the clock)
    A.deposits[sid] = A.deposits[sid] or Config.Get("armoury", "depositTime")
    Rhylib.Data.Set("train_dep", sid, { rows = Inv().StorageSerialize(storage), left = A.deposits[sid] })
    retitle(sid, storage)
end

local function depositVariant(storage, ply)
    local sid = ply:SteamID64()
    if not sid then return nil end
    local sub = storage.subs[sid]
    if not sub then
        sub = Inv().NewStorage(storage.ent, {
            kind = "grid", w = 6, h = 6, title = "Training deposit", bulkOnly = true, grow = true,
            onChanged = function(s) depositSave(sid, s) end,
        })
        storage.subs[sid] = sub
    end
    if not next(sub.viewers) then Inv().StorageLoad(sub, (depositRead(sid))) end
    sub.title = depositTitle(sid)
    return sub
end

-- Time's up: what's left is deleted (in every deposit that has it loaded).
local function depositExpire(sid, ply)
    Rhylib.Data.Delete("train_dep", sid)
    A.deposits[sid] = nil
    if not Inv() then return end
    for _, ent in ipairs(ents.FindByClass("rhylib_training_deposit")) do
        local storage = Inv().GetStorage(ent)
        local sub = storage and storage.subs[sid]
        if sub then
            Inv().StorageLoad(sub, nil)
            sub.title = depositTitle(sid)
            Inv().RefreshStorage(ent)
        end
    end
    if IsValid(ply) then ply:ChatPrint("Your training deposit ran out of time and was cleared") end
end

Rhylib.Hook.Add("PlayerInitialSpawn", "armoury.deposit", function(ply)
    local sid = ply:SteamID64()
    if not sid then return end
    local rows, left = depositRead(sid)
    if rows then A.deposits[sid] = left or Config.Get("armoury", "depositTime") end
end)

Rhylib.Hook.Add("PlayerDisconnected", "armoury.deposit", function(ply)
    local sid = ply:SteamID64()
    if sid then A.deposits[sid] = nil end   -- (left is saved once a minute)
end)

-- Online time counts down once a minute.
timer.Create("Rhylib.Armoury.Deposit", 60, 0, function()
    for _, ply in ipairs(player.GetHumans()) do
        local sid = ply:SteamID64()
        local left = sid and A.deposits[sid]
        if left then
            left = left - 60
            if left <= 0 then
                depositExpire(sid, ply)
            else
                A.deposits[sid] = left
                local d = Rhylib.Data.Get("train_dep", sid)
                if istable(d) and d.rows then
                    d.left = left
                    Rhylib.Data.Set("train_dep", sid, d)
                else
                    A.deposits[sid] = nil
                end
            end
        end
    end
end)

local function lockerTitle(ent)
    local name = ent:GetOwnerName()
    return name ~= "" and ("Locker: " .. name) or "Personal locker"
end

function A.LoadLocker(ent, storage)
    local sid = ent:GetOwnerSid()
    Inv().StorageLoad(storage, sid ~= "" and Rhylib.Data.Get("locker", sid) or nil)
    storage.title = lockerTitle(ent)
end

function A.SaveLocker(ent)
    if not Inv() then return end   -- (rhylib_inventory missing)
    local storage = Inv().GetStorage(ent)
    local sid = ent:GetOwnerSid()
    if not storage or sid == "" then return end
    Rhylib.Data.Set("locker", sid, Inv().StorageSerialize(storage))
end

-- The storage for an armoury entity, made the first time someone uses it.
function A.Setup(ent)
    local I = Inv()
    if not I or not I.CreateStorage then return nil end
    local storage = I.GetStorage(ent)
    if storage then return storage end

    local kind = ent.ArmouryKind
    if kind == "armoury" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Weapons armoury", stock = weaponStock() })
    elseif kind == "ammo" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Ammo cabinet", stock = ammoStock() })
    elseif kind == "trainingArmoury" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Training armoury", stock = weaponStock(true) })
    elseif kind == "trainingAmmo" then
        return I.CreateStorage(ent, { kind = "depot", w = 6, title = "Training ammo", stock = ammoStock(true) })
    elseif kind == "trainingDeposit" then
        return I.CreateStorage(ent, { kind = "grid", w = 6, h = 6, title = "Training deposit", variant = depositVariant })
    elseif kind == "gear" then
        return I.CreateStorage(ent, { kind = "grid", w = 1, h = 1, title = "Gear cabinet", variant = gearVariant })
    elseif kind == "spec" then
        storage = I.CreateStorage(ent, { kind = "grid", w = 1, h = 1, title = ent.PrintName, variant = specVariant })
        storage.specKind = ent.SpecKind
        return storage
    elseif kind == "crate" then
        storage = I.CreateStorage(ent, {
            kind = "grid", title = ent.PrintName,
            w = Config.Get("armoury", "crateW"), h = Config.Get("armoury", "crateH"),
        })
        A.FillCrate(ent, storage)
        return storage
    elseif kind == "locker" then
        storage = I.CreateStorage(ent, {
            kind = "grid", title = lockerTitle(ent),
            w = Config.Get("armoury", "lockerW"), h = Config.Get("armoury", "lockerH"),
            onChanged = function() A.SaveLocker(ent) end,
            controls = function(_, ply)
                return { canLock = ply:SteamID64() == ent:GetOwnerSid(), locked = ent:GetLocked() }
            end,
        })
        A.LoadLocker(ent, storage)
        return storage
    end
end

--------------------------------------------------------------------------
-- Using
--------------------------------------------------------------------------

function A.Use(ent, ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local storage = A.Setup(ent)
    if not storage then
        ply:PrintMessage(HUD_PRINTCENTER, "Needs rhylib_inventory")
        return
    end

    if ent.ArmouryKind == "locker" then
        local sid = ent:GetOwnerSid()
        if sid == "" then
            Rhylib.Net.Start("armoury.prompt")
            net.WriteEntity(ent)
            net.Send(ply)
            return
        end
        -- Military police can search locked lockers (rhylib_mp answers the hook).
        if sid ~= ply:SteamID64() and ent:GetLocked() and hook.Run("Rhylib.CanSearchLocker", ply, ent) ~= true then
            ply:PrintMessage(HUD_PRINTCENTER, "Locked. This is " .. ent:GetOwnerName() .. "'s locker")
            return
        end
    end
    Inv().OpenStorage(ply, ent)
end

--------------------------------------------------------------------------
-- Lockers: claim, lock, unclaim
--------------------------------------------------------------------------

local function ownsLocker(sid)
    for _, e in ipairs(ents.FindByClass("rhylib_locker")) do
        if e:GetOwnerSid() == sid then return e end
    end
end

function A.Claim(ply, ent)
    if not Inv() then return end   -- (rhylib_inventory missing)
    if not IsValid(ent) or ent:GetClass() ~= "rhylib_locker" or ent:GetOwnerSid() ~= "" then return end
    local dist = Inv() and Inv().STORAGE_DIST or 160
    if ply:GetPos():DistToSqr(ent:GetPos()) > dist * dist then return end
    local sid = ply:SteamID64()
    if not sid then return end
    if ownsLocker(sid) then
        ply:PrintMessage(HUD_PRINTCENTER, "You already have a locker")
        return
    end
    ent:SetOwnerSid(sid)
    ent:SetOwnerName(ply:Nick())
    ent:SetLocked(true)
    local storage = A.Setup(ent)
    if storage then A.LoadLocker(ent, storage) end
    A.UpdatePlacement(ent)
    Inv().OpenStorage(ply, ent)
end

function A.ToggleLock(ent)
    if not Inv() then return end   -- (rhylib_inventory missing)
    ent:SetLocked(not ent:GetLocked())
    local storage = Inv().GetStorage(ent)
    if storage and ent:GetLocked() then
        for p in pairs(storage.viewers) do
            if IsValid(p) and p:SteamID64() ~= ent:GetOwnerSid() then Inv().CloseStorage(p) end
        end
    end
    Inv().RefreshStorage(ent)
    A.UpdatePlacement(ent)
end

-- The contents stay saved under the old owner; they get them back in
-- whichever locker they claim next.
function A.Unclaim(ent)
    if not Inv() then return end   -- (rhylib_inventory missing)
    A.SaveLocker(ent)
    Inv().RemoveStorage(ent)
    ent:SetOwnerSid("")
    ent:SetOwnerName("")
    ent:SetLocked(false)
    A.UpdatePlacement(ent)
end

-- A new job can mean a different role: close a specialist armoury left open.
Rhylib.Hook.Add("OnPlayerChangedTeam", "armoury.roles", function(ply)
    local I = Inv()
    local st = I and I.states and I.states[ply]
    local storage = st and st.ext
    if storage and IsValid(storage.ent) and storage.ent.ArmouryKind == "spec" then I.CloseStorage(ply) end
end)

Rhylib.Net.Receive("armoury.claim", function(ply)
    A.Claim(ply, net.ReadEntity())
end, { rate = 2, burst = 2 })

-- Owner buttons in the locker window: 0 = lock/unlock, 1 = unclaim.
Rhylib.Net.Receive("armoury.control", function(ply)
    local action = net.ReadUInt(1)
    if not Inv() then return end
    local storage = Inv().Get(ply).ext
    local ent = storage and storage.ent
    if not IsValid(ent) or ent:GetClass() ~= "rhylib_locker" or ent:GetOwnerSid() ~= ply:SteamID64() then return end
    if action == 0 then A.ToggleLock(ent) else A.Unclaim(ent) end
end, { rate = 3, burst = 3 })

--------------------------------------------------------------------------
-- Placements per map
--------------------------------------------------------------------------

A.placements = A.placements or {}

local function rowFor(ent)
    local p, a = ent:GetPos(), ent:GetAngles()
    local row = { class = ent:GetClass(), pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r } }
    if ent:GetClass() == "rhylib_locker" then
        row.owner, row.ownerName, row.locked = ent:GetOwnerSid(), ent:GetOwnerName(), ent:GetLocked()
    end
    return row
end

function A.SavePlacements()
    local rows = {}
    for class in pairs(A.CLASSES) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            -- (only permanent ones: the toolgun's Permanent tool, 2026-10-09u)
            if (not Rhylib.Perma or Rhylib.Perma.Is(ent)) then
                rows[#rows + 1] = rowFor(ent)
                ent.placeIndex = #rows
            else
                ent.placeIndex = nil
            end
        end
    end
    A.placements = rows
    Rhylib.Data.Set("armoury", game.GetMap(), rows)
    return #rows
end

-- Keep a saved locker's claim when it changes.
function A.UpdatePlacement(ent)
    local i = ent.placeIndex
    if not i or not A.placements[i] then return end
    A.placements[i] = rowFor(ent)
    Rhylib.Data.Set("armoury", game.GetMap(), A.placements)
end

function A.SpawnPlacements()
    local rows = Rhylib.Data.Get("armoury", game.GetMap())
    if not istable(rows) then return end
    A.placements = rows
    for i, row in ipairs(rows) do
        if A.CLASSES[row.class] then
            local ent = ents.Create(row.class)
            if IsValid(ent) then
                ent:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
                ent:SetAngles(Angle(row.ang[1], row.ang[2], row.ang[3]))
                ent:Spawn()
                if row.class == "rhylib_locker" and row.owner and row.owner ~= "" then
                    ent:SetOwnerSid(row.owner)
                    ent:SetOwnerName(row.ownerName or "")
                    ent:SetLocked(row.locked and true or false)
                end
                ent.placeIndex = i
                if Rhylib.Perma then Rhylib.Perma.Mark(ent, true) end
            end
        end
    end
    Rhylib.Print("armoury", "Placed %d armoury entities on %s", #rows, game.GetMap())
end

if Rhylib.Perma and Rhylib.Perma.Register then
    local list = {}
    for c in pairs(A.CLASSES) do list[#list + 1] = c end
    Rhylib.Perma.Register(list, A.SavePlacements)
end

Rhylib.Hook.Add("InitPostEntity", "armoury.spawn", function()
    timer.Simple(1, A.SpawnPlacements)
end)

Rhylib.Hook.Add("PostCleanupMap", "armoury.spawn", function()
    A.SpawnPlacements()
end)

--------------------------------------------------------------------------
-- Admin commands
--------------------------------------------------------------------------

local function reply(ply, msg)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

local function adminCommand(name, fn)
    concommand.Add(name, function(ply, _, args)
        Rhylib.Perms.Check(ply, "rhylib.armoury.admin", function(ok)
            if not ok then
                reply(ply, "You don't have permission for " .. name)
                return
            end
            fn(ply, args)
        end)
    end)
end

local function lookedAt(ply, class)
    if not IsValid(ply) then return nil end
    local ent = ply:GetEyeTrace().Entity
    if IsValid(ent) and (not class or ent:GetClass():find(class, 1, true)) then return ent end
end

adminCommand("rhylib_armoury_save", function(ply)
    reply(ply, "Saved " .. A.SavePlacements() .. " armoury entities for " .. game.GetMap())
end)

adminCommand("rhylib_crate_refill", function(ply, args)
    local list = {}
    if args[1] == "all" then
        for _, class in ipairs(A.CRATES) do
            for _, e in ipairs(ents.FindByClass(class)) do list[#list + 1] = e end
        end
    else
        local e = lookedAt(ply)
        if e and table.HasValue(A.CRATES, e:GetClass()) then list[1] = e end
    end
    local n = 0
    for _, ent in ipairs(list) do
        local storage = A.Setup(ent)
        if storage then
            A.FillCrate(ent, storage)
            Inv().RefreshStorage(ent)
            n = n + 1
        end
    end
    reply(ply, "Refilled " .. n .. " crate" .. (n == 1 and "" or "s"))
end)

adminCommand("rhylib_locker_unclaim", function(ply)
    local ent = lookedAt(ply, "rhylib_locker")
    if not ent or ent:GetOwnerSid() == "" then
        reply(ply, "Look at a claimed locker")
        return
    end
    local name = ent:GetOwnerName()
    A.Unclaim(ent)
    reply(ply, "Unclaimed " .. name .. "'s locker (their items are kept for their next locker)")
end)
