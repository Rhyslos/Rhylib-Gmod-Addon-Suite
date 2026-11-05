--[[
    Quartermaster (client): the loadout window net armoury.qm opens
    (sv_50_quartermaster.lua sends it on E and after every change).

    Layout: a header (purple top edge, crate badge, QUARTERMASTER, a line
    about it, close). Left column YOU CARRY NOW: what you carry, one row
    per item (colour strip by kind, count / fill % / "worn"; job gear dim
    with "job gear", what he won't take in with a red tag) and the weight,
    then a note that job gear stays. Right: a red banner when you carry
    things he can't take in (each as a chip with why; Apply is greyed,
    saving still works), three slot cards side by side, and a note about
    the stock and fresh magazines.
      Filled card: number, name with a rename button, "Saved 2 days ago",
      WEIGHT and ITEMS tiles, the items (LOW STOCK / OUT OF STOCK marks),
      Apply this loadout (purple on the last one you applied), Save
      current kit here (asks before replacing), Clear (asks).
      Empty card: dashed, "Empty slot", Save current kit here.

    Apply: op check -> armoury.qmprob. Nothing in the way: confirms at once
    (option 0). Otherwise the popup SOME ITEMS CAN'T BE ISSUED lists each
    with why (amber for stock, weight and room; red for skills, roles and
    limits): Apply without them (1) / Apply, and save the loadout without
    them (2) / Cancel. When none of it can be issued: only Close.

    Handout (net armoury.qmhand): the body is covered by HANDING OUT · name,
    a bar run from the duration and time left the server sent once, the
    seconds left, step lines lighting up as the bar passes them (the
    backpack line only when the loadout has one), the stay-at-the-counter
    line and Stop (op stop). With the loadout editor on (armoury qmEditor)
    filled cards also have Edit and empty ones Create loadout (op editor:
    cl_55_quartermaster_editor.lua opens on the catalogue).

    Closes when you walk away, die or the NPC goes; Esc closes a popup
    first, then the window (UI closer "armoury.qm"; it leaves the window
    alone while a text prompt such as Rename is open). Closing sends op
    close.
]]

local A = Rhylib.Armoury
A.QM = A.QM or {}
local Q = A.QM
local UI = Rhylib.UI

-- (Q.win: the open window { frame, npc, body, data, busy, popup }; kept on refresh)

local C_WIN, C_SIDE, C_CARD, C_INSET = Color(14, 16, 15), Color(18, 20, 19), Color(22, 25, 23), Color(14, 16, 15)
local C_TILE, C_EDGE, C_BLACK = Color(26, 30, 27), Color(42, 45, 41), Color(0, 0, 0)
local C_TEXT, C_DIM, C_LABEL, C_OFF = Color(228, 227, 220), Color(169, 168, 160), Color(138, 140, 132), Color(111, 116, 109)
local C_BLUE, C_AMBER, C_RED, C_GREEN, C_PURPLE = Color(133, 183, 235), Color(239, 159, 39), Color(226, 75, 74), Color(151, 196, 89), Color(164, 110, 224)
local C_PURPLE_BG, C_DARK, C_DIS_BG = Color(29, 20, 40), Color(20, 20, 19), Color(35, 38, 42)
local C_DANGER_EDGE, C_DANGER_TXT = Color(90, 42, 42), Color(240, 149, 149)
local C_BAN_BG, C_BAN_EDGE, C_BAN_ICON = Color(36, 19, 19), Color(107, 42, 42), Color(240, 128, 110)
local C_BAN_TITLE, C_BAN_TEXT, C_CHIP_BG = Color(246, 194, 184), Color(224, 176, 166), Color(22, 11, 11)
local C_EMPTY_ICON, C_OVERLAY, C_HOVER = Color(58, 64, 59), Color(7, 8, 7, 215), Color(255, 255, 255, 22)

local ICONS = {
    qm_crate = { { 3, 7, 12, 3, 21, 7, 21, 17, 12, 21, 3, 17, closed = true }, { 3, 7, 12, 11, 21, 7 }, { 12, 11, 12, 21 } },
    qm_close = { { 6, 6, 18, 18 }, { 18, 6, 6, 18 } },
    qm_check = { { 20, 6, 9, 17, 4, 12 } },
    qm_alert = { { arc = { 12, 12, 9, 0, 360 } }, { 12, 7, 12, 13 }, { 12, 16, 12, 17 } },
}

local function K() return UI and UI.Kit end
local function S(n) return K().S(n) end
local function F(size, weight) return K().Font(size, weight) end

-- (the kit draws icons by name from K.ICONS: ours added there)
local function ensureIcons()
    local k = K()
    if not (k and k.ICONS) then return end
    for name, shape in pairs(ICONS) do
        if not k.ICONS[name] then k.ICONS[name] = shape end
    end
end

local function icon(name, x, y, size, col)
    local k = K()
    if k and k.Icon then k.Icon(name, x, y, size, col) end
end

local function kindCol(def)
    if not def then return C_LABEL end
    local It = Rhylib.Items
    if It and It.GroupOf and It.GroupOf(def) == "grenade" then return C_PURPLE end
    local Inv = Rhylib.Inventory
    local cc = Inv and Inv.CATEGORY_COLORS and (Inv.CATEGORY_COLORS[def.category] or Inv.CATEGORY_COLORS.misc)
    return cc and cc.stripe or C_LABEL
end

local function ago(sec)
    if sec < 60 then return "Saved just now" end
    if sec < 3600 then return "Saved " .. math.floor(sec / 60) .. " min ago" end
    if sec < 86400 then
        local h = math.floor(sec / 3600)
        return "Saved " .. h .. (h == 1 and " hour ago" or " hours ago")
    end
    local d = math.floor(sec / 86400)
    if d == 1 then return "Saved yesterday" end
    return "Saved " .. d .. " days ago"
