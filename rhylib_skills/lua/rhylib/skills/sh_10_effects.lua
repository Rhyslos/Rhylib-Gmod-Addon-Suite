--[[
    What the skills do (shared, so firing and movement stay predicted).
    Other addons ask these when rhylib_skills is installed; without it
    nothing is gated (every fire mode, scope and item works).

        K.ModeAllowed(ply, wep, mode)    skill-gated fire modes (SWEP.SkillModes)
        K.ScopeAllowed(ply, wep)         SWEP.ScopeSkill
        K.RunAndGun(ply, wep)            fire while sprinting
        K.SpreadMult(ply, wep)           cone multiplier (sprinting, Z-6, pistols)
        K.RecoilMult(ply, wep)           view kick multiplier
        K.FireRateMult(ply, wep, mode)
        K.ReloadMult(ply, wep, cell)     reload time multiplier (server; Speed loader: pistols)
        K.DrawMult(ply, wep)             draw time multiplier (Quick draw)
        K.MagBonus(ply, magId)           extra rounds per magazine
        K.CellMult(ply)                  power cell shots multiplier
        K.SpinMoveMult(ply, wep, base)   walk speed while the barrels spin
        K.WeightPenaltyMult(ply)         rhylib_stamina weight penalty
        K.AdjustWeight(ply, state, weight, cap)  rhylib_inventory carry
        K.FreeSprint(ply)                Momentum, Second wind: sprinting costs nothing
        K.RegenMult(ply)                 stamina refill multiplier (Second wind)
        K.MagAllowed(ply, wep, magId)    SWEP.MagSkills (Heavy feed: Z-6 large mags)
        K.PelletConeMult(ply, wep)       shotgun pellet cone (Shotgun drills)
        K.ShotDamageMult(ply, wep)       per shot, after its spread (First shot)
        K.JetCfg(ply, key, value)        rhylib_jetpack settings per player (Airborne)
        K.Airborne(ply)                  has any Airborne skill
        K.Hovering(ply)                  hovering on the jetpack (Hover)
    Numbers are config "skills" values so they can be tuned without code.
]]

local K = Rhylib.Skills
local Config = Rhylib.Config

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
reg("markLockDamage", 1.15, "Mark target: damage multiplier for the marker's squad mates (not Marksmen) on a locked target (a Q mark)")
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

local function cfg(k) return Config.Get("skills", k) end

K.Z6 = "rhylib_z6"
K.DC15X = "rhylib_dc15x"
K.DP24 = "rhylib_dp24"
K.DC15S = "rhylib_dc15s"
K.DC15A = "rhylib_dc15a"

-- The gun a weapon counts as for skills (training copies count as the real one).
function K.GunClass(wep)
    return wep.TrainingOf or wep:GetClass()
end

-- Same for an item id.
function K.ItemGun(id)
    local w = weapons.GetStored(id)
    return w and w.TrainingOf or id
end
K.PISTOLS = { rhylib_dc17 = true }

local function isPly(p) return IsValid(p) and p:IsPlayer() end

function K.ModeAllowed(ply, wep, mode)
    local need = wep.SkillModes and wep.SkillModes[mode]
    if not need then return true end
    return isPly(ply) and K.Has(ply, need)
end

function K.ScopeAllowed(ply, wep)
    if not wep.ScopeSkill then return true end
    return isPly(ply) and K.Has(ply, wep.ScopeSkill)
end

function K.RunAndGun(ply, wep)
    return isPly(ply) and K.Has(ply, "run_gun")
end

local function sprinting(ply, wep)
    return wep.OwnerSprinting and wep:OwnerSprinting(ply) or false
end

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
    if set.hover and K.Hovering(ply) then m = m * cfg("hoverSpread") end
    if set.first_shot and K.FirstShotReady(ply, wep) then m = m * cfg("firstShotSpread") end
    return m
end

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

function K.PelletConeMult(ply, wep)
    if K.GunClass(wep) == K.DP24 and isPly(ply) and K.Has(ply, "shotgun_drills") then return cfg("shotgunCone") end
    return 1
end

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

function K.ReloadMult(ply, wep, cell)
    if not isPly(ply) then return 1 end
    local m = 1
    if not cell and K.Has(ply, "quick_hands") then m = m * cfg("quickHandsMult") end
    if K.Has(ply, "speed_loader") and K.PISTOLS[K.GunClass(wep)] then m = m * cfg("speedLoaderMult") end
    if (ply.rhylibMomentumReload or 0) > CurTime() then
        m = m * cfg("momentumReload")
        ply.rhylibMomentumReload = nil   -- (one reload)
    end
    return m
