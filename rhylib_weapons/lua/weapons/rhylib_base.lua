--[[
    Rhylib weapon base. Every blaster derives from this.

    Hip-fire by default. Hold right mouse to half-aim: the gun comes up
    toward the shoulder, the view zooms slightly and the spread tightens.
    (Aiming will be gated behind a skill once the skill module exists.)

    Ammo:
      - Magazine: Clip1 holds the shots. SWEP.Mags lists the magazine
        types the gun takes (see W.MagTypes); the loaded type decides how
        many shots it holds. Tap R to reload the best magazine (the same
        type if you have one, else the first in SWEP.Mags).
      - Power cell (weapons with UsesCell): the "Cell" value drains per shot.
      Hold R for the radial menu to pick a magazine type or a power cell.
      Magazines and cells come from the inventory (or the pouch without it),
      see sv_20_pouch.lua.

    Sprinting lowers the gun the same way safety does (passive hold, no
    firing or aiming) without changing the fire mode. It comes back up
    SprintRaiseTime after you stop.

    Fire modes and safety:
      - E + R cycles through the weapon's FireModes ("semi", "auto", "burst").
        Any mode but "auto" fires once per trigger pull (e.g. "sidearm").
      - Shift + E + R toggles safety: the weapon is lowered (passive hold),
        can't fire or aim, and the crosshair hides.
      Semi and burst need a fresh trigger pull for each shot or burst.
      Primary.Automatic must stay true; the fire mode decides instead.

    Derived weapons set their own values below. Note: GMod does NOT merge
    the Primary, Secondary and Spread tables from the base, so a weapon
    that changes any field in them must define the whole table.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Rhylib base"
SWEP.Category = "Rhylib"
SWEP.Spawnable = false
SWEP.Author = "Rhylib"
SWEP.IsRhylib = true

SWEP.ViewModel = "models/weapons/c_smg1.mdl"
SWEP.WorldModel = "models/weapons/w_smg1.mdl"
SWEP.ViewModelFOV = 54
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.Slot = 2
SWEP.SlotPos = 1
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true  -- must stay true so DoDrawCrosshair is called

SWEP.Primary = {
    ClipSize = 30,          -- rounds of the preferred magazine, SWEP.Mags[1]
    DefaultClip = 30,       -- keep equal to ClipSize: spawned guns come loaded, spares come from the inventory
    Automatic = true,
    Ammo = "rhylib_mag_small",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "none",          -- set to "rhylib_cell" on cell weapons so the HUD shows spare cells
}

-- Rhylib settings
SWEP.FireRate = 600                 -- rounds per minute
SWEP.Damage = 25
SWEP.BoltSpeed = 7000               -- units per second (max 16383)
SWEP.BoltColor = 1                  -- 1 blue, 2 red, 3 green
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

-- Fire modes this weapon can switch between (E + R), first one is the default.
SWEP.FireModes = { "semi" }
SWEP.SprintRaiseTime = 0.25         -- seconds after sprinting before the gun can fire
SWEP.Grapple = false                -- true: gets a "grapple" fire mode while you carry a grapple hook
SWEP.BurstCount = 3
SWEP.BurstDelay = 0.25              -- extra pause after a burst
SWEP.BurstFireRate = nil            -- rounds per minute inside a burst (nil = FireRate)
SWEP.SkillModes = nil               -- { [mode] = skill id }: modes that need a skill (rhylib_skills)
SWEP.DualHoldType = nil             -- hold type for the "dual" fire mode
SWEP.ModeHoldTypes = nil            -- { mode = hold type } for other modes (DC-15S "sidearm": revolver = two-handed pistol grip)
SWEP.ModeReplaces = nil             -- { mode = other mode }: while mode is allowed, the other one isn't (sidearm replaces semi)
SWEP.ModeCarriers = nil             -- { mode = { CarrierVM, CarrierBone, CarrierBoneMove, PropBonePos, PropBoneAng,
                                    --   PropBoneScale, VMOffset, CarrierFOV, AimPos } }: another first-person
                                    --   viewmodel in that mode (only with the normal carrier in use)
SWEP.DualPropVMPos = nil            -- "dual" mode: a second prop floating at the left (forward, right, up)
SWEP.DualPropVMAng = Angle(0, 0, 0)
SWEP.DualPropWMPos = nil            -- "dual" mode: a second prop on the left hand (forward, right, up)
SWEP.DualPropWMAng = Angle(0, 0, 0)
SWEP.DualCarrierVM = nil            -- "dual" mode viewmodel with two guns and hands (their gun bones hidden, props drawn on them)
SWEP.DualMirror = nil               -- "dual" mode, first person: the left pistol is the normal viewmodel and hands
                                    --   drawn mirrored (no second viewmodel needed; wins over DualCarrierVM)
SWEP.DualSpread = 0                 -- DualMirror: how far each hand moves out from the middle (units)
SWEP.DualMirrorPos = nil            -- DualMirror: left pistol nudge from its mirrored place (forward, right, up)
SWEP.DualMirrorAng = nil
SWEP.ModeFireGestures = nil         -- { mode = ACT_ } third-person firing gesture for a mode (sidearm: the short pistol one)
SWEP.DualBonePos = Vector(0, 0, 0)  -- prop offset on each of its gun bones (forward, right, up)
SWEP.DualBoneAng = Angle(0, 0, 0)
SWEP.DualMags = 2                   -- "dual" mode holds this many magazines (one per pistol)
SWEP.NoAim = false                  -- true: right mouse doesn't aim (the riot shield bashes instead)
SWEP.CarrierHideBones = nil         -- more carrier bones to hide (e.g. a built-in shield): { "bone", ... }
-- Extra props, each drawn on a bone in first and third person:
-- { key, model, vmBone, vmPos, vmAng, vmScale, wmBone, wmPos, wmAng, wmScale }
SWEP.ExtraProps = nil
SWEP.CarrierInvisible = false       -- true: the carrier itself isn't drawn, only the hands (an HL2 c_ model as
                                    -- arms only); CarrierBone is then a hand bone and is not shrunk
SWEP.CarrierBoneMods = nil          -- carrier bone moves every frame: { ["bone"] = { pos = Vector, ang = Angle } }
SWEP.WorldBoneMods = nil            -- the holder's bone turns in third person (client side, not while lowered):
                                    -- { ["bone"] = Angle }
SWEP.FireAct = nil                  -- viewmodel activity per shot (nil = ACT_VM_PRIMARYATTACK, false = none)
SWEP.DualVMOffset = nil             -- viewmodel offset with the two-gun viewmodel (right, forward, up)
SWEP.DualBoneL = nil                -- the two-gun viewmodel's gun bones (nil = found by name)
SWEP.DualBoneR = nil

-- Magazine types this gun takes, preferred first (ids from W.MagTypes).
SWEP.Mags = { "mag_small" }
SWEP.ReloadTime = nil               -- seconds; nil = the viewmodel's reload animation length
SWEP.AutoReload = false             -- reload by itself when empty (off everywhere: reloading is manual)

-- Spin-up (rotary guns): hold fire this long before the first shot.
-- While spinning or firing, walk speed is multiplied by SpinMoveMult.
SWEP.SpinUp = nil                   -- seconds, nil = fires at once
SWEP.SpinMoveMult = 0.6

-- Explosive bolts (rockets): { radius = units, damage = at the centre }.
-- The bolt then does blast damage where it hits instead of a direct hit.
SWEP.Explosive = nil
SWEP.BoltLife = nil                 -- seconds before a bolt that hit nothing is gone; nil = config

SWEP.UsesCell = false
SWEP.CellShots = 500                -- shots from one full power cell
SWEP.CellReloadMult = 1.6           -- cell swap takes this much longer than a magazine swap

-- Spare ammo given when the weapon is picked up (of the preferred
-- magazine type). Testing only, until armouries exist.
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Size in the inventory grid (cells). InvLarge = can't go in a backpack.
SWEP.InvW = 3
SWEP.InvH = 1
SWEP.InvLarge = false
SWEP.InvWeight = 3                  -- kg

-- Cone angles in degrees. See rhylib/weapons/sh_10_spread.lua.
-- View recoil per shot (cl_50_recoil.lua): degrees up, random sideways,
-- sideways lean (-1 left .. 1 right), share that settles back, aiming mult.
SWEP.Recoil = { up = 0.6, side = 0.25, bias = 0, recover = 0.6, aimMult = 0.65 }

SWEP.Spread = {
    hip = 1.4,              -- resting cone, hip-fire
    aim = 0.7,              -- resting cone, aiming
    kickMain = 0.35,        -- kick on the arc nearest the shot (times the streak)
    kickSide = 0.1,         -- kick on the other two arcs
    bloomPerShot = 0.11,    -- shared bloom per shot
    bloomMax = 2.0,
    aimKickMult = 0.5,      -- kicks and bloom added while aiming
    aimOffsetMult = 0.6,    -- all arc offsets while aiming
}

SWEP.AimPos = Vector(-2, 0, 1)      -- viewmodel offset when aiming (right, forward, up)
SWEP.AimFov = 0.85                  -- FOV multiplier when aiming
SWEP.Scope = nil                    -- true: aiming looks through a scope (gun hidden, AimFov zoom, scope overlay)
SWEP.ScopeSkill = nil               -- skill needed to use the scope (rhylib_skills); without it, a normal aim
SWEP.ClipCap = nil                  -- most rounds loaded from one magazine (the rest stays in it)
SWEP.Pellets = nil                  -- bolts per shot (shotguns), each uses one round
SWEP.PelletCone = 0                 -- extra spread of the pellets, degrees
SWEP.PropBodygroups = nil           -- { [index] = value } set on the prop model

--[[
    Prop models: a plain prop (no arms, no animations) can be used as the
    gun. Third person: attached to the right hand (PropWMPos / PropWMAng).
    First person with a carrier (SWEP.CarrierVM, a c_ viewmodel with its
    gun on one bone, e.g. the Battlefront ones from Reworked Assets): that
    model plays its animations with the player's hands (UseHands), its gun
    bone (CarrierBone) is shrunk away and the prop is drawn on that bone at
    PropBonePos / PropBoneAng / PropBoneScale (the SCK/TFA technique).
    Without a carrier (or if its model is missing) the prop floats
    (PropVMPos / PropVMAng). Tune in game with rhylib_vm_editor.
]]
SWEP.PropModel = nil
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(0, 0, 0)    -- first person: forward, right, up from the view
SWEP.PropVMAng = Angle(0, 0, 0)     -- first person: pitch, yaw, roll
SWEP.PropWMPos = Vector(0, 0, 0)    -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)
SWEP.PropMuzzle = Vector(0, 0, 0)   -- muzzle point in the prop's own coordinates
SWEP.PropFirstPerson = true         -- false: first person shows SWEP.ViewModel as it is (a real v_/c_ model); the prop is third person only
SWEP.ReloadAct = ACT_VM_RELOAD       -- the viewmodel's reload animation (some models only have ACT_VM_RELOAD_EMPTY)
SWEP.CarrierVM = nil                -- c_ viewmodel whose hands hold the prop in first person
SWEP.CarrierBone = nil              -- its gun bone: shrunk, the prop sits on it
SWEP.CarrierBoneMove = nil          -- optional Vector: ManipulateBonePosition for that bone
SWEP.PropBonePos = Vector(0, 0, 0)  -- prop from the carrier bone: forward, right, up
SWEP.PropBoneAng = nil               -- (nil or false = worked out on an idle frame so the prop points
                                    -- like the floating gun did, PropVMAng; printed to the console)
SWEP.PropBoneScale = nil            -- first-person prop scale (nil = PropScale)
SWEP.CarrierFOV = nil               -- viewmodel FOV with the carrier (nil = ViewModelFOV)
SWEP.SafePose = nil                 -- carrier: pose while lowered (safety, sprint), blended in:
                                    -- { PropBonePos, PropBoneAng, PropBoneScale, VMOffset, CarrierFOV },
                                    -- any left out = the normal value
SWEP.SafeBlendTime = 0.2            -- seconds to lower / raise the gun
SWEP.VMOffset = nil                 -- viewmodel offset with the carrier: right, forward, up
                                    -- (nil = worked out on first idle frame so the prop sits at
                                    -- PropVMPos, where the floating gun was; printed to the console)

local RELOAD_NONE, RELOAD_MAG, RELOAD_CELL = 0, 1, 2

function SWEP:SetupDataTables()
    -- The three arc kicks (Recoil) and bloom, streak and last arc
    -- (RecoilB), packed into two Ints (see sh_10_spread.lua), so a shot
    -- changes 3 network vars instead of 7.
    self:NetworkVar("Int", 7, "Recoil")
    self:NetworkVar("Int", 0, "RecoilB")
    self:NetworkVar("Float", 4, "KickTime")
    self:NetworkVar("Float", 5, "ReloadEnd")
    self:NetworkVar("Float", 6, "Cell")
    self:NetworkVar("Float", 7, "SpinStart")   -- when the barrels started spinning, 0 = not spinning
    self:NetworkVar("Int", 2, "ReloadKind")
    self:NetworkVar("Int", 3, "FireMode")
    self:NetworkVar("Int", 4, "BurstLeft")
    self:NetworkVar("Int", 5, "MagType")       -- index of the loaded magazine type, 0 = none
    self:NetworkVar("Int", 6, "ReloadMag")     -- magazine type being loaded
    self:NetworkVar("Bool", 0, "Aiming")
    self:NetworkVar("Bool", 1, "Safety")
    self:NetworkVar("Bool", 2, "TriggerReady")
    self:NetworkVar("Bool", 3, "Lowered")      -- lowered while sprinting

    -- Lowered hold on every client as soon as safety or sprinting changes.
    self:NetworkVarNotify("Safety", self.OnLoweredChanged)
    self:NetworkVarNotify("Lowered", self.OnLoweredChanged)
    self:NetworkVarNotify("FireMode", self.OnFireModeChanged)
end

-- Player animations from the hold type; a mode can swap the firing
-- gesture (ModeFireGestures: the revolver hold's recoil is long and slow).
-- Same as weapon_base otherwise.
local FIRE_ACTS = { [ACT_MP_ATTACK_STAND_PRIMARYFIRE] = true, [ACT_MP_ATTACK_CROUCH_PRIMARYFIRE] = true }
function SWEP:TranslateActivity(act)
    if self.ModeFireGestures and FIRE_ACTS[act] then
        local g = self.ModeFireGestures[self:GetFireModeName()]
        if g then return g end
    end
    if self.ActivityTranslate and self.ActivityTranslate[act] ~= nil then return self.ActivityTranslate[act] end
    return -1
end

-- Hold type while lowered or sprinting: pistol grips (one or two pistols)
-- hang the guns at the sides ("normal"), not across the chest like a rifle
-- ("passive"; owner: dual pistols sprinted like a DC-15). SWEP.LoweredHold overrides.
local SIDEARM_HOLDS = { pistol = true, duel = true, revolver = true }
function SWEP:LoweredHoldType()
    if self.LoweredHold then return self.LoweredHold end
    return SIDEARM_HOLDS[self:ActiveHoldType()] and "normal" or "passive"
end

-- Hold type for the current fire mode (dual pistols hold both). mode: an
-- index or a mode name (nil = the current one).
function SWEP:ActiveHoldType(mode)
    local name
    if isnumber(mode) then name = self:ModeNameAt(mode) else name = mode or self:GetFireModeName() end
    if self.DualHoldType and name == "dual" then return self.DualHoldType end
    if self.ModeHoldTypes and name and self.ModeHoldTypes[name] then return self.ModeHoldTypes[name] end
    return self.HoldType
end

function SWEP:OnFireModeChanged(_, _, new)
    -- (the stored mode isn't updated yet inside this notify: work from new)
    local name = self:ModeNameAt(new)
    self.rhylibModeCache = nil
    self:ApplyDualViewModel(name == "dual")
    self:ApplyModeCarrier(name, true)
    if SERVER then
        -- Out of dual: a second pistol's worth of rounds goes back to the pouch.
        timer.Simple(0, function() if IsValid(self) and self.TrimClip then self:TrimClip() end end)
    end
    if self:IsLowered() then return end
    self:SetHoldType(self:ActiveHoldType(name))
end

-- A fire mode's proxy viewmodel (SWEP.ModeProxies = { mode = { model, bone,
-- PropBonePos, PropBoneAng, PropBoneScale, VMOffset } }), when in that mode
-- with the normal carrier in use and the model installed; else nil.
function SWEP:ActiveProxy()
    local p = self.ModeProxies and self.rhylibCarrier and self.ModeProxies[self:GetFireModeName()]
    if not p then return nil end
    if p.ok == nil then p.ok = util.IsValidModel(p.model or "") end
    return p.ok and p or nil
