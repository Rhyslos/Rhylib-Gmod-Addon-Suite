--[[
    Battalion page in the pause menu (also /roster): your character, your
    battalion's members and ranks, and the roster log. Sergeants and up
    (manageRank) promote, demote and remove members below them, add CTs to
    the battalion and pass cadets through basic training. Admins pick any
    battalion. Cadets get "Request basic training" (roster.trainreq) and a
    note pointing to the training instructor NPC (the quiz, sh_60_quiz.lua).
    Client only; the page needs rhylib_menus. Asks with roster.get, draws
    roster.data (see R.SendRoster in sv_10_roster.lua), sends roster.act.
    Every action is checked again on the server; the buttons here only
    hide what you aren't allowed to do.
    Look: a card on top (your name, rank chip, where you stand; members /
    online numbers on the right), admins' battalion dropdown, an amber
    basic training box for cadets, then bands (diamond, name, counts) over
    alternating rows: members (online dot, rank chip, name, rank · last
    seen · note, Manage menu), CTs to add, cadets, the roster log. Removing
    and passing ask first (R.Draw.Confirm).
]]

local R = Rhylib.Roster
local data            -- last roster.data
local adminBn = ""    -- battalion an admin is looking at ("" = their own)

local ACT_TRAIN, ACT_ADD, ACT_RANK, ACT_REMOVE = 0, 1, 2, 3   -- (same as R.ACT_* on the server)

local function K() return Rhylib.UI and Rhylib.UI.Kit end

local function act(a, id, value)
    Rhylib.Net.Start("roster.act")
    net.WriteUInt(a, 2)
    net.WriteString(id)
    net.WriteUInt(value or 0, 8)
    net.SendToServer()
end

local function request()
    Rhylib.Net.Start("roster.get")
    net.WriteString(adminBn)
    net.SendToServer()
end

