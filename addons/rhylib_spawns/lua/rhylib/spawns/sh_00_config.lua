--[[
    Spawn points (player spawners).

      Spawn point (rhylib_spawn_point): a named respawn spot for one
      battalion (or everyone). Placed with the toolgun, saved per map.
      Event spawn (rhylib_event_spawn): named; staff switch it on for an
      event (then everyone can respawn there, and it's the default) and
      can teleport everyone to it.

    While dead you pick where to respawn from a list (number keys 1-9):
    active event spawns, then your battalion's points, then points for
    everyone. Nothing picked = the default (an active event spawn, else
    your battalion's first point). Every spawn (respawns, job changes,
    joining) goes to a point when one fits; no points for you = the map's
    own spawns (or DarkRP team spawns).

    Staff (perm rhylib.spawns.admin) press E on a point to rename it, set
    its battalion, switch an event spawn on or off, or teleport everyone
    there. Only permanent points are saved (toolgun Permanent tool, or
    rhylib_spawns_save saves the permanent ones now).

    Shared file: Rhylib.Spawns (S) with InBattalion, IsPoint, Options;
    server functions in sv_10_spawns.lua, the menus in cl_10_spawns.lua.
]]

Rhylib.Spawns = Rhylib.Spawns or {}
local S = Rhylib.Spawns

S.POINT = "rhylib_spawn_point"
S.EVENT = "rhylib_event_spawn"

Rhylib.Config.Register("spawns", "model", "models/props_combine/combine_mine01.mdl", "Spawn point model")
Rhylib.Perms.Register("rhylib.spawns.admin", "admin", "Edit and save spawn points, run event teleports")

-- S.InBattalion(ply, bn): does a point's battalion fit this player?
-- Matches their roster battalion (NW2 rhylib_bn), their job's battalion or
-- their DarkRP job category. "" fits everyone.
function S.InBattalion(ply, bn)
    if bn == "" then return true end
    if ply:GetNW2String("rhylib_bn", "") == bn then return true end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job ~= nil and (job.battalion == bn or job.category == bn)
end

-- S.IsPoint(ent): a spawn point or event spawn.
function S.IsPoint(ent)
    return IsValid(ent) and (ent:GetClass() == S.POINT or ent:GetClass() == S.EVENT)
end

-- S.Options(ply): points this player may respawn at, best first:
-- { { ent, event }, ... }: open event spawns, their battalion's points,
-- then everyone points. Empty = the map's own spawns are used.
function S.Options(ply)
    local list = {}
    for _, e in ipairs(ents.FindByClass(S.EVENT)) do
        if e:GetActive() then list[#list + 1] = { ent = e, event = true } end
    end
    local mine, all = {}, {}
    for _, e in ipairs(ents.FindByClass(S.POINT)) do
        local pbn = e:GetBattalion()
        if pbn == "" then
            all[#all + 1] = { ent = e }
        elseif S.InBattalion(ply, pbn) then
            mine[#mine + 1] = { ent = e }
        end
    end
    for _, o in ipairs(mine) do list[#list + 1] = o end
    for _, o in ipairs(all) do list[#list + 1] = o end
    return list
end
