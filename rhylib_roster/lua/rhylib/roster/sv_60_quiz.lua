--[[
    Basic training quiz (server). See sh_60_quiz.lua for how it plays.

    Nets:
      (start: R.QuizStart(ply), pressing E on a training instructor,
                        entities/rhylib_trainer.lua. Checked: quiz on, has
                        a character, not trained, the lock-out over,
                        questions on the list. With a quiz already open
                        the same one is sent again (no new questions); one
                        open over 10 min, or left by disconnecting, counts
                        as a failed try. At most 30 questions.)
      roster.quiz       server -> that cadet: UInt 6 count, then per
                        question String text, UInt 3 answers, Strings.
      roster.quizclose  client -> server, empty: the quiz window closed
                        unfinished: counts as a failed try. Rate 2/s.
      roster.quizdone   client -> server: UInt 6 count, UInt 3 answer per
                        question (1-based, 0 = none). Graded against the
                        session kept on the server (ply.rhylibQuiz); a
                        reply without one is ignored. Rate 1/s.
      roster.quizres    server -> that cadet: UInt 6 right, UInt 6 asked,
                        Bool passed, UInt 3 tries left (0 = locked out),
                        UInt 16 seconds locked out.
      roster.quizget    client -> server, empty: staff ask for the list
                        (rhylib.roster.quiz). Rate 1/s.
      roster.quizlist   server -> those staff: UInt 32 length, compressed
                        JSON list { { q, a = {..}, c }, ... }.
      roster.quizsave   client -> server: UInt 32 length, compressed JSON
                        list (the whole list). Checked: permission, at most
                        R.QUIZ_MAX questions, text lengths, 2-6 answers,
                        c an answer. Rate 1/s.

    Saved: Data "roster_quiz" "list" = the list (missing = R.QUIZ_STARTER);
    Data "roster_quiz" "wait" = { ["s"..sid] = os.time() the lock-out ends };
    Data "roster_quiz" "tries" = { ["s"..sid] = failed tries in a row }.
    quizTries failed tries in a row (a started quiz never answered counts)
    lock the cadet out for quizRetry s and call the instructors online
    for them (R.CallTrainers, sv_10_roster.lua).
    Player NW2Bool rhylib_quizFailed (failed since joining, or locked out).
    Training instructors (rhylib_trainer) are saved per map through
    Rhylib.Perma.Placements("roster"): Data "roster_places" / <map>
    (console rhylib_trainer_save).
]]

local R = Rhylib.Roster
local Data = Rhylib.Data

-- A starting set (server only: clients never get the answers) until staff write their own (Staff > Training quiz).
-- { q = question, a = { answers }, c = the right one (index) }
R.QUIZ_STARTER = {
    { q = "An officer gives you an order. What do you do?", a = { "Acknowledge it and carry it out", "Ask why first", "Wait until someone else does it", "Ignore it if you're busy" }, c = 1 },
    { q = "How do you answer a Sergeant who calls your name?", a = { "\"Sir, yes sir\" (or \"Sergeant\")", "\"What?\"", "\"Yeah\"", "Say nothing" }, c = 1 },
    { q = "What does \"Roger\" mean on the radio?", a = { "Message received and understood", "Repeat that", "I'm in trouble", "Over and out" }, c = 1 },
    { q = "Someone steps into your line of fire. What do you do?", a = { "Stop firing until the shot is clear", "Keep shooting", "Shout at them and keep firing", "Throw a grenade instead" }, c = 1 },
    { q = "How do you carry your weapon on base?", a = { "Lowered, on safety", "Aimed at the door", "Firing at targets you like", "It doesn't matter" }, c = 1 },
    { q = "You're hurt and down in a fight. What do you do?", a = { "Call for a medic and wait for help", "Leave the game", "Shout over everyone on the radio", "Nothing, it's over" }, c = 1 },
    { q = "Who do you report to first?", a = { "Your squad leader", "Anyone you like", "A droid", "Nobody" }, c = 1 },
    { q = "The squad is marching in formation. Where are you?", a = { "In your place in the formation", "Running ahead to scout", "Wherever you like", "Back at base" }, c = 1 },
}

