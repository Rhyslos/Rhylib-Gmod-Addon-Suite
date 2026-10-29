--[[
    Roster staff commands for rhylib_admin (shared: the
    staff menu needs the list; the server runs them). Registered with
    Rhylib.Admin.AddCommand once rhylib_admin is there (Rhylib.After);
    without rhylib_admin they don't exist. Permission "roster", as before.
    (The DarkRP money commands live in rhylib_admin sh_20_money.lua.)

      !rrank <player|id> <rank>          (!rosterrank) roster rank
      !battalion <player|id> <name>      into a battalion as PVT (trains a cadet)
      !unbattalion <player|id>           out of their battalion
      !train <player|id>                 pass basic training
      !qual <player|id> <qual> <on|off>  a qualification
      !charreset <player>                new number and nickname
    Also: the character line in !info (hook Rhylib.AdminInfo) and the
    staff menu's pickers for rosterrank / qual (Admin.ArgChoices, client).
]]

local R = Rhylib.Roster

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end
local function who(t, ctx) return IsValid(t) and t:Nick() or ctx.sid end

local H = {}
if SERVER then
    H.rrank = function(caller, t, a, ctx)
        local want = tostring(a.rank or "")
        local idx = tonumber(want)
        if idx and (idx ~= math.floor(idx) or idx < 1 or idx > #R.Ranks()) then return nil, "Roster rank 1 to " .. #R.Ranks() end
        idx = idx or R.RankIndex(string.upper(want))
        if not idx then
            for i, x in ipairs(R.Ranks()) do
                if string.lower(x[2]) == string.lower(want) then idx = i end
            end
        end
        if not idx then return nil, "No roster rank " .. want end
        local c = R.Char(ctx.sid)
        if not c or (c.bn or "") == "" then return nil, who(t, ctx) .. " isn't in a battalion" end
        if not R.SetRank(ctx.sid, idx, name(caller)) then return nil, "Nothing changed" end
        return name(caller) .. " set the roster rank of " .. who(t, ctx) .. " to " .. R.RankName(idx)
    end

    H.battalion = function(caller, t, a, ctx)
        -- A battalion is a DarkRP job category.
        local bn
        for _, job in pairs(RPExtraTeams or {}) do
            if job.category and string.lower(job.category) == string.lower(a.bn or "") then bn = job.category end
        end
        if not bn and RPExtraTeams then return nil, "No battalion " .. tostring(a.bn) end
        a.bn = bn or a.bn
        local c = R.Char(ctx.sid)
        if not c then return nil, who(t, ctx) .. " has no character yet" end
        if not c.trained then R.Train(ctx.sid, name(caller)) end
        if not R.AddMember(ctx.sid, a.bn, name(caller) .. " added") then return nil, "Nothing changed (already in the " .. tostring(a.bn) .. "?)" end
        return name(caller) .. " put " .. who(t, ctx) .. " in the " .. a.bn
    end

    H.unbattalion = function(caller, t, a, ctx)
        if not R.RemoveMember(ctx.sid, name(caller)) then return nil, who(t, ctx) .. " isn't in a battalion" end
        return name(caller) .. " removed " .. who(t, ctx) .. " from their battalion"
    end

    H.train = function(caller, t, a, ctx)
        if not R.Train(ctx.sid, name(caller)) then return nil, who(t, ctx) .. " is already trained (or has no character)" end
        return name(caller) .. " passed " .. who(t, ctx) .. " through basic training"
    end

    H.qual = function(caller, t, a, ctx)
        local q = string.lower(a.qual or "")
        local known = false
        for _, x in ipairs(R.Quals()) do if x[1] == q then known = true end end
        if not known then return nil, "No qualification " .. q end
        if not R.SetQual(ctx.sid, q, a.on, name(caller)) then return nil, "Nothing changed" end
        return name(caller) .. (a.on and " qualified " or " removed a qualification from ") .. who(t, ctx) .. ": " .. R.QualName(q)
    end

    H.charreset = function(caller, t)
        if not R.ResetChar(t:SteamID64()) then return nil, name(t) .. " has no character" end
        return name(caller) .. " reset the character of " .. name(t)
    end

end

local ROSTER = { "player", "Roster & staff rank" }

local function register()
    local A = Rhylib.Admin
    if not (A and A.AddCommand) then return end
    A.AddCommand({ id = "rrank", name = "Set roster rank", cat = "Ranks", perm = "roster", target = "id", args = { { "rank", "Rank", "rosterrank" } }, aliases = { "rosterrank" } }, H.rrank, ROSTER)
    A.AddCommand({ id = "battalion", name = "Set battalion", cat = "Ranks", perm = "roster", target = "id", args = { { "bn", "Battalion", "battalion" } }, desc = "Moves them in as PVT" }, H.battalion, ROSTER)
    A.AddCommand({ id = "unbattalion", name = "Remove from battalion", cat = "Ranks", perm = "roster", target = "id", args = {} }, H.unbattalion, ROSTER)
    A.AddCommand({ id = "train", name = "Pass basic training", cat = "Ranks", perm = "roster", target = "id", args = {} }, H.train, ROSTER)
    A.AddCommand({ id = "qual", name = "Qualification", cat = "Ranks", perm = "roster", target = "id", args = { { "qual", "Qualification", "qual" }, { "on", "On / off", "onoff" } } }, H.qual, ROSTER)
    A.AddCommand({ id = "charreset", name = "Reset character", cat = "Ranks", target = "player", args = {}, desc = "They pick a new number and nickname" }, H.charreset, ROSTER)

    if CLIENT then
        A.ArgChoices = A.ArgChoices or {}
        A.ArgChoices.rosterrank = function()
            local out = {}
            for i, r in ipairs(R.Ranks()) do out[#out + 1] = { tostring(i), r[1] .. " · " .. r[2] } end
            return out
        end
        A.ArgChoices.qual = function()
            local out = {}
            for _, q in ipairs(R.Quals()) do out[#out + 1] = { q[1], q[2] } end
            return out
        end
    end
end
Rhylib.After("admin", register)

if SERVER then
    Rhylib.Hook.Add("Rhylib.AdminInfo", "roster.info", function(t, sid, add)
        local c = R.Char and R.Char(sid)
        if c then
            add("Character: " .. tostring(c.num or "?") .. " " .. tostring(c.nick or "")
                .. ((c.bn or "") ~= "" and (" · " .. c.bn .. " · " .. R.RankName(c.r or 0)) or (c.trained and " · no battalion" or " · cadet")))
        end
    end)
end
