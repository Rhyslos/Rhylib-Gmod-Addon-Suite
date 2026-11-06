--[[
    F4 menu (DarkRP), as pages of the pause menu: F4 opens the pause menu
    on Jobs (a fresh F4 press closes it). Replaces DarkRP's own F4 menu.
      Jobs       a header ("You are <job>" in its colour, rank and basic
                 training with rhylib_roster; a search box; "Only jobs I
                 can take"). Left: jobs by DarkRP category, each a colour
                 band (diamond, name, N online) over rows in two columns
                 (icon, name, a sub line: your job / short description /
                 why it's locked, slots). Right: the model preview (< >
                 for several models; wears your skin, picked on Trooper >
                 Appearance), battalion, name, description, weapons as
                 chips, a checklist (ticks met, "!" notes, crosses block),
                 salary (money on), slots bar and the button in the job's
                 colour: Become / Start a vote / Update job / the reason.
      Shop       the same look: kinds (entities, single weapons,
                 shipments, ammo, vehicles you can buy as your job) as
                 tabs plus a search box; items by category on the left,
                 the picked one on the right (model, facts, price, your
                 money while money is on, Buy). Only shown when the
                 server has anything to sell.
      Trooper > Overview ("character")  your model, name, battalion,
                 rank, job and qualifications (rhylib_roster); tiles to
                 Skills (points left, rhylib_skills), Jobs and Battalion;
                 the service record (clone number, kills, carried weight;
                 money and salary only while money is in use,
                 R.MoneyOn); quick actions (appearance, inventory, class,
                 the money / door commands while money is on, RP name
                 only without rhylib_roster).

    Everything runs DarkRP's own console commands ("darkrp <command>"),
    so DarkRP checks money, limits and jobs on the server as usual.
    Without DarkRP, F4 does what it did before.

    Client only. Pages: "jobs" (section you, order 30, key F4), "shop"
    (you, 32), "character" (the Overview tab of the Trooper group, order
    10); each only while DarkRP is loaded. Adds Menus.ToggleF4,
    Menus.SkillPointsLeft(ply) (left, total; nil without rhylib_skills;
    math.huge = free) and console command
    rhylib_f4. Replaces DarkRP.openF4Menu / toggleF4Menu / closeF4Menu /
    getF4MenuPanel so DarkRP's own calls open ours.
    The client-side checks (job full, customCheck, can afford) only grey
    out buttons; DarkRP decides on the server.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local function isDarkRP() return DarkRP ~= nil and RPExtraTeams ~= nil end

local function money(n)
    if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(n or 0) end
    return "$" .. tostring(n or 0)
end

local function myMoney()
    local ply = LocalPlayer()
    return ply.getDarkRPVar and (ply:getDarkRPVar("money") or 0) or 0
end

-- Is DarkRP money in use? rhylib_roster's money setting (R.MoneyOn); without
-- rhylib_roster always yes.
local function moneyOn()
    local Ro = Rhylib.Roster
    return not (Ro and Ro.MoneyOn) or Ro.MoneyOn()
end

local function canAfford(price)
    local ply = LocalPlayer()
    if ply.canAfford then return ply:canAfford(price) end
    return myMoney() >= (price or 0)
end

local function categories(kind)
    if not (DarkRP and DarkRP.getCategories) then return {} end
    return DarkRP.getCategories()[kind] or {}
end

-- A server's customCheck can error on the client; treat that as "no".
local function check(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res
end

-- Can the local player see / use this shop item as their job?
local function allowedItem(item)
    local ply = LocalPlayer()
    if item.allowed and istable(item.allowed) and #item.allowed > 0 and not table.HasValue(item.allowed, ply:Team()) then return false end
    if item.customCheck and not check(item.customCheck, ply) then return false end
    return true
end

-- How many can do this job, for display (0 = no limit). A max below 1 is
-- a share of the players.
local function jobLimit(job)
    local max = job.max or 0
    if max > 0 and max % 1 ~= 0 then return math.floor(player.GetCount() * max) end
    return max
end

-- Full, the way DarkRP decides it on the server.
local function jobFull(job, n)
    local max = job.max or 0
    if max == 0 then return false end
    if max % 1 == 0 then return n >= max end
    return (n + 1) / math.max(1, player.GetCount()) > max
end

local function jobBlockedNow(job, n)
    local ply = LocalPlayer()
    if ply:Team() == job.team then return "Your current job" end
    if jobFull(job, n) then return "Full" end
    if job.NeedToChangeFrom then
        local from = istable(job.NeedToChangeFrom) and job.NeedToChangeFrom or { job.NeedToChangeFrom }
        if not table.HasValue(from, ply:Team()) then return "Needs another job first" end
    end
    if job.customCheck and not check(job.customCheck, ply) then
        local msg = job.CustomCheckFailMsg
        if isfunction(msg) then msg = check(msg, ply, job) end
        return isstring(msg) and msg or "Not available to you"
    end
    if job.admin == 1 and not ply:IsAdmin() then return "Admins only" end
    if job.admin and job.admin > 1 and not ply:IsSuperAdmin() then return "Superadmins only" end
    return nil
end

-- Per job: players in it and why it's blocked, refreshed twice a second
-- (not every frame; the job list paints many of these).
local jobCache, jobCacheTime = {}, 0
local function jobState(job)
    if RealTime() - jobCacheTime > 0.5 then
        jobCache, jobCacheTime = {}, RealTime()
    end
    local st = jobCache[job]
    if not st then
        local n = team.NumPlayers(job.team)
        st = { count = n, limit = jobLimit(job), full = jobFull(job, n), blocked = jobBlockedNow(job, n) }
        jobCache[job] = st
    end
    return st
end
local function jobBlocked(job) return jobState(job).blocked end

local function needsVote(job)
    return job.vote or (job.RequiresVote and check(job.RequiresVote, LocalPlayer(), job.team))
end

local function becomeJob(job)
    RunConsoleCommand("darkrp", (needsVote(job) and "vote" or "") .. job.command)
end

local function firstModel(job)
    local m = job.model
    if istable(m) then return m[1], m end
    return m, nil
end

--------------------------------------------------------------------------
-- Look shared by Jobs and Shop: colours and small drawing helpers
--------------------------------------------------------------------------

-- Theme tokens "f4.<key>"; the ones that are the kit's text / state
-- colours use the kit tokens.
local Col = Rhylib.UI.Col
local T = {
    inset = Col("f4.inset", 14, 16, 15), side = Col("f4.side", 18, 20, 19), card = Col("f4.card", 22, 25, 23),
    tile = Col("f4.tile", 26, 30, 27), sel = Col("f4.sel", 27, 37, 48), selEdge = Col("f4.selEdge", 47, 58, 68),
    edge = Col("f4.edge", 42, 45, 41), faint = Col("f4.faint", 31, 35, 32), black = Col("f4.black", 0, 0, 0),
    text = C.text, text2 = Col("f4.text2", 201, 200, 192), dim = C.textDim,
    label = Col("f4.label", 138, 140, 132), off = Col("f4.off", 111, 116, 109),
    blue = C.accent, amber = C.warn, red = C.bad, green = C.good,
    dark = Col("f4.dark", 20, 20, 19), lockSub = Col("f4.lockSub", 200, 176, 122), lockIcon = Col("f4.lockIcon", 58, 64, 59),
    noteText = Col("f4.noteText", 232, 207, 154), badText = Col("f4.badText", 240, 149, 149),
}
local GRAD_L, GRAD_R = Material("vgui/gradient-l"), Material("vgui/gradient-r")
local INF = "∞"

-- (one vertex table each, filled per draw: no tables made in Paint)
local DIA = { {}, {}, {}, {} }
local function diamond(cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K.SetCol(col)
    surface.DrawPoly(DIA)
end

local TRI = { {}, {}, {} }
local function chevron(cx, cy, r, left, col)
    if left then
        TRI[1].x, TRI[1].y = cx + r * 0.6, cy - r
        TRI[2].x, TRI[2].y = cx + r * 0.6, cy + r
        TRI[3].x, TRI[3].y = cx - r * 0.6, cy
    else
        TRI[1].x, TRI[1].y = cx - r * 0.6, cy - r
        TRI[2].x, TRI[2].y = cx + r * 0.6, cy
        TRI[3].x, TRI[3].y = cx - r * 0.6, cy + r
    end
    draw.NoTexture()
    K.SetCol(col)
    surface.DrawPoly(TRI)
end

-- A 2 px line (two 1 px lines side by side).
local function line2(x1, y1, x2, y2)
    surface.DrawLine(x1, y1, x2, y2)
    surface.DrawLine(x1 + 1, y1, x2 + 1, y2)
end

local function drawTick(x, y, sz)
    line2(x + sz * 0.24, y + sz * 0.52, x + sz * 0.42, y + sz * 0.70)
    line2(x + sz * 0.42, y + sz * 0.70, x + sz * 0.76, y + sz * 0.30)
end

-- A requirement mark: "good" a green tick, "note" an amber "!", "bad" a red cross.
local MARK_BG = { good = T.green, note = T.amber, bad = T.red }
local MARK_TEXT = { good = T.text, note = T.noteText, bad = T.badText }
local function drawMark(kind, x, y, sz)
    K.SetCol(MARK_BG[kind] or T.dim)
    surface.DrawRect(x, y, sz, sz)
    K.SetCol(T.dark)
    if kind == "good" then
        drawTick(x, y, sz)
    elseif kind == "bad" then
        line2(x + sz * 0.3, y + sz * 0.3, x + sz * 0.68, y + sz * 0.7)
        line2(x + sz * 0.68, y + sz * 0.3, x + sz * 0.3, y + sz * 0.7)
    else
        draw.SimpleText("!", K.Font(12, 900), x + sz * 0.5, y + sz * 0.5, T.dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- A dark band tinted from the left in col (category bands, previews).
local function tintLeft(x, y, w, h, col, a)
    K.SetCol(col, a)
    surface.SetMaterial(GRAD_L)
    surface.DrawTexturedRect(x, y, w, h)
end

-- A soft glow in the middle of a box (the model preview).
local function glow(w, h, col, a)
    K.SetCol(col, a)
    surface.SetMaterial(GRAD_R)
    surface.DrawTexturedRect(0, 0, math.ceil(w * 0.5), h)
    surface.SetMaterial(GRAD_L)
    surface.DrawTexturedRect(math.floor(w * 0.5), 0, math.ceil(w * 0.5), h)
end

-- Dark text on a light fill, light text on a dark one.
local function textOn(col)
    return (col.r * 0.299 + col.g * 0.587 + col.b * 0.114) > 120 and T.dark or T.text
end

-- A colour a little of col mixed into the card colour (a picked row).
-- Worked out again when drawn after a theme switch (mixNow).
local function mixNow(c)
    local stamp = Rhylib.UI.themeStamp or 0
    if c.mixStamp ~= stamp then
        c.mixStamp = stamp
        local col, f, card = c.mixCol, c.mixF, T.card
        c.r, c.g, c.b = card.r + (col.r - card.r) * f, card.g + (col.g - card.g) * f, card.b + (col.b - card.b) * f
    end
    return c
end
local function mix(col, f)
    local c = Color(0, 0, 0)
    c.mixCol, c.mixF = col, f
    return mixNow(c)
end

-- "Only jobs I can take" style check box. get() -> bool, set(bool).
local function checkBox(parent, text, get, set)
    local s = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    surface.SetFont(K.Font(13))
    b:SetWide(s(26) + surface.GetTextSize(text) + s(4))
    function b:Paint(w, h)
        local sz = s(18)
        local y = math.floor((h - sz) * 0.5)
        if get() then
            K.SetCol(T.blue)
            surface.DrawRect(0, y, sz, sz)
            K.SetCol(T.dark)
            drawTick(0, y, sz)
        else
            K.SetCol(T.inset)
            surface.DrawRect(0, y, sz, sz)
            K.SetCol(self:IsHovered() and T.blue or T.edge)
            surface.DrawOutlinedRect(0, y, sz, sz)
        end
        draw.SimpleText(text, K.Font(13), sz + s(8), h * 0.5, self:IsHovered() and T.text or T.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        set(not get())
    end
    return b
end

-- The big action button. state() -> label, colour (nil colour = greyed:
-- the label is the reason). fn() on click while it has a colour.
local function bigButton(parent, state, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:Paint(w, h)
        local label, col = state()
        if col then
            K.SetCol(T.card)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(col, self:IsDown() and 200 or (self:IsHovered() and 255 or 235))
            surface.DrawRect(0, 0, w, h)
        else
            K.SetCol(T.tile)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(T.edge)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        local f = K.Font(16, 700)
        draw.SimpleText(K.Fit(label or "", f, w - K.S(24)), f, w * 0.5, h * 0.5, col and textOn(col) or T.off, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        local _, col = state()
        if not col then return end
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
end

-- A small square button with a chevron (the model < >).
local function arrowButton(parent, left, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:Paint(w, h)
        K.SetCol(self:IsHovered() and T.tile or T.inset)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(self:IsHovered() and T.blue or T.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        chevron(w * 0.5, h * 0.5, K.S(6), left, T.text)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
end

-- A category band: tint in col, a thick left edge, a diamond, the caps
-- name and a right-hand text from getRight() (cached by the caller).
local function band(parent, name, col, getRight)
    local s = K.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(s(36))
    local title = string.upper(name or "")
    function p:Paint(w, h)
        tintLeft(0, 0, w * 0.7, h, col, 50)
        K.SetCol(col)
        surface.DrawRect(0, 0, s(4), h)
        diamond(s(20), h * 0.5, s(6), col)
        local right = getRight and getRight() or ""
        draw.SimpleText(right, K.Font(12), w - s(12), h * 0.5, T.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText(K.Fit(title, K.Font(16, 700), w - s(130)), K.Font(16, 700), s(34), h * 0.5, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

-- A grid of row panels: two columns when wide enough. Returns the panel;
-- add rows with grid.rows[#grid.rows + 1] = row (parented to it).
local function rowGrid(parent)
    local s = K.S
    local g = vgui.Create("DPanel", parent)
    g.Paint = nil
    g.rows = {}
    function g:PerformLayout(w)
        local cols = w >= s(560) and 2 or 1
        local gap, rh = s(4), s(60)
        local cw = math.floor((w - gap * (cols - 1)) / cols)
        for i, r in ipairs(self.rows) do
            local c, row = (i - 1) % cols, math.floor((i - 1) / cols)
            r:SetPos(c * (cw + gap), row * (rh + gap))
            r:SetSize(cw, rh)
        end
        local n = math.ceil(#self.rows / cols)
        local want = math.max(0, n * (rh + gap) - gap)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    return g
end

-- The common row look: fill, edges, the icon square. Returns the text x.
local function paintRow(w, h, picked, mine, hovered, col, pickedBg)
    local s = K.S
    K.SetCol(picked and mixNow(pickedBg) or (mine and T.sel or (hovered and T.tile or T.card)))
    surface.DrawRect(0, 0, w, h)
    K.SetCol(picked and col or (mine and T.selEdge or T.faint))
    surface.DrawOutlinedRect(0, 0, w, h)
    if picked or mine then
        K.SetCol(picked and col or T.blue)
        surface.DrawRect(0, 0, s(3), h)
    end
    local sq = s(40)
    local y = math.floor((h - sq) * 0.5)
    K.SetCol(T.inset)
    surface.DrawRect(s(10), y, sq, sq)
    K.SetCol(T.edge)
    surface.DrawOutlinedRect(s(10), y, sq, sq)
    return s(10) + sq + s(12), y
end

-- The model preview box of the right column: a glow in getCol(), a
-- DModelPanel filling it (box.mp) and a caption line (box.caption).
local function previewBox(parent, col)
    local s = K.S
    local box = vgui.Create("DPanel", parent)
    box.caption = ""
    function box:Paint(w, h)
        K.SetCol(T.side)
        surface.DrawRect(0, 0, w, h)
        glow(w, h, col, 34)
        K.SetCol(T.black)
        surface.DrawRect(0, h - 1, w, 1)
    end
    function box:PaintOver(w, h)
        if self.caption ~= "" then
            draw.SimpleText(self.caption, K.Font(12), w * 0.5, h - s(18), T.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local mp = vgui.Create("DModelPanel", box)
    mp:SetMouseInputEnabled(false)
    mp:SetFOV(36)
    box.mp = mp
    function box:PerformLayout(w, h)
        mp:SetPos(0, 0)
        mp:SetSize(w, h)
        local a = s(44)
        if IsValid(self.prev) then self.prev:SetPos(s(14), math.floor((h - a) * 0.5)) self.prev:SetSize(a, a) end
        if IsValid(self.next) then self.next:SetPos(w - s(14) - a, math.floor((h - a) * 0.5)) self.next:SetSize(a, a) end
    end
    return box
end

-- Height of the right column (with a guess before the page is laid out).
local function sideTall(aside)
    local h = aside:GetTall()
    if h < K.S(300) then h = ScrH() - K.S(300) end
    return h
end

-- Right column panel (the detail side).
local function sideColumn(parent, w, emptyText)
    local aside = vgui.Create("DPanel", parent)
    aside:Dock(RIGHT)
    aside:SetWide(w)
    aside:DockMargin(K.S(18), 0, 0, 0)
    function aside:Paint(pw, ph)
        K.SetCol(T.side)
        surface.DrawRect(0, 0, pw, ph)
        K.SetCol(T.black)
        surface.DrawRect(0, 0, 1, ph)
        if not self.filled then
            draw.SimpleText(emptyText, K.Font(14), pw * 0.5, ph * 0.5, T.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    return aside
end

-- The flow of loadout chips (weapons / item facts). Sizes itself.
local function chipFlow(parent, names)
    local s = K.S
    local p = vgui.Create("DPanel", parent)
    p.pos = {}
    function p:PerformLayout(w)
        local f = K.Font(12, 500)
        surface.SetFont(f)
        local x, y, ch, gap = 0, 0, s(26), s(6)
        for i, n in ipairs(names) do
            local cw = math.min(w, surface.GetTextSize(n) + s(20))
            if x > 0 and x + cw > w then x, y = 0, y + ch + gap end
            local q = self.pos[i] or {}
            q[1], q[2], q[3] = x, y, cw
            self.pos[i] = q
            x = x + cw + gap
        end
        local want = #names > 0 and (y + ch) or 0
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    function p:Paint(w, h)
        local f, ch = K.Font(12, 500), s(26)
        for i, n in ipairs(names) do
            local q = self.pos[i]
            if q then
                K.SetCol(T.tile)
                surface.DrawRect(q[1], q[2], q[3], ch)
                K.SetCol(T.edge)
                surface.DrawOutlinedRect(q[1], q[2], q[3], ch)
                draw.SimpleText(K.Fit(n, f, q[3] - s(16)), f, q[1] + s(10), q[2] + ch * 0.5, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
    return p
end

-- The requirements checklist: list of { kind, text } (see drawMark).
local function checklist(parent, items)
    local s = K.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(#items * s(24))
    function p:Paint(w, h)
        local sz, f = s(18), K.Font(13)
        for i, it in ipairs(items) do
            local y = (i - 1) * s(24)
            drawMark(it[1], 0, y + s(1), sz)
            draw.SimpleText(K.Fit(it[2], f, w - s(30)), f, s(28), y + s(10), MARK_TEXT[it[1]] or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return p
end

-- A one-line caps heading with a diamond, then a big name: the top of the
-- detail column. Returns nothing; docks into info.
local function detailTitle(info, caps, name, col)
    local s = K.S
    local capsText, nameText = string.upper(caps or ""), string.upper(name or "")
    if capsText ~= "" then
        local l = vgui.Create("DPanel", info)
        l:Dock(TOP)
        l:SetTall(s(18))
        l:DockMargin(0, 0, s(8), 0)
        function l:Paint(w, h)
            diamond(s(4), h * 0.5, s(4), col)
            draw.SimpleText(K.Fit(capsText, K.Font(11, 700), w - s(16)), K.Font(11, 700), s(14), h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local n = vgui.Create("DPanel", info)
    n:Dock(TOP)
    n:SetTall(s(40))
    n:DockMargin(0, 0, s(8), 0)
    function n:Paint(w, h)
        draw.SimpleText(K.Fit(nameText, K.Font(30, 800), w), K.Font(30, 800), 0, h * 0.5, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- Width of the right column for a page this wide.
local function sideWidth(pageW)
    local s = K.S
    return math.Clamp(math.floor(pageW * 0.36), s(300), s(440))
end

-- Search typing: run fn 0.2 s after the last key (one named timer per
-- page, so fast typing rebuilds the list once), only while panel exists.
local function debounced(name, panel, fn)
    timer.Create(name, 0.2, 1, function()
        if IsValid(panel) then fn() end
    end)
end

-- Top bar of a page: a panel the page paints its left text into.
local function topBar(body)
    local s = K.S
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(38))
    bar:DockMargin(0, 0, 0, s(14))
    return bar
end

--------------------------------------------------------------------------
-- Jobs tab
--------------------------------------------------------------------------

-- The search text and the "Only jobs I can take" box (kept while the game runs).
local jobsQuery, jobsOnlyOpen = "", false

-- First sentence (or line) of a job's description: the row's sub line.
local function shortDesc(job)
    local d = string.Trim(job.description or "")
    d = string.Trim(string.match(d, "^[^\n]*") or "")
    local first = string.match(d, "^(.-[%.%!%?])%s")
    return string.Trim(first or d)
end

local function weaponNames(list)
    local out = {}
    for _, class in ipairs(list or {}) do
        local stored = weapons.GetStored(class)
        out[#out + 1] = stored and stored.PrintName or class
    end
    return out
end

-- What the checklist shows for a job: ticks for what you meet, a cross for
-- what blocks, "!" notes. The fields are rhylib_roster's job rules
-- (needsTraining, battalion, minRank, qual) and DarkRP's own.
local function jobChecks(job, vote, mine)
    local out, bad = {}, 0
    local ply = LocalPlayer()
    local function add(kind, text)
        out[#out + 1] = { kind, text }
        if kind == "bad" then bad = bad + 1 end
    end
    if mine then add("note", "This is your job now") end
    local R = Rhylib.Roster
    if R and R.Get then
        local c = R.Get(ply)
        if job.rhylibOff then add("bad", "Switched off by staff") end
        if (job.needsTraining or job.battalion) and not c.has then add("bad", "Create your character first") end
        if job.needsTraining then
            if c.trained then add("good", "Basic training done") else add("bad", "Needs basic training (ask a Sergeant or higher)") end
        end
        if job.battalion then
            if c.bn == job.battalion then add("good", "In the " .. job.battalion) else add("bad", "Only for members of the " .. job.battalion) end
            local need = R.RankIndex and R.RankIndex(job.minRank)
            if need and R.RankName then
                local rn = R.RankName(need)
                if c.bn == job.battalion and c.rank >= need then add("good", "Rank " .. rn .. " or higher") else add("bad", "Needs rank " .. rn .. " or higher") end
            end
        end
        if job.qual and R.HasQual and R.QualName then
            local qn = R.QualName(job.qual)
            if R.HasQual(ply, job.qual) then add("good", qn .. " qualification") else add("bad", "Needs the " .. qn .. " qualification") end
        end
    end
    if job.NeedToChangeFrom and not mine then
        local from = istable(job.NeedToChangeFrom) and job.NeedToChangeFrom or { job.NeedToChangeFrom }
        local names = {}
        for _, t in ipairs(from) do
            local j = RPExtraTeams and RPExtraTeams[t]
            names[#names + 1] = j and j.name or team.GetName(t)
        end
        local list = table.concat(names, " or ")
        add(table.HasValue(from, ply:Team()) and "good" or "bad", "Only from the job " .. list)
    end
    if job.admin == 1 then add(ply:IsAdmin() and "good" or "bad", "Admins only") end
    if job.admin and job.admin > 1 then add(ply:IsSuperAdmin() and "good" or "bad", "Superadmins only") end
    local st = jobState(job)
    if st.full and not mine then add("bad", "No free slot") end
    -- (any other reason the job's own check gives)
    if st.blocked and not mine and st.blocked ~= "Full" and bad == 0 then add("bad", st.blocked) end
    if vote then add("note", "Needs a vote from the other players") end
    if #out == 0 then add("good", "Open to everyone") end
    return out
end

local function buildJobs(body, frame)
    local s = K.S
    local ply = LocalPlayer()
    local R = Rhylib.Roster
    local selJob
    local fillList, showJob, only

    -- Header: who you are, the search box and the "can take" box.
    local bar = topBar(body)
    local hdr = { t = -1, job = "", rest = "", col = T.blue }
    function bar:Paint(w, h)
        if RealTime() - hdr.t > 0.5 then
            hdr.t = RealTime()
            hdr.job = (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team())
            hdr.col = team.GetColor(ply:Team()) or T.blue
            local rest = ""
            if R and R.Get then
                local c = R.Get(ply)
                if not c.has then
                    rest = "  ·  no character yet"
                else
                    local rank = (c.rank > 0 and R.RankName and R.RankName(c.rank)) or (R.Prefix and R.Prefix(ply)) or ""
                    rest = (rank ~= "" and ("  ·  " .. rank) or "") .. "  ·  " .. (c.trained and "basic training done" or "no basic training yet")
                end
            end
            hdr.rest = rest
        end
        local f, fb = K.Font(13), K.Font(13, 700)
        surface.SetFont(f)
        local x = surface.GetTextSize("You are ")
        draw.SimpleText("You are ", f, 0, h * 0.5, T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(hdr.job, fb, x, h * 0.5, hdr.col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(fb)
        x = x + surface.GetTextSize(hdr.job)
        draw.SimpleText(K.Fit(hdr.rest, f, math.max(0, only:GetX() - x - s(12))), f, x, h * 0.5, T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local search
    search = K.Search(bar, "Search jobs", function(t)
        jobsQuery = string.lower(string.Trim(t or ""))
        if fillList then debounced("rhylib.f4.jobsSearch", search, fillList) end
    end)
    search:Dock(RIGHT)
    search:SetWide(math.min(s(300), math.floor(body:GetWide() * 0.28)))
    search:SetText(jobsQuery)
    only = checkBox(bar, "Only jobs I can take", function() return jobsOnlyOpen end, function(v)
        jobsOnlyOpen = v
        fillList()
    end)
    only:Dock(RIGHT)
    only:DockMargin(0, 0, s(18), 0)

    local main = vgui.Create("DPanel", body)
    main:Dock(FILL)
    main.Paint = nil
    local aside = sideColumn(main, sideWidth(body:GetWide() - s(32)), "Pick a job on the left.")
    local list = K.Scroll(main)
    list:Dock(FILL)

    -- The list, by category (search and the box filter it).
    function fillList()
        list:Clear()
        local any = false
        local me = LocalPlayer()
        for _, cat in ipairs(categories("jobs")) do
            local all, shown = {}, {}
            for _, job in ipairs(cat.members or {}) do
                if not job.hidden then
                    all[#all + 1] = job
                    local ok = jobsQuery == "" or string.find(string.lower(job.name or ""), jobsQuery, 1, true) ~= nil
                    if ok and jobsOnlyOpen then ok = me:Team() == job.team or jobBlocked(job) == nil end
                    if ok then shown[#shown + 1] = job end
                end
            end
            if #shown > 0 and (not cat.canSee or cat.canSee(me)) then
                local ccol = IsColor(cat.color) and cat.color or (istable(cat.color) and cat.color.r and cat.color) or (all[1].color or T.blue)
                -- "N online" (everyone in the category's jobs, twice a second)
                local cnt = { t = -1, text = "" }
                local b = band(list, cat.name or "Jobs", ccol, function()
                    if RealTime() - cnt.t > 0.5 then
                        cnt.t = RealTime()
                        local n = 0
                        for _, j in ipairs(all) do n = n + jobState(j).count end
                        cnt.text = n .. " online"
                    end
                    return cnt.text
                end)
                b:Dock(TOP)
                b:DockMargin(0, any and s(14) or 0, s(10), s(4))
                any = true
                local grid = rowGrid(list)
                grid:Dock(TOP)
                grid:DockMargin(0, 0, s(10), 0)
                for _, job in ipairs(shown) do
                    local col = job.color or T.blue
                    local pickedBg = mix(col, 0.1)
                    local desc = shortDesc(job)
                    local row = vgui.Create("DButton", grid)
                    row:SetText("")
                    grid.rows[#grid.rows + 1] = row
                    function row:Paint(w, h)
                        -- (texts rebuilt only when the job's state is refreshed)
                        local st = jobState(job)
                        if self.st ~= st then
                            self.st = st
                            self.mine = LocalPlayer():Team() == job.team
                            self.slots = st.count .. " / " .. (st.limit > 0 and st.limit or INF)
                            local why = st.blocked
                            self.locked = why ~= nil and not self.mine and why ~= "Full"
                            self.sub = self.mine and "Your job" or why or desc
                        end
                        local x, iy = paintRow(w, h, selJob == job, self.mine, self:IsHovered(), col, pickedBg)
                        K.Icon("trooper", s(19), iy + s(9), s(22), self.locked and T.lockIcon or col)
                        local f12 = K.Font(12, 700)
                        surface.SetFont(f12)
                        local sw = surface.GetTextSize(self.slots)
                        draw.SimpleText(self.slots, f12, w - s(14), h * 0.5, st.full and T.red or T.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                        local tw = w - x - sw - s(26)
                        draw.SimpleText(K.Fit(job.name or "?", K.Font(14, 700), tw), K.Font(14, 700), x, h * 0.5 - s(9), self.locked and T.label or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        if self.sub ~= "" then
                            draw.SimpleText(K.Fit(self.sub, K.Font(11), tw), K.Font(11), x, h * 0.5 + s(10), self.locked and T.lockSub or T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        end
                        return true
                    end
                    function row:DoClick()
                        surface.PlaySound("ui/buttonclick.wav")
                        showJob(job)
                    end
                end
            end
        end
        if not any then
            local l = K.Label(list, jobsQuery ~= "" and "No job matches that search." or "No jobs to show.", 14, 400, T.dim)
            l:Dock(TOP)
            l:DockMargin(0, s(6), 0, 0)
        end
    end

    -- The right column: model, title, description, loadout, checklist,
    -- slots and the action button.
    function showJob(job)
        aside:Clear()
        selJob = job
        aside.filled = job ~= nil
        if not job then return end
        local col = job.color or T.blue
        local me = LocalPlayer()
        local mine = me:Team() == job.team
        local vote = needsVote(job)
        local model, models = firstModel(job)
        local modelIndex = 1
        -- Start on the model you wear (your job) or the one you picked before.
        if models then
            local want = mine and me:GetModel()
                or (DarkRP.getPreferredJobModel and DarkRP.getPreferredJobModel(job.team))
            for i, m in ipairs(models) do
                if want and string.lower(m) == string.lower(want) then modelIndex = i end
            end
            model = models[modelIndex]
        end
        local function wearing()
            return string.lower(LocalPlayer():GetModel() or "") == string.lower(models and models[modelIndex] or model or "")
        end

        -- Model preview (wears your own skin when the model has it; skins
        -- are picked on Trooper > Appearance).
        local box = previewBox(aside, col)
        box:Dock(TOP)
        box:SetTall(math.min(s(330), math.floor(sideTall(aside) * 0.42)))
        local mp = box.mp
        local function mySkin() return LocalPlayer():GetNW2Int("rhylib_skin", 0) end
        local function setModel(m)
            if not m then return end
            mp:SetModel(m)
            local ent = mp:GetEntity()
            local skinned = false
            if IsValid(ent) then
                local sk = mySkin()
                if sk < (ent:SkinCount() or 1) then
                    ent:SetSkin(sk)
                    skinned = sk > 0
                end
                local mn, mx = ent:GetRenderBounds()
                local size = math.max(mx.z - mn.z, 1)
                mp:SetLookAt(Vector(0, 0, size * 0.5))
                mp:SetCamPos(Vector(size * 1.55, size * 0.25, size * 0.6))
                local seq = ent:LookupSequence("idle_all_01")
                if seq and seq > 0 then ent:ResetSequence(seq) end
            end
            local cap = (models and #models > 1) and ("Model " .. modelIndex .. " of " .. #models) or ""
            if skinned then cap = cap ~= "" and (cap .. "  ·  wears your skin") or "Wears your skin" end
            box.caption = cap
        end
        setModel(model)
        local ang = Angle()
        function mp:LayoutEntity(ent)
            ang.y = 20 + math.sin(RealTime() * 0.6) * 18
            ent:SetAngles(ang)
            self:RunAnimation()
        end
        if models and #models > 1 then
            local function step(d)
                modelIndex = (modelIndex - 1 + d) % #models + 1
                setModel(models[modelIndex])
                if DarkRP.setPreferredJobModel then DarkRP.setPreferredJobModel(job.team, models[modelIndex]) end
            end
            box.prev = arrowButton(box, true, function() step(-1) end)
            box.next = arrowButton(box, false, function() step(1) end)
        end

        -- Footer: salary (while money is in use), slots bar, the button.
        local foot = vgui.Create("DPanel", aside)
        foot:Dock(BOTTOM)
        foot:DockMargin(s(20), s(8), s(20), s(16))
        foot.Paint = nil
        local salary = moneyOn() and money(job.salary or 0) or nil
        local slots = vgui.Create("DPanel", foot)
        slots:Dock(TOP)
        slots:SetTall(salary and s(48) or s(28))
        function slots:Paint(w, h)
            local st = jobState(job)
            if self.st ~= st then
                self.st = st
                if st.limit > 0 then
                    self.text = st.count .. " / " .. st.limit .. (st.full and "  ·  full" or " taken")
                    self.frac = math.Clamp(st.count / st.limit, 0, 1)
                else
                    self.text = st.count .. " taken  ·  no limit"
                    self.frac = 0
                end
            end
            local f, fb = K.Font(12), K.Font(12, 700)
            local y = s(8)
            if salary then
                draw.SimpleText("Salary", f, 0, y, T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(salary, fb, w, y, T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                y = y + s(20)
            end
            draw.SimpleText("Slots", f, 0, y, T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(self.text, fb, w, y, st.full and T.red or T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            K.SetCol(T.inset)
            surface.DrawRect(0, h - s(6), w, s(6))
            if self.frac > 0 then
                K.SetCol(st.full and T.red or col)
                surface.DrawRect(0, h - s(6), math.floor(w * self.frac), s(6))
            end
        end
        -- Your own job with several models: put the picked one on now
        -- (rhylib_roster changes it in place, no respawn; DarkRP remembers it).
        local canUpdate = models and #models > 1 and mine and Rhylib.Roster
        local become = vote and "Start a vote" or ("Become " .. (job.name or ""))
        local btn = bigButton(foot, function()
            if canUpdate then
                if not wearing() then return "Update job", col end
                return "Your current job", nil
            end
            local why = jobBlocked(job)
            if why then return why, nil end
            return become, col
        end, function()
            if canUpdate then
                if DarkRP.setPreferredJobModel then DarkRP.setPreferredJobModel(job.team, models[modelIndex]) end
                Rhylib.Net.Start("roster.jobmodel")
                net.WriteString(models[modelIndex])
                net.SendToServer()
                return
            end
            becomeJob(job)
            frame:Remove()
        end)
        btn:Dock(TOP)
        btn:SetTall(s(52))
        btn:DockMargin(0, s(12), 0, 0)
        if canUpdate then btn:SetTooltip("Wear the model shown, and keep it next time") end
        foot:SetTall(slots:GetTall() + s(12) + s(52))

        -- Middle: battalion line, name, description, loadout, checklist.
        local info = K.Scroll(aside)
        info:Dock(FILL)
        info:DockMargin(s(20), s(16), s(12), 0)
        detailTitle(info, job.battalion or job.category or "", job.name, col)
        local d = string.Trim(job.description or "")
        if d ~= "" then
            local desc = K.Label(info, d, 13, 400, T.dim)
            desc:Dock(TOP)
            desc:DockMargin(0, s(2), s(8), 0)
        end
        local wl = weaponNames(job.weapons)
        if #wl > 0 then
            local chips = chipFlow(info, wl)
            chips:Dock(TOP)
            chips:DockMargin(0, s(14), s(8), 0)
        end
        local reqs = checklist(info, jobChecks(job, vote, mine))
        reqs:Dock(TOP)
        reqs:DockMargin(0, s(14), s(8), s(8))
    end

    fillList()
    -- Start on your current job.
    local cur = RPExtraTeams and RPExtraTeams[ply:Team()]
    -- (the column has its height once the page is laid out)
    body:InvalidateLayout(true)
    main:InvalidateLayout(true)
    if cur then showJob(cur) end
end

--------------------------------------------------------------------------
-- Shop tab
--------------------------------------------------------------------------

-- kind: DarkRP category list name, and how to buy and price an item.
local SHOP = {
    { id = "entities", title = "Entities", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", i.cmd) end },
    { id = "weapons", title = "Weapons", price = function(i) return i.pricesep or i.price end,
      filter = function(i) return i.separate end,
      buy = function(i) RunConsoleCommand("darkrp", "buy", i.name) end },
    { id = "shipments", title = "Shipments", price = function(i) return i.price end,
      filter = function(i) return not i.noship end,
      buy = function(i) RunConsoleCommand("darkrp", "buyshipment", i.name) end },
    { id = "ammo", title = "Ammo", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", "buyammo", tostring(i.id)) end },
    { id = "vehicles", title = "Vehicles", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", "buyvehicle", i.name) end },
}

-- DarkRP keeps single weapons inside the shipments list.
local function shopItems(kind)
    local src = kind.id == "weapons" and "shipments" or kind.id
    local out = {}
    for _, cat in ipairs(categories(src)) do
        local items = {}
        for _, item in ipairs(cat.members or {}) do
            if (not kind.filter or kind.filter(item)) and allowedItem(item) then items[#items + 1] = item end
        end
        if #items > 0 and (not cat.canSee or cat.canSee(LocalPlayer())) then
            out[#out + 1] = { name = cat.name, color = cat.color, items = items }
        end
    end
    return out
end

-- The open kind and the search text (kept while the game runs).
local shopKindId, shopQuery = nil, ""

-- Short facts about an item: the row's sub line and the detail chips.
local function itemFacts(kind, item)
    local out = {}
    if kind.id == "shipments" and item.amount then out[#out + 1] = "Shipment of " .. item.amount end
    if kind.id == "ammo" and item.amountGiven then out[#out + 1] = item.amountGiven .. " rounds" end
    if (kind.id == "weapons" or kind.id == "shipments") and item.entity then
        local stored = weapons.GetStored(item.entity)
        if stored and stored.PrintName and stored.PrintName ~= item.name then out[#out + 1] = stored.PrintName end
    end
    if kind.id == "vehicles" then out[#out + 1] = "Vehicle" end
    return out
end

local function buildShop(body)
    local s = K.S
    local fillList, showItem
    local selItem, current

    -- Header: the kinds as tabs, the search box.
    local bar = topBar(body)
    bar.Paint = nil
    local search
    search = K.Search(bar, "Search the shop", function(t)
        shopQuery = string.lower(string.Trim(t or ""))
        if fillList then debounced("rhylib.f4.shopSearch", search, fillList) end
    end)
    search:Dock(RIGHT)
    search:SetWide(math.min(s(300), math.floor(body:GetWide() * 0.28)))
    search:SetText(shopQuery)

    local kinds = {}
    for _, kind in ipairs(SHOP) do
        if #shopItems(kind) > 0 then kinds[#kinds + 1] = kind end
    end
    for _, kind in ipairs(kinds) do
        if kind.id == shopKindId then current = kind end
    end
    current = current or kinds[1]

    local main = vgui.Create("DPanel", body)
    main:Dock(FILL)
    main.Paint = nil
    local aside = sideColumn(main, sideWidth(body:GetWide() - s(32)), "Pick something on the left.")
    local list = K.Scroll(main)
    list:Dock(FILL)

    for _, kind in ipairs(kinds) do
        local b = K.Button(bar, kind.title, function()
            if current == kind then return end
            current = kind
            shopKindId = kind.id
            selItem = nil
            fillList()
        end, { small = true, selected = function() return current == kind end })
        b:Dock(LEFT)
        surface.SetFont(K.Font(12, 700))
        b:SetWide(surface.GetTextSize(string.upper(kind.title)) + s(36))
        b:DockMargin(0, 0, s(6), 0)
    end

    function fillList()
        list:Clear()
        if not current then
            showItem(nil)
            local l = K.Label(list, "Nothing to buy as your current job.", 14, 400, T.dim)
            l:Dock(TOP)
            return
        end
        local kind = current
        local first, keep
        local any = false
        for _, g in ipairs(shopItems(kind)) do
            local shown = {}
            for _, item in ipairs(g.items) do
                if shopQuery == "" or string.find(string.lower(item.name or ""), shopQuery, 1, true) then shown[#shown + 1] = item end
            end
            if #shown > 0 then
                local gcol = IsColor(g.color) and g.color or (istable(g.color) and g.color.r and g.color) or T.blue
                local count = #shown == 1 and "1 item" or (#shown .. " items")
                local b = band(list, g.name or kind.title, gcol, function() return count end)
                b:Dock(TOP)
                b:DockMargin(0, any and s(14) or 0, s(10), s(4))
                any = true
                local grid = rowGrid(list)
                grid:Dock(TOP)
                grid:DockMargin(0, 0, s(10), 0)
                for _, item in ipairs(shown) do
                    first = first or { item, gcol, g.name }
                    if item == selItem then keep = { item, gcol, g.name } end
                    local price = kind.price(item) or 0
                    local priceText = money(price)
                    local facts = itemFacts(kind, item)
                    local sub = facts[1] or ""
                    local pickedBg = mix(gcol, 0.1)
                    local row = vgui.Create("DButton", grid)
                    row:SetText("")
                    grid.rows[#grid.rows + 1] = row
                    function row:Paint(w, h)
                        local x = paintRow(w, h, selItem == item, false, self:IsHovered(), gcol, pickedBg)
                        local ok = canAfford(price)
                        local f12 = K.Font(12, 700)
                        surface.SetFont(f12)
                        local pw = surface.GetTextSize(priceText)
                        draw.SimpleText(priceText, f12, w - s(14), h * 0.5, ok and T.green or T.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                        local tw = w - x - pw - s(26)
                        draw.SimpleText(K.Fit(item.name or "?", K.Font(14, 700), tw), K.Font(14, 700), x, h * 0.5 - s(9), T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        local line = ok and sub or "Not enough money"
                        if line ~= "" then
                            draw.SimpleText(K.Fit(line, K.Font(11), tw), K.Font(11), x, h * 0.5 + s(10), ok and T.dim or T.lockSub, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        end
                        return true
                    end
                    if item.model and item.model ~= "" then
                        local icon = vgui.Create("ModelImage", row)
                        icon:SetMouseInputEnabled(false)
                        icon:SetModel(item.model)
                        function row:PerformLayout(w, h)
                            local sq = s(40)
                            icon:SetPos(s(10) + 1, math.floor((h - sq) * 0.5) + 1)
                            icon:SetSize(sq - 2, sq - 2)
                        end
                    end
                    function row:DoClick()
                        surface.PlaySound("ui/buttonclick.wav")
                        showItem(item, gcol, g.name)
                    end
                end
            end
        end
        if not any then
            local l = K.Label(list, shopQuery ~= "" and "Nothing matches that search." or "Nothing to buy here as your current job.", 14, 400, T.dim)
            l:Dock(TOP)
        end
        local pick = keep or first
        -- (the right column, with its model panel, is only rebuilt when
        -- the picked item changes)
        if pick then
            if pick[1] ~= selItem or not aside.filled then showItem(pick[1], pick[2], pick[3]) end
        else
            showItem(nil)
        end
    end

    -- The right column: model, title, facts, price and the buy button.
    function showItem(item, gcol, catName)
        aside:Clear()
        selItem = item
        aside.filled = item ~= nil
        if not item then return end
        local kind = current
        local price = kind.price(item) or 0
        local col = gcol or T.blue

        local box = previewBox(aside, col)
        box:Dock(TOP)
        box:SetTall(math.min(s(300), math.floor(sideTall(aside) * 0.4)))
        local mp = box.mp
        if item.model and item.model ~= "" then
            mp:SetModel(item.model)
            local ent = mp:GetEntity()
            if IsValid(ent) then
                local mn, mx = ent:GetRenderBounds()
                local c = (mn + mx) * 0.5
                local size = math.max((mx - mn):Length(), 1)
                mp:SetLookAt(c)
                mp:SetCamPos(c + Vector(size * 0.85, size * 0.85, size * 0.45))
            end
        end
        local ang = Angle()
        function mp:LayoutEntity(ent)
            ang.y = (RealTime() * 30) % 360
            ent:SetAngles(ang)
        end

        local foot = vgui.Create("DPanel", aside)
        foot:Dock(BOTTOM)
        foot:DockMargin(s(20), s(8), s(20), s(16))
        foot.Paint = nil
        local priceText = money(price)
        local showMoney = moneyOn()
        local lines = vgui.Create("DPanel", foot)
        lines:Dock(TOP)
        lines:SetTall(showMoney and s(40) or s(20))
        function lines:Paint(w, h)
            local f, fb = K.Font(12), K.Font(12, 700)
            draw.SimpleText("Price", f, 0, s(8), T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(priceText, fb, w, s(8), canAfford(price) and T.green or T.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            if showMoney then
                local m = myMoney()
                if self.m ~= m then self.m, self.mt = m, money(m) end
                draw.SimpleText("Your money", f, 0, s(28), T.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(self.mt, fb, w, s(28), T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        local buyText = "Buy for " .. priceText
        local btn = bigButton(foot, function()
            if canAfford(price) then return buyText, T.blue end
            return "Not enough money", nil
        end, function() kind.buy(item) end)
        btn:Dock(TOP)
        btn:SetTall(s(52))
        btn:DockMargin(0, s(12), 0, 0)
        foot:SetTall(lines:GetTall() + s(12) + s(52))

        local info = K.Scroll(aside)
        info:Dock(FILL)
        info:DockMargin(s(20), s(16), s(12), 0)
        detailTitle(info, (catName and catName ~= "" and (kind.title .. "  ·  " .. catName)) or kind.title, item.name, col)
        if isstring(item.description) and item.description ~= "" then
            local d = K.Label(info, string.Trim(item.description), 13, 400, T.dim)
            d:Dock(TOP)
            d:DockMargin(0, s(2), s(8), 0)
        end
        local facts = itemFacts(kind, item)
        if #facts > 0 then
            local chips = chipFlow(info, facts)
            chips:Dock(TOP)
            chips:DockMargin(0, s(14), s(8), s(8))
        end
    end

    body:InvalidateLayout(true)
    main:InvalidateLayout(true)
    fillList()
end

--------------------------------------------------------------------------
-- Character tab
--------------------------------------------------------------------------

-- Skill points left (rhylib_skills), or nil without it. math.huge = free.
local function skillPointsLeft(ply)
    local Sk = Rhylib.Skills
    if not (Sk and Sk.Points and Sk.Spent and Sk.Set) then return nil end
    local pts = Sk.Points(ply)
    if pts == math.huge then return math.huge, pts end
    return math.max(0, pts - Sk.Spent(Sk.Set(ply))), pts
end
Menus.SkillPointsLeft = skillPointsLeft

local function goPage(id)
    return function()
        if IsValid(Menus.pause) and Menus.pages and Menus.pages[id] then Menus.pause:ShowPage(id) end
    end
end

-- A clickable tile: caps label, a big line, a dim line, a link line.
local function tile(parent, label, getBig, getDim, link, fn, col)
    local s = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:Paint(w, h)
        local on = fn ~= nil
        K.SetCol(on and self:IsHovered() and C.buttonHover or C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(col or C.accent)
        surface.DrawRect(0, 0, w, s(2))
        K.Caps(label, s(14), s(20))
        draw.SimpleText(K.Fit(getBig(), K.Font(19, 700), w - s(28)), K.Font(19, 700), s(14), s(46), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(K.Fit(getDim() or "", K.Font(13), w - s(28)), K.Font(13), s(14), s(70), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if link and on then
            draw.SimpleText(link, K.Font(13, 700), s(14), h - s(16), col or C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function b:DoClick()
        if not fn then return end
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
end

-- Trooper > Overview: who you are (model, name, battalion, rank, job,
-- qualifications), tiles to Skills / Jobs / Battalion, the service
-- record and quick actions.
local function buildCharacter(body, frame)
    local s = K.S
    local ply = LocalPlayer()
    local R = Rhylib.Roster
    local function char() return R and R.Get and R.Get(ply) or { has = false } end
    local function jobName() return (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team()) end

    -- Who you are.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(200))
    function top:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local x = s(196)
        local c = char()
        local name = (R and R.FullName and R.FullName(ply)) or ply:Nick()
        draw.SimpleText(K.Fit(string.upper(name), K.Font(28, 700), w - x - s(16)), K.Font(28, 700), x, s(38), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tc = team.GetColor(ply:Team()) or C.accent
        local unit
        if c.has then
            unit = (c.bn ~= "" and c.bn or (c.trained and "No battalion yet" or "Cadet: waiting for basic training"))
            if c.rank and c.rank > 0 and R.RankName then unit = unit .. "  ·  " .. R.RankName(c.rank) end
        end
        if unit then
            -- (a small diamond in the job's colour)
            local dx, dy, r = x + s(6), s(72), s(5)
            draw.NoTexture()
            K.SetCol(tc)
            surface.DrawPoly({ { x = dx, y = dy - r }, { x = dx + r, y = dy }, { x = dx, y = dy + r }, { x = dx - r, y = dy } })
            draw.SimpleText(unit, K.Font(16, 600), x + s(18), dy, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("Job: " .. jobName(), K.Font(14), x, s(100), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- Qualifications as chips.
        local cx = x
        local f = K.Font(12, 700)
        surface.SetFont(f)
        for id in string.gmatch(ply:GetNW2String("rhylib_quals", ""), "[^,]+") do
            local q = R and R.QualName and R.QualName(id) or id
            local tw = surface.GetTextSize(q) + s(14)
            if cx + tw > w - s(12) then break end
            K.SetCol(C.good, 160)
            surface.DrawOutlinedRect(cx, s(124), tw, s(22))
            draw.SimpleText(q, f, cx + tw * 0.5, s(135), C.good, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cx = cx + tw + s(6)
        end
    end
    local mp = vgui.Create("DModelPanel", top)
    mp:SetPos(s(8), s(8))
    mp:SetSize(s(172), s(184))
    mp:SetFOV(30)
    mp:SetModel(ply:GetModel())
    local ent = mp:GetEntity()
    if IsValid(ent) then
        ent:SetSkin(ply:GetSkin())
        for i = 0, ply:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, ply:GetBodygroup(i)) end
        local mn, mx = ent:GetRenderBounds()
        local size = math.max(mx.z - mn.z, 1)
        mp:SetLookAt(Vector(0, 0, size * 0.62))
        mp:SetCamPos(Vector(size * 1.25, size * 0.2, size * 0.7))
        local seq = ent:LookupSequence("idle_all_01")
        if seq and seq > 0 then ent:ResetSequence(seq) end
    end
    function mp:LayoutEntity(e)
        e:SetAngles(Angle(0, 20 + math.sin(RealTime() * 0.6) * 18, 0))
        self:RunAnimation()
    end

    -- Tiles.
    local tiles = vgui.Create("DPanel", body)
    tiles:Dock(TOP)
    tiles:DockMargin(0, s(10), 0, 0)
    tiles:SetTall(s(118))
    tiles.Paint = nil
    local list = {}
    if Menus.pages.skills then
        list[#list + 1] = tile(tiles, "Skills", function()
            local left = skillPointsLeft(ply)
            if left == math.huge then return "Free (testing)" end
            if not left then return "-" end
            return left == 1 and "1 point to spend" or (left .. " points to spend")
        end, function()
            local left, pts = skillPointsLeft(ply)
            if not pts or pts == math.huge then return "" end
            return (pts - left) .. " of " .. pts .. " spent"
        end, "Spend points ›", goPage("skills"), C.warn)
    end
    if Menus.pages.jobs and isDarkRP() then
        list[#list + 1] = tile(tiles, "Job", jobName, function()
            local j = RPExtraTeams and RPExtraTeams[ply:Team()]
            if not j then return "" end
            local lim = jobLimit(j)
            local n = team.NumPlayers(ply:Team())
            return lim and lim > 0 and (n .. " of " .. lim .. " slots taken") or (n .. " on this job")
        end, "Change job ›", goPage("jobs"))
    end
    if Menus.pages.roster then
        list[#list + 1] = tile(tiles, "Battalion", function()
            local c = char()
            return c.bn ~= "" and c.bn or "None yet"
        end, function()
            local c = char()
            if not c.bn or c.bn == "" then return "" end
            local n = 0
            for _, p in ipairs(player.GetAll()) do
                if p:GetNW2String(Rhylib.NW.BATTALION, "") == c.bn then n = n + 1 end
            end
            return n .. " online"
        end, "See your unit ›", goPage("roster"), team.GetColor(ply:Team()))
    end
    function tiles:PerformLayout(w, h)
        local n = #list
        if n == 0 then return end
        local gap = s(10)
        local tw = (w - gap * (n - 1)) / n
        for i, t in ipairs(list) do
            t:SetPos(math.floor((i - 1) * (tw + gap)), 0)
            t:SetSize(math.floor(tw), h)
        end
    end
    if #list == 0 then tiles:SetVisible(false) end

    -- Service record.
    local h1 = K.Heading(body, "Service record")
    h1:Dock(TOP)
    h1:DockMargin(0, s(14), 0, s(8))
    local rec = vgui.Create("DPanel", body)
    rec:Dock(TOP)
    rec:SetTall(s(66))
    function rec:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local c = char()
        local lines = {}
        if c.has then lines[#lines + 1] = { "Clone number", c.num ~= "" and c.num or "-" } end
        lines[#lines + 1] = { "Kills / deaths", ply:Frags() .. " / " .. ply:Deaths() }
        local weight = ply:GetNW2Float("rhylib_weight", -1)
        if weight >= 0 then
            lines[#lines + 1] = { "Carrying", string.format("%.1f / %.0f kg", weight, ply:GetNW2Float("rhylib_carry", 20)) }
        end
        if moneyOn() then
            lines[#lines + 1] = { "Money", money(myMoney()) }
            lines[#lines + 1] = { "Salary", money(ply.getDarkRPVar and ply:getDarkRPVar("salary") or 0) }
        end
        local per = math.min(#lines, 5)
        local rows = math.ceil(#lines / per)
        local need = rows * s(58) + s(8)
        if math.abs(self:GetTall() - need) > 1 then self:SetTall(need) end
        local colW = (w - s(16)) / per
        for i, l in ipairs(lines) do
            local cx = s(16) + ((i - 1) % per) * colW
            local cy = s(22) + math.floor((i - 1) / per) * s(58)
            K.Caps(l[1], cx, cy)
            draw.SimpleText(tostring(l[2]), K.Font(17, 700), cx, cy + s(20), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Quick actions.
    local h2 = K.Heading(body, "Quick actions")
    h2:Dock(TOP)
    h2:DockMargin(0, s(14), 0, s(8))
    local grid = vgui.Create("DIconLayout", body)
    grid:Dock(FILL)
    grid:SetSpaceX(s(8))
    grid:SetSpaceY(s(8))
    local function number(text)
        local n = tonumber(string.Trim(text or ""))
        return n and n > 0 and math.floor(n) or nil
    end
    local actions = {}
    local looks = Menus.pages.looks
    if looks and (not looks.visible or looks.visible()) then actions[#actions + 1] = { "Change appearance", goPage("looks") } end
    actions[#actions + 1] = { "Open inventory", function()
        frame:Remove()
        if Rhylib.Inventory and Rhylib.Inventory.Toggle then Rhylib.Inventory.Toggle() end
    end }
    local cls = Menus.pages.class
    if cls and (not cls.visible or cls.visible()) then actions[#actions + 1] = { "Pick class", goPage("class") } end
    -- Money and door actions only while money is in use; the name comes
    -- from the character when rhylib_roster is installed.
    if moneyOn() then
        actions[#actions + 1] = { "Drop money", function()
            K.Prompt("Drop money", "How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "dropmoney", tostring(n)) end end)
        end }
        actions[#actions + 1] = { "Give money", function()
            K.Prompt("Give money", "To the player you're looking at. How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "give", tostring(n)) end end)
        end }
        actions[#actions + 1] = { "Sell all doors", function()
            K.Prompt("Sell all doors", "Type yes to sell every door you own.", "", function(t)
                if string.lower(string.Trim(t)) == "yes" then RunConsoleCommand("darkrp", "unownalldoors") end
            end)
        end }
    end
    if not Rhylib.Roster then
        actions[#actions + 1] = { "Change RP name", function()
            K.Prompt("RP name", "Your new name", ply:Nick(), function(t) t = string.Trim(t) if t ~= "" then RunConsoleCommand("darkrp", "rpname", t) end end)
        end }
    end
    for _, a in ipairs(actions) do
        local b = K.Button(grid, a[1], a[2])
        b:SetSize(s(200), s(36))
    end
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- The F4 menu lives in the pause menu: Jobs, Shop and Character pages.
-- F4 opens it on Jobs (or closes it); Esc opens it where you left off.

-- The tab builders close "the frame" after choosing a job; here that's the pause menu.
local frame = { Remove = function() Menus.ClosePause() end }

local function sub()
    local ply = LocalPlayer()
    local job = (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team())
    if not moneyOn() then return job end
    return job .. "   ·   " .. money(myMoney())
end

-- Is there anything at all in the shop (any category of any kind with a
-- member)? A server that removed every DarkRP item has no Shop page.
local function shopHasItems()
    for _, kind in ipairs({ "entities", "shipments", "weapons", "ammo", "vehicles" }) do
        for _, cat in ipairs(categories(kind)) do
            if cat.members and #cat.members > 0 then return true end
        end
    end
    return false
end

-- Jobs shows your job in its own header: only the money on the plate.
local function moneySub()
    if moneyOn() then return "Money  " .. money(myMoney()) end
    return nil
end

local function page(id, def, fn, subFn)
    def.visible = def.visible or isDarkRP
    def.build = function(p)
        Menus.pages[id].sub = (subFn or sub)()
        fn(p, frame)
    end
    Menus.AddPage(id, def)
end
page("jobs", { title = "Jobs", order = 30, section = "you", icon = "jobs", key = "F4", wide = true }, buildJobs, moneySub)
page("shop", { title = "Shop", order = 32, section = "you", icon = "shop", wide = true,
    visible = function() return isDarkRP() and shopHasItems() end }, buildShop)
page("character", { title = "Overview", order = 10, group = "trooper" }, buildCharacter)

-- Menus.ToggleF4(): F4. Opens the pause menu on Jobs; if it's already open
-- on Jobs it closes it, on another page it switches to Jobs.
function Menus.ToggleF4()
    if not isDarkRP() then return end
    if IsValid(Menus.pause) then
        if Menus.pause.pageId == "jobs" then
            Menus.ClosePause()
        else
            Menus.pause:ShowPage("jobs")
        end
        return
    end
    Menus.lastPage = "jobs"
    Menus.OpenPause()
    Menus.f4Held = true   -- the key that opened it must be let go before it can close it
end

-- F4 (gm_showspare2): ours, before DarkRP's runs on the server.
Rhylib.Hook.Add("PlayerBindPress", "menus.f4", function(_, bind, pressed)
    if pressed and isDarkRP() and string.find(bind, "gm_showspare2", 1, true) then
        Menus.ToggleF4()
        return true
    end
end)

-- While the menu is open it has the keyboard, so binds don't fire: watch
-- the F4 key itself (a fresh press closes it).
local f4Down = false
Rhylib.Hook.Add("Think", "menus.f4key", function()
    if not IsValid(Menus.pause) then
        f4Down = false
        return
    end
    local down = input.IsKeyDown(KEY_F4)
    if not down then Menus.f4Held = false end
    if down and not f4Down and not Menus.f4Held then Menus.ToggleF4() end
    f4Down = down
end)

-- In case DarkRP opens its menu another way: it opens ours.
local function takeOver()
    if not DarkRP then return end
    local function open()
        if not (IsValid(Menus.pause) and Menus.pause.pageId == "jobs") then Menus.ToggleF4() end
    end
    DarkRP.openF4Menu = open
    DarkRP.toggleF4Menu = open
    DarkRP.closeF4Menu = function() end
    DarkRP.getF4MenuPanel = function() return Menus.pause end
end
Rhylib.Hook.Add("InitPostEntity", "menus.f4", takeOver)
Rhylib.Hook.Add("DarkRPFinishedLoading", "menus.f4", takeOver)
takeOver()

concommand.Add("rhylib_f4", Menus.ToggleF4)
