--[[
    Event tools (shared): respawn tickets, medic zones, objective markers.
    Server side in sv_20_events.lua, HUD and menus in cl_20_events.lua.

    Respawn tickets (staff switch them on for an event: !tickets):
      one shared pool for everyone. Each respawn after a death spends one
      (going down and being revived costs nothing). At 0, whoever dies
      stays dead until staff add tickets or switch them off. Global2Bool
      rhylib_tickets_on, Global2Int rhylib_tickets.
    Medic zones (rhylib_medic_zone, toolgun Spawns): a green ring of
      config medicZoneRadius. A downed player brought into one gets up at
      full health with no injuries or illness (rhylib_medical) and the
      pool gains a ticket (while tickets are on); anyone standing in it
      heals medicZoneRegen health a second.
    Objective markers (rhylib_objective, toolgun Spawns): a named marker
      that shows on the HUD with its distance in metres, from anywhere.
      Staff press E on it: rename, who sees it (everyone or one
      battalion), show it to jammed players or not (by default a player
      inside a comms jammer doesn't see it).

    S.TicketsOn(), S.Tickets() (shared). S.OBJECTIVE, S.MEDIC_ZONE.
    Config (module spawns, section "Events"): medicZoneRadius,
    medicZoneRegen, ticketsStart.
]]

local S = Rhylib.Spawns
local Config = Rhylib.Config

S.OBJECTIVE = "rhylib_objective"
S.MEDIC_ZONE = "rhylib_medic_zone"

local E = { section = "Events" }
Config.Register("spawns", "ticketsStart", 50, "Respawn tickets: how many the pool starts with when staff switch tickets on without a number", E)
Config.Register("spawns", "medicZoneRadius", 300, "Medic zones: radius (units; 300 = about 6 m)", E)
Config.Register("spawns", "medicZoneRegen", 2, "Medic zones: health a second for anyone standing in one", E)
Config.Register("spawns", "objectiveModel", "models/props_combine/combine_mine01.mdl", "Objective marker: model", E)
Config.Register("spawns", "medicZoneModel", "models/props_combine/combine_mine01.mdl", "Medic zone: model at its centre", E)

-- Respawn tickets.
function S.TicketsOn() return GetGlobal2Bool("rhylib_tickets_on", false) end
function S.Tickets() return GetGlobal2Int("rhylib_tickets", 0) end

-- S.ObjectiveFor(ply, ent): may ply see this objective marker? Its
-- battalion ("" = everyone, S.InBattalion), and not while jammed unless
-- it's set to show then (rhylib_radio R.Jammed). Shared.
function S.ObjectiveFor(ply, ent)
    if not (IsValid(ent) and IsValid(ply)) then return false end
    if not S.InBattalion(ply, ent:GetBattalion()) then return false end
    if not ent:GetShowJammed() then
        local R = Rhylib.Radio
        if R and R.Jammed and R.Jammed(ply) then return false end
    end
    return true
end
