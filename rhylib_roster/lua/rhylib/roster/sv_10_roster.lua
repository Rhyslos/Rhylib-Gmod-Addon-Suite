--[[
    Roster (server): characters, names, membership, ranks, the roster page.

    Data (Rhylib.Data module/key):
      "char"/sid          { num, nick, trained, bn, r (rank index), seen,
                            hair, fhair, hcol, skin, q = { [qual] = true } }
      "char_nums"/"all"   { ["n" .. num] = sid }   taken numbers
      "roster"/battalion  { ["s" .. sid] = true }  members (also offline)
      "roster_log"/bn     list of { t, txt }, newest first
    (keys are prefixed: JSON would turn bare number-like keys into numbers)

    Messages:
      roster.need     server -> player: create your character (empty)
      roster.hello    player -> server: still no character? (empty; the
                      client asks every 6 s until it has one)
      roster.create   num, nick (strings), hair, fhair (strings), hair
                      colour (UInt 4), skin (UInt 4)
                      -> roster.created (ok bool, message string)
      roster.look     hair, fhair, hair colour (4), skin (4): new looks
      roster.lookopen server -> player: open the looks window (/look)
      roster.get      battalion string ("" = mine; only admins may pick
                      another) -> roster.data (see R.SendRoster)
      roster.act      action (UInt 2, R.ACT_*), target sid, value (UInt 8:
                      the new rank index for ACT_RANK)
      roster.open     server -> player: open the Battalion page (/roster)

    Hooks fired: Rhylib.RosterJoined(sid, battalion) after R.AddMember;
    Rhylib.RosterNote(battalion, sid) -> a short note shown next to a
    member on the roster page (rhylib_datapad: leave of absence).
    Hooks answered: Rhylib.CanPostBoard (rank >= boardRank in that
    battalion), Rhylib.DataPurged (forget cached characters).
    Permission: rhylib.roster.admin (default admin).
    Commands: rhylib_char_reset <SteamID64 | clone number | name>, chat
    /roster (!roster) and /look (!look).
]]

local R = Rhylib.Roster
local Data = Rhylib.Data

-- Server -> client messages (client -> server ones register in Net.Receive).
for _, n in ipairs({ "roster.need", "roster.created", "roster.data", "roster.open", "roster.lookopen" }) do Rhylib.Net.Register(n) end

local function validSid(id) return isstring(id) and #id <= 20 and string.match(id, "^%d+$") ~= nil end
Rhylib.Perms.Register("rhylib.roster.admin", "admin", "Manage any battalion's roster, ranks and characters")

-- roster.act actions (2 bits; cl_20_roster.lua has the same numbers).
R.ACT_TRAIN, R.ACT_ADD, R.ACT_RANK, R.ACT_REMOVE = 0, 1, 2, 3

local function sid(ply) return ply:SteamID64() or "" end

--------------------------------------------------------------------------
-- Storage (cached)
--------------------------------------------------------------------------

local chars = {}   -- [sid] = record or false

-- R.Char(sid): the saved character record of a SteamID64 (online or not),
-- or nil. Cached; the table is the live copy: change it, then R.SaveChar.
-- Example: local c = Rhylib.Roster.Char(ply:SteamID64())  if c then print(c.num) end
function R.Char(id)
    local c = chars[id]
    if c == nil then
        c = Data.Get("char", id)
        if not istable(c) then c = false end
        chars[id] = c
    end
    return c or nil
end

-- Forget cached characters (after saved data changed behind them).
function R.ForgetChars() chars = {} end
Rhylib.Hook.Add("Rhylib.DataPurged", "roster.cache", function() R.ForgetChars() end)

-- R.SaveChar(sid, record): store a character (cache + Data "char").
-- Doesn't update the player's NW2 vars: call R.Publish(ply) for that.
function R.SaveChar(id, c)
    chars[id] = c
    Data.Set("char", id, c)
