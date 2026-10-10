--[[
    What the skills do (shared, so firing and movement stay predicted).
    Other addons ask these when rhylib_skills is installed; without it
    nothing is gated (every fire mode, scope and item works). Callers
    always guard: `local K = Rhylib.Skills  if K and K.X then ... end`.

        K.ModeAllowed(ply, wep, mode)    skill-gated fire modes (SWEP.SkillModes)    weapons: rhylib_base
        K.ScopeAllowed(ply, wep)         SWEP.ScopeSkill                             weapons: rhylib_base
        K.RunAndGun(ply, wep)            fire while sprinting                        weapons: rhylib_base
        K.SpreadMult(ply, wep)           cone multiplier                             weapons: sh_10_spread
        K.RecoilMult(ply, wep)           view kick multiplier                        weapons: cl_50_recoil, cl_70_stats
        K.FireRateMult(ply, wep, mode)   fire rate multiplier                        weapons: rhylib_base
        K.ReloadMult(ply, wep, cell)     reload time multiplier                      weapons: rhylib_base; republic: grenade launcher
        K.DrawMult(ply, wep)             draw time multiplier (Quick draw)           weapons: rhylib_base
        K.MagBonus(ply, magId)           extra rounds per magazine                   weapons: rhylib_base
        K.CellMult(ply)                  power cell shots multiplier                 weapons: rhylib_base, cl_70_stats
        K.CellDrainMult(ply, wep)        cell drain per shot (Overcharge)            weapons: rhylib_base, cl_70_stats
        K.ModeDamageMult(ply, wep)       fire mode damage (Overcharge)               weapons: cl_70_stats
        K.ShotDamageMult(ply, wep)       per shot (First shot, Overcharge)           weapons: rhylib_base
        K.SpinMoveMult(ply, wep, base)   walk speed while the barrels spin           weapons: rhylib_base
        K.MagAllowed(ply, wep, magId)    SWEP.MagSkills (Heavy feed: Z-6 large mags) weapons: rhylib_base, cl_70_stats
        K.PelletConeMult(ply, wep)       shotgun pellet cone (Shotgun drills)        weapons: rhylib_base
        K.FlyFire(ply, wep)              DP-23 fires while flying                    weapons: rhylib_base
        K.WeightPenaltyMult(ply)         weight stamina penalty                      stamina: sh_00_config
        K.FreeSprint(ply)                sprinting costs nothing                     stamina: sh_10_move
        K.RegenMult(ply)                 stamina refill multiplier                   stamina: sh_10_move
        K.AdjustWeight(ply, state, weight, cap)  carry weight and limit              inventory: sv_10_inventory, cl_20_panel
        K.JetCfg(ply, key, value)        jetpack settings per player (Airborne)      jetpack: sh_10_move
        K.GrenadeMults(ply)              thrown grenades (Grenadier)                 republic: rhylib_grenade_base
        K.DemoMults(ply)                 thermal / HE charge blasts (EOD)            republic: grenade base, HE charge, launcher
        K.Airborne(ply)                  has any Airborne skill                      (this addon)
        K.Hovering(ply)                  hovering on the jetpack (Hover)             (this addon)
    Server-only effects (sv_10_skills.lua): K.DamageMult (weapons:
    sv_10_bolts), K.ExtraGrids (inventory). Command orders: sh_20_command.
    Numbers are config "skills" values so they can be tuned without code.
]]

local K = Rhylib.Skills
local Config = Rhylib.Config

