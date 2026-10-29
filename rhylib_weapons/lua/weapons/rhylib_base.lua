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
        Any mode but "auto" (and "overcharge", SWEP.AutoModes) fires once
        per trigger pull (e.g. "sidearm").
      - Shift + E + R toggles safety: the weapon is lowered (passive hold),
        can't fire or aim, and the crosshair hides.
      Semi and burst need a fresh trigger pull for each shot or burst.
      Primary.Automatic must stay true; the fire mode decides instead.

    Derived weapons set their own values below. Note: GMod does NOT merge
    the Primary, Secondary and Spread tables from the base, so a weapon
    that changes any field in them must define the whole table (Recoil too).

    Realm: shared (SWEP). Its client half is split into
    rhylib/weapons/base/cl_scope.lua, cl_vm.lua and cl_wm.lua (included at
    the end; each returns function(SWEP, env)). The position editors
    (rhylib_vm_editor, rhylib_wm_editor, rhylib_extra_editor, rhylib_vm_*)
    are in the separate Rhy's Dev Tools addon (rhylib_devtools).
    The parts it uses live in rhylib/weapons/:
    sh_10_spread (cone maths), sv_10_bolts / cl_10_bolts (bolts),
    cl_20_crosshair, cl_30_reload (R key, reload wheel), cl_50_recoil,
    sv_20_pouch (where magazines come from), sh_30_grapple (grapple and zipline modes).
    The guns themselves are in rhylib_republic; a gun file only sets
    fields (see docs/addons/rhylib_weapons.md, "Making your own gun").

    Methods other code calls (shared unless marked):
      IsLowered, GetFireModeName, ModeAllowed(i), FixFireMode, InGrappleMode, InZiplineMode,
      GetMag, GetMagSize, MagRounds(m), FirstMagFor(owner), TakesMag(id),
      IsReloading, CurrentFireRate, GetCellDamageMult, GetMoveMult,
      InfiniteAmmo, NoAmmoUse, UsesCarrier, GetInventoryData /
      SetInventoryData (rhylib_inventory), CarriedCount
      server: CycleFireMode, ToggleSafety, StartReload(kind, magId),
              FinishReload, ChooseMag, TrimClip, LeaveGrappleMode
      client: GetAimFrac, Scoped, GetPropMuzzle, CarrierPose(key), DrawScope
    Methods a gun may define to change behaviour: GetMoveMult,
    ExtraPoseOffset(e) (a moving offset for ExtraProps), RhylibModelsChanged
    (called by rhylib_core after a model override), and any of the usual
    SWEP hooks (CanPrimaryAttack, FireShot...) to change one part.

    Fields read here but not set below (nil = off / default):
      LoweredHold          hold type while lowered (nil = "normal" for pistol
                           grips, else "passive")
      PistolLowerTilt      degrees a pistol tips up while lowered (12)
      PistolLowerPos       its offset then: right, forward, up (0, -1, -3)
      PistolLowerPivot     turn point for that tilt: forward, right, up in
                           the view (nil = the eyes)
      ModeProxies          { mode = { model, bone, boneMove, PropBonePos,
                           PropBoneAng, PropBoneScale, VMOffset } }: another
                           viewmodel drawn for a fire mode (client copy)
      MagSkills            { mag id = skill id } (for the "needs a skill" note;
                           the real check is rhylib_skills K.MagAllowed)
      SpinSound            sound when the barrels start spinning (SpinUp)
      PlayerFireAnim       false = no third-person firing gesture
      Training, TrainingOf training copy of a gun (rhylib_training)
      Stun                 every bolt is a stun bolt (rhylib_mp)
    Fields other addons read: InvW/InvH/InvWeight/InvLarge/InvGroup/
    InvSlot/InvCategory (rhylib_inventory items), CarrySkill /
    RequiresSkill (rhylib_skills), NoArmoury (rhylib_armoury),
    NoGunStats (sh_70_gunstats).
]]

AddCSLuaFile()
-- The client parts (included from the CLIENT block at the end).
AddCSLuaFile("rhylib/weapons/base/cl_scope.lua")
AddCSLuaFile("rhylib/weapons/base/cl_vm.lua")
AddCSLuaFile("rhylib/weapons/base/cl_wm.lua")

