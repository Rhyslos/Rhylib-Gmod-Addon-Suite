--[[
    Roster: characters, battalion membership and ranks (shared).

    This file: the rank ladder, qualifications and look lists (config and
    tables), the checks both realms use (R.ValidNumber, R.ValidNick,
    R.JobBlock, R.Prefix, R.FullName) and the job wrapper that adds our
    rules to DarkRP's customCheck. Server side (saving, actions, the roster
    page data): sv_10_roster.lua. Client: the creator (cl_10_creator),
    looks (cl_15_look) and the Battalion page (cl_20_roster).

    Character: a 4-digit clone number (unique on the server) and a
    nickname, chosen once on first join (admins can reset it). The name
    shown everywhere (DarkRP rpname) is PREFIX-NUMBER Nickname:
        CC   cadet (job namePrefix = "CC")
        CT   passed basic training (job namePrefix = "CT")
        rank prefix in a battalion (PVT-1234 Nickname, SGT-..., ...)

    Career: Cadet -> basic training (a SGT+ marks them trained) -> CT ->
    added to a battalion as PVT by its SGT+ -> promoted up the ladder.
    One shared rank ladder for every battalion.

    Jobs (DarkRP, jobs.lua) say what they need:
        needsTraining = true          passed basic training (CT)
        battalion = "501st"           a member of that battalion ...
        minRank = "SGT"               ... with at least this rank
        qual = "pilot"                a qualification (config "quals")
    Unavailable jobs show the reason in the job list.

    Promoting: within your own battalion, members ranked below you, up to
    one rank below yours. Adding members and passing cadets needs
    manageRank or higher. Admins (rhylib.roster.admin) can do anything.

    Player NW2 (set on change): rhylib_char (bool), rhylib_num, rhylib_nick,
    rhylib_trained (bool), rhylib_bn, rhylib_rank (index, 0 = none),
    rhylib_quals (",heavy,pilot,").

    Qualifications (config "quals"): given at the battalion computer
    (Personnel). They stay with the character, unlock jobs (job qual = id)
    and are armoury roles (armoury config "roles": heavy = { weapons = ... }).
]]

Rhylib.Roster = Rhylib.Roster or {}
local R = Rhylib.Roster

-- The clone shown in the character creator and Appearance page
-- (Server settings > Models can swap it: rhylib_core's model catalogue
-- writes the chosen path back into R.PREVIEW.model).
R.PREVIEW = R.PREVIEW or { model = "models/ct_trp/pm_ct_trp.mdl" }
Rhylib.Hook.Add("Rhylib.ModelCatalogue", "roster.models", function(add)
    add("roster.preview", "Character creator preview", "Players", function() return R.PREVIEW end, "model")
end)
local Config = Rhylib.Config

Config.Register("roster", "ranks", {
    { "PVT", "Private" }, { "PFC", "Private First Class" }, { "CPL", "Corporal" },
    { "SGT", "Sergeant" }, { "SSG", "Staff Sergeant" }, { "LT", "Lieutenant" },
    { "CPT", "Captain" }, { "MAJ", "Major" }, { "CMD", "Commander" },
}, "The rank ladder, lowest first: { prefix, name }")
Config.Register("roster", "manageRank", "SGT", "Lowest rank that can add members, pass cadets and promote")
Config.Register("roster", "boardRank", "LT", "Lowest rank that can post on the battalion board")
Config.Register("roster", "blockedNumbers", { "1337", "6969", "0420", "6767", "6967", "6769" }, "Clone numbers nobody can take")
Config.Register("roster", "nickMax", 20, "Longest nickname")
Config.Register("roster", "quals", {
    { "heavy", "Heavy weapons" }, { "marksman", "Marksman" }, { "demo", "Demolitions" },
    { "jump", "Jump trooper" }, { "pilot", "Pilot" }, { "engineer", "Engineer" },
}, "Qualifications: { id, name }. The id is also an armoury role and a job's qual = id")

-- R.Cfg(key): a "roster" config value. Example: R.Cfg("manageRank") -> "SGT"
function R.Cfg(k) return Config.Get("roster", k) end

-- R.Ranks(): the rank ladder, lowest first: list of { prefix, name }.
function R.Ranks() return R.Cfg("ranks") or {} end

-- R.RankIndex(prefix): rank index by prefix ("SGT" -> 4 with the default
-- ladder), or nil. Index 0 means "no rank" everywhere (NW2Int rhylib_rank).
-- Example: if ply:GetNW2Int("rhylib_rank", 0) >= Rhylib.Roster.RankIndex("LT") then ... end
function R.RankIndex(prefix)
    if not prefix then return nil end
    for i, r in ipairs(R.Ranks()) do
        if r[1] == prefix then return i end
    end
