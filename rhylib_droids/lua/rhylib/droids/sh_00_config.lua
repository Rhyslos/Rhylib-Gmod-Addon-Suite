--[[
    Droids: lightweight NextBot enemies that fire real bolts (rhylib_weapons),
    so hits, hit markers and kill markers work like against players.

      B1 battle droid (rhylib_b1): 200 health, E-5 blaster with red bolts,
      now and then a grenade at someone who just ducked behind cover.
      B2 super battle droid (rhylib_b2): tough and slow, wrist blaster, and
      a wrist rocket lobbed high over cover (purple blast).
      Training B1 / B2 (rhylib_b1_training, rhylib_b2_training): the same
      with orange-yellow bolts that only take sim health (rhylib_training).
      Spots players in sight within range (checked a few times a second,
      not every tick), turns, fires short inaccurate bursts, advances when
      far away, chases to where it last saw you, wanders near where it was
      spawned when idle. Walking needs a navmesh (nav_generate); without
      one droids stand and shoot.

    Spawn menu: NPCs tab, "Rhylib Droids" (admins). Droids don't hurt each
    other. At most maxActive droids exist at once.
]]

Rhylib.Droids = Rhylib.Droids or {}
local D = Rhylib.Droids
local Config = Rhylib.Config

Config.Register("droids", "maxActive", 40, "Most droids alive at once (more are removed when spawned)")
Config.Register("droids", "b1Health", 200, "B1 battle droid health")
Config.Register("droids", "b1Speed", 170, "B1 run speed")
Config.Register("droids", "b1Range", 3000, "How far a B1 sees and shoots")
Config.Register("droids", "b1Reaction", 0.6, "Seconds before a B1 starts firing at a new target")
Config.Register("droids", "e5Damage", 12, "E-5 damage per bolt")
Config.Register("droids", "e5RPM", 300, "E-5 shots per minute within a burst")
Config.Register("droids", "e5Spread", 1.2, "E-5 inaccuracy cone (degrees), more against moving targets")

Config.Register("droids", "b1NadeChance", 0.5, "B1: chance to throw a grenade at a target that just went behind cover")
Config.Register("droids", "b1NadeCooldown", 20, "B1: seconds between one droid's grenades")
Config.Register("droids", "b1NadeDamage", 90, "B1 grenade: damage at the centre")
Config.Register("droids", "b1NadeRadius", 260, "B1 grenade: blast radius")

Config.Register("droids", "b2Health", 650, "B2 super battle droid health")
Config.Register("droids", "b2Speed", 115, "B2 walk speed")
Config.Register("droids", "b2Range", 2800, "How far a B2 sees and shoots")
Config.Register("droids", "b2Reaction", 0.8, "Seconds before a B2 starts firing at a new target")
Config.Register("droids", "b2Damage", 14, "B2 wrist blaster damage per bolt")
Config.Register("droids", "b2RPM", 420, "B2 wrist blaster shots per minute within a burst")
Config.Register("droids", "b2Spread", 1.8, "B2 inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "b2RocketDamage", 75, "B2 wrist rocket: damage at the centre")
Config.Register("droids", "b2RocketRadius", 230, "B2 wrist rocket: blast radius")
Config.Register("droids", "b2RocketCooldown", 9, "B2 wrist rocket: seconds between one droid's rockets")
Config.Register("droids", "b2RocketMin", 350, "B2 wrist rocket: closest target it fires at")
Config.Register("droids", "b2RocketMax", 2600, "B2 wrist rocket: furthest target it fires at")
Config.Register("droids", "b2RocketSpread", 70, "B2 wrist rocket: miss distance per 1000 units of range")

Config.Register("droids", "moveSpread", 0.003, "Extra aim cone (degrees) per unit/s the target moves")
Config.Register("droids", "flashSuppress", 3, "Flash charge: droid aim cone multiplier while dazzled")
Config.Register("droids", "flashTime", 5, "Flash charge: seconds droids stay dazzled")

function D.Cfg(k) return Config.Get("droids", k) end

D.B1_MODEL = "models/npc_b1/npc_droid_cis_b1_h.mdl"
D.E5_MODEL = "models/jajoff/sps/cgiweapons/tc13j/e5.mdl"
D.E5_SOUND = "weapons/airboat/airboat_gun_energy2.wav"

D.B2_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid.mdl"
D.B1T_MODEL = "models/aussiwozzi/cgi/b1droids/b1_battledroid_training.mdl"
D.B2T_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid_training.mdl"

--[[
    Droid kinds (ENT.DroidKind). Numbers are config keys. training: yellow
    bolts and blasts that only take sim health (rhylib_training), no kill
    credit. Training droids take normal damage (and training bolts).
]]
D.KINDS = {
    b1 = { name = "B1 battle droid", model = D.B1_MODEL, health = "b1Health", speed = "b1Speed", range = "b1Range", reaction = "b1Reaction",
        damage = "e5Damage", rpm = "e5RPM", spread = "e5Spread", burst = { 2, 3 }, color = 2, gun = D.E5_MODEL, nades = true },
    b2 = { name = "B2 super battle droid", model = D.B2_MODEL, health = "b2Health", speed = "b2Speed", range = "b2Range", reaction = "b2Reaction",
        damage = "b2Damage", rpm = "b2RPM", spread = "b2Spread", burst = { 2, 4 }, color = 2, rockets = true, big = true },
}
D.KINDS.b1t = table.Copy(D.KINDS.b1)
D.KINDS.b1t.name, D.KINDS.b1t.model, D.KINDS.b1t.training, D.KINDS.b1t.color = "B1 training droid", D.B1T_MODEL, true, 8
D.KINDS.b2t = table.Copy(D.KINDS.b2)
D.KINDS.b2t.name, D.KINDS.b2t.model, D.KINDS.b2t.training, D.KINDS.b2t.color = "B2 training droid", D.B2T_MODEL, true, 8

D.CLASSES = { b1 = "rhylib_b1", b2 = "rhylib_b2", b1t = "rhylib_b1_training", b2t = "rhylib_b2_training" }

-- A droid's blaster as rhylib_weapons sees it (BoltColor 2 = red, 8 = training).
D.guns = D.guns or {}
function D.Gun(kind)
    local k = D.KINDS[kind] or D.KINDS.b1
    local g = D.guns[kind]
    if not g then
        g = { BoltSpeed = 6500, BoltColor = k.color, Training = k.training }
        D.guns[kind] = g
    end
    g.Damage = D.Cfg(k.damage)
    return g
end
function D.E5() return D.Gun("b1") end   -- (older callers)

for kind, class in pairs(D.CLASSES) do
    list.Set("NPC", class, {
        Name = D.KINDS[kind].name,
        Class = class,
        Category = "Rhylib Droids",
        AdminOnly = true,
    })
    if CLIENT then language.Add(class, D.KINDS[kind].name) end
end
