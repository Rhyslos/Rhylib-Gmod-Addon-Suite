--[[
    Battalion page in the pause menu (also /roster): your character, your
    battalion's members and ranks, and the roster log. Sergeants and up
    (manageRank) promote, demote and remove members below them, add CTs to
    the battalion and pass cadets through basic training. Admins pick any
    battalion.
]]

local R = Rhylib.Roster
local data            -- last roster.data
local adminBn = ""    -- battalion an admin is looking at ("" = their own)

local ACT_TRAIN, ACT_ADD, ACT_RANK, ACT_REMOVE = 0, 1, 2, 3

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end

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

local function build(page)
    local k = K()
    local s = k.S
    local me = R.Get(LocalPlayer())

    if not data then
        local l = k.Label(page, "Loading…", 14, 400, k.C.textDim)
        l:Dock(TOP)
        request()
        return
    end

    -- You.
    local you = vgui.Create("DPanel", page)
    you:Dock(TOP)
    you:SetTall(s(58))
    you:DockMargin(0, 0, 0, s(10))
    function you:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        local name = R.FullName(LocalPlayer()) or LocalPlayer():Nick()
        draw.SimpleText(name, k.Font(18, 700), s(12), h * 0.36, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local line
        if not me.has then line = "No character yet"
        elseif me.bn ~= "" then line = R.RankName(me.rank) .. " in the " .. me.bn
        elseif me.trained then line = "Clone trooper, not in a battalion yet"
        else line = "Cadet: waiting for basic training" end
        draw.SimpleText(line, k.Font(13), s(12), h * 0.72, k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Admins: which battalion to look at.
    if data.admin then
        local row = k.Row(page, "Battalion", "Admins can manage any battalion")
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, s(8))
        row.right:SetWide(s(220))
        local b = k.Button(row.right, (data.bn ~= "" and data.bn or "Pick one") .. " ▾", function()
            local m = k.Menu()
            for _, bn in ipairs(battalions()) do
                m:AddOption(bn, function()
                    adminBn = bn
                    data = nil
                    request()
                end)
            end
            m:Open()
        end, { small = true })
        b:Dock(FILL)
    end

    local sp = k.Scroll(page)
    sp:Dock(FILL)
    local function heading(text)
        local h = k.Heading(sp, text)
        h:Dock(TOP)
        h:DockMargin(0, s(6), s(8), s(4))
    end
    local function note(text)
        local l = k.Label(sp, text, 13, 400, k.C.textDim)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(4))
    end

    -- Members.
    if data.bn == "" then
        note(data.admin and "Pick a battalion above." or "You're not in a battalion. A Sergeant or higher of a battalion can add you once you're a clone trooper.")
    else
        heading(data.bn .. " — " .. #data.members .. " member" .. (#data.members == 1 and "" or "s"))
        local limit = data.limit   -- you can give ranks below this
        local nRanks = #R.Ranks()
        for _, m in ipairs(data.members) do
            local r = k.Row(sp, m.name, R.RankName(m.r) .. "  ·  " .. seenText(m) .. (m.note ~= "" and ("  ·  " .. m.note) or ""))
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(3))
            local canAct = data.manager and m.r < limit and (data.admin or m.id ~= LocalPlayer():SteamID64())
            if canAct then
                -- Manage: a small menu with what you're allowed to do.
                r.right:SetWide(s(120))
                local b = k.Button(r.right, "Manage ▾", function()
                    local menu = k.Menu()
                    local up, down = m.r + 1, m.r - 1
                    local o = menu:AddOption("Promote to " .. R.RankName(up), function() act(ACT_RANK, m.id, up) end)
                    if not (up < limit and up <= nRanks) then o:SetEnabled(false) end
                    o = menu:AddOption("Demote to " .. (down >= 1 and R.RankName(down) or "—"), function() act(ACT_RANK, m.id, down) end)
                    if down < 1 then o:SetEnabled(false) end
                    -- Any rank at once (below yours).
                    local subMenu = menu:AddSubMenu("Set rank")
                    for i = 1, nRanks do
                        if i < limit and i ~= m.r then
                            subMenu:AddOption(R.RankName(i), function() act(ACT_RANK, m.id, i) end)
                        end
                    end
                    menu:AddSpacer()
                    menu:AddOption("Remove from the " .. data.bn, function()
                        Derma_Query("Remove " .. m.name .. " from the " .. data.bn .. "?", "Remove member", "Remove", function() act(ACT_REMOVE, m.id) end, "Cancel")
                    end)
                    menu:Open()
                end, { small = true })
                b:Dock(FILL)
                b:DockMargin(0, s(6), 0, s(6))
            else
                r.right:SetWide(0)
            end
        end
        if #data.members == 0 then note("Nobody yet.") end
    end

    -- Officers: people waiting.
    if data.manager then
        if data.bn ~= "" and #data.cts > 0 then
            heading("Clone troopers to add")
            note("Adding someone from another battalion moves them here as PVT.")
            for _, p in ipairs(data.cts) do
                local r = k.Row(sp, p.name)
                r:Dock(TOP)
                r:DockMargin(0, 0, s(8), s(3))
                r.right:SetWide(s(170))
                local b = k.Button(r.right, "Add to " .. data.bn, function() act(ACT_ADD, p.id) end, { small = true, accent = true })
                b:Dock(FILL)
                b:DockMargin(0, s(6), 0, s(6))
            end
        end
        if #data.cadets > 0 then
            heading("Cadets")
            for _, p in ipairs(data.cadets) do
                local r = k.Row(sp, p.name)
                r:Dock(TOP)
                r:DockMargin(0, 0, s(8), s(3))
                r.right:SetWide(s(190))
                local b = k.Button(r.right, "Pass basic training", function()
                    Derma_Query(p.name .. " passed basic training and becomes a clone trooper?", "Basic training", "Pass", function() act(ACT_TRAIN, p.id) end, "Cancel")
                end, { small = true, accent = true })
                b:Dock(FILL)
                b:DockMargin(0, s(6), 0, s(6))
            end
        end
    end

    -- Log.
    if data.bn ~= "" then
        heading("Roster log")
        if #data.log == 0 then note("Nothing yet.") end
        for _, e in ipairs(data.log) do
            note(os.date("%d %b %H:%M", e.t) .. "   " .. e.txt)
        end
    end
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage) then return end
    Menus.AddPage("roster", {
        title = "Battalion",
        order = 30,
        group = "unit",
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
