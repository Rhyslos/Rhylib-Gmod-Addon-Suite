--[[
    Wearable gear (server): bodygroups follow what's worn, the battalion
    kit at spawn, the parts' effects, helmet lights, and the gear
    cabinet's per-player stock and unlocks.
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
    -- Helmet on or off (the inventory's helmet toggle).
    local helmetOn = G.HelmetOn(ply)
    local helm = info.groups.helmet
    if helm then
        local want
        for name, i in pairs(helm.opts) do
            local isHelmet = string.find(name, "helmet", 1, true) ~= nil
            if isHelmet == helmetOn and (not want or i < want) then want = i end
        end
        setGroup(ply, helm, want)
    end
    -- Each group goes to the first worn item (G.ORDER) the model shows
    -- there; groups nothing claims are emptied.
    local want = {}
    for _, id in ipairs(G.ORDER) do
        local sh = G.SHOWS[id]
        local inst = sh and G.Worn(ply, sh.slot)
        -- (binoculars, rangefinder, lights and visor sit on the helmet)
        if inst and inst.id == id and (helmetOn or not G.ON_HELMET[sh.slot]) then
            local down = sh.optics and optics == sh.optics
            for _, gn in ipairs(sh.groups) do
                local g = info.groups[gn]
                if g and want[gn] == nil then
                    local idx = (down and G.Option(g, sh.down)) or G.Option(g, sh.on)
                    if idx then want[gn] = idx end
                end
            end
        end
    end
    for gn in pairs(G.ALL_GROUPS) do
        local g = info.groups[gn]
        if g then setGroup(ply, g, want[gn] or g.opts.empty) end
    end
    -- Hair and facial hair (rhylib_roster looks): only with the helmet off,
    -- they poke through it otherwise.
    for gn, var in pairs({ hair = "rhylib_hair", fhair = "rhylib_fhair" }) do
        local g = info.groups[gn]
        if g then
            local want = ply:GetNW2String(var, gn == "hair" and "hair_reg" or "")
            setGroup(ply, g, (not helmetOn and want ~= "" and g.opts[want]) or g.opts.empty)
        end
    end
    -- Hair colour (rhylib_roster looks): the hair material swapped for a
    -- tinted copy every client makes (cl_15_look.lua).
    local R = Rhylib.Roster
    if R and R.HairMatName then
        for i, m in ipairs(ply:GetMaterials() or {}) do
            local l = string.lower(m)
            if string.sub(l, -5) == "/hair" or l == "hair" then
                -- (only with the helmet off: owner saw the helmet take the hair colour,
                -- and the hair is hidden under it anyway)
                local col = helmetOn and 0 or ply:GetNW2Int("rhylib_haircol", 0)
                local want = col > 0 and ("!" .. R.HairMatName(m, col)) or ""
                if (ply:GetSubMaterial(i - 1) or "") ~= want then ply:SetSubMaterial(i - 1, want) end
                break
            end
        end
    end
    -- Skin (rhylib_roster looks), where the model has that many.
    local skin = ply:GetNW2Int("rhylib_skin", 0)
    if skin < (ply:SkinCount() or 1) and ply:GetSkin() ~= skin then ply:SetSkin(skin) end

end

-- Battalion kit: given as job gear; old kit from another battalion goes.
function G.GiveKit(ply)
    local I = Inv()
    if not (I and I.AddItem and I.Get) then return end
    local kit = G.KitFor(ply)
    local st = I.Get(ply)
    local old = {}
    -- Old kit only goes once you're in a battalion job: joining spawns you
    -- as a cadet for a moment, which mustn't strip the 327th's kama.
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    local inBattalion = job and isstring(job.battalion) and job.battalion ~= ""
    for uid, o in pairs(inBattalion and st.byUid or {}) do
        if G.ITEMS[o.id] and o.data and o.data.loadout and not kit[o.id] then old[#old + 1] = uid end
    end
    for _, uid in ipairs(old) do
        if I.Remove then I.Remove(ply, uid) end
    end
    for id in pairs(kit) do
        if Items().defs[id] and I.Count(ply, id) < 1 then I.AddItem(ply, id, 1, { issued = true, loadout = true }) end
    end
end

-- May the helmet lights be on? (Worn and shown, or anyone with the
-- helmet on when config lightNeeded is off.)
function G.LightsAllowed(ply)
    if G.Worn(ply, "binos") or G.Worn(ply, "rangefinder") then return false end   -- (one or the other)
    return G.Active(ply, "light") or (not G.Cfg("lightNeeded") and G.HelmetOn(ply))
end
local lightsAllowed = G.LightsAllowed

-- Optics and lights go off once the gear behind them stops working.
local function checkUse(ply)
    local o = ply:GetNW2Int("rhylib_optics", 0)
    if o ~= 0 and not G.OpticsAllowed(ply, o) then
        ply:SetNW2Int("rhylib_optics", 0)
        ply:SetNW2Bool("rhylib_opticsFire", false)
    end
    if not lightsAllowed(ply) then G.SetLights(ply, false) end
end

local function refresh(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    -- A new model: sub-materials stay on their index, so the old model's
    -- hair colour could land on another part (a helmet) of the new one.
    if ply.rhylibGearModel and ply.rhylibGearModel ~= ply:GetModel() then ply:SetSubMaterial() end
    checkUse(ply)
    G.Apply(ply)
    ply.rhylibGearModel = ply:GetModel()
end

-- After spawning (DarkRP sets the model during spawn): kit, then bodygroups.
Rhylib.Hook.Add("PlayerSpawn", "gear.spawn", function(ply)
    ply:SetNW2Int("rhylib_optics", 0)
    ply:SetNW2Bool("rhylib_opticsFire", false)
    timer.Simple(0.5, function()
        if not IsValid(ply) or not ply:Alive() then return end
        refresh(ply)
        G.GiveKit(ply)
        G.Apply(ply)
    end)
end)

Rhylib.Hook.Add("Rhylib.InventoryChanged", "gear.apply", function(ply)
    checkUse(ply)
    G.Apply(ply)
end)

-- A model change without a respawn (some job changes): checked every second.
timer.Create("Rhylib.Gear.Models", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and ply.rhylibGearModel and ply.rhylibGearModel ~= ply:GetModel() then refresh(ply) end
    end
end)

--------------------------------------------------------------------------
-- Helmet on / off (inventory toggle). Off: hair shows, the helmet-mounted
-- parts can't be used, and a headshot downs you whatever hits you.
--------------------------------------------------------------------------

Rhylib.Net.Receive("gear.helmet", function(ply)
    if not ply:Alive() or not G.ModelInfo(ply).groups.helmet then return end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and Med.IsDown(ply) then return end
    ply:SetNW2Bool("rhylib_helmetOff", not ply:GetNW2Bool("rhylib_helmetOff", false))
    if not G.HelmetOn(ply) then
        if G.SetOptics then G.SetOptics(ply, 0) end
        G.SetLights(ply, false)
    end
    ply:EmitSound("items/ammo_pickup.wav", 50, 90)
    G.Apply(ply)
end, { rate = 3, burst = 3 })

Rhylib.Hook.Add("PlayerSpawn", "gear.helmet", function(ply)
    ply:SetNW2Bool("rhylib_helmetOff", false)
    G.SetLights(ply, false)
end)
Rhylib.Hook.Add("PostPlayerDeath", "gear.lights", function(ply) G.SetLights(ply, false) end)

-- No helmet: a head hit downs you (before armour, priority 100, and medical).
Rhylib.Hook.Add("EntityTakeDamage", "gear.headshot", function(ply, dmg)
    if not (ply:IsPlayer() and G.Cfg("bareHeadshotDowns") and not G.HelmetOn(ply) and ply:Alive()) then return end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and Med.IsDown(ply) then return end
    -- (bolts set rhylibHitGroup; the engine's LastHitGroup only counts for bullets, it lingers)
    local group = ply.rhylibHitGroup
    if not group and bit.band(dmg:GetDamageType(), DMG_BULLET) ~= 0 then group = ply:LastHitGroup() end
    if group == HITGROUP_HEAD and dmg:GetDamage() > 0 then
        dmg:SetDamage(math.max(dmg:GetDamage(), ply:Health() + ply:Armor() * 10 + 1000))
    end
end, 80)

-- New looks from rhylib_roster: put them on.
Rhylib.Hook.Add("EntityNetworkedVarChanged", "gear.looks", function(ent, name)
    if (name == "rhylib_hair" or name == "rhylib_fhair" or name == "rhylib_skin" or name == "rhylib_haircol") and IsValid(ent) and ent:IsPlayer() then
        timer.Simple(0, function() if IsValid(ent) then G.Apply(ent) end end)
    end
end)

--------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------

local LEGS = { lleg = true, rleg = true }

Rhylib.Hook.Add("Rhylib.BlastPartMult", "gear.kama", function(ply, limb)
    if LEGS[limb] and G.Active(ply, "kama") then return G.Cfg("kamaBlastMult") end
end)

Rhylib.Hook.Add("Rhylib.FractureChance", "gear.kama", function(ply, limb)
    if LEGS[limb] and G.Active(ply, "kama") then return G.Cfg("kamaFractureChance") end
end)

Rhylib.Hook.Add("Rhylib.ArmorDrainMult", "gear.pauldron", function(ply)
    if G.Active(ply, "pauldron") then return G.Cfg("pauldronDrainMult") end
end)

--------------------------------------------------------------------------
-- Helmet lights: the flashlight key switches two forward beams
-- (NW2Bool rhylib_lights, drawn by every client in cl_40_lights.lua)
-- instead of the engine flashlight. Without config lightNeeded, anyone
-- may use them.
--------------------------------------------------------------------------

function G.SetLights(ply, on)
    on = on and true or false
    if ply:GetNW2Bool("rhylib_lights", false) == on then return end
    ply:SetNW2Bool("rhylib_lights", on)
    ply:EmitSound("items/flashlight1.wav", 55, on and 105 or 90)
end

local function toggleLights(ply)
    -- (with optics up the flashlight key is night vision: cl_30_optics)
    if ply:GetNW2Int("rhylib_optics", 0) ~= 0 then return end
    if ply:Alive() and lightsAllowed(ply) then
        G.SetLights(ply, not ply:GetNW2Bool("rhylib_lights", false))
    end
end

-- The helmet gear key (default L, cl_30_optics) and the flashlight key both switch them.
Rhylib.Net.Receive("gear.lights", function(ply) toggleLights(ply) end, { rate = 4, burst = 4 })

Rhylib.Hook.Add("PlayerSwitchFlashlight", "gear.light", function(ply, on)
    if ply:FlashlightIsOn() then ply:Flashlight(false) end
    toggleLights(ply)
    return false
end)

--------------------------------------------------------------------------
-- Gear cabinet: the parts are stocked; some need a rank or qualification
--------------------------------------------------------------------------

-- The cabinet shows each player only what they may take and their model
-- shows (rhylib_armoury asks per player). Order as G.ORDER.
Rhylib.Hook.Add("Rhylib.GearStockFor", "gear.stock", function(ply, list)
    local have = {}
    for _, id in ipairs(list) do have[id] = true end
    for _, id in ipairs(G.ORDER) do
        if G.ITEMS[id] and not have[id] and Items().defs[id] and G.ItemShown(ply, id) and G.Unlocked(ply, id) then
            list[#list + 1] = id
        end
    end
end)

Rhylib.Hook.Add("Rhylib.GearReturnable", "gear.stock", function(set)
    for id in pairs(G.ITEMS) do set[id] = true end
end)

Rhylib.Hook.Add("Rhylib.CanTakeStock", "gear.unlocks", function(ply, storage, id)
    if not G.ITEMS[id] or not storage or storage.kind ~= "depot" then return end
    local ok, why = G.Unlocked(ply, id)
    if not ok then return false, why end
end)