-- Every effect number. Multipliers: 1 = no change, below 1 = less (spread,
-- kick, time, damage taken), above 1 = more. Distances are Hammer units
-- (about 52 to a metre).
local function reg(key, val, desc) Config.Register("skills", key, val, desc) end
reg("quickHandsMult", 0.9, "Quick hands: magazine reload time multiplier")
reg("runGunSpread", 1.6, "Run and gun: spread multiplier while sprinting and firing")
reg("pointBlankMult", 1.25, "Point blank: damage multiplier up close")
reg("pointBlankNear", 420, "Point blank: full bonus within this many units (420 = 8 m)")
reg("pointBlankFar", 790, "Point blank: no bonus beyond this many units (790 = 15 m)")
reg("lightKitSpeed", 1.05, "Light kit: speed multiplier")
reg("lightKitLoad", 0.6, "Light kit: only under this share of your carry limit")
reg("momentumTime", 4, "Momentum: seconds of free sprinting after a kill")
reg("momentumReload", 0.75, "Momentum: next reload time multiplier")
reg("extMagBonus", 10, "Extended mags: extra rounds in a medium magazine")
reg("effCellsMult", 1.25, "Efficient cells: power cell shots multiplier")
reg("loadBearerCarry", 6, "Load bearer: extra carry limit (kg)")
reg("loadBearerPenalty", 0.75, "Load bearer: weight stamina penalty multiplier")
reg("cellRack", { 5, 2 }, "Load bearer: cell rack size in inventory cells (cells are 1x2, so 5x2 = 5 cells)")
reg("gunRunnerSpin", 0.9, "Gun runner: walk speed while the Z-6 spins (normally 0.6)")
reg("gunRunnerWeight", 0.5, "Gun runner: Z-6 weight multiplier")
reg("steadySpread", 0.45, "Steady barrels: Z-6 spread multiplier")
reg("steadyRecoil", 0.45, "Steady barrels: Z-6 view kick multiplier")
reg("rapidFireRPM", 600, "Rapid fire: DC-15S fire rate")
reg("pistolSpread", 0.8, "Pistol proficiency: DC-17 spread multiplier")
reg("steadyGripRecoil", 0.5, "Steady grip: pistol view kick multiplier (DC-17, and the DC-15S in Sidearm mode)")
reg("dualRate", 1, "Dual DC-17: fire rate multiplier (the gain is the second magazine)")
reg("critChance", 0.1, "Critical hits: chance per hit")
reg("critMult", 1.5, "Critical hits: damage multiplier")
reg("lightRoundsChance", 0.15, "Light rounds: crit chance with a small magazine loaded (doesn't stack with Critical hits)")
reg("quickDrawMult", 0.6, "Quick draw: draw time multiplier")
reg("speedLoaderMult", 0.7, "Speed loader: pistol reload time multiplier")
reg("markTime", 15, "Mark target: seconds a mark lasts")
reg("markRange", 8000, "Mark target: reach (units)")
reg("markCooldown", 1, "Mark target: seconds between marks")
reg("markMax", 5, "Mark target: most enemies one Q marks through macrobinoculars / a rangefinder")
reg("markOpticsCone", 10, "Mark target: widest cone (degrees from the middle) searched through optics")
reg("visorSpotEvery", 5, "Mark target + sun visor down: seconds between automatic spots")
reg("visorSpotCone", 30, "Mark target + sun visor down: cone (degrees from the middle) the automatic spot searches")
reg("visorSpotTime", 6, "Mark target + sun visor down: seconds an automatic spot lasts")
reg("markAimCone", 3, "Mark target: without optics, the nearest enemy within this many degrees of the crosshair counts")
reg("markLockDamage", 1.15, "Tactical visor: damage multiplier for the marker's squad mates (not Marksmen) on a locked target")
reg("markLockTime", 25, "Tactical visor: seconds a lock (a Q mark) lasts")
reg("squadSkillRange", 600, "Field logistics / Steady the line: reach around the commander (units, 600 = about 15 m)")
reg("logiReload", 0.85, "Field logistics: reload time multiplier near the commander")
reg("lineKick", 0.85, "Steady the line: view kick multiplier near the commander")
reg("lineRegen", 1.25, "Steady the line: stamina refill multiplier near the commander")
reg("rifleDrillSpread", 0.8, "Rifle drill: aimed spread multiplier (rifles and carbines)")
reg("vetRifle", 0.9, "Combat veteran: rifle spread, kick and reload time multiplier")
reg("vetCarbineDamage", 1.08, "Combat veteran: carbine damage multiplier")
reg("vetZ6Resist", 0.9, "Combat veteran: damage taken multiplier with the Z-6 in hand")
reg("markVisorCone", 10, "Mark target: Q with the sun visor down locks the ringed enemy if it's within this many degrees of the aim")
reg("undoWindow", 120, "Seconds after learning a skill in which right-click can undo it (any time while reset is allowed)")
reg("rushDamage", 1.25, "Battle rush: damage multiplier")
reg("rushTime", 5, "Battle rush: seconds it lasts after the first hit")
reg("rushCooldown", 60, "Battle rush: seconds before it can trigger again")
reg("grenadeRange", 1.2, "Grenadier: throw distance multiplier")
reg("grenadeDamage", 1.3, "Grenadier: frag damage multiplier")
reg("grenadeRadius", 1.1, "Grenadier: blast radius multiplier (frag, EMP, flash)")
reg("sidearmDamage", 1.06, "Carbine sidearm: DC-15S damage multiplier in Sidearm mode")
reg("airborneFuel", 15, "Airborne: jetpack seconds of thrust with any Airborne skill (others: jetpack fuelTime)")
reg("fallMult", 0.5, "Hard landings: fall damage multiplier")
reg("tankMult", 1.4, "Extended tanks: fuel time and refill speed multiplier")
reg("springJump", 1.2, "Hard landings: jump power multiplier")
reg("hoverFuelMult", 0.5, "Hover: jetpack fuel burn multiplier while hovering")
reg("hoverSpread", 0.75, "Hover: spread multiplier while hovering")
reg("hoverRecoil", 0.75, "Hover: view kick multiplier while hovering")
reg("afterburnerMult", 1.25, "Afterburner: jetpack climb, steering and top speed multiplier")
reg("combatDropAir", 7, "Combat drop: seconds of jetpack flight needed before a landing counts")
reg("combatDropTime", 5, "Combat drop: seconds of reduced damage after landing")
reg("combatDropMult", 0.5, "Combat drop: damage multiplier while it lasts")
reg("sidestepSpeed", 340, "Sidestep: dash speed (units/s)")
reg("sidestepTime", 0.18, "Sidestep: seconds at full dash speed, then it slows to sidestepCarry")
reg("sidestepCarry", 60, "Sidestep: sideways speed kept after the burst (units/s)")
reg("sidestepCooldown", 2.5, "Sidestep: seconds between dashes")
reg("sidestepStamina", 25, "Sidestep: stamina per dash")
reg("lightMagBonus", 20, "Light mags: extra rounds in a small magazine")
reg("blastMult", 0.7, "Blast hardened: explosion damage multiplier")
reg("airMult", 0.8, "Aerial stability: damage multiplier while off the ground")
reg("slamSpeed", 500, "Death from above: landing speed needed (units/s)")
reg("slamRadius", 220, "Death from above: radius (units)")
reg("slamDamage", 60, "Death from above: damage at the centre (more for faster landings)")
reg("underFireMult", 0.8, "Under fire: damage multiplier while reviving or treating")
reg("stanceSpread", 0.8, "Steady stance: spread multiplier while crouched")
reg("steadyAimSpread", 0.75, "Steady aim: spread multiplier while aiming")
reg("headhunterMult", 1.25, "Headhunter: headshot damage multiplier")
reg("boltDrillsRate", 1.2, "Bolt drills: DC-15X fire rate multiplier")
reg("longGunWeight", 0.75, "Long gun: DC-15X weight multiplier")
reg("carbineSpread", 0.7, "Carbine discipline: DC-15S spread multiplier while aiming")
reg("carbineRecoil", 0.85, "Carbine discipline: DC-15S view kick multiplier")
reg("carbineDraw", 0.7, "Carbine discipline: DC-15S draw time multiplier")
reg("calledShotTime", 6, "Called shot: seconds a headshot mark lasts")
reg("priorityMult", 1.2, "Priority target: damage multiplier on heavy droids and marked targets")
reg("rhythmStep", 0.05, "Precision rhythm: extra damage per DC-15S hit in a row")
reg("rhythmMax", 2, "Precision rhythm: most steps (2 x 0.05 = +10%); only while aiming")
reg("overchargeDamage", 1.3, "Overcharge: DC-15A damage multiplier")
reg("overchargeDrain", 4, "Overcharge: power cell drain multiplier")
reg("overchargeKick", 1.15, "Overcharge: view kick multiplier")
reg("sustainKick", 0.6, "Sustained fire: view kick multiplier once fully settled")
reg("sustainRamp", 1.5, "Sustained fire: seconds of continuous fire to settle fully (eased)")
reg("sustainStep", 0.02, "Sustained fire: extra damage per DC-15A hit in a row on one target")
reg("sustainMax", 5, "Sustained fire: most steps (5 x 0.02 = +10%)")
reg("sustainWindow", 0.4, "Sustained fire: seconds between hits to keep the streak")
reg("rhythmWindow", 1.5, "Precision rhythm: seconds between hits to keep the streak")
reg("firstShotWait", 3, "First shot: seconds without firing before it's ready")
reg("firstShotMult", 1.5, "First shot: damage multiplier with the DC-15X")
reg("firstShotOther", 1.3, "First shot: damage multiplier with other guns")
reg("firstShotSpread", 0.05, "First shot: spread multiplier")
reg("reinforcedHealth", 25, "Reinforced: extra max health")
reg("plantedMult", 0.5, "Planted: Z-6 spread and kick multiplier while crouched")
reg("ammoBelt", { 5, 1 }, "Ammo belt: size in inventory cells")
reg("shotgunDamage", 1.3, "Shotgun drills: DP-24 pellet damage multiplier")
reg("shotgunCone", 0.8, "Shotgun drills: DP-24 pellet cone multiplier")
reg("sidearmWeight", 0.5, "Shotgun drills: weight multiplier for guns 4 cells long or shorter")
reg("juggernautMult", 0.85, "Juggernaut: damage multiplier")
reg("suppressRadius", 300, "Suppression: droids this close to one you hit with the Z-6 aim worse (units)")
reg("suppressMult", 1.8, "Suppression: droid aim cone multiplier")
reg("suppressTime", 3, "Suppression: seconds it lasts")
reg("holdLineMult", 0.8, "Hold the line: damage multiplier with the shield up and another MP near")
reg("holdLineRange", 200, "Hold the line: how close the other MP must be (units)")
reg("bashDamage", 30, "Shield bash: damage to droids")
reg("searchMult", 1.2, "Thorough search: search roll multiplier")
-- EOD (Field technician, 2026-10-10)
reg("eodBlastMult", 0.7, "EOD Blast hardened: explosion damage multiplier")
reg("eodPackWeight", 0.5, "EOD Explosives pack: weight multiplier of grenades, charges, rockets and mines")
reg("eodPackStack", 1, "EOD Explosives pack: extra per stack of grenades, charges and mines")
reg("eodDemoDamage", 1.25, "EOD Demolitions: thermal detonator and HE charge damage multiplier")
reg("eodDemoRadius", 1.15, "EOD Demolitions: thermal detonator and HE charge blast radius multiplier")
reg("eodAntiArmour", 1.25, "EOD Anti-armour: explosive damage multiplier against B2s, heavy and commander droids")

