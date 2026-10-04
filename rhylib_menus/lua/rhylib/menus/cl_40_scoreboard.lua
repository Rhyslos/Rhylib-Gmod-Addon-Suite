--[[
    Scoreboard (hold Tab). Players are grouped by job (DarkRP jobs in their
    category order, or plain teams without DarkRP), each group under a
    header in the job's colour. Right-click while it's open to use the
    mouse; click a player for options (profile, copy SteamID, mute, and
    admin actions for staff).

    Values (ping, kills, ...) are read while drawing; the rows are only
    rebuilt when someone joins, leaves or changes job.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local COLS = {  -- right-aligned columns: label, width at 1080p
    { "Rank", 130 }, { "Kills", 64 }, { "Deaths", 64 }, { "Ping", 64 },
}

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

local function rankColour(group)
    if group == "superadmin" or group == "owner" then return C.bad end
    if group == "admin" or string.find(group, "admin", 1, true) or string.find(group, "mod", 1, true) then return C.warn end
    return C.textDim
end

local PANEL = {}

function PANEL:Init()
    local s = K.S
    local w = math.min(ScrW() - s(80), s(1000))
    local h = ScrH() - s(160)
    self:SetSize(w, h)
    self:Center()
    self:DockPadding(s(14), s(96), s(14), s(14))

    self.scroll = K.Scroll(self)
    self.scroll:Dock(FILL)
    self.signature = ""
    self.nextCheck = 0
end

function PANEL:Signature()
    local parts = {}
    for _, p in ipairs(player.GetAll()) do
        parts[#parts + 1] = p:UserID() .. ":" .. p:Team()
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

function PANEL:Rebuild()
    local s = K.S
    local sp = self.scroll
    sp:Clear()
    local order = teamOrder()
    local groups, teams = {}, {}
    for _, p in ipairs(player.GetAll()) do
        local t = p:Team()
        if not groups[t] then
            groups[t] = {}
            teams[#teams + 1] = t
        end
        table.insert(groups[t], p)
    end
    table.sort(teams, function(a, b)
        local oa, ob = order[a] or (100000 + a), order[b] or (100000 + b)
        return oa < ob
    end)

    for _, t in ipairs(teams) do
        local list = groups[t]
        table.sort(list, function(a, b) return string.lower(a:Nick()) < string.lower(b:Nick()) end)
        local col = team.GetColor(t)
        local head = vgui.Create("DPanel", sp)
        head:Dock(TOP)
        head:SetTall(s(26))
        head:DockMargin(0, s(6), s(8), s(2))
        local name = team.GetName(t)
        local count = #list
        function head:Paint(w, h)
            K.SetCol(C.header)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(col)
            surface.DrawRect(0, 0, s(4), h)
            surface.DrawRect(0, h - 1, w, 1)
            draw.SimpleText(string.upper(name), K.Font(13, 700), s(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(count, K.Font(12, 700), w - s(10), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        for i, p in ipairs(list) do self:AddRow(sp, p, col, i % 2 == 0) end
    end
end

function PANEL:AddRow(sp, p, col, alt)
    local s = K.S
    local row = vgui.Create("DButton", sp)
    row:SetText("")
    row:Dock(TOP)
    row:SetTall(s(36))
    row:DockMargin(0, 0, s(8), 1)
    local av = vgui.Create("AvatarImage", row)
    av:SetSize(s(28), s(28))
    av:SetPos(s(10), s(4))
    av:SetPlayer(p, 32)
    av:SetMouseInputEnabled(false)
    local me = p == LocalPlayer()

    function row:Paint(w, h)
        if not IsValid(p) then return true end
        K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
        surface.DrawRect(0, 0, w, h)
        K.SetCol(col, 160)
        surface.DrawRect(0, 0, s(2), h)
        if me then
            K.SetCol(C.accent, 160)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        -- Right-aligned columns: ping, deaths, kills, rank.
        local x = w - s(10)
        local f = K.Font(14, 500)
        draw.SimpleText(p:Ping(), f, x, h * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        x = x - s(COLS[4][2])
        draw.SimpleText(p:Deaths(), f, x, h * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        x = x - s(COLS[3][2])
        draw.SimpleText(p:Frags(), f, x, h * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        x = x - s(COLS[2][2])
        local group = p:GetUserGroup()
        draw.SimpleText(string.upper(group), K.Font(11, 700), x, h * 0.5, rankColour(group), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        x = x - s(COLS[1][2])
        local nameX = s(48)
        local room = x - nameX - s(10)
        draw.SimpleText(K.Fit(p:Nick(), K.Font(15, 500), room * 0.55), K.Font(15, 500), nameX, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local job = jobName(p)
        if job ~= team.GetName(p:Team()) then
            draw.SimpleText(K.Fit(job, K.Font(12), room * 0.4), K.Font(12), nameX + room * 0.58, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        if p:IsMuted() then
            draw.SimpleText("MUTED", K.Font(10, 700), x - s(4), h * 0.5, C.bad, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
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

function PANEL:Paint(w, h)
    local s = K.S
    K.Plate(0, 0, w, h, { ticks = "all" })
    local t = Rhylib.Config.Get("menus", "title")
    if not t or t == "" then t = GetHostName() end
    draw.SimpleText(K.Fit(t, K.Font(22, 700), w - s(300)), K.Font(22, 700), s(16), s(30), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(game.GetMap() .. "  ·  " .. player.GetCount() .. " / " .. game.MaxPlayers() .. " players", K.Font(13), w - s(16), s(30), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    K.SetCol(C.accent, 170)
    surface.DrawRect(s(14), s(52), w - s(28), 1)
    -- Column labels.
    local y = s(76)
    K.Caps("Player", s(14 + 48), y)
    local x = w - s(14) - s(10) - s(8)
    for i = #COLS, 1, -1 do
        K.Caps(COLS[i][1], x, y, nil, TEXT_ALIGN_RIGHT)
        x = x - s(COLS[i][2])
    end
    draw.SimpleText("Right-click for the mouse", K.Font(11), w - s(16), h - s(8), C.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
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

-- Staff actions on a player (scoreboard row, interaction wheel). With
-- rhylib_admin also Heal and Revive.
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
