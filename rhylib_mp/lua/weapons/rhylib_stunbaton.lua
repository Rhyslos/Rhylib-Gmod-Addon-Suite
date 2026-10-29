--[[
    Stun baton (military police).
      LMB  swing: a hit makes the target collapse (rhylib_mp stun)
      RMB  search the player you look at: see their inventory; if they're
           cuffed you can take items. Also lets you open locked lockers.

    Shared SWEP. Anyone can swing it, but only an MP's hit stuns
    (server checks MP.IsMP). The swing is lag compensated. RMB just asks
    the server (MP.OpenSearch); the server checks MP, range and sight.
    Range and delay come from config mp batonRange, batonDelay, searchRange.
    Client DrawHUD: "name · LMB stun · RMB search" under the crosshair
    while aiming at a player in reach (SWEP.Hint).
]]


AddCSLuaFile()

SWEP.PrintName = "Stun baton"
SWEP.Category = "Rhy's Military police"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.UseHands = true
SWEP.HoldType = "melee"
SWEP.Instructions = "LMB: stun   RMB: search"
SWEP.Hint = "LMB stun  ·  RMB search"   -- (DrawHUD: under the crosshair while aiming at someone in reach)

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- Inventory item (rhylib_inventory).
SWEP.InvW = 2
SWEP.InvH = 1
SWEP.InvWeight = 0.8
SWEP.InvCategory = "gear"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
    local MP = Rhylib.MP
    local owner = self:GetOwner()
    if not MP or not IsValid(owner) then return end
    self:SetNextPrimaryFire(CurTime() + MP.Cfg("batonDelay"))
    owner:SetAnimation(PLAYER_ATTACK1)
    owner:LagCompensation(true)
    local target = MP.Target(owner, MP.Cfg("batonRange"))
    owner:LagCompensation(false)
    self:SendWeaponAnim(target and ACT_VM_HITCENTER or ACT_VM_MISSCENTER)
    if not IsFirstTimePredicted() then return end
    self:EmitSound(target and "weapons/stunstick/stunstick_fleshhit1.wav" or "weapons/stunstick/stunstick_swing1.wav", 65)
    if SERVER and target and MP.IsMP(owner) then MP.Stun(target, owner) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.6)
    if not CLIENT or not IsFirstTimePredicted() then return end
    local MP = Rhylib.MP
    local target = MP and MP.Target(self:GetOwner(), MP.Cfg("searchRange"))
    if target and MP.OpenSearch then MP.OpenSearch(target) end
end

if CLIENT then
    -- Key hint while aiming at someone in reach (looked up every 0.15 s).
    function SWEP:DrawHUD()
        local MP = Rhylib.MP
        if not MP then return end
        local now = CurTime()
        if not self.rhylibHintAt or now > self.rhylibHintAt then
            self.rhylibHintAt = now + 0.15
            self.rhylibHintT = MP.Target(LocalPlayer(), math.max(MP.Cfg("batonRange"), MP.Cfg("searchRange")))
        end
        local who = self.rhylibHintT
        if not IsValid(who) then return end
        local s = ScrH() / 1080
        draw.SimpleText(who:Nick() .. "   ·   " .. self.Hint, Rhylib.UI.Font(14, 500), ScrW() * 0.5, ScrH() * 0.5 + 68 * s,
            Rhylib.UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end
