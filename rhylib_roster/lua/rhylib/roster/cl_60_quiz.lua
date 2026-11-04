--[[
    Basic training quiz (client): the quiz window and the staff editor.
    See sh_60_quiz.lua for how it plays and sv_60_quiz.lua for the nets.

    Quiz window (net roster.quiz): one question at a time with its
    answers as buttons, "Question 3 of 10" at the top; the last answer
    sends roster.quizdone. The result (roster.quizres) shows the score and
    what's next. Esc closes it (UI closer "roster.quiz"; a closed quiz
    counts as not taken, so nothing is lost).

    Staff > Training quiz page (permission rhylib.roster.quiz, needs
    rhylib_menus): the question list (roster.quizget / roster.quizlist),
    each with Edit and Remove; Add question; Save sends the whole list
    (roster.quizsave). The editor: the question, up to 6 answers (empty
    ones are dropped), and which one is right.
]]

local R = Rhylib.Roster

local function K() return Rhylib.UI and Rhylib.UI.Kit end

R.quizPanel = R.quizPanel
local function closeQuiz()
    if IsValid(R.quizPanel) then R.quizPanel:Remove() return true end
    return false
end
local UI = Rhylib.UI
if UI and UI.RegisterCloser then UI.RegisterCloser("roster.quiz", closeQuiz) end

-- The window frame, reused for the quiz and its result.
local function frame(title, sub)
    local k = K()
    local s = k.S
    closeQuiz()
    local f = vgui.Create("EditablePanel")
    R.quizPanel = f
    f:SetSize(s(640), s(470))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(s(18), s(56), s(18), s(16))
    f.title, f.sub = title, sub
    function f:Paint(w, h)
        k.Plate(0, 0, w, h, { title = self.title, sub = self.sub, ticks = "all", header = s(40) })
    end
    return f
end