-- Every battalion name used by a DarkRP job (the admin picker).
local function battalions()
    local out, seen = {}, {}
    for _, j in pairs(RPExtraTeams or {}) do
        if j.battalion and not seen[j.battalion] then
            seen[j.battalion] = true
            out[#out + 1] = j.battalion
        end
    end
    table.sort(out)
    return out
end

local function seenText(m)
    if m.on then return "online" end
    if m.seen <= 0 then return "" end
    local d = os.time() - m.seen
    if d < 3600 then return "seen " .. math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return "seen " .. math.floor(d / 3600) .. " h ago" end
    return "seen " .. math.floor(d / 86400) .. " d ago"
end

-- The battalion's colour: its jobs' colour (game data), or nil.
local function bnColour(bn)
    if bn == "" then return nil end
    for _, j in pairs(RPExtraTeams or {}) do
        if j.battalion == bn and IsColor(j.color) then return j.color end
    end
end

-- A list row: alternating fill, hover, edges. Returns the panel (docked TOP).
local function listRow(parent, i, tall)
    local k = K()
    local s = k.S
    local r = vgui.Create("DPanel", parent)
    r:Dock(TOP)
    r:SetTall(tall or s(48))
    r:DockMargin(0, 0, s(8), 0)
    local pad = math.max(0, math.floor((r:GetTall() - s(26)) / 2))
    r:DockPadding(s(12), pad, s(12), pad)
    r.alt = i % 2 == 0
    function r:Paint(w, h)
        local C = k.C
        k.SetCol(self:IsHovered() and C.rowHover or (self.alt and C.rowAlt or C.row))
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawRect(0, h - 1, w, 1)
        if self.PaintRow then self:PaintRow(w, h) end
    end
    return r
end

local function build(page)
    local k = K()
    local s = k.S
    local C = k.C
    local D = R.Draw
    local me = R.Get(LocalPlayer())

    if not data then
        local l = k.Label(page, "Loading…", 14, 400, C.textDim)
        l:Dock(TOP)
        request()
        return
    end

    local bnCol = bnColour(data.bn)
    local online = 0
    for _, m in ipairs(data.members) do if m.on then online = online + 1 end end

    -- You: a card with your name, where you stand, and the battalion's numbers.
    local you = vgui.Create("DPanel", page)
    you:Dock(TOP)
    you:SetTall(s(84))
    you:DockMargin(0, 0, 0, s(10))
    local myLine
    if not me.has then myLine = "No character yet"
    elseif me.bn ~= "" then myLine = R.RankName(me.rank) .. " in the " .. me.bn
    elseif me.trained then myLine = "Clone trooper, not in a battalion yet"
    else myLine = "Cadet: waiting for basic training" end
    local chip = (me.has and me.bn ~= "" and R.RankPrefix(me.rank)) or (me.trained and "CT") or (me.has and "CADET") or nil
    local myBnCol = bnColour(me.bn)
    local function stateCol() return (me.has and not me.trained) and C.warn or (myBnCol or C.accent) end
    local bnText = data.bn ~= "" and string.upper(data.bn) or nil
    local nMembers, nOnline = tostring(#data.members), tostring(online)
    function you:Paint(w, h)
        local sc = stateCol()
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(sc, 22)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(sc)
        surface.DrawRect(0, 0, s(4), h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.Ticks(0, 0, w, h, false)
        local isz = s(40)
        k.SetCol(C.header)
        surface.DrawRect(s(18), (h - isz) * 0.5, isz, isz)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(s(18), (h - isz) * 0.5, isz, isz)
        k.Icon("battalion", s(18) + s(8), (h - isz) * 0.5 + s(8), isz - s(16), sc)
        local x = s(18) + isz + s(14)
        local name = R.FullName(LocalPlayer()) or LocalPlayer():Nick()
        local statW = data.bn ~= "" and s(220) or 0
        draw.SimpleText(k.Fit(name, k.Font(22, 800), w - x - statW - s(90)), k.Font(22, 800), x, h * 0.38, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(k.Font(22, 800))
        local nw = math.min(surface.GetTextSize(name), w - x - statW - s(90))
        if chip and D then D.Chip(chip, x + nw + s(10), h * 0.38, sc) end
        draw.SimpleText(myLine, k.Font(13), x, h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- (the battalion's numbers, right-aligned)
        if data.bn ~= "" then
            local rx = w - s(18)
            draw.SimpleText(nOnline, k.Font(24, 800), rx, h * 0.42, C.good, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            k.Caps("Online", rx, h * 0.74, C.label, TEXT_ALIGN_RIGHT)
            rx = rx - s(90)
            draw.SimpleText(nMembers, k.Font(24, 800), rx, h * 0.42, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            k.Caps("Members", rx, h * 0.74, C.label, TEXT_ALIGN_RIGHT)
            k.SetCol(C.edgeLight)
            surface.DrawRect(w - statW - s(4), s(14), 1, h - s(28))
        end
    end

    -- Admins: which battalion to look at.
    if data.admin then
        local row = k.Row(page, "Battalion", "Admins can manage any battalion")
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, s(8))
        row.right:SetWide(s(260))
        local function opts()
            local out = {}
            for _, bn in ipairs(battalions()) do out[#out + 1] = { bn, bn } end
            return out
        end
        local dd = k.Dropdown(row.right, opts(), function() return data and data.bn or adminBn end, function(bn)
            adminBn = bn
            data = nil
            request()
        end, { placeholder = "Pick one", width = s(260) })
        dd:Dock(FILL)
    end

    local sp = k.Scroll(page)
    sp:Dock(FILL)
    local function band(text, col, right)
        local b = D.Band(sp, text, col, right and function() return right end or nil)
        b:Dock(TOP)
        b:DockMargin(0, s(10), s(8), 0)
    end
    local function note(text)
        local l = k.Label(sp, text, 13, 400, C.textDim)
        l:Dock(TOP)
        l:DockMargin(s(4), s(6), s(8), s(6))
    end
    local function rowButton(r, text, fn, opts, w)
        local b = k.Button(r, text, fn, opts)
        b:Dock(RIGHT)
        b:SetWide(s(w or 120))
        b:DockMargin(s(6), 0, 0, 0)
        return b
    end

    -- A cadet can ask for an instructor (roster.trainreq); the quiz is at
    -- a training instructor NPC (E on him, sh_60_quiz.lua).
    if me.has and not me.trained then
        local box = vgui.Create("DPanel", sp)
        box:Dock(TOP)
        box:DockMargin(0, 0, s(8), s(4))
        box:DockPadding(s(18), s(32), s(14), s(12))
        function box:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.warn, 20)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.warn)
            surface.DrawRect(0, 0, s(3), h)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            D.Diamond(s(22), s(18), s(4), C.warn)
            k.Caps("Basic training", s(32), s(18), C.warn)
        end
        local b = k.Button(box, "Request basic training", function()
            Rhylib.Net.Start("roster.trainreq")
            net.SendToServer()
        end, { accent = true, tooltip = "Tells every Sergeant or higher online that you're waiting" })
        b:Dock(RIGHT)
        b:SetWide(s(230))
        b:DockMargin(s(12), 0, 0, 0)
        local text = R.Cfg("quiz") and "Know how to play? Find a training instructor and press E on him to take the basic training quiz. Or ask for an instructor to come and train you."
            or "An instructor (a Sergeant or higher) passes you through basic training."
        local l = k.Label(box, text, 13, 400, C.text)
        l:Dock(TOP)
        function box:PerformLayout()
            local want = math.max(s(34), l:GetTall()) + s(44)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
    end

    -- Members.
    if data.bn == "" then
        note(data.admin and "Pick a battalion above." or "You're not in a battalion. A Sergeant or higher of a battalion can add you once you're a clone trooper.")
    else
        band(data.bn, bnCol, #data.members .. " member" .. (#data.members == 1 and "" or "s") .. "  ·  " .. online .. " online")
        local limit = data.limit   -- you can give ranks below this
        local nRanks = #R.Ranks()
        for i, m in ipairs(data.members) do
            local r = listRow(sp, i, s(50))
            local prefix = R.RankPrefix(m.r) or "—"
            local sub = R.RankName(m.r) .. "  ·  " .. seenText(m) .. (m.note ~= "" and ("  ·  " .. m.note) or "")
            local canAct = data.manager and m.r < limit and (data.admin or m.id ~= LocalPlayer():SteamID64())
            function r:PaintRow(w, h)
                local cy = h * 0.5
                -- (online dot)
                draw.RoundedBox(s(4), s(14), cy - s(4), s(8), s(8), m.on and C.good or C.tick)
                -- (rank chip in a fixed column)
                local cx = s(32)
                k.SetCol(C.header)
                surface.DrawRect(cx, cy - s(11), s(52), s(22))
                k.SetCol(bnCol or C.accent, 160)
                surface.DrawOutlinedRect(cx, cy - s(11), s(52), s(22))
                draw.SimpleText(prefix, k.Font(12, 700), cx + s(26), cy, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                local x = cx + s(66)
                local room = w - x - (canAct and s(150) or s(12))
                draw.SimpleText(k.Fit(m.name, k.Font(15, 700), room), k.Font(15, 700), x, h * 0.34, m.on and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(k.Fit(sub, k.Font(12), room), k.Font(12), x, h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            if canAct then
                -- Manage: a small menu with what you're allowed to do.
                local b = rowButton(r, "Manage", function()
                    local menu = D.Menu()
                    local up, down = m.r + 1, m.r - 1
                    local o = menu:AddOption("Promote to " .. R.RankName(up), function() act(ACT_RANK, m.id, up) end)
                    if not (up < limit and up <= nRanks) then o:SetEnabled(false) end
                    o = menu:AddOption("Demote to " .. (down >= 1 and R.RankName(down) or "—"), function() act(ACT_RANK, m.id, down) end)
                    if down < 1 then o:SetEnabled(false) end
                    -- Any rank at once (below yours).
                    local subMenu = menu:AddSubMenu("Set rank")
                    for ri = 1, nRanks do
                        if ri < limit and ri ~= m.r then
                            subMenu:AddOption(R.RankName(ri), function() act(ACT_RANK, m.id, ri) end)
                        end
                    end
                    menu:AddSpacer()
                    menu:AddOption("Remove from the " .. data.bn, function()
                        D.Confirm("Remove member", "Remove " .. m.name .. " from the " .. data.bn .. "?", "Remove", function() act(ACT_REMOVE, m.id) end, true)
                    end)
                    menu:Open()
                end, { small = true, align = "left" }, 130)
                function b:PaintOver(w, h) k.Arrow(w - s(14), h * 0.5, s(8), "down", C.textDim) end
            end
        end
        if #data.members == 0 then note("Nobody yet.") end
    end

    -- Officers: people waiting.
    if data.manager then
        if data.bn ~= "" and #data.cts > 0 then
            band("Clone troopers to add", C.accent, #data.cts .. " waiting")
            note("Adding someone from another battalion moves them here as PVT.")
            for i, p in ipairs(data.cts) do
                local r = listRow(sp, i, s(44))
                function r:PaintRow(w, h)
                    draw.SimpleText(k.Fit(p.name, k.Font(15, 700), w - s(240)), k.Font(15, 700), s(14), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                rowButton(r, "Add to " .. data.bn, function() act(ACT_ADD, p.id) end, { small = true, accent = true }, 190)
            end
        end
        if #data.cadets > 0 then
            band("Cadets", C.warn, #data.cadets .. " waiting for basic training")
            for i, p in ipairs(data.cadets) do
                local r = listRow(sp, i, s(44))
                function r:PaintRow(w, h)
                    D.Chip("CADET", s(14), h * 0.5, C.warn)
                    draw.SimpleText(k.Fit(p.name, k.Font(15, 700), w - s(320)), k.Font(15, 700), s(80), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                rowButton(r, "Pass basic training", function()
                    D.Confirm("Basic training", p.name .. " passed basic training and becomes a clone trooper?", "Pass", function() act(ACT_TRAIN, p.id) end)
                end, { small = true, accent = true }, 200)
            end
        end
    end

    -- Log.
    if data.bn ~= "" then
        band("Roster log", C.label, #data.log > 0 and (#data.log .. " entries") or nil)
        if #data.log == 0 then note("Nothing yet.") end
        for i, e in ipairs(data.log) do
            local when = string.upper(os.date("%d %b %H:%M", e.t))
            local r = listRow(sp, i, s(32))
            function r:PaintRow(w, h)
                draw.SimpleText(when, k.Font(11, 700), s(14), h * 0.5, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(k.Fit(e.txt, k.Font(13), w - s(150)), k.Font(13), s(130), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage) then return end
    Menus.AddPage("roster", {
        title = "Battalion",
        order = 40,
        section = "you",
        icon = "battalion",
        build = function(page)
            data = nil   -- fresh every time the page opens
            build(page)
        end,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "roster.page", addPage)

Rhylib.Net.Receive("roster.data", function()
    local d = { members = {}, cadets = {}, cts = {}, log = {} }
    d.bn = net.ReadString()
    d.admin = net.ReadBool()
    d.manager = net.ReadBool()
    d.limit = net.ReadUInt(8)
    for i = 1, net.ReadUInt(8) do
        d.members[i] = { id = net.ReadString(), name = net.ReadString(), r = net.ReadUInt(8), on = net.ReadBool(), seen = net.ReadUInt(32), note = net.ReadString() }
    end
    for i = 1, net.ReadUInt(6) do d.cadets[i] = { id = net.ReadString(), name = net.ReadString() } end
    for i = 1, net.ReadUInt(6) do d.cts[i] = { id = net.ReadString(), name = net.ReadString() } end
    for i = 1, net.ReadUInt(6) do d.log[i] = { t = net.ReadUInt(32), txt = net.ReadString() } end
    data = d
    -- Draw it without asking again (build() would clear data).
    local Menus = Rhylib.Menus
    if Menus and IsValid(Menus.pause) and Menus.pause.pageId == "roster" then
        Menus.pause.page:Clear()
        build(Menus.pause.page)
    end
end)

-- /roster: open the pause menu on this page.
Rhylib.Net.Receive("roster.open", function()
    local Menus = Rhylib.Menus
    if not Menus then return end
    Menus.lastPage = "roster"
    if IsValid(Menus.pause) then Menus.pause:ShowPage("roster") else Menus.OpenPause() end
end)
