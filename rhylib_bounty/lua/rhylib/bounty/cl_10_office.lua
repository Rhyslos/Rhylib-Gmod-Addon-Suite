--[[
    Bounty Office window (client), opened by E on a Bounty Office
    (bounty.open). Tabs:
      Board    open bounties: target, dead / alive, reward, poster, time
               left; Accept (a contract into your inventory), Cancel (your
               own, or any for staff). Standalone ones can't be accepted.
      Post     pick an online player, reward, dead / alive / either,
               standalone (one contract, put in your inventory to hand to
               a hunter); staff: free bounties, also on yourself.
      Turn in  the proof, contracts and prisoner you have; Turn in claims
               everything that matches an open bounty.
      Gear     hunter gear for money (config bounty shop).
    Also keeps the client's copy of the board: Rhylib.Bounty.board (list
    from bounty.list), used by posters, the datapad tab and the puck HUD.
    Needs rhylib_menus (Kit). Esc closes the window.
]]

local B = Rhylib.Bounty
local Net = Rhylib.Net

B.board = B.board or {}
local win, office, tab, status = nil, nil, "board", nil
local post = { sid = nil, reward = "", mode = 3, std = false, free = false }

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end

-- B.FormatMoney(n): DarkRP's money format.
function B.FormatMoney(n)
    n = tonumber(n) or 0
    return DarkRP and DarkRP.formatMoney and DarkRP.formatMoney(n) or ("$" .. n)
end

local function modeLabel(m)
    for _, o in ipairs(B.MODES) do if o[1] == m then return o[2] end end
    return tostring(m)
end

local function isStaff()
    local me = LocalPlayer()
    local A = Rhylib.Admin
    if A and A.Has then return A.Has(me, "rhylib.bounty.gm", "admin") end
    return me:IsAdmin()
end

local function timeLeft(s)
    s = math.max(0, math.floor(s))
    if s >= 3600 then return math.floor(s / 3600) .. " h " .. math.floor(s % 3600 / 60) .. " min" end
    return math.max(1, math.floor(s / 60)) .. " min"
end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

Net.Receive("bounty.list", function()
    local len = net.ReadUInt(32)
    local raw = util.Decompress(net.ReadData(len), 262144)
    local t = raw and util.JSONToTable(raw)
    if not istable(t) then return end
    local now = RealTime()
    for _, b in ipairs(t) do b.endsAt = now + (tonumber(b.left) or 0) end
    B.board = t
    if IsValid(win) and win.Refresh then win:Refresh() end
end)

Rhylib.Hook.Add("InitPostEntity", "bounty.listreq", function()
    Net.Start("bounty.listreq")
    net.SendToServer()
end)

Net.Receive("bounty.msg", function()
    local ok, text = net.ReadBool(), net.ReadString()
    status = { ok = ok, text = text }
    chat.AddText(ok and Color(230, 190, 90) or Color(230, 110, 90), "[Bounty] ", Color(230, 230, 230), text)
    if IsValid(win) and win.Refresh then win:Refresh() end
end)

Net.Receive("bounty.collectx", function()
    local why = net.ReadString()
    local M = Rhylib.Menus
    if M and M.WheelProgressStop then M.WheelProgressStop() end
    if why ~= "" then chat.AddText(Color(230, 110, 90), "[Bounty] ", Color(230, 230, 230), why) end
end)

--------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------

local function line(parent, text, col)
    local k = K()
    local l = k.Label(parent, text, 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(6))
    return l
end

local function row(parent, title, desc, rightW)
    local k = K()
    local r = k.Row(parent, title, desc)
    r:Dock(TOP)
    r:DockMargin(0, 0, k.S(8), k.S(3))
    r.right:SetWide(k.S(rightW or 200))
    return r
end

local function button(r, text, fn, opts)
    local k = K()
    local b = k.Button(r.right, text, fn, opts or { small = true })
    b:Dock(RIGHT)
    b:SetWide(k.S(96))
    b:DockMargin(k.S(6), k.S(7), 0, k.S(7))
    return b
end

