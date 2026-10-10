--[[
    Military police: stun weapons, stun baton, handcuffs, searching, and a
    jail with cells and sentences.

      Stun        a stun ring (the MP "stun" fire mode) or a baton hit makes
                  the target collapse for stunTime seconds: they lie still
                  and can be cuffed.
      Cuffs       an MP cuffs a stunned or downed player (handcuffs LMB),
                  uncuffs (RMB on a cuffed player) and escorts (Reload:
                  the prisoner is pulled along behind you). Cuffed players
                  walk slowly, can't sprint, jump, shoot, switch weapons or
                  use their inventory.
      Search      with the stun baton in hand, RMB on a player shows their
                  inventory (look only). If they're cuffed, items can be
                  taken. MPs can also open locked lockers.
      Jail        admins place cells and a jail terminal (spawn menu,
                  rhylib_mp_save). At the terminal an MP jails a cuffed
                  prisoner nearby: minutes and a reason. Their items go to
                  evidence, they're put in a free cell, and when the time
                  is up they wait there to be processed (an MP at the
                  terminal, or automatically). Processed prisoners collect
                  their evidence at the property locker, minus contraband
                  and anything an MP withheld. Sentences survive
                  reconnects and map changes.
      Escort      escorting slows the MP (not with Escort drills).
      Hiding      players hide up to 3 contraband items; searches roll
                  for each (sv_20_search).

    Who is an MP: a DarkRP job with mp = true (or answer Rhylib.IsMP).

    This file (shared) loads first: the Rhylib.MP table, config keys,
    the state readers (IsStunned, IsCuffed, ...) and MP.Target. Then
    sh_10_move (input and movement), sv_10_stun (stun, cuffs, escort),
    sv_20_search, sv_30_jail, sv_40_property and the client windows.

    Hooks fired by this addon:
      Rhylib.IsMP(ply)                     return true/false to decide who is an MP
      Rhylib.CanStun(ply, by)              return false to block a stun
      Rhylib.PlayerStunned(ply, by)        after a stun starts
      Rhylib.PlayerCuffed(ply, by)         after cuffing
      Rhylib.PlayerUncuffed(ply, by)       after uncuffing (by is nil when the system does it)
      Rhylib.MPConfiscated(mp, target, id, count)  after an MP takes an item in a search
      Rhylib.PlayerJailed(ply, by, minutes, why)   after jailing
      Rhylib.PlayerReleased(ply, by)       after processing (out of jail)
      Rhylib.MPSearchTool(ply, weapon)     return true or a reach to let another tool search

    State is NW2 on the player, changed only on events:
      rhylib_stunEnd (CurTime), rhylib_stunYaw, rhylib_cuffed (bool),
      rhylib_escortBy (entity), rhylib_escorting (entity, on the MP),
      rhylib_jailEnd (CurTime), rhylib_jailWhy, rhylib_jailAwait (bool)
]]

Rhylib.MP = Rhylib.MP or {}
local MP = Rhylib.MP
local Config = Rhylib.Config

