--[[
    Client side of the admin suite: replies and action notices in chat,
    announcements (the event banner), the map change countdown, and the
    helpers the staff menu uses (rhylib_menus cl_30_commands.lua):
        Admin.Run(id, words)               send a command
        Admin.AskArgs(cmd, done(words))    ask for its arguments (menus / text boxes)
        Admin.RequestList(which, arg, cb)  0 maps, 1 bans, 2 log, 3 warnings (SteamID64)
        Admin.MapPicker(done(map))         the map window (cl_20_maps.lua)
        Admin.PickPlayer(cmd, done(word))  a player menu for a command
        Admin.TargetWord(ply)              how a picked player is sent (SteamID64)
        Admin.TrackAsk(panel)              free the mouse while a picker is open
    Client only. Pickers need rhylib_menus (its Kit); without it they do
    nothing and chat commands must be typed in full.
]]

local Admin = Rhylib.Admin

local ACCENT = Color(230, 170, 70)
local BAD = Color(235, 90, 80)
local TEXT = Color(225, 225, 225)

Rhylib.Net.Receive("admin.msg", function()
    local bad = net.ReadBool()
    local text = net.ReadString()
    chat.AddText(bad and BAD or ACCENT, "[Admin] ", TEXT, text)
end)

Rhylib.Net.Receive("admin.announce", function()
    local by = net.ReadString()
    local text = net.ReadString()
    local Chat = Rhylib.Chat
    if Chat and Chat.ShowEvent then Chat.ShowEvent(by, text) end
    chat.AddText(ACCENT, "[Announcement] ", TEXT, text)
    surface.PlaySound("buttons/blip1.wav")
end)

-- Map change countdown at the top of the screen.
local countdown
Rhylib.Net.Receive("admin.countdown", function()
    local m, secs = net.ReadString(), net.ReadUInt(6)
    if m == "" then countdown = nil return end   -- cancelled
    countdown = { map = m, at = CurTime() + secs }
    chat.AddText(ACCENT, "[Admin] ", TEXT, "Changing map to " .. m .. " in " .. secs .. " seconds")
end)
Rhylib.Hook.Add("HUDPaint", "admin.countdown", function()
    if not countdown then return end
    local left = math.ceil(countdown.at - CurTime())
    if left < 0 then countdown = nil return end
    local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(ScrH() / 40), 700) or "DermaLarge"
    draw.SimpleTextOutlined("Map change: " .. countdown.map .. " in " .. left, font, ScrW() * 0.5, ScrH() * 0.12, ACCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)

