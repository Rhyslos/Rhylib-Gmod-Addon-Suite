--[[
    Base for armoury entities: a frozen prop you press E on. What it holds
    is set up by rhylib/armoury/sv_10_armoury.lua from ENT.ArmouryKind.
    Placed by admins from the spawn menu; the toolgun's Permanent tool (or
    rhylib_armoury_save) keeps them.

    Shared (AddCSLuaFile). Server: model, frozen physics, E -> A.Use.
    Client: the name plate above it (within 250 units).
    Make your own kind: a small entity file with ENT.Base =
    "rhylib_armoury_base" and the fields below (copy rhylib_crate_small.lua),
    and add its class to Rhylib.Armoury.CLASSES so it can be saved.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Armoury base"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = false
ENT.AdminOnly = true

ENT.ArmouryKind = nil   -- what A.Setup builds: "armoury", "ammo", "crate", "locker", "spec",
                        -- "gear", "trainingArmoury", "trainingAmmo" or "trainingDeposit"
ENT.ModelKey = "crate"  -- key in Rhylib.Armoury.MODELS
ENT.Hint = "Press E"     -- second line of the name plate
-- Optional: ENT.Tint (Color), ENT.CrateMag (item id) / ENT.CrateStock (config
-- key) for crates, ENT.SpecKind ("weapons" / "gear") for specialist racks.

function ENT:SetupDataTables()
    -- Only lockers use these.
    self:NetworkVar("String", 0, "OwnerSid")
    self:NetworkVar("String", 1, "OwnerName")
    self:NetworkVar("Bool", 0, "Locked")
end

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(Rhylib.Armoury.MODELS[self.ModelKey])
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end  -- stays put; admins can still physgun it
    if self.Tint then self:SetColor(self.Tint) end   -- (training cabinets: yellowish)
end

if SERVER then
    function ENT:Use(ply)
        Rhylib.Armoury.Use(self, ply)
    end

    function ENT:OnRemove()
        if Rhylib.Armoury.SaveLocker and self.ArmouryKind == "locker" then Rhylib.Armoury.SaveLocker(self) end
        if Rhylib.Inventory and Rhylib.Inventory.RemoveStorage then Rhylib.Inventory.RemoveStorage(self) end
    end
end

if CLIENT then
    local COL_TITLE = Color(228, 227, 220)
    local COL_SUB = Color(169, 168, 160)
    local COL_BG = Color(20, 22, 20, 190)
    local RANGE = 250

    -- ENT:SubText() -> second line under the name (lockers override it to
    -- show who owns them). Client.
    function ENT:SubText()
        return self.Hint
    end

    function ENT:Draw()
        self:DrawModel()
        local ply = LocalPlayer()
        if ply:GetPos():DistToSqr(self:GetPos()) > RANGE * RANGE then return end

        local pos = self:LocalToWorld(Vector(0, 0, self:OBBMaxs().z + 10))
        local ang = Angle(0, ply:EyeAngles().y - 90, 90)
        local UI = Rhylib.UI
        cam.Start3D2D(pos, ang, 0.08)
            local title, sub = self.PrintName, self:SubText()
            surface.SetFont(UI.Font(30))
            local w = math.max(surface.GetTextSize(title), (surface.GetTextSize(sub))) + 40
            draw.RoundedBox(8, -w * 0.5, -34, w, 74, COL_BG)
            draw.SimpleText(title, UI.Font(30), 0, -16, COL_TITLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(sub, UI.Font(22), 0, 18, COL_SUB, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end
end
