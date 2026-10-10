--[[
    Rhylib HUD (shared): replaces the default health, armour, ammo and
    weapon selection HUD, and adds player info and voice/typing icons,
    the clone helmet visor, damage feedback and a low ammo warning.

    Everything is drawn in HUDPaint (or a world render hook for the
    head icons) with plain surface calls. No panels, no per-frame
    networking. Server work: sending armour values (sv_10_armor.lua),
    because the engine doesn't send other players' armour to clients,
    the server's default layout (sv_20_layout.lua) and hit reports for
    damage feedback (sv_30_damage.lua).

    This file: the module table Rhylib.HUD, the two config settings,
    the list of first-person layouts and the layout lookups
    (HUD.ServerLayout, HUD.VisorLayout).
]]

Rhylib.HUD = Rhylib.HUD or {}

local Config = Rhylib.Config
Config.Register("hud", "targetRange", 700, "How close you must be to see a player's name and health when looking at them")
Config.Register("hud", "iconRange", 1500, "How far away speaking and typing icons are drawn")

-- First-person HUD layouts. Each player picks one in the pause menu's
-- settings (client convar rhylib_hud_firstperson); empty means the server
-- default, which an admin sets with rhylib_hud_layout <name> (sent as the
-- global "rhylib_hud_layout"). "thirdperson" keeps the third-person HUD
-- in first person: no helmet visor.
Rhylib.HUD.Layouts = {
    f5 = "Curve tiles over a wide ammo plate",
    f4 = "Ammo strip on an even hotbar row",
    thirdperson = "The third-person HUD (no helmet visor)",
}
Rhylib.HUD.LAYOUT_ORDER = { "f5", "f4", "thirdperson" }
Rhylib.HUD.DEFAULT_LAYOUT = "f5"

local choiceVar = CLIENT and CreateClientConVar("rhylib_hud_firstperson", "", true, false,
    "First-person HUD: f5, f4 or thirdperson (empty = the server's default)")

-- HUD.ServerLayout(): the server's default layout name ("f5", "f4" or
-- "thirdperson"), from the Global2String an admin sets with
-- rhylib_hud_layout. Unknown names fall back to HUD.DEFAULT_LAYOUT. Shared.
function Rhylib.HUD.ServerLayout()
    local name = GetGlobal2String("rhylib_hud_layout", Rhylib.HUD.DEFAULT_LAYOUT)
    if not Rhylib.HUD.Layouts[name] then name = Rhylib.HUD.DEFAULT_LAYOUT end
    return name
end

-- HUD.VisorLayout(): the layout in use: the player's own choice
-- (client convar rhylib_hud_firstperson), else the server default.
-- On the server there is no convar, so it is the server default.
-- Example: if Rhylib.HUD.VisorLayout() == "thirdperson" then ... end
function Rhylib.HUD.VisorLayout()
    if choiceVar then
        local own = choiceVar:GetString()
        if Rhylib.HUD.Layouts[own] then return own end
    end
    return Rhylib.HUD.ServerLayout()
end
