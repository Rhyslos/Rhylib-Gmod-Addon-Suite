--[[
    Field command post (rhylib_logistics): the big outdoor command post
    (about the size of a small tank) for open maps; the computer one
    (entities/rhylib_command_post.lua) stays for indoor maps. Works the
    same: E opens the command post window, make it permanent to keep it.
    Model: logistics postFieldModel.
]]

AddCSLuaFile()

ENT.Base = "rhylib_command_post"
ENT.PrintName = "Command post (field)"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelKey = "postFieldModel"