SWEP.Base = "weapon_base"
SWEP.PrintName = "Rhy's weapon base"
SWEP.Category = "Rhy's"
SWEP.Spawnable = false
SWEP.Author = "Rhy"
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
SWEP.BoltSpeed = 7000               -- units per second, x config boltSpeedMult (max 32767: 15 bits on the wire)
SWEP.BoltColor = 1                  -- 1 blue, 2 red, 3 green (all styles: cl_10_bolts.lua)
-- Sounds from the Star Wars shared resources pack (Workshop dependency).
-- FireSound may be a list (one picked per shot); FireSoundLevel in dB
-- (140 = Source's own gunfire level, whose attenuation filter also sends
-- the sound far; lower levels don't carry across a map). FireSoundPitch
-- scales the pitch (DC-15S: the DC-15A sound, brighter). ReloadSound
-- overrides the magazine reload.
SWEP.FireSound = "weapons/dc15a/dc15a_fire.ogg"
SWEP.FireSoundLevel = 140
SWEP.FireSoundPitch = 1
-- Stun mode: the pack's own stun-ammo shot.
SWEP.StunSound = "weapons/bf3/e11_light.wav"
SWEP.ReloadSound = nil

-- Fire modes this weapon can switch between (E + R), first one is the default.
SWEP.FireModes = { "semi" }
SWEP.SprintRaiseTime = 0.25         -- seconds after sprinting before the gun can fire
SWEP.Grapple = false                -- true: gets "grapple" and "zipline" fire modes while you carry a grapple hook
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
SWEP.AimWhileReloading = nil        -- true: reloading doesn't lower the aim (riot shields: the shield stays up)
SWEP.CarrierHideBones = nil         -- more carrier bones to hide (e.g. a built-in shield): { "bone", ... }
-- Extra props, each drawn on a bone in first and third person:
-- { key, model, vmBone, vmPos, vmAng, vmScale, wmBone, wmPos, wmAng, wmScale }
SWEP.ExtraProps = nil   -- { { key, model, vmBone, vmPos, vmAng, vmScale, wmBone, wmPos, wmAng, wmScale,
                        --    vmAnchor = "view" (in the view, not on a bone), wmAnchor = "body" (bone position, body facing),
                        --    vmPosAim / vmAngAim (first-person pose while aiming, blended by GetAimFrac),
                        --    vmAimAnchor = "eyes" (with vmAnchor "view": the frame becomes the camera while aiming),
                        --    wmAttach = "anim_attachment_LH" (third person on a model attachment, wmBone as fallback),
                        --    vmIgnoreGunPose = true (with vmAnchor "view": not moved by the gun's AimPos, lowering,
                        --    reload dip or VMOffset; view bob still applies) } }
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
    (PropVMPos / PropVMAng). Tune in game with rhylib_vm_editor (Rhy's Dev Tools, rhylib_devtools).
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

-- Network vars (predicted, sent to everyone who can see the weapon, so a
-- shot changes as few as possible: Recoil, RecoilB, KickTime, Clip1).
-- ReloadKind: 0 none, 1 magazine, 2 power cell.
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
-- ("passive"). SWEP.LoweredHold overrides.
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
    if self.rhylibModeCache then self.rhylibModeCache[1] = nil end
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

-- Quick draw (rhylib_skills): called from Deploy, after the engine has
-- started the draw animation and set the wait to its end: the animation
-- plays faster and the gun (and the player's next attack) is ready sooner.
function SWEP:QuickDraw()
    local owner = self:GetOwner()
    if not (IsValid(owner) and owner:IsPlayer()) then return end
    local K = Rhylib.Skills
    local m = K and K.DrawMult and K.DrawMult(owner, self) or 1
    local vm = owner:GetViewModel()
    if m >= 1 or not IsValid(vm) then return end
    -- The draw animation's own length (not whatever the viewmodel was
    -- playing: an idle loop can be very long), capped.
    local seq = vm:SelectWeightedSequence(ACT_VM_DRAW)
    if not seq or seq < 0 then return end
    local dur = math.min(vm:SequenceDuration(seq), 2)
    local t = CurTime() + dur * m
    vm:SetPlaybackRate(1 / m)
    self.rhylibDrawEnd = t
    -- Only ever bring the waits forward, never push them later.
    if self:GetNextPrimaryFire() > t then self:SetNextPrimaryFire(t) end
    if self:GetNextSecondaryFire() > t then self:SetNextSecondaryFire(t) end
    local na = owner:GetInternalVariable("m_flNextAttack")
    if isnumber(na) and na > t then owner:SetSaveValue("m_flNextAttack", t) end
end

function SWEP:EndQuickDraw(owner)
    self.rhylibDrawEnd = nil
    local vm = IsValid(owner) and owner:GetViewModel()
    if IsValid(vm) and not self:IsReloading() then vm:SetPlaybackRate(1) end
end

-- Test mode (rhylib_infammo, admins): firing uses nothing, reloads are free.
function SWEP:InfiniteAmmo()
    local o = self:GetOwner()
    return IsValid(o) and o:IsPlayer() and o:GetNW2Bool("rhylib_infammo") or false
end

-- Shots take no ammo or cell charge: test ammo, or the officer order
-- Open up (rhylib_skills). Reloads still work normally under Open up.
function SWEP:NoAmmoUse()
    if self:InfiniteAmmo() then return true end
    local K = Rhylib.Skills
    return K and K.OrderIs and K.OrderIs(self:GetOwner(), "open") or false
end

-- Is the carrier viewmodel in use? (set in Initialize: CarrierVM,
-- CarrierBone and PropModel set and the carrier model installed)
function SWEP:UsesCarrier()
    return self.rhylibCarrier == true
end

-- Picks the carrier, sets the hold type, a full cell, the first fire mode
-- and the preferred magazine type. A gun that overrides Initialize should
-- call the base's (DEFINE_BASECLASS / self.BaseClass.Initialize).
function SWEP:Initialize()
    local c = self.CarrierVM
    if c and self.CarrierBone and self.PropModel and self.PropFirstPerson ~= false and (util.IsValidModel(c) or file.Exists(c, "GAME")) then   -- (client: a model nobody has loaded yet isn't "valid")
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

-- The grapple modes sit after the weapon's own modes: "grapple" at index
-- #FireModes + 1, "zipline" at #FireModes + 2.
-- The mode name used at index i: a grapple slot, the mode itself if
-- allowed, the mode that replaces it (sidearm for semi), else the first
-- allowed one (a skill since lost or gained).
function SWEP:ModeNameAt(i)
    if self.Grapple and i == #self.FireModes + 1 then return "grapple" end
    if self.Grapple and i == #self.FireModes + 2 then return "zipline" end
    if not self:ModeAllowed(i) then i = self:ReplacementFor(i) or self:FirstAllowedMode() end
    return self.FireModes[i] or self.FireModes[1] or "semi"
end

-- (asked many times a frame and per shot: worked out once per tick per mode)
function SWEP:GetFireModeName()
    local m, t = self:GetFireMode(), CurTime()
    local c = self.rhylibModeCache
    if c and c[1] == m and c[2] == t then return c[3] end
    local name = self:ModeNameAt(m)
    -- (one table per weapon, reused)
    if not c then c = {} self.rhylibModeCache = c end
    c[1], c[2], c[3] = m, t, name
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

-- InGrappleMode: either grapple slot (grapple or zipline); InZiplineMode: the second.
function SWEP:InGrappleMode()
    return self.Grapple and self:GetFireMode() > #self.FireModes
end

function SWEP:InZiplineMode()
    return self.Grapple and self:GetFireMode() == #self.FireModes + 2
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

-- Taking the gun out: Quick draw (skills), no aim, a fire mode the owner
-- may still use, the right viewmodel for the mode.
function SWEP:Deploy()
    self:QuickDraw()
    self:SetAiming(false)
    self:FixFireMode()
    if self:GetFireModeName() == "dual" then self:ApplyDualViewModel(true) end
    self:ApplyModeCarrier(nil, true)
    return true
end

function SWEP:Holster()
    if self.rhylibDrawEnd then self:EndQuickDraw(self:GetOwner()) end   -- (the viewmodel is shared)
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
        local total = n + (grapple and 2 or 0)   -- (grapple, then zipline)
        if self:GetSafety() or total <= 1 then
            self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 60)
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
            self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 60)
            return
        end
        if nextMode > n and cur <= n then self.preGrappleMode = cur end
        self:SetFireMode(nextMode)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/2misc_non_guns/sw_change.ogg", 60)
    end

    -- Back to the fire mode used before switching to grapple.
    function SWEP:LeaveGrappleMode()
        if not self:InGrappleMode() then return end
        local m = self.preGrappleMode
        self:SetFireMode(self.FireModes[m or 0] and m or 1)
    end

    -- The stun key (net wep.stunmode, MPs): straight to the "stun" fire
    -- mode, or back to the mode used before it. Refused (empty click) on
    -- safety, without a stun mode, or when the owner may not use it.
    function SWEP:ToggleStunMode()
        local idx
        for i, n in ipairs(self.FireModes or {}) do
            if n == "stun" then idx = i break end
        end
        if self:GetSafety() or not idx or not self:ModeAllowed(idx) then
            self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 60)
            return
        end
        local cur = self:GetFireMode()
        if cur == idx then
            local back = self.preStunMode
            if not (back and back ~= idx and self.FireModes[back] and self:ModeAllowed(back)) then back = self:FirstAllowedMode() end
            self:SetFireMode(back)
        else
            self.preStunMode = cur
            self:SetFireMode(idx)
        end
        self:SetBurstLeft(0)
        self:EmitSound("weapons/2misc_non_guns/sw_change.ogg", 60)
    end

    -- Shift + E + R.
    function SWEP:ToggleSafety()
        local on = not self:GetSafety()
        self:SetSafety(on)
        self:SetAiming(false)
        self:SetBurstLeft(0)
        self:EmitSound("weapons/2misc_non_guns/sw_change.ogg", 60, 85)
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
    if not (self.InvLarge and IsValid(owner) and owner:IsPlayer() and jp and jp.Flying and jp.Flying(owner)) then return false end
    local K = skills()
    if K and K.FlyFire and K.FlyFire(owner, self) then return false end   -- (DP-23 proficiency)
    return true
