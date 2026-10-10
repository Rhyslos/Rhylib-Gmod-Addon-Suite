--[[
    Rhylib menus: the pause menu (Esc; Shift + Esc opens Garry's Mod's own
    menu), with settings and an admin command page, the scoreboard, the
    killfeed, and a DarkRP F4 menu. Everything is client side; the admin
    commands are the admin mod's own (rhylib_admin, ULX or SAM) and
    Rhylib's console commands, which check permissions on the server
    themselves.

    This file is shared (sh_): it makes the Rhylib.Menus table and
    registers the "menus" config keys on both sides, so the server knows
    them for the Server settings page. Every other file is client only.

    Other addons can add to the menus:
        Rhylib.Menus.AddPage(id, page)                 (cl_10_pause.lua)
        Rhylib.Menus.AddSetting(section, setting)      (cl_20_settings.lua)
        Rhylib.Menus.AddControl(section, keys, text)   (cl_25_controls.lua)
        Rhylib.Menus.AddCommand(group, command)        (cl_30_commands.lua)
        hook Rhylib.WheelOptions                       (cl_70_wheel.lua)
        Rhylib.Menus.Spawn.AddTab(id, tab)             (cl_85_spawn.lua)
    and build windows with the UI kit, Rhylib.Menus.Kit (cl_00_kit.lua).
]]

Rhylib.Menus = Rhylib.Menus or {}

local Config = Rhylib.Config
Config.Register("menus", "title", "", "Title on the pause menu and scoreboard (empty = the server name)")
Config.Register("menus", "killfeedTime", 6, "Seconds a killfeed line stays")
Config.Register("menus", "killfeedMax", 6, "Most killfeed lines at once")