end

-- R.RankPrefix(i) / R.RankName(i): prefix ("SGT") or full name ("Sergeant")
-- of rank index i. RankPrefix returns nil and RankName "None" for no rank.
function R.RankPrefix(i) local r = R.Ranks()[i] return r and r[1] or nil end
function R.RankName(i) local r = R.Ranks()[i] return r and r[2] or "None" end

-- R.ValidNumber(num): clone number rules: 4 digits, never two zeros in a
-- row, not in blockedNumbers. Returns true, or false and the reason.
-- (Uniqueness is checked on the server against Data "char_nums".)
function R.ValidNumber(num)
    num = tostring(num or "")
    if not string.match(num, "^%d%d%d%d$") then return false, "The number must be exactly 4 digits" end
    if string.find(num, "00", 1, true) then return false, "No two zeros in a row (0411 is fine, 0011 isn't)" end
    for _, b in ipairs(R.Cfg("blockedNumbers") or {}) do
        if tostring(b) == num then return false, "That number isn't allowed" end
    end
    return true
end

-- Looks (shown with the helmet off; rhylib_gear hides them under a helmet).
-- Option names of the models' "hair" / "fhair" bodygroups ("" = none).
R.HAIR = {
    { "", "None" }, { "hair_reg", "Regulation" }, { "hair_short", "Short" }, { "hair_parted", "Parted" },
    { "hair_slick", "Slicked back" }, { "hair_spike", "Spiked" }, { "hair_mohawk", "Mohawk" }, { "hair_long", "Long" },
    { "hair_long2", "Long, loose" }, { "hair_tail", "Tail" }, { "hair_gree", "Gree style" }, { "hair_cornwall", "Cornwall" },
}
R.FHAIR = {
    { "", "None" }, { "fhair", "Stubble" }, { "fhair_stache", "Moustache" }, { "fhair_goatee", "Goatee" },
    { "fhair2", "Short beard" }, { "fhair3", "Chin beard" }, { "fhair_beard", "Full beard" },
}

-- Hair colour: a tint on the model's hair material ($color2; above 1 lightens).
R.HAIR_COLOURS = {
    { 0, "Natural" },
    { 1, "Black", { 0.45, 0.42, 0.40 } },
    { 2, "Dark brown", { 0.85, 0.65, 0.50 } },
    { 3, "Brown", { 1.30, 0.95, 0.65 } },
    { 4, "Auburn", { 1.70, 0.85, 0.50 } },
    { 5, "Blond", { 2.60, 2.10, 1.30 } },
    { 6, "Grey", { 1.80, 1.80, 1.80 } },
    { 7, "White", { 3.00, 3.00, 3.00 } },
}
-- Name of the tinted copy of a hair material (made on every client).
function R.HairMatName(orig, col)
    return "rhylib_hair_" .. util.CRC(string.lower(orig or "")) .. "_" .. (col or 0)
end

-- Model skins (the job models with hair have 5). { skin index, label }.
R.SKINS = { { 0, "1" }, { 1, "2" }, { 2, "3" }, { 3, "4" }, { 4, "5" } }

local function inList(list, v)
    for _, o in ipairs(list) do if o[1] == v then return true end end
    return false
end
-- R.ValidLook(hair, fhair, hcol, skin): true if every value is one of the
-- options above (the server checks what the client sends).
function R.ValidLook(hair, fhair, hcol, skin)
    return inList(R.HAIR, hair) and inList(R.FHAIR, fhair) and inList(R.HAIR_COLOURS, hcol or 0) and inList(R.SKINS, skin or 0)
end

