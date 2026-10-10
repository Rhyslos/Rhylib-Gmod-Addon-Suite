--[[
    Republic mine (rhylib_skills: EOD > Republic mines; needs rhylib_republic
    for the grenade base). A stack of mines you plant: LMB / RMB on the
    ground you look at. Only droids set them off; every player sees them
    outlined in blue. Up to 3 out at a time (6 with Minefield); E on one of
    your own picks it back up. Rules: rhylib_eod sv_35_repmines.lua.
]]

AddCSLuaFile()

DEFINE_BASECLASS("rhylib_grenade_base")

SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Republic mine"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"
SWEP.Spawnable = true
SWEP.ImpactMode = false
SWEP.ThrowDelay = 0.8

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvStack = 3
SWEP.InvWeight = 1.2

SWEP.RequiresSkill = "eod_mines"
SWEP.CarrySkill = "eod_mines"
SWEP.SkillName = "Republic mines"

SWEP.WorldModel = "models/props/starwars/weapons/ap_mine.mdl"
SWEP.PropModel = "models/props/starwars/weapons/ap_mine.mdl"
SWEP.PropColor = Color(170, 205, 255)
SWEP.PropScale = 0.5
SWEP.PropVMScale = 0.5

SWEP.Reach = 110            -- (units to the ground you plant on)

function SWEP:PrimaryAttack() self:PlaceMine() end
function SWEP:SecondaryAttack() self:PlaceMine() end

-- SWEP:PlaceMine(): LMB and RMB. Checks the skill and the ground (a
-- walkable brush within Reach), asks E.RepCanPlace, then on the server
-- plants with E.RepPlace and uses one from the stack (UseOne, grenade base).
function SWEP:PlaceMine()
    local o = self:GetOwner()
    if not IsValid(o) or not o:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if not self:SkillOK() then
        if SERVER then o:ChatPrint("You need the Republic mines skill to plant this") end
        return
    end
    local tr = util.TraceLine({
        start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * self.Reach,
        filter = o, mask = MASK_SOLID_BRUSHONLY,
    })
    if not tr.Hit or tr.HitSky or tr.HitNormal.z < 0.7 then
        if SERVER then o:ChatPrint("Look at the ground close by to plant the mine") end
        return
    end
    local E = Rhylib.EOD
    if SERVER and E and E.RepCanPlace then
        local ok, why = E.RepCanPlace(o, tr.HitPos)
        if not ok then o:ChatPrint(why) return end
    end
    self:SetNextPrimaryFire(CurTime() + self.ThrowDelay)
    self:SetNextSecondaryFire(CurTime() + self.ThrowDelay)
    self:SetLastThrow(CurTime())
    self:SetNeedDraw(true)
    self:SendWeaponAnim(ACT_VM_THROW)
    o:SetAnimation(PLAYER_ATTACK1)
    if CLIENT then return end
    -- (the stack it comes from: an issued mine stays issued)
    local issued
    local Inv = Rhylib.Inventory
    if Inv and Inv.Get then
        for _, inst in pairs(Inv.Get(o).byUid) do
            if inst.id == self:GetClass() then issued = inst.data and inst.data.issued break end
        end
    end
    if not (E and E.RepPlace and E.RepPlace(o, tr, issued)) then return end
    self:UseOne(o)
end

if CLIENT then
    function SWEP:DrawHUD()
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        local text
        if not self:SkillOK() then
            text = "Needs the Republic mines skill"
        else
            local E = Rhylib.EOD
            local n, max = 0, 3
            if E and E.RepCountClient then n, max = E.RepCountClient() end
            text = string.format("REPUBLIC MINE  ·  CLICK THE GROUND  ·  %d / %d OUT  ·  E ON YOURS: PICK UP", n, max)
        end
        draw.SimpleTextOutlined(text, font, ScrW() * 0.5, ScrH() * 0.55, Color(170, 205, 255, 230),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
    end
end
