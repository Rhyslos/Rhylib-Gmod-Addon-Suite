--[[
    T-19 grenade launcher (2026-10-10, owner: EOD Grenade launcher skill;
    "our own mortar clone").

    Fires the thermal detonators you carry (inventory items) as its rounds,
    always on impact, in a high arc: no gravity tricks, a plain ballistic
    shot at launcherRange's muzzle speed. One round in the breech; R loads
    the next thermal (training thermals fire training rounds).
    The range for your aim's pitch shows by the ammo counter (where the fire
    mode usually is), worked out for level ground, so someone with
    macrobinoculars can call "50 metres" and you aim until it reads 50.
    The longest shot (aimed about 45° up) is weapons launcherRange (60 m).

    Carrier and prop values are first guesses copied from the DP-23: tune
    with rhylib_vm_editor / rhylib_wm_editor and paste the lines below.

    Class rhylib_grenade_launcher. Shared: one file for server and client (AddCSLuaFile).
    Base rhylib_base (rhylib_weapons), where every SWEP field is explained;
    only the fields that differ are set here.
]]

AddCSLuaFile()

local Config = Rhylib.Config
-- Settings (module "weapons"; registered here, so only with rhylib_republic).
Config.Register("weapons", "launcherRange", 60, "Grenade launcher: longest shot on level ground (metres, aimed about 45° up)")
Config.Register("weapons", "launcherSpread", 0.6, "Grenade launcher: random aim error (degrees)")
Config.Register("weapons", "launcherDamage", 140, "Grenade launcher: blast damage at the centre (thermal detonator 140)")
Config.Register("weapons", "launcherRadius", 300, "Grenade launcher: blast radius (units; thermal detonator 300)")

