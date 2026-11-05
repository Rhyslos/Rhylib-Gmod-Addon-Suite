--[[
    The Radio page (client; pause menu section "you", also the radio page
    key, default T, or the console command rhylib_radio). Needs
    rhylib_menus (Menus.AddPage and its Kit); without it there is no page.
    A wide page.

    Top row: the radio state chip (radio on and the talk key, off, muted,
            deafened, jammed) and the buttons: mute mic, deafen, hide on
            radar (only while the server's showEveryone is on), radio
            off / on.
    Left:   YOUR CHANNELS as cards (Local, Squad, Channel 1, Channel 2):
            a diamond in the slot colour, the slot, name and who is on it;
            "Talk here" (lit in the slot colour while the radio key talks
            there), mute, leave, or create on an empty slot. Then OPEN
            CHANNELS to join (and "New channel" while a slot is free).
    Middle: your squad card (name, members, open / locked; rename, lock
            and leave; member rows with role symbol, role, LEAD / RO chip,
            distance, TALKING, and a ... button: your role, hail a mate,
            and the leader actions). Without a squad: create one. Then
            OTHER SQUADS as cards (Hail rings its leader and RO, Join, ...
            hails one member).
    Right:  hails ringing (answer / decline) and the call you're in (hang
            up) as highlighted cards, then the squad map (you in the middle
            facing up), its legend and the HUD compass switch.
    Closing the page never ends a call. The page rebuilds itself when
    something changes (R.Changed); live bits (talking, distance, state)
    are read while drawing.
]]

local R = Rhylib.Radio

local MODE_TEXT = { [0] = "open", [1] = "password", [2] = "battalion" }

local function K() return Rhylib.UI.Kit end

-- Board colours.
local COL = {
    inset = Color(14, 16, 15), side = Color(18, 20, 19), card = Color(22, 25, 23), tile = Color(26, 30, 27),
    sel = Color(27, 37, 48), talkCard = Color(22, 28, 25),
    edge = Color(42, 45, 41), edgeHover = Color(70, 75, 68), faint = Color(31, 35, 32), black = Color(0, 0, 0),
    text = Color(228, 227, 220), dim = Color(169, 168, 160), label = Color(138, 140, 132), off = Color(111, 116, 109),
    dark = Color(20, 20, 19),
    blue = Color(133, 183, 235), amber = Color(239, 159, 39), red = Color(226, 75, 74), green = Color(151, 196, 89),
    purple = Color(164, 110, 224),
    dangerEdge = Color(90, 42, 42), dangerText = Color(240, 149, 149),
    onBg = Color(20, 32, 23), onEdge = Color(45, 74, 42),
    warnBg = Color(32, 26, 14), warnEdge = Color(107, 82, 32),
    badBg = Color(34, 18, 18),
    hailBg = Color(29, 26, 18), hailEdge = Color(107, 82, 32), hailDim = Color(200, 176, 122), hailText = Color(232, 207, 154),
}
local MODE_COL = { [0] = COL.blue, [1] = COL.amber, [2] = COL.purple }

local DIA = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
-- A filled diamond (no table made per call).
local function diamond(cx, cy, r, col, a)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K().SetCol(col, a)
    surface.DrawPoly(DIA)
end

