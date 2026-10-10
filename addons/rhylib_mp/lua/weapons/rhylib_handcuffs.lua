--[[
    Handcuffs (military police).
      LMB     cuff a stunned or downed player (takes cuffTime; keep aiming)
      RMB     uncuff the cuffed player you look at
      Reload  escort the cuffed player you look at (again: let go)

    Shared SWEP. Cuffing is predicted: the progress is two DT vars
    (CuffTarget, CuffEnd) so the bar in DrawHUD matches the server;
    only the server actually cuffs (MP.Cuff), and only if the owner is
    an MP. Letting go of LMB or aiming away resets it.
    Also an inventory item (InvW/InvH/InvWeight/InvCategory, rhylib_inventory).
]]


AddCSLuaFile()

SWEP.PrintName = "Handcuffs"
SWEP.Category = "Rhylib: Military police"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 0
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.HoldType = "normal"
SWEP.Instructions = "LMB: cuff   RMB: uncuff   R: escort"

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvWeight = 0.4
SWEP.InvCategory = "gear"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:SetupDataTables()
    self:NetworkVar("Entity", 0, "CuffTarget")
    self:NetworkVar("Float", 0, "CuffEnd")
end

local function canBeCuffed(MP, t)
    if not IsValid(t) or MP.IsCuffed(t) then return false end
    return MP.IsStunned(t) or (t.rhylibDown or (Rhylib.Medical and Rhylib.Medical.IsDown and Rhylib.Medical.IsDown(t))) and true or false
end

-- Hold LMB on a stunned or downed player.
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.1)
    local MP = Rhylib.MP
    local owner = self:GetOwner()
    if not MP or not IsValid(owner) then return end
    local t = MP.Target(owner, MP.Cfg("cuffRange"))
    if not canBeCuffed(MP, t) then
        self:SetCuffTarget(NULL)
        return
    end
    if self:GetCuffTarget() ~= t then
        self:SetCuffTarget(t)
        self:SetCuffEnd(CurTime() + MP.Cfg("cuffTime"))
        return
    end
    if CurTime() >= self:GetCuffEnd() then
        self:SetCuffTarget(NULL)
        if SERVER and MP.IsMP(owner) then MP.Cuff(t, owner) end
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if IsValid(self:GetCuffTarget()) and IsValid(owner) and not owner:KeyDown(IN_ATTACK) then
        self:SetCuffTarget(NULL)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.8)
    if not SERVER then return end
    local MP = Rhylib.MP
    local owner = self:GetOwner()
    local t = MP and MP.Target(owner, MP.Cfg("cuffRange"))
    if t and MP.IsCuffed(t) and MP.IsMP(owner) then MP.Uncuff(t, owner) end
end

function SWEP:Reload()
    local owner = self:GetOwner()
    if not SERVER or not IsValid(owner) or not owner:KeyPressed(IN_RELOAD) then return end
    if (self.nextEscort or 0) > CurTime() then return end
    self.nextEscort = CurTime() + 0.4
    local MP = Rhylib.MP
    if not MP or not MP.IsMP(owner) then return end
    -- Already escorting someone: let go.
    for p in pairs(MP.cuffed) do
        if IsValid(p) and MP.EscortedBy(p) == owner then
            MP.SetEscort(p, nil)
            return
        end
    end
    local t = MP.Target(owner, MP.Cfg("cuffRange"))
    if t and MP.IsCuffed(t) then MP.SetEscort(t, owner) end
end

if CLIENT then
    function SWEP:DrawHUD()
        local t = self:GetCuffTarget()
        if not IsValid(t) then return end
        local MP = Rhylib.MP
        local f = 1 - math.Clamp((self:GetCuffEnd() - CurTime()) / MP.Cfg("cuffTime"), 0, 1)
        local w, h = ScrW() * 0.16, 6
        local x, y = (ScrW() - w) * 0.5, ScrH() * 0.56
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(x - 1, y - 1, w + 2, h + 2)
        surface.SetDrawColor(133, 183, 235)
        surface.DrawRect(x, y, w * f, h)
        draw.SimpleText("CUFFING " .. string.upper(t:Nick()), Rhylib.UI.Font(13, 700), ScrW() * 0.5, y - 12, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