-- Most questions in one quiz (the whole quiz goes in one net message).
local QUIZ_ASK_MAX = 30
-- An open quiz nobody answered: after this it counts as a failed try.
local QUIZ_EXPIRE = 600

for _, n in ipairs({ "roster.quiz", "roster.quizres", "roster.quizlist" }) do Rhylib.Net.Register(n) end

-- (forward: a failed try and the quiz sender, defined below)
local failTry, sendQuiz

local function sid(ply) return ply:SteamID64() or "" end

-- R.QuizList() -> the questions (the saved list, else the starter set).
function R.QuizList()
    local list = Data.Get("roster_quiz", "list")
    if istable(list) and #list > 0 then return list end
    return R.QUIZ_STARTER
end

-- Is one question well formed?
local function valid(e)
    if not (istable(e) and isstring(e.q) and istable(e.a)) then return false end
    local q = string.Trim(e.q)
    if q == "" or (utf8.len(q) or #q) > R.QUIZ_Q_LEN then return false end
    local n = #e.a
    if n < 2 or n > 6 then return false end
    for i = 1, n do
        if not isstring(e.a[i]) or string.Trim(e.a[i]) == "" or (utf8.len(e.a[i]) or #e.a[i]) > R.QUIZ_A_LEN then return false end
    end
    local c = tonumber(e.c)
    return c ~= nil and c >= 1 and c <= n and math.floor(c) == c
end

local function waitLeft(ply)
    local t = Data.Get("roster_quiz", "wait")
    local at = istable(t) and tonumber(t["s" .. sid(ply)]) or 0
    return math.max(0, at - os.time())
end

-- Failed tries in a row ("s"..sid -> n), reset by passing or a lock-out.
local function getTries(ply)
    local t = Data.Get("roster_quiz", "tries")
    return istable(t) and tonumber(t["s" .. sid(ply)]) or 0
end
local function setTries(ply, n)
    local t = Data.Get("roster_quiz", "tries")
    if not istable(t) then t = {} end
    t["s" .. sid(ply)] = n > 0 and n or nil
    if next(t) then Data.Set("roster_quiz", "tries", t) else Data.Delete("roster_quiz", "tries") end
end

local function setWait(ply, secs)
    local t = Data.Get("roster_quiz", "wait")
    if not istable(t) then t = {} end
    local now = os.time()
    -- (old entries out)
    for k, v in pairs(t) do if (tonumber(v) or 0) < now then t[k] = nil end end
    t["s" .. sid(ply)] = now + secs
    Data.Set("roster_quiz", "wait", t)
end

-- A failed try: after quizTries in a row, locked out for quizRetry s
-- and the instructors online are called for them (R.CallTrainers).
-- -> tries left (0 = locked out), seconds locked out.
function failTry(ply, quiet)
    ply:SetNW2Bool("rhylib_quizFailed", true)
    local most = math.max(1, math.floor(R.Cfg("quizTries")))
    local n = getTries(ply) + 1
    if n < most then
        setTries(ply, n)
        return most - n, 0
    end
    setTries(ply, 0)
    local retry = math.max(0, math.floor(R.Cfg("quizRetry")))
    setWait(ply, retry)
    if R.CallTrainers and not quiet then R.CallTrainers(ply, true) end   -- (quiet: they left)
    return 0, retry
end

-- R.QuizOn() -> the quiz can be taken (setting on, questions on the list).
function R.QuizOn()
    return R.Cfg("quiz") and #R.QuizList() > 0
end

-- Sends a quiz session's questions (answers already shuffled) to the cadet.
function sendQuiz(ply, s)
    Rhylib.Net.Start("roster.quiz")
    net.WriteUInt(#s.qs, 6)
    for _, e in ipairs(s.qs) do
        net.WriteString(e.q)
        net.WriteUInt(#e.a, 3)
        for _, a in ipairs(e.a) do net.WriteString(a) end
    end
    net.Send(ply)
end

-- R.QuizStart(ply): a cadet starts the quiz (pressing E on a training
-- instructor, entities/rhylib_trainer.lua).
function R.QuizStart(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    local me = R.Get(ply)
    if not me.has or me.trained then return end
    if not R.QuizOn() then return Rhylib.Notify(ply, "The basic training quiz is off: ask an instructor", "bad", "Roster") end
    -- (a quiz already open: the same one is sent again, so a window that
    -- never opened can't leave them stuck and there are no fresh questions
    -- to fish for; one left open past QUIZ_EXPIRE counts as a failed try)
    local open = ply.rhylibQuiz
    if open and CurTime() - open.at > QUIZ_EXPIRE then
        ply.rhylibQuiz = nil
        local left = failTry(ply)
        Rhylib.Notify(ply, left > 0 and ("Your last quiz was never finished and counted as a try: " .. left .. " left") or "Your last quiz was never finished and used your last try", "info", "Roster")
        open = nil
    end
    if open then
        sendQuiz(ply, open)
        return
    end
    local wait = waitLeft(ply)
    if wait > 0 then
        return Rhylib.Notify(ply, string.format("You can take the quiz again in %d min", math.ceil(wait / 60)), "bad", "Roster")
    end
    -- Pick the questions, shuffle the answers (remember where the right one went).
    local list = R.QuizList()
    local order = {}
    for i = 1, #list do order[i] = i end
    for i = #order, 2, -1 do local j = math.random(i) order[i], order[j] = order[j], order[i] end
    local n = math.min(math.max(1, math.floor(R.Cfg("quizCount"))), #order, QUIZ_ASK_MAX)
    local session = { right = {}, qs = {}, at = CurTime() }
    for i = 1, n do
        local e = list[order[i]]
        local idx = {}
        for k = 1, #e.a do idx[k] = k end
        for k = #idx, 2, -1 do local j = math.random(k) idx[k], idx[j] = idx[j], idx[k] end
        local shown = { q = e.q, a = {} }
        for k, src in ipairs(idx) do
            shown.a[k] = e.a[src]
            if src == e.c then session.right[i] = k end
        end
        session.qs[i] = shown
    end
    ply.rhylibQuiz = session
    sendQuiz(ply, session)
end

-- Training instructors stay where they're placed (made permanent with
-- the toolgun's Permanent tool; saved per map in Data "roster_places").
if Rhylib.Perma and Rhylib.Perma.Placements then
    R.TrainerPlaces = Rhylib.Perma.Placements("roster", {
        classes = { "rhylib_trainer" },
        dataModule = "roster_places",
        command = "rhylib_trainer_save",
        perm = "rhylib.roster.quiz",
    })
end

-- Net roster.quizclose (client -> server, empty): the cadet closed the
-- quiz window without finishing: that counts as a try (no restarting for
-- easier questions). Rate 2/s.
Rhylib.Net.Receive("roster.quizclose", function(ply)
    if not ply.rhylibQuiz then return end
    ply.rhylibQuiz = nil
    local left = failTry(ply)
    Rhylib.Notify(ply, left > 0 and ("Leaving the quiz counted as a try: " .. left .. " left") or "Leaving the quiz used your last try: instructors have been called for you", "info", "Roster")
end, { rate = 2, burst = 2 })

Rhylib.Net.Receive("roster.quizdone", function(ply)
    local s = ply.rhylibQuiz
    ply.rhylibQuiz = nil
    if not s then return end
    local n = net.ReadUInt(6)
    if n ~= #s.right then return end
    local right = 0
    for i = 1, n do
        if net.ReadUInt(3) == s.right[i] then right = right + 1 end
    end
    local me = R.Get(ply)
    if not me.has or me.trained then return end
    local need = math.ceil(n * math.Clamp(tonumber(R.Cfg("quizPass")) or 0.8, 0, 1) - 0.0001)
    local passed = right >= need
    local retry, left = 0, 0
    if passed then
        R.Train(sid(ply), ply:Nick(), ply:Nick() .. " passed basic training by the quiz (" .. right .. " of " .. n .. ")")
        setTries(ply, 0)
        ply:SetNW2Bool("rhylib_quizFailed", false)
        Rhylib.Notify(ply, string.format("You passed basic training (%d of %d right). Welcome, trooper.", right, n), "good", "Roster")
    else
        left, retry = failTry(ply)
        Rhylib.Notify(ply, left > 0 and string.format("%d of %d right: you need %d. %d tr%s left.", right, n, need, left, left == 1 and "y" or "ies")
            or string.format("%d of %d right: you need %d. No tries left: instructors have been called for you.", right, n, need), "bad", "Roster")
    end
    Rhylib.Net.Start("roster.quizres")
    net.WriteUInt(right, 6)
    net.WriteUInt(n, 6)
    net.WriteBool(passed)
    net.WriteUInt(math.min(left, 7), 3)
    net.WriteUInt(math.min(retry, 65535), 16)
    net.Send(ply)
end, { rate = 1, burst = 2 })

local function staff(ply, cb)
    Rhylib.Perms.Check(ply, "rhylib.roster.quiz", function(ok) if ok and IsValid(ply) then cb() end end)
end

local function sendList(ply)
    local data = util.Compress(util.TableToJSON(R.QuizList()) or "[]") or ""
    Rhylib.Net.Start("roster.quizlist")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.Send(ply)
end

Rhylib.Net.Receive("roster.quizget", function(ply)
    staff(ply, function() sendList(ply) end)
end, { rate = 1, burst = 2 })

Rhylib.Net.Receive("roster.quizsave", function(ply)
    local len = net.ReadUInt(32)
    if len <= 0 or len > 60000 then return end
    local raw = net.ReadData(len)
    staff(ply, function()
        local list = util.JSONToTable(util.Decompress(raw or "") or "")
        if not istable(list) or #list > R.QUIZ_MAX then
            return Rhylib.Notify(ply, "Quiz not saved: too many questions or a bad list", "bad", "Roster")
        end
        local clean = {}
        for i, e in ipairs(list) do
            if not valid(e) then
                return Rhylib.Notify(ply, "Quiz not saved: question " .. i .. " needs text, 2-6 answers and a right answer", "bad", "Roster")
            end
            local a = {}
            for k, v in ipairs(e.a) do a[k] = string.Trim(v) end
            clean[#clean + 1] = { q = string.Trim(e.q), a = a, c = math.floor(tonumber(e.c)) }
        end
        if #clean == 0 then Data.Delete("roster_quiz", "list") else Data.Set("roster_quiz", "list", clean) end
        Rhylib.Notify(ply, #clean == 0 and "Quiz list cleared: the starter questions are back" or ("Quiz saved: " .. #clean .. " questions"), "good", "Roster")
        sendList(ply)
    end)
end, { rate = 1, burst = 2 })

-- (back after failing: still waiting for a retry, so "Request basic
-- training" shows again)
Rhylib.Hook.Add("PlayerInitialSpawn", "roster.quiz", function(ply)
    timer.Simple(2, function()
        if IsValid(ply) and waitLeft(ply) > 0 then ply:SetNW2Bool("rhylib_quizFailed", true) end
    end)
end)

-- (leaving mid-quiz counts as a failed try, like closing it)
Rhylib.Hook.Add("PlayerDisconnected", "roster.quiz", function(ply)
    if ply.rhylibQuiz then
        ply.rhylibQuiz = nil
        failTry(ply, true)
    end
end)