-- Admin.Run(id, words): asks the server to run a command (net admin.run).
-- The server checks everything. At most 15 words; each is cut to 200
-- characters on the server, so a long text argument should be one word.
-- Example: Rhylib.Admin.Run("bring", { Rhylib.Admin.TargetWord(ply) })
-- Example: Rhylib.Admin.Run("announce", { "Event starts in 5 minutes" })
function Admin.Run(id, words)
    words = words or {}
    Rhylib.Net.Start("admin.run")
    net.WriteString(id)
    net.WriteUInt(math.min(#words, 15), 4)
    for i = 1, math.min(#words, 15) do net.WriteString(tostring(words[i])) end
    net.SendToServer()
end

-- How the menu names a player for a command: SteamID64 (bots: their
-- name; invalid: "^" = you).
function Admin.TargetWord(p)
    if not IsValid(p) then return "^" end
    if p:IsBot() then return p:Nick() end
    return p:SteamID64() or p:Nick()
end

-- Choices for an argument kind, or nil (= type it). "?" = type your own.
-- Each choice: { word sent, label shown }.
local function choices(kind)
    if kind == "rank" then
        local out = {}
        local mine = Admin.Level(LocalPlayer())
        for _, r in ipairs(Admin.Ranks()) do
            if (r.level or 0) < mine then out[#out + 1] = { r.id, r.name } end
        end
        return out
    elseif kind == "rosterrank" and Rhylib.Roster then
        local out = {}
        for i, r in ipairs(Rhylib.Roster.Ranks()) do out[#out + 1] = { tostring(i), r[1] .. " · " .. r[2] } end
        return out
    elseif kind == "qual" and Rhylib.Roster then
        local out = {}
        for _, q in ipairs(Rhylib.Roster.Quals()) do out[#out + 1] = { q[1], q[2] } end
        return out
    elseif kind == "onoff" then
        return { { "on", "On" }, { "off", "Off" } }
    elseif kind == "battalion" then
        local out, seen = {}, {}
        for _, job in pairs(RPExtraTeams or {}) do
            local c = job.category
            if c and not seen[c] then
                seen[c] = true
                out[#out + 1] = { c, c }
            end
        end
        table.sort(out, function(a, b) return a[1] < b[1] end)
        return #out > 0 and out or nil
    elseif kind == "job" then
        local out = {}
        for _, job in pairs(RPExtraTeams or {}) do out[#out + 1] = { job.command or job.name, job.name } end
        table.sort(out, function(a, b) return a[2] < b[2] end)
        return #out > 0 and out or nil
    elseif kind == "duration" then
        return { { "30m", "30 minutes" }, { "2h", "2 hours" }, { "1d", "1 day" }, { "3d", "3 days" }, { "1w", "1 week" },
            { "perm", "Permanent" }, { "?", "Other..." } }
    elseif kind == "minutes" then
        return { { "5", "5 minutes" }, { "10", "10 minutes" }, { "15", "15 minutes" }, { "30", "30 minutes" }, { "?", "Other..." } }
    elseif kind == "scale" then
        return { { "0.5", "Small (0.5)" }, { "0.75", "Short (0.75)" }, { "1", "Normal" }, { "1.25", "Tall (1.25)" },
            { "1.5", "Big (1.5)" }, { "2", "Giant (2)" }, { "?", "Other..." } }
    elseif kind == "call" then
        local out = {}
        for _, c in ipairs(Admin.Cfg("calls") or {}) do
            local m = tonumber(c.minutes) or 0
            out[#out + 1] = { c.id, (c.name or c.id) .. (m > 0 and (" (" .. m .. " min)") or "") }
        end
        out[#out + 1] = { "custom", "Custom text..." }
        return out
    elseif kind == "callmins" then
        return { { "d", "Preset's own timer" }, { "0", "No timer" }, { "5", "5 minutes" }, { "10", "10 minutes" },
            { "15", "15 minutes" }, { "20", "20 minutes" }, { "30", "30 minutes" }, { "?", "Other..." } }
    elseif kind == "illness" then
        return { { "viral", "Viral" }, { "bacterial", "Bacterial" }, { "poison", "Poison" } }
    elseif kind == "illload" then
        return { { "20", "Light (20)" }, { "45", "Moderate (45)" }, { "75", "Severe (75)" }, { "?", "Other..." } }
    elseif kind == "mult" then
        return { { "0.5", "Half" }, { "1", "Normal" }, { "1.5", "x1.5" }, { "2", "Double" }, { "3", "Triple" }, { "?", "Other..." } }
    end
end

-- Hints shown in the text prompt for kinds you type.
local HINT = {
    number = "A number", text = "", word = "", class = "Weapon class, e.g. rhylib_dc15a",
    map = "Map name, e.g. rp_venator", duration = "30m, 2h, 1d, 1w or perm", minutes = "Minutes",
    scale = "1 = normal", mult = "1 = normal", model = "models/....mdl, or reset",
    sound = "e.g. ambient/alarms/klaxon1.wav", callmins = "Minutes, 0 = no timer",
}

-- Pickers opened from chat need the mouse; it's freed while any is open.
-- Admin.TrackAsk(panel): adds a panel; a 0.2 s timer drops closed ones and
-- gives the mouse back when none are left. Returns the panel.
local askPanels = {}
local cursorOn = false
local function track(p)
    if not IsValid(p) then return p end
    askPanels[#askPanels + 1] = p
    if not cursorOn and not vgui.CursorVisible() then
        cursorOn = true
        gui.EnableScreenClicker(true)
        timer.Create("rhylib_admin_ask", 0.2, 0, function()
            for k = #askPanels, 1, -1 do
                if not IsValid(askPanels[k]) or not askPanels[k]:IsVisible() then table.remove(askPanels, k) end
            end
            if #askPanels == 0 then
                timer.Remove("rhylib_admin_ask")
                cursorOn = false
                gui.EnableScreenClicker(false)
            end
        end)
    end
    return p
end
Admin.TrackAsk = track

-- Pick a player you can use cmd on (players you outrank, you, and * for mass commands).
-- done(word) gets "^", "*" or Admin.TargetWord(player).
function Admin.PickPlayer(cmd, done)
    local K = Rhylib.Menus and Rhylib.Menus.Kit
    if not K then return end
    local me = LocalPlayer()
    local m = K.Menu()
    m:AddOption("Myself", function() done("^") end)
    if cmd.mass then m:AddOption("Everyone", function() done("*") end) end
    local list = player.GetAll()
    table.sort(list, function(a, b) return string.lower(a:Nick()) < string.lower(b:Nick()) end)
    local any = false
    for _, p in ipairs(list) do
        if p ~= me and Admin.CanTarget(me, p) then
            any = true
            m:AddOption(p:Nick(), function() if IsValid(p) then done(Admin.TargetWord(p)) end end)
        end
    end
    if not any and cmd.target ~= "self" then m:AddOption("(nobody you can pick)", function() end) end
    m:Open()
    track(m)
end

-- Asks for each argument in turn from index `from` (default 1); done(words).
-- A kind with choices opens a menu, "map" opens the map picker, anything
-- else a text prompt. done gets only the words asked for (no target).
-- Example: Rhylib.Admin.AskArgs(Rhylib.Admin.byId.kick, function(w)
--     Rhylib.Admin.Run("kick", { Rhylib.Admin.TargetWord(ply), w[1] }) end)
function Admin.AskArgs(cmd, done, from)
    local K = Rhylib.Menus and Rhylib.Menus.Kit
    local words = {}
    local function step(i)
        local a = cmd.args[i]
        if not a then done(words) return end
        local function took(w)
            words[#words + 1] = w
            step(i + 1)
        end
        local function typed()
            if not K then return end
            track(K.Prompt(cmd.name, a[2] .. (HINT[a[3]] and HINT[a[3]] ~= "" and (" (" .. HINT[a[3]] .. ")") or ""), "", took))
        end
        if a[3] == "map" then
            track(Admin.MapPicker(took))
            return
        end
        local list = choices(a[3])
        if list and K then
            local m = K.Menu()
            for _, c in ipairs(list) do
                m:AddOption(c[2], function()
                    if c[1] == "?" then typed() return end
                    took(c[1])
                end)
            end
            m:Open()
            track(m)
        else
            typed()
        end
    end
    step(from or 1)
end

-- The server: a chat command was missing its player (from 0) or arguments.
Rhylib.Net.Receive("admin.ask", function()
    local cmd = Admin.byId[net.ReadString()]
    local from = net.ReadUInt(4)
    local given = {}
    for k = 1, net.ReadUInt(4) do given[k] = net.ReadString() end
    if not cmd then return end
    local function finish(rest)
        for _, w in ipairs(rest) do given[#given + 1] = w end
        Admin.Run(cmd.id, given)
    end
    if from == 0 then
        Admin.PickPlayer(cmd, function(word)
            given = { word }
            Admin.AskArgs(cmd, finish, 1)
        end)
    else
        Admin.AskArgs(cmd, finish, from)
    end
end)

-- Sounds and decals for everyone (admin.client: 0 play, 1 stop, 2 decals).
Rhylib.Net.Receive("admin.client", function()
    local kind = net.ReadUInt(2)
    local text = net.ReadString()
    if kind == 0 then
        surface.PlaySound(text)
    elseif kind == 1 then
        RunConsoleCommand("stopsound")
    elseif kind == 2 then
        RunConsoleCommand("r_cleardecals")
        game.RemoveRagdolls()
    end
end)

-- Admin.RequestList(which, arg, cb): asks the server for a list (0 maps,
-- 1 bans, 2 log, 3 warnings of SteamID64 arg); cb(rows) gets a list of
-- string lists (see admin.listget in sv_10_admin.lua). One callback per
-- list kind: a newer request replaces the older callback. No reply if you
-- lack the permission.
-- Example: Rhylib.Admin.RequestList(2, "", function(rows) PrintTable(rows) end)
Admin.listCb = Admin.listCb or {}
function Admin.RequestList(which, arg, cb)
    Admin.listCb[which] = cb
    Rhylib.Net.Start("admin.listget")
    net.WriteUInt(which, 2)
    net.WriteString(arg or "")
    net.SendToServer()
end

Rhylib.Net.Receive("admin.list", function()
    local which = net.ReadUInt(2)
    local rows = {}
    for i = 1, net.ReadUInt(8) do
        local r = {}
        for k = 1, net.ReadUInt(3) do r[k] = net.ReadString() end
        rows[i] = r
    end
    local cb = Admin.listCb[which]
    if cb then cb(rows) end
end)

-- Cloak (2026-10-07, owner: others saw the cloaked admin's gun floating):
-- Rhylib weapons skip drawing for a cloaked owner (DrawWorldModel); any
-- other weapon in a cloaked player's hands is hidden on this client here
-- (re-applied, since the server's effect flags overwrite it on a switch).
local hiddenWeps = {}
timer.Create("Rhylib.Admin.CloakWeapons", 0.1, 0, function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local now = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and p:GetNW2Bool("rhylib_cloak") and not p:IsDormant() then
            local w = p:GetActiveWeapon()
            if IsValid(w) then
                now[w] = p
                w:SetNoDraw(true)
            end
        end
    end
    -- Cloak over (or switched away): show it again if it's still in hand.
    for w, p in pairs(hiddenWeps) do
        if not now[w] and IsValid(w) and IsValid(p) and p:GetActiveWeapon() == w then w:SetNoDraw(false) end
    end
    hiddenWeps = now
end)