Config.Register("mp", "stunTime", 8, "Seconds a stun hit keeps someone down")
Config.Register("mp", "stunImmune", 3, "Seconds after getting up before they can be stunned again")
Config.Register("mp", "batonRange", 85, "Stun baton reach (units)")
Config.Register("mp", "propertyModel", "models/props_c17/lockers001a.mdl", "Property locker model")
Config.Register("mp", "terminalModel", "models/reizer_props/srsp/sci_fi/console_01/console_01.mdl", "Jail terminal model (HL2 console if missing)")
Config.Register("mp", "batonDelay", 1.2, "Seconds between baton swings")
Config.Register("mp", "cuffRange", 85, "How close you must be to cuff or uncuff")
Config.Register("mp", "cuffTime", 1.5, "Seconds to put cuffs on")
Config.Register("mp", "cuffWalk", 110, "Walk speed while cuffed")
Config.Register("mp", "escortLeash", 60, "How far behind the MP an escorted prisoner walks")
Config.Register("mp", "escortSlow", 0.75, "Speed multiplier for an MP escorting a prisoner (none with the Escort drills skill)")
Config.Register("mp", "searchRange", 100, "How close you must be to search someone")
Config.Register("mp", "searchMemory", 300, "Seconds an MP's search rolls on someone's hidden items are kept (searching again doesn't re-roll)")
Config.Register("mp", "processAuto", 300, "Seconds after a sentence ends before the prisoner is processed out automatically")
Config.Register("mp", "maxSentence", 60, "Longest sentence in minutes")
Config.Register("mp", "jailRadius", 350, "A prisoner further than this from their cell is put back")
Config.Register("mp", "terminalRange", 400, "Cuffed prisoners this close to a jail terminal can be jailed there")
Config.Register("mp", "poses", { "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }, "Lying poses while stunned, first that exists on the model wins")

-- MP.Cfg(key): shortcut for Rhylib.Config.Get("mp", key). Shared.
-- Example: local secs = Rhylib.MP.Cfg("stunTime")
function MP.Cfg(k) return Config.Get("mp", k) end

MP.TERM_USE = 180   -- how close an MP must stay to a terminal to use it

-- MP.IsMP(ply): true if ply is military police. Asks hook Rhylib.IsMP first
-- (any non-nil answer wins), else the DarkRP job's `mp = true` field. Shared.
-- Example: if Rhylib.MP.IsMP(ply) then ... end
function MP.IsMP(ply)
    if not IsValid(ply) then return false end
    local r = hook.Run("Rhylib.IsMP", ply)
    if r ~= nil then return r end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.mp == true or false
end

-- State readers (shared, read the NW2 values above):
--   MP.IsStunned(ply) -> bool, MP.IsCuffed(ply) -> bool,
--   MP.EscortedBy(ply) -> the MP pulling this prisoner, or nil.
function MP.IsStunned(ply) return ply:GetNW2Float("rhylib_stunEnd", 0) > CurTime() end
function MP.IsCuffed(ply) return ply:GetNW2Bool("rhylib_cuffed", false) end
function MP.EscortedBy(ply)
    local e = ply:GetNW2Entity("rhylib_escortBy")
    return IsValid(e) and e or nil
end
-- The prisoner this MP is escorting, if any.
function MP.Escorting(ply)
    local e = ply:GetNW2Entity("rhylib_escorting")
    if IsValid(e) and e:GetNW2Entity("rhylib_escortBy") == ply then return e end
end
-- MP.IsJailed(ply) -> bool (also true while awaiting processing).
-- MP.JailLeft(ply) -> seconds of sentence left (0 while awaiting).
function MP.IsJailed(ply) return ply:GetNW2Float("rhylib_jailEnd", 0) > 0 end
function MP.JailLeft(ply) return math.max(0, ply:GetNW2Float("rhylib_jailEnd", 0) - CurTime()) end

-- Cuffed, stunned or jailed: no inventory use (rhylib_inventory asks this).
Rhylib.Hook.Add("Rhylib.InventoryLocked", "mp.lock", function(ply)
    if MP.IsCuffed(ply) or MP.IsStunned(ply) or MP.IsJailed(ply) then return true end
end)

-- MP.Target(ply, range): the living player ply aims at within range units,
-- or nil. A lying player's ragdoll counts as that player. Two hull traces:
-- straight ahead, then aimed a little lower for bodies on the floor. Shared.
-- Example: local t = Rhylib.MP.Target(ply, Rhylib.MP.Cfg("cuffRange"))
function MP.Target(ply, range)

    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * range,
        filter = ply,
        mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
        mask = MASK_SHOT_HULL,
    })
    local L = Rhylib.Lying
    local e = tr.Entity
    if L and L.Owner and L.Owner(e) then e = L.Owner(e) end   -- a lying player's ragdoll
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
    -- Lying bodies (stunned or downed) are low: try a little lower too.
    local tr2 = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + (ply:GetAimVector() + Vector(0, 0, -0.35)):GetNormalized() * range,
        filter = ply,
        mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10),
        mask = MASK_SHOT_HULL,
    })
    e = tr2.Entity
    if L and L.Owner and L.Owner(e) then e = L.Owner(e) end
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
end