end

-- Quick draw: draw time multiplier for Rhylib guns.
-- Quick draw, and Carbine discipline for the DC-15S (the faster one wins).
function K.DrawMult(ply, wep)
    if not isPly(ply) then return 1 end
    local m = 1
    if K.Has(ply, "quick_draw") then m = cfg("quickDrawMult") end
    if K.Has(ply, "carbine_disc") and K.GunClass(wep) == K.DC15S then m = math.min(m, cfg("carbineDraw")) end
    return m
end

function K.MagBonus(ply, magId)
    if not isPly(ply) then return 0 end
    local W = Rhylib.Weapons
    if W and W.BaseMag then magId = W.BaseMag(magId) end   -- (training copies count too)
    if magId == "mag_medium" and K.Has(ply, "ext_mags") then return cfg("extMagBonus") end
    if magId == "mag_small" and K.Has(ply, "light_mags") then return cfg("lightMagBonus") end
    return 0
end

function K.CellMult(ply)
    if isPly(ply) and K.Has(ply, "eff_cells") then return cfg("effCellsMult") end
    return 1
end

function K.SpinMoveMult(ply, wep, base)
    if K.GunClass(wep) == K.Z6 and isPly(ply) and K.Has(ply, "gun_runner") then
        return math.max(base, cfg("gunRunnerSpin"))
    end
    return base
end

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

-- Carry: Load bearer raises the limit; Gun runner halves the Z-6's weight.
-- state is the inventory state ({ cont = { [cid] = { items } } }).
function K.AdjustWeight(ply, state, weight, cap)
    if not isPly(ply) then return weight, cap end
    local set = K.Set(ply)
    if set.load_bearer then cap = cap + cfg("loadBearerCarry") end
    if set.gun_runner or set.long_gun or set.shotgun_drills then
        local Items = Rhylib.Items
        if not (Items and Items.defs) then return weight, cap end
        for cid, c in pairs(state.cont or {}) do
            if cid ~= Items.EXT then
                for _, o in pairs(c.items) do
                    local def = Items.defs[o.id]
                    if def and def.weight and def.weapon then
                        -- The lightest that applies (they don't stack).
                        local mult = 1
                        if set.gun_runner and K.ItemGun(o.id) == K.Z6 then mult = math.min(mult, cfg("gunRunnerWeight")) end
                        if set.long_gun and K.ItemGun(o.id) == K.DC15X then mult = math.min(mult, cfg("longGunWeight")) end
                        if set.shotgun_drills and def.w <= 4 and isGun(def.weapon) then mult = math.min(mult, cfg("sidearmWeight")) end
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

-- DP-23 proficiency (Airborne): the DP-23 fires while flying a jetpack.
function K.FlyFire(ply, wep)
    return isPly(ply) and K.GunClass(wep) == "rhylib_dp23" and K.Has(ply, "dp23_prof")
end

-- Grenadier (Airborne): range, damage and radius multipliers for thrown
-- grenades, or nil without the skill.
function K.GrenadeMults(ply)
    if not (isPly(ply) and K.Has(ply, "grenadier")) then return nil end
    return cfg("grenadeRange"), cfg("grenadeDamage"), cfg("grenadeRadius")
end

-- Hovering on the jetpack: in the air, thrusting, Sprint held (rhylib_jetpack).
function K.Hovering(ply)
    local J = Rhylib.Jetpack
    return J ~= nil and ply:GetDTBool(J.DT_THRUST) and ply:KeyDown(IN_SPEED) and not ply:OnGround()
end

function K.FreeSprint(ply)
    if not isPly(ply) then return false end
    return ply:GetNW2Float("rhylib_momentum", 0) > CurTime() or K.OrderIs(ply, "wind")
end

function K.RegenMult(ply)
    if K.OrderIs(ply, "wind") then return cfg("windRegen") end
    return 1
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
                if n and n.cat == "airborne" then c.air = true break end
            end
        end
        return c.air
    end
    return set.hard_landings == true
end

function K.Airborne(ply)
    return isPly(ply) and airborne(ply)
end

-- rhylib_jetpack asks for these per player and tick.
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
local DT_DODGE, DT_STEP = 25, 24
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