SWEP.Base = "rhylib_base"
SWEP.PrintName = "T-19 grenade launcher"
SWEP.Category = "Rhylib: Heavy"
SWEP.InvGroup = "heavy"   -- (armoury shelf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/t19_grenadelauncher.mdl"
SWEP.UseHands = false
SWEP.CarrierVM = "models/weapons/synbf3/c_dlt19.mdl"
SWEP.CarrierBone = "v_dlt19_reference001"
SWEP.PropBonePos = Vector(0.7, -10, 0)
SWEP.PropBoneAng = Angle(1.2, -89, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(1.3, 0, -0.6)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 1.6
SWEP.HoldType = "ar2"
SWEP.Slot = 4

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/t19_grenadelauncher.mdl"
SWEP.PropScale = 0.9
SWEP.PropVMPos = Vector(18, 7, -8)
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-6.7, 2.2, 0)
SWEP.PropWMAng = Angle(-12, 0, 180)
SWEP.PropMuzzle = Vector(24, 0, 2)

SWEP.Primary = { ClipSize = 1, DefaultClip = 1, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }

SWEP.FireRate = 60
-- Recoil: view kick per shot (rhylib_weapons cl_50_recoil): up = degrees up,
-- side = random sideways, bias = lean -1 (left) .. 1 (right), recover = share
-- of the climb that settles back, aimMult = multiplier while aiming.
SWEP.Recoil = { up = 3.2, side = 0.6, bias = 0, recover = 0.85, aimMult = 0.8 }
SWEP.Damage = 0
SWEP.FireSound = "weapons/explosives_cannons_superlazers/wpn_mortar_cannon_r1_shoot_01.ogg"
SWEP.FireSoundLevel = 135

SWEP.Mags = {}                 -- (its rounds are thermal detonator items)
SWEP.FireModes = { "semi" }
SWEP.AutoReload = true         -- the next thermal goes in by itself after a shot
SWEP.UsesCell = false
-- Spare magazines / cells put in your pouch when you pick it up (rhylib_base).
SWEP.StartMags = 0
SWEP.StartCells = 0

SWEP.NoGunStats = true   -- (its blast is weapons launcherDamage / launcherRadius)
SWEP.CarrySkill = "eod_launcher"   -- (rhylib_skills: EOD Grenade launcher)

SWEP.InvW = 4
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 4.5

-- Spread: cone angles in degrees (rhylib_weapons sh_10_spread): hip / aim =
-- resting cone, kickMain / kickSide = how far the crosshair arcs move per shot,
-- bloomPerShot (up to bloomMax) = growth of the whole cone, aimKickMult /
-- aimOffsetMult = share of that while aiming.
SWEP.Spread = {
    hip = 1.2, aim = 0.6, kickMain = 0.8, kickSide = 0.3,
    bloomPerShot = 0.4, bloomMax = 1.5, aimKickMult = 0.5, aimOffsetMult = 0.6,
}
SWEP.AimPos = Vector(-2.5, 0, 1)
SWEP.AimFov = 0.85

-- Rounds it takes, best first (training thermals fire training rounds).
SWEP.Rounds = { "rhylib_thermal", "rhylib_thermal_impact", "rhylib_thermal_training" }
local TRAINING = { rhylib_thermal_training = true }

local UNITS_PER_M = 52.5
local LAUNCH_HEIGHT = 56   -- shoot position above the feet (lands at feet level)

local function gravity()
    local g = physenv and physenv.GetGravity and -physenv.GetGravity().z or 600
    return g > 1 and g or 600
end

-- SWEP:LaunchSpeed(): muzzle speed (units/s) for the configured longest
-- shot. Shared.
-- Muzzle speed for the configured longest shot (from LAUNCH_HEIGHT onto
-- level ground: R² = u(u + 2h), u = v²/g).
function SWEP:LaunchSpeed()
    local R = math.max(5, Config.Get("weapons", "launcherRange") or 60) * UNITS_PER_M
    local h = LAUNCH_HEIGHT
    return math.sqrt(gravity() * (math.sqrt(h * h + R * R) - h))
end

-- SWEP:RangeAt(pitch) -> metres. Shared (the HUD uses it).
-- Metres a shot at this view pitch (Source: negative = up) lands away on
-- level ground.
function SWEP:RangeAt(pitch)
    local v, g, h = self:LaunchSpeed(), gravity(), LAUNCH_HEIGHT
    local th = math.rad(-pitch)
    local vy, vx = v * math.sin(th), v * math.cos(th)
    local t = (vy + math.sqrt(math.max(0, vy * vy + 2 * g * h))) / g
    return vx * t / UNITS_PER_M
end

-- SWEP:RoundsCarried() -> how many thermals (any of SWEP.Rounds) the owner
-- carries. Server: from the inventory; client: only for your own weapon,
-- cached 0.25 s.
-- Thermals carried (server: inventory; client: your own copy of it).
function SWEP:RoundsCarried()
    local o = self:GetOwner()
    local Inv = Rhylib.Inventory
    if not (IsValid(o) and Inv) then return 0 end
    if SERVER then
        if not Inv.Count then return 0 end
        local n = 0
        for _, id in ipairs(self.Rounds) do n = n + Inv.Count(o, id) end
        return n
    end
    if o ~= LocalPlayer() or not Inv.byUid then return 0 end
    local now = RealTime()
    if self.rhylibRoundsAt and now < self.rhylibRoundsAt then return self.rhylibRounds end
    local n = 0
    for _, it in pairs(Inv.byUid) do
        for _, id in ipairs(self.Rounds) do
            if it.id == id then n = n + (it.count or 1) break end
        end
    end
    self.rhylibRounds, self.rhylibRoundsAt = n, now + 0.25
    return n
end

-- SWEP:FireShot(): replaces rhylib_base's shot (no bolt). Takes the round,
-- plays the sound and kick, and on the server calls SWEP:Launch.
-- One shot: a thermal detonator on impact, lobbed along the aim.
function SWEP:FireShot()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    local now = CurTime()
    self:SetNextPrimaryFire(now + 60 / self.FireRate)
    if not self:NoAmmoUse() then self:TakePrimaryAmmo(1) end
    self:EmitSound(self.FireSound, self.FireSoundLevel, util.SharedRandom("rhylib.pitch", 96, 104), 1, CHAN_WEAPON)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)
    if CLIENT and IsFirstTimePredicted() then
        Rhylib.Weapons.Recoil.Kick(self)
    elseif SERVER and game.SinglePlayer() then
        self:CallOnClient("RhylibRecoilKick")
    end
    if SERVER then self:Launch(owner) end
end

