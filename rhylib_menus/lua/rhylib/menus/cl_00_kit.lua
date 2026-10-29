--[[
    The UI kit moved to rhylib_core (cl_12_kit.lua, Rhylib.UI.Kit), so other
    addons' windows work without rhylib_menus. This file keeps the old names
    pointing at it: Rhylib.Menus.Kit, Menus.prompts, Menus.closers,
    Menus.RegisterCloser, Menus.CloseAll (the same tables and functions).
    Client only; loads first in rhylib_menus.
]]

local UI = Rhylib.UI
local Menus = Rhylib.Menus
Menus.Kit = UI.Kit
Menus.prompts = UI.prompts
Menus.closers = UI.closers
Menus.RegisterCloser = UI.RegisterCloser
Menus.CloseAll = UI.CloseAll