Rhylib.Net.Receive("roster.quiz", function()
    local qs = {}
    for i = 1, net.ReadUInt(6) do
        local q = { text = net.ReadString(), a = {} }
        for j = 1, net.ReadUInt(3) do q.a[j] = net.ReadString() end
        qs[i] = q
    end
    local k = K()
    if not k or #qs == 0 then return end
    local s = k.S
    local picks = {}
    -- (the same quiz sent again, E on the instructor with it open: the old
    -- window goes without telling the server it was left)
    if IsValid(R.quizPanel) then R.quizPanel.done = true end
    local f = frame("Basic training quiz", "")
    -- (closed before the last answer: the server counts it as a try)
    function f:OnRemove()
        if not self.done then
            Rhylib.Net.Start("roster.quizclose")
            net.SendToServer()
        end
    end
    local function show(i)
        f:Clear()
        f.sub = string.format("Question %d of %d", i, #qs)
        local q = qs[i]
        local l = k.Label(f, q.text, 18, 600)
        l:SetWrap(true)
        l:SetAutoStretchVertical(true)
        l:Dock(TOP)
        l:DockMargin(0, 0, 0, s(16))
        for j, ans in ipairs(q.a) do
            local b = k.Button(f, ans, function()
                picks[i] = j
                if i < #qs then
                    show(i + 1)
                else
                    f.done = true
                    Rhylib.Net.Start("roster.quizdone")
                    net.WriteUInt(#qs, 6)
                    for n = 1, #qs do net.WriteUInt(picks[n] or 0, 3) end
                    net.SendToServer()
                    f:Clear()
                    f.sub = "Checking your answers…"
                end
            end)
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, s(8))
        end
        local cancel = k.Button(f, "Stop (counts as a try)", function() closeQuiz() end, { small = true })
        cancel:Dock(BOTTOM)
    end
    show(1)
end)

Rhylib.Net.Receive("roster.quizres", function()
    local right, n, passed, left, retry = net.ReadUInt(6), net.ReadUInt(6), net.ReadBool(), net.ReadUInt(3), net.ReadUInt(16)
    local k = K()
    if not k then return end
    local s = k.S
    local f = frame(passed and "Passed" or "Not passed yet", string.format("%d of %d right", right, n))
    local text = passed and "You passed basic training. You're a clone trooper now: a Sergeant or higher can add you to a battalion."
        or (left > 0 and string.format("You have %d tr%s left: press E on the instructor to take it again. Or press \"Request basic training\" on the Battalion page and an instructor will come to train you.", left, left == 1 and "y" or "ies")
            or ("No tries left: the instructors online have been called for you. Wait for one to come and train you." ..
                (retry > 0 and string.format(" You can take the quiz again in %d minutes.", math.ceil(retry / 60)) or "")))
    local l = k.Label(f, text, 16, 400)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:Dock(TOP)
    local b = k.Button(f, "Close", function() closeQuiz() end, { accent = true })
    b:Dock(BOTTOM)
    b:SetTall(s(34))
    -- (the Battalion page shows the right buttons next time it opens)
end)

--------------------------------------------------------------------------
-- Staff > Training quiz
--------------------------------------------------------------------------

local edit = { list = nil, page = nil }   -- the list being edited, the page panel

-- The first n letters (not bytes, so no letter is cut in half), "…" if cut.
local function utf8cut(s, n)
    local len = utf8.len(s)
    if not len or len <= n then return s end
    local p = utf8.offset(s, n + 1)
    return p and (string.sub(s, 1, p - 1) .. "…") or s
end

local function sendSave()
    local data = util.Compress(util.TableToJSON(edit.list or {}) or "[]") or ""
    if #data > 60000 then
        Rhylib.Notify(nil, "The quiz is too long to send", "bad", "Roster")
        return
    end
    Rhylib.Net.Start("roster.quizsave")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.SendToServer()
end

local fillPage

-- The editor for one question (i = its place, nil = a new one).
local function editor(i)
    local k = K()
    local s = k.S
    local e = i and edit.list[i] or { q = "", a = { "", "" }, c = 1 }
    local f = frame(i and ("Question " .. i) or "New question", "The question, its answers (2-6) and the right one")
    f:SetKeyboardInputEnabled(true)
    f:SetTall(s(560))
    f:Center()
    local qe = k.TextEntry(f, "The question")
    qe:SetText(e.q)
    qe:Dock(TOP)
    qe:DockMargin(0, 0, 0, s(10))
    local right = e.c or 1
    local boxes = {}
    for n = 1, 6 do
        local row = vgui.Create("DPanel", f)
        row.Paint = nil
        row:Dock(TOP)
        row:SetTall(s(32))
        row:DockMargin(0, 0, 0, s(4))
        local pick = k.Button(row, "Right", function() right = n end, { small = true, selected = function() return right == n end })
        pick:Dock(RIGHT)
        pick:SetWide(s(80))
        pick:DockMargin(s(6), 0, 0, 0)
        local te = k.TextEntry(row, "Answer " .. n .. (n > 2 and " (optional)" or ""))
        te:SetText(e.a[n] or "")
        te:Dock(FILL)
        boxes[n] = te
    end
    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    local cancel = k.Button(bar, "Cancel", function() closeQuiz() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(110))
    local ok = k.Button(bar, "Done", function()
        local a, map = {}, {}
        for n = 1, 6 do
            local t = string.Trim(boxes[n]:GetValue() or "")
            if t ~= "" then a[#a + 1] = utf8cut(t, R.QUIZ_A_LEN - 3) map[n] = #a end
        end
        local q = utf8cut(string.Trim(qe:GetValue() or ""), R.QUIZ_Q_LEN - 3)
        if q == "" or #a < 2 or not map[right] then
            Rhylib.Notify(nil, "A question needs text, at least two answers, and the right one filled in", "bad", "Roster")
            return
        end
        local item = { q = q, a = a, c = map[right] }
        if i then edit.list[i] = item else edit.list[#edit.list + 1] = item end
        closeQuiz()
        if fillPage then fillPage() end
    end, { accent = true })
    ok:Dock(RIGHT)
    ok:SetWide(s(110))
    ok:DockMargin(0, 0, s(8), 0)
end

fillPage = function()
    local k = K()
    local p = edit.page
    if not (k and IsValid(p)) then return end
    local s = k.S
    p:Clear()
    local top = vgui.Create("DPanel", p)
    top.Paint = nil
    top:Dock(TOP)
    top:SetTall(s(34))
    top:DockMargin(0, 0, 0, s(8))
    if not edit.list then
        local l = k.Label(p, "Loading…", 14, 400, k.C.textDim)
        l:Dock(TOP)
        return
    end
    local save = k.Button(top, "Save", function() sendSave() end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(110))
    local add = k.Button(top, "Add question", function()
        if #edit.list >= R.QUIZ_MAX then return Rhylib.Notify(nil, "That's the most questions the quiz can hold", "bad", "Roster") end
        editor(nil)
    end)
    add:Dock(RIGHT)
    add:SetWide(s(150))
    add:DockMargin(0, 0, s(8), 0)
    local info = k.Label(top, string.format("%d questions · cadets get %d at random, %d%% to pass · not saved until you press Save",
        #edit.list, math.min(R.Cfg("quizCount"), #edit.list), math.Round((tonumber(R.Cfg("quizPass")) or 0.8) * 100)), 13, 400, k.C.textDim)
    info:Dock(FILL)
    local sc = k.Scroll(p)
    sc:Dock(FILL)
    for i, e in ipairs(edit.list) do
        local title = utf8cut(e.q, 80)
        local row = k.Row(sc, i .. ". " .. title, "Right: " .. utf8cut(tostring(e.a[e.c] or "?"), 60) .. " · " .. #e.a .. " answers")
        row:Dock(TOP)
        row:DockMargin(0, 0, s(8), s(3))
        row.right:SetWide(s(190))
        local rm = k.Button(row.right, "Remove", function()
            table.remove(edit.list, i)
            fillPage()
        end, { small = true })
        rm:Dock(RIGHT)
        rm:SetWide(s(90))
        local ed = k.Button(row.right, "Edit", function() editor(i) end, { small = true })
        ed:Dock(RIGHT)
        ed:SetWide(s(90))
        ed:DockMargin(0, 0, s(6), 0)
    end
end

Rhylib.Net.Receive("roster.quizlist", function()
    local len = net.ReadUInt(32)
    local list = util.JSONToTable(util.Decompress(net.ReadData(len) or "") or "")
    edit.list = istable(list) and list or {}
    fillPage()
end)

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage) then return end
    Menus.AddPage("rosterquiz", {
        title = "Training quiz",
        order = 66,
        group = "staff",
        visible = function()
            local me = LocalPlayer()
            if not IsValid(me) then return false end
            local A = Rhylib.Admin
            if A and A.Has then return A.Has(me, "rhylib.roster.quiz", "admin") end
            return me:IsAdmin()
        end,
        build = function(page)
            local p = vgui.Create("DPanel", page)
            p.Paint = nil
            p:Dock(FILL)
            edit.page, edit.list = p, nil
            fillPage()
            Rhylib.Net.Start("roster.quizget")
            net.SendToServer()
        end,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "roster.quizpage", addPage)
