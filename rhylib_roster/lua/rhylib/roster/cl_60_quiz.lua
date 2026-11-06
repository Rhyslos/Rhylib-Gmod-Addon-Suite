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

    Look: the quiz window has a progress strip under the header (one
    segment per question), the question in big letters and the answers as
    cards with a letter box (A-F); the result shows the score big with a
    bar and the pass mark. The staff page: counts on top (questions, asked,
    to pass, NOT SAVED after a change), a band, numbered rows with the
    right answer in green.
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

local LETTERS = { "A", "B", "C", "D", "E", "F" }

-- The window frame, reused for the quiz, its result and the question editor.
local function frame(title, sub, w, h)
    local k = K()
    local s = k.S
    closeQuiz()
    local f = vgui.Create("EditablePanel")
    R.quizPanel = f
    f:SetSize(math.min(ScrW() - s(40), w or s(720)), math.min(ScrH() - s(40), h or s(540)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    local headH = s(40)
    f:DockPadding(s(20), headH + s(18), s(20), s(18))
    f.title, f.sub = title, sub
    function f:Paint(pw, ph)
        k.Plate(0, 0, pw, ph, { title = self.title, sub = self.sub, ticks = "all", header = headH, rule = self.rule })
        if self.progress then self:progress(pw, headH) end
        if self.centreText then
            draw.SimpleText(self.centreText, k.Font(16, 600), pw * 0.5, ph * 0.5, k.C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    return f
end

-- An answer card: a letter box, the answer (wrapping) and hover.
local function answerButton(parent, letter, text, fn)
    local k = K()
    local s = k.S
    local C = k.C
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:Dock(TOP)
    b:DockMargin(0, 0, 0, s(8))
    b:DockPadding(s(60), s(12), s(16), s(12))
    b:SetTall(s(48))
    function b:Paint(w, h)
        local hov = self:IsHovered()
        k.SetCol(hov and C.rowHover or C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(hov and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if hov then
            k.SetCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
        end
        local sz = s(30)
        k.SetCol(hov and C.accent or C.header)
        surface.DrawRect(s(14), math.floor((h - sz) * 0.5), sz, sz)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(s(14), math.floor((h - sz) * 0.5), sz, sz)
        draw.SimpleText(letter, k.Font(15, 800), s(14) + sz * 0.5, h * 0.5, hov and C.bg or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    local l = k.Label(b, text, 15, 500, C.text)
    l:Dock(TOP)
    l:SetMouseInputEnabled(false)
    -- (as tall as its text)
    function b:Think()
        local want = math.max(s(48), l:GetTall() + s(24))
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
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
    local C = k.C
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
    f.at = 1
    -- A segment per question under the header: done ones in the accent,
    -- the current one bright.
    function f:progress(pw, top)
        local n = #qs
        local x0, w0 = s(20), pw - s(40)
        local gap = s(3)
        local sw = (w0 - gap * (n - 1)) / n
        for i = 1, n do
            if i < self.at then k.SetCol(C.accent)
            elseif i == self.at and not self.centreText then k.SetCol(C.text)
            else k.SetCol(C.button) end
            surface.DrawRect(math.floor(x0 + (i - 1) * (sw + gap)), top + s(8), math.max(1, math.floor(sw)), s(4))
        end
    end
    local function show(i)
        f:Clear()
        f.at = i
        f.sub = string.format("Question %d of %d", i, #qs)
        local q = qs[i]
        local cap = vgui.Create("DPanel", f)
        cap:Dock(TOP)
        cap:SetTall(s(20))
        local capText = "Question " .. i
        function cap:Paint(w, h) k.Caps(capText, 0, h * 0.5, C.accent) end
        local l = k.Label(f, q.text, 20, 700)
        l:Dock(TOP)
        l:DockMargin(0, s(2), 0, s(18))
        local bar = vgui.Create("DPanel", f)
        bar:Dock(BOTTOM)
        bar:SetTall(s(30))
        bar:DockMargin(0, s(8), 0, 0)
        function bar:Paint(w, h)
            draw.SimpleText("Pick an answer", k.Font(12), w, h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local cancel = k.Button(bar, "Stop (counts as a try)", function() closeQuiz() end, { small = true, danger = true })
        cancel:Dock(LEFT)
        cancel:SetWide(s(210))
        local sp = k.Scroll(f)
        sp:Dock(FILL)
        for j, ans in ipairs(q.a) do
            local b = answerButton(sp, LETTERS[j] or tostring(j), ans, function()
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
                    f.at = #qs + 1
                    f.sub = "Checking your answers…"
                    f.centreText = "Checking your answers…"
                end
            end)
            b:DockMargin(0, 0, s(8), s(8))
        end
    end
    show(1)
end)

Rhylib.Net.Receive("roster.quizres", function()
    local right, n, passed, left, retry = net.ReadUInt(6), net.ReadUInt(6), net.ReadBool(), net.ReadUInt(3), net.ReadUInt(16)
    local k = K()
    if not k then return end
    local s = k.S
    local C = k.C
    local f = frame(passed and "Passed" or "Not passed yet", string.format("%d of %d right", right, n), s(640), s(440))
    f.rule = passed and C.good or C.warn
    local text = passed and "You passed basic training. You're a clone trooper now: a Sergeant or higher can add you to a battalion."
        or (left > 0 and string.format("You have %d tr%s left: press E on the instructor to take it again. Or press \"Request basic training\" on the Battalion page and an instructor will come to train you.", left, left == 1 and "y" or "ies")
            or ("No tries left: the instructors online have been called for you. Wait for one to come and train you." ..
                (retry > 0 and string.format(" You can take the quiz again in %d minutes.", math.ceil(retry / 60)) or "")))
    -- The score: big numbers, a bar with the pass mark.
    local pass = math.Clamp(tonumber(R.Cfg("quizPass")) or 0.8, 0, 1)
    local score = vgui.Create("DPanel", f)
    score:Dock(TOP)
    score:SetTall(s(120))
    score:DockMargin(0, 0, 0, s(16))
    local big, small = tostring(right), "/ " .. n
    local frac = n > 0 and right / n or 0
    local passText = "PASS MARK " .. math.Round(pass * 100) .. "%"
    function score:Paint(w, h)
        local col = passed and C.good or C.warn
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(col, 22)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(col)
        surface.DrawRect(0, 0, s(4), h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.Caps(passed and "Basic training passed" or "Score", s(20), s(22), col)
        draw.SimpleText(big, k.Font(46, 800), s(20), s(64), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(k.Font(46, 800))
        local bw = surface.GetTextSize(big)
        draw.SimpleText(small, k.Font(22, 700), s(28) + bw, s(70), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local bx, by, bwid = s(20), h - s(24), w - s(40)
        k.SetCol(C.button)
        surface.DrawRect(bx, by, bwid, s(6))
        k.SetCol(col)
        surface.DrawRect(bx, by, math.floor(bwid * frac), s(6))
        k.SetCol(C.text)
        surface.DrawRect(bx + math.floor(bwid * pass) - 1, by - s(4), 2, s(14))
        draw.SimpleText(passText, k.Font(11, 700), bx + bwid * pass, by - s(14), C.label, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local l = k.Label(f, text, 15, 400)
    l:Dock(TOP)
    local b = k.Button(f, "Close", function() closeQuiz() end, { accent = true })
    b:Dock(BOTTOM)
    b:SetTall(s(38))
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
    local C = k.C
    local e = i and edit.list[i] or { q = "", a = { "", "" }, c = 1 }
    local f = frame(i and ("Question " .. i) or "New question", "The question, its answers (2-6) and the right one", s(720), s(600))
    f:SetKeyboardInputEnabled(true)
    local cap = vgui.Create("DPanel", f)
    cap:Dock(TOP)
    cap:SetTall(s(20))
    function cap:Paint(w, h) k.Caps("Question", 0, h * 0.5) end
    local qe = k.TextEntry(f, "The question")
    qe:SetText(e.q)
    qe:Dock(TOP)
    qe:SetTall(s(36))
    qe:DockMargin(0, s(2), 0, s(14))
    local cap2 = vgui.Create("DPanel", f)
    cap2:Dock(TOP)
    cap2:SetTall(s(20))
    function cap2:Paint(w, h)
        k.Caps("Answers", 0, h * 0.5)
        draw.SimpleText("Empty ones are dropped", k.Font(12), w, h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local right = e.c or 1
    local boxes = {}
    for n = 1, 6 do
        local row = vgui.Create("DPanel", f)
        row:Dock(TOP)
        row:SetTall(s(40))
        row:DockMargin(0, s(4), 0, 0)
        row:DockPadding(s(46), s(5), s(5), s(5))
        local letter = LETTERS[n]
        function row:Paint(w, h)
            local on = right == n
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            if on then
                k.SetCol(C.good, 24)
                surface.DrawRect(0, 0, w, h)
                k.SetCol(C.good)
                surface.DrawRect(0, 0, s(3), h)
            end
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(letter, k.Font(15, 800), s(24), h * 0.5, on and C.good or C.label, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local pick = k.Button(row, function() return right == n and "Right" or "Mark right" end, function() right = n end,
            { small = true, selected = function() return right == n end, col = C.good })
        pick:Dock(RIGHT)
        pick:SetWide(s(110))
        pick:DockMargin(s(6), 0, 0, 0)
        local te = k.TextEntry(row, "Answer " .. n .. (n > 2 and " (optional)" or ""))
        te:SetText(e.a[n] or "")
        te:Dock(FILL)
        boxes[n] = te
    end
    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(36))
    local cancel = k.Button(bar, "Cancel", function() closeQuiz() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(120))
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
        edit.dirty = true
        closeQuiz()
        if fillPage then fillPage() end
    end, { accent = true })
    ok:Dock(RIGHT)
    ok:SetWide(s(140))
    ok:DockMargin(0, 0, s(8), 0)
end

fillPage = function()
    local k = K()
    local p = edit.page
    if not (k and IsValid(p)) then return end
    local s = k.S
    local C = k.C
    local D = R.Draw
    p:Clear()
    local top = vgui.Create("DPanel", p)
    top:Dock(TOP)
    top:SetTall(s(44))
    top:DockMargin(0, 0, 0, s(10))
    top:DockPadding(0, s(5), 0, s(5))
    if not edit.list then
        top.Paint = nil
        local l = k.Label(p, "Loading…", 14, 400, C.textDim)
        l:Dock(TOP)
        return
    end
    local nAsk = math.min(R.Cfg("quizCount"), #edit.list)
    local passPct = math.Round((tonumber(R.Cfg("quizPass")) or 0.8) * 100)
    local stats = { { tostring(#edit.list), "Questions" }, { tostring(nAsk), "Asked" }, { passPct .. "%", "To pass" } }
    function top:Paint(w, h)
        local x = 0
        for _, st in ipairs(stats) do
            draw.SimpleText(st[1], k.Font(20, 800), x, h * 0.36, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            k.Caps(st[2], x, h * 0.80)
            x = x + s(96)
        end
        if edit.dirty then D.Chip("NOT SAVED", x + s(8), h * 0.5, C.warn) end
    end
    local save = k.Button(top, "Save", function() sendSave() end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(120))
    local add = k.Button(top, "Add question", function()
        if #edit.list >= R.QUIZ_MAX then return Rhylib.Notify(nil, "That's the most questions the quiz can hold", "bad", "Roster") end
        editor(nil)
    end)
    add:Dock(RIGHT)
    add:SetWide(s(160))
    add:DockMargin(0, 0, s(8), 0)
    local info = k.Label(p, string.format("Cadets get %d of these at random and need %d%% right to pass. Nothing is saved until you press Save.", nAsk, passPct), 13, 400, C.textDim)
    info:Dock(TOP)
    info:DockMargin(0, 0, 0, s(8))
    local sc = k.Scroll(p)
    sc:Dock(FILL)
    local band = D.Band(sc, "Questions", nil, function() return #edit.list .. " in the list" end)
    band:Dock(TOP)
    band:DockMargin(0, 0, s(8), 0)
    if #edit.list == 0 then
        local l = k.Label(sc, "No questions: saving an empty list brings back the starter questions.", 13, 400, C.textDim)
        l:Dock(TOP)
        l:DockMargin(s(4), s(8), s(8), 0)
    end
    for i, e in ipairs(edit.list) do
        local title = utf8cut(e.q, 80)
        local rightText = "Right: " .. utf8cut(tostring(e.a[e.c] or "?"), 60)
        local nText = #e.a .. " ANSWERS"
        local num = tostring(i)
        local row = vgui.Create("DPanel", sc)
        row:Dock(TOP)
        row:SetTall(s(54))
        row:DockMargin(0, 0, s(8), 0)
        row:DockPadding(s(12), s(14), s(12), s(14))
        function row:Paint(w, h)
            k.SetCol(self:IsHovered() and C.rowHover or (i % 2 == 0 and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.edgeDark)
            surface.DrawRect(0, h - 1, w, 1)
            local sz = s(30)
            k.SetCol(C.header)
            surface.DrawRect(s(12), (h - sz) * 0.5, sz, sz)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(s(12), (h - sz) * 0.5, sz, sz)
            draw.SimpleText(num, k.Font(13, 800), s(12) + sz * 0.5, h * 0.5, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            local x = s(12) + sz + s(12)
            local room = w - x - s(220)
            draw.SimpleText(k.Fit(title, k.Font(14, 700), room), k.Font(14, 700), x, h * 0.34, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local rf = k.Font(12)
            local rt = k.Fit(rightText, rf, room - s(100))
            draw.SimpleText(rt, rf, x, h * 0.70, C.good, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetFont(rf)
            D.Chip(nText, x + surface.GetTextSize(rt) + s(10), h * 0.70, C.label)
        end
        local rm = k.Button(row, "Remove", function()
            table.remove(edit.list, i)
            edit.dirty = true
            fillPage()
        end, { small = true, danger = true })
        rm:Dock(RIGHT)
        rm:SetWide(s(96))
        local ed = k.Button(row, "Edit", function() editor(i) end, { small = true, accent = true })
        ed:Dock(RIGHT)
        ed:SetWide(s(96))
        ed:DockMargin(0, 0, s(6), 0)
    end
end

Rhylib.Net.Receive("roster.quizlist", function()
    local len = net.ReadUInt(32)
    local list = util.JSONToTable(util.Decompress(net.ReadData(len) or "") or "")
    edit.list = istable(list) and list or {}
    edit.dirty = false
    fillPage()
end)

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage) then return end
    Menus.AddPage("rosterquiz", {
        title = "Training quiz",
        order = 250,
        section = "staff",
        icon = "quiz",
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
