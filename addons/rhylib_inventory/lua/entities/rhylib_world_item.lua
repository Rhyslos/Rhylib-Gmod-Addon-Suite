--[[
    An inventory item lying in the world (dropped by a player; shared).
    Press E to pick it up. Anything that doesn't fit stays on the ground.

    Made by Inv.SpawnWorldItem (sv_10_inventory): ents.Create, then
    ENT:SetItem(id, count, data) before Spawn. Removes itself after config
    inventory worldItemLife (600 s), or issuedDropLife (300 s) for issued
    gear, whichever is shorter. Network vars: ItemName, ItemCount (for the
    name shown up close). Model: the item's def.model, else a cardboard box.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item"
ENT.Spawnable = false

local FALLBACK_MODEL = "models/props_junk/cardboard_box004a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemName")
    self:NetworkVar("Int", 0, "ItemCount")
end

if SERVER then
    -- ENT:SetItem(id, count, data): what it holds. Call before Spawn().
    function ENT:SetItem(id, count, data)
        self.itemId = id
        self.itemCount = count or 1
        self.itemData = data and table.Copy(data) or {}
    end

    function ENT:Initialize()
        local def = Rhylib.Items.Get(self.itemId or "")
        local model = def and def.model
        if not model or not util.IsValidModel(model) then model = FALLBACK_MODEL end

        self:SetModel(model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)  -- players walk through it
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end

        self:SetItemName(def and def.name or "Unknown item")
        self:SetItemCount(self.itemCount or 1)

        -- Dropped items don't pile up forever; issued (armoury) gear goes sooner.
        local life = Rhylib.Config.Get("inventory", "worldItemLife") or 0
        if self.itemData and self.itemData.issued then
            local il = Rhylib.Config.Get("inventory", "issuedDropLife") or 300
            if il > 0 then life = life > 0 and math.min(life, il) or il end
        end
        if life > 0 then SafeRemoveEntityDelayed(self, life) end
    end

    function ENT:Use(ply)
        -- taken: Remove() only happens at the end of the frame, so a second
        -- player pressing E in the same tick must not get it too.
        if self.taken or not IsValid(ply) or not ply:IsPlayer() or not self.itemId then return end
        local left = Rhylib.Inventory.AddItem(ply, self.itemId, self.itemCount, self.itemData)
        if left <= 0 then
            self.taken = true
            ply:EmitSound("items/ammo_pickup.wav", 60)
            self:Remove()
        elseif left < self.itemCount then
            self.itemCount = left
            self:SetItemCount(left)
            ply:EmitSound("items/ammo_pickup.wav", 60)
        else
            local def = Rhylib.Items.Get(self.itemId)
            local Inv = Rhylib.Inventory
            local dupe = Inv.AtLimit(ply, self.itemId)
            local text = dupe and Inv.LimitText(ply, self.itemId) or "No room in your inventory"
            if Inv.MayHold and not Inv.MayHold(ply, self.itemId) then text = Inv.HoldReason(self.itemId) end
            ply:PrintMessage(HUD_PRINTCENTER, text)
        end
    end
end

if CLIENT then
    -- Show the name when looking at it up close. The cheap distance check
    -- runs first, so far-away items never touch the eye trace.
    function ENT:Draw()
        self:DrawModel()
        local ply = LocalPlayer()
        if ply:GetPos():DistToSqr(self:GetPos()) > 150 * 150 or ply:GetEyeTrace().Entity ~= self then return end

        local count = self:GetItemCount()
        local text = self:GetItemName() .. (count > 1 and (" x" .. count) or "")
        local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 6)
        local ang = Angle(0, ply:EyeAngles().y - 90, 90)
        cam.Start3D2D(pos, ang, 0.1)
            draw.SimpleTextOutlined(text, Rhylib.UI.Font(24), 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        cam.End3D2D()
    end
end
