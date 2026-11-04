--[[
    Repair tool (rhylib_logistics): a hydro-spanner for field structures.
    Anyone can take one from the gear cabinet (sv_30_build.lua). Works like
    the E-tool (weapons/rhylib_etool.lua: build menu, place, build, turn,
    remove) but builds at logistics repairBuildSpeed of its speed, and LMB
    held on a damaged built structure repairs it (repairRate health a second).
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
SWEP.HoldType = "melee"
SWEP.CanRepair = true

SWEP.InvGroup = "gear"
SWEP.InvW = 1
SWEP.InvH = 2
SWEP.InvWeight = 1

SWEP.VMOffset = Vector(3, 1.5, -2)
SWEP.VMAngle = Angle(0, 0, 180)
SWEP.WMOffset = Vector(4, 1.5, -2)
SWEP.WMAngle = Angle(0, 0, 180)
