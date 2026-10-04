--[[
    Ammo store for reloads (server only).

    kind is an item id: "mag_small", "mag_medium", "mag_large", "rocket"
    or "cell" (see W.MagTypes in sh_00_config.lua).

    With rhylib_inventory installed, magazines and power cells are real
    inventory items with a fill level from 0 to 1. Without it, a simple
    per-player pouch is used instead, so the weapons addon still works on
    its own.

    Reloading always loads the fullest one of the chosen type and puts the
    old one back if it isn't empty, so no shots are lost.

    Counts are mirrored into GMod ammo types so the client HUD and reload
    menu can read them.
]]

local W = Rhylib.Weapons
W.Pouch = W.Pouch or {}
local Pouch = W.Pouch
local Config = Rhylib.Config

-- Every kind the store knows, with its mirror ammo type.
local KINDS = {}
for id, m in pairs(W.MagTypes) do KINDS[id] = m.ammo end
KINDS[W.CELL] = "rhylib_cell"
if W.Grapple then KINDS[W.Grapple.ITEM] = W.Grapple.AMMO end  -- grapple hooks, so the client knows you have one

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.AddItem and Inv or nil
end

-- Fallback pouch -------------------------------------------------------

local function get(ply, kind)
    local p = ply.RhylibPouch
    if not p then
        p = {}
        ply.RhylibPouch = p
    end
    local list = p[kind]
    if not list then
        list = {}
        p[kind] = list
    end
    return list
end

local function limit(kind)
    return Config.Get("weapons", kind == W.CELL and "maxCells" or "maxMags")
end

-- Shared API -----------------------------------------------------------

function Pouch.Count(ply, kind)
    if not KINDS[kind] then return 0 end
    local Inv = inventory()
    if Inv then return Inv.Count(ply, kind) end
    return #get(ply, kind)
end

function Pouch.Sync(ply)
    for kind, ammo in pairs(KINDS) do
        ply:SetAmmo(Pouch.Count(ply, kind), ammo)
    end
end

-- Returns false if there's no room. force: never lose it (drops it on
-- the ground with the inventory, ignores the limit without).
-- issued: it came from an armoury (keeps that mark in the inventory).
function Pouch.Add(ply, kind, fill, force, issued)
    if not KINDS[kind] then return false end
    fill = math.Clamp(fill, 0, 1)
    local Inv = inventory()
    if Inv then
        local data = { fill = fill, issued = issued or nil }
        if force then
            Inv.AddOrDrop(ply, kind, 1, data)
            return true
        end
        return Inv.AddItem(ply, kind, 1, data) == 0
    end

    local list = get(ply, kind)
    if not force and #list >= limit(kind) then return false end
    list[#list + 1] = fill
    Pouch.Sync(ply)
    return true
end

-- Removes and returns the fullest one (and, with the inventory, whether it
-- was issued), or nil if there are none.
function Pouch.TakeBest(ply, kind)
    if not KINDS[kind] then return nil end
    local Inv = inventory()
    if Inv then return Inv.TakeBest(ply, kind) end

    local list = get(ply, kind)
    local best, bestIndex = -1, nil
    for i, fill in ipairs(list) do
        if fill > best then
            best, bestIndex = fill, i
        end
    end
    if not bestIndex then return nil end
    table.remove(list, bestIndex)
    Pouch.Sync(ply)
    return best
end

function Pouch.Reset(ply)
    ply.RhylibPouch = {}
    Pouch.Sync(ply)
end

-- Gives a weapon's start ammo (testing only, until armouries exist).
function Pouch.GiveStartAmmo(ply, swep, force)
    local kind = swep.Mags and (swep.FirstMagFor and swep:FirstMagFor(ply) or swep.Mags[1])
    if kind then
        for _ = 1, swep.StartMags or 0 do Pouch.Add(ply, kind, 1, force) end
    end
    for _ = 1, swep.StartCells or 0 do Pouch.Add(ply, W.CELL, 1, force) end
end

-- Hooks ----------------------------------------------------------------

-- Without the inventory, players respawn with an empty pouch.
Rhylib.Hook.Add("PlayerSpawn", "weapons.pouch", function(ply)
    if inventory() then
        timer.Simple(0, function() if IsValid(ply) then Pouch.Sync(ply) end end)
        return
    end
    Pouch.Reset(ply)
end)

-- Keep the mirrored counts in step with the inventory.
Rhylib.Hook.Add("Rhylib.InventoryChanged", "weapons.pouch", function(ply)
    Pouch.Sync(ply)
end)

-- A newly picked-up weapon comes with its start ammo (testing only).
Rhylib.Hook.Add("Rhylib.InventoryWeaponPickup", "weapons.startammo", function(ply, class)
    local swep = weapons.Get(class)
    if not swep or not swep.IsRhylib then return end
    Pouch.GiveStartAmmo(ply, swep, true)
end)

-- E + R (fire mode) and Shift + E + R (safety).
Rhylib.Net.Receive("wep.mode", function(ply)
    local safety = net.ReadBool()
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep.IsRhylib) then return end
    if safety then wep:ToggleSafety() else wep:CycleFireMode() end
end, { rate = 4, burst = 3 })

-- Reload requests from the R key and the radial menu.
-- See W.RELOAD_REQ_* in sh_00_config.lua.
Rhylib.Net.Receive("wep.reload", function(ply)
    local req = net.ReadUInt(W.RELOAD_REQ_BITS)
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep.IsRhylib and wep.StartReload) then return end
    if req == W.RELOAD_REQ_CELL then
        wep:StartReload(2)
    else
        local m = W.MagByIndex[req]
        wep:StartReload(1, m and m.id or nil)
    end
end, { rate = 4, burst = 3 })

-- rhylib_infammo (admins): toggles test ammo for yourself. Firing uses
-- nothing and reloading always works and loads a full magazine / cell.
Rhylib.Perms.Register("rhylib.weapons.infammo", "admin", "Infinite test ammo (rhylib_infammo)")

concommand.Add("rhylib_infammo", function(ply)
    if not IsValid(ply) then return end
    Rhylib.Perms.Check(ply, "rhylib.weapons.infammo", function(ok)
        if not IsValid(ply) then return end
        if not ok then ply:ChatPrint("You don't have permission for rhylib_infammo") return end
        local on = not ply:GetNW2Bool("rhylib_infammo")
        ply:SetNW2Bool("rhylib_infammo", on)
        local wep = ply:GetActiveWeapon()
        if on and IsValid(wep) and wep.IsRhylib and wep.GetMagSize then
            wep:SetClip1(wep:GetMagSize())
            if wep.UsesCell then wep:SetCell(1) end
        end
        ply:ChatPrint("Infinite test ammo " .. (on and "on" or "off"))
    end)
end)

-- Dual mode needs both pistols in the inventory: one gone, back to one.
Rhylib.Hook.Add("Rhylib.InventoryChanged", "weapons.dualcheck", function(ply)
    if not IsValid(ply) then return end
    for _, w in ipairs(ply:GetWeapons()) do
        if w.IsRhylib and w.FixFireMode then w:FixFireMode() end
    end
end)