end

-- Can a shot go now? Not lowered, not reloading (or waiting for the
-- server's reload answer), not too heavy to fire in flight, rounds in the
-- clip and charge in the cell. Plays the empty click when empty.
function SWEP:CanPrimaryAttack()
    if self:IsLowered() then return false end
    if self:GetReloadKind() ~= RELOAD_NONE then
        self.rhylibReloadHold = nil
        return false
    end
    -- (client: a reload was asked for, the server's answer isn't here yet;
    -- cl_30_reload. Commands from before the request, run again by
    -- prediction, still fire.)
    local hold = self.rhylibReloadHold
    if hold then
        local now = CurTime()
        if now >= hold then
            self.rhylibReloadHold = nil
        elseif now >= (self.rhylibReloadFrom or 0) then
            return false
        end
    end
    if self:TooHeavyToFire() then return false end

    if self:Clip1() <= 0 then
        self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 65)
        self:SetNextPrimaryFire(CurTime() + 0.3)
        return false  -- empty: just the click, reloading is up to you (R)
    end

    if self.UsesCell and self:GetCell() <= 0 then
        self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 65)
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
    if not self.AutoModes[mode] or self:GetSafety() then
        if not self:GetTriggerReady() then return end
        self:SetTriggerReady(false)
    end

    if self:GetSafety() then
        self:EmitSound("weapons/2misc_non_guns/sw_noammo.ogg", 60)
        return
    end
    if mode == "grapple" or mode == "zipline" then
        self:FireGrapple(mode == "zipline")
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
-- Overcharge (DC-15A, Autorifleman skill): bigger, brighter bolts (training copies stay yellow).
local OVER_OPTS = { color = 10 }
-- Modes that keep firing while the trigger is held.
SWEP.AutoModes = { auto = true, overcharge = true }
SWEP.StunFireRate = 75   -- one ring every 0.8 s