if SERVER then
    -- SWEP:Launch(ply): spawns a rhylib_grenade of kind "impact" with the
    -- launcher's damage / radius (× EOD Demolitions), aimed with a random
    -- error of launcherSpread, at LaunchSpeed() with no drag. Server only.
    function SWEP:Launch(o)
        local ang = o:EyeAngles()
        local err = Config.Get("weapons", "launcherSpread") or 0.6
        ang.p = ang.p + (math.random() * 2 - 1) * err
        ang.y = ang.y + (math.random() * 2 - 1) * err
        local dir = ang:Forward()
        local start = o:GetShootPos()
        local pos = start + dir * 20 + ang:Right() * 4 - ang:Up() * 3
        local tr = util.TraceLine({ start = start, endpos = pos, filter = o, mask = MASK_SOLID })
        if tr.Hit then pos = tr.HitPos + tr.HitNormal * 4 end
        local g = ents.Create("rhylib_grenade")
        if not IsValid(g) then return end
        g:SetPos(pos)
        g:SetAngles(ang)
        g.kind = "impact"
        g.thrower = o
        g.launched = true
        g.training = self.loadedTraining or nil
        g.Damage = Config.Get("weapons", "launcherDamage") or 140
        g.Radius = Config.Get("weapons", "launcherRadius") or 300
        -- Demolitions (EOD): harder and wider.
        local K = Rhylib.Skills
        if K and K.DemoMults then
            local dm, rm = K.DemoMults(o)
            if dm then g.Damage, g.Radius = g.Damage * dm, g.Radius * rm end
        end
        g:SetOwner(o)
        g:SetColor(Color(255, 190, 150))
        g:Spawn()
        local phys = g:GetPhysicsObject()
        if IsValid(phys) then
            -- (no drag, so the range readout holds)
            phys:SetDamping(0, 2)
            phys:EnableDrag(false)
            phys:SetVelocity(dir * self:LaunchSpeed())
            phys:AddAngleVelocity(VectorRand() * 300)
        end
    end

    -- StartReload / FinishReload replace rhylib_base's magazine reload.
    -- FinishReload takes one thermal item (first match in SWEP.Rounds) and
    -- notes whether it was a training one (self.loadedTraining).
    -- R (or the automatic reload after a shot): load one thermal.
    function SWEP:StartReload(kind)
        if self:IsReloading() or kind ~= 1 then return end
        local owner = self:GetOwner()
        if not (IsValid(owner) and owner:IsPlayer()) then return end
        if self:Clip1() >= 1 then return end
        if not self:InfiniteAmmo() and self:RoundsCarried() <= 0 then return end
        self:SendWeaponAnim(self.ReloadAct or ACT_VM_RELOAD)
        local vm = owner:GetViewModel()
        local animTime = IsValid(vm) and vm:SequenceDuration() or 2
        local duration = self.ReloadTime
        local K = Rhylib.Skills
        local sm = K and K.ReloadMult and K.ReloadMult(owner, self, false) or 1
        duration = duration * sm
        if IsValid(vm) and duration > 0 then vm:SetPlaybackRate(animTime / duration) end
        local finish = CurTime() + duration
        self:SetReloadKind(1)
        self:SetReloadEnd(finish)
        self:SetNextPrimaryFire(finish)
        self:SetAiming(false)
        owner:SetAnimation(PLAYER_RELOAD)
        self:EmitSound("weapons/shotgun/shotgun_reload" .. math.random(1, 3) .. ".wav", 70, 90)
    end

    function SWEP:FinishReload()
        self:SetReloadKind(0)
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        local vm = owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(1) end
        self:SendWeaponAnim(ACT_VM_IDLE)
        if self:InfiniteAmmo() then
            self.loadedTraining = nil
            self:SetClip1(1)
            return
        end
        local Inv = Rhylib.Inventory
        if not (Inv and Inv.Get and Inv.Remove) then return end
        for _, id in ipairs(self.Rounds) do
            for _, inst in pairs(Inv.Get(owner).byUid) do
                if inst.id == id then
                    Inv.Remove(owner, inst.uid, 1)
                    self.loadedTraining = TRAINING[id] or nil
                    self:SetClip1(1)
                    owner:EmitSound("weapons/shotgun/shotgun_cock.wav", 65, 85)
                    return
                end
            end
        end
    end
end

-- Saved with the inventory item (rhylib_inventory): { clip, mode, safe, tr }.
-- Inventory data: the round in the breech (and whether it's training).
function SWEP:GetInventoryData()
    return { clip = self:Clip1(), mode = 1, safe = self:GetSafety() or nil, tr = self.loadedTraining or nil }
end

function SWEP:SetInventoryData(data)
    data = data or {}
    self:SetClip1(math.Clamp(data.clip or 0, 0, 1))
    if data.safe then self:SetSafety(true) end
    self.loadedTraining = data.tr or nil
end

if CLIENT then
    -- rhylib_hud asks guns for these two: HUDModeText() replaces the fire
    -- mode text, HUDSpare() -> count, label for the spare ammo.
    -- By the ammo counter: the range for your aim, not a fire mode.
    function SWEP:HUDModeText()
        local o = self:GetOwner()
        if not IsValid(o) then return "" end
        return string.format("RANGE %d M", math.Round(math.max(0, self:RangeAt(o:EyeAngles().p))))
    end

    function SWEP:HUDSpare()
        return self:RoundsCarried(), "Thermal"
    end
end
