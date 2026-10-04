--[[
    Wearable gear (server): bodygroups follow what's worn, the battalion
    kit at spawn, parts the model can't show come off, the parts' effects,
    and the gear cabinet's stock and unlocks.
]]

local G = Rhylib.Gear

local function Items() return Rhylib.Items end
local function Inv() return Rhylib.Inventory end

-- Option for a group: wanted "on", "down" or "off" (empty if there is one,
-- else left as the model has it).
local function setGroup(ply, g, idx)
    if idx and ply:GetBodygroup(g.id) ~= idx then ply:SetBodygroup(g.id, idx) end
end

-- Bodygroups from what's worn (and optics in use: flipped down).
function G.Apply(ply)
    if not (IsValid(ply) and Items() and Items().WORN_BY_SLOT) then return end
    local info = G.ModelInfo(ply)
    local optics = ply:GetNW2Int("rhylib_optics", 0)
    for slot, part in pairs(G.PARTS) do
        local worn = G.Worn(ply, slot) ~= nil
        local down = worn and ((slot == "binos" and optics == 1) or (slot == "rangefinder" and optics == 2))
        for _, gn in ipairs(part.groups) do
            local g = info.groups[gn]
            if g then
                local idx
                if down then
                    idx = G.Option(g, part.down) or G.Option(g, part.on)
                elseif worn then
                    idx = G.Option(g, part.on)
                else
                    idx = g.opts.empty
                end
                setGroup(ply, g, idx)
            end
        end
    end
    -- Back: the backpack or jetpack you wear.
    local back = Items().SLOT_BACK
    local st = Inv() and Inv().states and Inv().states[ply]
    local inst = st and st.cont[back] and select(2, next(st.cont[back].items))
    for _, gn in ipairs(G.BACK_GROUPS) do
        local g = info.groups[gn]
        if g then
            if inst then
                setGroup(ply, g, G.Option(g, G.BACK_OPTIONS[inst.id]))
            else
                setGroup(ply, g, g.opts.empty)
            end
        end
    end
end

-- Parts this model can't show come off.
function G.TakeOffUnseen(ply)
    local I = Inv()
    if not (I and I.TakeOff) then return end
    for slot in pairs(G.PARTS) do
        local inst = G.Worn(ply, slot)
        if inst and not G.ModelHas(ply, slot) then
            local kept = I.TakeOff(ply, inst.uid)
            local w = Items().WORN[Items().WORN_BY_SLOT[slot]]
            local what = string.lower(w and w.title or slot)
            if kept then
                ply:ChatPrint("Your model has no " .. what .. ": it's in your inventory now")
            elseif inst.data and inst.data.loadout then
                ply:ChatPrint("Your model has no " .. what .. ": handed back")
            else
                ply:ChatPrint("Your model has no " .. what .. ": no room, so it's on the ground")
            end
        end
    end
end

-- Battalion kit: given as job gear; old kit from another battalion goes.
function G.GiveKit(ply)
    local I = Inv()
    if not (I and I.AddItem and I.Get) then return end
    local kit = G.KitFor(ply)
    local st = I.Get(ply)
    local old = {}
    for uid, o in pairs(st.byUid) do
        if G.ITEMS[o.id] and o.data and o.data.loadout and not kit[o.id] then old[#old + 1] = uid end
    end
    for _, uid in ipairs(old) do
        if I.Remove then I.Remove(ply, uid) end
    end
    for id in pairs(kit) do
        if Items().defs[id] and I.Count(ply, id) < 1 then I.AddItem(ply, id, 1, { issued = true, loadout = true }) end
    end
end

local function refresh(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    G.TakeOffUnseen(ply)
    G.Apply(ply)
    ply.rhylibGearModel = ply:GetModel()
end

-- After spawning (DarkRP sets the model during spawn): kit, then bodygroups.
Rhylib.Hook.Add("PlayerSpawn", "gear.spawn", function(ply)
    ply:SetNW2Int("rhylib_optics", 0)
    timer.Simple(0.5, function()
        if not IsValid(ply) or not ply:Alive() then return end
        refresh(ply)
        G.GiveKit(ply)
        G.Apply(ply)
    end)
end)

Rhylib.Hook.Add("Rhylib.InventoryChanged", "gear.apply", function(ply)
    if ply:GetNW2Int("rhylib_optics", 0) ~= 0 and not G.OpticsAllowed(ply, ply:GetNW2Int("rhylib_optics", 0)) then
        ply:SetNW2Int("rhylib_optics", 0)
    end
    -- (no helmet light: the flashlight goes out)
    if G.Cfg("lightNeeded") and ply:FlashlightIsOn() and not G.Worn(ply, "light") then ply:Flashlight(false) end
    G.Apply(ply)
end)

-- A model change without a respawn (some job changes): checked every 2 s.
timer.Create("Rhylib.Gear.Models", 2, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and ply.rhylibGearModel and ply.rhylibGearModel ~= ply:GetModel() then refresh(ply) end
    end
end)

--------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------

local LEGS = { lleg = true, rleg = true }

Rhylib.Hook.Add("Rhylib.BlastPartMult", "gear.kama", function(ply, limb)
    if LEGS[limb] and G.Worn(ply, "kama") then return G.Cfg("kamaBlastMult") end
end)

Rhylib.Hook.Add("Rhylib.FractureChance", "gear.kama", function(ply, limb)
    if LEGS[limb] and G.Worn(ply, "kama") then return G.Cfg("kamaFractureChance") end
end)

Rhylib.Hook.Add("Rhylib.ArmorDrainMult", "gear.pauldron", function(ply)
    if G.Worn(ply, "pauldron") then return G.Cfg("pauldronDrainMult") end
end)

-- The flashlight needs a helmet light.
Rhylib.Hook.Add("PlayerSwitchFlashlight", "gear.light", function(ply, on)
    if on and G.Cfg("lightNeeded") and not G.Worn(ply, "light") then return false end
end)

--------------------------------------------------------------------------
-- Gear cabinet: the parts are stocked; some need a rank or qualification
--------------------------------------------------------------------------

local STOCK_ORDER = { "rhylib_macrobinoculars", "rhylib_rangefinder", "rhylib_helmet_light", "rhylib_holster", "rhylib_kama", "rhylib_pauldron" }

Rhylib.Hook.Add("Rhylib.GearStock", "gear.stock", function(list)
    local have = {}
    for _, id in ipairs(list) do have[id] = true end
    for _, id in ipairs(STOCK_ORDER) do
        if not have[id] and Items().defs[id] then list[#list + 1] = id end
    end
end)

Rhylib.Hook.Add("Rhylib.CanTakeStock", "gear.unlocks", function(ply, storage, id)
    if not G.ITEMS[id] or not storage or storage.kind ~= "depot" then return end
    local ok, why = G.Unlocked(ply, id)
    if not ok then return false, why end
end)
