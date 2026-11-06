--[[
    Supply depot (rhylib_logistics; staff place it with the toolgun, Base
    > Supply depot, in three sizes; named with the toolgun's Beacon name
    box). A green ring on the ground round a marker (depotModel): supply
    crates and fuel canisters set down inside it (not carried, within
    about 2 m up or down) count as its stock. RP only: nothing draws from
    it. A destroyed crate or canister simply stops counting.

    The server counts every second (sv_70_depots.lua) into DT Int Crates,
    Supplies, Fuel; DT String BeaconName (the toolgun names it), Float
    Radius (the toolgun's size, else depotRadius). Everyone sees the ring
    and its label ("SUPPLY DEPOT", "4 crates · 400 supplies · 6 fuel
    canisters") within depotLabelRange; the command post lists it.
    Permanent with the Permanent tool (sv_70_depots.lua placements).
    Players walk through the marker.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Supply depot"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/props_c17/signpole001.mdl"
local COL = Color(110, 190, 120)

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "BeaconName")
    self:NetworkVar("Float", 0, "Radius")
    self:NetworkVar("Int", 0, "Crates")
    self:NetworkVar("Int", 1, "Supplies")
    self:NetworkVar("Int", 2, "Fuel")
end

function ENT:Initialize()
    local L = Rhylib.Logistics
    if L then
        L.depots = L.depots or {}
        L.depots[self] = true
    end
    if CLIENT then return end
    local m = L and L.Cfg("depotModel") or FALLBACK
    if not (isstring(m) and (util.IsValidModel(m) or file.Exists(m, "GAME"))) then m = FALLBACK end
    self:SetModel(m)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    if self:GetRadius() <= 0 then self:SetRadius(self.ZoneRadius or (L and L.Cfg("depotRadius")) or 260) end
    if self:GetBeaconName() == "" or self:GetBeaconName() == "Beacon" then self:SetBeaconName("Supply depot") end
end

function ENT:OnRemove(fullUpdate)
    if fullUpdate then return end
    local L = Rhylib.Logistics
    if L and L.depots then L.depots[self] = nil end
end

if SERVER then return end

local SEG = 64
local WHITE, GREEN, DIM, SHADOW = Color(235, 238, 240), Color(170, 225, 170), Color(170, 180, 186), Color(0, 0, 0, 200)
local RING = Color(COL.r, COL.g, COL.b, 190)

function ENT:Draw() self:DrawModel() end

-- ENT:StockLine() -> "4 crates · 400 supplies · 6 fuel canisters" / "Empty".
function ENT:StockLine()
    local parts = {}
    local c, s, f = self:GetCrates(), self:GetSupplies(), self:GetFuel()
    if c > 0 then parts[#parts + 1] = c .. (c == 1 and " crate · " or " crates · ") .. s .. " supplies" end
    if f > 0 then parts[#parts + 1] = f .. (f == 1 and " fuel canister" or " fuel canisters") end
    return #parts > 0 and table.concat(parts, " · ") or "Empty"
end

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local L = Rhylib.Logistics
    local range = L and L.Cfg and L.Cfg("depotLabelRange") or 790
    local pos = self:GetPos()
    local r = self:GetRadius()
    -- (the ring is far wider than the marker: bounds from its radius)
    if self.rhylibBoundsR ~= r then
        self.rhylibBoundsR = r
        self:SetRenderBounds(Vector(-r - 20, -r - 20, -20), Vector(r + 20, r + 20, 120))
    end
    local d2 = me:GetPos():DistToSqr(pos)
    if d2 > (range + r) ^ 2 then return end
    render.SetColorMaterial()
    local prev
    for i = 0, SEG do
        local a = i / SEG * math.pi * 2
        local p = pos + Vector(math.cos(a) * r, math.sin(a) * r, 3)
        if prev then render.DrawBeam(prev, p, 3, 0, 1, RING) end
        prev = p
    end
    local ang = Angle(0, me:EyeAngles().y - 90, 90)
    local UI = Rhylib.UI
    local f = UI and UI.Font and UI.Font(30, 700) or "DermaLarge"
    local f2 = UI and UI.Font and UI.Font(20, 600) or "DermaDefaultBold"
    local line = self:StockLine()
    cam.Start3D2D(pos + Vector(0, 0, math.max(60, self:OBBMaxs().z + 12)), ang, 0.1)
        draw.SimpleTextOutlined(string.upper(self:GetBeaconName()), f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(line, f2, 0, 28, line == "Empty" and DIM or GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
