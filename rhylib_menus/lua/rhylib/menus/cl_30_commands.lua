--[[
    Commands page (staff). Tabs:
      Players: pick a player, then an action. With rhylib_admin the actions
               are its commands (only those your rank has; arguments are
               asked for) in sections (Admin.SECTIONS.player), else the admin
               mod's own (ULX or SAM).
      Bans / Log (rhylib_admin): current bans (unban) and the admin log.
      Server:  with rhylib_admin a Calls block (presets, timer, message, end,
               what's up now) and its no-target commands in sections
               (Admin.SECTIONS.server); then Rhylib's console tools, which
               check rights themselves.
    Add more with:
        Rhylib.Menus.AddCommand("Server", {
            id = "x", title = "Do X", desc = "...", order = 50,
            run = function() RunConsoleCommand("x") end,
            -- or choices = { { "arg", "Label" }, ... }, run = function(arg) end
        })
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

--------------------------------------------------------------------------
-- Admin mods
--------------------------------------------------------------------------

local MODS = {
    { id = "rhylib", name = "Rhylib Admin",
      detect = function() return Rhylib.Admin ~= nil and Rhylib.Admin.Run ~= nil end },
    { id = "ulx", name = "ULX",
      detect = function() return ulx ~= nil and ULib ~= nil end,
      target = function(p) return "$" .. p:SteamID() end,
      run = function(...) RunConsoleCommand("ulx", ...) end },
    { id = "sam", name = "SAM",
      detect = function() return sam ~= nil end,
      target = function(p) return p:SteamID() end,
      run = function(...) RunConsoleCommand("sam", ...) end },
}

function Menus.AdminMod()
    for _, m in ipairs(MODS) do
        if m.detect() then return m end
    end
end

-- Player actions. verb: the command (same name in ULX and SAM).
-- ask: prompts before running; the answers are added as arguments.
local ACTIONS = {
    { "Go to", "goto" }, { "Bring", "bring" }, { "Return", "return" },
    { "Spectate", "spectate" },
    { "Freeze", "freeze" }, { "Unfreeze", "unfreeze" },
    { "Jail", "jail" }, { "Unjail", "unjail" },
    { "God", "god" }, { "Ungod", "ungod" },
    { "Noclip", "noclip" }, { "Strip weapons", "strip" },
    { "Slay", "slay", danger = true },
    { "Mute chat", "mute" }, { "Unmute chat", "unmute" },
    { "Gag voice", "gag" }, { "Ungag voice", "ungag" },
    { "Kick", "kick", danger = true, ask = { { "Kick", "Reason", "" } } },
    { "Ban", "ban", danger = true, ask = { { "Ban", "Length in minutes (0 = forever)", "60" }, { "Ban", "Reason", "" } } },
}

-- Asks each question in turn, then calls done(answers).
local function askAll(questions, i, answers, done)
    local q = questions[i]
    if not q then done(answers) return end
    K.Prompt(q[1], q[2], q[3], function(text)
        answers[#answers + 1] = text
        askAll(questions, i + 1, answers, done)
    end)
end

local function runAction(mod, act, ply)
    if not IsValid(ply) then return end
    local target = mod.target(ply)
    if act.ask then
        askAll(act.ask, 1, {}, function(answers)
            if not IsValid(ply) then return end
            mod.run(act[2], target, unpack(answers))
        end)
    else
        mod.run(act[2], target)
    end
end
Menus.RunPlayerAction = function(verb, ply)
    local mod = Menus.AdminMod()
    if not mod then return end
    for _, act in ipairs(ACTIONS) do
        if act[2] == verb then runAction(mod, act, ply) return end
    end
end

--------------------------------------------------------------------------
-- Server commands
--------------------------------------------------------------------------

Menus.commands = Menus.commands or {}
function Menus.AddCommand(group, cmd)
    local list = Menus.commands[group]
    if not list then
        list = {}
        Menus.commands[group] = list
    end
    for i, c in ipairs(list) do
        if c.id == cmd.id then list[i] = cmd return end
    end
    list[#list + 1] = cmd
end

Menus.AddCommand("Server", {
    id = "hud.layout", order = 10,
    title = "Default first-person HUD", desc = "For players who haven't picked their own",
    choices = { { "f5", "F5" }, { "f4", "F4" }, { "thirdperson", "3rd person" } },
    current = function() return Rhylib.HUD and Rhylib.HUD.ServerLayout and Rhylib.HUD.ServerLayout() end,
    run = function(arg) RunConsoleCommand("rhylib_hud_layout", arg) end,
})
Menus.AddCommand("Server", {
    id = "armoury.save", order = 20,
    title = "Save armoury placements", desc = "Armouries, cabinets, lockers and crates on this map",
    run = function() RunConsoleCommand("rhylib_armoury_save") end,
})
Menus.AddCommand("Server", {
    id = "crate.refill", order = 30,
    title = "Refill supply crates", desc = "The crate you're looking at, or all of them",
    choices = { { "", "Looked at" }, { "all", "All" } },
    run = function(arg) if arg == "" then RunConsoleCommand("rhylib_crate_refill") else RunConsoleCommand("rhylib_crate_refill", arg) end end,
})
Menus.AddCommand("Server", {
    id = "locker.unclaim", order = 40,
    title = "Unclaim locker", desc = "The locker you're looking at (the owner keeps their items)",
    run = function() RunConsoleCommand("rhylib_locker_unclaim") end,
})
Menus.AddCommand("Server", {
    id = "jetpack.give", order = 50,
    title = "Give yourself a jetpack",
    run = function() RunConsoleCommand("rhylib_jetpack_give") end,
})
Menus.AddCommand("Server", {
    id = "clean.hotbar", order = 60,
    title = "Clean your hotbar", desc = "Remove held weapons that aren't in your inventory",
    run = function() RunConsoleCommand("rhylib_cleanhotbar") end,
})
Menus.AddCommand("Server", {
    id = "status", order = 70,
    title = "Rhylib status / profiler report", desc = "Superadmin; the report prints in the console",
    choices = { { "status", "Status" }, { "report", "Report" }, { "reset", "Reset" } },
    run = function(arg)
        if arg == "status" then RunConsoleCommand("rhylib_status")
        elseif arg == "report" then RunConsoleCommand("rhylib_profile_report")
        else RunConsoleCommand("rhylib_profile_reset") end
    end,
})

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function isStaff()
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    if Rhylib.Admin and Rhylib.Admin.Level then return Rhylib.Admin.Level(ply) > 0 end
    if ply:IsAdmin() then return true end
    if ULib and ULib.ucl and ULib.ucl.query then return ULib.ucl.query(ply, "ulx kick") and true or false end
    if sam and ply.HasPermission then return ply:HasPermission("kick") and true or false end
    return false
end
Menus.IsStaff = isStaff

local function buildPlayers(parent)
    local s = K.S
    local mod = Menus.AdminMod()
    local box = vgui.Create("DPanel", parent)
    box.Paint = nil

    local left = vgui.Create("DPanel", box)
    left:Dock(LEFT)
    left:SetWide(s(280))
    left.Paint = nil
    local search = K.TextEntry(left, "Search players")
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, s(6))
    local list = K.Scroll(left)
    list:Dock(FILL)

    local right = vgui.Create("DPanel", box)
    right:Dock(FILL)
    right:DockMargin(s(12), 0, 0, 0)
    right:DockPadding(s(12), s(12), s(12), s(12))
    function right:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local p = box.selected
        if not mod then
            draw.SimpleText("No admin mod found (ULX or SAM).", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif not IsValid(p) then
            draw.SimpleText("Pick a player on the left.", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local info = vgui.Create("DPanel", right)
    info:Dock(TOP)
    info:SetTall(s(54))
    function info:Paint(w, h)
        local p = box.selected
        if not IsValid(p) then return end
        draw.SimpleText(p:Nick(), K.Font(18, 700), 0, s(14), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local group = Rhylib.Admin and Rhylib.Admin.Rank and Rhylib.Admin.Rank(p).name or p:GetUserGroup()
        draw.SimpleText(p:SteamID() .. "  ·  " .. group .. "  ·  " .. team.GetName(p:Team()) .. "  ·  " .. p:Ping() .. " ms",
            K.Font(12), 0, s(36), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Actions in sectioned blocks (rhylib_admin: Admin.SECTIONS.player).
    local grid = K.Scroll(right)
    grid:Dock(FILL)
    grid:SetVisible(false)

    local function block(title, buttons)
        if #buttons == 0 then return end
        local h = K.Heading(grid, title)
        h:Dock(TOP)
        h:DockMargin(0, 0, s(8), s(4))
        local lay = vgui.Create("DIconLayout", grid)
        lay:Dock(TOP)
        lay:DockMargin(0, 0, s(8), s(12))
        lay:SetSpaceX(s(6))
        lay:SetSpaceY(s(6))
        if lay.SetStretchHeight then lay:SetStretchHeight(true) end
        for _, def in ipairs(buttons) do
            local b = K.Button(lay, def[1], def[2], { small = true, danger = def.danger })
            b:SetSize(s(150), s(30))
        end
        lay:Layout()
    end

    local function fillGrid()
        grid:Clear()
        if not mod then return end
        local extra = {
            { "Copy SteamID", function() if IsValid(box.selected) then SetClipboardText(box.selected:SteamID()) end end },
            { "Steam profile", function() if IsValid(box.selected) then box.selected:ShowProfile() end end },
        }
        if mod.id == "rhylib" then
            -- rhylib_admin: the commands your rank has for this player, by section.
            local Admin = Rhylib.Admin
            local me = LocalPlayer()
            local sel = box.selected
            local DANGER = { kick = true, ban = true, slay = true, charreset = true }
            local function usable(cmd)
                if not cmd or not cmd.target or (Admin.SECTIONS and Admin.SECTIONS.skip[cmd.id]) then return false end
                local full = Admin.Has(me, cmd.perm)
                local allowed = full or (sel == me and Admin.Has(me, cmd.perm .. ".self"))
                return allowed and IsValid(sel) and (sel == me or Admin.CanTarget(me, sel))
            end
            local function button(cmd)
                return { cmd.name, function()
                    local p = box.selected
                    if not IsValid(p) then return end
                    Admin.AskArgs(cmd, function(words)
                        table.insert(words, 1, Admin.TargetWord(p))
                        Admin.Run(cmd.id, words)
                    end)
                end, danger = DANGER[cmd.id] }
            end
            local placed = {}
            for _, sec in ipairs(Admin.SECTIONS and Admin.SECTIONS.player or {}) do
                local list = {}
                for _, id in ipairs(sec[2]) do
                    local cmd = Admin.byId[id]
                    placed[id] = true
                    if usable(cmd) then list[#list + 1] = button(cmd) end
                end
                block(sec[1], list)
            end
            local other = {}
            for _, cmd in ipairs(Admin.COMMANDS) do
                if not placed[cmd.id] and usable(cmd) then other[#other + 1] = button(cmd) end
            end
            block("Other", other)
            block("Steam", extra)
        else
            local list = {}
            for _, act in ipairs(ACTIONS) do
                list[#list + 1] = { act[1], function() runAction(mod, act, box.selected) end, danger = act.danger }
            end
            block("Actions", list)
            block("Steam", extra)
        end
    end
    fillGrid()

    local function rebuild()
        list:Clear()
        local q = string.lower(search:GetText() or "")
        local players = player.GetAll()
        table.sort(players, function(a, b) return string.lower(a:Nick()) < string.lower(b:Nick()) end)
        for _, p in ipairs(players) do
            if q == "" or string.find(string.lower(p:Nick()), q, 1, true) or string.find(string.lower(p:SteamID()), q, 1, true) then
                local b = vgui.Create("DButton", list)
                b:SetText("")
                b:Dock(TOP)
                b:SetTall(s(34))
                b:DockMargin(0, 0, s(8), s(2))
                local av = vgui.Create("AvatarImage", b)
                av:SetSize(s(26), s(26))
                av:SetPos(s(4), s(4))
                av:SetPlayer(p, 32)
                av:SetMouseInputEnabled(false)
                function b:Paint(w, h)
                    local sel = box.selected == p
                    K.SetCol(sel and C.buttonDown or (self:IsHovered() and C.rowHover or C.row))
                    surface.DrawRect(0, 0, w, h)
                    if not IsValid(p) then return true end
                    K.SetCol(team.GetColor(p:Team()))
                    surface.DrawRect(w - 3, 0, 3, h)
                    draw.SimpleText(K.Fit(p:Nick(), K.Font(13, 500), w - s(46)), K.Font(13, 500), s(38), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    return true
                end
                function b:DoClick()
                    box.selected = p
                    grid:SetVisible(mod ~= nil)
                    if mod and mod.id == "rhylib" then fillGrid() end   -- (depends on who it is)
                end
            end
        end
    end
    search.OnChange = rebuild
    rebuild()
    box.rebuild = rebuild
    return box
end

local function heading(sp, text)
    local h = K.Heading(sp, text)
    h:Dock(TOP)
    h:DockMargin(0, K.S(4), K.S(10), K.S(6))
end

-- Calls (rhylib_admin !call): preset buttons, timer, message, end, and what's up now.
local function callsBlock(sp)
    local Admin = Rhylib.Admin
    local me = LocalPlayer()
    if not (Admin.byId.call and Admin.Has(me, "call")) then return end
    heading(sp, "Calls")
    local s = K.S
    local box = vgui.Create("DPanel", sp)
    box:Dock(TOP)
    box:DockMargin(0, 0, s(10), s(12))
    box:DockPadding(s(12), s(36), s(12), s(10))
    box:SetTall(s(176))
    function box:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local c = Admin.CurrentCall and Admin.CurrentCall()
        local text, col = "No call is up", C.textDim
        if c then
            text = "Up now: " .. c.title .. (c.left and string.format("  ·  %d:%02d left", math.floor(c.left / 60), math.ceil(c.left) % 60) or "")
            col = C.warn
        end
        draw.SimpleText(text, K.Font(14, 700), s(12), s(18), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local timerWord, msg = "d", nil
    local function send(id)
        local text = string.Trim(msg:GetText() or "")
        if id == "custom" and text == "" then
            msg:RequestFocus()
            surface.PlaySound("buttons/button10.wav")
            return
        end
        Admin.Run("call", { id, timerWord, text })
    end

    -- Preset buttons (+ custom), End call on the right.
    local row = vgui.Create("DPanel", box)
    row:Dock(TOP)
    row:SetTall(s(30))
    row.Paint = nil
    local stop = K.Button(row, "End call", function() Admin.Run("endcall", {}) end, { small = true, danger = true })
    stop:Dock(RIGHT)
    stop:SetWide(s(110))
    local list = {}
    for _, p in ipairs(Admin.Cfg("calls") or {}) do list[#list + 1] = { p.id, p.name or p.id, tonumber(p.minutes) or 0 } end
    list[#list + 1] = { "custom", "Custom (message as title)", 0 }
    for _, p in ipairs(list) do
        local label = p[2] .. (p[3] > 0 and (" · " .. p[3] .. " min") or "")
        local b = K.Button(row, label, function() send(p[1]) end, { small = true, accent = p[1] ~= "custom" })
        b:Dock(LEFT)
        b:DockMargin(0, 0, s(6), 0)
        surface.SetFont(K.Font(12, 700))
        b:SetWide(surface.GetTextSize(string.upper(label)) + s(30))
    end

    -- Timer.
    local trow = vgui.Create("DPanel", box)
    trow:Dock(TOP)
    trow:SetTall(s(30))
    trow:DockMargin(0, s(10), 0, 0)
    function trow:Paint(w, h)
        draw.SimpleText("Timer", K.Font(13, 500), 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local opts = { { "d", "Preset" }, { "0", "None" }, { "5", "5 min" }, { "10", "10 min" }, { "15", "15 min" }, { "20", "20 min" }, { "30", "30 min" } }
    local ch = K.Choices(trow, opts, function() return timerWord end, function(v) timerWord = v end)
    ch:Dock(FILL)
    ch:DockMargin(s(80), 0, 0, 0)

    -- Message.
    local mrow = vgui.Create("DPanel", box)
    mrow:Dock(TOP)
    mrow:SetTall(s(30))
    mrow:DockMargin(0, s(10), 0, 0)
    function mrow:Paint(w, h)
        draw.SimpleText("Message", K.Font(13, 500), 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    msg = K.TextEntry(mrow, "Optional: replaces the subtitle (the title for Custom)")
    msg:Dock(FILL)
    msg:DockMargin(s(80), 0, 0, 0)
end

-- rhylib_admin's server commands (only those your rank has), by section.
local function adminRows(sp)
    local Admin = Rhylib.Admin
    if not (Admin and Admin.Run) then return end
    callsBlock(sp)
    local me = LocalPlayer()
    local function usable(cmd)
        return cmd and (not cmd.target or cmd.target == "opt") and not (Admin.SECTIONS and Admin.SECTIONS.skip[cmd.id])
            and Admin.Has(me, cmd.perm)
    end
    local function row(cmd)
        local r = K.Row(sp, cmd.name, cmd.desc)
        r:Dock(TOP)
        r:DockMargin(0, 0, K.S(10), K.S(4))
        local b = K.Button(r.right, "Run", function()
            Admin.AskArgs(cmd, function(words)
                if cmd.target == "opt" then words = {} end   -- (no target: everyone's)
                Admin.Run(cmd.id, words)
            end)
        end, { small = true, accent = true })
        b:Dock(RIGHT)
        b:SetWide(K.S(90))
    end
    local placed = {}
    for _, sec in ipairs(Admin.SECTIONS and Admin.SECTIONS.server or {}) do
        local list = {}
        for _, id in ipairs(sec[2]) do
            placed[id] = true
            if usable(Admin.byId[id]) then list[#list + 1] = Admin.byId[id] end
        end
        if #list > 0 then
            heading(sp, sec[1])
            for _, cmd in ipairs(list) do row(cmd) end
        end
    end
    local other = {}
    for _, cmd in ipairs(Admin.COMMANDS) do
        if not placed[cmd.id] and usable(cmd) then other[#other + 1] = cmd end
    end
    if #other > 0 then
        heading(sp, "Other")
        for _, cmd in ipairs(other) do row(cmd) end
    end
end

-- A list from rhylib_admin (bans or the log) with an optional action per row.
local function buildList(parent, which, columns, action)
    local Admin = Rhylib.Admin
    local sp = K.Scroll(parent)
    sp:Dock(FILL)
    local function load()
        sp:Clear()
        Admin.RequestList(which, "", function(rows)
            if not IsValid(sp) then return end
            sp:Clear()
            if #rows == 0 then
                local l = K.Label(sp, which == 1 and "Nobody is banned." or "Nothing logged yet.", 14)
                l:Dock(TOP)
                return
            end
            for _, r in ipairs(rows) do
                local title, desc = columns(r)
                local row = K.Row(sp, title, desc)
                row:Dock(TOP)
                row:DockMargin(0, 0, K.S(10), K.S(4))
                if action then
                    local b = K.Button(row.right, action[1], function() action[2](r) timer.Simple(0.5, load) end, { small = true, danger = action.danger })
                    b:Dock(RIGHT)
                    b:SetWide(K.S(90))
                end
            end
        end)
    end
    load()
    return sp
end

-- Rows straight into a scroll panel.
local function buildServer(sp)
    adminRows(sp)
    local groups = {}
    for g in pairs(Menus.commands) do groups[#groups + 1] = g end
    table.sort(groups)
    for _, g in ipairs(groups) do
        heading(sp, g == "Server" and "Rhylib tools" or g)
        local list = table.Copy(Menus.commands[g])
        table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
        for _, cmd in ipairs(list) do
            local row = K.Row(sp, cmd.title, cmd.desc)
            row:Dock(TOP)
            row:DockMargin(0, 0, K.S(10), K.S(4))
            if cmd.choices then
                row.right:SetWide(K.S(420))
                local cur = cmd.current or function() return nil end
                local c = K.Choices(row.right, cmd.choices, function() return cur() end, function(v) cmd.run(v) end)
                c:Dock(FILL)
            else
                local b = K.Button(row.right, "Run", function() cmd.run() end, { small = true, accent = true })
                b:Dock(RIGHT)
                b:SetWide(K.S(90))
            end
        end
    end
end

Menus.AddPage("commands", {
    title = "Commands",
    order = 50,
    group = "staff",
    visible = isStaff,
    build = function(page)
        local mod = Menus.AdminMod()
        Menus.pages.commands.sub = mod and ("Admin mod: " .. mod.name) or "No admin mod found"

        local tabs = vgui.Create("DPanel", page)
        tabs:Dock(TOP)
        tabs:SetTall(K.S(30))
        tabs:DockMargin(0, 0, 0, K.S(10))
        tabs.Paint = nil
        local body = vgui.Create("DPanel", page)
        body:Dock(FILL)
        body.Paint = nil

        local current
        local Admin = Rhylib.Admin
        local function show(which)
            current = which
            body:Clear()
            if which == "players" then
                buildPlayers(body):Dock(FILL)
            elseif which == "bans" then
                buildList(body, 1, function(r) return r[2] .. "  ·  " .. r[1], r[3] .. "  ·  by " .. r[4] .. "  ·  " .. r[5] end,
                    { "Unban", function(r) Admin.Run("unban", { r[1] }) end, danger = false })
            elseif which == "log" then
                buildList(body, 2, function(r) return r[2], os.date("%d %b %H:%M", tonumber(r[1]) or 0) end)
            else
                local sp = K.Scroll(body)
                sp:Dock(FILL)
                buildServer(sp)
            end
        end
        local tabList = { { "players", "Players" } }
        if mod and mod.id == "rhylib" then
            local me = LocalPlayer()
            if Admin.Has(me, "bans") or Admin.Has(me, "ban") then tabList[#tabList + 1] = { "bans", "Bans" } end
            if Admin.Has(me, "logs") then tabList[#tabList + 1] = { "log", "Log" } end
        end
        tabList[#tabList + 1] = { "server", "Server" }
        for _, t in ipairs(tabList) do
            local b = K.Button(tabs, t[2], function() show(t[1]) end, { small = true, selected = function() return current == t[1] end })
            b:Dock(LEFT)
            b:SetWide(K.S(140))
            b:DockMargin(0, 0, K.S(6), 0)
        end
        show("players")
    end,
})
