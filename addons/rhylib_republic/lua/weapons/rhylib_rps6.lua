--[[
    RPS-6 rocket launcher. One rocket at a time; in the normal ("semi")
    mode it flies straight (unguided).
    The rocket is a slow explosive bolt: blast damage where it hits.
    Reload with R after each shot.
    Too heavy to fire while flying.
    Lock-on mode (EOD Top attack skill, E + R): aim at a comms jammer or a
    droid until it locks (box on the HUD), then fire: rhylib_topattack
    climbs and dives onto it by itself. Fired without a lock it's laser
    guided: it climbs, then dives onto the spot you aim at (a red dot) and
    follows it while you keep the RPS-6 out.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/rps.mdl), held in
    first person by the trooper hands on the HL2 launcher (CarrierVM). The model's addon must be
    installed. Tune with rhylib_vm_editor, then paste its lines below.
    All numbers are first guesses for tuning.

    Class rhylib_rps6. Shared: one file for server and client (AddCSLuaFile).
    Base rhylib_base (rhylib_weapons), where every SWEP field is explained;
    only the fields that differ are set here.
    Training copy: rhylib_rps6_training.
]]

AddCSLuaFile()

DEFINE_BASECLASS("rhylib_base")

SWEP.Base = "rhylib_base"
SWEP.PrintName = "RPS-6"
SWEP.Category = "Rhylib: Heavy"
SWEP.InvGroup = "heavy"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel (the carrier model is HL2's, so it's always there); ReloadTime sets the reload length.
SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on GMod's own HL2 rocket
-- launcher viewmodel (shoulder hold); its launcher bone "base" is hidden.
SWEP.CarrierVM = "models/weapons/c_rpg.mdl"
SWEP.CarrierBone = "base"
SWEP.PropBonePos = Vector(1.3, 6.8, 0)
SWEP.PropBoneAng = Angle(90, -90, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(-5, -5.4, 3)
SWEP.CarrierFOV = 54
SWEP.HoldType = "rpg"
SWEP.Slot = 4

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 8, -6)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(-7, 3.4, 0)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 1, 180)
SWEP.PropMuzzle = Vector(30, 0, 4)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 1,
    DefaultClip = 1,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_rocket",
}

SWEP.FireRate = 60
-- Recoil: view kick per shot (rhylib_weapons cl_50_recoil): up = degrees up,
-- side = random sideways, bias = lean -1 (left) .. 1 (right), recover = share
-- of the climb that settles back, aimMult = multiplier while aiming.
SWEP.Recoil = { up = 4.5, side = 0.8, bias = 0, recover = 0.85, aimMult = 0.8 }  -- view kick per shot
SWEP.Damage = 0               -- all damage comes from the blast
SWEP.BoltSpeed = 2200
SWEP.BoltColor = 4            -- rocket look
SWEP.BoltLife = 5
SWEP.FireSound = { "weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_01.ogg", "weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_02.ogg", "weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_03.ogg" }
SWEP.FireSoundLevel = 150

SWEP.Explosive = { radius = 200, damage = 250 }   -- blast where the rocket lands (units, damage at the centre)

SWEP.Mags = { "rocket" }
SWEP.FireModes = { "semi", "lockon" }
SWEP.SkillModes = { lockon = "eod_lockon" }   -- (rhylib_skills: EOD Top attack)
SWEP.ReloadTime = 3
SWEP.AutoReload = false     -- reload with R like every other gun

SWEP.UsesCell = false
-- Spare magazines / cells put in your pouch when you pick it up (rhylib_base).
SWEP.StartMags = 3
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 6   -- (long guns are 6 long, the inventory is 6 wide; owner 2026-10-07)
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 8           -- kg

-- Spread: cone angles in degrees (rhylib_weapons sh_10_spread): hip / aim =
-- resting cone, kickMain / kickSide = how far the crosshair arcs move per shot,
-- bloomPerShot (up to bloomMax) = growth of the whole cone, aimKickMult /
-- aimOffsetMult = share of that while aiming. Each value is also a setting
-- in Server settings > guns (rhylib_weapons sh_70_gunstats).
SWEP.Spread = {
    hip = 0.8,
    aim = 0.25,
    kickMain = 1.2,
    kickSide = 0.5,
    bloomPerShot = 0.5,
    bloomMax = 1.5,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-3.5, 0, 0.5)
SWEP.AimFov = 0.75

--------------------------------------------------------------------------
-- Lock-on (Top attack)
--------------------------------------------------------------------------

local Config = Rhylib.Config
-- Settings (module "weapons"). Registered here, so they exist only while
-- rhylib_republic is installed.
Config.Register("weapons", "lockRange", 6000, "RPS-6 lock-on: longest lock (units)")
Config.Register("weapons", "lockCone", 6, "RPS-6 lock-on: how close to the crosshair a target must be (degrees)")
Config.Register("weapons", "lockTime", 1.2, "RPS-6 lock-on: seconds of aiming at a target to lock it")