end

-- Mode carriers (SWEP.ModeCarriers): the mode's viewmodel values are put
-- on the weapon (its own values saved and put back after), and the
-- viewmodel model swapped. swap = also change the viewmodel model.
local MODE_KEYS = { "CarrierVM", "CarrierBone", "CarrierBoneMove", "PropBonePos", "PropBoneAng", "PropBoneScale",
    "VMOffset", "CarrierFOV", "AimPos", "SafePose" }
function SWEP:ApplyModeCarrier(name, swap)
    if not (self.ModeCarriers and self.rhylibCarrier) then return end
    name = name or self:GetFireModeName()
    local mc = self.ModeCarriers[name]
    if mc and mc.ok == nil then mc.ok = util.IsValidModel(mc.CarrierVM or "") end
    if mc and not mc.ok then mc = nil end
    local key = mc and name or false
    if self.rhylibModeCarrier ~= key then
        -- Back to the weapon's own values first.
        local saved = self.rhylibModeSaved
        if saved then
            for _, k in ipairs(MODE_KEYS) do self[k] = saved[k] end
            self.ViewModel = saved.ViewModel
            self.ViewModelFOV = saved.ViewModelFOV
            self.rhylibModeSaved = nil
        end
        if mc then
            saved = {}
            for _, k in ipairs(MODE_KEYS) do saved[k] = self[k] end
            saved.ViewModel, saved.ViewModelFOV = self.ViewModel, self.ViewModelFOV
            self.rhylibModeSaved = saved
            for _, k in ipairs(MODE_KEYS) do
                if mc[k] ~= nil then self[k] = mc[k] end
            end
            self.SafePose = mc.SafePose or false
            self.ViewModel = mc.CarrierVM
            if mc.CarrierFOV then self.ViewModelFOV = mc.CarrierFOV end
        end
        self.rhylibModeCarrier = key
    end
    if not swap then return end
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer() and o:GetActiveWeapon() == self) then return end
    local vm = o:GetViewModel()
    local want = self.ViewModel
    if IsValid(vm) and want and vm:GetModel() ~= want and not self:DualViewModelOn() then
        vm:SetWeaponModel(want, self)
        self:SendWeaponAnim(ACT_VM_DRAW)
    end
end

-- Is the two-gun viewmodel usable? (checked once)
function SWEP:HasDualCarrier()
    if self.DualMirror then return false end
    if self.dualCarrierOK == nil then
        self.dualCarrierOK = self.DualCarrierVM and self.PropModel and util.IsValidModel(self.DualCarrierVM) or false
    end
    return self.dualCarrierOK
end

