--[[
    Battalion computer window, Missions tab (client; sv_90_missions): the
    current mission (run from officers' datapads) and the archive of ended
    ones (officers delete). State in MS; registered with D.TermAddTab.
      dp.mlist -> dp.mlistr   dp.mread -> dp.mfull   dp.mdel
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)

local MS = { missions = nil, missionsAsked = nil, missionSel = nil, missionFull = {} }

local function missionsTab(body)
    local k = T.K()
    local s = k.S
    if not MS.missions then
        T.Label(body, "Loading…")
        if not MS.missionsAsked then
            MS.missionsAsked = true
            T.Send("dp.mlist")
            timer.Simple(5, function() MS.missionsAsked = nil end)
        end
        return
    end
    local left, right = T.Columns(body)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    local cur = MS.missions.current
    if cur then
        local hd = k.Heading(sp, "Current")
        hd:Dock(TOP)
        hd:DockMargin(0, 0, s(8), s(4))
        T.ListRow(sp, cur.title, (cur.active and "Active" or "Posted") .. "  ·  " .. cur.by, function() return MS.missionSel == "cur" end, function()
            MS.missionSel = "cur"
            T.Build()
        end, cur.active and "Live" or "Posted")
    end
    local hd = k.Heading(sp, "Archive (" .. #MS.missions.list .. ")")
    hd:Dock(TOP)
    hd:DockMargin(0, s(4), s(8), s(4))
    if #MS.missions.list == 0 then T.Label(sp, "No finished missions yet.") end
    for _, x in ipairs(MS.missions.list) do
        T.ListRow(sp, x.title, (x.date ~= "" and (x.date .. "  ·  ") or "") .. x.n .. " took part  ·  " .. x.by,
            function() return MS.missionSel == x.id end, function()
                MS.missionSel = x.id
                T.Build()
            end)
    end

    -- Reader.
    if MS.missionSel == "cur" and cur then
        local h = k.Heading(right, cur.title)
        h:Dock(TOP)
        T.Label(right, (cur.date ~= "" and (cur.date .. "  ·  ") or "") .. "by " .. cur.by .. "  ·  " ..
            (cur.active and ("active since " .. T.when(cur.started)) or "not started"), cur.active and k.C.good or k.C.warn)
        local r = k.Scroll(right)
        r:Dock(FILL)
        local function part(title, txt)
            if txt == "" then return end
            local ph = k.Heading(r, title)
            ph:Dock(TOP)
            ph:DockMargin(0, s(6), s(10), s(4))
            local l = k.Label(r, txt, 14, 400, k.C.text)
            l:Dock(TOP)
            l:DockMargin(0, 0, s(10), 0)
        end
        part("Objectives", cur.obj)
        part("Sub objectives", cur.sub)
        part("Info", cur.info)
        if cur.npeople > 0 then part("Taking part (" .. cur.npeople .. ")", table.concat(cur.people, ", ")) end
        T.Label(r, "Officers run it from their datapad (Mission tab).", nil, 12)
        return
    end
    local x
    for _, it in ipairs(MS.missions.list) do
        if it.id == MS.missionSel then x = it end
    end
    if not x then
        T.Label(right, "Pick a mission to read it. Officers post, start and end missions from their datapad; ended ones land here.")
        return
    end
    local h = k.Heading(right, x.title)
    h:Dock(TOP)
    local by = T.Label(right, (x.date ~= "" and (x.date .. "  ·  ") or "") .. "by " .. x.by .. "  ·  " ..
        (x.started > 0 and (T.when(x.started) .. " – ") or "not started – ") .. T.when(x.ended))
    by:DockMargin(0, s(4), 0, s(6))
    if MS.missions.canDelete then
        local foot = T.FootRow(right)
        T.FootButton(foot, "Delete", function()
            T.Send("dp.mdel", function() net.WriteUInt(x.id, 16) end)
            MS.missionSel = nil
        end, { danger = true })
    end
    local full = MS.missionFull[x.id]
    local r = k.Scroll(right)
    r:Dock(FILL)
    if not full then
        T.Label(r, "Loading…")
        if not MS.missionFull["asked" .. x.id] then
            MS.missionFull["asked" .. x.id] = true
            T.Send("dp.mread", function() net.WriteUInt(x.id, 16) end)
        end
        return
    end
    local function part(title, txt)
        if txt == "" then return end
        local ph = k.Heading(r, title)
        ph:Dock(TOP)
        ph:DockMargin(0, s(6), s(10), s(4))
        local l = k.Label(r, txt, 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(10), 0)
    end
    part("Objectives", full.obj)
    part("Sub objectives", full.sub)
    part("Info", full.info)
    part("Took part (" .. #full.people .. ")", #full.people > 0 and table.concat(full.people, ", ") or "nobody")
    if full.endedBy ~= "" then T.Label(r, "Ended by " .. full.endedBy, nil, 12) end
end

Rhylib.Net.Receive("dp.mlistr", function()
    local ent = net.ReadEntity()
    local d = { list = {} }
    d.canDelete = net.ReadBool()
    d.current = D.ReadMission()
    for i = 1, net.ReadUInt(7) do
        d.list[i] = { id = net.ReadUInt(16), title = net.ReadString(), date = net.ReadString(), by = net.ReadString(),
            started = net.ReadUInt(32), ended = net.ReadUInt(32), n = net.ReadUInt(8) }
    end
    MS.missionsAsked = nil
    if not T.term or T.term.ent ~= ent then return end
    MS.missions = d
    if IsValid(T.panel) and T.tab == "missions" then T.Build() end
end)

Rhylib.Net.Receive("dp.mfull", function()
    local id = net.ReadUInt(16)
    local f = { obj = net.ReadString(), sub = net.ReadString(), info = net.ReadString(), endedBy = net.ReadString(), people = {} }
    for i = 1, net.ReadUInt(8) do f.people[i] = net.ReadString() end
    MS.missionFull[id] = f
    if IsValid(T.panel) and T.tab == "missions" and MS.missionSel == id then T.Build() end
end)

D.TermAddTab("missions", {
    order = 40, name = "Missions",
    has = function(tm) return not tm.med end,
    build = missionsTab,
    reset = function() MS.missions, MS.missionsAsked, MS.missionSel, MS.missionFull = nil, nil, nil, {} end,
})
