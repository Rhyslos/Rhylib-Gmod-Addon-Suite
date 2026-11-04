--[[
    Repair tool (rhylib_logistics): a hydro-spanner for field structures.
    Anyone can take one from the gear cabinet (sv_30_build.lua). It can't
    place structures (no build menu, ghost or RMB): LMB held on a hologram
    someone placed helps build it (logistics repairBuildSpeed of the
    E-tool's speed), LMB held on a damaged built structure repairs it
    (repairRate health a second). Z removes your own, like the E-tool.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_etool"
SWEP.PrintName = "Repair tool"
SWEP.Category = "Rhy's Logistics"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.SlotPos = 5
SWEP.WorldModel = "models/niksacokica/misc/misc_tool_clippers.mdl"
SWEP.ToolModel = "models/niksacokica/misc/misc_tool_clippers.mdl"
SWEP.CanRepair = true
SWEP.CanPlace = false
SWEP.HoldType = "slam"         -- (if the datapad SWEP isn't there)
SWEP.HoldLikeDatapad = true    -- (held like the datapad in third person)

SWEP.InvGroup = "gear"
SWEP.InvW = 1
SWEP.InvH = 2
SWEP.InvWeight = 1

SWEP.VMScale = 0.7
SWEP.WMScale = 0.6
SWEP.VMOffset = Vector(3.6, -0.7, 0.2)
SWEP.VMAngle = Angle(45, 2, -90)
SWEP.WMOffset = Vector(3.4, -2.9, 0.1)
SWEP.WMAngle = Angle(44, 1, -79)
