--[[
    Coruscant Guard riot shield + DC-15S (military police, rhylib_skills
    Shock Trooper > Riot shield). A DC-15S in the right hand, a shield on
    the left arm: bolts from the front stop on it (rhylib_weapons
    sh_60_shield.lua), and so does a breaching charge's blast.

    2026-10-08 (owner): right mouse aims like any gun again; the shield
    bash has its own key (client convar rhylib_shield_bash_key, default X,
    Settings > Controls), sent to the server (net wep.shieldbash).
    This CG shield is the proficient one (SWEP.ShieldProficiency): Hold
    the line, Phalanx and the bash's stun (Shield bash skill) only work
    with it. rhylib_riotshield_rep is the Republic shield anyone may
    carry: same blocking, a bash that only shoves, no skill bonuses.

    Shield models (SWEP.ShieldKind -> SHIELDS below, first installed of
    the kind's list wins): cs574's shields pack (Workshop dependency):
    models/cs574/weapons/shields/shield2.mdl (CG) and blast_shield.mdl
    (Republic); the old packs as fallbacks. Tune in game:
    rhylib_extra_editor (shield and arms), rhylib_vm_editor /
    rhylib_wm_editor (the gun).

    First person: the DC-15S's own viewmodel (left arm folded away), the
    shield placed in the view: out on the left, or with right mouse flat in
    front with its viewport on the crosshair (the CG shield stays angled,
    only pulled closer). Third person: the shield held in the left hand
    (anim_attachment_LH, "duel" hold type).

    Shared (AddCSLuaFile). Class rhylib_riotshield, base rhylib_dc15s.
    Blocking, Hold the line and Phalanx live in rhylib_weapons
    sh_60_shield.lua (W.ShieldBlocks etc.); this file is the weapon, its
    look and the bash. Net message rhylib.wep.shieldbash (client -> server,
    empty; rate 3 a second): the bash key was pressed. Client convar
    rhylib_shield_bash_key (default x, Settings > Controls).
]]

AddCSLuaFile()

DEFINE_BASECLASS("rhylib_dc15s")

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "CG riot shield (DC-15S)"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true

SWEP.RiotShield = true
SWEP.NoAim = false            -- (right mouse aims; the bash has its own key)
SWEP.AimWhileReloading = true -- (the shield stays up while you reload; it used to drop to the side and stop covering the front)
SWEP.CarrySkill = "riot_shield"
SWEP.ShieldKind = "cg"
SWEP.ShieldProficiency = true -- (Hold the line, Phalanx, stun bash: CG shield only)
SWEP.BashStun = true          -- (the bash stuns a player: MPs with Shield bash)
SWEP.BashSkill = "shield_bash"
SWEP.HoldType = "duel"   -- (third person: left arm up holding the shield, right hand the gun; cs574's shields use it)
-- On safety / sprinting (2026-10-09, owner: no bash; 2026-10-09c: only the
-- gun turns, straight up, 90°): first person the gun turns muzzle-up around
-- the hand (rhylib_base PistolLowerPivot), the shield stays put
-- (vmIgnoreGunPose); third person it hangs at the side ("normal"; GMod has
-- no pistol-up hold type). CanBash already refuses while lowered.
SWEP.LoweredHold = "normal"
SWEP.PistolLowerTilt = 90
SWEP.PistolLowerPivot = Vector(14, 5, -8)   -- (forward, right, up: about the gun hand; guess)
SWEP.PistolLowerPos = Vector(0, 0, -1)

-- Aiming (AimPos: right, forward, up). CG shield (2026-10-09g, owner): the
-- shield stays angled on the left, so the gun comes up slightly. The
-- Republic shield's own file drops it below the viewport instead.
SWEP.AimPos = Vector(-2.5, 1, 3.5)   -- (2026-10-09h, owner: further in and up the screen)

-- First person (2026-10-09b, owner: hold it like a handgun): the DC-15S on
-- the DC-17's pistol hands (bf2017 c_scoutblaster, with its firing kick),
-- using the values tuned for the DC-15S's sidearm mode (owner-confirmed).
-- The shield isn't hand-held (it's placed in the view), so the left arm is
-- folded away (CarrierHideBones).
SWEP.CarrierVM = "models/bf2017/c_scoutblaster.mdl"
SWEP.CarrierBone = "v_scoutblaster_reference001"
SWEP.CarrierBoneMove = Vector(0, 0, 0)
SWEP.PropBonePos = Vector(-1.5, 9, 0.5)
SWEP.PropBoneAng = Angle(-2, 89, 0)
SWEP.PropBoneScale = 0.8
SWEP.VMOffset = Vector(0, 0, -2.5)   -- (right, forward, up: lower, owner 2026-10-09c)
SWEP.CarrierHideBones = { "ValveBiped.Bip01_L_UpperArm" }
SWEP.CarrierBoneMods = nil

-- Semi only (2026-10-09, owner: no auto with a shield; stun stays for MPs),
-- no sidearm mode (it's always held like a sidearm now).
SWEP.FireModes = { "semi", "stun" }
SWEP.ModeReplaces = {}
SWEP.ModeProxies = {}
SWEP.ModeHoldTypes = {}
SWEP.ModeFireGestures = {}

-- More accurate than the plain DC-15S (owner 2026-10-09; its hip 1.4 /
-- aim 0.7, bloom 0.11 up to 2.0). Its own table, so Server settings "guns"
-- changes to the DC-15S don't reach it.
SWEP.Spread = {
    hip = 0.9,
    aim = 0.4,
    kickMain = 0.3,
    kickSide = 0.08,
    bloomPerShot = 0.08,
    bloomMax = 1.4,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

-- Firing through the viewport (2026-10-09, owner): only with the Shock
-- Trooper "Riot shield" skill; anyone else aiming a shield is in full
-- cover and can't fire. Without rhylib_skills: the CG shield may, the
-- Republic shield may not.
SWEP.AimFireSkill = "riot_shield"

-- Third person: extra turns of the left arm bones (client side, not while
-- lowered). All zero now; tune with rhylib_extra_editor.
-- Third person: the left arm off the pistol grip (start: none; rhylib_extra_editor).
SWEP.WorldBoneMods = {
    ["ValveBiped.Bip01_L_UpperArm"] = Angle(0, 0, 0),
    ["ValveBiped.Bip01_L_Forearm"] = Angle(0, 0, 0),
}

-- Shield models and where they sit. Each entry becomes one rhylib_base
-- ExtraProps prop (see rhylib_base for vmAnchor / vmAimAnchor / wmAttach
-- etc.). The cs574 entries are placed in the view (first person) and in
-- the left hand (third person); the old packs' entries use the left hand /
-- forearm bones. The cs574 numbers are starting guesses: tune with
-- rhylib_extra_editor and paste them here.
local SHIELDS = {
    -- cs574's models: 36 wide (X), ~5 thick (front face -Y), ~69 tall (Z),
    -- the handle near the origin. Placed in the view (first person) and at
    -- the left forearm turned with the body (third person), turned 90° so
    -- the face points ahead (owner 2026-10-08: the bone placement lay
    -- them flat / filled the screen).
    -- Third person (2026-10-09j, owner): held by the left hand like cs574's
    -- own shield weapons (their numbers: the player model's
    -- anim_attachment_LH, forward/right/up offset, turned 90-100°, scale 1)
    -- with the two-handed "duel" hold type raising the left arm, so it
    -- follows every animation. (The chest anchor, Spine2, clipped.)
    -- First person: about 40% of the screen wide on the left, top a quarter
    -- down the screen (2026-10-08b: the forearm anchor put it inside the
    -- body, and 0.45 was tiny in the viewmodel's narrower field of view).
    -- First person has two poses (2026-10-08d, owner): not aiming = out on
    -- the left, face turned ~45° to the left (blocks only a wedge there,
    -- sh_60_shield); aiming = centre-left, flat to the front, top just under
    -- the crosshair. Blended by the aim (vmPosAim / vmAngAim).
    -- Aimed (2026-10-09, owner: line the viewport up with the view): the
    -- frame becomes the camera itself (vmAimAnchor "eyes"), so a point at
    -- right 0 / up 0 sits on the crosshair. Read from the models' meshes:
    -- blast_shield's slit is x -8.5..9.0, z 14.9..19.5 (centre x 0.25,
    -- z 17.2, 86% up); shield2 has no slit, so its top notch (centre x 0.45,
    -- bottom z 12.7) is put there and you look over it. Model x runs to
    -- the left when turned 90°, so right = +0.9 × x centres it.
    cg = { model = "models/cs574/weapons/shields/shield2.mdl", vmAnchor = "view", vmAimAnchor = "eyes", vmIgnoreGunPose = true, wmAttach = "anim_attachment_LH", wmBone = "ValveBiped.Bip01_L_Hand",
        vmPos = Vector(24, -24, -9), vmAng = Angle(0, 135, 0), vmScale = 0.9,
        -- (2026-10-09f, owner: the CG shield keeps its angle when aiming and is
        -- only pulled in closer, so they see better; it still blocks the front
        -- cone while aimed, weapons cgShieldArc)
        vmPosAim = Vector(17, -16, -8), vmAngAim = Angle(0, 135, 0),
        wmPos = Vector(5, 5, -2), wmAng = Angle(0, 100, 0), wmScale = 1 },
    rep = { model = "models/cs574/weapons/shields/blast_shield.mdl", vmAnchor = "view", vmAimAnchor = "eyes", vmIgnoreGunPose = true, wmAttach = "anim_attachment_LH", wmBone = "ValveBiped.Bip01_L_Hand",
        vmPos = Vector(24, -24, -17), vmAng = Angle(0, 135, 0), vmScale = 0.9,
        vmPosAim = Vector(22, 0.2, -15.5), vmAngAim = Angle(0, 90, 0),
        wmPos = Vector(5, 5, -10), wmAng = Angle(0, 100, 0), wmScale = 1 },   -- (2026-10-09o, owner: like the CG shield: its numbers, 8 lower since this model's middle sits 8 higher above its handle)
    -- (older packs, used when cs574's isn't installed)
    tf2 = { model = "models/workshop/weapons/c_models/c_batonshield/c_batonshield_shield.mdl",
        vmPos = Vector(30.851, 42.902, -5.067), vmAng = Angle(0.535, 54.853, 5.843), vmScale = 1,
        wmPos = Vector(-43.257, 6.151, -1.39), wmAng = Angle(0, 79.309, 178.636), wmScale = 0.899 },
    riot = { model = "models/bshields/rshield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90.364, 1.33), vmScale = 0.699,
        wmPos = Vector(5.6, 2.9, 0.7), wmAng = Angle(0, 100, 0), wmScale = 0.92 },
    heavy = { model = "models/bshields/hshield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90.364, 1.33), vmScale = 0.699,
        wmPos = Vector(5.6, 2.9, 0.7), wmAng = Angle(0, 100, 0), wmScale = 0.92 },
    hevy = { model = "models/hevy/w_shield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90, 0), vmScale = 0.7,
        wmPos = Vector(4, 2, 0), wmAng = Angle(0, 90, 90), wmScale = 0.92 },
}
-- Fallback order per ShieldKind: the first installed model wins.
local ORDER = { cg = { "cg", "rep", "riot", "heavy", "tf2", "hevy" }, rep = { "rep", "cg", "riot", "heavy", "tf2", "hevy" } }
-- Inventory picture: the shield itself (rhylib_inventory cl_15_icons, first installed).
SWEP.InvIconModels = { SHIELDS.cg.model, SHIELDS.riot.model, SHIELDS.heavy.model, SHIELDS.hevy.model, SHIELDS.tf2.model }

local function installed(m) return util.IsValidModel(m) or file.Exists(m, "GAME") end

local function shieldProp(kind)
    for _, k in ipairs(ORDER[kind] or ORDER.cg) do
        local sh = SHIELDS[k]
        if sh and installed(sh.model) then
            return { key = "shield", model = sh.model, vmAnchor = sh.vmAnchor, vmAimAnchor = sh.vmAimAnchor, vmIgnoreGunPose = sh.vmIgnoreGunPose, wmAnchor = sh.wmAnchor, wmAttach = sh.wmAttach,
                vmBone = "ValveBiped.Bip01_L_Hand", vmPos = sh.vmPos, vmAng = sh.vmAng, vmScale = sh.vmScale,
                vmPosAim = sh.vmPosAim, vmAngAim = sh.vmAngAim,
                wmBone = sh.wmBone or "ValveBiped.Bip01_L_Forearm", wmPos = sh.wmPos, wmAng = sh.wmAng, wmScale = sh.wmScale }
        end
    end
end
SWEP.ShieldModels = SHIELDS

-- Server settings > Models: each shield's own model (the first picture
-- in its inventory icon list follows it).
if Rhylib and Rhylib.Hook then
    Rhylib.Hook.Add("Rhylib.ModelCatalogue", "republic.shields", function(add)
        for _, sp in ipairs({ { "rhylib_riotshield", "cg", "CG riot shield" }, { "rhylib_riotshield_rep", "rep", "Republic shield" } }) do
            local class, kind = sp[1], sp[2]
            add("weapon." .. class .. ".shield", sp[3] .. " · shield", "Weapons: Equipment", function() return SHIELDS[kind] end, "model", function(v)
                local st = weapons.GetStored(class)
                local icons = st and rawget(st, "InvIconModels")
                if istable(icons) then icons[1] = v end
            end)
        end
    end)
end

SWEP.ExtraProps = nil   -- (picked per weapon in Initialize, from the installed models)

function SWEP:Initialize()
    BaseClass.Initialize(self)
    if CLIENT then
        local p = shieldProp(self.ShieldKind)
        if p then util.PrecacheModel(p.model) end
        self.ExtraProps = p and { p } or nil
    end
end

-- Server settings > Models changed a shield after this one was made
-- (rhylib_core sh_25_models): pick the prop again.
function SWEP:RhylibModelsChanged()
    if not CLIENT then return end
    local p = shieldProp(self.ShieldKind)
    if p then util.PrecacheModel(p.model) end
    self.ExtraProps = p and { p } or nil
    for _, side in ipairs({ "vm", "wm" }) do
        local k = "rhylibExtra_shield" .. side
        if IsValid(self[k]) then self[k]:Remove() end
        self[k] = nil
    end
end

-- SWEP:AimFireBlocked(): true while aiming without the AimFireSkill
-- ("riot_shield"); without rhylib_skills only the CG shield may fire
-- through the viewport. Shared (CanPrimaryAttack and the HUD use it).
function SWEP:AimFireBlocked()
    if not (self.GetAiming and self:GetAiming()) then return false end
    local o = self:GetOwner()
    local K = Rhylib.Skills
    if K and K.Has then return not (IsValid(o) and K.Has(o, self.AimFireSkill)) end
    return not self.ShieldProficiency
end

function SWEP:CanPrimaryAttack()
    if self:AimFireBlocked() then return false end
    return BaseClass.CanPrimaryAttack(self)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return BaseClass.Deploy(self)
end

SWEP.InvW = 3
SWEP.InvH = 2
SWEP.InvLarge = true
-- Carried on the back (owner 2026-10-09): only in the back slot, so a shield
-- and a backpack / jetpack can't be carried together. Still goes on the
-- hotbar from there.
SWEP.InvSlot = "back"
SWEP.InvSlotOnly = true
-- CG shield vs the Republic shield (owner 2026-10-09: the CG one must be
-- better): lighter (7 vs 9 kg), faster on foot (0.92 vs 0.85), wider cover
-- (weapons cgShieldArc / cgShieldSideArc), halves blasts it's held up
-- against (cgShieldBlast), fires through its viewport (Riot shield skill,
-- which you need to carry it anyway), and its bash stuns (Shield bash).
SWEP.InvWeight = 7.0         -- kg (gun and shield)

SWEP.MoveMult = 0.92         -- walking with a shield up
SWEP.BashRange = 75
SWEP.BashDelay = 1.5

function SWEP:GetMoveMult()
    local m = BaseClass.GetMoveMult(self)
    return math.min(m, self.MoveMult)
end

-- Shield bash (own key, net wep.shieldbash; owner 2026-10-08: right mouse
-- aims). CG shield: needs the Shield bash skill and stuns a player (MPs);
-- the Republic shield: anyone, only shoves.
-- SWEP:CanBash(): off cooldown (BashDelay), not lowered, BashSkill if set.
-- SWEP:Bash(): server. A hull trace BashRange ahead: a player is stunned
-- (BashStun + the basher is an MP, rhylib_mp) or shoved; an NPC / NextBot
-- takes skills bashDamage (DMG_CLUB) and is pushed back. Downed (lying)
-- players are skipped.
function SWEP:CanBash()
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer()) then return false end
    if CurTime() < (self.rhylibNextBash or 0) or self:IsLowered() then return false end
    if self.BashSkill then
        local K = Rhylib.Skills
        if not (K and K.Has and K.Has(o, self.BashSkill)) then return false end
    end
    return true
end

function SWEP:Bash()
    if not self:CanBash() then return end
    local o = self:GetOwner()
    self.rhylibNextBash = CurTime() + self.BashDelay
    o:SetAnimation(PLAYER_ATTACK1)
    o:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav", 70, 95)
    o:LagCompensation(true)
    local tr = util.TraceHull({
        start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * self.BashRange,
        filter = o, mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10), mask = MASK_SHOT_HULL,
    })
    o:LagCompensation(false)
    local e = tr.Entity
    local L = Rhylib.Lying
    if L and L.Owner and L.Owner(e) then return end   -- (not on someone already down)
    if not IsValid(e) then return end
    local push = o:GetAimVector()
    push.z = 0
    push:Normalize()
    if e:IsPlayer() then
        local MP = Rhylib.MP
        if self.BashStun and MP and MP.Stun and MP.IsMP and MP.IsMP(o) then
            MP.Stun(e, o)
        else
            e:SetVelocity(push * 260 + Vector(0, 0, 90))   -- (a shove)
        end
    elseif e:IsNPC() or e:IsNextBot() then
        local d = DamageInfo()
        d:SetDamage(Rhylib.Config.Get("skills", "bashDamage") or 30)
        d:SetDamageType(DMG_CLUB)
        d:SetAttacker(o)
        d:SetInflictor(self)
        d:SetDamagePosition(tr.HitPos)
        d:SetDamageForce(push * 16000)
        e:TakeDamageInfo(d)
        if e:IsNextBot() and e.loco then e.loco:SetVelocity(push * 320 + Vector(0, 0, 120)) end
        if e.rhylibStagger then e:rhylibStagger(1) end
    end
end

if SERVER then
    Rhylib.Net.Receive("wep.shieldbash", function(ply)
        local w = ply:GetActiveWeapon()
        if IsValid(w) and w.RiotShield and w.Bash then w:Bash() end
    end, { rate = 3, burst = 3 })
end

if CLIENT then
    local bashKey = CreateClientConVar("rhylib_shield_bash_key", "x", true, false, "Riot shield: the shield bash key")
    local wasDown = false
    Rhylib.Hook.Add("Think", "weapons.shieldbashkey", function()
        local me = LocalPlayer()
        if not IsValid(me) then return end
        local w = me:GetActiveWeapon()
        if not (IsValid(w) and w.RiotShield) then wasDown = false return end
        local code = input.GetKeyCode(bashKey:GetString())
        local down = code and code > 0 and input.IsButtonDown(code) or false
        local pressed = down and not wasDown
        wasDown = down
        if not pressed or gui.IsGameUIVisible() or vgui.CursorVisible() or me:IsTyping() then return end
        if not (w.CanBash and w:CanBash()) then return end
        w.rhylibNextBash = CurTime() + w.BashDelay
        w.rhylibBashAt = RealTime()   -- (the shield shoves forward: ExtraPoseOffset)
        me:ViewPunch(Angle(-4, 2, 0))
        Rhylib.Net.Start("wep.shieldbash")
        net.SendToServer()
    end)
    local function addSetting()
        local M = Rhylib.Menus
        if M and M.AddSetting then
            M.AddSetting("Controls", { id = "weapons.shieldbash", order = 60, title = "Riot shield: shield bash", kind = "key", convar = "rhylib_shield_bash_key" })
        end
    end
    addSetting()
    Rhylib.Hook.Add("InitPostEntity", "weapons.shieldbashsetting", addSetting)
end

if CLIENT then
    -- Shield bash in first person: the shield shoves forward ~10 units and
    -- back over 0.3 s (the carbine's viewmodel has no bash animation).
    local BASH_TIME, BASH_PUSH = 0.3, 10
    function SWEP:ExtraPoseOffset(e)
        local t = self.rhylibBashAt and (RealTime() - self.rhylibBashAt) / BASH_TIME
        if not t or t >= 1 then return end
        return Vector(math.sin(t * math.pi) * BASH_PUSH, 0, 0)
    end

    function SWEP:DrawHUD()
        BaseClass.DrawHUD(self)
        local K = Rhylib.Skills
        local o = self:GetOwner()
        if IsValid(o) and self:AimFireBlocked() and not self:IsLowered() then
            local s = ScrH() / 1080
            draw.SimpleText("FULL COVER  ·  can't fire through the viewport (Riot shield skill)", Rhylib.UI.Font(13, 600),
                ScrW() * 0.5, ScrH() * 0.55 + 22 * s, Rhylib.UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        if IsValid(o) and not self:IsLowered() and (not self.BashSkill or (K and K.Has and K.Has(o, self.BashSkill))) then
            local s = ScrH() / 1080
            local key = string.upper(GetConVarString("rhylib_shield_bash_key") or "x")
            draw.SimpleText(key .. "  shield bash", Rhylib.UI.Font(13, 600), ScrW() * 0.5, ScrH() * 0.55 + 40 * s,
                Rhylib.UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end
