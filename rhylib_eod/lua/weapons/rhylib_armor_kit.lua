--[[
    Armour repair kit (rhylib_skills: EOD > Armour repair; needs rhylib_inventory).

    A 2x2 item holding a charge of armour points (config eod armorKitPool,
    300; the item's fill). LMB: the clone you look at, RMB: yourself.
    Gives armour back up to their spawn armour (Rhylib.Armor.SpawnArmor),
    taking the points from the kit. Empty = gone.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Armour repair kit"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/items/battery.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 2
SWEP.InvH = 2
SWEP.InvWeight = 2.5
SWEP.InvCharge = true
SWEP.InvCategory = "gear"

SWEP.RequiresSkill = "eod_armor"
SWEP.CarrySkill = "eod_armor"
SWEP.Range = 110
SWEP.Cooldown = 1.5

Rhylib.Config.Register("eod", "armorKitPool", 300, "Armour repair kit: armour points in a full kit")
Rhylib.Config.Register("eod", "armorKitStep", 50, "Armour repair kit: most armour one use gives (0 = all the way up)")

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end

function SWEP:SkillOK()
    local K = Rhylib.Skills
    if not (K and K.Has) then return true end
    return K.Has(self:GetOwner(), self.RequiresSkill)
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    if CLIENT then return end
    local o = self:GetOwner()
    if not IsValid(o) then return end
    local tr = util.TraceLine({ start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * self.Range, filter = o, mask = MASK_SHOT })
    local t = tr.Entity
    local L = Rhylib.Lying
    if L and L.Owner and L.Owner(t) then t = L.Owner(t) end
    if not (IsValid(t) and t:IsPlayer() and t:Alive()) then
        o:ChatPrint("Look at a clone (right click: yourself)")
        return
    end
    self:Repair(t)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if CLIENT then return end
    self:Repair(self:GetOwner())
end

if SERVER then
    local function cfg(k) return Rhylib.Config.Get("eod", k) end

    -- The kit item to draw from: the most used one.
    local function kitItem(Inv, ply, class)
        local pick
        for _, o in pairs(Inv.Get(ply).byUid) do
            if o.id == class then
                local f = o.data and o.data.fill or 1
                if not pick or f < (pick.data and pick.data.fill or 1) then pick = o end
            end
        end
        return pick
    end

    local function spawnArmor(t)
        local A = Rhylib.Armor
        if A and A.SpawnArmor then return A.SpawnArmor(t) end
        return 100
    end

    function SWEP:Repair(t)
        local o = self:GetOwner()
        if not IsValid(o) then return end
        self:SetNextPrimaryFire(CurTime() + self.Cooldown)
        self:SetNextSecondaryFire(CurTime() + self.Cooldown)
        if not self:SkillOK() then return o:ChatPrint("You need the Armour repair skill to use this") end
        local Inv = Rhylib.Inventory
        if not (Inv and Inv.Get) then return o:ChatPrint("The armour kit needs rhylib_inventory") end
        if Inv.Locked and (Inv.Locked(t) or Inv.Locked(o)) then return o:ChatPrint("Can't repair right now") end
        if t.rhylibDown then return o:ChatPrint("They need a medic first") end
        local kit = kitItem(Inv, o, self:GetClass())
        if not kit then return end

        local POOL = math.max(1, cfg("armorKitPool") or 300)
        local pool = (kit.data and kit.data.fill or 1) * POOL
        local cap = spawnArmor(t)
        local have = t:Armor()
        local want = cap - have
        local step = cfg("armorKitStep") or 50
        if step > 0 then want = math.min(want, step) end
        local give = math.floor(math.min(want, pool))
        if give < 1 then
            return o:ChatPrint(want < 1 and ((t == o and "Your" or t:Nick() .. "'s") .. " armour is full") or "The kit is empty")
        end
        t:SetArmor(have + give)

        local rest = pool - give
        if rest < 1 then
            Inv.Remove(o, kit.uid)
        else
            kit.data = kit.data or {}
            kit.data.fill = rest / POOL
            Inv.Internal.update(o, Inv.Get(o), kit)
        end
        o:EmitSound("items/battery_pickup.wav", 65)
        if t ~= o then
            t:EmitSound("items/battery_pickup.wav", 60)
            t:ChatPrint(o:Nick() .. " repaired your armour")
        end
        o:ChatPrint(string.format("Gave %d armour · %d left in the kit", give, math.floor(rest)))
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local text = self:SkillOK() and "LMB: repair a clone's armour  ·  RMB: yours" or "Needs the Armour repair skill"
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        draw.SimpleTextOutlined(text, font, ScrW() * 0.5, ScrH() * 0.55, Color(225, 225, 225, 220),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
    end
end

-- Interaction wheel (rhylib_menus): repair the player you hold E on.
if SERVER then
    Rhylib.Net.Receive("wheel.armor", function(ply)
        local t = net.ReadEntity()
        local wep = ply:GetWeapon("rhylib_armor_kit")
        if not (IsValid(wep) and IsValid(t) and t:IsPlayer() and t:Alive() and ply:Alive()) or ply.rhylibDown then return end
        if util.TraceLine({ start = ply:EyePos(), endpos = t:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then return end
        if CurTime() < wep:GetNextPrimaryFire() then return end
        local r = wep.Range + 40
        if ply:GetPos():DistToSqr(t:GetPos()) > r * r then return end
        wep:Repair(t)
    end, { rate = 2, burst = 2 })
end

if CLIENT then
    Rhylib.Hook.Add("Rhylib.WheelOptions", "eod.armorkit", function(t, me, add)
        local wep = me:GetWeapon("rhylib_armor_kit")
        if not IsValid(wep) then return end
        if not wep:SkillOK() then
            add("Repair armour", nil, { order = 36, disabled = "Needs the Armour repair skill" })
            return
        end
        add("Repair armour", function(x)
            Rhylib.Net.Start("wheel.armor")
            net.WriteEntity(x)
            net.SendToServer()
        end, { order = 36, sub = "Armour kit: up to their spawn armour" })
    end)
end