local function cfg(k) return Config.Get("skills", k) end

-- Weapon classes the effects check (K.GunClass compares against these).
K.Z6 = "rhylib_z6"
K.DC15X = "rhylib_dc15x"
K.DP24 = "rhylib_dp24"
K.DC15S = "rhylib_dc15s"
K.DC15A = "rhylib_dc15a"

-- K.GunClass(wep): the gun a weapon counts as for skills (training copies
-- count as the real one, via SWEP.TrainingOf).
function K.GunClass(wep)
    return wep.TrainingOf or wep:GetClass()
end

-- K.ItemGun(itemId): the same for an inventory item id (weapon class).
-- K.PISTOLS: classes that count as pistols (Pistol proficiency, Steady
-- grip, Speed loader).
function K.ItemGun(id)
    local w = weapons.GetStored(id)
    return w and w.TrainingOf or id
end
K.PISTOLS = { rhylib_dc17 = true }

-- Gun type from the weapon's InvGroup (rifle: DC-15A, Westar-M5; carbine:
-- DC-15S, DP-23; training copies inherit it).
function K.IsRifle(wep) return IsValid(wep) and wep.InvGroup == "rifle" end
function K.IsCarbine(wep) return IsValid(wep) and wep.InvGroup == "carbine" and not wep.RiotShield end   -- (the shield is a DC-15S underneath)

