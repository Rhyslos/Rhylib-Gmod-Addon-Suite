--[[
    Personal grappling hook: fires a short hook (15 m) where you look and
    reels only you up to it (rhylib/weapons/sh_32_phook.lua has the rules
    and the movement). Reusable; from the ammo cabinet (rhylib_armoury
    AMMO_STOCK), anyone may carry one.

    LMB (from the ground): fire. While hooked: W climbs over a ledge, Jump
    / E / S let go. Switching weapons lets go.

    Realm: shared SWEP (predicted). Placeholder models (the HL2 pistol).
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Personal grappling hook"
SWEP.Category = "Rhy's Equipment"
SWEP.Spawnable = true
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_pistol.mdl"   -- placeholder
SWEP.WorldModel = "models/weapons/w_pistol.mdl"  -- placeholder
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 2
SWEP.InvH = 1
SWEP.InvWeight = 1.5
SWEP.InvCategory = "gear"
SWEP.InvHolster = false   -- (not a pistol)

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end
function SWEP:SecondaryAttack() end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + 0.5)
    local G = Rhylib.Weapons.Grapple
    if not (G and G.PhookStart) then return end
    local ok, why = G.PhookStart(owner)
    if ok then
        if IsFirstTimePredicted() then
            self:EmitSound("weapons/crossbow/fire1.wav", 65, 125)
            owner:SetAnimation(PLAYER_ATTACK1)
        end
    elseif SERVER and why then
        Rhylib.Notify(owner, why, "bad", "Grapple")
    end
end

-- (Switching away or losing it lets go: the movement code sees the hook
-- is no longer in your hands, on both realms, and drops you.)

if CLIENT then
    -- Where it would take you (green) or why not (red), under the crosshair.
    local COL_OK, COL_BAD = Color(120, 220, 140), Color(235, 90, 80)
    function SWEP:DrawHUD()
        local owner = self:GetOwner()
        local G = Rhylib.Weapons.Grapple
        if not (IsValid(owner) and G and G.PhookAim) or G.PhookOn(owner) ~= 0 then return end
        -- (worked out 10 times a second, not every frame: it's a few traces)
        local now = RealTime()
        if not self.aimAt or now >= self.aimAt then
            self.aimAt = now + 0.1
            local at, _, ledge, why = G.PhookAim(owner)
            self.aimRes = { at ~= nil, ledge ~= nil, why }
        end
        local res = self.aimRes
        local at, ledge, why = res[1], res[2], res[3]
        local UI = Rhylib.UI
        local font = UI and UI.Font and UI.Font(14) or "DermaDefault"
        local x, y = ScrW() * 0.5, ScrH() * 0.5 + 26
        if at then
            draw.SimpleText(ledge and "Hook: up and over" or "Hook: hang", font, x, y, COL_OK, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(why or "", font, x, y, COL_BAD, TEXT_ALIGN_CENTER)
        end
    end
end
