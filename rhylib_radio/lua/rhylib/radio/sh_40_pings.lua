--[[
    Squad pings (2026-10-07, owner): hold the ping key (rhylib_radio_pingkey,
    default O) for a wheel of ping types; release on one to mark where you
    aim (or yourself, for the "on me" kinds) for your radio squad.

    Client cl_40_pings.lua: wheel (rhylib_menus Menus.Wheel.OpenList), the
    markers on screen and on the compass, a chat line and a blip.
    Server sv_30_pings.lua: net radio.ping (kind 4 bits) → checks (alive,
    in a squad, not jammed, cooldown), traces the aim, sends radio.ping
    (sender, kind, pos, tracked entity) to the squad (not to jammed mates).
]]

local R = Rhylib.Radio
local Config = Rhylib.Config

Config.Register("radio", "pingRange", 12000, "Squad pings: how far you can ping (units)")
Config.Register("radio", "pingCooldown", 0.6, "Squad pings: seconds between two pings from one player")

-- id, wheel label, marker text, icon (R.ICONS), colour, seconds shown,
-- self = on the pinger (follows them), track = sticks to an NPC aimed at,
-- chat = what the chat line says.
R.PINGS = {
    { id = "move", label = "Move here", short = "MOVE", icon = "ping_move", col = Color(90, 170, 255), life = 20, chat = "move here" },
    { id = "enemy", label = "Enemy", short = "ENEMY", icon = "crosshair", col = Color(235, 70, 60), life = 12, track = true, chat = "enemy spotted" },
    { id = "hold", label = "Hold here", short = "HOLD", icon = "ping_hold", col = Color(240, 180, 60), life = 30, chat = "hold here" },
    { id = "regroup", label = "Regroup on me", short = "REGROUP", icon = "leader", col = Color(232, 212, 90), life = 15, self = true, chat = "regroup on me" },
    { id = "defend", label = "Defend here", short = "DEFEND", icon = "shield", col = Color(70, 200, 190), life = 30, chat = "defend this position" },
    { id = "danger", label = "Danger", short = "DANGER", icon = "ping_danger", col = Color(255, 130, 40), life = 15, chat = "watch out there" },
    { id = "medic", label = "Need a medic", short = "MEDIC", icon = "cross", col = Color(110, 220, 120), life = 20, self = true, chat = "I need a medic" },
    { id = "ammo", label = "Need ammo", short = "AMMO", icon = "ammo", col = Color(205, 205, 215), life = 20, self = true, chat = "I need ammo" },
}
R.PING_BITS = 4
