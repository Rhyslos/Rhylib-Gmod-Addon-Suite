--[[
    Armour for other players (server).

    Armour isn't sent to other players by the engine, so the player info
    box couldn't show it. Every quarter second we copy each player's
    armour into the NW2Int "rhylib_armor", but only when it has changed;
    the engine then sends it once. Cost: one loop over the players, four
    times a second. Read on clients by cl_50_players.lua.

    Also turns off the default voice icon above heads (we draw our own in
    cl_50_players.lua): mp_show_voice_icons 0, at file load and again at
    Initialize in case the convar didn't exist yet.
]]

local last = {}   -- [ply] = armour value last written to NW2

timer.Create("Rhylib.HUD.Armor", 0.25, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local a = ply:Armor()
        if last[ply] ~= a then
            last[ply] = a
            ply:SetNW2Int("rhylib_armor", a)
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "hud.armor", function(ply)
    last[ply] = nil
end)

Rhylib.Hook.Add("Initialize", "hud.voiceicons", function()
    if ConVarExists("mp_show_voice_icons") then
        RunConsoleCommand("mp_show_voice_icons", "0")
    end
end)
if ConVarExists("mp_show_voice_icons") then RunConsoleCommand("mp_show_voice_icons", "0") end
