--[[
    Intel datapads (shared): a game master places one (toolgun Base, or
    the spawn menu) and writes its intel (E with the toolgun out:
    title, text, who may read it once cracked). Field technicians (any
    Field technician skill, rhylib_skills spec "eod") crack it: three
    signal locks in a row, easy, moderate, hard. Two knobs (frequency,
    amplitude) keep a drifting signal inside a target band until the
    lock bar is full. Then the intel shows.

    D.INTEL_ROUNDS[r] = { drift, band, hold, jumps } read from config
    (D.IntelRound(r)). D.IsFieldTech(ply). Permission rhylib.datapad.intel
    (write intel; admin by default).
    Server: sv_95_intel.lua. Client: cl_95_intel.lua.
]]

local D = Rhylib.Datapad
local Config = Rhylib.Config

local S = { section = "Intel datapads" }
Config.Register("datapad", "intelRange", 120, "Intel datapads: how close you must stand to open or crack one (units)", S)
Config.Register("datapad", "intelTitleMax", 60, "Intel datapads: longest title (characters)", S)
Config.Register("datapad", "intelTextMax", 2000, "Intel datapads: longest intel text (characters)", S)
Config.Register("datapad", "intelDrift", { 0.25, 0.4, 0.5 }, "Intel datapads: how hard the signal drifts in rounds 1, 2 and 3", S)
Config.Register("datapad", "intelBand", { 0.17, 0.13, 0.1 }, "Intel datapads: how wide the target band is in rounds 1, 2 and 3 (smaller = harder)", S)
Config.Register("datapad", "intelHold", { 3, 4, 5 }, "Intel datapads: seconds in the band to lock rounds 1, 2 and 3", S)

Rhylib.Perms.Register("rhylib.datapad.intel", "admin", "Write and reset intel datapads")

-- D.IntelRound(r) -> { drift, band, hold, jumps } for round 1-3.
function D.IntelRound(r)
    local function at(k, def) local t = D.Cfg(k) return istable(t) and tonumber(t[r]) or def end
    return {
        drift = math.Clamp(at("intelDrift", 0.4), 0, 3),
        band = math.Clamp(at("intelBand", 0.12), 0.02, 0.6),
        hold = math.Clamp(at("intelHold", 4), 1, 30),
        jumps = r >= 3,
    }
end
D.INTEL_ROUND_NAMES = { "EASY", "MODERATE", "HARD" }

-- D.IsFieldTech(ply): any Field technician skill. False without rhylib_skills.
function D.IsFieldTech(ply)
    local K = Rhylib.Skills
    if not (K and K.NODES and K.Has and IsValid(ply)) then return false end
    for _, n in ipairs(K.NODES) do
        if n.spec == "eod" and K.Has(ply, n.id) then return true end
    end
    return false
end