local function boardTab(body)
    local k = K()
    local C = k.C
    local me = LocalPlayer()
    local mySid = me:SteamID64() or ""
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #B.board == 0 then line(sp, "No open bounties.") return end
    local staff = isStaff()
    for _, b in ipairs(B.board) do
        local who = b.tsid == mySid and "  ·  THAT'S YOU" or ""
        local desc = modeLabel(b.mode) .. "  ·  posted by " .. tostring(b.byName) .. "  ·  " .. timeLeft((b.endsAt or 0) - RealTime()) .. " left"
            .. (b.std and "  ·  standalone contract" or "") .. (b.kind == "npc" and "  ·  NPC" or "")
        local r = row(sp, b.name .. "  —  " .. B.FormatMoney(b.reward) .. who, desc, 210)
        if staff or (b.by ~= "" and b.by == mySid) then
            button(r, "Cancel", function()
                Derma_Query("Cancel the bounty on " .. b.name .. "? " .. (b.free and "" or "The poster gets the money back minus the fee."),
                    "Cancel bounty", "Cancel it", function()
                        Net.Start("bounty.cancel")
                        net.WriteUInt(b.id, 32)
                        net.SendToServer()
                    end, "Keep it")
            end, { small = true, danger = true })
        end
        if not b.std then
            button(r, "Accept", function()
                Net.Start("bounty.accept")
                net.WriteEntity(office)
                net.WriteUInt(b.id, 32)
                net.SendToServer()
            end, { small = true, accent = true, enabled = b.tsid ~= mySid })
        end
    end
end

local function postTab(body)
    local k = K()
    local C = k.C
    local s = k.S
    local staff = isStaff()
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    line(sp, "Your money is held by the office until the bounty is claimed. If nobody claims it in time you get it back minus a fee. Proof of a kill pays dead and dead-or-alive bounties; bringing the target in cuffed pays alive and dead-or-alive ones.")

    local function targetName()
        for _, p in ipairs(player.GetAll()) do if p:SteamID64() == post.sid then return p:Nick() end end
        return "Pick a player"
    end
    local r = row(sp, "Target", "An online player", 260)
    local tb = k.Button(r.right, function() return targetName() .. "  ▾" end, function()
        local m = k.Menu()
        local list = player.GetAll()
        table.sort(list, function(a, b) return a:Nick() < b:Nick() end)
        for _, p in ipairs(list) do
            if p ~= LocalPlayer() or staff then
                m:AddOption(p:Nick(), function() post.sid = p:SteamID64() end)
            end
        end
        m:Open()
    end, { small = true, align = "left" })
    tb:Dock(FILL)
    tb:DockMargin(0, s(7), 0, s(7))

    r = row(sp, "Reward", "From " .. B.FormatMoney(B.Cfg("postMin")) .. " to " .. B.FormatMoney(B.Cfg("postMax")), 160)
    local e = k.TextEntry(r.right, "0")
    e:Dock(FILL)
    e:DockMargin(0, s(5), 0, s(5))
    e:SetNumeric(true)
    e:SetText(post.reward)
    e:SetUpdateOnType(true)
    function e:OnValueChange(v) post.reward = v end

    r = row(sp, "Wanted", nil, 330)
    local ch = k.Choices(r.right, { { 1, "Dead" }, { 2, "Alive" }, { 3, "Either" } }, function() return post.mode end, function(v) post.mode = v end)
    ch:Dock(FILL)
    ch:DockMargin(0, s(7), 0, s(7))

    r = row(sp, "Standalone contract", "One contract only, put in your inventory: give it to the hunter you choose. Only it can claim this bounty.", 64)
    k.Toggle(r.right, function() return post.std end, function(v) post.std = v end):Dock(RIGHT)
    if staff then
        r = row(sp, "Free (staff)", "Paid by the office, not you; you may also pick yourself", 64)
        k.Toggle(r.right, function() return post.free end, function(v) post.free = v end):Dock(RIGHT)
        line(sp, "Staff: to put a bounty on an NPC, look at it, hold E and pick \"Put a bounty on it\".")
    end

    local pb = k.Button(sp, "Post bounty", function()
        if not post.sid then status = { ok = false, text = "Pick a target" } win:Refresh() return end
        Net.Start("bounty.post")
        net.WriteEntity(office)
        net.WriteString(post.sid)
        net.WriteUInt(math.Clamp(math.floor(tonumber(post.reward) or 0), 0, 4294967295), 32)
        net.WriteUInt(post.mode, 2)
        net.WriteBool(post.std)
        net.WriteBool(post.free and staff)
        net.SendToServer()
    end, { accent = true })
    pb:Dock(TOP)
    pb:DockMargin(0, s(8), s(8), 0)
end

