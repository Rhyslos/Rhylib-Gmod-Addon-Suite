Rhylib.Weapons = Rhylib.Weapons or {}

local Config = Rhylib.Config
Config.Register("weapons", "handsModel", "models/aussiwozzi/cgi/base/trooper_arms.mdl",
    "First-person arms for everyone (a c_arms model; a DarkRP job's handsModel overrides it; \"\" = the player model's own)")
Config.Register("weapons", "lagCompMax", 0.35, "Max seconds (ping + interpolation) covered by lag compensation on a bolt's first leg")
Config.Register("weapons", "boltSpeedMult", 1.3, "Multiplies every gun's bolt speed (faster = less leading)")
Config.Register("weapons", "recoilMult", 1, "Multiplies every gun's view recoil (SWEP.Recoil)")
Config.Register("weapons", "firstShotMult", 0.35, "Spread of a first shot from rest, as a share of the normal cone")
Config.Register("weapons", "shotRange", 6000, "Players further than this from a shot don't receive it")
Config.Register("weapons", "boltRange", 0, "Bolts stop (no damage, no impact) after this many units; 0 = off, they fly their full life. Scoped guns and rockets never stop early. Admins change it live with rhylib_boltrange")

-- Bolt reach cap in units (0 = none). Clients get it as a Global2Int.
function Rhylib.Weapons.BoltRange()
    if SERVER then return tonumber(Config.Get("weapons", "boltRange")) or 0 end
    return GetGlobal2Int("rhylib_boltRange", 0)
end
Config.Register("weapons", "boltLife", 1.2, "Seconds before a bolt that hit nothing disappears")
Config.Register("weapons", "headMult", 2, "Damage multiplier for head hits")
Config.Register("weapons", "limbMult", 0.75, "Damage multiplier for arm and leg hits")
Config.Register("weapons", "knockMin", 30, "Explosions: damage (before armour) that knocks a player down")
Config.Register("weapons", "knockTimeMin", 2, "Explosions: shortest time a knocked-down player lies there (seconds)")
Config.Register("weapons", "knockTimeMax", 8, "Explosions: longest time (random in between for each knockdown; 0 = knockdowns off)")
Config.Register("weapons", "knockPush", 260, "Explosions: how hard the body is thrown (units/s, more for bigger hits)")
Config.Register("weapons", "knockDropChance", 0.1, "Explosions: chance a knocked-down player drops the gun in their hands (0-1)")

Config.Register("weapons", "lowCellThreshold", 0.1, "Below this power cell charge (0-1), damage starts to drop")
Config.Register("weapons", "lowCellMinDamage", 0.5, "Damage multiplier when the power cell is completely drained")
Config.Register("weapons", "reloadHoldTime", 0.2, "Seconds R must be held to open the reload menu")
Config.Register("weapons", "maxMags", 12, "Without rhylib_inventory: spare magazines of each type a player can carry")
Config.Register("weapons", "maxCells", 4, "Without rhylib_inventory: spare power cells a player can carry")

--[[
    Magazine types. A weapon lists the types it takes in SWEP.Mags (first
    = preferred). The loaded magazine decides how many shots the gun holds,
    so a DC-15A with a small magazine holds 30, with a medium one 60.
    Partly used magazines keep their exact fill (0-1) and don't stack.
    Weight is a shell plus about 5 g per round. Small and medium hold the
    same rounds per inventory cell (60), large packs more for the Z-6.
    A rocket is a one-shot "magazine" for the RPS-6.

    index: sent on the network and stored in the weapon (keep them stable).
]]
local W = Rhylib.Weapons
W.MagTypes = {
    mag_small  = { index = 1, name = "Small magazine",  short = "Small",  rounds = 30,  w = 1, h = 1, stack = 2, weight = 0.5, model = "models/items/boxsrounds.mdl" },
    mag_medium = { index = 2, name = "Medium magazine", short = "Medium", rounds = 60,  w = 1, h = 2, stack = 2, weight = 0.9, model = "models/items/boxmrounds.mdl" },
    mag_large  = { index = 3, name = "Large magazine",  short = "Large",  rounds = 250, w = 1, h = 3, stack = 1, weight = 3.0,  model = "models/items/boxbuckshot.mdl" },
    rocket     = { index = 4, name = "Rocket",          short = "Rocket", rounds = 1,   w = 1, h = 2, stack = 1, weight = 3.5,  model = "models/weapons/w_missile_closed.mdl" },
}
-- Training copies (rhylib_training): same sizes, yellow bolts that only
-- hit "sim health". Training guns take only these; normal guns never do.
W.TRAINING_SUFFIX = "_t"
for id, m in pairs(table.Copy(W.MagTypes)) do
    W.MagTypes[id .. W.TRAINING_SUFFIX] = {
        index = m.index + 4, name = "Training " .. string.lower(m.name), short = "T-" .. m.short, rounds = m.rounds,
        w = m.w, h = m.h, stack = m.stack, weight = m.weight, model = m.model, training = true, base = id,
    }
end
W.MagByIndex = {}
for id, m in pairs(W.MagTypes) do
    m.id = id
    m.ammo = "rhylib_" .. id  -- ammo type that mirrors the count for the HUD
    W.MagByIndex[m.index] = m
end
-- The normal type a magazine copies ("mag_small_t" -> "mag_small").
function W.BaseMag(id)
    local m = W.MagTypes[id]
    return m and m.base or id
end

-- The training copy of a magazine type.
function W.TrainingMag(id)
    return W.MagTypes[id .. W.TRAINING_SUFFIX] and (id .. W.TRAINING_SUFFIX) or id
end

W.CELL = "cell"
W.CELL_WEIGHT = 1.5

-- Reload request sent by the client: 0 = best magazine, 1-14 = that
-- magazine type (index), 15 = power cell.
W.RELOAD_REQ_BITS = 4
W.RELOAD_REQ_CELL = 15

-- Ammo types. Their counts mirror the inventory (or pouch) so the HUD can
-- read spare counts on the client. The inventory is the real store.
local function addAmmo(name)
    game.AddAmmoType({
        name = name,
        dmgtype = DMG_BULLET,
        tracer = TRACER_NONE,
        plydmg = 0,
        npcdmg = 0,
        force = 0,
        maxcarry = 9999,
    })
end
for _, m in pairs(W.MagTypes) do addAmmo(m.ammo) end
addAmmo("rhylib_cell")

-- Inventory items, if rhylib_inventory is installed (it loads before this addon).
if Rhylib.Items then
    for id, m in pairs(W.MagTypes) do
        Rhylib.Items.Register(id, {
            name = m.name,
            w = m.w, h = m.h,
            stack = m.stack,
            fill = true,
            rounds = m.rounds,
            weight = m.weight,
            category = m.training and "training" or "ammo",
            model = m.model,
            training = m.training,
            hand = true,   -- can be held from the hotbar and handed out (rhylib_hand)
        })
    end
    Rhylib.Items.Register("cell", {
        name = "Power cell",
        w = 1, h = 2,
        stack = 1,
        fill = true,
        weight = W.CELL_WEIGHT,
        category = "ammo",
        model = "models/items/battery.mdl",
        hand = true,
    })
end

if CLIENT then
    for _, m in pairs(W.MagTypes) do language.Add(m.ammo .. "_ammo", m.name .. "s") end
    language.Add("rhylib_cell_ammo", "Power cells")
end