-- LockTarget: what the lock is on (NULL = nothing). LockStart: CurTime()
-- when that target was first held (0 = none). Set by the server only.
function SWEP:SetupDataTables()
    BaseClass.SetupDataTables(self)
    self:NetworkVar("Entity", 0, "LockTarget")
    self:NetworkVar("Float", 0, "LockStart")
end

-- SWEP:LockOn(): true while the fire mode is "lockon". Shared.
function SWEP:LockOn()
    return self:GetFireModeName() == "lockon"
end

-- SWEP:LockedTarget(): the locked target, or nil (still locking / none).
-- A target counts as locked once it has been held for weapons lockTime. Shared.
function SWEP:LockedTarget()
    local t = self:GetLockTarget()
    local st = self:GetLockStart()
    if not IsValid(t) or st <= 0 then return nil end
    if CurTime() - st < (Config.Get("weapons", "lockTime") or 1.2) then return nil end
    return t
end

-- SWEP:FireShot(): rhylib_base calls this for each shot. Normal mode uses
-- the base (an explosive bolt). Lock-on mode spawns rhylib_topattack instead
-- and passes it: dir, target (nil = laser guided), owner, weapon, explosive.
function SWEP:FireShot()
    if not self:LockOn() then return BaseClass.FireShot(self) end
    -- Lock-on mode: always the top-attack rocket. Locked = it homes on the
    -- target by itself; not locked = it follows your aim (laser).
    local t = self:LockedTarget()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    self:SetNextPrimaryFire(CurTime() + 60 / self:CurrentFireRate())
    if not self:NoAmmoUse() then self:TakePrimaryAmmo(1) end
    local snd = self.FireSound
    if istable(snd) then snd = snd[math.floor(util.SharedRandom("rhylib.snd", 1, #snd + 0.999))] or snd[1] end
    self:EmitSound(snd, self.FireSoundLevel or 140, util.SharedRandom("rhylib.pitch", 96, 104), 1, CHAN_WEAPON)
    self:SendWeaponAnim(self.FireAct or ACT_VM_PRIMARYATTACK)
    owner:SetAnimation(PLAYER_ATTACK1)
    if CLIENT and IsFirstTimePredicted() then
        Rhylib.Weapons.Recoil.Kick(self)
    elseif SERVER and game.SinglePlayer() then
        self:CallOnClient("RhylibRecoilKick")
    end
    if CLIENT then return end
    local ang = owner:EyeAngles()
    local start = owner:GetShootPos()
    local pos = start + ang:Forward() * 30 + ang:Right() * 6
    local tr = util.TraceLine({ start = start, endpos = pos, filter = owner, mask = MASK_SOLID })
    if tr.Hit then pos = tr.HitPos + tr.HitNormal * 4 end
    local m = ents.Create("rhylib_topattack")
    if not IsValid(m) then return end
    m:SetPos(pos)
    m.dir = ang:Forward()
    m.target = t
    m.owner = owner
    m.weapon = self
    m.explosive = self.Explosive
    m:Spawn()
    self:SetLockTarget(NULL)
    self:SetLockStart(0)
end

if SERVER then
    -- Comms jammers (rhylib_radio), refreshed once a second.
    local jammers, jammersAt = {}, 0
    local function jammerList()
        local now = CurTime()
        if now >= jammersAt then
            jammersAt = now + 1
            jammers = ents.FindByClass("rhylib_comms_jammer*")
        end
        return jammers
    end

    local function lockable(e)
        if not IsValid(e) then return false end
        if e.IsRhylibDroid then return e:Health() > 0 and not e.Training end
        return not e.destroyed
    end

    -- Lockable: a live, non-training Rhylib droid, or a jammer that isn't
    -- destroyed.
    -- SWEP:FindLockTarget(owner): best target within lockRange and lockCone,
    -- in sight (brushes only), nearest the crosshair; or nil. Server only.
    function SWEP:FindLockTarget(owner)
        local eye = owner:GetShootPos()
        local aim = owner:GetAimVector()
        local range = Config.Get("weapons", "lockRange") or 6000
        local cosCone = math.cos(math.rad(Config.Get("weapons", "lockCone") or 6))
        local best, bestDot
        local function try(e)
            if not lockable(e) then return end
            local c = e:WorldSpaceCenter()
            local d = c - eye
            local len = d:Length()
            if len > range or len < 1 then return end
            local dot = aim:Dot(d / len)
            if dot < cosCone or (bestDot and dot <= bestDot) then return end
            local tr = util.TraceLine({ start = eye, endpos = c, mask = MASK_SOLID_BRUSHONLY })
            if tr.Hit then return end
            best, bestDot = e, dot
        end
        for _, e in ipairs(jammerList()) do try(e) end
        local D = Rhylib.Droids
        for e in pairs(D and D.active or {}) do try(e) end
        return best
    end

    -- SWEP:UpdateLock(): run from Think, at most every 0.1 s. Keeps
    -- LockTarget / LockStart up to date while the owner aims in lock-on mode
    -- with a rocket loaded. Server only.
    function SWEP:UpdateLock()
        local now = CurTime()
        if now < (self.rhylibLockCheck or 0) then return end
        self.rhylibLockCheck = now + 0.1
        local owner = self:GetOwner()
        local want = IsValid(owner) and owner:IsPlayer() and self:LockOn() and self:GetAiming()
            and self:Clip1() > 0 and not self:IsReloading() and not self:GetSafety()
        local t = want and self:FindLockTarget(owner) or nil
        local cur = self:GetLockTarget()
        if t == cur and IsValid(t) then
            self.rhylibLockLost = nil
            return
        end
        if not t and IsValid(cur) then
            -- (a short grace: a twitch off the target doesn't lose the lock)
            if want and lockable(cur) then
                self.rhylibLockLost = self.rhylibLockLost or now
                if now - self.rhylibLockLost < 0.35 then return end
            end
        end
        self.rhylibLockLost = nil
        self:SetLockTarget(t or NULL)
        self:SetLockStart(t and now or 0)
    end
end

function SWEP:Think()
    BaseClass.Think(self)
    if SERVER then self:UpdateLock() end
end

if CLIENT then
    local AMBER = Color(255, 190, 60)
    local RED = Color(255, 70, 60)

    local function corners(x, y, w, h, len, col)
        surface.SetDrawColor(col)
        surface.DrawRect(x, y, len, 2) surface.DrawRect(x, y, 2, len)
        surface.DrawRect(x + w - len, y, len, 2) surface.DrawRect(x + w - 2, y, 2, len)
        surface.DrawRect(x, y + h - 2, len, 2) surface.DrawRect(x, y + h - len, 2, len)
        surface.DrawRect(x + w - len, y + h - 2, len, 2) surface.DrawRect(x + w - 2, y + h - len, 2, len)
    end

    -- Lock-on HUD: a hint line with no target; with one, a box of corners
    -- that closes in while it locks, "LOCKING n%" / "LOCKED · FIRE" and beeps.
    function SWEP:DrawHUD()
        if BaseClass.DrawHUD then BaseClass.DrawHUD(self) end
        if not self:LockOn() then return end
        local s = ScrH() / 1080
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        local t = self:GetLockTarget()
        local cx, cy = ScrW() * 0.5, ScrH() * 0.5
        if not IsValid(t) then
            local guiding = false
            for _, m in ipairs(ents.FindByClass("rhylib_topattack")) do
                if IsValid(m) and m.GetGuide and m:GetGuide() == LocalPlayer() then guiding = true break end
            end
            local text = guiding and "GUIDING · KEEP YOUR AIM ON THE TARGET"
                or (self:GetAiming() and "NO LOCK · FIRE TO GUIDE IT BY LASER" or "LOCK-ON · HOLD AIM ON A JAMMER OR DROID, OR FIRE TO GUIDE BY LASER")
            draw.SimpleTextOutlined(text, font, cx, cy + 70 * s, guiding and Color(255, 90, 80, 230) or Color(220, 220, 220, 200),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
            return
        end
        local need = Rhylib.Config.Get("weapons", "lockTime") or 1.2
        local k = math.Clamp((CurTime() - self:GetLockStart()) / need, 0, 1)
        local locked = k >= 1
        -- A box round the target, closing in while it locks.
        local mn, mx = t:OBBMins(), t:OBBMaxs()
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for i = 0, 7 do
            local p = t:LocalToWorld(Vector(bit.band(i, 1) > 0 and mx.x or mn.x, bit.band(i, 2) > 0 and mx.y or mn.y, bit.band(i, 4) > 0 and mx.z or mn.z)):ToScreen()
            x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
        end
        local pad = Lerp(k, 40 * s, 6 * s)
        x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
        local col = locked and RED or AMBER
        corners(x0, y0, x1 - x0, y1 - y0, math.max(8 * s, (x1 - x0) * 0.2), col)
        draw.SimpleTextOutlined(locked and "LOCKED · FIRE" or ("LOCKING " .. math.floor(k * 100) .. "%"), font,
            (x0 + x1) * 0.5, y1 + 4 * s, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 160))
        -- Tone: ticks while locking, fast beeps once locked.
        local now = RealTime()
        if now >= (self.rhylibLockBeep or 0) then
            self.rhylibLockBeep = now + (locked and 0.12 or 0.3)
            self:EmitSound("buttons/blip1.wav", 50, locked and 150 or 95, 0.35, CHAN_ITEM)
        end
    end
end
