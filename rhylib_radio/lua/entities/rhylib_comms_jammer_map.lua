--[[
    Comms jammer (whole map) (rhylib_radio, 2026-10-07, owner): the comms jammer
    (rhylib_comms_jammer.lua) with radio jammerModelMap / jammerChargesMap: it jams everyone on the map.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_comms_jammer"
ENT.PrintName = "Comms jammer (whole map)"
ENT.Category = "Rhylib: Military police"
ENT.Spawnable = true
ENT.AdminOnly = true