local function carriedNotes(id)
    local out = {}
    local I = Rhylib.Inventory
    for _, inst in pairs(I and I.byUid or {}) do
        if inst.id == id then out[#out + 1] = (inst.data and inst.data.note) or "?" end
    end
    return out
end

local function turnInTab(body)
    local k = K()
    local s = k.S
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    local proofs, contracts = carriedNotes(B.PROOF), carriedNotes(B.CONTRACT)
    local h = k.Heading(sp, "Proof you carry")
    h:Dock(TOP)
    h:DockMargin(0, 0, s(8), s(4))
    if #proofs == 0 then line(sp, "None. Collect it from a wanted target's body (hold E on it).") end
    for _, n in ipairs(proofs) do line(sp, n, k.C.text) end
    h = k.Heading(sp, "Contracts you carry")
    h:Dock(TOP)
    h:DockMargin(0, s(6), s(8), s(4))
    if #contracts == 0 then line(sp, "None.") end
    for _, n in ipairs(contracts) do line(sp, (string.gsub(n, "^#%d+ ", "")), k.C.text) end
    local MP = Rhylib.MP
    local prisoner = LocalPlayer():GetNW2Entity("rhylib_escorting")
    h = k.Heading(sp, "Prisoner")
    h:Dock(TOP)
    h:DockMargin(0, s(6), s(8), s(4))
    line(sp, IsValid(prisoner) and (prisoner:Nick() .. " (escorted by you)") or "Nobody. Bind a target and escort them here (R with the binders).",
        IsValid(prisoner) and k.C.text or nil)
    line(sp, "Turning in pays every open bounty your proof or prisoner matches. Standalone bounties also need their contract.")
    local b = k.Button(sp, "Turn in", function()
        Net.Start("bounty.turnin")
        net.WriteEntity(office)
        net.SendToServer()
    end, { accent = true })
    b:Dock(TOP)
    b:DockMargin(0, s(8), s(8), 0)
end

local function gearTab(body)
    local k = K()
    local Items = Rhylib.Items
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if B.Cfg("hunterOnly") and not B.IsHunter(LocalPlayer()) then line(sp, "Only bounty hunters can buy here.", k.C.warn) end
    for i, r in ipairs(B.Cfg("shop") or {}) do
        local def = Items and Items.Get(r[1])
        if def then
            local rr = row(sp, def.name or r[1], B.FormatMoney(r[2]) .. (def.desc and ("  ·  " .. def.desc) or ""), 110)
            button(rr, "Buy", function()
                Net.Start("bounty.buy")
                net.WriteEntity(office)
                net.WriteUInt(i, 8)
                net.SendToServer()
            end, { small = true, accent = true })
        end
    end
end

local TABS = {
    { "board", "Board", boardTab }, { "post", "Post", postTab }, { "turnin", "Turn in", turnInTab }, { "gear", "Gear", gearTab },
}

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function open(ent)
    local k = K()
    if not k then return end
    if IsValid(win) then win:Remove() end
    office = ent
    status = nil
    local s = k.S
    win = vgui.Create("EditablePanel")
    win:SetSize(math.min(ScrW() - s(80), s(860)), math.min(ScrH() - s(80), s(640)))
    win:Center()
    win:MakePopup()
    win:DockPadding(s(14), s(42), s(14), s(14))
    function win:Paint(w, h) k.Plate(0, 0, w, h, { title = "Bounty Office", ticks = "all" }) end
    function win:Think()
        if not IsValid(office) or LocalPlayer():GetPos():DistToSqr(office:GetPos()) > 260 * 260 then self:Remove() end
    end

    local top = vgui.Create("DPanel", win)
    top:Dock(TOP)
    top:SetTall(s(32))
    top:DockMargin(0, 0, 0, s(8))
    top.Paint = nil
    local close = k.Button(top, "Close", function() win:Remove() end, { small = true })
    close:Dock(RIGHT)
    close:SetWide(s(90))
    for _, t in ipairs(TABS) do
        local b = k.Button(top, t[2], function() tab = t[1] status = nil win:Refresh() end,
            { small = true, selected = function() return tab == t[1] end })
        b:Dock(LEFT)
        b:SetWide(s(120))
        b:DockMargin(0, 0, s(6), 0)
    end
    local body = vgui.Create("DPanel", win)
    body:Dock(FILL)
    body.Paint = nil

    function win:Refresh()
        body:Clear()
        if status then
            local l = k.Label(body, status.text, 13, 600, status.ok and k.C.good or k.C.bad)
            l:Dock(TOP)
            l:DockMargin(0, 0, 0, s(6))
        end
        for _, t in ipairs(TABS) do
            if t[1] == tab then t[3](body) end
        end
    end
    win:Refresh()
end

Net.Receive("bounty.open", function()
    local ent = net.ReadEntity()
    if IsValid(ent) then open(ent) end
end)

local function closer()
    if IsValid(win) then win:Remove() return true end
    return false
end
Rhylib.Hook.Add("InitPostEntity", "bounty.closer", function()
    local M = Rhylib.Menus
    if M and M.RegisterCloser then M.RegisterCloser("bounty", closer) end
end)
if Rhylib.Menus and Rhylib.Menus.RegisterCloser then Rhylib.Menus.RegisterCloser("bounty", closer) end