local function isPly(p) return IsValid(p) and p:IsPlayer() end

-- K.ModeAllowed(ply, wep, mode): may ply use this fire mode? A mode named
-- in SWEP.SkillModes = { mode = skillId } needs that skill; other modes
-- are always allowed. Non-players can't use gated modes.
-- Example (SWEP): SWEP.SkillModes = { auto = "full_auto" }
function K.ModeAllowed(ply, wep, mode)
    local need = wep.SkillModes and wep.SkillModes[mode]
    if not need then return true end
    if not isPly(ply) then return false end
    -- Combat veteran: the DC-15A's full auto too.
    if need == "full_auto" and K.Has(ply, "combat_veteran") then return true end
    return K.Has(ply, need)
end

-- K.ScopeAllowed(ply, wep): may ply look through this gun's scope?
-- SWEP.ScopeSkill = skill id (DC-15X: "long_gun"); no field = always.
function K.ScopeAllowed(ply, wep)
    if not wep.ScopeSkill then return true end
    return isPly(ply) and K.Has(ply, wep.ScopeSkill)
end

-- K.RunAndGun(ply, wep): true if ply may fire while sprinting (Run and gun).
function K.RunAndGun(ply, wep)
    return isPly(ply) and K.Has(ply, "run_gun")
end

local function sprinting(ply, wep)
    return wep.OwnerSprinting and wep:OwnerSprinting(ply) or false
end

-- K.SpreadMult(ply, wep): multiplier on every cone of this gun right now
-- (sprint-firing, Steady barrels, Pistol proficiency, Steady stance,
-- Planted, Steady aim, Carbine discipline, Rifle drill, Combat veteran,
-- Hover, First shot). Called in predicted code, so only shared state.
function K.SpreadMult(ply, wep)
    if not isPly(ply) then return 1 end
    local set = K.Set(ply)
    if next(set) == nil then return 1 end
    local m = 1
    local class = K.GunClass(wep)
    local steady = class == K.Z6 and set.steady_barrels and sprinting(ply, wep)
    if steady then m = m * cfg("steadySpread") end
    if set.run_gun and not steady and sprinting(ply, wep) then m = m * cfg("runGunSpread") end
    if set.pistol_prof and K.PISTOLS[class] then m = m * cfg("pistolSpread") end
    local crouched = ply:Crouching()
    if set.steady_stance and crouched then m = m * cfg("stanceSpread") end
    if set.planted and crouched and class == K.Z6 then m = m * cfg("plantedMult") end
    local aiming = wep.GetAiming and wep:GetAiming()
    if set.steady_aim and aiming then m = m * cfg("steadyAimSpread") end
    if set.carbine_disc and aiming and class == K.DC15S then m = m * cfg("carbineSpread") end
    if set.rifle_drill and aiming and (K.IsRifle(wep) or K.IsCarbine(wep)) then m = m * cfg("rifleDrillSpread") end
    if set.combat_veteran and K.IsRifle(wep) then m = m * cfg("vetRifle") end
    if set.hover and K.Hovering(ply) then m = m * cfg("hoverSpread") end
    if set.first_shot and K.FirstShotReady(ply, wep) then m = m * cfg("firstShotSpread") end
    return m
