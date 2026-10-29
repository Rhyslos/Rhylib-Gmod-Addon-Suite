--[[
    Inventory weapons (server only; split from sv_10_inventory.lua).

    An item with a `weapon` class gives that weapon while it's in any
    container and strips it when the item leaves. Clip, magazine, cell and
    fire mode are stored in the item via the weapon's GetInventoryData /
    SetInventoryData (captureWeapon). Two copies of one gun (an officer's
    two DC-17s) share one weapon entity: the lowest uid holds the live state.

    Also the weapon game hooks: pickups become items (PlayerCanPickupWeapon,
    job loadout guns marked loadout), every carried gun is given on spawn
    (stowed), inventory weapons can't be dropped as plain weapons, and the
    live state is captured on death.

    Public: Inv.Stow, Inv.CaptureWeapons, Inv.GiveAllWeapons, Inv.STOWED.
    Inv.Internal (I): twinOf, captureWeapon, undoCapture, giveWeapon,
    stripWeapon (used by sv_10_inventory, sv_30_storage, sv_40_give).
    Hook fired: Rhylib.InventoryWeaponPickup(ply, class).
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local I = Inv.Internal

--------------------------------------------------------------------------
-- Weapons
--------------------------------------------------------------------------

-- Another item of the same gun still carried (an officer's two DC-17s
-- share one weapon entity), or nil.
local function twinOf(ply, inst)
    local st = Inv.states[ply]
    if not st then return nil end
    for uid, o in pairs(st.byUid) do
        if uid ~= inst.uid and o.id == inst.id then return o end
    end
end

-- Data for a second copy that isn't the gun in your hands: empty, or in
-- dual mode the second magazine, taken out of the live gun (take = true).
local function spareData(wep, take)
    local live = wep:GetInventoryData() or {}
    local data = { mag = live.mag, clip = 0, mode = 1, magIssued = live.magIssued }
    if take and wep.GetFireModeName and wep:GetFireModeName() == "dual" then
        local single = math.floor(wep:GetMagSize() / (wep.DualMags or 2))
        local extra = math.min(wep:Clip1() - single, single)
        if extra > 0 then
            wep:SetClip1(wep:Clip1() - extra)
            data.clip = extra
        end
    end
    return data
end

-- The weapon's state (clip, mode...) into its item. staying: the item stays
-- with the player (saving); otherwise it's about to leave. With two copies
-- the one leaving only takes a spare's share (no ammo copied).
local function captureWeapon(ply, inst, staying, primary)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    local wep = ply:GetWeapon(def.weapon)
    if IsValid(wep) and wep.GetInventoryData then
        local issued, loadout = inst.data and inst.data.issued, inst.data and inst.data.loadout
        local twin = twinOf(ply, inst)
        inst.rhylibSpareClip = nil
        if twin and not staying then
            inst.data = spareData(wep, true)
            inst.rhylibSpareClip = inst.data.clip   -- (undoCapture puts it back if the move fails)
        elseif twin and primary == false then
            inst.data = spareData(wep, false)
        else
            inst.data = wep:GetInventoryData() or inst.data
        end
        inst.data.issued, inst.data.loadout = issued, loadout  -- keep the armoury / job marks
    end
end

-- undoCapture(ply, inst): a capture for a leaving copy took the second
-- magazine out of the live gun; the move failed (no room, no spot), so put
-- those rounds back in the gun.
local function undoCapture(ply, inst)
    local back = inst.rhylibSpareClip
    inst.rhylibSpareClip = nil
    if not back or back <= 0 then return end
    local def = Items.defs[inst.id]
    local wep = def and def.weapon and ply:GetWeapon(def.weapon)
    if IsValid(wep) then
        wep:SetClip1(wep:Clip1() + back)
        if inst.data then inst.data.clip = 0 end
    end
end

local function giveWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon or not ply:Alive() or ply:HasWeapon(def.weapon) then return end
    ply.rhylibGiving = true
    local wep = ply:Give(def.weapon, true)
    ply.rhylibGiving = false
    if IsValid(wep) and wep.SetInventoryData then
        wep:SetInventoryData(inst.data)
    end
end

Inv.STOWED = "rhylib_stowed"  -- the empty weapon (lua/weapons/rhylib_stowed.lua)

-- Inv.Stow(ply): put the gun away: hold the empty Stowed weapon (given if missing).
function Inv.Stow(ply)
    if not ply:HasWeapon(Inv.STOWED) then ply:Give(Inv.STOWED) end
    ply:SelectWeapon(Inv.STOWED)
end

local function stripWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    -- Another stack of the same kit is still carried: keep the weapon.
    local st = Inv.states[ply]
    if st then
        for uid, o in pairs(st.byUid) do
            if uid ~= inst.uid and o.id == inst.id then return end
        end
    end
    captureWeapon(ply, inst)
    if ply:HasWeapon(def.weapon) then
        local active = ply:GetActiveWeapon()
        local wasActive = IsValid(active) and active:GetClass() == def.weapon
        ply:StripWeapon(def.weapon)
        if wasActive then Inv.Stow(ply) end
    end
end

-- Inv.CaptureWeapons(ply): writes every carried weapon's live state
-- (clip, magazine, cell, fire mode) into its item. Runs before saving and
-- on death.
function Inv.CaptureWeapons(ply)
    local st = Inv.states[ply]
    if not st then return end
    -- (two copies of one gun: the lowest uid holds the live state)
    local first = {}
    for uid, inst in pairs(st.byUid) do
        if not first[inst.id] or uid < first[inst.id] then first[inst.id] = uid end
    end
    for uid, inst in pairs(st.byUid) do captureWeapon(ply, inst, true, first[inst.id] == uid) end
end

-- Inv.GiveAllWeapons(ply): gives the weapon of every weapon item carried
-- (on spawn), each loaded from its item's data.
function Inv.GiveAllWeapons(ply)
    -- Lowest uid first: of two copies, that one's state is the live gun's.
    local list = {}
    for _, inst in pairs(Inv.Get(ply).byUid) do list[#list + 1] = inst end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    for _, inst in ipairs(list) do giveWeapon(ply, inst) end
end


--------------------------------------------------------------------------
-- Weapon game hooks
--------------------------------------------------------------------------

-- Weapons from the spawn menu, the map or other addons go into the
-- inventory instead of straight into the hands.
Rhylib.Hook.Add("PlayerCanPickupWeapon", "inventory.pickup", function(ply, wep)
    if ply.rhylibGiving then return end
    local class = wep:GetClass()
    local def = Items.defs[class]
    if not def then return end  -- not an inventory weapon: normal behaviour

    if wep.rhylibClaimed then return false end
    -- This hook runs every tick while touching a weapon: remember a "no"
    -- for half a second instead of scanning the grid each time.
    if ply.rhylibPickupNoWep == wep and (ply.rhylibPickupNoUntil or 0) > CurTime() then return false end

    -- Stacking kits from a job loadout only top up to one stack, so
    -- respawning (the inventory survives death) doesn't pile them up.
    if not Items.Unique(def) and ply.rhylibSpawnTick and engine.TickCount() - ply.rhylibSpawnTick <= 2
        and Inv.Count(ply, class) >= Items.StackFor(def, ply) then
        wep.rhylibClaimed = true
        timer.Simple(0, function() if IsValid(wep) then wep:Remove() end end)
        return false
    end
    if not Inv.MayHold(ply, class) then
        ply.rhylibPickupNoWep, ply.rhylibPickupNoUntil = wep, CurTime() + 0.5
        if (ply.rhylibFullNotice or 0) < CurTime() then
            ply.rhylibFullNotice = CurTime() + 2
            Rhylib.Notify(ply, Inv.HoldReason(class), "bad", "Inventory")
        end
        return false
    end
    if not Inv.CanAdd(ply, class) then
        ply.rhylibPickupNoWep, ply.rhylibPickupNoUntil = wep, CurTime() + 0.5
        if (ply.rhylibFullNotice or 0) < CurTime() then
            ply.rhylibFullNotice = CurTime() + 2
            Rhylib.Notify(ply, Inv.AtLimit(ply, class) and Inv.LimitText(ply, class)
                or Items.SlotTakenText(Inv.Get(ply), class) or "No room in your inventory", "bad", "Inventory")
        end
        return false
    end

    -- Given by the job loadout at spawn: marked loadout, so it vanishes
    -- when dropped and can't be given or stored (no "drop kits, die,
    -- respawn" farming).
    local loadout = ply.rhylibSpawnTick and engine.TickCount() - ply.rhylibSpawnTick <= 2
    wep.rhylibClaimed = true
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        -- ply:Give (spawn menu, admin mods) removes a weapon whose pickup
        -- was refused, so it may be gone already; nobody else could take
        -- it (claimed), so it still goes into the inventory.
        local gone = not IsValid(wep)
        -- Add first; the weapon only leaves the ground if it really went in
        -- (the inventory may have filled up during this tick).
        if Inv.AddItem(ply, class, 1, loadout and { issued = true, loadout = true } or {}) == 0 then
            if not gone then wep:Remove() end
            hook.Run("Rhylib.InventoryWeaponPickup", ply, class)
        elseif not gone then
            wep.rhylibClaimed = nil
        end
    end)
    return false
end)

Rhylib.Hook.Add("PlayerSpawn", "inventory.weapons", function(ply)
    ply.rhylibSpawnTick = engine.TickCount()
    timer.Simple(0, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        Inv.GiveAllWeapons(ply)
        Inv.Stow(ply)  -- everyone spawns with their guns stowed
    end)
end)

-- Inventory weapons can't be dropped as plain weapons (DarkRP /drop, drop
-- on death): the item stays in the inventory, so that would duplicate it.
-- Drop from the inventory window instead.
Rhylib.Hook.Add("canDropWeapon", "inventory.nodrop", function(ply, wep)
    if IsValid(wep) and (Items.defs[wep:GetClass()] or wep:GetClass() == Inv.HAND or wep:GetClass() == Inv.STOWED) then return false end
end)

Rhylib.Hook.Add("PlayerDroppedWeapon", "inventory.nodrop", function(ply, wep)
    if not IsValid(wep) or not Items.defs[wep:GetClass()] then return end
    local class = wep:GetClass()
    -- Keep the dropped weapon's clip and cell in the item before it's
    -- given back, or the ammo would roll back to the old values.
    if wep.GetInventoryData then
        for _, inst in pairs(Inv.Get(ply).byUid) do
            if inst.id == class then
                local issued, loadout = inst.data and inst.data.issued, inst.data and inst.data.loadout
                inst.data = wep:GetInventoryData() or inst.data
                inst.data.issued, inst.data.loadout = issued, loadout
                break
            end
        end
    end
    wep.rhylibClaimed = true
    timer.Simple(0, function()
        if IsValid(wep) then wep:Remove() end
        if not (IsValid(ply) and ply:Alive()) then return end
        for _, inst in pairs(Inv.Get(ply).byUid) do
            if inst.id == class then giveWeapon(ply, inst) break end
        end
    end)
end)

-- Keep clip and cell state before the weapons are removed on death.
Rhylib.Hook.Add("DoPlayerDeath", "inventory.capture", function(ply)
    Inv.CaptureWeapons(ply)
    Inv.CancelCombine(ply)
end)

I.twinOf = twinOf
I.captureWeapon = captureWeapon
I.undoCapture = undoCapture
I.giveWeapon = giveWeapon
I.stripWeapon = stripWeapon
