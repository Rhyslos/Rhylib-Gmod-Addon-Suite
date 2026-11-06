--[[
    Scoreboard (hold Tab). A header with the server's title (and the
    menus scoreboardTag line above it) and facts on the right: map,
    online / slots, respawn tickets (while rhylib_spawns tickets are on),
    weather (rhylib_weather). Below, the players in groups laid out in two
    columns: by battalion with rhylib_roster (the battalion's colour band
    and a diamond, its name, "N online"), then Cadets (not through basic
    training yet) and Staff (players on a staff job); without rhylib_roster,
    by job (DarkRP category order, or plain teams). A row: portrait, rank
    chip (rhylib_roster prefix) edged in the group colour, name and job,
    squad tag (rhylib_radio, when known), a microphone while talking, DOWN
    while downed, MUTED, and ping bars. Your own row is tinted.
    Right-click while it's open to use the mouse; click a player for
    options (profile, copy SteamID, mute, and admin actions for staff).

    Values (ping, talking, down) are read while drawing; the rows are only
    rebuilt when someone joins, leaves, changes job or battalion.

    Client only. Adds: the "RhylibScoreboard" panel (Menus.scoreboard),
    Menus.AddStaffOptions, and the "Staff" interaction-wheel option.
    Hooks: ScoreboardShow / ScoreboardHide (other scoreboards' hooks on
    those events are removed at InitPostEntity, so ours is the only one),
    PlayerBindPress (right-click frees the mouse), OnScreenSizeChanged.
    Opening it asks rhylib_radio for the squad list (radio.dirreq) at most
    every 15 s, for the squad tags.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local function jobName(p)
    local j = p.getDarkRPVar and p:getDarkRPVar("job")
    if j and j ~= "" then return j end
    return team.GetName(p:Team())
end

-- Sort key for a team: DarkRP category order, then the team index.
local function teamOrder()
    local order = {}
    if DarkRP and DarkRP.getCategories and RPExtraTeams then
        local cats = DarkRP.getCategories().jobs or {}
        for ci, cat in ipairs(cats) do
            for ji, job in ipairs(cat.members or {}) do
                if job.team then order[job.team] = ci * 1000 + ji end
            end
        end
    end
    return order
end

-- Battalion facts from the DarkRP jobs: [bn] = { name, col, order }. The
-- name is the category of its jobs ("212th Attack Battalion"), the colour
-- its first job's.
local function battalions()
    local out = {}
    if not RPExtraTeams then return out end
    local catOf, catOrder = {}, {}
    if DarkRP and DarkRP.getCategories then
        for ci, cat in ipairs(DarkRP.getCategories().jobs or {}) do
            for _, job in ipairs(cat.members or {}) do catOf[job] = cat catOrder[job] = ci end
        end
    end
    for i, job in ipairs(RPExtraTeams) do
        local bn = job.battalion
        if isstring(bn) and bn ~= "" and not out[bn] then
            local cat = catOf[job]
            out[bn] = { name = (cat and cat.name) or bn, col = job.color or team.GetColor(i), order = (catOrder[job] or 99) * 1000 + i }
        end
    end
    return out
end

local STAFF_COL = Rhylib.UI.Col("scoreboard.staff", 194, 123, 224)    -- the Staff group
local ME_COL = Rhylib.UI.Col("scoreboard.me", 31, 42, 53)              -- your own row
local CADET_COL = Rhylib.UI.Col("scoreboard.cadets", 169, 168, 160)   -- the Cadets group

-- A staff job: one marked staff, or named like one.
local function staffJob(p)
    local j = RPExtraTeams and RPExtraTeams[p:Team()]
    if j and (j.staff or j.admin) then return true end
    local n = string.lower(team.GetName(p:Team()) or "")
    return string.find(n, "staff", 1, true) or string.find(n, "admin", 1, true) or string.find(n, "game master", 1, true)
        or string.find(n, "gamemaster", 1, true)
end

local function squadTag(p)
    local R = Rhylib.Radio
    if not (R and R.SquadOf and R.dir and R.dir.squads) then return nil end
    local ok, id = pcall(R.SquadOf, p)
    if not ok or not id or id == 0 then return nil end
    local sq = R.dir.squads[id]
    return sq and sq.name and string.upper(sq.name) or nil
end

local function isDown(p)
    local St = Rhylib.State
    if St and St.IsDown then return St.IsDown(p) end
    return false
end

local PANEL = {}

local HEAD_H, ROW_H, GROUP_GAP = 36, 46, 14

function PANEL:Init()
    local s = K.S
    local w = math.min(ScrW() - s(80), s(1100))
    local h = ScrH() - s(140)
    self:SetSize(w, h)
    self:Center()
    self:DockPadding(s(26), s(100), s(20), s(46))

    self.scroll = K.Scroll(self)
    self.scroll:Dock(FILL)
    self.signature = ""
    self.nextCheck = 0
end

-- One string of every player's UserID, team and battalion: when it
-- changes, Rebuild.
function PANEL:Signature()
    local parts = {}
    for _, p in ipairs(player.GetAll()) do
        parts[#parts + 1] = p:UserID() .. ":" .. p:Team() .. ":" .. p:GetNW2String(Rhylib.NW.BATTALION, "") .. ":" .. (p:GetNW2Bool("rhylib_trained", false) and 1 or 0)
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- Groups: { title, col, order, players }.
local function makeGroups()
    local R = Rhylib.Roster
    local groups, byKey = {}, {}
    local function group(key, title, col, order)
        local g = byKey[key]
        if not g then
            g = { title = title, col = col, order = order, players = {} }
            byKey[key] = g
            groups[#groups + 1] = g
        end
        return g
    end
    if R and R.Get then
        local bns = battalions()
        for _, p in ipairs(player.GetAll()) do
            local c = R.Get(p)
            local g
            if staffJob(p) then
                g = group("\1staff", "Staff", STAFF_COL, 1e9 + 1)
            elseif c.bn ~= "" then
                local b = bns[c.bn]
                g = group("bn:" .. c.bn, b and b.name or c.bn, b and b.col or team.GetColor(p:Team()), b and b.order or 5e8)
            elseif not c.trained then
                g = group("\1cadets", "Cadets", CADET_COL, 1e9)
            else
                -- (trained, no battalion: by job)
                local t = p:Team()
                g = group("team:" .. t, team.GetName(t), team.GetColor(t), 6e8 + t)
            end
            table.insert(g.players, p)
        end
    else
        local order = teamOrder()
        for _, p in ipairs(player.GetAll()) do
            local t = p:Team()
            local g = group("team:" .. t, team.GetName(t), team.GetColor(t), order[t] or (100000 + t))
            table.insert(g.players, p)
        end
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.title < b.title
    end)
    -- (in a group: highest rank first, then by name)
    for _, g in ipairs(groups) do
        table.sort(g.players, function(a, b)
            local ra, rb = a:GetNW2Int(Rhylib.NW.RANK, 0), b:GetNW2Int(Rhylib.NW.RANK, 0)
            if ra ~= rb then return ra > rb end
            return string.lower(a:Nick()) < string.lower(b:Nick())
        end)
    end
    return groups
end

function PANEL:Rebuild()
    local s = K.S
    local sp = self.scroll
    sp:Clear()
    local cols = vgui.Create("DPanel", sp)
    cols:Dock(TOP)
    cols.Paint = nil
    local panels = {}
    for _, g in ipairs(makeGroups()) do
        local gp = vgui.Create("DPanel", cols)
        gp.rows = #g.players
        local col, title = g.col, string.upper(g.title)
        local n = #g.players
        function gp:Paint(w, h)
            -- the colour band: tint, a thick edge and a diamond
            local hh = s(HEAD_H)
            surface.SetDrawColor(col.r, col.g, col.b, 30)
            surface.DrawRect(0, 0, w, hh)
            K.SetCol(col)
            surface.DrawRect(0, 0, s(4), hh)
            local cx, cy, r = s(24), hh * 0.5, s(8)
            draw.NoTexture()
            surface.DrawPoly({ { x = cx, y = cy - r }, { x = cx + r, y = cy }, { x = cx, y = cy + r }, { x = cx - r, y = cy } })
            K.SetCol(C.bg)
            local ri = r - s(3)
            surface.DrawPoly({ { x = cx, y = cy - ri }, { x = cx + ri, y = cy }, { x = cx, y = cy + ri }, { x = cx - ri, y = cy } })
            local cnt = n .. " online"
            surface.SetFont(K.Font(13))
            local cw = surface.GetTextSize(cnt)
            draw.SimpleText(K.Fit(title, K.Font(16, 700), w - s(52) - cw - s(20)), K.Font(16, 700), s(42), hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(cnt, K.Font(13), w - s(12), hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        for i, p in ipairs(g.players) do
            self:AddRow(gp, p, col, s(HEAD_H) + (i - 1) * s(ROW_H))
        end
        panels[#panels + 1] = gp
    end
    -- Two columns: each group goes to the shorter one, in order.
    function cols:PerformLayout(w)
        local gap = s(18)
        local cw = math.floor((w - gap) / 2)
        local hs = { 0, 0 }
        for _, gp in ipairs(panels) do
            local gh = s(HEAD_H) + gp.rows * s(ROW_H)
            local c = hs[1] <= hs[2] and 1 or 2
            gp:SetPos((c - 1) * (cw + gap), hs[c])
            gp:SetSize(cw, gh)
            for _, row in ipairs(gp:GetChildren()) do row:SetWide(cw) end
            hs[c] = hs[c] + gh + s(GROUP_GAP)
        end
        local want = math.max(hs[1], hs[2])
        if self:GetTall() ~= want then self:SetTall(want) end
    end
end

-- Ping bars: three, green / amber / red.
local function pingBars(x, y, ms)
    local s = K.S
    local good = ms < 80 and 3 or (ms < 160 and 2 or 1)
    local col = good == 3 and C.good or (good == 2 and C.warn or C.bad)
    for i = 1, 3 do
        local bh = s(4 + (i - 1) * 4)
        K.SetCol(i <= good and col or C.edgeLight, i <= good and 255 or 140)
        surface.DrawRect(x + (i - 1) * s(5), y - bh, s(3), bh)
    end
end

-- A microphone (talking).
local function mic(x, y, size, col)
    local s = size / 16
    K.SetCol(col)
    surface.DrawRect(x + 6 * s, y + 1 * s, 4 * s, 8 * s)
    surface.DrawRect(x + 3 * s, y + 7 * s, 1.5 * s, 3 * s)
    surface.DrawRect(x + 11.5 * s, y + 7 * s, 1.5 * s, 3 * s)
    surface.DrawRect(x + 3 * s, y + 10 * s, 10 * s, 1.5 * s)
    surface.DrawRect(x + 7.25 * s, y + 11 * s, 1.5 * s, 4 * s)
end

function PANEL:AddRow(gp, p, col, y)
    local s = K.S
    local row = vgui.Create("DButton", gp)
    row:SetText("")
    row:SetPos(0, y)
    row:SetTall(s(ROW_H))
    local me = p == LocalPlayer()
    local R = Rhylib.Roster

    function row:Paint(w, h)
        if not IsValid(p) then return true end
        if me then
            K.SetCol(ME_COL)
            surface.DrawRect(0, 0, w, h)
        elseif self:IsHovered() then
            K.SetCol(C.rowHover)
            surface.DrawRect(0, 0, w, h)
        end
        K.SetCol(C.edgeDark, 160)
        surface.DrawRect(0, h - 1, w, 1)
        -- portrait
        local ps = s(34)
        local x = s(12)
        if Rhylib.UI and Rhylib.UI.DrawPortrait then Rhylib.UI.DrawPortrait(p, x, (h - ps) * 0.5, ps) end
        x = x + ps + s(10)
        -- rank chip
        local prefix = R and R.Prefix and R.Get and R.Get(p).has and R.Prefix(p) or nil
        if prefix then
            local cw = s(38)
            local cy = math.floor((h - s(20)) * 0.5)
            K.SetCol(col)
            surface.DrawOutlinedRect(x, cy, cw, s(20))
            draw.SimpleText(K.Fit(prefix, K.Font(11, 700), cw - s(4)), K.Font(11, 700), x + cw * 0.5, cy + s(10), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            x = x + cw + s(10)
        end
        -- right side, from the edge in: ping, DOWN / talking / muted, squad
        local rx = w - s(12)
        pingBars(rx - s(13), h * 0.5 + s(7), p:Ping())
        rx = rx - s(13) - s(12)
        if isDown(p) then
            draw.SimpleText("DOWN", K.Font(11, 700), rx, h * 0.5, C.bad, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            rx = rx - s(44)
        end
        if p:IsSpeaking() then
            mic(rx - s(16), h * 0.5 - s(8), s(16), C.good)
            rx = rx - s(24)
        end
        if p:IsMuted() then
            draw.SimpleText("MUTED", K.Font(10, 700), rx, h * 0.5, C.bad, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            rx = rx - s(46)
        end
        local sq = squadTag(p)
        if sq then
            local f = K.Font(11, 700)
            surface.SetFont(f)
            local tw = math.min(surface.GetTextSize(sq), s(90))
            local bw = tw + s(12)
            K.SetCol(C.good, 110)
            surface.DrawOutlinedRect(rx - bw, h * 0.5 - s(10), bw, s(20))
            draw.SimpleText(K.Fit(sq, f, s(90)), f, rx - bw * 0.5, h * 0.5, C.good, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            rx = rx - bw - s(8)
        end
        -- name and job
        local room = rx - x - s(6)
        draw.SimpleText(K.Fit(p:Nick(), K.Font(14, 500), room), K.Font(14, 500), x, h * 0.5 - s(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(K.Fit(jobName(p), K.Font(12), room), K.Font(12), x, h * 0.5 + s(9), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end

    function row:DoClick()
        if not IsValid(p) then return end
        local m = K.Menu()
        m:AddOption("Steam profile", function() if IsValid(p) then p:ShowProfile() end end)
        m:AddOption("Copy SteamID", function() if IsValid(p) then SetClipboardText(p:SteamID()) end end)
        if not me then
            m:AddOption(p:IsMuted() and "Unmute voice" or "Mute voice", function() if IsValid(p) then p:SetMuted(not p:IsMuted()) end end)
        end
        if Menus.IsStaff and Menus.IsStaff() and Menus.AdminMod and Menus.AdminMod() then
            m:AddSpacer()
            Menus.AddStaffOptions(m, p)
        end
        m:Open()
    end
end

function PANEL:Think()
    if RealTime() < self.nextCheck then return end
    self.nextCheck = RealTime() + 0.5
    local sig = self:Signature()
    if sig ~= self.signature then
        self.signature = sig
        self:Rebuild()
    end
end

-- The header facts: { label, value, colour? }.
local function facts()
    local out = {
        { "Map", game.GetMap() },
        { "Online", player.GetCount() .. " / " .. game.MaxPlayers() },
    }
    local Sp = Rhylib.Spawns
    if Sp and Sp.TicketsOn and Sp.TicketsOn() then
        out[#out + 1] = { "Respawn tickets", tostring(Sp.Tickets()), C.warn }
    end
    local W = Rhylib.Weather
    if W and W.Kind and W.KINDS then
        local k = W.Kind()
        local info = W.KINDS[k]
        out[#out + 1] = { "Weather", info and info.name or k }
    end
    return out
end

function PANEL:Paint(w, h)
    local s = K.S
    K.Plate(0, 0, w, h, { ticks = "all" })
    local t = Rhylib.Config.Get("menus", "title")
    if not t or t == "" then t = GetHostName() end
    local tag = Rhylib.Config.Get("menus", "scoreboardTag")
    -- facts on the right, from the edge in
    local x = w - s(26)
    local list = facts()
    for i = #list, 1, -1 do
        local f = list[i]
        surface.SetFont(K.Font(15, 700))
        local vw = surface.GetTextSize(f[2])
        surface.SetFont(K.Font(12))
        local lw = surface.GetTextSize(f[1])
        draw.SimpleText(f[1], K.Font(12), x, s(42), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText(f[2], K.Font(15, 700), x, s(62), f[3] or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        x = x - math.max(vw, lw) - s(24)
    end
    local room = x - s(26)
    if isstring(tag) and tag ~= "" then
        draw.SimpleText(K.Fit(string.upper(tag), K.Font(12, 700), room), K.Font(12, 700), s(26), s(34), C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    draw.SimpleText(K.Fit(t, K.Font(30, 700), room), K.Font(30, 700), s(26), s(62), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    K.SetCol(C.edgeLight, 120)
    surface.DrawRect(s(1), s(86), w - s(2), 1)
    -- footer
    surface.DrawRect(s(1), h - s(38), w - s(2), 1)
    draw.SimpleText("Right-click: mouse  ·  click a trooper for options", K.Font(12), s(26), h - s(19), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local staff = 0
    for _, p in ipairs(player.GetAll()) do if p:IsAdmin() then staff = staff + 1 end end
    draw.SimpleText("Staff online: " .. staff, K.Font(12), w - s(26), h - s(19), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

vgui.Register("RhylibScoreboard", PANEL, "EditablePanel")


local clickerOn = false  -- whether we turned the screen clicker on

local function close()
    local open = IsValid(Menus.scoreboard) and Menus.scoreboard:IsVisible()
    if IsValid(Menus.scoreboard) then Menus.scoreboard:SetVisible(false) end
    CloseDermaMenus()
    if clickerOn then
        gui.EnableScreenClicker(false)
        clickerOn = false
    end
    return open
end
Menus.RegisterCloser("scoreboard", close)

Rhylib.Hook.Add("ScoreboardShow", "menus.scoreboard", function()
    if not IsValid(Menus.scoreboard) then
        Menus.scoreboard = vgui.Create("RhylibScoreboard")
    end
    local sb = Menus.scoreboard
    -- (squad tags: ask rhylib_radio for its squad list now and then)
    local R = Rhylib.Radio
    if R and Rhylib.Net and (not Menus.sbDirAt or RealTime() > Menus.sbDirAt) then
        Menus.sbDirAt = RealTime() + 15
        Rhylib.Net.Start("radio.dirreq")
        net.SendToServer()
    end
    sb.signature = ""
    sb.nextCheck = 0
    sb:SetVisible(true)
    return true
end)

Rhylib.Hook.Add("ScoreboardHide", "menus.scoreboard", function()
    close()
    return true
end)

-- Other scoreboards (FAdmin's, addons) also claim Tab and can win the
-- race; ours is the only one.
local function takeOver()
    for _, ev in ipairs({ "ScoreboardShow", "ScoreboardHide" }) do
        local t = hook.GetTable()[ev]
        if t then
            for id in pairs(t) do
                if id ~= "Rhylib.Bus" then hook.Remove(ev, id) end
            end
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "menus.scoreboard", takeOver)
timer.Simple(5, takeOver)  -- in case of a Lua refresh

-- Right-click while the scoreboard is up: free the mouse.
Rhylib.Hook.Add("PlayerBindPress", "menus.scoreboard", function(_, bind, pressed)
    if pressed and IsValid(Menus.scoreboard) and Menus.scoreboard:IsVisible() and string.find(bind, "+attack2", 1, true) then
        gui.EnableScreenClicker(true)
        clickerOn = true
        return true
    end
end)

-- The screen size changed: build a new one next time.
Rhylib.Hook.Add("OnScreenSizeChanged", "menus.scoreboard", function()
    if IsValid(Menus.scoreboard) then Menus.scoreboard:Remove() end
end)

-- Menus.AddStaffOptions(m, p): adds staff actions on player p to menu m
-- (scoreboard row, interaction wheel). With rhylib_admin also Heal and
-- Revive, run through Admin.Run; else through Menus.RunPlayerAction.
-- The server still checks every command.
-- Example: local m = Rhylib.Menus.Kit.Menu() Rhylib.Menus.AddStaffOptions(m, ply) m:Open()
function Menus.AddStaffOptions(m, p)
    local A = Rhylib.Admin
    local rhylib = A and A.Run and A.TargetWord
    local list = { { "Go to", "goto" }, { "Bring", "bring" }, { "Return", "return" }, { "Spectate", "spectate" },
        { "Freeze", "freeze" }, { "Unfreeze", "unfreeze" }, { "Slay", "slay" }, { "Kick", "kick" } }
    if rhylib then
        table.insert(list, 1, { "Revive", "revive" })
        table.insert(list, 1, { "Heal", "heal" })
    end
    for _, a in ipairs(list) do
        m:AddOption(a[1], function()
            if not IsValid(p) then return end
            -- (rhylib_admin runs its own commands; other mods go through RunPlayerAction)
            if rhylib then A.Run(a[2], { A.TargetWord(p) }) else Menus.RunPlayerAction(a[2], p) end
        end)
    end
end

-- Interaction wheel: staff get their actions too.
Rhylib.Hook.Add("Rhylib.WheelOptions", "menus.staff", function(t, me, add)
    if not (Menus.IsStaff and Menus.IsStaff() and Menus.AdminMod and Menus.AdminMod()) then return end
    add("Staff", function(x)
        local m = Menus.Kit.Menu()
        Menus.AddStaffOptions(m, x)
        m:Open()
    end, { order = 90, sub = "Heal, revive, bring..." })
end)
