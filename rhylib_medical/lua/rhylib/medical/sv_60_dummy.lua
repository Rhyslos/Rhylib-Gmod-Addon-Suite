--[[
    Test dummies, server side of the damage (the entity itself is
    lua/entities/rhylib_test_dummy.lua).

    A dummy is a NextBot, not a player, so the engine's player damage
    rules don't apply; these hooks make a hit on it go the player way:
      -400  a dead dummy (the 3 s before it stands up) takes nothing
       100  armour like a player's, only without rhylib_weapons (which
            handles dummies in its own armour hook at 100)
       140  the hit after armour is noted for the damage number; the
            tough dummy shows it and takes nothing (no injuries, no down)
       900  a lethal hit leaves 1 HP and is marked; the dummy "dies" in
            PostEntityTakeDamage (ENT:DummyDie), so the engine never
            kills the NextBot. Downing (medical.down, 150) comes first,
            so this only kills a downed dummy or one with downing off.
    PostEntityTakeDamage 40 (before the injuries at 50): the damage
    number, then the death.

    Damage numbers: net dummy.dmg (server -> players within 1500): dummy
    entity, damage 12 bits, head bool. Drawn by the entity's client part.

    Commands (permission rhylib.medical.dummies, default admin):
      rhylib_dummy_move still|walk|run     every dummy stands, or walks /
                                           runs back and forth
      rhylib_dummy_infect viral|bacterial|poison|cure [load 1-100]
                                           every dummy gets that illness
    State: Med.dummyMove ("still", "walk", "run"; read by the entity).
    Public: Med.DummyArmor().
]]

local Med = Rhylib.Medical

Med.dummyMove = Med.dummyMove or "still"

Rhylib.Net.Register("dummy.dmg")

-- Med.DummyArmor(): the armour a test dummy (re)spawns with: rhylib_weapons'
-- armor spawnArmor setting with it installed, else none (like a player).
function Med.DummyArmor()
    if not (Rhylib.Armor and Rhylib.Armor.Mitigation) then return 0 end
    return math.Clamp(math.floor(tonumber(Rhylib.Config.Get("armor", "spawnArmor")) or 100), 0, 255)
end

local function isDummy(ent) return ent.IsRhylibDummy == true end

-- Damage numbers to players nearby.
local function showDamage(ent, amount, head)
    local n = math.floor(amount + 0.5)
    if n <= 0 then return end
    local near = {}
    local pos = ent:GetPos()
    for _, p in ipairs(player.GetHumans()) do
        if p:GetPos():DistToSqr(pos) < 1500 * 1500 then near[#near + 1] = p end
    end
    if #near == 0 then return end
    Rhylib.Net.Start("dummy.dmg")
    net.WriteEntity(ent)
    net.WriteUInt(math.min(n, 4095), 12)
    net.WriteBool(head)
    net.Send(near)
end

local function isHead(ent, dmg)
    local g = Med.HitGroupOf and Med.HitGroupOf(ent)
    if (not g or g == HITGROUP_GENERIC) and Rhylib.HitGroupAt and bit.band(dmg:GetDamageType(), bit.bor(DMG_BLAST, DMG_BURN, DMG_FALL)) == 0 then
        g = Rhylib.HitGroupAt(ent, dmg:GetDamagePosition())
    end
    return g == HITGROUP_HEAD
end

Rhylib.Hook.Add("EntityTakeDamage", "dummy.dead", function(ent)
    if isDummy(ent) and not ent:Alive() then return true end
end, -400)

-- Armour without rhylib_weapons: the engine's player maths (armour takes
-- 80% of the hit, 1 armour per point; falls, drowning, poison and
-- radiation go straight through). None while down.
local ARMOUR_SKIP = bit.bor(DMG_FALL, DMG_DROWN, DMG_POISON, DMG_RADIATION, DMG_DIRECT)
Rhylib.Hook.Add("EntityTakeDamage", "dummy.armor", function(ent, dmg)
    if not isDummy(ent) or ent.Tough or (Rhylib.Armor and Rhylib.Armor.Mitigation) or ent.rhylibDown then return end
    local armour = ent:Armor()
    local amount = dmg:GetDamage()
    if armour <= 0 or amount <= 0 or bit.band(dmg:GetDamageType(), ARMOUR_SKIP) ~= 0 then return end
    local keep = amount * 0.2
    local soak = amount - keep
    if soak > armour then
        keep = amount - armour
        soak = armour
    end
    ent:SetArmor(armour - soak)
    dmg:SetDamage(keep)
end, 100)