end

local function kg(n) return string.format("%.1f kg", n) end

-- "Loadout 2 · Breacher" (just "Loadout 2" while it has the default name)
local function slotTitle(slot, name)
    if not name or name == "" or name == Q.DefaultName(slot) then return Q.DefaultName(slot) end
    return "Loadout " .. slot .. " · " .. name
end

local function dashed(x, y, w, h, col)
    surface.SetDrawColor(col)
    local dash, gap = S(6), S(4)
    for i = x, x + w - 1, dash + gap do
        local l = math.min(dash, x + w - i)
        surface.DrawRect(i, y, l, 1)
        surface.DrawRect(i, y + h - 1, l, 1)
    end
    for j = y, y + h - 1, dash + gap do
        local l = math.min(dash, y + h - j)
        surface.DrawRect(x, j, 1, l)
        surface.DrawRect(x + w - 1, j, 1, l)
    end
end

--------------------------------------------------------------------------
-- Talking to the server
--------------------------------------------------------------------------

local function act(op, slot, write)
    local w = Q.win
    if not w then return end
    Rhylib.Net.Start("armoury.qmact")
    net.WriteEntity(w.npc)
    net.WriteUInt(op, 3)
    net.WriteUInt(slot or 0, 2)
    if write then write() end
    net.SendToServer()
end

local function close(tell)
    local w = Q.win
    if not w then return end
    Q.win = nil
    if tell then
        Rhylib.Net.Start("armoury.qmact")
        net.WriteEntity(IsValid(w.npc) and w.npc or NULL)
        net.WriteUInt(Q.OP_CLOSE, 3)
        net.WriteUInt(0, 2)
        net.SendToServer()
    end
    if IsValid(w.frame) then w.frame:Remove() end
end
Q.Close = close