-- Nickname: 2 to nickMax characters, no control characters, single spaces.
-- R.CleanNick(nick): strips control characters and extra spaces; returns
-- the cleaned string. R.ValidNick(nick): true, or false and the reason.
function R.CleanNick(nick)
    nick = string.gsub(tostring(nick or ""), "%c", "")
    nick = string.Trim((string.gsub(nick, "%s+", " ")))   -- (brackets: gsub's count must not reach Trim)
    return nick
end

function R.ValidNick(nick)
    local len = utf8.len(nick)
    if not len then return false, "Use normal letters" end
    if len < 2 then return false, "The nickname needs at least 2 characters" end
    if len > R.Cfg("nickMax") then return false, "The nickname is too long (max " .. R.Cfg("nickMax") .. ")" end
    return true
end

-- Qualifications.
-- R.Quals(): list of { id, name } (config "quals").
-- R.QualName(id): the display name, or the id if it isn't in the list.
-- R.HasQual(ply, id): from NW2String rhylib_quals, so it works on both realms.
-- Example: if Rhylib.Roster.HasQual(ply, "pilot") then ... end
function R.Quals() return R.Cfg("quals") or {} end
function R.QualName(id)
    for _, q in ipairs(R.Quals()) do
        if q[1] == id then return q[2] end
    end
    return id
end
function R.HasQual(ply, id)
    return string.find(ply:GetNW2String("rhylib_quals", ""), "," .. id .. ",", 1, true) ~= nil
end

-- Qualifications are armoury roles too: answers rhylib_armoury's
-- Rhylib.PlayerRoles(ply) hook with the list of qualification ids.
Rhylib.Hook.Add("Rhylib.PlayerRoles", "roster.quals", function(ply)
    local out = {}
    for id in string.gmatch(ply:GetNW2String("rhylib_quals", ""), "[^,]+") do out[#out + 1] = id end
    if #out > 0 then return out end
end)

-- R.Get(ply): what a player is, from their networked state (both realms):
-- { has, num, nick, trained, bn, rank }. rank is an index (0 = none),
-- bn the battalion name ("" = none).
-- Example: local c = Rhylib.Roster.Get(ply)  if c.bn == "212th" then ... end
function R.Get(ply)
    return {
        has = ply:GetNW2Bool("rhylib_char", false),
        num = ply:GetNW2String("rhylib_num", ""),
        nick = ply:GetNW2String("rhylib_nick", ""),
        trained = ply:GetNW2Bool("rhylib_trained", false),
        bn = ply:GetNW2String("rhylib_bn", ""),
        rank = ply:GetNW2Int("rhylib_rank", 0),
    }
end

local function job(ply) return RPExtraTeams and RPExtraTeams[ply:Team()] end

-- R.Prefix(ply, job): the name prefix for this player's job (default: the
-- current one): the job's namePrefix, else their rank prefix in their own
-- battalion's job, else "CT" (trained) or "CC" (cadet).
function R.Prefix(ply, j)
    j = j or job(ply)
    if j and j.namePrefix then return j.namePrefix end
    local c = R.Get(ply)
    if j and j.battalion and c.bn == j.battalion and c.rank > 0 then return R.RankPrefix(c.rank) or "CT" end
    return c.trained and "CT" or "CC"
end

-- R.FullName(ply, job): "PREFIX-NUMBER Nickname", or nil without a character.
function R.FullName(ply, j)
    local c = R.Get(ply)
    if not c.has then return nil end
    return R.Prefix(ply, j) .. "-" .. c.num .. " " .. c.nick
end

-- R.JobBlock(ply, job): why a player can't take a DarkRP job right now (a
-- sentence for the job list), or nil if they can. Reads the job's
-- needsTraining / battalion / minRank / qual fields.
-- Example: local why = Rhylib.Roster.JobBlock(ply, RPExtraTeams[ply:Team()])
function R.JobBlock(ply, j)
    local c = R.Get(ply)
    if not c.has and (j.needsTraining or j.battalion) then return "Create your character first" end
    if j.needsTraining and not c.trained then return "Needs basic training (ask a Sergeant or higher)" end
    if j.battalion then
        if c.bn ~= j.battalion then return "Only for members of the " .. j.battalion end
        local need = R.RankIndex(j.minRank)
        if need and c.rank < need then return "Needs rank " .. R.RankName(need) .. " or higher" end
    end
    if j.qual and not R.HasQual(ply, j.qual) then return "Needs the " .. R.QualName(j.qual) .. " qualification" end
    return nil
end

-- Add our rules to the DarkRP jobs (customCheck runs on both sides and
-- in the F4 / job list). Done once the jobs exist. The job's own
-- customCheck / CustomCheckFailMsg still run after ours; j.rhylibWrapped
-- stops a second wrap on Lua refresh.
local function wrapJobs()
    if not RPExtraTeams then return end
    for _, j in pairs(RPExtraTeams) do
        if (j.needsTraining or j.battalion or j.qual) and not j.rhylibWrapped then
            j.rhylibWrapped = true
            local oldCheck, oldMsg = j.customCheck, j.CustomCheckFailMsg
            j.customCheck = function(ply)
                if R.JobBlock(ply, j) then return false end
                return not oldCheck or oldCheck(ply)
            end
            j.CustomCheckFailMsg = function(ply, jj)
                local why = R.JobBlock(ply, j)
                if why then return why end
                if isfunction(oldMsg) then return oldMsg(ply, jj) end
                return oldMsg
            end
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "roster.jobs", wrapJobs)
Rhylib.Hook.Add("DarkRPFinishedLoading", "roster.jobs", wrapJobs)
wrapJobs()  -- (Lua refresh)