-- Two-gun viewmodel on (dual) or back to the normal one.
function SWEP:ApplyDualViewModel(dual)
    local o = self:GetOwner()
    -- (only with the normal carrier too: that's what turns the hands on)
    if not (IsValid(o) and o:IsPlayer() and o:GetActiveWeapon() == self) or not self:HasDualCarrier() or not self.rhylibCarrier then return end
    local vm = o:GetViewModel()
    if not IsValid(vm) then return end
    local want = dual and self.DualCarrierVM or self.ViewModel
    if vm:GetModel() ~= want then
        vm:SetWeaponModel(want, self)
        self:SendWeaponAnim(ACT_VM_DRAW)
    end
end

function SWEP:DualViewModelOn()
    if not self:HasDualCarrier() or self:GetFireModeName() ~= "dual" then return false end
    local o = self:GetOwner()
    local vm = IsValid(o) and o:IsPlayer() and o:GetViewModel()
    return IsValid(vm) and vm:GetModel() == self.DualCarrierVM
end

-- rhylib_skills (nil without it: nothing is gated).
local function skills() return Rhylib.Skills end

-- Safety on, or lowered while sprinting: gun down, can't fire or aim.
function SWEP:IsLowered()
    return self:GetSafety() or self:GetLowered()
end

-- Notify callbacks run before the new value is stored, so take it from the args.
function SWEP:OnLoweredChanged(name, _, on)
    local safety = name == "Safety" and on or (name ~= "Safety" and self:GetSafety())
    local lowered = name == "Lowered" and on or (name ~= "Lowered" and self:GetLowered())
    self:SetHoldType((safety or lowered) and self:LoweredHoldType() or self:ActiveHoldType())
end

-- Test mode (rhylib_infammo, admins): firing uses nothing, reloads are free.
function SWEP:InfiniteAmmo()
    local o = self:GetOwner()
    return IsValid(o) and o:IsPlayer() and o:GetNW2Bool("rhylib_infammo") or false
end

-- Is the carrier viewmodel in use? (set in Initialize)
function SWEP:UsesCarrier()
    return self.rhylibCarrier == true
end

function SWEP:Initialize()
    local c = self.CarrierVM
    if c and self.CarrierBone and self.PropModel and self.PropFirstPerson ~= false and util.IsValidModel(c) then
        self.ViewModel = c
        self.UseHands = true
        if self.CarrierFOV then self.ViewModelFOV = self.CarrierFOV end
        self.CarrierFOV = self.ViewModelFOV
        self.rhylibCarrier = true
    end
    self:SetHoldType(self:IsLowered() and self:LoweredHoldType() or self:ActiveHoldType())
    if self.UsesCell then self:SetCell(1) end
    if self:GetFireMode() == 0 then self:SetFireMode(1) end
    if self:GetMagType() == 0 then
        local m = Rhylib.Weapons.MagTypes[self.Mags[1]]
        if m then self:SetMagType(m.index) end
    end
    self:SetTriggerReady(true)
end

-- The grapple mode sits after the weapon's own modes (index #FireModes + 1).
-- The mode name used at index i: the grapple slot, the mode itself if
-- allowed, the mode that replaces it (sidearm for semi), else the first
-- allowed one (a skill since lost or gained).
function SWEP:ModeNameAt(i)
    if self.Grapple and i == #self.FireModes + 1 then return "grapple" end
    if not self:ModeAllowed(i) then i = self:ReplacementFor(i) or self:FirstAllowedMode() end
    return self.FireModes[i] or self.FireModes[1] or "semi"
end

-- (asked many times a frame and per shot: worked out once per tick per mode)
function SWEP:GetFireModeName()
    local m, t = self:GetFireMode(), CurTime()
    local c = self.rhylibModeCache
    if c and c[1] == m and c[2] == t then return c[3] end
    local name = self:ModeNameAt(m)
    self.rhylibModeCache = { m, t, name }
    return name
end

-- Index of an allowed mode that replaces mode i (ModeReplaces), or nil.
function SWEP:ReplacementFor(i)
    local name = self.FireModes[i]
    if not (name and self.ModeReplaces) then return nil end
    for other, replaced in pairs(self.ModeReplaces) do
        if replaced == name then
            for j, n in ipairs(self.FireModes) do
                if n == other and self:ModeAllowedBase(j) then return j end
            end
        end
    end
end

-- The first mode the owner may use (1 if none).
function SWEP:FirstAllowedMode()
    for i = 1, #self.FireModes do
        if self:ModeAllowed(i) then return i end
    end
    return 1
end

-- How many of this gun the owner carries (rhylib_inventory; without it, 2).
function SWEP:CarriedCount()
    local o = self:GetOwner()
    local Inv = Rhylib.Inventory
    if not (IsValid(o) and o:IsPlayer() and Inv) then return 2 end
    local class = self:GetClass()
    if SERVER then return Inv.Count and Inv.Count(o, class) or 2 end
    if o ~= LocalPlayer() or not Inv.byUid then return 2 end   -- (others' inventories aren't known here)
    local n = 0
    for _, it in pairs(Inv.byUid) do
        if it.id == class then n = n + (it.count or 1) end
    end
    return n
end

-- Is fire mode i usable by the owner (SkillModes; dual needs two of the
-- gun; not while a mode that replaces it is allowed, e.g. sidearm for semi)?
function SWEP:ModeAllowed(i)
    if self.ModeReplaces and self:ReplacementFor(i) then return false end
    return self:ModeAllowedBase(i)
end

-- The same without replacements (one level, so no loops).
function SWEP:ModeAllowedBase(i)
    local name = self.FireModes[i]
    if not name then return true end
    if name == "dual" and self:CarriedCount() < 2 then return false end
    if name == "stun" then   -- military police only (rhylib_mp)
        local MP = Rhylib.MP
        return MP and MP.IsMP and MP.IsMP(self:GetOwner()) or false
    end
    local K = skills()
    if not (K and K.ModeAllowed) then return true end
    return K.ModeAllowed(self:GetOwner(), self, name)
end

-- Back to the first mode if the current one isn't allowed any more.
function SWEP:FixFireMode()
    local m = self:GetFireMode()
    if self.FireModes[m] and not self:ModeAllowed(m) then
        self:SetFireMode(self:ReplacementFor(m) or self:FirstAllowedMode())
        self:SetBurstLeft(0)
    end
end

-- The scope, if the owner may use it (SWEP.ScopeSkill).
function SWEP:HasScope()
    if self.Scope ~= true then return false end
    local K = skills()
    return not (K and K.ScopeAllowed) or K.ScopeAllowed(self:GetOwner(), self)
end

function SWEP:InGrappleMode()
    return self.Grapple and self:GetFireMode() == #self.FireModes + 1
end

-- Magazine helpers --------------------------------------------------------

function SWEP:TakesMag(id)
    for i = 1, #self.Mags do
        if self.Mags[i] == id then return true end
    end
    return false
end

-- The preferred magazine id this owner may load (Heavy feed skips the
-- Z-6's large ones for others).
function SWEP:FirstMagFor(owner)
    local K = skills()
    if K and K.MagAllowed and IsValid(owner) then
        for i = 1, #self.Mags do
            if K.MagAllowed(owner, self, self.Mags[i]) then return self.Mags[i] end
        end
    end
    return self.Mags[1]
end

-- The loaded magazine type (table from W.MagTypes) or nil.
function SWEP:GetMag()
    return Rhylib.Weapons.MagByIndex[self:GetMagType()]
end

-- Rounds a full magazine of type m holds for this gun's owner (skills
-- can add some: Extended mags).
function SWEP:MagRounds(m)
    local n = m.rounds
    local K = skills()
    if K and K.MagBonus then n = n + K.MagBonus(self:GetOwner(), m.id) end
    return n
end

-- Shots the loaded magazine holds when full.
function SWEP:GetMagSize()
    local m = self:GetMag()
    local n = m and self:MagRounds(m) or self.Primary.ClipSize
    if self.ClipCap then n = math.min(n, self.ClipCap) end
    if self:GetFireModeName() == "dual" then n = n * (self.DualMags or 2) end   -- (one magazine per pistol)
    return n
end

if SERVER then
    -- A clip over the current size (left dual mode) gives the rest back.
    function SWEP:TrimClip()
        local m = self:GetMag()
        local size = self:GetMagSize()
        local extra = self:Clip1() - size
        if not m or extra <= 0 or self:InfiniteAmmo() then return end
        local o = self:GetOwner()
        self:SetClip1(size)
        if not IsValid(o) or not o:IsPlayer() then return end
        local full = self:MagRounds(m)
        while extra > 0 do
            Rhylib.Weapons.Pouch.Add(o, m.id, math.min(1, extra / full), true, self.magIssued)
            extra = extra - full
        end
    end
end

function SWEP:Deploy()
    self:SetAiming(false)
    self:FixFireMode()
    if self:GetFireModeName() == "dual" then self:ApplyDualViewModel(true) end
    self:ApplyModeCarrier(nil, true)
    return true
end

function SWEP:Holster()
    self:SetAiming(false)
    self:SetBurstLeft(0)
    self:SetSpinStart(0)
    self:SetLowered(false)
    self:CancelReload()
    return true
end

if SERVER then
    -- E + R (sent by cl_30_reload.lua).
    function SWEP:CycleFireMode()
        local n = #self.FireModes
        local G = Rhylib.Weapons.Grapple
        local owner = self:GetOwner()
        local grapple = self.Grapple and G and IsValid(owner)
            and Rhylib.Weapons.Pouch.Count(owner, G.ITEM) > 0
        local total = n + (grapple and 1 or 0)
        if self:GetSafety() or total <= 1 then
            self:EmitSound("Weapon_AR2.Empty", 60)
            return
        end
        local cur = self:GetFireMode()
        if cur < 1 or cur > total then cur = 1 end
        -- Next mode the owner may use (skill-gated modes are skipped).
        local nextMode = cur
        for _ = 1, total do
            nextMode = nextMode % total + 1
            if nextMode > n or self:ModeAllowed(nextMode) then break end
        end
        if nextMode == cur then
            self:EmitSound("Weapon_AR2.Empty", 60)
            return
        end
        if nextMode == n + 1 then self.preGrappleMode = cur end
        self:SetFireMode(nextMode)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/smg1/switch_burst.wav", 60)
    end

    -- Back to the fire mode used before switching to grapple.
    function SWEP:LeaveGrappleMode()
        if not self:InGrappleMode() then return end
        local m = self.preGrappleMode
        self:SetFireMode(self.FireModes[m or 0] and m or 1)
    end

    -- Shift + E + R.
    function SWEP:ToggleSafety()
        local on = not self:GetSafety()
        self:SetSafety(on)
        self:SetAiming(false)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/smg1/switch_single.wav", 60)
    end
end

--------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------

-- Damage drops once the power cell is nearly empty.
function SWEP:GetCellDamageMult()
    if not self.UsesCell then return 1 end
    local low = Rhylib.Config.Get("weapons", "lowCellThreshold")
    local cell = self:GetCell()
    if cell >= low then return 1 end
    return Lerp(cell / low, Rhylib.Config.Get("weapons", "lowCellMinDamage"), 1)
end

-- Large weapons (InvLarge) are too heavy to fire while flying a jetpack.
function SWEP:TooHeavyToFire()
    local owner = self:GetOwner()
    local jp = Rhylib.Jetpack
    return self.InvLarge and IsValid(owner) and owner:IsPlayer() and jp and jp.Flying and jp.Flying(owner) or false
end

function SWEP:CanPrimaryAttack()
    if self:IsLowered() then return false end
    if self:GetReloadKind() ~= RELOAD_NONE then return false end
    if self:TooHeavyToFire() then return false end

    if self:Clip1() <= 0 then
        self:EmitSound("Weapon_Pistol.Empty")
        self:SetNextPrimaryFire(CurTime() + 0.3)
        return false  -- empty: just the click, reloading is up to you (R)
    end

    if self.UsesCell and self:GetCell() <= 0 then
        self:EmitSound("Weapon_AR2.Empty")
        self:SetNextPrimaryFire(CurTime() + 0.3)
        return false
    end

    return true
end

-- Called by the engine every tick while the trigger is held (Automatic
-- is always true). The fire mode decides whether that fires.
function SWEP:PrimaryAttack()
    if self:GetBurstLeft() > 0 then return end  -- a burst is running (Think fires it)
    if self:GetLowered() then return end        -- sprinting: gun is down

    local mode = self:GetFireModeName()
    if mode ~= "auto" or self:GetSafety() then
        if not self:GetTriggerReady() then return end
        self:SetTriggerReady(false)
    end

    if self:GetSafety() then
        self:EmitSound("Weapon_Pistol.Empty", 60)
        return
    end
    if mode == "grapple" then
        self:FireGrapple()
        return
    end
    -- Rotary guns wait for spin-up (an empty gun skips it, so you still
    -- hear the empty click).
    if self:Clip1() > 0 and not self:SpunUp() then return end
    if not self:CanPrimaryAttack() then return end

    if mode == "burst" then self:SetBurstLeft(self.BurstCount - 1) end
    self:FireShot()
end

-- Rounds per minute right now (burst, dual and skills).
function SWEP:CurrentFireRate()
    local mode = self:GetFireModeName()
    if mode == "stun" then return self.StunFireRate end
    local rate = (mode == "burst" and self.BurstFireRate) or self.FireRate
    local K = skills()
    if K and K.FireRateMult then rate = rate * K.FireRateMult(self:GetOwner(), self, mode) end
    return rate
end

-- The MP "stun" fire mode: slow blue rings that do no damage (rhylib_mp).
local STUN_OPTS = { stun = true, color = 6, speed = 2600 }
SWEP.StunFireRate = 75   -- one ring every 0.8 s

-- One shot: spread, recoil, ammo, sound and the bolt.
function SWEP:FireShot()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local now = CurTime()
    self:SetNextPrimaryFire(now + 60 / self:CurrentFireRate())

    local Spread = Rhylib.Weapons.Spread
    local dir, a = Spread.ShotDirection(self, owner:EyeAngles(), 0)
    local K = skills()
    local damage = self.Damage * self:GetCellDamageMult()
    if K and K.ShotDamageMult then damage = damage * K.ShotDamageMult(owner, self) end   -- (First shot, before AddShot)
    Spread.AddShot(self, Spread.NearestArc(a), now)
    -- Shotguns: Pellets bolts, one round each (fewer when the clip is low).
    local pellets = self.Pellets or 1
    if not self:InfiniteAmmo() then
        pellets = math.max(1, math.min(pellets, self:Clip1()))
        self:TakePrimaryAmmo(pellets)
    end
    if self.UsesCell and not self:InfiniteAmmo() then
        local shots = self.CellShots * (K and K.CellMult and K.CellMult(owner) or 1)
        self:SetCell(math.max(0, self:GetCell() - 1 / shots))
    end

    local stun = self:GetFireModeName() == "stun"
    self:EmitSound(stun and "weapons/stunstick/spark2.wav" or self.FireSound, 80, util.SharedRandom("rhylib.pitch", 96, 104), 1, CHAN_WEAPON)
    -- Dual pistols take turns (left on odd rounds left).
    if CLIENT and IsFirstTimePredicted() then self.rhylibLeftShot = self:Clip1() % 2 == 1 end
    if self:DualViewModelOn() and self:Clip1() % 2 == 1 then
        self:SendWeaponAnim(ACT_VM_SECONDARYATTACK)
    elseif self.DualMirror and self:Clip1() % 2 == 1 and self:GetFireModeName() == "dual" then
        -- (mirrored dual: a left shot kicks only the mirrored hand, drawMirror)
        if CLIENT and IsFirstTimePredicted() then self.rhylibMirrorShot = RealTime() end
    elseif self.FireAct ~= false then
        self:SendWeaponAnim(self.FireAct or ACT_VM_PRIMARYATTACK)
        -- (mirrored dual: a right shot; the mirrored hand stays still, drawMirror)
        if CLIENT and self.DualMirror and IsFirstTimePredicted() then self.rhylibMainShot = RealTime() end
        -- (a proxy viewmodel plays its own fire animation, drawProxy)
        if CLIENT and self.ModeProxies and IsFirstTimePredicted() then self.rhylibProxyShot = RealTime() end
    end
    -- The third-person firing gesture (SWEP.PlayerFireAnim = false turns it
    -- off, for guns whose hold type's gesture looks wrong).
    if self.PlayerFireAnim ~= false then owner:SetAnimation(PLAYER_ATTACK1) end

    -- Recoil turns the real aim (not ViewPunch, which moved the screen
    -- centre off the aim). Singleplayer has no client prediction.
    if CLIENT and IsFirstTimePredicted() then
        Rhylib.Weapons.Recoil.Kick(self)
    elseif SERVER and game.SinglePlayer() then
        self:CallOnClient("RhylibRecoilKick")
    end

    local origin = owner:GetShootPos()
    local cone = self.PelletCone or 0
    if self.Pellets and K and K.PelletConeMult then cone = cone * K.PelletConeMult(owner, self) end   -- (Shotgun drills)
    for i = 1, pellets do
        local d = dir
        if self.Pellets then
            -- Around the shot's own direction (the cone shown when firing).
            local pa = util.SharedRandom("rhylib.pellet.a", 0, 2 * math.pi, i)
            local off = math.tan(math.rad(cone) * math.sqrt(util.SharedRandom("rhylib.pellet.r", 0, 1, i)))
            local da = d:Angle()
            d = da:Forward() + da:Right() * (math.cos(pa) * off) - da:Up() * (math.sin(pa) * off)
            d:Normalize()
        end
        local opts = stun and STUN_OPTS or nil
        if SERVER then
            Rhylib.Weapons.Bolts.Fire(owner, self, origin, d, stun and 0 or damage, opts)
        elseif IsFirstTimePredicted() then
            Rhylib.Weapons.Bolts.FireLocal(owner, self, origin, d, opts)
        end
    end
end

-- One grapple hook (see rhylib/weapons/sh_30_grapple.lua).
function SWEP:FireGrapple()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + Rhylib.Config.Get("grapple", "cooldown"))
    local G = Rhylib.Weapons.Grapple
    if IsFirstTimePredicted() then
        self:EmitSound("weapons/crossbow/fire1.wav", 70, 115)
        owner:SetAnimation(PLAYER_ATTACK1)
        -- Your own client draws the hook flying out straight away.
        if CLIENT and owner:GetAmmoCount(G.AMMO) > 0 then
            Rhylib.Weapons.Bolts.Spawn(owner, owner:GetShootPos(), owner:GetAimVector(),
                Rhylib.Config.Get("grapple", "hookSpeed"), 5)
        end
    end
    if SERVER then G.Fire(owner, self) end
end

function SWEP:RhylibRecoilKick()
    if CLIENT then Rhylib.Weapons.Recoil.Kick(self) end
end

function SWEP:SecondaryAttack()
    -- Right mouse is aim, handled in Think.
end

-- Spin-up ---------------------------------------------------------------

function SWEP:IsSpinning()
    return self.SpinUp ~= nil and self:GetSpinStart() > 0
end

function SWEP:SpunUp()
    if not self.SpinUp then return true end
    local start = self:GetSpinStart()
    return start > 0 and CurTime() - start >= self.SpinUp
end

-- Walk speed multiplier for this weapon right now (see sh_20_move.lua).
function SWEP:GetMoveMult()
    if self:IsSpinning() then
        local K = skills()
        if K and K.SpinMoveMult then return K.SpinMoveMult(self:GetOwner(), self, self.SpinMoveMult) end
        return self.SpinMoveMult
    end
    return 1
end

-- Runs in Think: spin while the trigger is held and the gun could fire.
function SWEP:UpdateSpin(owner)
    if not self.SpinUp then return end
    local want = owner:KeyDown(IN_ATTACK) and not self:IsLowered() and not self:IsReloading()
        and not self:TooHeavyToFire() and self:Clip1() > 0
    local spinning = self:GetSpinStart() > 0
    if want and not spinning then
        self:SetSpinStart(CurTime())
        if IsFirstTimePredicted() and self.SpinSound then self:EmitSound(self.SpinSound, 70) end
    elseif not want and spinning then
        self:SetSpinStart(0)
    end
end

--------------------------------------------------------------------------
-- Reloading
--------------------------------------------------------------------------

-- R is handled by the radial menu (cl_30_reload.lua), which asks the
-- server to reload. The default reload key action does nothing.
function SWEP:Reload()
end

function SWEP:IsReloading()
    return self:GetReloadKind() ~= RELOAD_NONE
end

function SWEP:CancelReload()
    if self:GetReloadKind() == RELOAD_NONE then return end
    self:SetReloadKind(RELOAD_NONE)
    self:SetNextPrimaryFire(CurTime())
    local owner = self:GetOwner()
    local vm = IsValid(owner) and owner:IsPlayer() and owner:GetViewModel()
    if IsValid(vm) then vm:SetPlaybackRate(1) end
end

if SERVER then
    local SOUNDS = {
        [RELOAD_MAG] = "weapons/smg1/smg1_reload.wav",
        [RELOAD_CELL] = "items/battery_pickup.wav",
    }

    -- Which magazine type a reload should load. magId: the type asked
    -- for, or nil for the best one. Returns a W.MagTypes entry or nil.
    function SWEP:ChooseMag(owner, magId)
        local W = Rhylib.Weapons
        local Pouch = W.Pouch
        local cur = self:GetMag()
        if self:InfiniteAmmo() then
            if magId and self:TakesMag(magId) then return W.MagTypes[magId] end
            return cur or W.MagTypes[self.Mags[1]]
        end
        local full = self:Clip1() >= self:GetMagSize()

        local K = skills()
        local function usable(id)
            if not self:TakesMag(id) or Pouch.Count(owner, id) == 0 then return false end
            if K and K.MagAllowed and not K.MagAllowed(owner, self, id) then return false end   -- (Heavy feed)
            return not (full and cur and cur.id == id)  -- same type into a full gun does nothing
        end

        if magId then return usable(magId) and W.MagTypes[magId] or nil end
        if cur and usable(cur.id) then return cur end
        for i = 1, #self.Mags do
            if usable(self.Mags[i]) then return W.MagTypes[self.Mags[i]] end
        end
    end

    -- kind: 1 = magazine, 2 = power cell. magId: magazine type (nil = best).
    function SWEP:StartReload(kind, magId)
        if self:IsReloading() then return end
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner:IsPlayer() then return end
        local W = Rhylib.Weapons

        if kind == RELOAD_MAG then
            local m = self:ChooseMag(owner, magId)
            if not m then
                -- Only magazines this owner may not load (Heavy feed): say so.
                local K = skills()
                if self.MagSkills and K and K.MagAllowed and (owner.rhylibMagNote or 0) < CurTime() then
                    for id, need in pairs(self.MagSkills) do
                        if W.Pouch.Count(owner, id) > 0 and not K.MagAllowed(owner, self, id) then
                            owner.rhylibMagNote = CurTime() + 2
                            local n = K.byId and K.byId[need]
                            owner:PrintMessage(HUD_PRINTCENTER, "Loading those needs the " .. (n and n.name or need) .. " skill")
                            break
                        end
                    end
                end
                return
            end
            self:SetReloadMag(m.index)
        elseif kind == RELOAD_CELL then
            if not self.UsesCell or (W.Pouch.Count(owner, W.CELL) == 0 and not self:InfiniteAmmo()) then return end
        else
            return
        end

        self:SendWeaponAnim(self.ReloadAct or ACT_VM_RELOAD)
        local vm = owner:GetViewModel()
        local animTime = IsValid(vm) and vm:SequenceDuration() or 2
        local duration = self.ReloadTime or animTime
        local rate = animTime / duration
        if kind == RELOAD_CELL then
            duration = duration * self.CellReloadMult
            rate = rate / self.CellReloadMult
        end
        local K = skills()
        local sm = K and K.ReloadMult and K.ReloadMult(owner, self, kind == RELOAD_CELL) or 1
        if sm ~= 1 then
            duration = duration * sm
            rate = rate / sm
        end
        if IsValid(vm) and rate ~= 1 then vm:SetPlaybackRate(rate) end

        local finish = CurTime() + duration
        self:SetReloadKind(kind)
        self:SetReloadEnd(finish)
        self:SetNextPrimaryFire(finish)
        self:SetAiming(false)
        owner:SetAnimation(PLAYER_RELOAD)
        self:EmitSound(SOUNDS[kind], 70)
    end

    function SWEP:FinishReload()
        local kind = self:GetReloadKind()
        self:SetReloadKind(RELOAD_NONE)
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        local W = Rhylib.Weapons
        local Pouch = W.Pouch

        local vm = owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(1) end
        self:SendWeaponAnim(ACT_VM_IDLE)   -- (the reload may outlast its animation)

        if self:InfiniteAmmo() then
            local m = W.MagByIndex[self:GetReloadMag()]
            if kind == RELOAD_MAG and m then
                self:SetMagType(m.index)
                self:SetClip1(self:GetMagSize())
            elseif kind == RELOAD_CELL then
                self:SetCell(1)
            end
            return
        end

        if kind == RELOAD_MAG then
            local m = W.MagByIndex[self:GetReloadMag()]
            local best, issued = nil, nil
            if m then best, issued = Pouch.TakeBest(owner, m.id) end
            if not best then return end
            local old = self:GetMag()
            local clip = math.max(self:Clip1(), 0)
            local full = self:MagRounds(m)
            local rounds = math.floor(best * full + 0.5)
            -- Dual pistols: one more magazine per extra pistol, if there is one.
            if self:GetFireModeName() == "dual" then
                for _ = 2, self.DualMags or 2 do
                    local more, moreIssued = Pouch.TakeBest(owner, m.id)
                    if not more then break end
                    rounds = rounds + math.floor(more * full + 0.5)
                    if moreIssued then issued = true end   -- (any issued magazine keeps the rounds issued)
                end
            end
            local oldIssued = self.magIssued
            self.magIssued = issued
            self:SetMagType(m.index)
            local cap = self:GetMagSize()
            if self.ClipCap and old and old.id == m.id then
                -- ClipCap, same type: top up from the magazine; what's left
                -- goes back as one magazine.
                local total = clip + rounds
                local load = math.min(total, cap)
                if total > load then Pouch.Add(owner, m.id, (total - load) / full, true, issued or oldIssued) end
                self:SetClip1(load)
            else
                -- ClipCap: what doesn't fit stays in the new magazine (back
                -- first, it frees the room it came from).
                local load = math.min(rounds, cap)
                local spare = rounds - load
                while spare > 0 do
                    Pouch.Add(owner, m.id, math.min(1, spare / full), true, issued)
                    spare = spare - full
                end
                -- The old magazine goes back with what's left in it (still
                -- issued if it came from an armoury).
                if old and clip > 0 then
                    local ofull = self:MagRounds(old)
                    while clip > 0 do   -- (a dual clip can be more than one magazine)
                        Pouch.Add(owner, old.id, math.min(1, clip / ofull), true, oldIssued)
                        clip = clip - ofull
                    end
                end
                self:SetClip1(load)
            end
        elseif kind == RELOAD_CELL then
            local best, issued = Pouch.TakeBest(owner, W.CELL)
            if not best then return end
            local old = self:GetCell()
            if old > 0.001 then Pouch.Add(owner, W.CELL, old, true, self.cellIssued) end
            self.cellIssued = issued
            self:SetCell(best)
        end
    end

    -- Without the inventory addon, picking up the weapon gives its start ammo.
    -- With it, rhylib_inventory handles pickups (see sv_20_pouch.lua).
    function SWEP:Equip(owner)
        if Rhylib.Inventory and Rhylib.Inventory.AddItem then return end
        if not IsValid(owner) or not owner:IsPlayer() then return end
        Rhylib.Weapons.Pouch.GiveStartAmmo(owner, self, false)
    end
end

-- Clip, magazine type and cell are kept in the inventory item while the
-- weapon is stored.
function SWEP:GetInventoryData()
    return {
        clip = self:Clip1(),
        mag = self:GetMagType(),
        cell = self.UsesCell and self:GetCell() or nil,
        mode = self:GetFireMode(),
        safe = self:GetSafety() or nil,
        -- Whether the loaded magazine / cell came from an armoury.
        magIssued = self.magIssued or nil,
        cellIssued = self.cellIssued or nil,
    }
end