end

local function numbers()
    local t = Data.Get("char_nums", "all")
    return istable(t) and t or {}
end

local function members(bn)
    local t = Data.Get("roster", bn)
    return istable(t) and t or {}
end

local function setMember(bn, id, on)
    if bn == "" then return end
    local t = members(bn)
    t["s" .. id] = on or nil
    Data.Set("roster", bn, t)
end

-- R.Members(battalion): members, online or not: list of { id = sid, c = character }.
function R.Members(bn)
    local out = {}
    if bn == "" then return out end
    for key in pairs(members(bn)) do
        local id = string.sub(tostring(key), 2)
        local c = R.Char(id)
        if c and c.bn == bn then out[#out + 1] = { id = id, c = c } end
    end
    return out
end

-- R.Log(battalion, text): add a line to the battalion's roster log
-- (Data "roster_log", newest first, 200 lines kept). "" battalion = no log.
function R.Log(bn, txt)
    if bn == "" then return end
    local t = Data.Get("roster_log", bn)
    if not istable(t) then t = {} end
    table.insert(t, 1, { t = os.time(), txt = txt })
    while #t > 200 do table.remove(t) end
    Data.Set("roster_log", bn, t)
end

--------------------------------------------------------------------------
-- Names and networked state
--------------------------------------------------------------------------

-- R.Publish(ply): copy the saved character to the player's NW2 vars
-- (rhylib_char, _num, _nick, _hair, _fhair, _haircol, _skin, _trained, _bn,
-- _rank, _quals). Call after changing a record of an online player.
function R.Publish(ply)
    local c = R.Char(sid(ply))
    ply:SetNW2Bool("rhylib_char", c ~= nil)
    ply:SetNW2String("rhylib_num", c and c.num or "")
    ply:SetNW2String("rhylib_nick", c and c.nick or "")
    ply:SetNW2String("rhylib_hair", c and c.hair or "hair_reg")
    ply:SetNW2String("rhylib_fhair", c and c.fhair or "")
    ply:SetNW2Int("rhylib_haircol", c and tonumber(c.hcol) or 0)
    ply:SetNW2Int("rhylib_skin", c and tonumber(c.skin) or 0)
    ply:SetNW2Bool("rhylib_trained", c and c.trained or false)
    ply:SetNW2String("rhylib_bn", c and c.bn or "")
    ply:SetNW2Int("rhylib_rank", c and c.r or 0)
    local q = {}
    if c and istable(c.q) then
        for id, on in pairs(c.q) do
            if on then q[#q + 1] = tostring(id) end
        end
    end
    table.sort(q)
    ply:SetNW2String("rhylib_quals", #q > 0 and ("," .. table.concat(q, ",") .. ",") or "")
end

-- R.ApplyName(ply): set PREFIX-NUMBER Nickname as the DarkRP rpname.
function R.ApplyName(ply)
    if not IsValid(ply) then return end
    local name = R.FullName(ply)
    if name and ply.setDarkRPVar then ply:setDarkRPVar("rpname", name) end
end

-- After a rank or membership change: if the current job isn't allowed any
-- more, back to their home job.
-- Home job: their battalion's job for their rank (the highest minRank they
-- meet, not medic, with a free slot), else CT (trained) or cadet.
-- Players sitting in cadet/CT who have something better move there too
-- (on join, after training, when added to a battalion).
local function slotFree(t, j)
    local max = j.max or 0
    if max <= 0 then return true end
    if max < 1 then max = math.ceil(max * player.GetCount()) end   -- (DarkRP: a share of the players)
    return team.NumPlayers(t) < max
end

local function homeJob(ply)
    local c = R.Get(ply)
    if c.bn ~= "" and RPExtraTeams then
        local best, bestNeed
        for t, j in pairs(RPExtraTeams) do
            if j.battalion == c.bn and not j.medic and (t == ply:Team() or slotFree(t, j)) then
                local ok = true
                if j.customCheck then ok = j.customCheck(ply) and true or false else ok = R.JobBlock(ply, j) == nil end
                local need = R.RankIndex(j.minRank) or 0
                if ok and (not best or need > bestNeed) then best, bestNeed = t, need end
            end
        end
        if best then return best end
    end
    return c.trained and TEAM_CT or (TEAM_CADET or GAMEMODE.DefaultTeam)
end

local function moveTo(ply, t)
    if not t or ply:Team() == t or not ply.changeTeam then return end
    ply:changeTeam(t, true)
    ply.LastJob = nil   -- a move we made doesn't start DarkRP's job-change wait
end

local function checkJob(ply)
    local j = RPExtraTeams and RPExtraTeams[ply:Team()]
    local cadet = TEAM_CADET or GAMEMODE.DefaultTeam
    if (j and R.JobBlock(ply, j)) or ply:Team() == cadet or (TEAM_CT and ply:Team() == TEAM_CT) then
        moveTo(ply, homeJob(ply))
    end
    R.ApplyName(ply)
end

local function needCharacter(ply)
    Rhylib.Net.Start("roster.need")
    net.Send(ply)
end

Rhylib.Hook.Add("PlayerInitialSpawn", "roster.load", function(ply)
    if ply:IsBot() then return end
    R.Publish(ply)
    timer.Simple(2, function()
        if not IsValid(ply) then return end
        if R.Char(sid(ply)) then
            R.ApplyName(ply)
            checkJob(ply)
        else
            needCharacter(ply)
        end
    end)
end)

Rhylib.Hook.Add("PlayerSpawn", "roster.name", function(ply)
    timer.Simple(0, function() R.ApplyName(ply) end)
end)

-- The client asks once it has loaded (the first message can arrive too early).
Rhylib.Net.Receive("roster.hello", function(ply)
    if not R.Char(sid(ply)) then needCharacter(ply) end
end, { rate = 1, burst = 3 })
Rhylib.Hook.Add("OnPlayerChangedTeam", "roster.name", function(ply)
    timer.Simple(0, function() R.ApplyName(ply) end)
end)

-- Names come from the character, not /rpname.
Rhylib.Hook.Add("CanChangeRPName", "roster.name", function(ply)
    if R.Char(sid(ply)) then return false, "Your name comes from your character" end
end)

Rhylib.Hook.Add("PlayerDisconnected", "roster.seen", function(ply)
    local c = R.Char(sid(ply))
    if c then
        c.seen = os.time()
        R.SaveChar(sid(ply), c)
    end
end)

--------------------------------------------------------------------------
-- Character creator
--------------------------------------------------------------------------

local function reply(ply, ok, msg)
    Rhylib.Net.Start("roster.created")
    net.WriteBool(ok)
    net.WriteString(msg or "")
    net.Send(ply)
end

Rhylib.Net.Receive("roster.create", function(ply)
    local num = string.Trim(net.ReadString())
    local nick = R.CleanNick(net.ReadString())
    local hair, fhair, hcol, skin = net.ReadString(), net.ReadString(), net.ReadUInt(4), net.ReadUInt(4)
    if not R.ValidLook(hair, fhair, hcol, skin) then hair, fhair, hcol, skin = "hair_reg", "", 0, 0 end
    local id = sid(ply)
    if id == "" or R.Char(id) then return end   -- one character per player
    local ok, why = R.ValidNumber(num)
    if not ok then return reply(ply, false, why) end
    ok, why = R.ValidNick(nick)
    if not ok then return reply(ply, false, why) end
    local nums = numbers()
    if nums["n" .. num] and nums["n" .. num] ~= id then return reply(ply, false, "That number is taken") end
    nums["n" .. num] = id
    Data.Set("char_nums", "all", nums)
    R.SaveChar(id, { num = num, nick = nick, trained = false, bn = "", r = 0, seen = os.time(), hair = hair, fhair = fhair, hcol = hcol, skin = skin })
    R.Publish(ply)
    reply(ply, true)
    -- Start as a cadet.
    local cadet = TEAM_CADET or GAMEMODE.DefaultTeam
    if cadet and ply:Team() ~= cadet and ply.changeTeam then ply:changeTeam(cadet, true) end
    ply:Spawn()
    R.ApplyName(ply)
end, { rate = 1, burst = 3 })

-- Change your looks later (rhylib_look / !look).
Rhylib.Net.Receive("roster.look", function(ply)
    local hair, fhair, hcol, skin = net.ReadString(), net.ReadString(), net.ReadUInt(4), net.ReadUInt(4)
    local c = R.Char(sid(ply))
    if not c or not R.ValidLook(hair, fhair, hcol, skin) then return end
    c.hair, c.fhair, c.hcol, c.skin = hair, fhair, hcol, skin
    R.SaveChar(sid(ply), c)
    R.Publish(ply)
end, { rate = 2, burst = 4 })

-- Admin: rhylib_char_reset <name or SteamID64>: the player picks a new character.
concommand.Add("rhylib_char_reset", function(caller, _, args)
    Rhylib.Perms.Check(caller, "rhylib.roster.admin", function(allowed)
        local function say(m) if IsValid(caller) then caller:ChatPrint(m) else print(m) end end
        if not allowed then return say("You don't have permission for rhylib_char_reset") end
        local q = string.lower(string.Trim(table.concat(args, " ")))
        if q == "" then return say("Usage: rhylib_char_reset <SteamID64, clone number or exact name>") end
        local target, id
        -- SteamID64, then clone number, then exactly one name match.
        for _, p in ipairs(player.GetHumans()) do
            if sid(p) == q then target = p end
        end
        if not target and #q == 4 then
            local owner = numbers()["n" .. q]
            if owner then
                id = owner
                for _, p in ipairs(player.GetHumans()) do
                    if sid(p) == owner then target = p end
                end
            end
        end
        if not target and not id then
            local found
            for _, p in ipairs(player.GetHumans()) do
                if string.find(string.lower(p:Nick()), q, 1, true) then
                    if found then return say("More than one player matches '" .. q .. "'; use the SteamID64 or clone number") end
                    found = p
                end
            end
            target = found
        end
        id = id or (IsValid(target) and sid(target)) or (validSid(q) and q)
        local c = id and R.Char(id)
        if not c then return say("No character found for " .. q) end
        local nums = numbers()
        nums["n" .. c.num] = nil
        Data.Set("char_nums", "all", nums)
        setMember(c.bn or "", id, false)
        chars[id] = false
        Data.Delete("char", id)
        say("Reset the character of " .. (IsValid(target) and target:Nick() or id))
        if IsValid(target) then
            R.Publish(target)
            checkJob(target)
            if target.setDarkRPVar then target:setDarkRPVar("rpname", "New recruit") end
            needCharacter(target)
        end
    end)
end)

--------------------------------------------------------------------------
-- Roster actions
--------------------------------------------------------------------------

local function isAdmin(ply, fn)
    Rhylib.Perms.Check(ply, "rhylib.roster.admin", function(ok) if IsValid(ply) then fn(ok) end end)
end

local function manageRank() return R.RankIndex(R.Cfg("manageRank")) or 4 end

-- Online player by SteamID64.
local function online(id)
    for _, p in ipairs(player.GetHumans()) do
        if sid(p) == id then return p end
    end
end

local function after(id)
    local p = online(id)
    if IsValid(p) then
        R.Publish(p)
        checkJob(p)
    end
end

local function fullName(c)
    if not c then return "?" end
    local prefix = ((c.bn or "") ~= "" and (c.r or 0) > 0) and (R.RankPrefix(c.r) or "CT") or (c.trained and "CT" or "CC")
    return prefix .. "-" .. c.num .. " " .. c.nick
end

-- R.SetQual(sid, qual, on, by): give (on = true) or take a qualification.
-- by: a name for the log. Returns true if it changed. No permission check
-- here (the caller checks).
-- Example: Rhylib.Roster.SetQual(ply:SteamID64(), "pilot", true, admin:Nick())
function R.SetQual(id, q, on, by)
    local c = R.Char(id)
    if not c then return false end
    c.q = istable(c.q) and c.q or {}
    if (c.q[q] and true or false) == on then return false end
    c.q[q] = on or nil
    R.SaveChar(id, c)
    R.Log(c.bn or "", by .. (on and " qualified " or " removed the qualification of ") .. fullName(c) .. (on and " as " or ": ") .. R.QualName(q))
    after(id)
    return true
end

-- R.FullCharName(record): "PREFIX-NUMBER Nickname" from a saved record
-- (works for offline characters, unlike R.FullName).
R.FullCharName = function(c) return fullName(c) end

-- Put a trained CT into bn as PVT; a member of another battalion is
-- moved out of it (one whitelist at a time). how: "X added" or "X accepted
-- the application of" (for the log). Returns true if it happened.
-- Fires hook Rhylib.RosterJoined(sid, bn). No rank checks here.
-- Example: Rhylib.Roster.AddMember(sid, "212th", "CPT-1234 Rex added")
function R.AddMember(id, bn, how)
    local c = R.Char(id)
    if bn == "" or not c or not c.trained or c.bn == bn then return false end
    local old = c.bn or ""
    if old ~= "" then
        setMember(old, id, false)
        R.Log(old, fullName(c) .. " transferred to the " .. bn)
    end
    c.bn, c.r = bn, 1
    R.SaveChar(id, c)
    setMember(bn, id, true)
    R.Log(bn, how .. " " .. fullName(c) .. " (" .. bn .. ")")
    after(id)
    hook.Run("Rhylib.RosterJoined", id, bn)
    return true
end

-- For rhylib_admin (no rank checks here; the caller checks). by: a name for
-- the log. Each returns true if something changed.
-- R.SetRank(sid, rankIndex, by): only for battalion members (1..#ranks).
-- R.RemoveMember(sid, by): out of their battalion (rank back to 0).
-- R.Train(sid, by): pass basic training (cadet -> CT).
function R.SetRank(id, value, by)
    local c = R.Char(id)
    local bn = c and c.bn or ""
    if bn == "" or value < 1 or value > #R.Ranks() or value == c.r then return false end
    local old = c.r
    c.r = value
    R.SaveChar(id, c)
    R.Log(bn, by .. (value > old and " promoted " or " demoted ") .. fullName(c) .. " (" .. R.RankName(old) .. " → " .. R.RankName(value) .. ")")
    after(id)
    return true
end

function R.RemoveMember(id, by)
    local c = R.Char(id)
    local bn = c and c.bn or ""
    if bn == "" then return false end
    R.Log(bn, by .. " removed " .. fullName(c) .. " from the " .. bn)
    c.bn, c.r = "", 0
    R.SaveChar(id, c)
    setMember(bn, id, false)
    after(id)
    return true
end

function R.Train(id, by)
    local c = R.Char(id)
    if not c or c.trained then return false end
    c.trained = true
    R.SaveChar(id, c)
    R.Log(c.bn or "", by .. " passed " .. fullName(c) .. " through basic training")
    after(id)
    return true
end

-- R.ResetChar(sid): delete the character (number freed, out of the
-- battalion); an online player gets the creator again. Returns true if
-- there was one.
function R.ResetChar(id)
    local c = R.Char(id)
    if not c then return false end
    local nums = numbers()
    nums["n" .. c.num] = nil
    Data.Set("char_nums", "all", nums)
    setMember(c.bn or "", id, false)
    chars[id] = false
    Data.Delete("char", id)
    local target = online(id)
    if IsValid(target) then
        R.Publish(target)
        checkJob(target)
        if target.setDarkRPVar then target:setDarkRPVar("rpname", "New recruit") end
        needCharacter(target)
    end
    return true
end

-- Roster actions from the Battalion page. Managers (rank >= manageRank in
-- their battalion) act only on members ranked below them and give ranks
-- below their own; admins (rhylib.roster.admin) anything, in the battalion
-- they picked on the page (ply.rhylibRosterBn). Replies with roster.data.
Rhylib.Net.Receive("roster.act", function(ply)
    local act = net.ReadUInt(2)
    local id = net.ReadString()
    local value = net.ReadUInt(8)
    if not validSid(id) then return end
    isAdmin(ply, function(admin)
        local me = R.Char(sid(ply))
        local myRank = (me and (me.bn or "") ~= "" and me.r) or 0
        local manager = admin or myRank >= manageRank()
        if not manager then return end   -- (before looking anyone up)
        local them = R.Char(id)
        if not them then return end
        local by = ply:Nick()

        if act == R.ACT_TRAIN then
            if not manager or them.trained then return end
            them.trained = true
            R.SaveChar(id, them)
            R.Log(me and me.bn or "", by .. " passed " .. fullName(them) .. " through basic training")
            after(id)
        elseif act == R.ACT_ADD then
            -- value: unused for officers (their battalion); admins pass the battalion name via the roster page's bn.
            local bn = me and me.bn or ""
            if admin and ply.rhylibRosterBn and ply.rhylibRosterBn ~= "" then bn = ply.rhylibRosterBn end
            if bn == "" or not manager then return end
            if not admin and (not me or me.bn ~= bn) then return end
            -- Taking someone from another battalion: only if they rank below you.
            if not admin and (them.bn or "") ~= "" and (them.r or 0) >= myRank then return end
            R.AddMember(id, bn, by .. ((them.bn or "") ~= "" and " transferred in" or " added"))
        elseif act == R.ACT_RANK then
            local bn = them.bn or ""
            if bn == "" or value < 1 or value > #R.Ranks() then return end
            if not admin then
                -- Own battalion, someone below you, to below your rank.
                if not me or me.bn ~= bn or not manager or them.r >= myRank or value >= myRank then return end
            end
            if value == them.r then return end
            local old = them.r
            them.r = value
            R.SaveChar(id, them)
            R.Log(bn, by .. (value > old and " promoted " or " demoted ") .. fullName(them) .. " (" .. R.RankName(old) .. " → " .. R.RankName(value) .. ")")
            after(id)
        elseif act == R.ACT_REMOVE then
            local bn = them.bn or ""
            if bn == "" then return end
            if not admin and (not me or me.bn ~= bn or not manager or them.r >= myRank) then return end
            R.Log(bn, by .. " removed " .. fullName(them) .. " from the " .. bn)
            them.bn, them.r = "", 0
            R.SaveChar(id, them)
            setMember(bn, id, false)
            after(id)
        end
        R.SendRoster(ply, ply.rhylibRosterBn or "")
    end)
end, { rate = 4, burst = 6 })

--------------------------------------------------------------------------
-- The roster page
--------------------------------------------------------------------------

-- R.SendRoster(ply, want): send roster.data for battalion `want` (admins)
-- or the player's own. Contents: battalion (string), admin (bool), manager
-- (bool), rank limit (UInt 8: ranks below this may be given; 255 for
-- admins), members (UInt 8 count, each: sid, name, rank UInt 8, online
-- bool, last seen UInt 32, note string), cadets (UInt 6 count: sid, name),
-- CTs that could be added (UInt 6 count: sid, name), log (UInt 6 count,
-- at most 40: time UInt 32, text).
function R.SendRoster(ply, want)
    isAdmin(ply, function(admin)
        local me = R.Char(sid(ply))
        local bn = (admin and want ~= "") and want or (me and me.bn or "")
        ply.rhylibRosterBn = admin and want or ""
        local myRank = (me and me.bn == bn and me.r) or 0
        local manager = admin or (myRank >= manageRank())

        local list = {}
        if bn ~= "" then
            for key in pairs(members(bn)) do
                local id = string.sub(key, 2)
                local c = R.Char(id)
                if c and c.bn == bn then
                    list[#list + 1] = { id = id, name = fullName(c), r = c.r, on = IsValid(online(id)), seen = c.seen or 0 }
                end
            end
            table.sort(list, function(a, b)
                if a.r ~= b.r then return a.r > b.r end
                return a.name < b.name
            end)
        end
        -- Online people an officer could act on: cadets to pass, CTs to add.
        local cadets, cts = {}, {}
        if manager then
            for _, p in ipairs(player.GetHumans()) do
                local c = R.Char(sid(p))
                if c and not c.trained then cadets[#cadets + 1] = p
                elseif c and c.trained and bn ~= "" and c.bn ~= bn and (admin or (c.bn or "") == "" or (c.r or 0) < myRank) then
                    cts[#cts + 1] = p
                end
            end
        end
        local log = bn ~= "" and Data.Get("roster_log", bn) or {}
        if not istable(log) then log = {} end

        Rhylib.Net.Start("roster.data")
        net.WriteString(bn)
        net.WriteBool(admin)
        net.WriteBool(manager)
        net.WriteUInt(admin and 255 or myRank, 8)   -- you can set ranks below this
        net.WriteUInt(math.min(#list, 255), 8)
        for i = 1, math.min(#list, 255) do
            local m = list[i]
            net.WriteString(m.id)
            net.WriteString(m.name)
            net.WriteUInt(m.r, 8)
            net.WriteBool(m.on)
            net.WriteUInt(m.seen, 32)
            net.WriteString(hook.Run("Rhylib.RosterNote", bn, m.id) or "")   -- e.g. leave of absence
        end
        net.WriteUInt(math.min(#cadets, 63), 6)
        for i = 1, math.min(#cadets, 63) do net.WriteString(sid(cadets[i])) net.WriteString(cadets[i]:Nick()) end
        net.WriteUInt(math.min(#cts, 63), 6)
        for i = 1, math.min(#cts, 63) do
            local c = R.Char(sid(cts[i]))
            net.WriteString(sid(cts[i]))
            net.WriteString(cts[i]:Nick() .. ((c and (c.bn or "") ~= "") and ("  ·  " .. c.bn) or ""))
        end
        local nlog = math.min(#log, 40)
        net.WriteUInt(nlog, 6)
        for i = 1, nlog do
            net.WriteUInt(log[i].t or 0, 32)
            net.WriteString(log[i].txt or "")
        end
        net.Send(ply)
    end)
end

Rhylib.Net.Receive("roster.get", function(ply)
    R.SendRoster(ply, string.sub(net.ReadString(), 1, 64))
end, { rate = 3, burst = 4 })

-- /roster opens the Battalion page.
Rhylib.Hook.Add("PlayerSay", "roster.cmd", function(ply, text)
    local t = string.lower(string.Trim(text))
    if t == "/roster" or t == "!roster" then
        Rhylib.Net.Start("roster.open")
        net.Send(ply)
        return ""
    end
    if (t == "/look" or t == "!look") and R.Char(sid(ply)) then
        Rhylib.Net.Start("roster.lookopen")
        net.Send(ply)
        return ""
    end
end)

-- The battalion board: officers (boardRank and up) of that battalion post.
Rhylib.Hook.Add("Rhylib.CanPostBoard", "roster.board", function(ply, bn)
    local c = R.Get(ply)
    local need = R.RankIndex(R.Cfg("boardRank")) or 6
    if c.bn == bn and c.rank >= need then return true end
end)