local function clock(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function pick(v) if isfunction(v) then return v() end return v end

--[[
    A board style button. o: kind ("outline" default, "primary" filled,
    "danger" red outline; may be a function), col (fill colour for primary
    and lit; Color or function), lit (function -> bool: filled in col),
    enabled (bool or function), tooltip, widthText (text to size by),
    wide (fixed width), dots (draws three dots instead of text), h.
]]
local function btn(parent, text, fn, o)
    local Kit = K()
    local S = Kit.S
    o = o or {}
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(S(o.h or 34))
    b.label, b.o = text, o
    if o.tooltip then b:SetTooltip(o.tooltip) end
    local fontN, fontB = Kit.Font(13, 500), Kit.Font(13, 700)
    if o.wide then
        b:SetWide(o.wide)
    elseif not o.dots then
        surface.SetFont(fontB)
        b:SetWide(surface.GetTextSize(o.widthText or pick(text) or "") + S(28))
    else
        b:SetWide(S(36))
    end
    function b:IsOn()
        local e = self.o.enabled
        if e == nil then return true end
        if isfunction(e) then return e() and true or false end
        return e and true or false
    end
    function b:Paint(w, h)
        local on = self:IsOn()
        local hov = on and self:IsHovered()
        local kind = pick(self.o.kind) or "outline"
        local lit = self.o.lit and self.o.lit()
        local tc
        if lit or kind == "primary" then
            Kit.SetCol(pick(self.o.col) or COL.blue, on and (hov and 255 or 225) or 60)
            surface.DrawRect(0, 0, w, h)
            tc = COL.dark
        else
            if hov then
                Kit.SetCol(COL.tile)
                surface.DrawRect(0, 0, w, h)
            end
            if kind == "danger" then
                Kit.SetCol(hov and COL.red or COL.dangerEdge)
                tc = on and COL.dangerText or COL.off
            else
                Kit.SetCol(pick(self.o.edge) or (hov and COL.edgeHover or COL.edge))
                tc = on and (pick(self.o.textCol) or COL.text) or COL.off
            end
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        if self.o.dots then
            local d = math.max(2, S(3))
            for i = -1, 1 do surface.SetDrawColor(tc.r, tc.g, tc.b, 255) surface.DrawRect(w * 0.5 + i * d * 2 - d * 0.5, h * 0.5 - d * 0.5, d, d) end
        else
            draw.SimpleText(pick(self.label), (lit or kind == "primary") and fontB or fontN, w * 0.5, h * 0.5, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function b:DoClick()
        if not self:IsOn() then return end
        surface.PlaySound("ui/buttonclick.wav")
        if fn then fn(self) end
    end
    return b
end

-- Docks a button to the right of a row.
local function rbtn(parent, text, fn, o)
    local b = btn(parent, text, fn, o)
    b:Dock(RIGHT)
    b:DockMargin(K().S(6), 0, 0, 0)
    return b
end

-- Lays its children side by side, equal widths.
local function evenRow(p, gap)
    function p:PerformLayout(w, h)
        local kids = self:GetChildren()
        local n = #kids
        if n == 0 then return end
        local bw = math.floor((w - gap * (n - 1)) / n)
        for i, c in ipairs(kids) do c:SetPos((i - 1) * (bw + gap), 0) c:SetSize(bw, h) end
    end
end

-- Section label (small caps).
local function section(parent, text, top)
    local Kit = K()
    local S = Kit.S
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(S(22))
    p:DockMargin(0, top and S(10) or 0, S(8), S(6))
    local t = string.upper(text)
    function p:Paint(w, h)
        draw.SimpleText(t, Kit.Font(13, 700), 0, h * 0.5, COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

local function note(parent, text, top)
    local Kit = K()
    local l = Kit.Label(parent, text, 12, 400, COL.dim)
    l:Dock(TOP)
    l:DockMargin(0, top or 0, Kit.S(8), Kit.S(6))
    return l
end

-- R.Choose(title, options): a small choice window on top of everything
-- (a DermaMenu opened from a prompt ended up behind the pause menu).
-- options = { { label, fn }, ... }; a Cancel button is added. Opens a
-- frame later; Esc closes it (registered in Menus.prompts).
-- Example: Rhylib.Radio.Choose("Pick one", { { "Yes", function() end } })
function R.Choose(title, options)
    timer.Simple(0, function()
        local Kit = K()
        local S = Kit.S
        local f = vgui.Create("EditablePanel")
        f:SetSize(S(320), S(52) + #options * S(38) + S(44))
        f:Center()
        f:MakePopup()
        f:DoModal()
        local M = Rhylib.Menus
        if M.prompts then
            M.prompts[f] = true
            f.OnRemove = function(self) M.prompts[self] = nil end
        end
        f:DockPadding(S(12), S(46), S(12), S(12))
        function f:Paint(w, h) Kit.Plate(0, 0, w, h, { title = title, ticks = "all", header = S(34) }) end
        for _, o in ipairs(options) do
            local b = Kit.Button(f, o[1], function() f:Remove() o[2]() end)
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, S(4))
        end
        local c = Kit.Button(f, "Cancel", function() f:Remove() end, { danger = true })
        c:Dock(BOTTOM)
    end)
end

local function suggestName()
    local used = {}
    for _, sq in pairs(R.dir.squads) do used[sq.name] = true end
    local names = R.Cfg("squadNames") or { "Squad" }
    for n = 1, 9 do
        for _, base in ipairs(names) do
            local s = base .. " " .. n
            if not used[s] then return s end
        end
    end
    return "Squad"
end

local function createSquad()
    K().Prompt("Create squad", "Squad name", suggestName(), function(n) R.SquadOp(R.SQ.CREATE, n) end)
end

--------------------------------------------------------------------------
-- Top row: radio state and buttons
--------------------------------------------------------------------------

-- The state chip: text, text colour, ground, edge.
local function chipState()
    local me = LocalPlayer()
    local t = R.Mine()
    if R.Jammed(me) then return "JAMMED · the radio can't get through here", COL.red, COL.badBg, COL.dangerEdge end
    if t.off then return "RADIO OFF · you don't hear or send anything", COL.off, COL.inset, COL.edge end
    if t.muted and t.deaf then return "MUTED AND DEAFENED", COL.amber, COL.warnBg, COL.warnEdge end
    if t.muted then return "MIC MUTED · you still hear the radio", COL.amber, COL.warnBg, COL.warnEdge end
    if t.deaf then return "DEAFENED · you hear nothing on the radio", COL.amber, COL.warnBg, COL.warnEdge end
    local key = string.upper(GetConVarString("rhylib_radio_key"))
    if key == "" then return "RADIO ON · no talk key set (Settings > Controls)", COL.green, COL.onBg, COL.onEdge end
    return "RADIO ON · hold " .. key .. " to talk", COL.green, COL.onBg, COL.onEdge
end

local function buildTop(page)
    local Kit = K()
    local S = Kit.S
    local bar = vgui.Create("DPanel", page)
    bar:Dock(TOP)
    bar:SetTall(S(36))
    bar:DockMargin(0, S(2), 0, S(12))
    function bar:Paint(w, h)
        local text, tc, bg, edge = chipState()
        local font = Kit.Font(12, 700)
        surface.SetFont(font)
        local tw = surface.GetTextSize(text)
        local ch = S(30)
        local y = math.floor((h - ch) * 0.5)
        local cw = tw + S(34)
        Kit.SetCol(bg)
        surface.DrawRect(0, y, cw, ch)
        Kit.SetCol(edge)
        surface.DrawOutlinedRect(0, y, cw, ch)
        local d = S(8)
        draw.RoundedBox(math.floor(d * 0.5), S(12), y + math.floor((ch - d) * 0.5), d, d, tc)
        draw.SimpleText(text, font, S(26), y + ch * 0.5, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    -- (created right to left)
    local function mine() return R.Mine() end
    rbtn(bar, function() return mine().off and "Turn radio on" or "Radio off" end, function() R.Toggle("off") end,
        { kind = function() return mine().off and "primary" or "danger" end, col = COL.green, widthText = "Turn radio on" })
    -- (the compass shows everyone: a player may hide from all but their squad)
    if R.Cfg("showEveryone") then
        rbtn(bar, function() return R.Hidden() and "Hidden on radar" or "Hide on radar" end, function() R.ToggleHidden() end,
            { lit = function() return R.Hidden() end, col = COL.blue, widthText = "Hidden on radar",
              tooltip = "Takes you off everyone's compass but your squad's" })
    end
    rbtn(bar, function() return mine().deaf and "Undeafen" or "Deafen" end, function() R.Toggle("deaf") end,
        { lit = function() return mine().deaf end, col = COL.amber, widthText = "Undeafen" })
    rbtn(bar, function() return mine().muted and "Unmute mic" or "Mute mic" end, function() R.Toggle("muted") end,
        { lit = function() return mine().muted end, col = COL.amber, widthText = "Unmute mic" })
end

--------------------------------------------------------------------------
-- Left: your channels and the open ones
--------------------------------------------------------------------------

local function freeSlot()
    if (R.me.slots[1] or 0) == 0 then return 1 end
    if (R.me.slots[2] or 0) == 0 then return 2 end
end

local function joinChannel(c)
    local function go(slot)
        if c.mode == R.MODE_PASS then
            K().Prompt("Join " .. c.name, "Password", "", function(pass) R.ChanJoin(slot, c.id, pass) end)
        else
            R.ChanJoin(slot, c.id)
        end
    end
    local slot = freeSlot()
    if slot then return go(slot) end
    R.Choose("Join " .. c.name, {
        { "Replace Channel 1 (" .. R.SlotName(2) .. ")", function() go(1) end },
        { "Replace Channel 2 (" .. R.SlotName(3) .. ")", function() go(2) end },
    })
end

local function createChannel(slot)
    K().Prompt("New radio channel", "Name (Channel " .. slot .. ")", "", function(name)
        name = R.CleanName(name)
        if name == "" then return end
        local bn = R.Battalion(LocalPlayer())
        local opts = {
            { "Open to everyone", function() R.ChanCreate(slot, name, R.MODE_OPEN) end },
            { "Needs a password", function()
                timer.Simple(0, function()
                    K().Prompt("Channel password", "Password for " .. name, "", function(pass) R.ChanCreate(slot, name, R.MODE_PASS, pass) end)
                end)
            end },
        }
        if bn ~= "" then opts[#opts + 1] = { bn .. " only", function() R.ChanCreate(slot, name, R.MODE_BN) end } end
        R.Choose("Who can join " .. name .. "?", opts)
    end)
end

--[[
    A channel card. d: caps (slot label), name, info (strings or
    functions), col (Color or function), slot (1-3: lit while the radio
    key talks there; nil = Local), muted (function), buttons(row) adds the
    buttons (nil = none).
]]
local function chanCard(parent, d)
    local Kit = K()
    local S = Kit.S
    local card = vgui.Create("DPanel", parent)
    card:Dock(TOP)
    card:DockMargin(0, 0, S(8), S(8))
    -- (header 56 px; the button row under it, 34 px, then 12 px)
    card:DockPadding(S(12), S(56), S(12), S(12))
    card:SetTall(d.buttons and (S(56) + S(34) + S(12)) or S(56))
    local function talking() return d.slot ~= nil and R.SlotOn(d.slot) and R.Selected() == d.slot end
    function card:Paint(w, h)
        local col = pick(d.col)
        local on = talking()
        Kit.SetCol(on and COL.talkCard or COL.card)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(on and col or COL.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        local cy = S(28)
        diamond(S(12) + S(6), cy, S(6), col)
        local x = S(32)
        draw.SimpleText(d.caps, Kit.Font(10, 700), x, cy - S(8), COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local info = pick(d.info) or ""
        local f = Kit.Font(11)
        surface.SetFont(f)
        local iw = surface.GetTextSize(info)
        draw.SimpleText(info, f, w - S(12), cy, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local nf = Kit.Font(15, 700)
        local muted = d.muted and d.muted()
        draw.SimpleText(Kit.Fit(pick(d.name) or "", nf, w - x - iw - S(24)), nf, x, cy + S(7), muted and COL.label or COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    if d.buttons then
        local row = vgui.Create("DPanel", card)
        row:Dock(FILL)
        row.Paint = nil
        d.buttons(row, talking)
    end
    return card
end

local function talkButton(row, slot, talking)
    local b = btn(row, function() return talking() and "Talking here" or "Talk here" end, function() RunConsoleCommand("rhylib_radio_slot", tostring(slot)) end,
        { lit = talking, col = function() return R.SlotColor(slot) end, tooltip = "The radio key talks on this one" })
    b:Dock(FILL)
end

local function muteButton(row, slot)
    rbtn(row, function() return R.ChanMuted(slot) and "Unmute" or "Mute" end, function() R.ToggleChanMute(slot) end,
        { widthText = "Unmute", tooltip = "Mute this channel's voice for you only (you can still talk on it)" })
end

local function buildLeft(col)
    local Kit = K()
    local S = Kit.S
    section(col, "Your channels")
    chanCard(col, { caps = "LOCAL", name = "Local", col = R.COL.local_, info = "near you" })
    -- Squad slot.
    local inSq = R.SlotOn(1)
    local sq = R.dir.squads[R.SquadOf(LocalPlayer())]
    local n = 0
    if sq then for _, p in ipairs(sq.members) do if IsValid(p) then n = n + 1 end end end
    chanCard(col, {
        caps = "SQUAD", slot = 1, col = function() return R.SlotColor(1) end,
        name = inSq and R.SlotName(1) or "No squad",
        info = function() if not inSq then return "join or create one" end return R.ChanMuted(1) and "muted" or (n .. " on it") end,
        muted = function() return inSq and R.ChanMuted(1) end,
        buttons = inSq and function(row, talking)
            muteButton(row, 1)
            talkButton(row, 1, talking)
        end or nil,
    })
    for slot = 2, 3 do
        local on = R.SlotOn(slot)
        local c = on and R.dir.channels[R.me.slots[slot - 1]]
        local listening = c and c.n or 1
        chanCard(col, {
            caps = "CHANNEL " .. (slot - 1), slot = slot,
            col = function() return on and R.SlotColor(slot) or R.COL.grey end,
            name = on and R.SlotName(slot) or "Empty",
            info = function() if not on then return "free slot" end return R.ChanMuted(slot) and "muted" or (listening .. " on it") end,
            muted = function() return on and R.ChanMuted(slot) end,
            buttons = function(row, talking)
                if on then
                    rbtn(row, "Leave", function() R.ChanLeave(slot - 1) end, { kind = "danger" })
                    muteButton(row, slot)
                    talkButton(row, slot, talking)
                else
                    local b = btn(row, "Create channel", function() createChannel(slot - 1) end, { kind = "primary" })
                    b:Dock(FILL)
                end
            end,
        })
    end
    note(col, string.upper(GetConVarString("rhylib_radio_switchkey")) .. " switches the channel you talk on. Your voice key stays local.", 0)

    section(col, "Open channels", true)
    local list = {}
    for _, c in pairs(R.dir.channels) do
        if c.id ~= R.me.slots[1] and c.id ~= R.me.slots[2] then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    local bn = R.Battalion(LocalPlayer())
    local function openRow(dc, name, sub, act, fn, o)
        local r = vgui.Create("DPanel", col)
        r:Dock(TOP)
        r:SetTall(S(48))
        r:DockMargin(0, 0, S(8), S(4))
        r:DockPadding(0, S(6), S(6), S(6))
        local bw
        function r:Paint(w, h)
            Kit.SetCol(COL.card)
            surface.DrawRect(0, 0, w, h)
            diamond(S(16), h * 0.5, S(5), dc)
            bw = bw or (self.act and self.act:GetWide() or 0)
            local f = Kit.Font(11)
            surface.SetFont(f)
            local sw = surface.GetTextSize(sub)
            local right = w - S(6) - bw - S(10)
            draw.SimpleText(sub, f, right, h * 0.5, COL.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            local nf = Kit.Font(14, 500)
            draw.SimpleText(Kit.Fit(name, nf, right - sw - S(40)), nf, S(30), h * 0.5, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        r.act = rbtn(r, act, fn, o)
    end
    if #list == 0 then note(col, "No other channels yet.") end
    for _, c in ipairs(list) do
        local sub = c.n .. " on it · " .. (c.mode == R.MODE_BN and (c.bn .. " only") or MODE_TEXT[c.mode])
        local can = c.mode ~= R.MODE_BN or c.bn == bn
        openRow(MODE_COL[c.mode] or COL.blue, c.name, sub, "Join", function() joinChannel(c) end,
            { enabled = can, tooltip = not can and ("Only for " .. c.bn) or nil })
    end
    local free = freeSlot()
    if free then
        openRow(COL.edgeHover, "New channel...", "", "Create", function() createChannel(free) end)
    end
end

--------------------------------------------------------------------------
-- Middle: your squad and the others
--------------------------------------------------------------------------

local function memberMenu(p, iLead)
    local Kit = K()
    local m = Kit.Menu()
    if p == LocalPlayer() then
        local cur = R.RoleOf(p)
        for i, ro in ipairs(R.ROLES) do
            m:AddOption((i == cur and "Your role: " or "Be ") .. ro[2], function() R.SetRole(i) end)
        end
    else
        m:AddOption("Hail " .. p:Nick(), function() if IsValid(p) then R.HailPlayer(p) end end)
        if iLead then
            m:AddSpacer()
            m:AddOption(R.IsRO(p) and "Remove radio operator" or "Make radio operator", function() R.SquadOp(R.SQ.RO, p) end)
            m:AddOption("Make squad leader", function() R.SquadOp(R.SQ.LEADER, p) end)
            m:AddOption("Remove from squad", function() R.SquadOp(R.SQ.KICK, p) end)
        end
    end
    m:Open()
end

local MEMBER_H = 52
local function memberRow(parent, p, iLead)
    local Kit = K()
    local S = Kit.S
    local me = LocalPlayer()
    local isMe = p == me
    local r = vgui.Create("DPanel", parent)
    r:SetTall(S(MEMBER_H))
    r:Dock(TOP)
    r:DockMargin(0, 0, 0, S(4))
    r:DockPadding(0, S(8), S(8), S(8))
    local role = R.ROLES[R.RoleOf(p)]
    local sub = role[2] .. (isMe and " · you" or "")
    local lead, ro = R.IsLeader(p), R.IsRO(p)
    local chip = (lead and ro) and "LEAD · RO" or (lead and "LEAD") or (ro and "RO") or nil
    local nick = p:Nick()
    function r:Paint(w, h)
        if not IsValid(p) then return end
        Kit.SetCol(isMe and COL.sel or COL.side)
        surface.DrawRect(0, 0, w, h)
        if isMe then
            Kit.SetCol(COL.blue)
            surface.DrawRect(0, 0, S(3), h)
        end
        local bs = S(34)
        local bx, by = S(10), math.floor((h - bs) * 0.5)
        Kit.SetCol(COL.inset)
        surface.DrawRect(bx, by, bs, bs)
        Kit.SetCol(COL.edge)
        surface.DrawOutlinedRect(bx, by, bs, bs)
        R.DrawIcon(role[3], bx + S(7), by + S(7), bs - S(14), COL.green)
        -- Right part, from the ... button leftwards: TALKING, distance, chip.
        local rx = w - S(8) - S(36) - S(12)
        local talk = isMe and (R.txOn or R.speaking[p]) or R.speaking[p]
        if talk then
            local f = Kit.Font(10, 700)
            surface.SetFont(f)
            local tw = surface.GetTextSize("TALKING")
            local cw, ch = tw + S(12), S(18)
            Kit.SetCol(R.SpeakerColor(p) or COL.green)
            surface.DrawRect(rx - cw, h * 0.5 - ch * 0.5, cw, ch)
            draw.SimpleText("TALKING", f, rx - cw * 0.5, h * 0.5, COL.dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        rx = rx - S(70) - S(8)
        if not isMe then
            local pos = R.MatePos(p)
            if pos then
                draw.SimpleText(math.floor(me:GetPos():Distance(pos) * 0.01905 + 0.5) .. " m", Kit.Font(12), rx, h * 0.5, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        rx = rx - S(54) - S(12)
        local nameRight = rx
        if chip then
            local f = Kit.Font(11, 700)
            surface.SetFont(f)
            local tw = surface.GetTextSize(chip)
            local cw, ch = tw + S(16), S(22)
            Kit.SetCol(COL.onEdge)
            surface.DrawOutlinedRect(rx - cw, h * 0.5 - ch * 0.5, cw, ch)
            draw.SimpleText(chip, f, rx - cw * 0.5, h * 0.5, COL.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            nameRight = rx - cw
        end
        local x = bx + bs + S(12)
        local nf = Kit.Font(14, 700)
        draw.SimpleText(Kit.Fit(nick, nf, nameRight - x - S(8)), nf, x, h * 0.36, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, Kit.Font(11), x, h * 0.68, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    rbtn(r, "", function() if IsValid(p) then memberMenu(p, iLead) end end,
        { dots = true, tooltip = isMe and "Pick your role" or (iLead and "Hail, radio operator, leader, remove" or "Hail " .. nick) })
end

local function squadCount(sq)
    local n = 0
    for _, p in ipairs(sq.members) do if IsValid(p) then n = n + 1 end end
    return n
end

local function yourSquad(col, sq, mine)
    local Kit = K()
    local S = Kit.S
    local me = LocalPlayer()
    local iLead = R.IsLeader(me)
    local card = vgui.Create("DPanel", col)
    card:Dock(TOP)
    card:DockMargin(0, 0, S(8), S(14))
    card:DockPadding(S(16), S(17), S(16), S(14))
    function card:Paint(w, h)
        Kit.SetCol(COL.card)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(mine ~= 0 and COL.green or COL.label)
        surface.DrawRect(0, 0, w, S(3))
    end
    local head = vgui.Create("DPanel", card)
    head:Dock(TOP)
    head:SetTall(S(46))
    head:DockMargin(0, 0, 0, S(12))
    head:DockPadding(0, S(6), 0, S(6))
    local hint
    -- In a squad (own NW2 state) but the directory doesn't have it yet:
    -- the name we know, Leave, and ask for the directory again (at most
    -- every 3 s; the reply rebuilds the page).
    if mine ~= 0 and not sq then
        local name = string.upper(R.SlotName(1))
        function head:Paint(w, h)
            draw.SimpleText("YOUR SQUAD", Kit.Font(10, 700), 0, S(8), COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local nf = Kit.Font(28, 700)
            surface.SetFont(nf)
            local nw = surface.GetTextSize(name)
            draw.SimpleText(name, nf, 0, S(31), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Loading squad...", Kit.Font(12), nw + S(12), S(33), COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        rbtn(head, "Leave", function() R.SquadOp(R.SQ.LEAVE) end, { kind = "danger" })
        card:SetTall(S(17) + S(46) + S(14))
        if CurTime() >= (R.dirAskAt or 0) then
            R.dirAskAt = CurTime() + 3
            Rhylib.Net.Start("radio.dirreq")
            net.SendToServer()
        end
        return
    end
    if not sq then
        local name = "NO SQUAD"
        function head:Paint(w, h)
            draw.SimpleText("YOUR SQUAD", Kit.Font(10, 700), 0, S(8), COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(name, Kit.Font(28, 700), 0, S(31), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        rbtn(head, "Create squad", createSquad, { kind = "primary" })
        hint = "You're not in a squad. Create one, or join an open squad below. A squad gets its own radio channel, the squad map and pings."
        local l = note(card, hint, 0)
        l:DockMargin(0, 0, 0, 0)
        card:SetTall(S(17) + S(46) + S(12) + S(36) + S(14))
        -- (the text may wrap to more lines in a narrow column)
        l.OnSizeChanged = function() if IsValid(card) then card:InvalidateLayout() end end
        function card:PerformLayout()
            local want = S(17) + S(46) + S(12) + l:GetTall() + S(14)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        return
    end
    local n = squadCount(sq)
    local name = string.upper(sq.name)
    local facts = n .. (n == 1 and " member" or " members") .. " · " .. (sq.open and "open" or "locked")
    function head:Paint(w, h)
        draw.SimpleText("YOUR SQUAD", Kit.Font(10, 700), 0, S(8), COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local nf = Kit.Font(28, 700)
        surface.SetFont(nf)
        local nw = surface.GetTextSize(name)
        draw.SimpleText(name, nf, 0, S(31), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(facts, Kit.Font(12), nw + S(12), S(33), sq.open and COL.dim or COL.amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    rbtn(head, "Leave", function() R.SquadOp(R.SQ.LEAVE) end, { kind = "danger" })
    if iLead then
        rbtn(head, sq.open and "Lock" or "Unlock", function() R.SquadOp(R.SQ.LOCK) end,
            { widthText = "Unlock", tooltip = sq.open and "Nobody new can join" or "Anyone can join again" })
        rbtn(head, "Rename", function()
            Kit.Prompt("Rename squad", "Squad name", sq.name or "", function(nm) R.SquadOp(R.SQ.RENAME, nm) end)
        end)
    end
    local rows = 0
    for _, p in ipairs(sq.members) do
        if IsValid(p) then
            memberRow(card, p, iLead)
            rows = rows + 1
        end
    end
    hint = iLead and ("You lead " .. sq.name .. ": use a member's ... button to make them RO, hand over the lead or remove them.")
        or "Use ... on your own row to pick your role, on a mate's to hail them."
    local hp = vgui.Create("DPanel", card)
    hp:Dock(TOP)
    hp:SetTall(S(18))
    hp:DockMargin(0, S(6), 0, 0)
    function hp:Paint(w, h)
        local f = Kit.Font(12)
        draw.SimpleText(Kit.Fit(hint, f, w), f, 0, h * 0.5, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    card:SetTall(S(17) + S(46) + S(12) + rows * (S(MEMBER_H) + S(4)) + S(6) + S(18) + S(14))
end

local TILE_H = 112
local function squadTile(grid, sq)
    local Kit = K()
    local S = Kit.S
    local t = vgui.Create("DPanel", grid)
    t:DockPadding(S(14), 0, S(14), S(12))
    local n = squadCount(sq)
    local name = string.upper(sq.name)
    local count = n .. (n == 1 and " member" or " members")
    local state = sq.open and "OPEN" or "LOCKED"
    local lead = IsValid(sq.leader) and ("Lead " .. sq.leader:Nick()) or "No leader"
    function t:Paint(w, h)
        Kit.SetCol(COL.card)
        surface.DrawRect(0, 0, w, h)
        local nf = Kit.Font(20, 700)
        local sf = Kit.Font(11, 700)
        surface.SetFont(sf)
        local stw = surface.GetTextSize(state)
        draw.SimpleText(state, sf, w - S(14), S(24), sq.open and COL.green or COL.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetFont(nf)
        local shown = Kit.Fit(name, nf, w - S(28) - stw - S(80))
        local nw = surface.GetTextSize(shown)
        draw.SimpleText(shown, nf, S(14), S(24), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(count, Kit.Font(12), S(14) + nw + S(8), S(25), COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(Kit.Fit(lead, Kit.Font(12), w - S(28)), Kit.Font(12), S(14), S(48), COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local row = vgui.Create("DPanel", t)
    row:Dock(BOTTOM)
    row:SetTall(S(34))
    row.Paint = nil
    local hb = btn(row, "Hail", function() R.HailSquad(sq.id) end, { tooltip = "Rings the squad leader and radio operator" })
    hb:Dock(LEFT)
    local jb = btn(row, "Join", function() R.SquadOp(R.SQ.JOIN, sq.id) end,
        { kind = sq.open and "primary" or "outline", enabled = sq.open, tooltip = not sq.open and "This squad is locked" or nil })
    jb:Dock(LEFT)
    jb:DockMargin(S(6), 0, 0, 0)
    if n > 0 then
        local mb = btn(row, "", function()
            local m = Kit.Menu()
            for _, p in ipairs(sq.members) do
                if IsValid(p) then
                    local pl = p
                    m:AddOption("Hail " .. pl:Nick() .. " (" .. R.ROLES[R.RoleOf(pl)][2] .. ")", function() if IsValid(pl) then R.HailPlayer(pl) end end)
                end
            end
            m:Open()
        end, { dots = true, tooltip = "Hail one member" })
        mb:Dock(LEFT)
        mb:DockMargin(S(6), 0, 0, 0)
    end
end

local function buildMiddle(col)
    local Kit = K()
    local S = Kit.S
    local mine = R.SquadOf(LocalPlayer())
    local sq = mine ~= 0 and R.dir.squads[mine] or nil
    yourSquad(col, sq, mine)

    local list = {}
    for _, s in pairs(R.dir.squads) do if s.id ~= mine then list[#list + 1] = s end end
    table.sort(list, function(a, b) return a.name < b.name end)
    section(col, mine ~= 0 and "Other squads" or "Squads to join")
    if #list == 0 then
        note(col, mine ~= 0 and "No other squads yet." or "No squads yet. Create one and others can join it.")
        return
    end
    local grid = vgui.Create("DPanel", col)
    grid:Dock(TOP)
    grid:DockMargin(0, 0, S(8), S(8))
    grid.Paint = nil
    local gap = S(8)
    local function rowsFor(w, n)
        local cols = (w > 0 and w < S(380)) and 1 or 2
        return cols, math.ceil(n / cols)
    end
    local _, rows = rowsFor(0, #list)
    grid:SetTall(rows * (S(TILE_H) + gap) - gap)
    function grid:PerformLayout(w)
        local kids = self:GetChildren()
        local cols, nr = rowsFor(w, #kids)
        local tw = math.floor((w - gap * (cols - 1)) / cols)
        for i, c in ipairs(kids) do
            c:SetPos(((i - 1) % cols) * (tw + gap), math.floor((i - 1) / cols) * (S(TILE_H) + gap))
            c:SetSize(tw, S(TILE_H))
        end
        local want = math.max(0, nr * (S(TILE_H) + gap) - gap)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    for _, s in ipairs(list) do squadTile(grid, s) end
end

--------------------------------------------------------------------------
-- Right: hails, the call, the squad map
--------------------------------------------------------------------------

local function hailCard(col, title, line, sub, timeFn)
    local Kit = K()
    local S = Kit.S
    local p = vgui.Create("DPanel", col)
    p:Dock(TOP)
    p:DockMargin(0, 0, S(8), S(10))
    p:DockPadding(S(14), S(76), S(14), S(12))
    p:SetTall(S(76) + S(36) + S(12))
    function p:Paint(w, h)
        Kit.SetCol(COL.hailBg)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(COL.hailEdge)
        surface.DrawOutlinedRect(0, 0, w, h)
        R.DrawIcon("hail", S(12), S(10), S(20), COL.amber)
        draw.SimpleText(title, Kit.Font(12, 700), S(38), S(20), COL.amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local t = timeFn and timeFn()
        if t then draw.SimpleText(t, Kit.Font(11), w - S(14), S(20), COL.hailDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        local lf = Kit.Font(15, 700)
        local shown = Kit.Fit(line, lf, w - S(28))
        surface.SetFont(lf)
        local lw = surface.GetTextSize(shown)
        draw.SimpleText(shown, lf, S(14), S(50), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if sub and sub ~= "" then
            local sf = Kit.Font(13)
            local room = w - S(28) - lw - S(6)
            if room > S(30) then draw.SimpleText(Kit.Fit("· " .. sub, sf, room), sf, S(14) + lw + S(6), S(51), COL.hailDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
    end
    local row = vgui.Create("DPanel", p)
    row:Dock(FILL)
    row.Paint = nil
    evenRow(row, S(6))
    return row
end

local function buildCalls(col)
    for id, r in pairs(R.rings) do
        local who = IsValid(r.caller) and r.caller:Nick() or "?"
        local at = r.at or RealTime()
        local row = hailCard(col, "HAIL RINGING", r.label or "Hail", who, function() return clock(RealTime() - at) end)
        btn(row, "Answer", function() R.Answer(id, true) end, { kind = "primary", col = COL.green })
        btn(row, "Decline", function() R.Answer(id, false) end, { edge = COL.hailEdge, textCol = COL.hailText })
    end
    local c = R.call
    if c then
        local names = {}
        for _, p in ipairs(c.members) do if IsValid(p) and p ~= LocalPlayer() then names[#names + 1] = p:Nick() end end
        local live = #c.members >= 2
        local sub = live and table.concat(names, ", ") or (c.ringing > 0 and "ringing" or "waiting for an answer")
        local row = hailCard(col, live and "ON A CALL" or "HAILING", c.label or "Hail", sub,
            live and function() return clock(CurTime() - (c.started or CurTime())) end or nil)
        btn(row, "Hang up", function() R.HangUp() end, { kind = "danger" })
    end
end

local function buildMap(col)
    local Kit = K()
    local S = Kit.S
    section(col, "Squad map")
    local m = vgui.Create("DPanel", col)
    m:Dock(TOP)
    m:DockMargin(0, 0, S(8), S(8))
    function m:PerformLayout(w)
        if self:GetTall() ~= w then self:SetTall(w) end
        -- (the round ground, rebuilt only when the size changes)
        if self.polyW ~= w then
            self.polyW = w
            local pts, cx, r = {}, w * 0.5, w * 0.5
            for i = 0, 47 do
                local a = i / 48 * math.pi * 2
                pts[#pts + 1] = { x = cx + math.cos(a) * r, y = cx + math.sin(a) * r }
            end
            self.poly = pts
        end
    end
    function m:Paint(w, h)
        local cx, cy = w * 0.5, h * 0.5
        if self.poly then
            draw.NoTexture()
            Kit.SetCol(COL.inset)
            surface.DrawPoly(self.poly)
            Kit.SetCol(COL.edge)
            local pts = self.poly
            for i = 1, #pts do
                local a, b = pts[i], pts[i % #pts + 1]
                surface.DrawLine(a.x, a.y, b.x, b.y)
            end
        end
        Kit.SetCol(COL.tile)
        surface.DrawLine(cx, S(4), cx, h - S(4))
        surface.DrawLine(S(4), cy, w - S(4), cy)
        local ox, oy = self:LocalToScreen(0, 0)
        R.DrawRadar(cx, cy, math.floor(w * 0.5) - S(8), true, ox, oy)
        if R.SquadOf(LocalPlayer()) == 0 then
            draw.SimpleText("Join a squad to see it here", Kit.Font(12), cx, cy + S(28), COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    -- Legend (what the map really draws: leaders gold, pings as their symbol).
    local everyone = R.Cfg("showEveryone")
    local lg = vgui.Create("DPanel", col)
    lg:Dock(TOP)
    lg:SetTall(S(36))
    lg:DockMargin(0, 0, S(8), S(6))
    local items = { { "Squad", 1 }, { "Leader", 2 } }
    if everyone then items[#items + 1] = { "Others", 4 } end
    items[#items + 1] = { "Ping", 3 }
    items[#items + 1] = { R.RADAR_M .. " m to the rim", 0 }
    local pingCol = R.PINGS and R.PINGS[1] and R.PINGS[1].col or COL.blue
    function lg:Paint(w, h)
        local f = Kit.Font(11)
        surface.SetFont(f)
        local x, y = 0, S(9)
        for _, it in ipairs(items) do
            local tw = surface.GetTextSize(it[1])
            local iw = (it[2] > 0 and S(15) or 0) + tw
            if x > 0 and x + iw > w then x, y = 0, y + S(18) end
            if it[2] == 1 then diamond(x + S(5), y, S(5), R.COL.squad)
            elseif it[2] == 2 then diamond(x + S(5), y, S(5), R.COL.hail)
            elseif it[2] == 3 then draw.RoundedBox(S(4), x + S(1), y - S(4), S(9), S(9), pingCol)
            elseif it[2] == 4 then diamond(x + S(5), y, S(5), R.COL.ch1)
            end
            local tx = x + (it[2] > 0 and S(15) or 0)
            draw.SimpleText(it[1], f, tx, y, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            x = tx + tw + S(14)
        end
    end
    local t = btn(col, function() return R.RadarOn() and "Compass on HUD: on" or "Compass on HUD: off" end, function()
        RunConsoleCommand("rhylib_radio_compass", R.RadarOn() and "0" or "1")
    end, { lit = function() return R.RadarOn() end, col = COL.blue, tooltip = "In first person it takes half of the chat's room", h = 32 })
    t:Dock(TOP)
    t:DockMargin(0, S(2), S(8), 0)
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

-- A column: a painted holder with a scroll panel inside.
local function column(parent, dock, w, bg)
    local Kit = K()
    local S = Kit.S
    local h = vgui.Create("DPanel", parent)
    h:Dock(dock)
    if w then h:SetWide(w) end
    h:DockPadding(S(14), S(14), S(6), S(14))
    function h:Paint(pw, ph)
        if not bg then return end
        Kit.SetCol(bg)
        surface.DrawRect(0, 0, pw, ph)
        Kit.SetCol(COL.black)
        surface.DrawOutlinedRect(0, 0, pw, ph)
    end
    local sp = Kit.Scroll(h)
    sp:Dock(FILL)
    return sp
end

local function build(page)
    local Kit = K()
    local S = Kit.S
    buildTop(page)
    local body = vgui.Create("DPanel", page)
    body:Dock(FILL)
    body.Paint = nil
    local pw = page:GetWide() - S(32)
    local lw = math.floor(math.min(S(370), pw * 0.31))
    local rw = math.floor(math.min(S(330), pw * 0.27))
    local left = column(body, LEFT, lw, COL.side)
    local right = column(body, RIGHT, rw, COL.side)
    local mid = column(body, FILL, nil, nil)
    -- (rows go straight into the scroll panels; they take docked children)
    buildLeft(left)
    buildMiddle(mid)
    buildCalls(right)
    buildMap(right)
    -- Rebuilds (any squad or channel change) keep where you'd scrolled to.
    R.scroll = R.scroll or {}
    for key, sp in pairs({ left = left, mid = mid, right = right }) do
        local bar = sp:GetVBar()
        local want = R.scroll[key]
        if want and want > 0 then timer.Simple(0, function() if IsValid(bar) then bar:SetScroll(want) end end) end
        function bar:Think() R.scroll[key] = self:GetScroll() end
    end
    -- Ask for a fresh directory when the menu opens on this page (not on rebuilds).
    local pause = Rhylib.Menus.pause
    if R.pageFor ~= pause then
        R.pageFor = pause
        Rhylib.Net.Start("radio.dirreq")
        net.SendToServer()
    end
end

local function addPage()
    local M = Rhylib.Menus
    if not (M and M.AddPage and M.Kit) then return end
    M.AddPage("radio", { title = "Radio & squads", order = 50, section = "you", icon = "radio", build = build, wide = true,
        key = function() return GetConVarString("rhylib_radio_menukey") end })
end
Rhylib.Hook.Add("InitPostEntity", "radio.page", addPage)
addPage()
