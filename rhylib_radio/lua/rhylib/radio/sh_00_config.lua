--[[
    Radio and squads (shared).

    Voice: the normal voice key is local (3D, within localRange). The radio
    key sends on your selected radio channel (Squad, Channel 1, Channel 2),
    or on a hail call while you're in one. People near you still hear you.
    Channels and squads live in memory and reset on map change.

    Everyone's radio state is one NW2Int "rhylib_radio", changed only on
    events (R.Bits / R.Pack):
      bit 0     radio off
      bit 1     muted (can't send on the radio)
      bit 2     deafened (hears no radio)
      bits 3-4  sending on: 0 nothing / local, 1 squad, 2 channel, 3 call
      bits 5-13 id of that squad / channel / call
      bits 14-22 squad id (0 = none)
      bits 23-27 role (R.ROLES index)
      bit 28    squad leader
      bit 29    radio operator

    Files: sv_10_radio (state, voice, squads, channels, jammer checks
    and saves), sv_20_hails (calls), sh_40_pings / sv_30_pings /
    cl_40_pings (squad pings), cl_05_icons (vector symbols), cl_10_client
    (keys, state), cl_20_hud (visor squares, meters, compass, markers),
    cl_25_fx (radio sound effects, jammer static), cl_30_page (the Radio
    page). Entities: rhylib_comms_jammer (+ _medium, _large, _map).

    This file: the module table Rhylib.Radio (R), config settings, jammer
    sizes, roles, and the state packing helpers used on both realms.
]]

Rhylib.Radio = Rhylib.Radio or {}
local R = Rhylib.Radio
local Config = Rhylib.Config

Config.Register("radio", "localRange", 800, "Local voice reaches this far (units, 800 = 15 m)")
Config.Register("radio", "maxChannels", 200, "Most custom channels on the server at once")
Config.Register("radio", "hailTime", 30, "Seconds a hail rings before it counts as missed")
Config.Register("radio", "squadNames", { "Aurek", "Besh", "Cresh", "Dorn", "Esk", "Forn", "Grek", "Herf", "Isk", "Jenth" }, "Squad name suggestions (with a number after)")

-- Radio sound (2026-10-07, owner): GMod can't filter voice audio itself,
-- so radio voices get squelch clicks, tiny drop-outs and the odd burst of
-- interference instead (cl_25_fx.lua).
Config.Register("radio", "fxDropEvery", 7, "Radio voice: average seconds between tiny drop-outs per talker (0 = none)")
Config.Register("radio", "fxDropLen", 0.08, "Radio voice: length of a drop-out (seconds; keep it tiny so nothing is lost)")
Config.Register("radio", "fxNoiseEvery", 20, "Radio voice: average seconds between interference bursts while someone talks on the radio (0 = none)")
Config.Register("radio", "fxSquelchOn", "npc/combine_soldier/vo/on1.wav", "Radio voice: click when someone starts talking on your radio")
Config.Register("radio", "fxSquelchOff", "npc/combine_soldier/vo/off1.wav", "Radio voice: click when they stop")
Config.Register("radio", "fxCrackle", { "ambient/energy/zap1.wav", "ambient/energy/zap2.wav", "ambient/energy/zap3.wav" }, "Radio voice: crackles at a drop-out")
Config.Register("radio", "fxNoise", { "ambient/levels/prison/radio_random1.wav", "ambient/levels/prison/radio_random2.wav", "ambient/levels/prison/radio_random3.wav", "ambient/levels/prison/radio_random4.wav", "ambient/levels/prison/radio_random5.wav" }, "Radio voice: interference bursts")

-- Comms jammer (2026-10-07, owner): inside its range the radio is dead
-- (static when you try, only local voice), and the radio text channels
-- (squad, battalion, command, comms) can't be used.
-- Four sizes (2026-10-07, owner): small, medium (twice the range), large
-- (four times), and one that covers the whole map. A model that isn't
-- installed falls back to jammerFallbackModel. Only explosives destroy
-- them (until the next map change or cleanup): small = any grenade,
-- medium = an RPS-6 rocket or a breaching charge, large = jammerPointsLarge
-- damage points (HE 6, rocket 3, breaching charge 2, adding up), whole map
-- = jammerChargesMap HE charges going off together.
Config.Register("radio", "jammerRange", 1800, "Small comms jammer: radius it jams (units, 1800 = 34 m)")
Config.Register("radio", "jammerModel", "models/props/starwars/weapons/hoth_bomb.mdl", "Small comms jammer: model")
Config.Register("radio", "jammerRangeMedium", 3600, "Medium comms jammer: radius it jams (units)")
Config.Register("radio", "jammerModelMedium", "models/lordtrilobite/starwars/props/barrel_scarif2c_phys.mdl", "Medium comms jammer: model")
Config.Register("radio", "jammerRangeLarge", 7200, "Large comms jammer: radius it jams (units; meant to cover about a quarter of the map)")
-- Large jammer (2026-10-07, owner): damage points add up: 1 HE charge,
-- 2 rockets, 3 breaching charges or a mix (2 charges + 1 rocket).
Config.Register("radio", "jammerPointsLarge", 6, "Large comms jammer: damage points to destroy it (they add up; see jamPoints*)")
Config.Register("radio", "jamPointsHE", 6, "Comms jammers: damage points of a high explosive charge (large jammer)")
Config.Register("radio", "jamPointsRocket", 3, "Comms jammers: damage points of an RPS-6 rocket (large jammer)")
Config.Register("radio", "jamPointsBreach", 2, "Comms jammers: damage points of a breaching charge (large jammer)")
Config.Register("radio", "jammerModelLarge", "models/starwars/syphadias/props/sw_tor/bioware_ea/props/neutral/neu_industrial_tower.mdl", "Large comms jammer: model")
Config.Register("radio", "jammerChargesMap", 4, "Map-wide comms jammer: high explosive charges needed to destroy it")
Config.Register("radio", "jammerChargeWindow", 3, "Comms jammers needing several HE charges: seconds within which they must all go off (0 = any time)")
Config.Register("radio", "jammerModelMap", "models/props/starwars/tech/imperial_deflector.mdl", "Map-wide comms jammer: model")
Config.Register("radio", "jammerFallbackModel", "models/props_lab/reciever01a.mdl", "Comms jammers: model used when a jammer's own model isn't installed")
Config.Register("radio", "jammerFringe", 0.35, "Comms jammers: interference zone outside the range, as a part of the range (0.35 = 35% further out; the compass breaks up and radio gets static as you get closer)")
Config.Register("radio", "jamReconnect", 4, "Comms jammers: seconds the radio stays jammed and reconnects after leaving the range")
Config.Register("radio", "jamStatic", "ambient/energy/electric_loop.wav", "Comms jammer: the static loop you hear when you key the radio while jammed")

-- R.Cfg(key): a radio config value (Config.Get("radio", key)). Shared.
function R.Cfg(k) return Config.Get("radio", k) end

-- Jammer sizes: class -> config key suffix and name. range nil = whole map.
-- tier = explosive strength needed (R.JAMMER_TIERS); points = config key
-- of the damage points it takes (they add up); charges = config key for
-- how many HE charges it takes (all together); need = what to tell players.
R.JAMMER_SIZES = {
    rhylib_comms_jammer = { key = "", name = "Comms jammer (small)", tier = 1 },
    rhylib_comms_jammer_medium = { key = "Medium", name = "Comms jammer (medium)", tier = 2 },
    rhylib_comms_jammer_large = { key = "Large", name = "Comms jammer (large)", tier = 2, points = "jammerPointsLarge",
        need = "a high explosive charge, 2 RPS-6 rockets, 3 breaching charges or a mix" },
    rhylib_comms_jammer_map = { key = "Map", name = "Comms jammer (whole map)", wholeMap = true, tier = 3, charges = "jammerChargesMap" },
}
-- Explosive strengths (hook Rhylib.Explosion): 1 any grenade, 2 RPS-6
-- rocket / breaching charge, 3 high explosive charge.
R.JAMMER_TIERS = { "any grenade", "an RPS-6 rocket or a breaching charge", "a high explosive charge" }

-- R.JammerSize(entOrClass): the R.JAMMER_SIZES row for a jammer entity
-- or class name; unknown classes count as the small one. Shared.
function R.JammerSize(ent)
    return R.JAMMER_SIZES[isstring(ent) and ent or ent:GetClass()] or R.JAMMER_SIZES.rhylib_comms_jammer
end

-- R.JammerRange(entOrClass): radius a jammer covers in units
-- (math.huge for the map-wide one). An entity with ENT:JamRange() (the
-- rhylib_eod interference device) answers for itself. Shared.
function R.JammerRange(ent)
    if not isstring(ent) and IsValid(ent) and ent.JamRange then return ent:JamRange() end   -- (rhylib_eod interference devices)
    local s = R.JammerSize(ent)
    if s.wholeMap then return math.huge end
    return R.Cfg("jammerRange" .. s.key) or 1800
end

-- R.Jammed(ply): is this player jammed? True inside an active jammer's
-- range and while reconnecting after leaving it (NW2Bool "rhylib_jammed",
-- set by the server's 0.5 s jam timer in sv_10_radio.lua). Shared.
-- Example: if Rhylib.Radio and Rhylib.Radio.Jammed(ply) then return end
function R.Jammed(ply)
    return IsValid(ply) and ply:GetNW2Bool("rhylib_jammed", false)
end

-- R.Reconnecting(ply): jammed but out of range again, reconnecting:
-- seconds left (or nil). From NW2Float "rhylib_jamUntil". Shared.
function R.Reconnecting(ply)
    if not R.Jammed(ply) then return nil end
    local t = ply:GetNW2Float("rhylib_jamUntil", 0)
    if t <= 0 then return nil end
    return math.max(0, t - CurTime())
end

-- R.JamLevel(ply): how strong the jamming is for this player, 0-1:
-- 1 inside a jammer, falling over the reconnect time after leaving, the
-- fringe level outside (NW2Float "rhylib_jamLevel", 5% steps). The
-- client uses it to scale the compass glitches and radio static. Shared.
function R.JamLevel(ply)
    if not IsValid(ply) then return 0 end
    local fringe = ply:GetNW2Float("rhylib_jamLevel", 0)
    if not R.Jammed(ply) then return fringe end
    local left = R.Reconnecting(ply)
    if not left then return 1 end
    local total = math.max(0.1, R.Cfg("jamReconnect") or 4)
    return math.max(fringe, math.Clamp(left / total, 0, 1))
end

R.ID_BITS = 9      -- bits for squad / channel / call ids on the wire
R.MAX_ID = 511     -- highest id (ids are 1..511; 0 = none)
R.NAME_LEN = 24    -- longest squad / channel name (and password)

-- What a player is sending on (the "tx kind" in the state bits).
R.TX_NONE, R.TX_SQUAD, R.TX_CHAN, R.TX_CALL = 0, 1, 2, 3

-- Roles: visual only. { id, name, icon } (icon = R.ICONS key, cl_05_icons).
-- The index is what is stored (5 bits, so at most 31 roles); add new
-- ones at the end so saved choices (rhylib_radio_role) keep their meaning.
R.ROLES = {
    { "rifleman", "Rifleman", "rifle" },
    { "assault", "Assault", "bolt" },
    { "spearhead", "Spearhead", "spear" },
    { "autorifleman", "Autorifleman", "mag" },
    { "ammo", "Ammo bearer", "ammo" },
    { "marksman", "Marksman", "crosshair" },
    { "heavy", "Heavy", "barrels" },
    { "antitank", "Anti-tank", "rocket" },
    { "breacher", "Breacher", "door" },
    { "grenadier", "Grenadier", "grenade" },
    { "medic", "Combat medic", "cross" },
    { "chemist", "Chemist", "cross" },
    { "airborne", "Airborne", "wings" },
    { "officer", "Officer", "star" },
    { "shock", "Shock trooper", "shield" },
}

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

-- R.Unpack(v): the radio state int as a table { off, muted, deaf,
-- txKind, txId, squad, role, leader, ro } (a new table each call;
-- R.State caches it). Shared.
function R.Unpack(v)
    return {
        off = band(v, 1) ~= 0,
        muted = band(v, 2) ~= 0,
        deaf = band(v, 4) ~= 0,
        txKind = band(rshift(v, 3), 3),
        txId = band(rshift(v, 5), 511),
        squad = band(rshift(v, 14), 511),
        role = band(rshift(v, 23), 31),
        leader = band(v, lshift(1, 28)) ~= 0,
        ro = band(v, lshift(1, 29)) ~= 0,
    }
end

-- R.Pack(t): the reverse of R.Unpack: a table of fields -> the int.
function R.Pack(t)
    local v = 0
    if t.off then v = bor(v, 1) end
    if t.muted then v = bor(v, 2) end
    if t.deaf then v = bor(v, 4) end
    v = bor(v, lshift(band(t.txKind or 0, 3), 3))
    v = bor(v, lshift(band(t.txId or 0, 511), 5))
    v = bor(v, lshift(band(t.squad or 0, 511), 14))
    v = bor(v, lshift(band(t.role or 0, 31), 23))
    if t.leader then v = bor(v, lshift(1, 28)) end
    if t.ro then v = bor(v, lshift(1, 29)) end
    return v
end

-- R.Raw(ply): the packed NW2Int "rhylib_radio".
function R.Raw(ply) return ply:GetNW2Int("rhylib_radio", 0) end
-- R.State(ply): unpacked state, kept per player until the value changes
-- (read only: it is shared between callers). Shared.
-- Example: if Rhylib.Radio.State(ply).off then ... end
function R.State(ply)
    local v = R.Raw(ply)
    local c = ply.rhylibRadioC
    if c and c.v == v then return c.t end
    local t = R.Unpack(v)
    ply.rhylibRadioC = { v = v, t = t }
    return t
end

-- Cheap single reads (used every frame and in the voice hook):
-- R.SquadOf(ply) squad id (0 = none), R.RoleOf(ply) role index (1 if
-- unset), R.IsLeader(ply), R.IsRO(ply). On the client cl_10_client.lua
-- replaces these for other players with the directory's values (their
-- NW2 arrives late while they're out of view).
-- Example (rhylib_chat's squad channel): local sq = Rhylib.Radio.SquadOf(ply)
function R.SquadOf(ply) return band(rshift(R.Raw(ply), 14), 511) end
function R.RoleOf(ply)
    local r = band(rshift(R.Raw(ply), 23), 31)
    return R.ROLES[r] and r or 1
end
function R.IsLeader(ply) return band(R.Raw(ply), lshift(1, 28)) ~= 0 end
function R.IsRO(ply) return band(R.Raw(ply), lshift(1, 29)) ~= 0 end

-- R.Battalion(ply): rhylib_roster's battalion (NW2String "rhylib_bn"),
-- else the DarkRP job category, else "". Used for battalion-only channels.
function R.Battalion(ply)
    local bn = ply:GetNW2String("rhylib_bn", "")
    if bn ~= "" then return bn end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.category or ""
end

-- R.CleanName(s): a squad / channel name with control characters
-- removed, trimmed, cut to R.NAME_LEN.
function R.CleanName(s)
    s = string.Trim(string.gsub(tostring(s or ""), "[%c]", ""))
    return string.sub(s, 1, R.NAME_LEN)
end

-- Channel access modes: open to all, needs the password, or only for
-- the creator's battalion (R.Battalion at creation).
R.MODE_OPEN, R.MODE_PASS, R.MODE_BN = 0, 1, 2