end

-- K.RecoilMult(ply, wep): view kick multiplier (Steady grip, Focus fire,
-- Carbine discipline, Hover, Combat veteran, Steady the line, Overcharge,
-- Sustained fire, Steady barrels, Planted).
function K.RecoilMult(ply, wep)
    if not isPly(ply) then return 1 end
    local m = 1
    -- Steady grip: pistols kick half as much (the DC-15S held as a sidearm too).
    if K.Has(ply, "steady_grip") and (K.PISTOLS[K.GunClass(wep)]
        or (wep.GetFireModeName and wep:GetFireModeName() == "sidearm")) then
        m = m * cfg("steadyGripRecoil")
    end
    if K.OrderIs(ply, "focus") then m = m * cfg("focusRecoil") end   -- (command order)
    if K.GunClass(wep) == K.DC15S and K.Has(ply, "carbine_disc") then m = m * cfg("carbineRecoil") end
    if K.Has(ply, "hover") and K.Hovering(ply) then m = m * cfg("hoverRecoil") end
    if K.Has(ply, "combat_veteran") and K.IsRifle(wep) then m = m * cfg("vetRifle") end
    if ply:GetNW2Bool("rhylib_steadyLine", false) then m = m * cfg("lineKick") end   -- (Steady the line)
    local mode = wep.GetFireModeName and wep:GetFireModeName()
    if mode == "overcharge" then m = m * cfg("overchargeKick") end
    -- Sustained fire: the kick eases down (smoothstep) the longer a DC-15A
    -- full-auto spray lasts (rhylib_base notes rhylibSprayStart per shot).
    if wep.AutoModes and wep.AutoModes[mode] and wep.rhylibSprayStart and K.GunClass(wep) == K.DC15A
        and CurTime() - (wep.rhylibLastShot or 0) <= 0.3
        and K.Has(ply, "sustained_fire") then
        local t = math.Clamp((CurTime() - wep.rhylibSprayStart) / cfg("sustainRamp"), 0, 1)
        m = m * (1 - (1 - cfg("sustainKick")) * t * t * (3 - 2 * t))
    end
    if K.GunClass(wep) == K.Z6 then
        if K.Has(ply, "steady_barrels") and sprinting(ply, wep) then m = m * cfg("steadyRecoil") end
        if K.Has(ply, "planted") and ply:Crouching() then m = m * cfg("plantedMult") end
    end
    return m
end

-- First shot: aiming a single-bolt gun, and nothing fired from it for a
-- while (the predicted KickTime, so client and server agree).
function K.FirstShotReady(ply, wep)
    if wep.Pellets or not (wep.GetAiming and wep:GetAiming() and wep.GetKickTime) then return false end
    if not K.Has(ply, "first_shot") then return false end
    return CurTime() - wep:GetKickTime() >= cfg("firstShotWait")
end

-- Fire mode damage (Overcharge); also shown by the C stats panel.
function K.ModeDamageMult(ply, wep)
    if wep.GetFireModeName and wep:GetFireModeName() == "overcharge" then return cfg("overchargeDamage") end
    return 1
end

-- Power cell drain multiplier per shot (Overcharge).
function K.CellDrainMult(ply, wep)
    if wep.GetFireModeName and wep:GetFireModeName() == "overcharge" then return cfg("overchargeDrain") end
    return 1
end

-- Called by the weapon base for each shot, before the shot is recorded:
-- damage multiplier for this shot (First shot, Overcharge).
function K.ShotDamageMult(ply, wep)
    local m = K.ModeDamageMult(ply, wep)
    if isPly(ply) and K.FirstShotReady(ply, wep) then
        m = m * (K.GunClass(wep) == K.DC15X and cfg("firstShotMult") or cfg("firstShotOther"))
    end
    return m
end

-- Heavy feed: SWEP.MagSkills = { [magId] = skill }.
function K.MagAllowed(ply, wep, magId)
    local need = wep.MagSkills and wep.MagSkills[magId]
    if not need then return true end
    return isPly(ply) and K.Has(ply, need)
end

-- K.PelletConeMult(ply, wep): pellet cone multiplier (Shotgun drills, DP-24).
function K.PelletConeMult(ply, wep)
    if K.GunClass(wep) == K.DP24 and isPly(ply) and K.Has(ply, "shotgun_drills") then return cfg("shotgunCone") end
    return 1
end