-- After armour: what the number shows. The tough dummy stops here.
Rhylib.Hook.Add("EntityTakeDamage", "dummy.tough", function(ent, dmg)
    if not isDummy(ent) then return end
    ent.rhylibDummyHit = dmg:GetDamage()
    if ent.Tough then
        showDamage(ent, dmg:GetDamage(), isHead(ent, dmg))
        return true
    end
end, 140)

-- Lethal: leave 1 HP, die in PostEntityTakeDamage.
Rhylib.Hook.Add("EntityTakeDamage", "dummy.lethal", function(ent, dmg)
    if not isDummy(ent) then return end
    ent.rhylibDummyLethal = nil
    local hp = ent:Health()
    -- (+1: fractional damage rounds up; medical.down's cut to hp - 1 is not lethal)
    if dmg:GetDamage() + 1 <= hp then return end
    if hp <= 1 then
        ent:SetHealth(2)
        hp = 2
    end
    dmg:SetDamage(hp - 1)
    ent.rhylibDummyLethal = true
end, 900)

Rhylib.Hook.Add("PostEntityTakeDamage", "dummy.numbers", function(ent, dmg, took)
    if not isDummy(ent) or ent.Tough then return end
    local hit = ent.rhylibDummyHit
    ent.rhylibDummyHit = nil
    local lethal = ent.rhylibDummyLethal
    ent.rhylibDummyLethal = nil
    if not took then return end
    -- (no number for bleeding, or for bleeding out / being finished by medical)
    if not ent.rhylibBleedTick and not ent.rhylibDying then showDamage(ent, hit or dmg:GetDamage(), isHead(ent, dmg)) end
    if lethal and ent.DummyDie then ent:DummyDie() end
end, 40)

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

Rhylib.Command.Add({
    name = "rhylib_dummy_move", perm = "rhylib.medical.dummies", minAccess = "admin", tag = "Medical",
    args = "still|walk|run", help = "Make every test dummy stand still, walk or run back and forth",
    fn = function(ply, args)
        local m = string.lower(args[1] or "")
        if m ~= "still" and m ~= "walk" and m ~= "run" then
            return "rhylib_dummy_move still|walk|run (now: " .. Med.dummyMove .. ")", "bad"
        end
        Med.dummyMove = m
        return "Test dummies: " .. m, "good"
    end,
})

Rhylib.Command.Add({
    name = "rhylib_dummy_infect", perm = "rhylib.medical.dummies", minAccess = "admin", tag = "Medical",
    args = "viral|bacterial|poison|cure [load]", help = "Give every test dummy an illness (or cure them)",
    fn = function(ply, args)
        local what = string.lower(args[1] or "")
        local n = 0
        if what == "cure" then
            for d in pairs(Med.dummies) do
                if IsValid(d) and Med.Cure then Med.Cure(d) n = n + 1 end
            end
            return "Test dummies cured: " .. n, "good"
        end
        local kind = Med.ILL_BY_ID and Med.ILL_BY_ID[what]
        if not kind or not Med.Infect then return "rhylib_dummy_infect viral|bacterial|poison|cure [load 1-100]", "bad" end
        if Med.Simple() then return "The simplified medical system is on: no illnesses", "bad" end
        local load = math.Clamp(math.floor(tonumber(args[2]) or 40), 1, 100)
        for d in pairs(Med.dummies) do
            if IsValid(d) and Med.Infect(d, kind, load) then n = n + 1 end
        end
        return "Test dummies infected (" .. what .. ", " .. load .. "): " .. n, "good"
    end,
})
