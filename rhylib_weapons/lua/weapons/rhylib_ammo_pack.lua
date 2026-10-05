--[[
    Ammo pack (rhylib_skills: Autorifleman > Ammo pack; needs rhylib_inventory).

    A 2x2 item holding a pool of rounds (config skills ammoPackPool, 300;
    the item's fill). LMB: the teammate you look at, RMB: yourself. For the
    blaster in their hands (or their first Rhylib blaster) it
      1. tops up the loaded magazine,
      2. tops up every part-used magazine that gun takes,
      3. adds magazines of the gun's best type until they have 4 spares,
    taking rounds from the pool as it goes (large magazines cost 0.72 each:
    they already pack more rounds per cell). Rockets and power cells aren't
    covered. Magazines from an issued pack are issued too.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Ammo pack"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/items/boxmrounds.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 2
SWEP.InvH = 2
SWEP.InvWeight = 3
SWEP.InvCharge = true
SWEP.InvCategory = "ammo"

SWEP.RequiresSkill = "ammo_pack"
SWEP.CarrySkill = "ammo_pack"   -- (only Autoriflemen with the skill may even carry one)
SWEP.Range = 110
SWEP.Cooldown = 1.5
SWEP.Spares = 4

Rhylib.Config.Register("skills", "ammoPackPool", 300, "Ammo pack: rounds in a full pack")
Rhylib.Config.Register("skills", "ammoPackLargeCost", 0.72, "Ammo pack: pool cost of one large-magazine round")

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
        o:ChatPrint("Look at a teammate (right click: yourself)")
        return
    end
    self:Supply(t)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if CLIENT then return end
    self:Supply(self:GetOwner())
end

if SERVER then
    local function cfg(k) return Rhylib.Config.Get("skills", k) end

    -- The pack item to draw from: the most used one.
    local function packItem(Inv, ply, class)
        local pick
        for _, o in pairs(Inv.Get(ply).byUid) do
            if o.id == class then
                local f = o.data and o.data.fill or 1
                if not pick or f < (pick.data and pick.data.fill or 1) then pick = o end
            end
        end
        return pick
    end

    -- The gun to resupply: the one in their hands, else their first blaster.
    local function gunOf(ply)
        local w = ply:GetActiveWeapon()
        if IsValid(w) and w.IsRhylib and w.Mags then return w end
        for _, x in ipairs(ply:GetWeapons()) do
            if x.IsRhylib and x.Mags and not x.Explosive then return x end
        end
    end

    function SWEP:Supply(t)
        local o = self:GetOwner()
        if not IsValid(o) then return end
        self:SetNextPrimaryFire(CurTime() + self.Cooldown)
        self:SetNextSecondaryFire(CurTime() + self.Cooldown)
        if not self:SkillOK() then return o:ChatPrint("You need the Ammo pack skill to use this") end
        local Inv, W = Rhylib.Inventory, Rhylib.Weapons
        if not (Inv and Inv.Get and W) then return end
        if Inv.Locked and (Inv.Locked(t) or Inv.Locked(o)) then return o:ChatPrint("Can't resupply right now") end
        local pack = packItem(Inv, o, self:GetClass())
        if not pack then return end
        local gun = gunOf(t)
        if not gun then return o:ChatPrint((t == o and "You have" or t:Nick() .. " has") .. " no blaster to resupply") end

        local POOL = cfg("ammoPackPool")
        local pool = (pack.data and pack.data.fill or 1) * POOL
        local spent = 0
        local function cost(id) return W.BaseMag(id) == "mag_large" and cfg("ammoPackLargeCost") or 1 end
        local function left(id) return math.floor((pool - spent) / cost(id)) end
        local takes = {}
        for _, id in ipairs(gun.Mags) do
            if W.BaseMag(id) ~= "rocket" and W.MagTypes[id] then takes[id] = true end
        end

        -- 1. The loaded magazine.
        local m = gun:GetMag()
        if m and takes[m.id] then
            local give = math.min(gun:GetMagSize() - gun:Clip1(), left(m.id))
            if give > 0 then
                gun:SetClip1(gun:Clip1() + give)
                spent = spent + give * cost(m.id)
            end
        end

        -- 2. Part-used magazines it takes.
        local st = Inv.Get(t)
        for _, inst in pairs(st.byUid) do
            if takes[inst.id] and inst.c ~= Rhylib.Items.EXT then
                local rounds = W.MagTypes[inst.id].rounds
                local fill = inst.data and inst.data.fill or 1
                if fill < 1 then
                    local give = math.min(math.ceil((1 - fill) * rounds), left(inst.id))
                    if give > 0 then
                        inst.data = inst.data or {}
                        inst.data.fill = math.min(1, fill + give / rounds)
                        if inst.data.fill >= 0.999 then inst.data.fill = nil end
                        Inv.Internal.update(t, st, inst)
                        spent = spent + give * cost(inst.id)
                    end
                end
            end
        end

        -- 3. New magazines of the best type, up to Spares.
        local best = gun.FirstMagFor and gun:FirstMagFor(t) or gun.Mags[1]
        if best and takes[best] then
            local rounds = W.MagTypes[best].rounds
            local have = Inv.Count(t, best)
            local issued = pack.data and pack.data.issued or nil
            while have < self.Spares do
                local give = math.min(rounds, left(best))
                if give < rounds * 0.25 or not Inv.CanAdd(t, best) then break end
                local data = { issued = issued }
                if give < rounds then data.fill = give / rounds end
                if Inv.AddItem(t, best, 1, data) > 0 then break end   -- (no room after all)
                spent = spent + give * cost(best)
                have = have + 1
            end
        end

        if spent < 0.5 then
            return o:ChatPrint((t == o and "You're" or t:Nick() .. " is") .. " full (or the pack is empty)")
        end
        local rest = pool - spent
        if rest < 1 then
            Inv.Remove(o, pack.uid)
        else
            pack.data = pack.data or {}
            pack.data.fill = rest / POOL
            Inv.Internal.update(o, Inv.Get(o), pack)
        end
        o:EmitSound("items/ammo_pickup.wav", 65)
        if t ~= o then
            t:EmitSound("items/ammo_pickup.wav", 60)
            t:ChatPrint(o:Nick() .. " resupplied you")
        end
        o:ChatPrint(string.format("Gave %d rounds · %d left in the pack", math.floor(spent + 0.5), math.floor(rest)))
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local text = self:SkillOK() and "LMB: resupply teammate  ·  RMB: yourself" or "Needs the Ammo pack skill"
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        draw.SimpleTextOutlined(text, font, ScrW() * 0.5, ScrH() * 0.55, Color(225, 225, 225, 220),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
    end
end

-- Interaction wheel (rhylib_menus): resupply the player you hold E on.
if SERVER then
    Rhylib.Net.Receive("wheel.supply", function(ply)
        local t = net.ReadEntity()
        local wep = ply:GetWeapon("rhylib_ammo_pack")
        if not (IsValid(wep) and IsValid(t) and t:IsPlayer() and t:Alive() and ply:Alive()) or ply.rhylibDown then return end
        if util.TraceLine({ start = ply:EyePos(), endpos = t:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then return end
        if CurTime() < wep:GetNextPrimaryFire() then return end
        local r = wep.Range + 40
        if ply:GetPos():DistToSqr(t:GetPos()) > r * r then return end
        wep:Supply(t)
    end, { rate = 2, burst = 2 })
end

if CLIENT then
    Rhylib.Hook.Add("Rhylib.WheelOptions", "weapons.ammopack", function(t, me, add)
        local wep = me:GetWeapon("rhylib_ammo_pack")
        if not IsValid(wep) then return end
        if not wep:SkillOK() then
            add("Resupply", nil, { order = 35, disabled = "Needs the Ammo pack skill" })
            return
        end
        add("Resupply", function(x)
            Rhylib.Net.Start("wheel.supply")
            net.WriteEntity(x)
            net.SendToServer()
        end, { order = 35, sub = "Ammo pack: top up their mags" })
    end)
end
