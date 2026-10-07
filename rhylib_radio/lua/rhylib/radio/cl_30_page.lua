--[[
    The Radio page (pause menu, also the radio page key, default T).

    Left:   your radio (on, mute, deafen), your channels (Local, Squad,
            Channel 1, Channel 2: talk on it, leave, create) and the open
            channels to join.
    Middle: squads: create, join, leave; members with their symbols and
            roles; your own role; hail a squad (its leader and RO) or one
            member; leader tools (lock, rename, leader, RO, remove).
    Right:  squad map (you in the middle, facing up), hails ringing
            (answer / decline) and the call you're in (hang up).
    Closing the page never ends a call. The page rebuilds itself when
    something changes (R.Changed).
]]

local R = Rhylib.Radio

local MODE_TEXT = { [0] = "open", [1] = "password", [2] = "battalion" }

local function K() return Rhylib.Menus.Kit end

-- A plain painted row: colour chip, title, sub line; buttons docked right.
local function row(parent, col, title, sub, h)
    local Kit = K()
    local S = Kit.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(S(h or 46))
    p:Dock(TOP)
    p:DockMargin(0, 0, 0, S(5))
    p:DockPadding(S(8), S(9), S(8), S(9))
    function p:Paint(w, hh)
        Kit.SetCol(Kit.C.row)
        surface.DrawRect(0, 0, w, hh)
        Kit.SetCol(Kit.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, hh)
        local x = S(10)
        if col then
            Kit.SetCol(col)
            surface.DrawRect(x, hh * 0.5 - S(7), S(14), S(14))
            x = x + S(24)
        end
        local t = isfunction(title) and title() or title
        local sb = isfunction(sub) and sub() or sub
        draw.SimpleText(t, Kit.Font(14, 600), x, sb and hh * 0.36 or hh * 0.5, Kit.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if sb then draw.SimpleText(sb, Kit.Font(12), x, hh * 0.70, Kit.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end
    return p
end

local function smallButton(parent, text, fn, opts)
    local Kit = K()
    opts = opts or {}
    opts.small = true
    local b = Kit.Button(parent, text, fn, opts)
    b:Dock(RIGHT)
    b:DockMargin(Kit.S(4), 0, 0, 0)
    surface.SetFont(Kit.Font(12, 700))
    b:SetWide(surface.GetTextSize(string.upper(isfunction(text) and text() or text)) + Kit.S(24))
    return b
end

local function heading(parent, text, top)
    local Kit = K()
    local h = Kit.Heading(parent, text)
    h:Dock(TOP)
    h:DockMargin(0, top and Kit.S(12) or 0, 0, Kit.S(6))
    return h
end

-- A small choice window on top of everything (a DermaMenu opened from a
-- prompt ended up behind the pause menu). options = { { label, fn }, ... }
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

--------------------------------------------------------------------------
-- Left: your radio and channels
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

local function buildLeft(col)
    local Kit = K()
    local S = Kit.S
    heading(col, "Your radio")
    local btns = vgui.Create("DPanel", col)
    btns:Dock(TOP)
    btns:SetTall(S(30))
    btns:DockMargin(0, 0, 0, S(4))
    btns.Paint = nil
    local defs = {
        { "Radio on", function() return not R.Mine().off end, function() R.Toggle("off") end },
        { "Mute", function() return R.Mine().muted end, function() R.Toggle("muted") end },
        { "Deafen", function() return R.Mine().deaf end, function() R.Toggle("deaf") end },
    }
    function btns:PerformLayout(w, h)
        local bw = math.floor((w - S(8)) / 3)
        for i, b in ipairs(self:GetChildren()) do b:SetPos((i - 1) * (bw + S(4)), 0) b:SetSize(bw, h) end
    end
    for _, d in ipairs(defs) do
        Kit.Button(btns, d[1], d[3], { small = true, selected = d[2] })
    end
    local hint = Kit.Label(col, "Hold " .. string.upper(GetConVarString("rhylib_radio_key")) .. " to talk on the radio, "
        .. string.upper(GetConVarString("rhylib_radio_switchkey")) .. " switches the channel. Your voice key stays local.", 12, 400, Kit.C.textDim)
    hint:Dock(TOP)
    hint:DockMargin(0, S(2), 0, S(8))

    heading(col, "Channels", true)
    local localRow = row(col, R.COL.local_, "Local", "Voice key · people near you")
    -- Squad slot.
    local sqRow = row(col, R.SlotColor(1), function() return R.SlotOn(1) and ("Squad · " .. R.SlotName(1)) or "Squad" end,
        function() return R.SlotOn(1) and "Your squad's radio" or "Join or create a squad" end)
    if R.SlotOn(1) then
        smallButton(sqRow, function() return R.Selected() == 1 and "Talking" or "Talk" end, function() RunConsoleCommand("rhylib_radio_slot", "1") end,
            { selected = function() return R.Selected() == 1 end })
    end
    for slot = 2, 3 do
        local on = R.SlotOn(slot)
        local c = on and R.dir.channels[R.me.slots[slot - 1]]
        local r = row(col, on and R.SlotColor(slot) or R.COL.grey, on and R.SlotName(slot) or ("Channel " .. (slot - 1)),
            on and ("Channel " .. (slot - 1) .. " · " .. (c and c.n or 1) .. " listening") or "Empty")
        if on then
            smallButton(r, "Leave", function() R.ChanLeave(slot - 1) end)
            smallButton(r, function() return R.Selected() == slot and "Talking" or "Talk" end, function() RunConsoleCommand("rhylib_radio_slot", tostring(slot)) end,
                { selected = function() return R.Selected() == slot end })
        else
            smallButton(r, "Create", function() createChannel(slot - 1) end, { accent = true })
        end
    end

    heading(col, "Open channels", true)
    local list = {}
    for _, c in pairs(R.dir.channels) do
        if c.id ~= R.me.slots[1] and c.id ~= R.me.slots[2] then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    if #list == 0 then
        local l = Kit.Label(col, "No other channels yet.", 12, 400, Kit.C.textDim)
        l:Dock(TOP)
    end
    local bn = R.Battalion(LocalPlayer())
    for _, c in ipairs(list) do
        local sub = c.n .. " listening · " .. (c.mode == R.MODE_BN and (c.bn .. " only") or MODE_TEXT[c.mode])
        local r = row(col, nil, c.name, sub, 42)
        local can = c.mode ~= R.MODE_BN or c.bn == bn
        smallButton(r, "Join", function() joinChannel(c) end, { enabled = can })
    end
end

--------------------------------------------------------------------------
-- Middle: squads
--------------------------------------------------------------------------

local function memberRow(parent, sq, p, mineSq, iLead)
    local Kit = K()
    local S = Kit.S
    local me = LocalPlayer()
    local r = vgui.Create("DPanel", parent)
    r:SetTall(S(32))
    r:Dock(TOP)
    r:DockPadding(S(6), S(4), S(6), S(4))
    function r:Paint(w, h)
        if not IsValid(p) then return end
        Kit.SetCol(p == me and Kit.C.rowHover or Kit.C.row)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(Kit.C.edgeDark)
        surface.DrawLine(0, h - 1, w, h - 1)
        local is = S(16)
        local tw = R.DrawTags(p, S(8), (h - is) * 0.5, is, Kit.C.text)
        draw.SimpleText(p:Nick(), Kit.Font(13, 600), S(16) + tw, h * 0.5, Kit.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local role = R.ROLES[R.RoleOf(p)]
    if p == me then
        smallButton(r, role[2], function()
            local m = Kit.Menu()
            for i, ro in ipairs(R.ROLES) do m:AddOption(ro[2], function() R.SetRole(i) end) end
            m:Open()
        end, { accent = true })
    else
        smallButton(r, "Hail", function() R.HailPlayer(p) end)
        if iLead and mineSq then
            smallButton(r, "...", function()
                local m = Kit.Menu()
                m:AddOption(R.IsRO(p) and "Remove radio operator" or "Make radio operator", function() R.SquadOp(R.SQ.RO, p) end)
                m:AddOption("Make squad leader", function() R.SquadOp(R.SQ.LEADER, p) end)
                m:AddOption("Remove from squad", function() R.SquadOp(R.SQ.KICK, p) end)
                m:Open()
            end)
        end
        local lbl = vgui.Create("DLabel", r)
        lbl:Dock(RIGHT)
        lbl:SetFont(Kit.Font(12))
        lbl:SetTextColor(Kit.C.textDim)
        lbl:SetText(role[2])
        lbl:SizeToContentsX()
        lbl:DockMargin(0, 0, S(6), 0)
    end
end

local function buildMiddle(col)
    local Kit = K()
    local S = Kit.S
    local me = LocalPlayer()
    local mine = R.SquadOf(me)
    heading(col, "Squads")
    local bar = vgui.Create("DPanel", col)
    bar:Dock(TOP)
    bar:SetTall(S(28))
    bar:DockMargin(0, 0, 0, S(8))
    bar.Paint = nil
    if mine == 0 then
        local b = Kit.Button(bar, "Create squad", function()
            Kit.Prompt("Create squad", "Squad name", suggestName(), function(n) R.SquadOp(R.SQ.CREATE, n) end)
        end, { small = true, accent = true })
        b:Dock(LEFT)
        b:SetWide(S(150))
    else
        local b = Kit.Button(bar, "Leave squad", function() R.SquadOp(R.SQ.LEAVE) end, { small = true, danger = true })
        b:Dock(LEFT)
        b:SetWide(S(130))
        if R.IsLeader(me) then
            local sq = R.dir.squads[mine]
            local lk = Kit.Button(bar, (sq and not sq.open) and "Unlock" or "Lock", function() R.SquadOp(R.SQ.LOCK) end, { small = true })
            lk:Dock(LEFT)
            lk:SetWide(S(90))
            lk:DockMargin(S(6), 0, 0, 0)
            local rn = Kit.Button(bar, "Rename", function()
                Kit.Prompt("Rename squad", "Squad name", sq and sq.name or "", function(n) R.SquadOp(R.SQ.RENAME, n) end)
            end, { small = true })
            rn:Dock(LEFT)
            rn:SetWide(S(90))
            rn:DockMargin(S(6), 0, 0, 0)
        end
    end

    local list = {}
    for _, sq in pairs(R.dir.squads) do list[#list + 1] = sq end
    table.sort(list, function(a, b)
        if (a.id == mine) ~= (b.id == mine) then return a.id == mine end
        return a.name < b.name
    end)
    if #list == 0 then
        local l = Kit.Label(col, "No squads yet. Create one and others can join it.", 13, 400, Kit.C.textDim)
        l:Dock(TOP)
    end
    for _, sq in ipairs(list) do
        local isMine = sq.id == mine
        local count = 0
        for _, p in ipairs(sq.members) do if IsValid(p) then count = count + 1 end end
        local h = row(col, isMine and R.COL.squad or R.COL.grey, sq.name,
            (isMine and "your squad · " or "") .. count .. (count == 1 and " member" or " members") .. " · " .. (sq.open and "open" or "locked"), 44)
        h:DockMargin(0, S(4), 0, 0)
        if not isMine then
            smallButton(h, "Hail", function() R.HailSquad(sq.id) end, { tooltip = "Rings the squad leader and radio operator" })
            if sq.open then smallButton(h, "Join", function() R.SquadOp(R.SQ.JOIN, sq.id) end, { accent = true }) end
        end
        local iLead = isMine and R.IsLeader(me)
        for _, p in ipairs(sq.members) do
            if IsValid(p) then memberRow(col, sq, p, isMine, iLead) end
        end
    end
end

--------------------------------------------------------------------------
-- Right: map, hails, call
--------------------------------------------------------------------------

local function buildMap(col)
    local Kit = K()
    local S = Kit.S
    heading(col, "Squad compass")
    local m = vgui.Create("DPanel", col)
    m:Dock(TOP)
    function m:PerformLayout(w) self:SetTall(w) end
    function m:Paint(w, h)
        draw.NoTexture()
        Kit.SetCol(Kit.C.row)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(Kit.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local r = math.floor(w * 0.5) - S(8)
        local ox, oy = self:LocalToScreen(0, 0)
        R.DrawRadar(w * 0.5, h * 0.5, r, true, ox, oy)
        draw.SimpleText(R.RADAR_M .. " m to the edge", Kit.Font(11), S(8), h - S(8), Kit.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        if R.SquadOf(LocalPlayer()) == 0 then
            draw.SimpleText("Join a squad to see it here", Kit.Font(12), w * 0.5, S(14), Kit.C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local t = Kit.Button(col, function() return R.RadarOn() and "Compass on HUD: on" or "Compass on HUD: off" end, function()
        RunConsoleCommand("rhylib_radio_compass", R.RadarOn() and "0" or "1")
    end, { small = true, selected = function() return R.RadarOn() end, tooltip = "In first person it takes half of the chat's room" })
    t:Dock(TOP)
    t:DockMargin(0, S(6), 0, 0)
end

local function buildHails(col)
    local Kit = K()
    local S = Kit.S
    local any = false
    for id, r in pairs(R.rings) do
        if not any then heading(col, "Hails", true) any = true end
        local who = IsValid(r.caller) and r.caller:Nick() or "?"
        local p = row(col, R.COL.hail, "Hail · " .. r.label, who, 52)
        smallButton(p, "Decline", function() R.Answer(id, false) end, { danger = true })
        smallButton(p, "Answer", function() R.Answer(id, true) end, { accent = true })
    end
end

local function buildCallBar(page)
    local c = R.call
    if not c then return end
    local Kit = K()
    local S = Kit.S
    local bar = vgui.Create("DPanel", page)
    bar:Dock(TOP)
    bar:SetTall(S(38))
    bar:DockMargin(0, 0, 0, S(10))
    bar:DockPadding(S(8), S(6), S(8), S(6))
    function bar:Paint(w, h)
        surface.SetDrawColor(30, 26, 14, 255)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(R.COL.hail)
        surface.DrawOutlinedRect(0, 0, w, h)
        local live = #c.members >= 2
        local names = {}
        for _, p in ipairs(c.members) do if IsValid(p) and p ~= LocalPlayer() then names[#names + 1] = p:Nick() end end
        local text
        if live then
            local t = math.max(0, math.floor(CurTime() - (c.started or CurTime())))
            text = "Hail call · " .. c.label .. " · " .. table.concat(names, ", ") .. " · " .. string.format("%d:%02d", math.floor(t / 60), t % 60)
        else
            text = "Hailing... " .. (c.ringing > 0 and "ringing" or "waiting for an answer")
        end
        draw.SimpleText(text, Kit.Font(14, 600), S(12), h * 0.5, R.COL.hail, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    smallButton(bar, "Hang up", function() R.HangUp() end, { danger = true })
end

local function build(page)
    local Kit = K()
    local S = Kit.S
    buildCallBar(page)
    local left = Kit.Scroll(page)
    left:Dock(LEFT)
    left:SetWide(S(290))
    local right = Kit.Scroll(page)
    right:Dock(RIGHT)
    right:SetWide(S(280))
    right:DockMargin(S(12), 0, 0, 0)
    local mid = Kit.Scroll(page)
    mid:Dock(FILL)
    mid:DockMargin(S(12), 0, 0, 0)
    -- (rows go straight into the scroll panels; they take docked children)
    buildLeft(left)
    buildMiddle(mid)
    buildMap(right)
    buildHails(right)
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
    M.AddPage("radio", { title = "Radio", order = 31, group = "unit", build = build })
end
Rhylib.Hook.Add("InitPostEntity", "radio.page", addPage)
addPage()