if UI and UI.RegisterCloser then
    -- (Esc runs every closer: while a text prompt such as Rename is open,
    -- that prompt's own closer takes it and the window stays)
    UI.RegisterCloser("armoury.qm", function()
        local w = Q.win
        if not w then return false end
        -- (the prompts closer may already have removed it this time round:
        -- w.prompt is what the window saw open last frame)
        if w.prompt then return false end
        if w.editor or (Q.editor and IsValid(Q.editor.frame)) then return false end
        for pr in pairs(UI.prompts or {}) do
            if IsValid(pr) then return false end
        end
        if IsValid(w.popup) then
            w.popup:Remove()
            w.popup = nil
            return true
        end
        close(true)
        return true
    end)
end

local function busy()
    local w = Q.win
    return w and ((w.busy and w.busy > CurTime()) or w.hand ~= nil)
end

local function editorOn() return Rhylib.Config.Get("armoury", "qmEditor") == true end
local function openEditor(slot)
    local w = Q.win
    if not w or busy() then return end
    w.busy = CurTime() + 3
    act(Q.OP_EDITOR, slot, function() net.WriteUInt(0, 1) end)
end

--------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------

-- A button in the board's style. style: "primary" (filled, dark text;
-- opts.col a function -> colour), "outline", "ghost" (dim text), "danger".
-- label: string or function; enabled: function -> bool.
local function button(parent, label, style, fn, enabled, opts)
    opts = opts or {}
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:IsOn() return not enabled or enabled() and true or false end
    function b:Paint(w, h)
        local on = self:IsOn()
        local text = isfunction(label) and label() or label
        local font = opts.font or F(style == "primary" and 14 or 12, style == "primary" and 700 or 500)
        local tc
        if style == "primary" then
            if on then
                surface.SetDrawColor(opts.col and opts.col() or C_BLUE)
                surface.DrawRect(0, 0, w, h)
                if self:IsHovered() then
                    surface.SetDrawColor(C_HOVER)
                    surface.DrawRect(0, 0, w, h)
                end
                tc = C_DARK
            else
                surface.SetDrawColor(C_DIS_BG)
                surface.DrawRect(0, 0, w, h)
                tc = C_OFF
            end
        else
            if on and self:IsHovered() then
                surface.SetDrawColor(C_TILE)
                surface.DrawRect(0, 0, w, h)
            end
            surface.SetDrawColor(style == "danger" and C_DANGER_EDGE or C_EDGE)
            surface.DrawOutlinedRect(0, 0, w, h)
            tc = not on and C_OFF or (style == "danger" and C_DANGER_TXT or (style == "ghost" and C_DIM or C_TEXT))
        end
        -- (fitted again only when the text or width changes)
        if text ~= self.fitText or w ~= self.fitW then
            self.fitText, self.fitW = text, w
            self.fitted = K().Fit(text, font, w - S(12))
        end
        draw.SimpleText(self.fitted, font, w / 2, h / 2, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        if not self:IsOn() then return end
        surface.PlaySound("ui/buttonclick.wav")
        if fn then fn(self) end
    end
    return b
end

-- One item line: colour strip, name, count on the right, an optional tag.
local function itemRow(parent, def, right, tag, tagCol, o)
    o = o or {}
    local r = vgui.Create("DPanel", parent)
    r:SetTall(S(o.tall or 34))
    local name = def and def.name or "Unknown item"
    local nameFont, rightFont, tagFont = F(o.nameSize or 13, 500), F(o.rightSize or 12), F(10, 700)
    local tagW = 0
    if tag then
        surface.SetFont(tagFont)
        tagW = surface.GetTextSize(tag) + S(8)
    end
    local rightW = 0
    if right and right ~= "" then
        surface.SetFont(rightFont)
        rightW = surface.GetTextSize(right) + S(8)
    end
    local shown = name
    local col = kindCol(def)
    function r:PerformLayout(w)
        shown = K().Fit(name, nameFont, math.max(S(20), w - S(o.small and 22 or 26) - rightW - tagW - S(10)))
    end
    function r:Paint(w, h)
        surface.SetDrawColor(o.bg or C_CARD)
        surface.DrawRect(0, 0, w, h)
        local bh = S(o.small and 14 or 18)
        surface.SetDrawColor(o.dim and C_OFF or col)
        surface.DrawRect(S(o.small and 8 or 10), (h - bh) / 2, S(3), bh)
        draw.SimpleText(shown, nameFont, S(o.small and 19 or 23), h / 2, o.dim and C_DIM or C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local x = w - S(o.small and 8 or 10)
        if tag then
            draw.SimpleText(tag, tagFont, x, h / 2, tagCol or C_AMBER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            x = x - tagW
        end
        if right and right ~= "" then
            draw.SimpleText(right, rightFont, x, h / 2, C_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    return r
end

--------------------------------------------------------------------------
-- Popups (inside the window, over a dimmed backdrop)
--------------------------------------------------------------------------

local function popup(width, height, topCol, build)
    local w = Q.win
    if not (w and IsValid(w.frame)) then return end
    if IsValid(w.popup) then w.popup:Remove() end
    local o = vgui.Create("DPanel", w.frame)
    o:SetPos(0, 0)
    o:SetSize(w.frame:GetWide(), w.frame:GetTall())
    o:SetZPos(100)
    o:MoveToFront()
    function o:Paint(pw, ph)
        surface.SetDrawColor(C_OVERLAY)
        surface.DrawRect(0, 0, pw, ph)
    end
    local bw = math.min(S(width), o:GetWide() - S(40))
    local bh = math.min(height, o:GetTall() - S(40))
    local box = vgui.Create("DPanel", o)
    box:SetSize(bw, bh)
    box:SetPos((o:GetWide() - bw) / 2, (o:GetTall() - bh) / 2)
    box:DockPadding(S(22), S(20), S(22), S(20))
    function box:Paint(pw, ph)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(topCol)
        surface.DrawRect(0, 0, pw, S(3))
        surface.SetDrawColor(C_BLACK)
        surface.DrawOutlinedRect(0, 0, pw, ph)
    end
    w.popup = o
    build(box)
    return o
end

local function closePopup()
    local w = Q.win
    if w and IsValid(w.popup) then w.popup:Remove() end
    if w then w.popup = nil end
end

-- (title and a wrapped line under it, docked at the top of a popup box)
local function popupHead(box, title, sub, subLines)
    local t = vgui.Create("DPanel", box)
    t:Dock(TOP)
    t:SetTall(S(28))
    function t:Paint(pw, ph)
        draw.SimpleText(title, F(24, 800), 0, ph / 2, C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local l = K().Label(box, sub, 13, 400, C_DIM)
    l:SetAutoStretchVertical(false)
    l:SetContentAlignment(7)
    l:Dock(TOP)
    l:SetTall(S(18) * (subLines or 2) + S(2))
    l:DockMargin(0, S(4), 0, S(14))
end

-- A yes / cancel question (replacing or clearing a slot).
local function confirm(title, sub, yes, fn, danger)
    local h = S(20 + 28 + 4 + 38 + 14 + 44 + 8 + 40 + 20)
    popup(480, h, danger and C_RED or C_AMBER, function(box)
        popupHead(box, title, sub, 2)
        local b1 = button(box, yes, danger and "danger" or "primary", function()
            closePopup()
            fn()
        end)
        b1:Dock(TOP)
        b1:SetTall(S(44))
        local b2 = button(box, "Cancel", "ghost", closePopup)
        b2:Dock(TOP)
        b2:SetTall(S(40))
        b2:DockMargin(0, S(8), 0, 0)
    end)
end

-- What can't be issued (Skills board).
local function problemsPopup(slot, rows, nothing, again)
    local w = Q.win
    if not w then return end
    local s = w.data and w.data.slots[slot]
    local title = slotTitle(slot, s and s.name)
    local sub
    if nothing then
        sub = title .. ". None of it can be issued right now, so your kit stays as it is:"
    else
        sub = (again and "Something changed since you looked. " or "") .. title .. ". Everything else is ready. Choose what to do with these:"
    end
    local rowsH = math.min(#rows * S(50), S(300))
    local btnH = nothing and S(44) or (S(48) + S(8) + S(44) + S(8) + S(44))
    local h = S(20) + S(28) + S(4) + S(38) + S(14) + rowsH + S(14) + btnH + S(20)
    popup(560, h, C_AMBER, function(box)
        popupHead(box, nothing and "NOTHING CAN BE ISSUED" or "SOME ITEMS CAN'T BE ISSUED", sub, 2)
        local sp = K().Scroll(box)
        sp:Dock(TOP)
        sp:SetTall(rowsH)
        sp:DockMargin(0, 0, 0, S(14))
        for _, r in ipairs(rows) do
            local p = vgui.Create("DPanel", sp)
            p:Dock(TOP)
            p:SetTall(S(46))
            p:DockMargin(0, 0, #rows * S(50) > S(300) and S(10) or 0, S(4))
            local name = r.def and r.def.name or r.id or "Unknown item"
            local col = kindCol(r.def)
            local whyCol = (r.why == Q.WHY_STOCK or r.why == Q.WHY_HEAVY or r.why == Q.WHY_ROOM) and C_AMBER or C_BAN_ICON
            local nText = r.n > 1 and ("x" .. r.n) or ""
            local shownName, shownWhy = name, r.text
            function p:PerformLayout(pw)
                shownName = K().Fit(name, F(14, 700), pw - S(80))
                shownWhy = K().Fit(r.text, F(12), pw - S(80))
            end
            function p:Paint(pw, ph)
                surface.SetDrawColor(C_INSET)
                surface.DrawRect(0, 0, pw, ph)
                surface.SetDrawColor(col)
                surface.DrawRect(S(12), (ph - S(22)) / 2, S(3), S(22))
                draw.SimpleText(shownName, F(14, 700), S(27), ph / 2 - S(8), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(shownWhy, F(12), S(27), ph / 2 + S(10), whyCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(nText, F(12), pw - S(12), ph / 2, C_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        local function go(option)
            closePopup()
            local ww = Q.win
            if ww then ww.busy = CurTime() + 5 end
            act(Q.OP_APPLY, slot, function() net.WriteUInt(option, 2) end)
        end
        if nothing then
            local c = button(box, "Close", "ghost", closePopup)
            c:Dock(TOP)
            c:SetTall(S(44))
            return
        end
        local b1 = button(box, "Apply without them", "primary", function() go(Q.APPLY_WITHOUT) end)
        b1:Dock(TOP)
        b1:SetTall(S(48))
        local b2 = button(box, "Apply, and save the loadout without them", "outline", function() go(Q.APPLY_AND_SAVE) end, nil, { font = F(13, 500) })
        b2:Dock(TOP)
        b2:SetTall(S(44))
        b2:DockMargin(0, S(8), 0, 0)
        local b3 = button(box, "Cancel: keep my current kit", "ghost", closePopup, nil, { font = F(13, 500) })
        b3:Dock(TOP)
        b3:SetTall(S(44))
        b3:DockMargin(0, S(8), 0, 0)
    end)
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function saveTo(slot)
    local w = Q.win
    local s = w and w.data and w.data.slots[slot]
    local function go()
        local ww = Q.win
        if ww then ww.busy = CurTime() + 3 end
        act(Q.OP_SAVE, slot)
    end
    if s then
        confirm("REPLACE THIS LOADOUT?", slotTitle(slot, s.name) .. " is replaced by what you carry now (only what he can take in; job gear never).", "Replace it", go)
    else
        go()
    end
end

local function applySlot(slot)
    local w = Q.win
    if not w or busy() then return end
    w.busy = CurTime() + 5
    act(Q.OP_CHECK, slot)
end

local function canApply()
    local w = Q.win
    if not (w and w.data) then return false end
    return #w.data.blocked == 0 and CurTime() >= (w.data.readyAt or 0) and not busy()
end

local readyLeft, readyText   -- (the countdown text, made once a second)
local function applyLabel()
    local w = Q.win
    local d = w and w.data
    if not d then return "" end
    if #d.blocked > 0 then return "Can't apply: see above" end
    local left = math.ceil((d.readyAt or 0) - CurTime())
    if left > 0 then
        if left ~= readyLeft then readyLeft, readyText = left, "Ready in " .. left .. " s" end
        return readyText
    end
    if busy() then return "Working…" end
    return "Apply this loadout"
end

local function header(card, slot, s)
    local h = vgui.Create("DPanel", card)
    h:Dock(TOP)
    h:SetTall(S(36))
    local name = s and s.name or ("Slot " .. slot)
    local saved = s and ago(s.age) or "Nothing saved yet"
    local num = tostring(slot)
    local shown = name
    function h:PerformLayout(pw)
        shown = K().Fit(name, F(16, 700), pw - S(40) - (s and S(46) or 0))
    end
    function h:Paint(pw, ph)
        local bs = S(30)
        local by = (ph - bs) / 2
        surface.SetDrawColor(C_INSET)
        surface.DrawRect(0, by, bs, bs)
        surface.SetDrawColor(C_EDGE)
        surface.DrawOutlinedRect(0, by, bs, bs)
        draw.SimpleText(num, F(16, 800), bs / 2, ph / 2, s and C_TEXT or C_OFF, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(shown, F(16, 700), bs + S(10), ph / 2 - S(7), s and C_TEXT or C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(saved, F(11), bs + S(10), ph / 2 + S(10), C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    if s then
        local rb = vgui.Create("DButton", h)
        rb:SetText("")
        rb:Dock(RIGHT)
        rb:SetWide(S(36))
        rb:SetTooltip("Rename")
        function rb:Paint(pw, ph)
            if self:IsHovered() then
                surface.SetDrawColor(C_TILE)
                surface.DrawRect(0, 0, pw, ph)
            end
            surface.SetDrawColor(C_EDGE)
            surface.DrawOutlinedRect(0, 0, pw, ph)
            icon("editor", (pw - S(14)) / 2, (ph - S(14)) / 2, S(14), C_DIM)
            return true
        end
        function rb:DoClick()
            local max = math.floor(Rhylib.Config.Get("armoury", "qmNameMax"))
            K().Prompt("Rename loadout", "Up to " .. max .. " letters", s.name, function(t)
                local clean = Q.CleanName(t)
                if clean == "" then return end
                act(Q.OP_RENAME, slot, function() net.WriteString(clean) end)
            end)
        end
    end
end

local function filledCard(parent, slot, s, picked)
    local card = vgui.Create("DPanel", parent)
    card:DockPadding(S(14), S(14), S(14), S(14))
    function card:Paint(pw, ph)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(picked and C_PURPLE or C_EDGE)
        surface.DrawOutlinedRect(0, 0, pw, ph)
    end
    header(card, slot, s)

    local tiles = vgui.Create("DPanel", card)
    tiles:Dock(TOP)
    tiles:SetTall(S(50))
    tiles:DockMargin(0, S(10), 0, 0)
    local kgText = kg(s.kg)
    local kinds = #s.items .. (#s.items == 1 and " kind" or " kinds")
    function tiles:Paint(pw, ph)
        local tw = (pw - S(8)) / 2
        for i = 0, 1 do
            local x = i * (tw + S(8))
            surface.SetDrawColor(C_INSET)
            surface.DrawRect(x, 0, tw, ph)
            draw.SimpleText(i == 0 and "WEIGHT" or "ITEMS", F(10, 700), x + S(10), S(15), C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(i == 0 and kgText or kinds, F(15, 700), x + S(10), S(34), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- (bottom up: the save row, then Apply above it)
    local row = vgui.Create("DPanel", card)
    row:Dock(BOTTOM)
    row:SetTall(S(38))
    row.Paint = nil
    local clear = button(row, "Clear", "danger", function()
        confirm("CLEAR THIS LOADOUT?", slotTitle(slot, s.name) .. " is deleted. What you carry stays as it is.", "Clear it", function()
            act(Q.OP_CLEAR, slot)
        end, true)
    end, function() return not busy() end)
    clear:Dock(RIGHT)
    clear:SetWide(S(64))
    clear:DockMargin(S(6), 0, 0, 0)
    if editorOn() then
        local ed = button(row, "Edit", "outline", function() openEditor(slot) end, function() return not busy() end)
        ed:Dock(RIGHT)
        ed:SetWide(S(64))
        ed:DockMargin(S(6), 0, 0, 0)
    end
    local save = button(row, "Save current kit here", "outline", function() saveTo(slot) end, function() return not busy() end)
    save:Dock(FILL)

    local apply = button(card, applyLabel, "primary", function() applySlot(slot) end, canApply,
        { col = function() return picked and C_PURPLE or C_BLUE end })
    apply:Dock(BOTTOM)
    apply:SetTall(S(48))
    apply:DockMargin(0, 0, 0, S(6))

    local sp = K().Scroll(card)
    sp:Dock(FILL)
    sp:DockMargin(0, S(10), 0, S(10))
    for _, it in ipairs(s.items) do
        local right = it.worn and "worn" or (it.n > 1 and ("x" .. it.n) or "")
        local tag, tagCol
        if it.mark == 3 then tag, tagCol = "OUT OF STOCK", C_RED
        elseif it.mark >= 1 then tag, tagCol = "LOW STOCK", C_AMBER end
        local r = itemRow(sp, it.def, right, tag, tagCol, { tall = 28, bg = C_SIDE, nameSize = 12, rightSize = 11, small = true })
        r:Dock(TOP)
        r:DockMargin(0, 0, S(8), S(3))
    end
    return card
end

local function emptyCard(parent, slot)
    local card = vgui.Create("DPanel", parent)
    card:DockPadding(S(14), S(14), S(14), S(14))
    function card:Paint(pw, ph)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, ph)
        dashed(0, 0, pw, ph, C_EDGE)
        local cy = ph / 2 - S(10)
        icon("qm_crate", (pw - S(34)) / 2, cy - S(44), S(34), C_EMPTY_ICON)
        draw.SimpleText("Empty slot.", F(13), pw / 2, cy + S(4), C_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Kit yourself out at the armouries,", F(13), pw / 2, cy + S(24), C_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("then save it here.", F(13), pw / 2, cy + S(44), C_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    header(card, slot, nil)
    local save = button(card, "Save current kit here", "primary", function() saveTo(slot) end, function() return not busy() end, { font = F(13, 700) })
    save:Dock(BOTTOM)
    save:SetTall(S(44))
    if editorOn() then
        local cr = button(card, "Create loadout", "outline", function() openEditor(slot) end, function() return not busy() end, { font = F(13, 500) })
        cr:Dock(BOTTOM)
        cr:SetTall(S(40))
        cr:DockMargin(0, 0, 0, S(6))
    end
    return card
end

-- The red banner (Blocked board): why, and one chip per item.
local function banner(parent, blocked)
    local b = vgui.Create("DPanel", parent)
    b:Dock(TOP)
    b:DockMargin(0, 0, 0, S(14))
    local chips = {}
    local chipFont, whyFont = F(13, 500), F(11)
    for _, it in ipairs(blocked) do
        local name = it.def and it.def.name or "Unknown item"
        local why = Q.BLOCK_TEXT[it.why] or ""
        surface.SetFont(chipFont)
        local nw = surface.GetTextSize(name)
        surface.SetFont(whyFont)
        local ww = surface.GetTextSize(why)
        chips[#chips + 1] = { name = name, why = why, nw = nw, w = S(10) + nw + S(8) + ww + S(10) }
    end
    local title = "He can't take these in, so he won't swap your kit"
    local text = "Put them in your locker, hand them to someone or drop them, then come back. You can still save your current kit (only what he can take in is saved)."
    local shownText = text
    function b:PerformLayout(pw)
        local x0 = S(16) + S(22) + S(14)
        local maxW = pw - x0 - S(16)
        shownText = K().Fit(text, F(13), maxW)
        local x, y = 0, 0
        for _, c in ipairs(chips) do
            c.w = math.min(c.w, maxW)
            if x > 0 and x + c.w > maxW then
                x = 0
                y = y + S(36)
            end
            c.x, c.y = x0 + x, S(14) + S(18) + S(8) + S(18) + S(8) + y
            x = x + c.w + S(6)
        end
        local want = S(14) + S(18) + S(8) + S(18) + S(8) + y + S(30) + S(14)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    function b:Paint(pw, ph)
        surface.SetDrawColor(C_BAN_BG)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(C_BAN_EDGE)
        surface.DrawOutlinedRect(0, 0, pw, ph)
        icon("qm_alert", S(16), S(16), S(22), C_BAN_ICON)
        local x0 = S(16) + S(22) + S(14)
        draw.SimpleText(title, F(15, 700), x0, S(14) + S(9), C_BAN_TITLE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(shownText, F(13), x0, S(14) + S(18) + S(8) + S(9), C_BAN_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        for _, c in ipairs(chips) do
            if c.x then
                surface.SetDrawColor(C_CHIP_BG)
                surface.DrawRect(c.x, c.y, c.w, S(30))
                surface.SetDrawColor(C_BAN_EDGE)
                surface.DrawOutlinedRect(c.x, c.y, c.w, S(30))
                draw.SimpleText(c.name, chipFont, c.x + S(10), c.y + S(15), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(c.why, whyFont, c.x + S(10) + c.nw + S(8), c.y + S(15), C_BAN_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
    b:SetTall(S(120))
    return b
end

local function fill(w)
    local d = w.data
    local left, right = w.left, w.right
    left:Clear()
    right:Clear()

    -- Left: YOU CARRY NOW
    local top = vgui.Create("DPanel", left)
    top:Dock(TOP)
    top:SetTall(S(22))
    top:DockMargin(0, 0, 0, S(10))
    local wText = kg(d.weight)
    function top:Paint(pw, ph)
        draw.SimpleText("YOU CARRY NOW", F(14, 800), 0, ph / 2, C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(wText, F(12), pw, ph / 2, C_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local foot = K().Label(left, "Job gear (your spawn kit) stays with you and isn't part of a loadout.", 12, 400, C_LABEL)
    foot:Dock(BOTTOM)
    foot:DockMargin(0, S(10), 0, 0)
    local sp = K().Scroll(left)
    sp:Dock(FILL)
    if #d.carry == 0 then
        local e = K().Label(sp, "You carry nothing.", 13, 400, C_DIM)
        e:Dock(TOP)
    end
    for _, it in ipairs(d.carry) do
        local right = it.worn and "worn" or (it.pct and (it.pct .. "%")) or (it.n > 1 and ("x" .. it.n) or "")
        local tag, tagCol
        if it.kind == Q.KIND_JOB then tag, tagCol = "JOB GEAR", C_LABEL
        elseif it.kind == Q.KIND_BLOCKED then tag, tagCol = "CAN'T TAKE", C_BAN_ICON end
        local r = itemRow(sp, it.def, right, tag, tagCol, { dim = it.kind == Q.KIND_JOB })
        r:Dock(TOP)
        r:DockMargin(0, 0, S(8), S(6))
    end

    -- Right: the banner, the cards, the note
    if #d.blocked > 0 then banner(right, d.blocked) end
    local note = vgui.Create("DPanel", right)
    note:Dock(BOTTOM)
    note:DockMargin(0, S(14), 0, 0)
    note:DockPadding(S(44), S(10), S(14), S(10))
    function note:Paint(pw, ph)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, ph)
        icon("qm_check", S(14), (ph - S(18)) / 2, S(18), C_GREEN)
    end
    local nl = K().Label(note, "Applying hands your current kit back into the armoury stock and issues the loadout from it. Magazines, power cells and kit charges always come full, even if you saved them half empty. Job gear stays where it is.", 12, 400, C_DIM)
    nl:Dock(TOP)
    note:SetTall(S(56))
    function note:PerformLayout()
        local want = nl:GetTall() + S(20)
        if want > S(20) and self:GetTall() ~= want then self:SetTall(want) end
    end

    local area = vgui.Create("DPanel", right)
    area:Dock(FILL)
    area.Paint = nil
    local cards = {}
    for n = 1, Q.SLOTS do
        local s = d.slots[n]
        cards[n] = s and filledCard(area, n, s, d.applied == n) or emptyCard(area, n)
    end
    function area:PerformLayout(pw, ph)
        local gap = S(14)
        local cw = math.floor((pw - gap * (Q.SLOTS - 1)) / Q.SLOTS)
        for i, c in ipairs(cards) do
            c:SetPos((i - 1) * (cw + gap), 0)
            c:SetSize(cw, ph)
        end
    end
end

local function open(npc, data)
    local k = K()
    if not k then return end
    ensureIcons()
    local w = Q.win
    if w and IsValid(w.frame) and w.npc == npc then
        w.data = data
        w.busy = nil
        fill(w)
        return
    end
    close(false)
    local f = vgui.Create("EditablePanel")
    f:SetSize(math.min(ScrW() - S(40), S(1240)), math.min(ScrH() - S(40), S(740)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:DockPadding(0, S(76), 0, 0)
    w = { frame = f, npc = npc, data = data }
    Q.win = w
    local sub = "Save what you carry as a loadout, then swap your whole kit in one go"
    function f:Paint(pw, ph)
        surface.SetDrawColor(C_WIN)
        surface.DrawRect(0, 0, pw, ph)
        local hh = S(76)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, hh)
        surface.SetDrawColor(C_PURPLE)
        surface.DrawRect(0, 0, pw, S(3))
        surface.SetDrawColor(C_BLACK)
        surface.DrawRect(0, hh - 1, pw, 1)
        local bs = S(42)
        local bx, by = S(24), (hh + S(3) - bs) / 2
        surface.SetDrawColor(C_PURPLE_BG)
        surface.DrawRect(bx, by, bs, bs)
        surface.SetDrawColor(C_PURPLE)
        surface.DrawOutlinedRect(bx, by, bs, bs)
        icon("qm_crate", bx + (bs - S(22)) / 2, by + (bs - S(22)) / 2, S(22), C_PURPLE)
        local tx = bx + bs + S(16)
        draw.SimpleText("QUARTERMASTER", F(26, 800), tx, hh / 2 - S(8), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, F(12), tx, hh / 2 + S(15), C_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C_BLACK)
        surface.DrawOutlinedRect(0, 0, pw, ph)
    end
    function f:Think()
        local open = false
        for pr in pairs(UI.prompts or {}) do
            if IsValid(pr) then open = true break end
        end
        w.prompt = open
        w.editor = Q.editor ~= nil and IsValid(Q.editor.frame)
        local me = LocalPlayer()
        local r = Rhylib.Config.Get("armoury", "qmRange") + 60
        if not IsValid(npc) or not IsValid(me) or not me:Alive() or me:GetPos():DistToSqr(npc:GetPos()) > r * r then
            close(true)
        end
    end
    local x = vgui.Create("DButton", f)
    x:SetText("")
    x:SetSize(S(44), S(44))
    x:SetPos(f:GetWide() - S(24) - S(44), (S(76) + S(3) - S(44)) / 2)
    function x:Paint(pw, ph)
        if self:IsHovered() then
            surface.SetDrawColor(C_TILE)
            surface.DrawRect(0, 0, pw, ph)
        end
        surface.SetDrawColor(C_EDGE)
        surface.DrawOutlinedRect(0, 0, pw, ph)
        icon("qm_close", (pw - S(16)) / 2, (ph - S(16)) / 2, S(16), C_DIM)
        return true
    end
    function x:DoClick() close(true) end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body.Paint = nil
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(math.min(S(300), math.floor(f:GetWide() * 0.3)))
    left:DockPadding(S(18), S(18), S(18), S(18))
    function left:Paint(pw, ph)
        surface.SetDrawColor(C_SIDE)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(C_BLACK)
        surface.DrawRect(pw - 1, 0, 1, ph)
    end
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right:DockPadding(S(22), S(18), S(22), S(18))
    right.Paint = nil
    w.left, w.right = left, right
    fill(w)
end

--------------------------------------------------------------------------
-- The handout (Handout board): a bar the client runs from the start
-- time and duration the server sent once
--------------------------------------------------------------------------

local C_BAR_BG = Color(11, 12, 11)

local function closeHand()
    local w = Q.win
    if w and IsValid(w.handPanel) then w.handPanel:Remove() end
    if w then w.handPanel, w.hand = nil, nil end
end

local function showHand(h)
    local w = Q.win
    if not (w and IsValid(w.frame)) then return end
    closeHand()
    w.hand = h
    local f = w.frame
    local o = vgui.Create("DPanel", f)
    o:SetPos(1, S(76))
    o:SetSize(f:GetWide() - 2, f:GetTall() - S(76) - 1)
    o:SetZPos(50)
    o:MoveToFront()
    if IsValid(w.popup) then w.popup:MoveToFront() end
    function o:Paint(pw, ph)
        surface.SetDrawColor(C_WIN)
        surface.DrawRect(0, 0, pw, ph)
    end
    local s = w.data and w.data.slots[h.slot]
    local title = "HANDING OUT · " .. string.upper(s and s.name or Q.DefaultName(h.slot))
    local steps = { "Taking in your current kit", "Issuing weapons", "Topping off magazines and cells" }
    if h.backpack then steps[#steps + 1] = "Packing your backpack" end
    local bw = math.min(S(620), o:GetWide() - S(40))
    local stepsH = #steps * S(20)
    local bh = S(22) + S(28) + S(14) + S(12) + S(14) + stepsH + S(14) + S(18) + S(14) + S(44) + S(22)
    local box = vgui.Create("DPanel", o)
    box:SetSize(bw, bh)
    box:SetPos((o:GetWide() - bw) / 2, (o:GetTall() - bh) / 2)
    local lastTenth, leftText = -1, ""
    local shownTitle = K().Fit(title, F(24, 800), bw - S(48) - S(70))
    local shownNote = K().Fit("Stay at the counter: walking away, getting downed or cuffed stops it and you keep your current kit.", F(12), bw - S(48))
    local diamonds = {}   -- (made once: the box doesn't change size)
    function box:Paint(pw, ph)
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(C_EDGE)
        surface.DrawOutlinedRect(0, 0, pw, ph)
        surface.SetDrawColor(C_PURPLE)
        surface.DrawRect(0, 0, pw, S(3))
        local frac = h.dur > 0 and math.Clamp((CurTime() - h.start) / h.dur, 0, 1) or 1
        local tenth = math.max(0, math.ceil((h.start + h.dur - CurTime()) * 10))
        if tenth ~= lastTenth then
            lastTenth = tenth
            leftText = string.format("%.1f s", tenth / 10)
        end
        local x, y = S(24), S(22)
        draw.SimpleText(shownTitle, F(24, 800), x, y + S(14), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(leftText, F(16, 700), pw - S(24), y + S(14), C_PURPLE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        y = y + S(28) + S(14)
        local barW = pw - S(48)
        surface.SetDrawColor(C_BAR_BG)
        surface.DrawRect(x, y, barW, S(12))
        surface.SetDrawColor(C_PURPLE)
        surface.DrawRect(x, y, math.floor(barW * frac), S(12))
        surface.SetDrawColor(C_EDGE)
        surface.DrawOutlinedRect(x, y, barW, S(12))
        y = y + S(12) + S(14)
        local n = #steps
        for i = 1, n do
            local col = frac >= i / n and C_GREEN or (frac >= (i - 1) / n and C_TEXT or C_OFF)
            local d = S(4)
            local cx, cy = x + d, y + S(10)
            surface.SetDrawColor(col)
            draw.NoTexture()
            local dm = diamonds[i]
            if not dm then
                dm = { { x = cx, y = cy - d }, { x = cx + d, y = cy }, { x = cx, y = cy + d }, { x = cx - d, y = cy } }
                diamonds[i] = dm
            end
            surface.DrawPoly(dm)
            draw.SimpleText(steps[i], F(13), x + S(18), cy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            y = y + S(20)
        end
        y = y + S(14)
        draw.SimpleText(shownNote, F(12), x, y + S(9), C_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local stop = button(box, "Stop", "outline", function() act(Q.OP_STOP, h.slot) end, nil, { font = F(13, 500) })
    stop:SetSize(bw - S(48), S(44))
    stop:SetPos(S(24), bh - S(22) - S(44))
    w.handPanel = o
end

--------------------------------------------------------------------------
-- Nets
--------------------------------------------------------------------------

local function readDef()
    local It = Rhylib.Items
    return It and It.FromNet and It.FromNet(net.ReadUInt(It.NET_BITS)) or nil
end

Rhylib.Net.Receive("armoury.qm", function()
    local It = Rhylib.Items
    if not It then return end
    local npc = net.ReadEntity()
    local d = { carry = {}, blocked = {}, slots = {} }
    d.weight = net.ReadUInt(12) / 10
    d.cooldown = net.ReadUInt(8)
    d.applied = net.ReadUInt(2)
    local nc = net.ReadUInt(8)
    for _ = 1, nc do
        local def = readDef()
        local n = net.ReadUInt(8)
        local kind = net.ReadUInt(2)
        local worn = net.ReadBool()
        local pct = net.ReadUInt(7)
        d.carry[#d.carry + 1] = { def = def, n = n, kind = kind, worn = worn, pct = pct ~= 127 and pct or nil }
    end
    local nb = net.ReadUInt(6)
    for _ = 1, nb do
        local def = readDef()
        local why = net.ReadUInt(2)
        d.blocked[#d.blocked + 1] = { def = def, why = why }
    end
    for n = 1, Q.SLOTS do
        if net.ReadBool() then
            local s = { items = {} }
            s.name = net.ReadString()
            s.age = net.ReadUInt(32)
            s.kg = net.ReadUInt(12) / 10
            local nk = net.ReadUInt(7)
            for _ = 1, nk do
                local def = readDef()
                local cnt = net.ReadUInt(8)
                local worn = net.ReadBool()
                local mark = net.ReadUInt(2)
                s.items[#s.items + 1] = { def = def, n = cnt, worn = worn, mark = mark }
            end
            d.slots[n] = s
        end
    end
    d.readyAt = CurTime() + d.cooldown
    if not IsValid(npc) then return end
    open(npc, d)
end)

Rhylib.Net.Receive("armoury.qmhand", function()
    local npc = net.ReadEntity()
    local running = net.ReadBool()
    local h
    if running then
        h = { slot = net.ReadUInt(2) }
        h.dur = net.ReadFloat()
        local left = net.ReadFloat()
        h.backpack = net.ReadBool()
        h.start = CurTime() - math.max(0, h.dur - left)   -- (from the time left: no clock to match)
    end
    local w = Q.win
    if not (w and IsValid(w.frame) and w.npc == npc) then return end
    if h then
        closePopup()
        w.busy = nil
        showHand(h)
    else
        closeHand()
    end
end)

Rhylib.Net.Receive("armoury.qmprob", function()
    local It = Rhylib.Items
    if not It then return end
    local npc = net.ReadEntity()
    local slot = net.ReadUInt(2)
    local nothing = net.ReadBool()
    local again = net.ReadBool()
    local n = net.ReadUInt(7)
    local rows = {}
    for _ = 1, n do
        local nid = net.ReadUInt(It.NET_BITS)
        local def = nid > 0 and It.FromNet(nid) or nil
        local id = nid == 0 and net.ReadString() or nil
        local cnt = net.ReadUInt(8)
        local why = net.ReadUInt(3)
        local text = net.ReadString()
        rows[#rows + 1] = { def = def, id = id, n = cnt, why = why, text = text }
    end
    local w = Q.win
    if not (w and IsValid(w.frame) and w.npc == npc) then return end
    w.busy = nil
    if n == 0 and not nothing then
        -- (nothing in the way: go ahead)
        w.busy = CurTime() + 5
        act(Q.OP_APPLY, slot, function() net.WriteUInt(Q.APPLY_PLAIN, 2) end)
        return
    end
    problemsPopup(slot, rows, nothing, again)
end)

-- For the editor (cl_55_quartermaster_editor.lua): the window's pieces.
Q.UIH = {
    K = K, S = S, F = F, icon = icon, kindCol = kindCol, dashed = dashed, button = button,
    act = act, slotTitle = slotTitle, kg = kg,
    C = { WIN = C_WIN, SIDE = C_SIDE, CARD = C_CARD, INSET = C_INSET, TILE = C_TILE, EDGE = C_EDGE, BLACK = C_BLACK,
        TEXT = C_TEXT, DIM = C_DIM, LABEL = C_LABEL, OFF = C_OFF, BLUE = C_BLUE, AMBER = C_AMBER, RED = C_RED,
        GREEN = C_GREEN, PURPLE = C_PURPLE, HOVER = C_HOVER },
}
