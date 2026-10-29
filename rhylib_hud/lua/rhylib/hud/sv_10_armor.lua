--[[
    Armour for other players (server).

    Armour isn't sent to other players by the engine, so the player info
    box couldn't show it. We copy each player's armour into the NW2Int
    "rhylib_armor", only when it has changed (the engine then sends it
    once): right after damage (PostEntityTakeDamage, after rhylib_weapons'
    armour maths put the value back), a moment after spawning, and in a
    slow safety pass every 0.5 s for anything else that sets armour (kits,
    admin commands). Read on clients by cl_50_players.lua.

    Also turns off the default voice icon above heads (we draw our own in
    cl_50_players.lua): mp_show_voice_icons 0, at file load and again at
    Initialize in case the convar didn't exist yet.
]]

local last = {}   -- [ply] = armour value last written to NW2

local function mirror(ply)
    if not IsValid(ply) then return end
    local a = ply:Armor()
    if last[ply] ~= a then
        last[ply] = a
        ply:SetNW2Int("rhylib_armor", a)
    end
end

-- (a tick later: nested hits and the armour restore have settled by then)
Rhylib.Hook.Add("PostEntityTakeDamage", "hud.armor", function(ent)
    if IsValid(ent) and ent:IsPlayer() then timer.Simple(0, function() mirror(ent) end) end
end, 1000)
Rhylib.Hook.Add("PlayerSpawn", "hud.armor", function(ply)
    timer.Simple(0.2, function() mirror(ply) end)   -- (spawn armour is set a tick after spawning)
end)
timer.Create("Rhylib.HUD.Armor", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do mirror(ply) end
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