-- First-leg pellet hits, applied after lag compensation (reused list).
local pelletHits = {}

-- The bolts of one shot. hits: see Bolts.Fire (server, several pellets).
local function firePellets(self, owner, origin, dir, pellets, cone, damage, stun, hits, overcharge)
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
        local opts = stun and STUN_OPTS or (overcharge and not self.Training and OVER_OPTS) or nil
        if SERVER then
            Rhylib.Weapons.Bolts.Fire(owner, self, origin, d, stun and 0 or damage, opts, hits)
        elseif IsFirstTimePredicted() then
            Rhylib.Weapons.Bolts.FireLocal(owner, self, origin, d, opts)
        end
    end
end

-- One shot: spread, recoil, ammo, sound and the bolt. Shared and
-- predicted: the server fires the real bolts (Bolts.Fire), the shooter's
-- client draws its own at once (Bolts.FireLocal). A gun can override it
-- for something that isn't a bolt (rhylib_republic's grenade launcher).
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
    if not self:NoAmmoUse() then
        pellets = math.max(1, math.min(pellets, self:Clip1()))
        self:TakePrimaryAmmo(pellets)
    end
    if self.UsesCell and not self:NoAmmoUse() then
        local shots = self.CellShots * (K and K.CellMult and K.CellMult(owner) or 1)
        if K and K.CellDrainMult then shots = shots / K.CellDrainMult(owner, self) end   -- (Overcharge)
        self:SetCell(math.max(0, self:GetCell() - 1 / shots))
    end

    local stun = self:GetFireModeName() == "stun"
    local over = self:GetFireModeName() == "overcharge"
    -- (Overcharge: the same shot, pitched down so it sounds heavier)
    local snd = self.FireSound
    if istable(snd) then snd = snd[math.floor(util.SharedRandom("rhylib.snd", 1, #snd + 0.999))] or snd[1] end
    local lvl = (self.FireSoundLevel or 140) + (over and 5 or 0)
    self:EmitSound(stun and self.StunSound or snd, stun and 100 or lvl,
        util.SharedRandom("rhylib.pitch", 96, 104) * (over and 0.82 or 1) * (stun and 1.15 or (self.FireSoundPitch or 1)), 1, CHAN_WEAPON)
    -- Sustained fire (rhylib_skills): when this spray started (a gap over 0.3 s starts a new one).
    if SERVER or IsFirstTimePredicted() then
        if now - (self.rhylibLastShot or 0) > 0.3 then self.rhylibSprayStart = now end
        self.rhylibLastShot = now
    end
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
    -- Several pellets: one lag compensation around them all; their hits
    -- are applied after it's off (Bolts.ApplyHits).
    local hits = SERVER and pellets > 1 and owner:IsPlayer() and pelletHits or nil
    if not hits then
        firePellets(self, owner, origin, dir, pellets, cone, damage, stun, nil, over)
        return
    end
    for i = #hits, 1, -1 do hits[i] = nil end   -- (left over if a hit errored)
    owner:LagCompensation(true)
    local ok, err = pcall(firePellets, self, owner, origin, dir, pellets, cone, damage, stun, hits, over)
    owner:LagCompensation(false)   -- (always, even after an error)
    if not ok then error(err, 0) end
    Rhylib.Weapons.Bolts.ApplyHits(hits)
end

-- One grapple hook (see rhylib/weapons/sh_30_grapple.lua); zipline = the
-- zipline fire mode.
function SWEP:FireGrapple(zipline)
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + Rhylib.Config.Get("grapple", "cooldown"))
    local G = Rhylib.Weapons.Grapple
    if IsFirstTimePredicted() then
        self:EmitSound("weapons/crossbow/fire1.wav", 70, 115)
        owner:SetAnimation(PLAYER_ATTACK1)
        -- Your own client draws the hook flying out straight away.
        -- (zipline mode: only when standing where the server will rig one)
        if CLIENT and owner:GetAmmoCount(G.AMMO) > 0 and (not zipline or G.ZipGround(owner)) then
            Rhylib.Weapons.Bolts.Spawn(owner, owner:GetShootPos(), owner:GetAimVector(),
                Rhylib.Config.Get("grapple", "hookSpeed"), 5)
        end
    end
    if SERVER then G.Fire(owner, self, zipline) end
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
        [RELOAD_MAG] = "weapons/shared/battlefront_standard_reload.ogg",
        [RELOAD_CELL] = "weapons/2misc_non_guns/sw_startup.ogg",
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
                            Rhylib.Notify(owner, "Loading those needs the " .. (n and n.name or need) .. " skill", "bad", "Weapons")
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
        self:EmitSound(kind == RELOAD_MAG and self.ReloadSound or SOUNDS[kind], 75)
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
-- weapon is stored. rhylib_inventory calls GetInventoryData when the gun
-- is put away and SetInventoryData(data) when it's given back.
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

-- Every tick (predicted): finish reloads, auto reload, sprint lowering,
-- spin-up, trigger release, bursts and the aim (right mouse).
function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    -- (Quick draw: back to normal speed once the faster draw is done)
    if self.rhylibDrawEnd and CurTime() >= self.rhylibDrawEnd then self:EndQuickDraw(owner) end

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
    local want = not self.NoAim and owner:KeyDown(IN_ATTACK2) and (self.AimWhileReloading or not self:IsReloading()) and not self:IsLowered()
        and not (Med and Med.CanAim and not Med.CanAim(owner))  -- hurt arms can't aim
    if want ~= self:GetAiming() then
        self:SetAiming(want)
    end
end

--------------------------------------------------------------------------
-- Client: aiming, crosshair, HUD and prop models
--------------------------------------------------------------------------

if CLIENT then
    -- The client parts live in rhylib/weapons/base/ (not loaded as module
    -- files: the core loader only reads rhylib/weapons/*.lua). Each returns
    -- function(SWEP, env); env carries the few helpers they share and is
    -- kept as Rhylib.Weapons.BaseClient (rhylib_devtools' editors use it).
    local env = {}
    Rhylib.Weapons = Rhylib.Weapons or {}
    Rhylib.Weapons.BaseClient = env
    include("rhylib/weapons/base/cl_scope.lua")(SWEP, env)


    -- Smooth 0..1 value for the aim animation, client only.
    function SWEP:GetAimFrac()
        return self.aimFrac or 0
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

    include("rhylib/weapons/base/cl_vm.lua")(SWEP, env)
    include("rhylib/weapons/base/cl_wm.lua")(SWEP, env)
end
