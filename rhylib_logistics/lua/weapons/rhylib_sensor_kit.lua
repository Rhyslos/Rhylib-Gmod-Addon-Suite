--[[
    Sensor kit (rhylib_logistics): a sensor array beacon to set down. 4x1,
    stacks to 2 (rhylib_inventory). Hold it and LMB / RMB on the ground
    close by: a beacon (entities/rhylib_sensor_beacon.lua) stands there,
    powered with a power cell from your inventory if you carry one
    (L.PlaceBeacon, rhylib/logistics/sv_10_sensors.lua). Anyone can carry
    and place one; logistics sensorMax per player.
]]

AddCSLuaFile()

SWEP.PrintName = "Sensor kit"
SWEP.Category = "Rhy's Logistics"
SWEP.Author = "Rhy"
SWEP.Spawnable = true
SWEP.AdminOnly = true   -- (players get them from the gear cabinet)
SWEP.Slot = 4
SWEP.SlotPos = 3
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/props_lab/reciever01b.mdl"
SWEP.HoldType = "slam"

SWEP.InvGroup = "gear"   -- (Equipment shelf; the armoury's gear cabinet stocks it, sv_10_sensors.lua)
SWEP.InvW = 4
SWEP.InvH = 1
SWEP.InvStack = 2
SWEP.InvWeight = 2.5

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local REACH = 110

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Place()
    self:SetNextPrimaryFire(CurTime() + 0.8)
    self:SetNextSecondaryFire(CurTime() + 0.8)
    if CLIENT then return end
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer()) then return end
    local tr = util.TraceLine({ start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * REACH,
        filter = o, mask = MASK_SOLID_BRUSHONLY })
    if not tr.Hit or tr.HitSky or tr.HitNormal.z < 0.7 then
        Rhylib.Notify(o, "Look at the ground close by to set the beacon down", "bad", "Logistics")
        return
    end
    local L = Rhylib.Logistics
    if not (L and L.PlaceBeacon) then return end
    if not (IsValid(o) and o:Alive()) or (Rhylib.State and Rhylib.State.CanAct and not Rhylib.State.CanAct(o)) then return end
    local e = L.PlaceBeacon(o, tr)
    if not e then return end
    -- (one from the stack; the beacon remembers whether it was issued
    -- armoury kit, so picking it up gives the same kind back)
    local Inv = Rhylib.Inventory
    if Inv and Inv.Get and Inv.Remove then
        for _, inst in pairs(Inv.Get(o).byUid) do
            if inst.id == self:GetClass() then
                e.rhylibIssued = inst.data and inst.data.issued or nil
                Inv.Remove(o, inst.uid, 1)
                return
            end
        end
    end
    o:StripWeapon(self:GetClass())
end

function SWEP:PrimaryAttack() self:Place() end
function SWEP:SecondaryAttack() self:Place() end

if CLIENT then
    local COL = Color(120, 220, 160, 230)
    local SHADOW = Color(0, 0, 0, 160)
    function SWEP:DrawHUD()
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        draw.SimpleTextOutlined("SENSOR KIT  ·  CLICK THE GROUND TO SET A BEACON DOWN  ·  USES A POWER CELL",
            font, ScrW() * 0.5, ScrH() * 0.55, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    end
end