-- K.FireRateMult(ply, wep, mode): fire rate multiplier (Bolt drills,
-- Rapid fire: rapidFireRPM / the gun's FireRate, Dual DC-17 "dual" mode).
function K.FireRateMult(ply, wep, mode)
    if not isPly(ply) then return 1 end
    local m = 1
    if K.GunClass(wep) == K.DC15X and K.Has(ply, "bolt_drills") then m = m * cfg("boltDrillsRate") end
    if K.GunClass(wep) == "rhylib_dc15s" and wep.FireRate and K.Has(ply, "rapid_fire") then
        m = m * cfg("rapidFireRPM") / wep.FireRate
    end
    if mode == "dual" then m = m * cfg("dualRate") end
    return m
end

-- K.ReloadMult(ply, wep, cell): reload time multiplier. cell = true for a
-- power cell swap (Quick hands only speeds magazines). Speed loader,
-- Combat veteran, Field logistics (server flag) and Momentum (one reload:
-- calling it uses the bonus up, so call it once per reload).
function K.ReloadMult(ply, wep, cell)
    if not isPly(ply) then return 1 end
    local m = 1
    if not cell and K.Has(ply, "quick_hands") then m = m * cfg("quickHandsMult") end
    if K.Has(ply, "speed_loader") and K.PISTOLS[K.GunClass(wep)] then m = m * cfg("speedLoaderMult") end
    if K.Has(ply, "combat_veteran") and K.IsRifle(wep) then m = m * cfg("vetRifle") end
    if ply.rhylibLogi then m = m * cfg("logiReload") end   -- (Field logistics, server)
    if (ply.rhylibMomentumReload or 0) > CurTime() then
        m = m * cfg("momentumReload")
        ply.rhylibMomentumReload = nil   -- (one reload)
    end
    return m
end

-- K.DrawMult(ply, wep): draw time multiplier for Rhylib guns: Quick draw,
-- and Carbine discipline for the DC-15S (the faster one wins).
function K.DrawMult(ply, wep)
    if not isPly(ply) then return 1 end
    local m = 1
    if K.Has(ply, "quick_draw") then m = cfg("quickDrawMult") end
    if K.Has(ply, "carbine_disc") and K.GunClass(wep) == K.DC15S then m = math.min(m, cfg("carbineDraw")) end
    return m
end

-- K.MagBonus(ply, magId): extra rounds when ply loads this magazine type
-- (Extended mags: medium, Light mags: small). Returns a number (0 = none).
function K.MagBonus(ply, magId)
    if not isPly(ply) then return 0 end
    local W = Rhylib.Weapons
    if W and W.BaseMag then magId = W.BaseMag(magId) end   -- (training copies count too)
    if magId == "mag_medium" and K.Has(ply, "ext_mags") then return cfg("extMagBonus") end
    if magId == "mag_small" and K.Has(ply, "light_mags") then return cfg("lightMagBonus") end
    return 0
end

-- K.CellMult(ply): power cell shots multiplier (Efficient cells).
function K.CellMult(ply)
    if isPly(ply) and K.Has(ply, "eff_cells") then return cfg("effCellsMult") end
    return 1
end

-- K.SpinMoveMult(ply, wep, base): walk speed multiplier while a minigun's
-- barrels spin; base is the gun's own SpinMoveMult (Gun runner raises it).
function K.SpinMoveMult(ply, wep, base)
    if K.GunClass(wep) == K.Z6 and isPly(ply) and K.Has(ply, "gun_runner") then
        return math.max(base, cfg("gunRunnerSpin"))
    end
    return base
end

-- K.WeightPenaltyMult(ply): multiplier on rhylib_stamina's weight penalty (Load bearer).
function K.WeightPenaltyMult(ply)
    if isPly(ply) and K.Has(ply, "load_bearer") then return cfg("loadBearerPenalty") end
    return 1
end

-- Rhylib blasters only (not kits, grenades, tools); cached per class.
local gunCache = {}
local function isGun(class)
    local v = gunCache[class]
    if v == nil then
        local t = weapons.Get(class)
        v = t and t.IsRhylib and t.Mags ~= nil and not t.Stun or false
        gunCache[class] = v
    end
    return v
end

-- K.AdjustWeight(ply, state, weight, cap): carry weight and limit after
-- skills. Load bearer raises the limit; Gun runner (Z-6), Long gun
-- (DC-15X), Shotgun drills (short guns) and Explosives pack lower item
-- weights (the lightest that applies). state is the inventory state
-- ({ cont = { [cid] = { items } } }). Returns weight, cap.
function K.AdjustWeight(ply, state, weight, cap)
    if not isPly(ply) then return weight, cap end
    local set = K.Set(ply)
    if set.load_bearer then cap = cap + cfg("loadBearerCarry") end
    if set.gun_runner or set.long_gun or set.shotgun_drills or set.eod_pack then
        local Items = Rhylib.Items
        if not (Items and Items.defs) then return weight, cap end
        for cid, c in pairs(state.cont or {}) do
            if cid ~= Items.EXT then
                for _, o in pairs(c.items) do
                    local def = Items.defs[o.id]
                    if def and def.weight and (def.weapon or (set.eod_pack and K.ExplosiveItem(def))) then
                        -- The lightest that applies (they don't stack).
                        local mult = 1
                        if def.weapon then
                            if set.gun_runner and K.ItemGun(o.id) == K.Z6 then mult = math.min(mult, cfg("gunRunnerWeight")) end
                            if set.long_gun and K.ItemGun(o.id) == K.DC15X then mult = math.min(mult, cfg("longGunWeight")) end
                            if set.shotgun_drills and def.w <= 4 and isGun(def.weapon) then mult = math.min(mult, cfg("sidearmWeight")) end
                        end
                        if set.eod_pack and K.ExplosiveItem(def) then mult = math.min(mult, cfg("eodPackWeight")) end
                        -- (backpack contents count at backpackWeightMult in Items.Weight)
                        local share = cid == Items.BACK and (Config.Get("inventory", "backpackWeightMult") or 0.8) or 1
                        if mult < 1 then weight = weight - def.weight * (1 - mult) * (o.count or 1) * share end
                    end
                end
            end
        end
    end
    return math.max(0, weight), cap
end

-- K.ExplosiveItem(def): is this item an explosive for the EOD Explosives
-- pack? Grenades and charges (armoury shelf "grenade"), rockets, Republic mines.
function K.ExplosiveItem(def)
    if not def then return false end
    if def.group == "grenade" or def.id == "rhylib_rep_mine" then return true end
    local W = Rhylib.Weapons
    return W ~= nil and W.BaseMag ~= nil and not def.weapon and W.BaseMag(def.id) == "rocket"
end

-- Explosives pack: one more per stack of explosives that stack.
-- (Items.StackFor allows up to def.stackMax.) Answers rhylib_inventory's
-- Rhylib.ItemStack(def, ply) hook with the stack size for this player.
Rhylib.Hook.Add("Rhylib.ItemStack", "skills.eodpack", function(def, ply)
    if not (def and def.stack and def.stack > 1 and K.ExplosiveItem(def)) then return end
    local extra = math.max(0, math.floor(cfg("eodPackStack") or 1))
    def.stackMax = def.stack + extra
    if isPly(ply) and K.Has(ply, "eod_pack") then return def.stack + extra end
end)

-- K.DemoMults(ply): Demolitions (EOD): damage and radius multipliers for
-- thermal detonators and HE charges, or nil without the skill.
-- Example: local dm, rm = K.DemoMults(owner)  if dm then dmg = dmg * dm end
function K.DemoMults(ply)
    if not (isPly(ply) and K.Has(ply, "eod_demo")) then return nil end
    return cfg("eodDemoDamage"), cfg("eodDemoRadius")
end

-- K.FlyFire(ply, wep): DP-23 proficiency (Airborne): true if this gun may
-- fire while flying a jetpack (rhylib_base TooHeavyToFire asks).
function K.FlyFire(ply, wep)
    return isPly(ply) and K.GunClass(wep) == "rhylib_dp23" and K.Has(ply, "dp23_prof")
end

-- K.GrenadeMults(ply): Grenadier (Airborne): range, damage and radius
-- multipliers for thrown grenades, or nil without the skill.
function K.GrenadeMults(ply)
    if not (isPly(ply) and K.Has(ply, "grenadier")) then return nil end
    return cfg("grenadeRange"), cfg("grenadeDamage"), cfg("grenadeRadius")
end

-- K.Hovering(ply): hovering on the jetpack: in the air, thrusting, Sprint
-- held (rhylib_jetpack). False without rhylib_jetpack.
function K.Hovering(ply)
    local J = Rhylib.Jetpack
    return J ~= nil and ply:GetDTBool(J.DT_THRUST) and ply:KeyDown(IN_SPEED) and not ply:OnGround()
end

-- K.FreeSprint(ply): sprinting costs no stamina right now (Momentum after
-- a kill: NW2Float rhylib_momentum; or the Second wind order).
function K.FreeSprint(ply)
    if not isPly(ply) then return false end
    return ply:GetNW2Float("rhylib_momentum", 0) > CurTime() or K.OrderIs(ply, "wind")
end

-- K.RegenMult(ply): stamina refill multiplier (Second wind order, Steady the line).
function K.RegenMult(ply)
    local m = 1
    if K.OrderIs(ply, "wind") then m = cfg("windRegen") end
    if isPly(ply) and ply:GetNW2Bool("rhylib_steadyLine", false) then m = m * cfg("lineRegen") end   -- (Steady the line)
    return m
end

-- Light kit: a little faster while lightly loaded. Before every limiter
-- (medical legs -90, MP cuffs -95, stamina 0), which only ever lower it.
Rhylib.Hook.Add("SetupMove", "skills.move", function(ply, mv)
    if not K.Has(ply, "light_kit") then return end
    local w = ply:GetNW2Float("rhylib_weight", 0)
    local cap = ply:GetNW2Float("rhylib_carry", 20)
    if cap > 0 and w / cap >= cfg("lightKitLoad") then return end
    local m = cfg("lightKitSpeed")
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * m)
    mv:SetMaxSpeed(mv:GetMaxSpeed() * m)
end, -200)

--------------------------------------------------------------------------
-- Airborne
--------------------------------------------------------------------------

-- Any Airborne skill (an officer may borrow one without Hard landings).
local function airborne(ply)
    local set = K.Set(ply)
    local c = ply.rhylibSkillCache
    if c and c.set == set then
        if c.air == nil then
            c.air = false
            for id in pairs(set) do
                local n = K.byId[id]
                if n and n.cat == "airborne" and n.spec ~= "eod" then c.air = true break end   -- (the Field technician only shares the page)
            end
        end
        return c.air
    end
    return set.hard_landings == true
end

-- K.Airborne(ply): has any Airborne skill (not counting the Field
-- technician, which only shares the page).
function K.Airborne(ply)
    return isPly(ply) and airborne(ply)
end

-- K.JetCfg(ply, key, value): rhylib_jetpack asks for these per player and
-- tick. key is a jetpack setting (fuelTime, rechargeTime, hoverFuel,
-- climbSpeed, airAccel, maxAirSpeed), value the jetpack's own; returns the
-- value for this player. Only players with an Airborne skill change.
function K.JetCfg(ply, key, v)
    local set = K.Set(ply)
    if not airborne(ply) then return v end
    if key == "fuelTime" then
        v = math.max(v, cfg("airborneFuel"))
        if set.extended_tanks then v = v * cfg("tankMult") end
    elseif key == "rechargeTime" then
        if set.extended_tanks then v = v / cfg("tankMult") end
    elseif key == "hoverFuel" then
        if set.hover then v = v * cfg("hoverFuelMult") end
    elseif key == "climbSpeed" or key == "airAccel" or key == "maxAirSpeed" then
        if set.afterburner then v = v * cfg("afterburnerMult") end
    end
    return v
end

-- Sidestep (Officer): Sprint + left / right / back + Jump (a forward
-- sprint-jump stays a jump), or Alt + any direction, from the ground. A
-- short burst (sidestepTime), then the sideways speed drops to
-- sidestepCarry so the step stays short. Predicted; cooldown in DTFloat
-- 25, end of the burst in DTFloat 24.
local DT_DODGE, DT_STEP = 25, 24   -- (player DTFloat slots; other addons must not use them)
Rhylib.Hook.Add("SetupMove", "skills.dodge", function(ply, mv)
    local now = CurTime()
    -- End of the burst: slow down.
    local stepEnd = ply:GetDTFloat(DT_STEP)
    if stepEnd > 0 and now >= stepEnd then
        ply:SetDTFloat(DT_STEP, 0)
        local vel = mv:GetVelocity()
        local h = math.sqrt(vel.x * vel.x + vel.y * vel.y)
        local carry = cfg("sidestepCarry")
        if h > carry then
            vel.x, vel.y = vel.x * carry / h, vel.y * carry / h
            mv:SetVelocity(vel)
        end
    end

    local alt = mv:KeyPressed(IN_WALK)
    if not (alt or (mv:KeyPressed(IN_JUMP) and mv:KeyDown(IN_SPEED))) then return end
    if not alt and mv:GetSideSpeed() == 0 and mv:GetForwardSpeed() >= 0 then return end
    if not K.Has(ply, "sidestep") or not ply:OnGround() then return end
    if K.OrderIs and K.OrderIs(ply, "hold") then return end   -- (Hold fast: hold the position)
    if not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() >= 2 then return end
    local Med = Rhylib.Medical
    if Med and Med.IsDown and (Med.IsDown(ply) or (Med.Dragging and Med.Dragging(ply))) then return end
    if Med and Med.InTank and (Med.InTank(ply) or ply:GetNW2Int("rhylib_medAct", 0) ~= 0) then return end
    if IsValid(ply:GetDTEntity(31)) then return end   -- (on a grapple rope)
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and (MP.IsCuffed(ply) or MP.IsStunned(ply) or MP.EscortedBy(ply)) then return end
    if ply:GetDTFloat(DT_DODGE) > now then return end
    local f, s = mv:GetForwardSpeed(), mv:GetSideSpeed()
    if f * f + s * s < 1 then return end

    local cost = cfg("sidestepStamina")
    local St = Rhylib.Stamina
    if St and St.Get then
        if St.Get(ply) < cost then return end
        if SERVER then St.Drain(ply, cost) end
    end

    local speed = cfg("sidestepSpeed")
    local yaw = Angle(0, mv:GetMoveAngles().y, 0)
    local dir = yaw:Forward() * f + yaw:Right() * s
    dir.z = 0
    dir:Normalize()
    local vel = mv:GetVelocity()
    vel.x, vel.y = dir.x * speed, dir.y * speed
    vel.z = math.max(vel.z, 160)   -- a hop (over 140 leaves the ground), so friction doesn't eat it
    ply:SetGroundEntity(NULL)
    mv:SetVelocity(vel)
    ply:SetDTFloat(DT_DODGE, now + cfg("sidestepCooldown"))
    ply:SetDTFloat(DT_STEP, now + cfg("sidestepTime"))
    if SERVER then ply:EmitSound("ambient/machines/thumper_dust.wav", 60, 140, 0.5) end
end, -150)