function SWEP:SetInventoryData(data)
    data = data or {}
    local W = Rhylib.Weapons
    local m = W.MagByIndex[data.mag or 0]
    if not (m and self:TakesMag(m.id)) then m = W.MagTypes[self:FirstMagFor(self:GetOwner())] end
    if m then self:SetMagType(m.index) end
    -- (mode first: dual pistols hold two magazines)
    if data.mode and self.FireModes[data.mode] and self:ModeAllowed(data.mode) then self:SetFireMode(data.mode) end
    local want = data.clip or self:GetMagSize()
    if SERVER and want > self:GetMagSize() then
        -- (saved in dual mode, which isn't allowed now: the rest goes back as magazines)
        self:SetClip1(want)
        timer.Simple(0, function() if IsValid(self) then self:TrimClip() end end)
    else
        self:SetClip1(math.min(want, self:GetMagSize()))
    end
    if self.UsesCell then self:SetCell(data.cell or 1) end
    if data.safe then self:SetSafety(true) end
    -- An issued gun's own magazine and cell count as issued too.
    self.magIssued = data.magIssued or data.issued or nil
    self.cellIssued = data.cellIssued or data.issued or nil
end

-- Actually sprinting: sprint held, on the ground and moving faster than
-- a walk. Going by speed means a player too tired to sprint (held to walking
-- speed by rhylib_stamina) keeps the gun up.
function SWEP:OwnerSprinting(owner)
    if not owner:KeyDown(IN_SPEED) or not owner:OnGround() then return false end
    local walk = owner:GetWalkSpeed() * 1.1
    return owner:GetVelocity():Length2DSqr() > walk * walk
end

function SWEP:UpdateLowered(owner)
    local sprint = self:OwnerSprinting(owner)
    local K = skills()
    if sprint and K and K.RunAndGun and K.RunAndGun(owner, self) then sprint = false end   -- (Run and gun)
    if sprint == self:GetLowered() then return end
    self:SetLowered(sprint)
    if sprint then
        self:SetBurstLeft(0)
        self:SetAiming(false)
    else
        -- A short moment to bring the gun back up.
        self:SetNextPrimaryFire(math.max(self:GetNextPrimaryFire(), CurTime() + self.SprintRaiseTime))
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    if SERVER and self:IsReloading() and CurTime() >= self:GetReloadEnd() then
        self:FinishReload()
    end

    -- Launchers load the next round by themselves once the shot is away.
    if SERVER and self.AutoReload and self:Clip1() <= 0 and not self:IsReloading()
        and CurTime() >= self:GetNextPrimaryFire() and not self:GetSafety()
        and CurTime() >= (self.autoReloadTry or 0) then
        self.autoReloadTry = CurTime() + 0.5  -- with no rounds left, don't recount every tick
        self:StartReload(RELOAD_MAG)
    end

    self:UpdateLowered(owner)
    self:UpdateSpin(owner)

    -- Trigger released: the next semi shot or burst may fire.
    if not self:GetTriggerReady() and not owner:KeyDown(IN_ATTACK) then
        self:SetTriggerReady(true)
    end

    -- Keep a burst going after the first shot.
    local left = self:GetBurstLeft()
    if left > 0 and CurTime() >= self:GetNextPrimaryFire() then
        if self:CanPrimaryAttack() then
            self:FireShot()
            left = left - 1
            if left == 0 then self:SetNextPrimaryFire(self:GetNextPrimaryFire() + self.BurstDelay) end
            self:SetBurstLeft(left)
        else
            self:SetBurstLeft(0)
        end
    end

    local Med = Rhylib.Medical
    local want = not self.NoAim and owner:KeyDown(IN_ATTACK2) and not self:IsReloading() and not self:IsLowered()
        and not (Med and Med.CanAim and not Med.CanAim(owner))  -- hurt arms can't aim
    if want ~= self:GetAiming() then
        self:SetAiming(want)
    end
end

--------------------------------------------------------------------------
-- Client: aiming, crosshair, HUD and prop models
--------------------------------------------------------------------------

if CLIENT then
    -- Looking through the scope (most of the way aimed in)?
    local function thirdPerson()
        local tp = Rhylib.ThirdPerson
        return tp and tp.Active and tp.Active() or false
    end

    function SWEP:Scoped()
        return (self.aimFrac or 0) >= 0.8 and self:HasScope() and not thirdPerson()
    end

    -- Aim zoom; a scope only zooms in first person.
    function SWEP:EffectiveAimFov()
        if self.Scope and (thirdPerson() or not self:HasScope()) then return 0.85 end
        return self.AimFov
    end

    -- Scope overlay: black outside a circle, a soft dark edge, a light
    -- lens tint, the reticle and a range readout.
    local SEG = 96
    local ringCache = {}
    local function ring(cx, cy, r1, r2, col)
        surface.SetDrawColor(col)
        draw.NoTexture()
        local key = cx .. ":" .. cy .. ":" .. r1 .. ":" .. r2
        local polys = ringCache[key]
        if not polys then
            polys = {}
            for i = 0, SEG - 1 do
                local a0, a1 = i / SEG * math.pi * 2, (i + 1) / SEG * math.pi * 2
                local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
                polys[#polys + 1] = {
                    { x = cx + c0 * r1, y = cy + s0 * r1 },
                    { x = cx + c0 * r2, y = cy + s0 * r2 },
                    { x = cx + c1 * r2, y = cy + s1 * r2 },
                    { x = cx + c1 * r1, y = cy + s1 * r1 },
                }
            end
            if table.Count(ringCache) > 32 then ringCache = {} end
            ringCache[key] = polys
        end
        for i = 1, #polys do surface.DrawPoly(polys[i]) end
    end

    local BLACK = Color(0, 0, 0, 255)
    function SWEP:DrawScope()
        local w, h = ScrW(), ScrH()
        local cx, cy = math.floor(w * 0.5), math.floor(h * 0.5)
        local r = math.floor(h * 0.45)
        local accent = (Rhylib.UI and Rhylib.UI.Colors and Rhylib.UI.Colors.accent) or Color(90, 200, 255)

        -- Lens tint, then everything outside the lens black.
        surface.SetDrawColor(40, 90, 130, 22)
        surface.DrawRect(cx - r, cy - r, r * 2, r * 2)
        surface.SetDrawColor(BLACK)
        surface.DrawRect(0, 0, cx - r + 1, h)
        surface.DrawRect(cx + r - 1, 0, w - cx - r + 1, h)
        surface.DrawRect(cx - r, 0, r * 2, cy - r + 1)
        surface.DrawRect(cx - r, cy + r - 1, r * 2, h - cy - r + 1)
        ring(cx, cy, r, r * 1.5, BLACK)
        -- Soft dark edge inside the lens.
        for i = 1, 6 do
            ring(cx, cy, r - i * r * 0.018, r - (i - 1) * r * 0.018, Color(0, 0, 0, 150 - i * 22))
        end

        -- Reticle: thick posts from the edge, thin lines to a gap, a dot.
        local thin, thick, gap = math.max(1, math.floor(h / 900)), math.max(3, math.floor(h / 260)), r * 0.06
        surface.SetDrawColor(0, 0, 0, 230)
        surface.DrawRect(cx - r, cy - thick / 2, r * 0.55, thick)
        surface.DrawRect(cx + r * 0.45, cy - thick / 2, r * 0.55, thick)
        surface.DrawRect(cx - thick / 2, cy + r * 0.45, thick, r * 0.55)
        surface.DrawRect(cx - r * 0.45, cy - thin / 2, r * 0.45 - gap, thin)
        surface.DrawRect(cx + gap, cy - thin / 2, r * 0.45 - gap, thin)
        surface.DrawRect(cx - thin / 2, cy + gap, thin, r * 0.45 - gap)
        surface.DrawRect(cx - thin / 2, cy - r, thin, r - gap)
        -- Mil ticks on the lower and side lines (drop and lead marks).
        for i = 1, 4 do
            local d = gap + i * r * 0.08
            local len = (i % 2 == 0) and r * 0.035 or r * 0.02
            surface.DrawRect(cx - len / 2, cy + d, len, thin)
            surface.DrawRect(cx + d, cy - len / 2, thin, len)
            surface.DrawRect(cx - d, cy - len / 2, thin, len)
        end
        surface.SetDrawColor(accent.r, accent.g, accent.b, 255)
        surface.DrawRect(cx - thick / 2, cy - thick / 2, thick, thick)

        -- Range to whatever is under the reticle, in metres.
        local o = self:GetOwner()
        if IsValid(o) then
            local tr = util.TraceLine({ start = o:EyePos(), endpos = o:EyePos() + o:EyeAngles():Forward() * 32768, filter = o, mask = MASK_SHOT })
            local m = tr.Hit and math.floor(tr.HitPos:Distance(tr.StartPos) * 0.01905 + 0.5) or nil
            local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(18 * h / 1080)) or "DermaDefault"
            draw.SimpleText(m and (m .. " m") or "---", font, cx + r * 0.62, cy + r * 0.62, Color(accent.r, accent.g, accent.b, 220), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("x%.1f", 1 / (self.AimFov or 1)), font, cx - r * 0.62, cy + r * 0.62, Color(accent.r, accent.g, accent.b, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Smooth 0..1 value for the aim animation, client only.
    function SWEP:GetAimFrac()
        return self.aimFrac or 0
    end

    local ease = math.ease and math.ease.InOutSine or function(x) return x end
    -- Pistols when lowered/sprinting: where they idle, muzzles tipped up a
    -- little (owner: "just lifted a little up from where they are when aiming").
    -- The tilt turns around the eyes, so the offset pulls them back down.
    local PISTOL_LOWER = Vector(0, -1, -3)
    local PISTOL_TILT = 12

    function SWEP:GetViewModelPosition(pos, ang)
        local ft = FrameTime()
        self.aimFrac = math.Approach(self.aimFrac or 0, (self:GetAiming() or self.rhylibAimPreview) and 1 or 0, ft * 6)
        self.safeFrac = math.Approach(self.safeFrac or 0, self:IsLowered() and 1 or 0, ft / (self.SafeBlendTime or 0.2))

        local dual = self:DualViewModelOn()
        local o = dual and self.DualVMOffset or (not dual and self.rhylibCarrier and self:CarrierPose("VMOffset"))
        if o then pos = pos + ang:Right() * o.x + ang:Forward() * o.y + ang:Up() * o.z end
        -- (mirrored dual pistols: the right hand out to the side; the left is its mirror image)
        if self.DualMirror and (self.DualSpread or 0) ~= 0 and self:GetFireModeName() == "dual" then
            pos = pos + ang:Right() * self.DualSpread
        end
        if self.rhylibCarrier and self.SafePose then self.ViewModelFOV = self:CarrierPose("CarrierFOV") end

        local f = ease(self.aimFrac)
        -- (dual pistols: aiming only tightens the spread; owner: both guns slid left)
        if f > 0 and not dual and self:GetFireModeName() ~= "dual" then
            local off = self.AimPos * f
            pos = pos + ang:Right() * off.x + ang:Forward() * off.y + ang:Up() * off.z
        end

        -- On safety or sprinting: a rifle lowered and turned inward; pistols
        -- (one or two) held muzzle-up instead (owner: dual pistols ran like a rifle).
        local sf = ease(self.safeFrac)
        if sf > 0 then
            ang = Angle(ang.p, ang.y, ang.r)
            if self:LoweredHoldType() == "normal" then
                -- (SWEP.PistolLowerPos: right, forward, up; SWEP.PistolLowerTilt: degrees up)
                local lp = self.PistolLowerPos or PISTOL_LOWER
                pos = pos + ang:Right() * (lp.x * sf) + ang:Forward() * (lp.y * sf) + ang:Up() * (lp.z * sf)
                ang:RotateAroundAxis(ang:Right(), (self.PistolLowerTilt or PISTOL_TILT) * sf)
            else
                pos = pos - ang:Up() * (4 * sf) + ang:Right() * (1.5 * sf) - ang:Forward() * (2 * sf)
                ang:RotateAroundAxis(ang:Right(), -20 * sf)
                ang:RotateAroundAxis(ang:Up(), 18 * sf)
            end
        end
        -- (the mirrored left hand starts from here: its own reload dip and sway)
        self.rhylibVMBase = self.rhylibVMBase or {}
        self.rhylibVMBase[1], self.rhylibVMBase[2] = pos, Angle(ang.p, ang.y, ang.r)
        local k = self:ReloadDip(false)
        if k > 0 then pos, ang = self:ApplyReloadDip(pos, ang, k) end
        return pos, ang
    end

    -- Reload with no reload animation on the viewmodel (Battlefront models
    -- often have none): the gun dips down and tilts, then comes back. Dual
    -- mirrored pistols take turns: right in the first half, left in the second.
    -- Returns 0-1 for the right (left = true: the left hand).
    function SWEP:ReloadDip(left)
        if not self:IsReloading() then
            self.rhylibDipLen = nil
            return 0
        end
        local o = self:GetOwner()
        local vm = IsValid(o) and o:IsPlayer() and o:GetViewModel()
        if not IsValid(vm) then return 0 end
        local mdl = vm:GetModel()
        if self.rhylibDipModel ~= mdl then
            self.rhylibDipModel = mdl
            self.rhylibHasReload = vm:SelectWeightedSequence(self.ReloadAct or ACT_VM_RELOAD) >= 0
        end
        if self.rhylibHasReload and not self.DualMirror then return 0 end
        local left0 = math.max(self:GetReloadEnd() - CurTime(), 0)
        self.rhylibDipLen = self.rhylibDipLen or math.max(left0, 0.1)
        local t = math.Clamp(1 - left0 / self.rhylibDipLen, 0, 1)
        if self.DualMirror and self:GetFireModeName() == "dual" then
            t = left and math.Clamp(t * 2 - 1, 0, 1) or math.Clamp(t * 2, 0, 1)
        elseif left or self.rhylibHasReload then
            return 0
        end
        return math.sin(math.pi * t) ^ 0.7
    end

    function SWEP:ApplyReloadDip(pos, ang, k)
        pos = pos - ang:Up() * (4 * k) - ang:Forward() * (2 * k)
        ang = Angle(ang.p, ang.y, ang.r)
        ang:RotateAroundAxis(ang:Right(), -25 * k)
        ang:RotateAroundAxis(ang:Forward(), 20 * k)
        return pos, ang
    end

    -- A carrier pose value, blended towards SafePose while lowered (same
    -- easing as the lowering). key: PropBonePos, PropBoneAng, PropBoneScale,
    -- VMOffset or CarrierFOV.
    local POSE_DEFAULT = { PropBoneScale = function(w) return w.PropScale end }
    function SWEP:CarrierPose(key)
        local v = self[key]
        if v == nil and POSE_DEFAULT[key] then v = POSE_DEFAULT[key](self) end
        local safe = self.SafePose and self.SafePose[key]
        local sf = safe and ease(self.safeFrac or 0) or 0   -- (SafePose false = a fire mode without one, ApplyModeCarrier)
        if sf <= 0 or v == nil then return v end
        if sf >= 1 then return safe end
        if isangle(v) then return LerpAngle(sf, v, safe) end
        if isvector(v) then return LerpVector(sf, v, safe) end
        return Lerp(sf, v, safe)
    end

    function SWEP:TranslateFOV(fov)
        return fov * Lerp(self:GetAimFrac(), 1, self:EffectiveAimFov())
    end

    function SWEP:AdjustMouseSensitivity()
        if self:GetAimFrac() > 0 then
            return Lerp(self:GetAimFrac(), 1, self:EffectiveAimFov())
        end
    end

    function SWEP:DoDrawCrosshair(x, y)
        if self:IsLowered() or self:Scoped() then return true end  -- no crosshair on safety or while sprinting
        local o = self:GetOwner()
        if IsValid(o) and o:GetNW2Int("rhylib_optics", 0) ~= 0 and not o:GetNW2Bool("rhylib_opticsFire", false) then return true end   -- (rhylib_gear: looking through binoculars)
        -- In Rhylib third person, rhylib_thirdperson draws it instead.
        local tp = Rhylib.ThirdPerson
        if not (tp and tp.Active and tp.Active()) then
            Rhylib.Weapons.Crosshair.Draw(self, x, y)
        end
        return true
    end

    local RELOAD_TEXT = {
        [RELOAD_MAG] = "Reloading magazine",
        [RELOAD_CELL] = "Replacing power cell",
    }

    function SWEP:DrawHUD()
        local UI = Rhylib.UI
        local s = ScrH() / 1080
        if self:Scoped() then self:DrawScope() end

        -- rhylib_hud shows the cell in its ammo counter; this is the fallback.
        if self.UsesCell and not Rhylib.HUD then
            local cell = self:GetCell()
            local col = cell < Rhylib.Config.Get("weapons", "lowCellThreshold") and UI.Colors.bad or UI.Colors.text
            draw.SimpleText(string.format("Power cell %d%%", math.ceil(cell * 100)), UI.Font(22), ScrW() - 40 * s, ScrH() - 150 * s, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end

        -- One message under the crosshair at a time, most important first.
        local text, col, size
        local kind = self:GetReloadKind()
        if self:TooHeavyToFire() then
            text, col, size = "Too heavy to fire while flying", UI.Colors.bad, 20
        elseif kind ~= RELOAD_NONE then
            text, col, size = RELOAD_TEXT[kind], UI.Colors.textDim, 20
        elseif self:GetSafety() and not Rhylib.HUD then
            text, col, size = "Safety on", UI.Colors.textDim, 18
        end
        if text then
            draw.SimpleText(text, UI.Font(size), ScrW() * 0.5, ScrH() * 0.62, col, TEXT_ALIGN_CENTER)
        end
    end

    -- Prop model helpers ------------------------------------------------

    local function offsetTransform(pos, ang, offPos, offAng)
        local p = pos + ang:Forward() * offPos.x + ang:Right() * offPos.y + ang:Up() * offPos.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:GetPropEntity(key, scale)
        scale = scale or self.PropScale
        local ent = self[key]
        if IsValid(ent) and ent:GetModel() == self.PropModel then
            if ent.rhylibScale ~= scale then ent:SetModelScale(scale, 0) ent.rhylibScale = scale end
            return ent
        end
        if IsValid(ent) then ent:Remove() end
        ent = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return nil end
        ent:SetNoDraw(true)
        ent:SetModelScale(scale, 0)
        ent.rhylibScale = scale
        for k, v in pairs(self.PropBodygroups or {}) do ent:SetBodygroup(k, v) end
        self[key] = ent
        return ent
    end

    -- Dual pistols: was the last shot from the left gun? Your own shots are
    -- noted when fired; others' come with the shot message (wep.shot).
    function SWEP:IsLeftShot()
        if self.rhylibLeftShot ~= nil then return self.rhylibLeftShot end
        return self:Clip1() % 2 == 1
    end

    -- Where bolts should appear to leave the gun. Used by cl_10_bolts.lua.
    function SWEP:GetPropMuzzle(firstPerson, left)
        if not self.PropModel then return nil end
        if firstPerson and self.PropFirstPerson == false then return nil end   -- (the viewmodel's attachment)
        if firstPerson and self:Scoped() then
            local o = self:GetOwner()
            if IsValid(o) then
                local a = o:EyeAngles()
                return o:EyePos() + a:Forward() * 12 - a:Up() * 3
            end
        end
        -- Dual pistols: the left one fires on odd rounds left (as the anims).
        if left == nil then left = self:GetFireModeName() == "dual" and self:IsLeftShot() end
        if left then
            local p = firstPerson and self.propMuzzleVML or self.propMuzzleWML
            if p then return p end
        end
        return firstPerson and self.propMuzzleVM or self.propMuzzleWM
    end

    -- Carrier viewmodel: its gun bone is shrunk (and moved, CarrierBoneMove)
    -- every frame while a carrier weapon is drawn (the server's bone state
    -- overwrites client changes), and restored for anything else.
    local SHRINK, ONE, ZERO = Vector(0.009, 0.009, 0.009), Vector(1, 1, 1), Vector(0, 0, 0)

    local function carrierBone(self, vm)
        local b = vm:LookupBone(self.CarrierBone or "")
        return b
    end

    local function unshrink(vm)
        local i = vm.rhylibShrunk
        if not i then return end
        if i < (vm:GetBoneCount() or 0) then
            vm:ManipulateBoneScale(i, ONE)
            vm:ManipulateBonePosition(i, ZERO)
        end
        vm.rhylibShrunk = nil
    end

    local function shrink(self, vm)
        local b = carrierBone(self, vm)
        if vm.rhylibShrunk and vm.rhylibShrunk ~= b then unshrink(vm) end
        if not b or self.CarrierInvisible then return end
        vm:ManipulateBoneScale(b, SHRINK)
        vm:ManipulateBonePosition(b, self.CarrierBoneMove or ZERO)
        vm.rhylibShrunk = b
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.vmreset", function(vm, ply, wep)
        if IsValid(vm) and vm.rhylibShrunk and not (IsValid(wep) and wep.UsesCarrier and wep:UsesCarrier()) then
            unshrink(vm)
        end
    end)

    -- Extra props (ExtraProps) and extra hidden carrier bones (CarrierHideBones).
    function SWEP:GetExtraEntity(e, side)
        local key = "rhylibExtra_" .. e.key .. side
        local ent = self[key]
        if IsValid(ent) then return ent end
        if not util.IsValidModel(e.model) then return nil end
        ent = ClientsideModel(e.model, RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return nil end
        ent:SetNoDraw(true)
        ent:SetModelScale((side == "vm" and e.vmScale or e.wmScale) or 1, 0)
        self[key] = ent
        return ent
    end

    local function drawExtra(self, ent, matrix, pos, ang, scale)
        scale = scale or 1
        if ent.rhylibScale ~= scale then
            ent:SetModelScale(scale, 0)
            ent.rhylibScale = scale
        end
        local p, a = offsetTransform(matrix:GetTranslation(), matrix:GetAngles(), pos or Vector(), ang or Angle())
        ent:SetPos(p)
        ent:SetAngles(a)
        ent:SetupBones()
        ent:DrawModel()
    end

    local function extraShrink(self, vm, on)
        if not on then
            local n = vm:GetBoneCount() or 0
            for _, i in ipairs(vm.rhylibExtraShrunk or {}) do
                if i < n then vm:ManipulateBoneScale(i, ONE) end
            end
            vm.rhylibExtraShrunk = nil
            return
        end
        if vm.rhylibExtraShrunk then
            for _, i in ipairs(vm.rhylibExtraShrunk) do vm:ManipulateBoneScale(i, SHRINK) end
            return
        end
        local list = {}
        for _, name in ipairs(self.CarrierHideBones or {}) do
            local b = vm:LookupBone(name)
            if b then
                vm:ManipulateBoneScale(b, SHRINK)
                list[#list + 1] = b
            end
        end
        vm.rhylibExtraShrunk = list
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.extrareset", function(vm, ply, wep)
        if IsValid(vm) and vm.rhylibExtraShrunk and not (IsValid(wep) and wep.CarrierHideBones and wep.UsesCarrier and wep:UsesCarrier()) then
            extraShrink(nil, vm, false)
        end
    end)

    -- Hidden viewmodel (CarrierInvisible, the dual carrier): drawn with
    -- render blend 0. The hands are a separate entity drawn after the
    -- PostDrawViewModel hooks, so this hook puts the blend back before them
    -- (and before the props). Same hook id as in the grenade base.
    local function blendOff(vm)
        render.SetBlend(0)
        vm.rhylibBlendOff = true
    end

    Rhylib.Hook.Add("PostDrawViewModel", "weapons.blendreset", function(vm)
        if IsValid(vm) and vm.rhylibBlendOff then
            render.SetBlend(1)
            vm.rhylibBlendOff = nil
        end
    end, -1000)
    -- (Safety: a viewmodel that wasn't drawn after all.)
    Rhylib.Hook.Add("PreDrawHUD", "weapons.blendsafety", function()
        local lp = LocalPlayer()
        local vm = IsValid(lp) and lp:GetViewModel()
        if IsValid(vm) and vm.rhylibBlendOff then
            render.SetBlend(1)
            vm.rhylibBlendOff = nil
        end
    end)

    -- CarrierBoneMods: applied every frame (the server overwrites client bone
    -- changes), undone for other weapons. The indices touched are kept on the vm.
    local function boneMods(self, vm, on)
        if not on then
            local n = vm:GetBoneCount() or 0
            for _, i in ipairs(vm.rhylibBoneMods or {}) do
                if i < n then
                    vm:ManipulateBonePosition(i, ZERO)
                    vm:ManipulateBoneAngles(i, angle_zero)
                end
            end
            vm.rhylibBoneMods = nil
            return
        end
        local list = {}
        for name, m in pairs(self.CarrierBoneMods or {}) do
            local b = vm:LookupBone(name)
            if b then
                vm:ManipulateBonePosition(b, m.pos or ZERO)
                vm:ManipulateBoneAngles(b, m.ang or angle_zero)
                list[#list + 1] = b
            end
        end
        vm.rhylibBoneMods = list
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.invisreset", function(vm, ply, wep)
        if not IsValid(vm) then return end
        local carrier = IsValid(wep) and wep.UsesCarrier and wep:UsesCarrier()
        if vm.rhylibBoneMods and not (carrier and wep.CarrierBoneMods) then boneMods(nil, vm, false) end
    end)

    -- WorldBoneMods: the holder's own bones, client side, for everyone who
    -- draws them (not while lowered); undone when they switch away.
    Rhylib.Hook.Add("PrePlayerDraw", "weapons.worldbonemods", function(ply)
        local w = ply:GetActiveWeapon()
        local mods = IsValid(w) and w.WorldBoneMods
        if mods and w.IsLowered and w:IsLowered() then mods = nil end
        local had = ply.rhylibWorldMods
        if not mods and not had then return end
        if had and had ~= mods then
            for b in pairs(ply.rhylibWorldModBones or {}) do ply:ManipulateBoneAngles(b, angle_zero) end
            ply.rhylibWorldMods, ply.rhylibWorldModBones = nil, nil
        end
        if not mods then return end
        local bones = {}
        for name, a in pairs(mods) do
            local b = ply:LookupBone(name)
            if b then
                ply:ManipulateBoneAngles(b, a)
                bones[b] = true
            end
        end
        ply.rhylibWorldMods, ply.rhylibWorldModBones = mods, bones
    end)

    local function drawProp(self, pos, ang, scale)
        local ent = self:GetPropEntity("propVM", scale)
        if not ent then return end
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVM = ent:LocalToWorld(self.PropMuzzle * (scale or self.PropScale) / self.PropScale)
    end

    -- Proxy viewmodels: a clientside copy of a viewmodel plus the player's
    -- hands, animated by us, so a gun can show other hands without swapping
    -- the real (networked) viewmodel. Used two ways:
    --   DualMirror: the left hand and pistol of dual pistols, the viewmodel
    --     drawn again mirrored (the left-handed viewmodel trick: scale -1 on
    --     the model's left axis, back faces culled the other way).
    --   ModeProxies: a fire mode held with another viewmodel (DC-15S sidearm
    --     on the DC-17's pistol hands); the real viewmodel and hands are hidden.
    -- Each proxy plays its own fire animation from its own shot time, and
    -- its gun is drawn on ITS gun bone, so it moves with its own hand.
    local MIRROR = Matrix()
    MIRROR:Scale(Vector(1, -1, 1))

    local function proxyModel(self, key, model, mirrored)
        local ent = self[key]
        if IsValid(ent) and ent:GetModel() == model and ent.rhylibMirrored == mirrored then return ent end
        if IsValid(ent) then ent:Remove() end
        ent = ClientsideModel(model, RENDERGROUP_VIEWMODEL)
        if not IsValid(ent) then return nil end
        ent:SetNoDraw(true)
        if mirrored then ent:EnableMatrix("RenderMultiply", MIRROR) end
        ent.rhylibMirrored = mirrored
        self[key] = ent
        return ent
    end

    -- A sequence to rest on: the idle activity, one named "idle", or the
    -- last one it showed at rest (Battlefront viewmodels often have no activities).
    local function restSeq(ent)
        local idle = ent:SelectWeightedSequence(ACT_VM_IDLE)
        if not idle or idle < 0 then idle = ent:LookupSequence("idle") end
        if (not idle or idle < 0) and ent.rhylibRest then idle = ent.rhylibRest end
        return idle
    end

    local function playSeq(ent, seq, cyc)
        if ent:GetSequence() ~= seq then ent:SetSequence(seq) end
        ent:SetCycle(math.Clamp(cyc, 0, 1))
    end

    -- Animate a proxy: its fire animation for a while after `shot`, else
    -- follow (seq, cyc) when given, else rest. True if it fired.
    local function animate(ent, shot, followSeq, followCyc)
        local fireSeq = ent:SelectWeightedSequence(ACT_VM_PRIMARYATTACK)
        local fireLen = (fireSeq and fireSeq >= 0) and ent:SequenceDuration(fireSeq) or 0
        if shot and fireLen > 0 and RealTime() - shot < fireLen then
            playSeq(ent, fireSeq, (RealTime() - shot) / fireLen)
            return true
        end
        if followSeq then
            playSeq(ent, followSeq, followCyc)
            -- (remembered to rest on only if it's an idle, not a draw or reload)
            if ent:GetSequenceActivity(followSeq) == ACT_VM_IDLE or string.find(string.lower(ent:GetSequenceName(followSeq) or ""), "idle", 1, true) then
                ent.rhylibRest = followSeq
            end
            return false
        end
        local idle = restSeq(ent)
        if idle and idle >= 0 then
            local len = math.max(ent:SequenceDuration(idle), 0.1)
            playSeq(ent, idle, (RealTime() % len) / len)
        end
        return false
    end

    -- The player's hands on a proxy (bonemerged), drawn now.
    local function drawProxyHands(self, key, parent, mirrored)
        local hands = LocalPlayer():GetHands()
        if not (IsValid(hands) and hands:GetModel()) then return end
        local mh = proxyModel(self, key, hands:GetModel(), mirrored)
        if not mh then return end
        if mh:GetParent() ~= parent then
            mh:SetParent(parent)
            mh:AddEffects(EF_BONEMERGE)
            mh:SetLocalPos(vector_origin)     -- (lighting is sampled at the origin)
            mh:SetLocalAngles(angle_zero)
            -- (battalion colours: the PlayerColor material proxy asks the entity)
            mh.GetPlayerColor = function()
                local p = LocalPlayer()
                return IsValid(p) and p:GetPlayerColor() or Vector(1, 1, 1)
            end
        end
        if mh:GetSkin() ~= hands:GetSkin() then mh:SetSkin(hands:GetSkin()) end
        for i = 0, (hands:GetNumBodyGroups() or 1) - 1 do
            local v = hands:GetBodygroup(i)
            if mh:GetBodygroup(i) ~= v then mh:SetBodygroup(i, v) end
        end
        mh:DrawModel()
    end

    -- Bones fresh for this frame's sequence, its gun bone hidden.
    local function proxyBones(ent, boneName, move)
        local b = ent:LookupBone(boneName or "")
        if b and ent.rhylibShrunkB ~= b then
            ent:ManipulateBoneScale(b, SHRINK)
            ent:ManipulateBonePosition(b, move or ZERO)
            ent.rhylibShrunkB = b
        end
        ent:InvalidateBoneCache()
        ent:SetupBones()
        return b
    end

    local function mirrorVec(v, right) return v - right * (2 * v:Dot(right)) end

    local function drawMirror(self, vm)
        local mv = proxyModel(self, "rhylibMirrorVM", vm:GetModel(), true)
        if not mv then return end
        local vpos, vang = vm:GetPos(), vm:GetAngles()
        -- Its own pose: the weapon's placement before the right hand's
        -- reload dip and sway (rhylibVMBase), its own reload dip, and the
        -- step/breath sway a quarter cycle off, so the hands don't move as
        -- mirror images (owner: walking looked mirrored).
        local base = self.rhylibVMBase
        if base and base[1] then vpos, vang = base[1], base[2] end
        local k = self:ReloadDip(true)
        if k > 0 then vpos, vang = self:ApplyReloadDip(vpos, vang, k) end
        local right = vang:Right()
        -- Mirrored across the middle of the view (through the eyes).
        local eye = EyePos()
        local mpos = vpos - right * (2 * (vpos - eye):Dot(right))
        local Mo = Rhylib.Lying and Rhylib.Lying.motion
        local side, dip, dp, dy, dr
        if Mo and Mo.Sway then side, dip, dp, dy, dr = Mo.Sway(self, math.pi * 0.5, 1.3) end
        if side then
            mpos = mpos - right * side + vang:Up() * dip   -- (its right is the mirror's left)
            vang = Angle(vang.p + dp, vang.y - dy, vang.r - dr)
        end
        mv:SetPos(mpos)
        mv:SetAngles(vang)
        -- Left shots kick this hand; the right gun's kick isn't copied (by
        -- its activity, or by time since its shot); draw/reload are.
        local seq = vm:GetSequence()
        local rightKick = vm:GetSequenceActivity(seq) == ACT_VM_PRIMARYATTACK
            or (self.rhylibMainShot and RealTime() - self.rhylibMainShot < 0.4)
        if rightKick then
            animate(mv, self.rhylibMirrorShot)
        else
            animate(mv, self.rhylibMirrorShot, seq, vm:GetCycle())
        end
        local b = proxyBones(mv, self.CarrierBone, self.CarrierBoneMove)
        render.CullMode(MATERIAL_CULLMODE_CW)
        mv:DrawModel()
        drawProxyHands(self, "rhylibMirrorHands", mv, true)
        render.CullMode(MATERIAL_CULLMODE_CCW)
        -- The left pistol on the mirrored hand's own gun bone: its pose is
        -- worked out unmirrored, then reflected like the model is drawn.
        local m = b and mv:GetBoneMatrix(b)
        if not m then return end
        local scale = self:CarrierPose("PropBoneScale")
        local ent = self:GetPropEntity("propVML", scale)
        if not ent then return end
        -- (RenderMultiply may already be baked into the bone matrices: a
        -- left-handed matrix is unmirrored first, so it's reflected once)
        mpos = mv:GetPos()
        local bp, ba = m:GetTranslation(), m:GetAngles()
        -- (columns read directly, so the sign of the determinant tells)
        local function col(c) return Vector(m:GetField(1, c), m:GetField(2, c), m:GetField(3, c)) end
        local bf, bl, bu = col(1), col(2), col(3)
        if bf:Cross(bl):Dot(bu) < 0 then
            bp = bp - right * (2 * (bp - mpos):Dot(right))
            bf:Normalize()
            bu:Normalize()
            ba = mirrorVec(bf, right):AngleEx(mirrorVec(bu, right))
        end
        local pos, ang = offsetTransform(bp, ba, self:CarrierPose("PropBonePos"), self:CarrierPose("PropBoneAng") or angle_zero)
        local lp = pos - right * (2 * (pos - mpos):Dot(right))
        local la = mirrorVec(ang:Forward(), right):AngleEx(mirrorVec(ang:Up(), right))
        if self.DualMirrorPos or self.DualMirrorAng then
            lp, la = offsetTransform(lp, la, self.DualMirrorPos or vector_origin, self.DualMirrorAng or angle_zero)
        end
        ent:SetPos(lp)
        ent:SetAngles(la)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle * (scale or self.PropScale) / self.PropScale)
    end

    -- A fire mode's proxy viewmodel (ModeProxies): its hands, its fire and
    -- reload animations, the gun on its gun bone.
    local function drawProxy(self, vm, px)
        local ent = proxyModel(self, "rhylibProxyVM", px.model, false)
        if not ent then return end
        local ang = vm:GetAngles()
        local pos = vm:GetPos()
        local o = px.VMOffset
        if o then pos = pos + ang:Right() * o.x + ang:Forward() * o.y + ang:Up() * o.z end
        ent:SetPos(pos)
        ent:SetAngles(ang)
        -- Reload: its reload animation stretched over the gun's reload time.
        if self:IsReloading() then
            -- (stretched over the real reload, skills included: ReloadEnd)
            local left = math.max(self:GetReloadEnd() - CurTime(), 0)
            self.rhylibProxyReload = self.rhylibProxyReload or math.max(left, 0.1)
            local rs = ent:SelectWeightedSequence(ACT_VM_RELOAD)
            if rs and rs >= 0 then
                playSeq(ent, rs, 1 - left / self.rhylibProxyReload)
            else
                animate(ent, nil)
            end
        else
            self.rhylibProxyReload = nil
            animate(ent, self.rhylibProxyShot)
        end
        local b = proxyBones(ent, px.bone, px.boneMove)
        ent:DrawModel()
        drawProxyHands(self, "rhylibProxyHands", ent, false)
        local m = b and ent:GetBoneMatrix(b)
        if not m then return end
        local ppos, pang = offsetTransform(m:GetTranslation(), m:GetAngles(), px.PropBonePos or vector_origin, px.PropBoneAng or angle_zero)
        drawProp(self, ppos, pang, px.PropBoneScale or self.PropScale)
    end

    -- The real hands stay hidden while a proxy stands in for them.
    Rhylib.Hook.Add("PreDrawPlayerHands", "weapons.proxyhands", function(hands, vm, ply, wep)
        if IsValid(wep) and wep.ActiveProxy and wep:ActiveProxy() then return true end
    end)

    -- "dual" mode: the second gun, floating at the left of the view.
    local function drawDualVM(self, vm)
        if self.DualMirror and self:UsesCarrier() then return end   -- (mirrored instead, below)
        if not self.DualPropVMPos or self:GetFireModeName() ~= "dual" then return end
        local ent = self:GetPropEntity("propVML", self.PropBoneScale or self.PropScale)
        if not ent then return end
        local pos, ang = offsetTransform(vm:GetPos(), vm:GetAngles(), self.DualPropVMPos, self.DualPropVMAng)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle)
    end

    -- First person. Carrier: it draws (gun bone shrunk) and the prop goes
    -- on that bone in PostDrawViewModel. Otherwise the placeholder isn't
    -- drawn and the prop floats in its place. Both inside the viewmodel
    -- pass (viewmodel FOV, bob, sway, aim offset).
    -- Two-gun viewmodel: hidden whole (render blend), and a prop is drawn
    -- on its left and right gun bone. (Shrinking its gun bones also shrank
    -- the left hand, which hangs off them.)
    local function dualBones(vm, wep)
        local key = vm:GetModel()
        if vm.rhylibDualKey == key then return vm.rhylibDualBones end
        local info = {}
        for i = 0, (vm:GetBoneCount() or 0) - 1 do
            local n = string.lower(vm:GetBoneName(i) or "")
            local gunPart = string.find(n, "elite", 1, true) or string.find(n, "weapon", 1, true) and not string.find(n, "hand", 1, true)
                and not string.find(n, "arm", 1, true) and not string.find(n, "finger", 1, true) and not string.find(n, "wrist", 1, true)
                and not string.find(n, "bip", 1, true)
            if gunPart then
                -- The gun itself: the shortest name with left / right in it.
                if string.find(n, "left", 1, true) and (not info.left or #n < info.leftLen) then info.left, info.leftLen = i, #n end
                if string.find(n, "right", 1, true) and (not info.right or #n < info.rightLen) then info.right, info.rightLen = i, #n end
            end
        end
        -- Named in the weapon (SWEP.DualBoneL / DualBoneR) wins over the guess.
        if wep and wep.DualBoneL then info.left = vm:LookupBone(wep.DualBoneL) or info.left end
        if wep and wep.DualBoneR then info.right = vm:LookupBone(wep.DualBoneR) or info.right end
        vm.rhylibDualKey, vm.rhylibDualBones = key, info
        return info
    end

    -- Bone list of the current viewmodel (for tuning the dual carrier).
    concommand.Add("rhylib_vm_bones", function()
        local vm = LocalPlayer():GetViewModel()
        if not IsValid(vm) then return end
        print("Bones of " .. tostring(vm:GetModel()))
        for i = 0, (vm:GetBoneCount() or 0) - 1 do print(i, vm:GetBoneName(i)) end
    end)

    function SWEP:PreDrawViewModel(vm)
        if self.ModeCarriers then self:ApplyModeCarrier() end
        if self:Scoped() then return true end   -- looking through the scope: no gun, no hands
        if self:ActiveProxy() then
            -- (another viewmodel stands in, PostDrawViewModel: this one hidden)
            if vm.rhylibShrunk then unshrink(vm) end
            blendOff(vm)
            return
        end
        if not self.PropModel or self.PropFirstPerson == false then return end
        if self:DualViewModelOn() then
            -- The two-gun model is only guns (the hands are their own
            -- entity), so all of it is hidden and props go on its gun bones.
            if vm.rhylibShrunk then unshrink(vm) end
            blendOff(vm)
            return
        end
        if self:UsesCarrier() then
            shrink(self, vm)
            if self.CarrierHideBones then extraShrink(self, vm, true) end
            if self.CarrierInvisible then blendOff(vm) end
            if self.CarrierBoneMods then boneMods(self, vm, true) end
            self:HoldReloadFrame(vm)
            return
        end
        drawProp(self, offsetTransform(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng))
        return true
    end

    function SWEP:PostDrawViewModel(vm)
        local px = self.PropModel and not self:Scoped() and self:ActiveProxy()
        if px then drawProxy(self, vm, px) return end
        if self.PropModel and not self:Scoped() and self:DualViewModelOn() then
            local info = dualBones(vm, self)
            for side, b in pairs({ right = info.right, left = info.left }) do
                local m = b and vm:GetBoneMatrix(b)
                if m then
                    local ent = self:GetPropEntity(side == "left" and "propVML" or "propVM", self.PropBoneScale or self.PropScale)
                    if ent then
                        local pos, ang = offsetTransform(m:GetTranslation(), m:GetAngles(), self.DualBonePos, self.DualBoneAng)
                        ent:SetPos(pos)
                        ent:SetAngles(ang)
                        ent:SetupBones()
                        ent:DrawModel()
                        if side == "right" then self.propMuzzleVM = ent:LocalToWorld(self.PropMuzzle)
                        else self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle) end
                    end
                end
            end
            return
        end
        if self.PropModel and not self:Scoped() then drawDualVM(self, vm) end
        if not self.PropModel or not self:UsesCarrier() then return end
        for _, e in ipairs(self.ExtraProps or {}) do
            local b = e.vmBone and vm:LookupBone(e.vmBone)
            local m = b and vm:GetBoneMatrix(b)
            local ent = m and self:GetExtraEntity(e, "vm")
            if ent then drawExtra(self, ent, m, e.vmPos, e.vmAng, e.vmScale) end
        end
        local b = carrierBone(self, vm)
        local m = b and vm:GetBoneMatrix(b)
        local pos, ang
        if m and (not self.PropBoneAng or self.rhylibRealign) then self:AlignPropAngle(vm, m:GetAngles()) end
        if m and self.PropBoneAng then
            pos, ang = offsetTransform(m:GetTranslation(), m:GetAngles(), self:CarrierPose("PropBonePos"), self:CarrierPose("PropBoneAng"))
        else
            pos, ang = offsetTransform(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng)
        end
        drawProp(self, pos, ang, self:CarrierPose("PropBoneScale"))
        if self.DualMirror and self:GetFireModeName() == "dual" then drawMirror(self, vm) end
        if m and (self.VMOffset == nil or self.rhylibRematch) then self:MatchFloatOffset(vm, pos) end
    end

    -- PropBoneAng that points the held prop like the floating prop
    -- (PropVMAng from the view), measured on an idle frame.
    local function idleFrame(self, vm)
        if self:IsReloading() or (self.aimFrac or 0) > 0 or (self.safeFrac or 0) > 0 then return false end
        return vm:GetSequenceActivity(vm:GetSequence()) == ACT_VM_IDLE
    end

    function SWEP:AlignPropAngle(vm, boneAng)
        if not idleFrame(self, vm) then return end
        local _, want = offsetTransform(vector_origin, vm:GetAngles(), vector_origin, self.PropVMAng)
        local _, l = WorldToLocal(vector_origin, want, vector_origin, boneAng)
        -- offsetTransform's rotation order may differ from WorldToLocal's
        -- in sign: keep the candidate that lands closest.
        local best, bestErr
        for _, c in ipairs({ l, Angle(-l.p, l.y, l.r), Angle(l.p, l.y, -l.r), Angle(-l.p, l.y, -l.r), Angle(l.p, -l.y, l.r), Angle(-l.p, -l.y, -l.r) }) do
            local _, a = offsetTransform(vector_origin, boneAng, vector_origin, c)
            local err = (1 - a:Forward():Dot(want:Forward())) + (1 - a:Up():Dot(want:Up()))
            if not bestErr or err < bestErr then best, bestErr = c, err end
        end
        best = Angle(math.Round(best.p, 2), math.Round(best.y, 2), math.Round(best.r, 2))
        self.PropBoneAng = best
        self.rhylibRealign = nil
        local st = not self.rhylibModeCarrier and weapons.GetStored(self:GetClass())   -- (not a fire mode's own values)
        if st then st.PropBoneAng = Angle(best) end
        print(string.format("[Rhylib] %s: SWEP.PropBoneAng = Angle(%g, %g, %g)", self:GetClass(), best.p, best.y, best.r))
    end

    -- VMOffset that puts the held prop where the floating prop was
    -- (PropVMPos from the view), measured on an idle frame. Stored on the
    -- weapon class for the rest of the session.
    function SWEP:MatchFloatOffset(vm, propPos)
        if not idleFrame(self, vm) then return end
        local o, a = vm:GetPos(), vm:GetAngles()
        local d = propPos - o
        local want = self.PropVMPos
        local v = Vector(want.y - d:Dot(a:Right()), want.x - d:Dot(a:Forward()), want.z - d:Dot(a:Up()))
        v = Vector(math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2))
        self.VMOffset = v
        self.rhylibRematch = nil
        local st = not self.rhylibModeCarrier and weapons.GetStored(self:GetClass())   -- (not a fire mode's own values)
        if st then st.VMOffset = Vector(v) end
        print(string.format("[Rhylib] %s: SWEP.VMOffset = Vector(%g, %g, %g)", self:GetClass(), v.x, v.y, v.z))
    end

    -- A reload longer than its animation holds the last frame instead of
    -- replaying it; FinishReload sends the idle animation.
    local HOLD = 0.96
    function SWEP:HoldReloadFrame(vm)
        local act = self.ReloadAct or ACT_VM_RELOAD
        if self:IsReloading() and vm:GetSequenceActivity(vm:GetSequence()) == act then
            if self.rhylibHold or vm:GetCycle() >= HOLD then
                self.rhylibHold = true
                vm:SetCycle(HOLD)
                vm:SetPlaybackRate(0)
            end
        elseif self.rhylibHold then
            self.rhylibHold = nil
            vm:SetPlaybackRate(1)
        end
    end

    -- The carrier's own muzzle flashes, shells and sounds stay off.
    function SWEP:FireAnimationEvent()
        if self:UsesCarrier() then return true end
    end

    -- Console helpers ----------------------------------------------------

    local function held()
        local w = LocalPlayer():GetActiveWeapon()
        if not IsValid(w) or not w.IsRhylib or not w.PropModel then print("Hold a Rhylib prop weapon first") return nil end
        return w, LocalPlayer():GetViewModel()
    end

    concommand.Add("rhylib_vm_info", function()
        local w, vm = held()
        if not w or not IsValid(vm) then return end
        print("Viewmodel: " .. tostring(vm:GetModel()) .. (w:UsesCarrier() and "  (carrier)" or ""))
        local cb = w:UsesCarrier() and carrierBone(w, vm)
        print("Bones (index: name):")
        for i = 0, (vm:GetBoneCount() or 0) - 1 do
            print(string.format("  %d: %s%s", i, vm:GetBoneName(i) or "?", cb == i and "   [gun bone: hidden, prop on it]" or ""))
        end
    end)

    -- rhylib_vm_aim right forward up: the aim-down-sights offset (SWEP.AimPos)
    concommand.Add("rhylib_vm_aim", function(_, _, args)
        local w = LocalPlayer():GetActiveWeapon()
        if not IsValid(w) or not w.AimPos then print("Hold a Rhylib weapon first") return end
        local x, y, z = tonumber(args[1]) or 0, tonumber(args[2]) or 0, tonumber(args[3]) or 0
        w.AimPos = Vector(x, y, z)
        print(string.format("SWEP.AimPos = Vector(%g, %g, %g)", x, y, z))
    end)

    -- rhylib_vm_fov n: the viewmodel FOV (SWEP.ViewModelFOV)
    concommand.Add("rhylib_vm_fov", function(_, _, args)
        local w = LocalPlayer():GetActiveWeapon()
        if not IsValid(w) then return end
        w.ViewModelFOV = tonumber(args[1]) or w.ViewModelFOV
        print("SWEP.ViewModelFOV = " .. tostring(w.ViewModelFOV))
    end)

    -- Live tuning of the floating gun: rhylib_vm_tune x y z pitch yaw roll
    -- (forward, right, up from the view; prints the lines for the weapon file).
    concommand.Add("rhylib_vm_tune", function(_, _, args)
        local w = held()
        if not w then return end
        local n = {}
        for i = 1, 6 do n[i] = tonumber(args[i]) or 0 end
        w.PropVMPos, w.PropVMAng = Vector(n[1], n[2], n[3]), Angle(n[4], n[5], n[6])
        print(string.format("SWEP.PropVMPos = Vector(%g, %g, %g)\nSWEP.PropVMAng = Angle(%g, %g, %g)", n[1], n[2], n[3], n[4], n[5], n[6]))
    end)

    -- rhylib_vm_editor: sliders for the held gun (prop in hand or floating,
    -- aim offset, viewmodel FOV). Changes last until the weapon is removed;
    -- Copy puts the lines for the weapon file on the clipboard.
    local editor

    local function editorLines(w, safe, px)
        local out = {}
        if px and not safe then
            local mode = w:GetFireModeName()
            out[1] = "-- in SWEP.ModeProxies (the " .. mode .. " block):"
            out[2] = string.format("        PropBonePos = Vector(%g, %g, %g),", px.PropBonePos:Unpack())
            out[3] = string.format("        PropBoneAng = Angle(%g, %g, %g),", px.PropBoneAng:Unpack())
            out[4] = string.format("        PropBoneScale = %g,", px.PropBoneScale or w.PropScale)
            out[5] = string.format("        VMOffset = Vector(%g, %g, %g),", (px.VMOffset or Vector()):Unpack())
            out[6] = string.format("-- and for the gun: SWEP.AimPos = Vector(%g, %g, %g)", w.AimPos.x, w.AimPos.y, w.AimPos.z)
            return table.concat(out, "\n")
        end
        if safe then
            out[1] = "SWEP.SafePose = {"
            out[2] = string.format("    PropBonePos = Vector(%g, %g, %g),", safe.PropBonePos:Unpack())
            out[3] = string.format("    PropBoneAng = Angle(%g, %g, %g),", safe.PropBoneAng:Unpack())
            out[4] = string.format("    PropBoneScale = %g,", safe.PropBoneScale)
            out[5] = string.format("    VMOffset = Vector(%g, %g, %g),", safe.VMOffset:Unpack())
            out[6] = string.format("    CarrierFOV = %g,", safe.CarrierFOV)
            out[7] = "}"
            return table.concat(out, "\n")
        end
        if w.rhylibModeCarrier then
            out[#out + 1] = "-- (fire mode \"" .. w.rhylibModeCarrier .. "\": these go in SWEP.ModeCarriers." .. w.rhylibModeCarrier .. ")"
        end
        local function v(name, x) out[#out + 1] = string.format("SWEP.%s = Vector(%g, %g, %g)", name, x.x, x.y, x.z) end
        local function a(name, x) out[#out + 1] = string.format("SWEP.%s = Angle(%g, %g, %g)", name, x.p, x.y, x.r) end
        if w:UsesCarrier() then
            v("PropBonePos", w.PropBonePos)
            a("PropBoneAng", w.PropBoneAng)
            out[#out + 1] = string.format("SWEP.PropBoneScale = %g", w.PropBoneScale or w.PropScale)
            v("VMOffset", w.VMOffset)
        else
            v("PropVMPos", w.PropVMPos)
            a("PropVMAng", w.PropVMAng)
        end
        v("AimPos", w.AimPos)
        if w.DualMirror and w.DualMirrorPos then
            out[#out + 1] = string.format("SWEP.DualSpread = %g", w.DualSpread or 0)
            v("DualMirrorPos", w.DualMirrorPos)
            a("DualMirrorAng", w.DualMirrorAng or Angle())
        end
        out[#out + 1] = w:UsesCarrier() and ("SWEP.CarrierFOV = " .. tostring(w.CarrierFOV)) or ("SWEP.ViewModelFOV = " .. tostring(w.ViewModelFOV))
        return table.concat(out, "\n")
    end

    -- Editor window: typed values with - / + buttons (Enter or leaving the
    -- box applies). Returns frame (with .list), label(text), field(...), rows.
    local function editorFrame(title, tall, w)
        local f = vgui.Create("DFrame")
        f:SetTitle(title)
        f:SetSize(340, tall)
        f:SetPos(20, ScrH() * 0.5 - tall * 0.5)
        f:MakePopup()   -- (keyboard goes to the window, so number keys don't switch weapons)

        local list = vgui.Create("DScrollPanel", f)
        list:Dock(FILL)
        f.list = list
        local rows = {}

        local function label(text)
            local l = list:Add("DLabel")
            l:SetText(text)
            l:Dock(TOP)
            l:DockMargin(4, 10, 4, 2)
        end

        local function field(text, step, lo, hi, get, set)
            local row = list:Add("DPanel")
            row:SetTall(24)
            row:Dock(TOP)
            row:DockMargin(4, 1, 4, 1)
            row:SetPaintBackground(false)
            local l = vgui.Create("DLabel", row)
            l:SetText(text)
            l:SetWide(90)
            l:Dock(LEFT)
            local plus = vgui.Create("DButton", row)
            plus:SetText("+")
            plus:SetWide(26)
            plus:Dock(RIGHT)
            local minus = vgui.Create("DButton", row)
            minus:SetText("-")
            minus:SetWide(26)
            minus:Dock(RIGHT)
            local e = vgui.Create("DTextEntry", row)
            e:Dock(FILL)
            e:DockMargin(0, 0, 4, 0)
            e:SetNumeric(true)
            local function show() e:SetText(tostring(math.Round(get(), 3))) end
            local function apply(v)
                if not IsValid(w) or not v then return end
                set(math.Clamp(v, lo, hi))
                show()
            end
            e.OnEnter = function() apply(tonumber(e:GetValue())) end
            local base = baseclass.Get("DTextEntry")
            e.OnLoseFocus = function(self)
                apply(tonumber(self:GetValue()))
                if base and base.OnLoseFocus then base.OnLoseFocus(self) end
            end
            minus.DoClick = function() apply(get() - step) end
            plus.DoClick = function() apply(get() + step) end
            show()
            rows[#rows + 1] = show
        end

        local function copyButton(getText)
            local copy = list:Add("DButton")
            copy:SetText("Copy lines for the weapon file")
            copy:SetTall(28)
            copy:Dock(TOP)
            copy:DockMargin(4, 10, 4, 4)
            copy.DoClick = function()
                if not IsValid(w) then return end
                local text = getText()
                SetClipboardText(text)
                print(text)
                chat.AddText(Color(120, 200, 255), "Copied (also printed in the console).")
            end
        end
        f.copyButton = copyButton

        return f, label, field, rows
    end

    -- Grenades (rhylib_grenade_base, not Rhylib guns): their first-person
    -- prop sits on the viewmodel's grenade bone (PropVMPos / PropVMAng /
    -- PropVMScale).
    local function grenadeEditor(w)
        w.PropVMPos = Vector(w.PropVMPos:Unpack())
        w.PropVMAng = Angle(w.PropVMAng:Unpack())
        w.PropVMScale = w.PropVMScale or 1
        local f, label, field = editorFrame("First person: " .. w:GetClass(), 360, w)
        editor = f
        local R = 30
        label("Grenade from the viewmodel's grenade bone")
        field("Forward", 0.1, -R, R, function() return w.PropVMPos.x end, function(v) w.PropVMPos.x = v end)
        field("Right", 0.1, -R, R, function() return w.PropVMPos.y end, function(v) w.PropVMPos.y = v end)
        field("Up", 0.1, -R, R, function() return w.PropVMPos.z end, function(v) w.PropVMPos.z = v end)
        field("Pitch", 1, -180, 180, function() return w.PropVMAng.p end, function(v) w.PropVMAng.p = v end)
        field("Yaw", 1, -180, 180, function() return w.PropVMAng.y end, function(v) w.PropVMAng.y = v end)
        field("Roll", 1, -180, 180, function() return w.PropVMAng.r end, function(v) w.PropVMAng.r = v end)
        field("Size", 0.05, 0.1, 3, function() return w.PropVMScale end, function(v) w.PropVMScale = v end)
        f.copyButton(function()
            return string.format("SWEP.PropVMScale = %g\nSWEP.PropVMPos = Vector(%g, %g, %g)\nSWEP.PropVMAng = Angle(%g, %g, %g)",
                w.PropVMScale, w.PropVMPos.x, w.PropVMPos.y, w.PropVMPos.z, w.PropVMAng.p, w.PropVMAng.y, w.PropVMAng.r)
        end)
    end

    concommand.Add("rhylib_vm_editor", function()
        if IsValid(editor) then editor:Remove() return end
        local g = LocalPlayer():GetActiveWeapon()
        if IsValid(g) and not g.IsRhylib and g.PropModel and g.PropVMPos and g.PropVMAng then
            grenadeEditor(g)
            return
        end
        local w = held()
        if not w then return end
        local carrier = w:UsesCarrier()
        local posKey, angKey = carrier and "PropBonePos" or "PropVMPos", carrier and "PropBoneAng" or "PropVMAng"
        -- Own copies, so the edits don't change the shared weapon table.
        w[posKey] = Vector(w[posKey]:Unpack())
        local hadAng = w.PropBoneAng ~= nil and w.PropBoneAng ~= false
        if carrier and not hadAng then w.rhylibRealign = true end
        w[angKey] = Angle((w[angKey] or Angle(0, 0, 0)):Unpack())
        w.AimPos = Vector(w.AimPos:Unpack())
        if carrier and w.VMOffset == nil then w.rhylibRematch = true end
        w.VMOffset = Vector((w.VMOffset or Vector(0, 0, 0)):Unpack())
        -- Opened while lowered (safety or sprint): edit the safety pose.
        local safe
        if carrier and hadAng and w:IsLowered() then
            local sp = w.SafePose or {}
            safe = {
                PropBonePos = Vector((sp.PropBonePos or w.PropBonePos):Unpack()),
                PropBoneAng = Angle((sp.PropBoneAng or w.PropBoneAng):Unpack()),
                PropBoneScale = sp.PropBoneScale or w.PropBoneScale or w.PropScale,
                VMOffset = Vector((sp.VMOffset or w.VMOffset):Unpack()),
                CarrierFOV = sp.CarrierFOV or w.CarrierFOV,
            }
            w.SafePose = safe
        end
        local t = safe or w
        -- A fire mode drawn on another viewmodel (ModeProxies): edit that one.
        local px
        if carrier and not safe and w.ActiveProxy and w:ActiveProxy() then
            w.ModeProxies = table.Copy(w.ModeProxies)
            px = w:ActiveProxy()
            px.PropBonePos = Vector((px.PropBonePos or Vector()):Unpack())
            px.PropBoneAng = Angle((px.PropBoneAng or Angle()):Unpack())
            px.PropBoneScale = px.PropBoneScale or w.PropScale
            px.VMOffset = Vector((px.VMOffset or Vector()):Unpack())
            t = px
        end

        local f, label, field, rows = editorFrame("Viewmodel: " .. w:GetClass() .. (px and (" (" .. w:GetFireModeName() .. " hands)") or safe and " (safety pose)" or carrier and " (in hands)" or " (floating)"), 640, w)
        editor = f
        local list = f.list
        f.OnRemove = function() if IsValid(w) then w.rhylibAimPreview = nil end end

        local R = 30
        label(carrier and "Gun on the hands' gun bone" or "Floating gun from the view")
        field("Forward", 0.1, -R, R, function() return t[posKey].x end, function(v) t[posKey].x = v end)
        field("Right", 0.1, -R, R, function() return t[posKey].y end, function(v) t[posKey].y = v end)
        field("Up", 0.1, -R, R, function() return t[posKey].z end, function(v) t[posKey].z = v end)
        field("Pitch", 1, -180, 180, function() return t[angKey].p end, function(v) t[angKey].p = v end)
        field("Yaw", 1, -180, 180, function() return t[angKey].y end, function(v) t[angKey].y = v end)
        field("Roll", 1, -180, 180, function() return t[angKey].r end, function(v) t[angKey].r = v end)
        if carrier then
            field("Size", 0.05, 0.1, 3, function() return t.PropBoneScale or w.PropScale end, function(v) t.PropBoneScale = v end)
            label("Hands and gun on screen")
            field("Right", 0.1, -R, R, function() return t.VMOffset.x end, function(v) t.VMOffset.x = v end)
            field("Forward", 0.1, -R, R, function() return t.VMOffset.y end, function(v) t.VMOffset.y = v end)
            field("Up", 0.1, -R, R, function() return t.VMOffset.z end, function(v) t.VMOffset.z = v end)
            if not safe and not px then
            local align = list:Add("DButton")
            align:SetText("Point the gun straight ahead")
            align:SetTall(24)
            align:Dock(TOP)
            align:DockMargin(4, 4, 4, 0)
            align.DoClick = function()
                if not IsValid(w) then return end
                w.rhylibRealign = true
                timer.Simple(0.3, function()
                    if not IsValid(w) or not IsValid(f) then return end
                    for _, show in ipairs(rows) do show() end
                end)
            end
            local match = list:Add("DButton")
            match:SetText("Move to the old floating gun position")
            match:SetTall(24)
            match:Dock(TOP)
            match:DockMargin(4, 4, 4, 0)
            match.DoClick = function()
                if not IsValid(w) then return end
                w.rhylibRematch = true   -- worked out again on the next idle frame
                timer.Simple(0.3, function()
                    if not IsValid(w) or not IsValid(f) then return end
                    for _, show in ipairs(rows) do show() end
                end)
            end
            end
        end
        if w.DualMirror and carrier and not safe then
            w.DualMirrorPos = Vector((w.DualMirrorPos or Vector()):Unpack())
            w.DualMirrorAng = Angle((w.DualMirrorAng or Angle()):Unpack())
            label("Dual pistols (switch to dual to see them)")
            field("Spread", 0.1, -R, R, function() return w.DualSpread or 0 end, function(v) w.DualSpread = v end)
            field("L forward", 0.1, -R, R, function() return w.DualMirrorPos.x end, function(v) w.DualMirrorPos.x = v end)
            field("L right", 0.1, -R, R, function() return w.DualMirrorPos.y end, function(v) w.DualMirrorPos.y = v end)
            field("L up", 0.1, -R, R, function() return w.DualMirrorPos.z end, function(v) w.DualMirrorPos.z = v end)
            field("L pitch", 1, -180, 180, function() return w.DualMirrorAng.p end, function(v) w.DualMirrorAng.p = v end)
            field("L yaw", 1, -180, 180, function() return w.DualMirrorAng.y end, function(v) w.DualMirrorAng.y = v end)
            field("L roll", 1, -180, 180, function() return w.DualMirrorAng.r end, function(v) w.DualMirrorAng.r = v end)
        end
        label("Aiming (tick Preview aim to see it)")
        field("Right", 0.1, -R, R, function() return w.AimPos.x end, function(v) w.AimPos.x = v end)
        field("Forward", 0.1, -R, R, function() return w.AimPos.y end, function(v) w.AimPos.y = v end)
        field("Up", 0.1, -R, R, function() return w.AimPos.z end, function(v) w.AimPos.z = v end)
        label("Viewmodel")
        field("FOV", 1, 30, 110, function() return safe and safe.CarrierFOV or w.ViewModelFOV end, function(v)
            if safe then safe.CarrierFOV = v return end
            w.ViewModelFOV = v
            if carrier then w.CarrierFOV = v end
        end)

        local aim = list:Add("DCheckBoxLabel")
        aim:SetText("Preview aim")
        aim:Dock(TOP)
        aim:DockMargin(4, 10, 4, 0)
        aim.OnChange = function(_, on) if IsValid(w) then w.rhylibAimPreview = on or nil end end

        local copy = list:Add("DButton")
        copy:SetText("Copy lines for the weapon file")
        copy:SetTall(28)
        copy:Dock(TOP)
        copy:DockMargin(4, 10, 4, 4)
        copy.DoClick = function()
            if not IsValid(w) then return end
            local text = editorLines(w, safe, px)
            SetClipboardText(text)
            print(text)
            chat.AddText(Color(120, 200, 255), "Copied (also printed in the console).")
        end
    end)

    -- Orbit camera for the third-person editors: the view circles your right
    -- hand while the editor is open (preset buttons, drag to turn, wheel to
    -- zoom). Yaw is from your body's facing: 0 = in front of you.
    local orbit = { on = false, yaw = 30, pitch = 10, dist = 45 }

    local function orbitCentre(ply)
        ply:SetupBones()
        local b = ply:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = b and ply:GetBoneMatrix(b)
        return m and m:GetTranslation() or (ply:GetPos() + Vector(0, 0, 45))
    end

    Rhylib.Hook.Add("CalcView", "weapons.editorcam", function(ply, pos, angles, fov)
        if not orbit.on then return end
        if not IsValid(orbit.frame) or ply ~= LocalPlayer() or not ply:Alive() then
            orbit.on = false
            return
        end
        local centre = orbitCentre(ply)
        local dir = Angle(orbit.pitch, ply:GetRenderAngles().y + orbit.yaw, 0):Forward()
        local origin = centre + dir * orbit.dist
        return { origin = origin, angles = (centre - origin):Angle(), fov = 60, znear = 1, drawviewer = true }
    end, -60)   -- (before the body camera and third person)

    -- (no gun sway or first-person bits while orbiting)
    Rhylib.Hook.Add("ShouldDrawLocalPlayer", "weapons.editorcam", function()
        if orbit.on and IsValid(orbit.frame) then return true end
    end, -60)

    local function addOrbit(f, label, startOff)
        orbit.frame = f
        orbit.on = not startOff
        label("Camera (circles your right hand)")
        local list = f.list
        local row = list:Add("DPanel")
        row:SetTall(24)
        row:Dock(TOP)
        row:DockMargin(4, 1, 4, 1)
        row:SetPaintBackground(false)
        local presets = { { "Front", 0, 5 }, { "Back", 180, 5 }, { "Left", 90, 5 }, { "Right", -90, 5 }, { "Top", 0, -85 }, { "Below", 0, 60 } }
        for _, p in ipairs(presets) do
            local b = vgui.Create("DButton", row)
            b:SetText(p[1])
            b:SetWide(50)
            b:Dock(LEFT)
            b:DockMargin(0, 0, 2, 0)
            b.DoClick = function()
                orbit.on = true
                orbit.yaw, orbit.pitch = p[2], p[3]
            end
        end
        local pad = list:Add("DPanel")
        pad:SetTall(90)
        pad:Dock(TOP)
        pad:DockMargin(4, 4, 4, 1)
        pad:SetCursor("sizeall")
        function pad:Paint(w, h)
            surface.SetDrawColor(20, 24, 30, 220)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(80, 100, 130, 255)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText("Drag here to turn · wheel to zoom", "DermaDefault", w * 0.5, h * 0.42, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("yaw %d · pitch %d · %d units", orbit.yaw, orbit.pitch, orbit.dist), "DermaDefault", w * 0.5, h * 0.66,
                Color(170, 180, 190), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        function pad:OnMousePressed(code)
            if code ~= MOUSE_LEFT then return end
            self.drag = { gui.MouseX(), gui.MouseY() }
            self:MouseCapture(true)
        end
        function pad:OnMouseReleased()
            self.drag = nil
            self:MouseCapture(false)
        end
        function pad:Think()
            if not self.drag then return end
            local x, y = gui.MouseX(), gui.MouseY()
            orbit.yaw = math.NormalizeAngle(orbit.yaw - (x - self.drag[1]) * 0.5)
            orbit.pitch = math.Clamp(orbit.pitch + (y - self.drag[2]) * 0.4, -89, 89)
            self.drag = { x, y }
            orbit.on = true
        end
        function pad:OnMouseWheeled(d)
            orbit.dist = math.Clamp(orbit.dist - d * 5, 15, 200)
            orbit.on = true
            return true
        end
        -- Zoom: distance from the hand (the wheel on the pad moves it too).
        local zoom = list:Add("DNumSlider")
        zoom:Dock(TOP)
        zoom:DockMargin(4, 4, 4, 1)
        zoom:SetText("Zoom (distance)")
        zoom:SetMinMax(15, 200)
        zoom:SetDecimals(0)
        zoom:SetValue(orbit.dist)
        function zoom:OnValueChanged(v)
            orbit.dist = math.Clamp(v, 15, 200)
            orbit.on = true
        end
        function zoom:Think()
            if not self:IsEditing() and math.abs(self:GetValue() - orbit.dist) > 0.5 then self:SetValue(orbit.dist) end
        end
        local off = list:Add("DCheckBoxLabel")
        off:SetText("Orbit camera on")
        off:Dock(TOP)
        off:DockMargin(4, 4, 4, 2)
        off:SetValue(orbit.on)
        function off:OnChange(v) orbit.on = v end
        function off:Think()
            if self:GetChecked() ~= orbit.on then self:SetChecked(orbit.on) end
        end
    end

    -- rhylib_wm_editor: the third-person gun (PropWMPos / PropWMAng /
    -- PropScale, from the right hand). Only your own view changes; the
    -- orbit camera shows it from any side.
    local wmEditor
    concommand.Add("rhylib_wm_editor", function()
        if IsValid(wmEditor) then wmEditor:Remove() return end
        -- Any weapon with a third-person prop (guns, grenades).
        local w = LocalPlayer():GetActiveWeapon()
        if not IsValid(w) or not w.PropModel or not w.PropWMPos then print("Hold a Rhylib weapon or grenade first") return end
        w.PropScale = w.PropScale or 1
        w.PropWMPos = Vector(w.PropWMPos:Unpack())
        w.PropWMAng = Angle(w.PropWMAng:Unpack())
        local f, label, field = editorFrame("Third person: " .. w:GetClass(), w.DualPropWMPos and 760 or 560, w)
        wmEditor = f
        local R = 30
        label("Gun from the right hand")
        field("Forward", 0.1, -R, R, function() return w.PropWMPos.x end, function(v) w.PropWMPos.x = v end)
        field("Right", 0.1, -R, R, function() return w.PropWMPos.y end, function(v) w.PropWMPos.y = v end)
        field("Up", 0.1, -R, R, function() return w.PropWMPos.z end, function(v) w.PropWMPos.z = v end)
        field("Pitch", 1, -180, 180, function() return w.PropWMAng.p end, function(v) w.PropWMAng.p = v end)
        field("Yaw", 1, -180, 180, function() return w.PropWMAng.y end, function(v) w.PropWMAng.y = v end)
        field("Roll", 1, -180, 180, function() return w.PropWMAng.r end, function(v) w.PropWMAng.r = v end)
        field("Size", 0.05, 0.1, 3, function() return w.PropScale end, function(v) w.PropScale = v end)
        -- Dual pistols: the second one, from the left hand (switch to dual first to see it).
        local dual = w.DualPropWMPos ~= nil
        if dual then
            w.DualPropWMPos = Vector(w.DualPropWMPos:Unpack())
            w.DualPropWMAng = Angle((w.DualPropWMAng or Angle()):Unpack())
            label("Left pistol from the left hand (dual mode)")
            field("L forward", 0.1, -R, R, function() return w.DualPropWMPos.x end, function(v) w.DualPropWMPos.x = v end)
            field("L right", 0.1, -R, R, function() return w.DualPropWMPos.y end, function(v) w.DualPropWMPos.y = v end)
            field("L up", 0.1, -R, R, function() return w.DualPropWMPos.z end, function(v) w.DualPropWMPos.z = v end)
            field("L pitch", 1, -180, 180, function() return w.DualPropWMAng.p end, function(v) w.DualPropWMAng.p = v end)
            field("L yaw", 1, -180, 180, function() return w.DualPropWMAng.y end, function(v) w.DualPropWMAng.y = v end)
            field("L roll", 1, -180, 180, function() return w.DualPropWMAng.r end, function(v) w.DualPropWMAng.r = v end)
        end
        f.copyButton(function()
            local t = string.format("SWEP.PropScale = %g\nSWEP.PropWMPos = Vector(%g, %g, %g)\nSWEP.PropWMAng = Angle(%g, %g, %g)",
                w.PropScale, w.PropWMPos.x, w.PropWMPos.y, w.PropWMPos.z, w.PropWMAng.p, w.PropWMAng.y, w.PropWMAng.r)
            if dual then
                t = t .. string.format("\nSWEP.DualPropWMPos = Vector(%g, %g, %g)\nSWEP.DualPropWMAng = Angle(%g, %g, %g)",
                    w.DualPropWMPos.x, w.DualPropWMPos.y, w.DualPropWMPos.z, w.DualPropWMAng.p, w.DualPropWMAng.y, w.DualPropWMAng.r)
            end
            return t
        end)
        addOrbit(f, label)
    end)

    -- rhylib_extra_editor: extra props (a riot shield) in first and third
    -- person, the carrier's arm moves and the holder's arm turns. Edits only
    -- your copy of the weapon; Copy gives the lines for the weapon file.
    local extraEditor
    local function fmtV(v) return string.format("Vector(%g, %g, %g)", v.x, v.y, v.z) end
    local function fmtA(a) return string.format("Angle(%g, %g, %g)", a.p, a.y, a.r) end
    concommand.Add("rhylib_extra_editor", function()
        if IsValid(extraEditor) then extraEditor:Remove() return end
        local w = LocalPlayer():GetActiveWeapon()
        if not IsValid(w) or not (w.ExtraProps or w.CarrierBoneMods or w.WorldBoneMods) then
            print("Hold a weapon with extra props (the riot shield) first")
            return
        end
        -- Own copies, so the edits don't change the shared weapon table.
        w.ExtraProps = table.Copy(w.ExtraProps or {})
        w.CarrierBoneMods = w.CarrierBoneMods and table.Copy(w.CarrierBoneMods) or nil
        w.WorldBoneMods = w.WorldBoneMods and table.Copy(w.WorldBoneMods) or nil
        local f, label, field = editorFrame("Extras: " .. w:GetClass(), 700, w)
        extraEditor = f
        addOrbit(f, label, true)   -- (off at first: this editor does first person too)
        local R, B = 60, 120
        local function posAng(t, posKey, angKey, what)
            t[posKey] = Vector((t[posKey] or Vector()):Unpack())
            t[angKey] = Angle((t[angKey] or Angle()):Unpack())
            field(what .. " fwd", 0.1, -B, B, function() return t[posKey].x end, function(v) t[posKey].x = v end)
            field(what .. " right", 0.1, -B, B, function() return t[posKey].y end, function(v) t[posKey].y = v end)
            field(what .. " up", 0.1, -B, B, function() return t[posKey].z end, function(v) t[posKey].z = v end)
            field(what .. " pitch", 1, -180, 180, function() return t[angKey].p end, function(v) t[angKey].p = v end)
            field(what .. " yaw", 1, -180, 180, function() return t[angKey].y end, function(v) t[angKey].y = v end)
            field(what .. " roll", 1, -180, 180, function() return t[angKey].r end, function(v) t[angKey].r = v end)
        end
        for _, e in ipairs(w.ExtraProps) do
            label(e.key .. ": first person (on " .. tostring(e.vmBone) .. ")")
            posAng(e, "vmPos", "vmAng", "")
            field(" size", 0.02, 0.05, 4, function() return e.vmScale or 1 end, function(v) e.vmScale = v end)
            label(e.key .. ": third person (on " .. tostring(e.wmBone) .. ")")
            posAng(e, "wmPos", "wmAng", "")
            field(" size", 0.02, 0.05, 4, function() return e.wmScale or 1 end, function(v) e.wmScale = v end)
        end
        for name, m in SortedPairs(w.CarrierBoneMods or {}) do
            label("First person arm: " .. name)
            m.pos = Vector((m.pos or Vector()):Unpack())
            m.ang = Angle((m.ang or Angle()):Unpack())
            field(" x", 0.1, -R, R, function() return m.pos.x end, function(v) m.pos.x = v end)
            field(" y", 0.1, -R, R, function() return m.pos.y end, function(v) m.pos.y = v end)
            field(" z", 0.1, -R, R, function() return m.pos.z end, function(v) m.pos.z = v end)
            field(" pitch", 1, -180, 180, function() return m.ang.p end, function(v) m.ang.p = v end)
            field(" yaw", 1, -180, 180, function() return m.ang.y end, function(v) m.ang.y = v end)
            field(" roll", 1, -180, 180, function() return m.ang.r end, function(v) m.ang.r = v end)
        end
        for name in SortedPairs(w.WorldBoneMods or {}) do
            local mods = w.WorldBoneMods
            label("Third person arm: " .. name)
            mods[name] = Angle(mods[name]:Unpack())
            field(" pitch", 1, -180, 180, function() return mods[name].p end, function(v) mods[name].p = v end)
            field(" yaw", 1, -180, 180, function() return mods[name].y end, function(v) mods[name].y = v end)
            field(" roll", 1, -180, 180, function() return mods[name].r end, function(v) mods[name].r = v end)
        end
        f.copyButton(function()
            local out = {}
            for _, e in ipairs(w.ExtraProps) do
                out[#out + 1] = string.format('%s = { vmPos = %s, vmAng = %s, vmScale = %g, wmPos = %s, wmAng = %s, wmScale = %g },',
                    e.key, fmtV(e.vmPos), fmtA(e.vmAng), e.vmScale or 1, fmtV(e.wmPos), fmtA(e.wmAng), e.wmScale or 1)
            end
            if w.CarrierBoneMods then
                out[#out + 1] = "SWEP.CarrierBoneMods = {"
                for name, m in SortedPairs(w.CarrierBoneMods) do
                    out[#out + 1] = string.format('    ["%s"] = { pos = %s, ang = %s },', name, fmtV(m.pos), fmtA(m.ang))
                end
                out[#out + 1] = "}"
            end
            if w.WorldBoneMods then
                out[#out + 1] = "SWEP.WorldBoneMods = {"
                for name, a in SortedPairs(w.WorldBoneMods) do
                    out[#out + 1] = string.format('    ["%s"] = %s,', name, fmtA(a))
                end
                out[#out + 1] = "}"
            end
            return table.concat(out, "\n")
        end)
    end)

    local handBone = {}

    function SWEP:DrawWorldModel(flags)
        local owner = self:GetOwner()
        if not self.PropModel or not IsValid(owner) then
            self:DrawModel(flags)
            return
        end

        -- Hand bone id per player model, so LookupBone runs once per model.
        local mdl = owner:GetModel() or ""
        local bone = handBone[mdl]
        if bone == nil then
            bone = owner:LookupBone("ValveBiped.Bip01_R_Hand") or false
            handBone[mdl] = bone
        end
        local matrix = bone and owner:GetBoneMatrix(bone)
        local ent = self:GetPropEntity("propWM")
        if not matrix or not ent then return end

        local pos, ang = offsetTransform(matrix:GetTranslation(), matrix:GetAngles(), self.PropWMPos, self.PropWMAng)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleWM = ent:LocalToWorld(self.PropMuzzle)

        for _, e in ipairs(self.ExtraProps or {}) do
            local key = mdl .. "|" .. (e.wmBone or "")
            local eb = handBone[key]
            if eb == nil then
                eb = e.wmBone and owner:LookupBone(e.wmBone) or false
                handBone[key] = eb
            end
            local em = eb and owner:GetBoneMatrix(eb)
            local ee = em and self:GetExtraEntity(e, "wm")
            if ee then drawExtra(self, ee, em, e.wmPos, e.wmAng, e.wmScale) end
        end

        -- "dual" mode: the second gun in the left hand.
        if self.DualPropWMPos and self:GetFireModeName() == "dual" then
            local key = mdl .. "|L"
            local lb = handBone[key]
            if lb == nil then
                lb = owner:LookupBone("ValveBiped.Bip01_L_Hand") or false
                handBone[key] = lb
            end
            local lm = lb and owner:GetBoneMatrix(lb)
            local le = lm and self:GetPropEntity("propWML")
            if le then
                local lp, la = offsetTransform(lm:GetTranslation(), lm:GetAngles(), self.DualPropWMPos, self.DualPropWMAng)
                le:SetPos(lp)
                le:SetAngles(la)
                le:SetupBones()
                le:DrawModel()
                self.propMuzzleWML = le:LocalToWorld(self.PropMuzzle)
            end
        end
    end

    function SWEP:OnRemove()
        if IsValid(self.propVM) then self.propVM:Remove() end
        if IsValid(self.propWM) then self.propWM:Remove() end
        if IsValid(self.propVML) then self.propVML:Remove() end
        if IsValid(self.propWML) then self.propWML:Remove() end
        if IsValid(self.rhylibMirrorHands) then self.rhylibMirrorHands:Remove() end
        if IsValid(self.rhylibMirrorVM) then self.rhylibMirrorVM:Remove() end
        if IsValid(self.rhylibProxyHands) then self.rhylibProxyHands:Remove() end
        if IsValid(self.rhylibProxyVM) then self.rhylibProxyVM:Remove() end
        for _, e in ipairs(self.ExtraProps or {}) do
            for _, side in ipairs({ "vm", "wm" }) do
                local x = self["rhylibExtra_" .. e.key .. side]
                if IsValid(x) then x:Remove() end
            end
        end
    end
end
