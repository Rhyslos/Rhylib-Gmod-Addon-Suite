--[[
    Bounty Puck (rhylib_bounty). A tracker for your contract's target:
      LMB   switch it on / off (it keeps beeping from your inventory)
      R     track the next contract you carry
    The beeping (from the server, everyone near hears it) gets faster and
    higher as you close in; there's no direction. See sv_20_puck.lua.
    An inventory item (1x1); sold at the Bounty Office.
]]

AddCSLuaFile()

SWEP.PrintName = "Bounty Puck"
SWEP.Category = "Rhy's Bounty hunters"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.HoldType = "normal"
SWEP.Instructions = "LMB: on / off   R: next contract"
SWEP.BountyPuck = true

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvWeight = 0.3
SWEP.InvCategory = "gear"

function SWEP:Initialize() self:SetHoldType(self.HoldType) end

local function send(op)
    Rhylib.Net.Start("bounty.puck")
    net.WriteUInt(op, 2)
    net.SendToServer()
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    if CLIENT and IsFirstTimePredicted() then send(0) end
end

function SWEP:SecondaryAttack() end

function SWEP:Reload()
    if not CLIENT or not IsFirstTimePredicted() then return end
    if (self.nextR or 0) > RealTime() then return end
    self.nextR = RealTime() + 0.4
    send(1)
end

if CLIENT then
    -- A small device in the corner: on/off light and who it tracks (the
    -- name only; the server never says where).
    function SWEP:DrawHUD()
        local me = LocalPlayer()
        local on = me:GetNW2Bool("rhylib_puckOn", false)
        local B = Rhylib.Bounty
        local name = "your first contract"
        local bid = me:GetNW2Int("rhylib_puckBid", 0)
        for _, b in ipairs(B and B.board or {}) do if b.id == bid then name = b.name end end
        local s = ScrH() / 1080
        local w, h = 300 * s, 92 * s
        local x, y = ScrW() - w - 40 * s, ScrH() - h - 220 * s
        draw.RoundedBox(8 * s, x, y, w, h, Color(20, 22, 24, 230))
        local pulse = on and (0.5 + 0.5 * math.sin(RealTime() * 4)) or 0
        draw.RoundedBox(6 * s, x + 14 * s, y + 14 * s, 18 * s, 18 * s, on and Color(220, 70 + 80 * pulse, 60, 255) or Color(70, 70, 70, 255))
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(16, 700) or "DermaDefaultBold"
        local small = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 500) or "DermaDefault"
        draw.SimpleText("BOUNTY PUCK  ·  " .. (on and "ON" or "OFF"), font, x + 42 * s, y + 23 * s, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Tracking: " .. name, small, x + 14 * s, y + 52 * s, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("LMB on / off   ·   R next contract", small, x + 14 * s, y + 72 * s, Color(150, 150, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end
