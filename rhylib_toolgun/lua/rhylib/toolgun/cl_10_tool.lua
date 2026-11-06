--[[
    Toolgun (client): what's chosen (client convars), its tab in the spawn
    window and the R key, the HUD line and the aim marker.

    Client convars: rhylib_tool_entry (chosen id, "@custom" = a spawn-window
    thing), rhylib_tool_count (1-5), rhylib_tool_name (beacon/spawn point
    name), rhylib_tool_droidmode (1-5), rhylib_tool_custom
    (kind|name|skin|body|weapon|label), rhylib_tool_squadaggro (0-5:
    aggression of newly placed squads, 0 = global), rhylib_tool_alertness
    (0-2: alertness of placed droids, 0 = the server default, 1 alert,
    2 unaware = stealth), rhylib_tool_physgun_key (default
    t: physgun mode on / off, cl_30_grab.lua), Settings > Weapons;
    rhylib_tool_info (strip / panel: where the toolgun info goes).
    Console: rhylib_toolgun.
    The spawn window and its tab need rhylib_menus; without it R prints a
    note and rhylib_tool_entry <id> picks an entry. The droid mode and
    aggression row needs rhylib_droids.
    R: a tap opens the window (stays open), held 0.3 s+ closes on release,
    a tap while open closes, two taps within 0.35 s open the old Q menu.
    In Command mode (cl_20_command.lua) R held is the order wheel instead.
    With a droid entry: the info shows PLACES AS <mode> in its colour
    (GUARD, PATROL, ATTACK, ROAM, ASSAULT: to the side's assault point);
    Shift + wheel changes the mode, Alt + wheel the new squad's aggression,
    Shift + Alt + wheel the alertness (Default / Alert / Unaware); the
    spawn window's "Alertness" row sets it too.
    Droid labels add the squad number (S12), its own aggression (A4) and
    its stealth state (UNAWARE, SUSPICIOUS, SEARCHING, ALARM).
    The droid spawner also shows in the spawn window's NPCs tab ("Rhy's
    Droid spawner") and its Entities tile picks it for the toolgun; on all
    three, right-click > Change spawner settings (menus hook
    Rhylib.SpawnTabItems).
    Look: the Rhy's tab's placing controls are one plate under the tiles,
    a row each with a caps caption (New droids: the five modes in their
    colours; Aggression 1-5; Alertness, Unaware in blue; full access
    only: X-ray (on, players, NPCs, spawned things, bombs / mines /
    objectives, range 40 / 80 / 150 m) and Staff view (night vision,
    names, minimal HUD), bound to cl_30_staffview's convars, read when
    clicked or painted; Toolgun info (Bottom strip / Side panel); Droids
    at once, Beacon name, Re-save). With many rows they get shorter.
    Toolgun info (Tool.DrawInfo, also used by Command mode and physgun
    mode): "strip" (default) is one sectioned bar near the bottom centre
    (a caps label and a value per section, the keys last), kept above
    the Simple HUD's hotbar and the visor cheeks; "panel" is a panel on
    the right edge, vertically centred (header, name, label / value
    grid, key caps), kept left of the Realistic HUD's side ladder. Near
    the crosshair only a small tag (Tool.DrawTag): the short name with a
    square in the mode colour, and "RMB: remove <name>" in red while
    aiming at something removable. The info is rebuilt only when what
    it shows changes. Colours are theme tokens "toolgun.*"
    (cl_11_theme.lua).
]]

local Tool = Rhylib.Tool
local UI = Rhylib.UI

-- Theme tokens (cl_11_theme.lua). COL: the toolgun's hint yellow (HUD
-- line, aim ring, chat prefix). MODE_COLS: placing modes (PLACES AS, the
-- New droids buttons, droid labels).
local COL = UI.Col("toolgun.hint", 255, 210, 80)
local COL_UNAWARE = UI.Col("toolgun.unaware", 133, 183, 235)
local COL_PERMA = UI.Col("toolgun.perma", 255, 150, 40)
local COL_AIM = UI.Col("toolgun.aim", 110, 200, 255)
local PICKED = UI.Col("toolgun.picked", 255, 255, 120)
local MODE_COL = {
    guard = UI.Col("toolgun.modeGuard", 110, 170, 255), patrol = UI.Col("toolgun.modePatrol", 120, 230, 140),
    attack = UI.Col("toolgun.modeAttack", 255, 100, 80), roam = UI.Col("toolgun.modeRoam", 200, 140, 255),
    assault = UI.Col("toolgun.modeAssault", 255, 60, 40), follow = UI.Col("toolgun.modeFollow", 240, 220, 120),
    retreat = UI.Col("toolgun.modeRetreat", 255, 170, 60), laststand = UI.Col("toolgun.modeLastStand", 255, 60, 60),
}
local MODE_COLS = { MODE_COL.guard, MODE_COL.patrol, MODE_COL.attack, MODE_COL.roam, MODE_COL.assault }

local cvEntry = CreateClientConVar("rhylib_tool_entry", "b1", true, false, "Toolgun: chosen entry id")
local cvCount = CreateClientConVar("rhylib_tool_count", "1", true, false, "Toolgun: how many droids at once (1-5)")
local cvName = CreateClientConVar("rhylib_tool_name", "Range", true, false, "Toolgun: name for new training beacons")

local cvMode = CreateClientConVar("rhylib_tool_droidmode", "1", true, false, "Toolgun: mode for placed droids (1 guard, 2 patrol, 3 attack, 4 roam, 5 assault: to the assault point set in Command mode)")
local cvAggro = CreateClientConVar("rhylib_tool_squadaggro", "0", true, false, "Toolgun: aggression for newly placed squads (0 = the global level, 1-5)")
local cvAlert = CreateClientConVar("rhylib_tool_alertness", "0", true, false, "Toolgun: alertness of placed droids (0 = the server default, 1 alert, 2 unaware: stealth)")
local ALERT_NAMES = { [0] = "Default", "Alert", "Unaware" }
local cvPhysKey = CreateClientConVar("rhylib_tool_physgun_key", "t", true, false, "Toolgun: key that switches physgun mode on and off")
local cvCustom = CreateClientConVar("rhylib_tool_custom", "", true, false, "Toolgun: picked spawn-window thing (kind|name|skin|body|weapon|label)")
local cvInfo = CreateClientConVar("rhylib_tool_info", "strip", true, false, "Toolgun: where its info goes (strip: a bar near the bottom, panel: a panel on the right)")
-- The droid spawner's settings for the next one placed (right-click its tile: "Change spawner settings").
local cvSpPreset = CreateClientConVar("rhylib_tool_sp_preset", "droid_small", true, false, "Toolgun: droid spawner preset squad")
local cvSpMode = CreateClientConVar("rhylib_tool_sp_mode", "patrol", true, false, "Toolgun: droid spawner orders (patrol, roam, attack, guard)")
local cvSpTotal = CreateClientConVar("rhylib_tool_sp_total", "60", true, false, "Toolgun: droid spawner droids in all")
local cvSpCap = CreateClientConVar("rhylib_tool_sp_cap", "20", true, false, "Toolgun: droid spawner alive at once")
local cvSpInterval = CreateClientConVar("rhylib_tool_sp_interval", "30", true, false, "Toolgun: droid spawner seconds between squads")
local SP_MODES = { patrol = 1, roam = 2, attack = 3, guard = 4 }

-- The droid spawner settings window for the next ones placed
-- (rhylib_droids D.Spawner.Window).
local function spawnerSettings()
    local D = Rhylib.Droids
    if not (D and D.Spawner and D.Spawner.Window) then return end
    local st = { preset = cvSpPreset:GetString(), mode = cvSpMode:GetString(), total = cvSpTotal:GetInt(),
        cap = cvSpCap:GetInt(), interval = cvSpInterval:GetInt() }   -- (no Running row: placed ones always run)
    D.Spawner.Window(st, nil, "Droid spawner: new ones", "What the next droid spawners you place send out", function(v)
        RunConsoleCommand("rhylib_tool_sp_preset", v.preset)
        RunConsoleCommand("rhylib_tool_sp_mode", v.mode)
        RunConsoleCommand("rhylib_tool_sp_total", tostring(v.total))
        RunConsoleCommand("rhylib_tool_sp_cap", tostring(v.cap))
        RunConsoleCommand("rhylib_tool_sp_interval", tostring(v.interval))
    end)
end

-- Pick a toolgun entry (and get the toolgun out).
local function pickEntry(id)
    RunConsoleCommand("rhylib_tool_entry", id)
    local me = LocalPlayer()
    local w = me:GetActiveWeapon()
    local tg = me:GetWeapon("rhylib_toolgun")
    if IsValid(tg) and w ~= tg then input.SelectWeapon(tg) end
end

-- The droid spawner in the spawn window's NPCs tab (its own "Rhy's Droid
-- spawner" category) and on its Entities tab tile: click picks it for the
-- toolgun, right-click has Change spawner settings (menus hook
-- Rhylib.SpawnTabItems).
local SPAWNER_TIP = "Click: pick it for the toolgun, then LMB places one facing you.\nRight-click: Change spawner settings (its squad, orders, numbers, timing)"
Rhylib.Hook.Add("Rhylib.SpawnTabItems", "toolgun.spawner", function(tabId, items)
    local e
    for _, x in ipairs(Tool.Entries()) do if x.spawner then e = x break end end
    if not (e and Tool.CanEntry(LocalPlayer(), e)) then return end
    local function menu(m) m:AddOption("Change spawner settings", spawnerSettings) end
    if tabId == "entities" then
        for _, it in ipairs(items) do
            if it.extra == e.class then
                it.tip, it.run = SPAWNER_TIP, function() pickEntry(e.id) end
                local old = it.menu
                it.menu = function(m) menu(m) if old then old(m) end end
            end
        end
    elseif tabId == "npcs" then
        items[#items + 1] = { cat = "Rhy's Droid spawner", name = e.name, extra = e.class, admin = true, tip = SPAWNER_TIP,
            model = Tool.EntryModel(e), run = function() pickEntry(e.id) end, menu = menu,
            selected = function() return cvEntry:GetString() == e.id end }
    end
end)

-- Spawn-window things picked with "Spawn with Rhy's toolgun": entry id
-- "@custom", the thing itself in rhylib_tool_custom.
Tool.KINDS = { prop = 1, entity = 2, npc = 3, vehicle = 4, weapon = 5 }
local customCache = {}
local function customEntry()
    local raw = cvCustom:GetString()
    if customCache.raw == raw then return customCache.e end
    local p = string.Explode("|", raw)
    local e
    if Tool.KINDS[p[1] or ""] and (p[2] or "") ~= "" then
        e = { id = "@custom", custom = { kind = p[1], name = p[2], skin = tonumber(p[3]) or 0, body = p[4] or "", wep = p[5] or "" },
            name = (p[6] ~= nil and p[6] ~= "") and p[6] or p[2] }
    end
    customCache.raw, customCache.e = raw, e
    return e
end

-- Tool.Chosen(): the entry LMB uses now (only ones this player may use;
-- never falls back to the Permanent tool).
local chosenFrame, chosenId, chosenVal = -1, nil, nil
local function chosen()
    local id = cvEntry:GetString()
    if id == "@custom" and Tool.FullAccess(LocalPlayer()) then
        local c = customEntry()
        if c then return c end
    end
    local list = {}
    local me = LocalPlayer()
    for _, e in ipairs(Tool.Entries()) do
        if Tool.CanEntry(me, e) then list[#list + 1] = e end   -- (gamemasters: only their entries)
    end
    for _, e in ipairs(list) do
        if e.id == id then return e end
    end
    for _, e in ipairs(list) do   -- (never fall back to the Permanent tool)
        if not e.perma then return e end
    end
    return list[1]
end
-- (worked out once a frame: the HUD, outlines and aim ring all ask)
function Tool.Chosen()
    local f, id = FrameNumber(), cvEntry:GetString()
    if f ~= chosenFrame or id ~= chosenId then
        chosenFrame, chosenId, chosenVal = f, id, chosen()
    end
    return chosenVal
end

-- X-ray and Staff view convars: cl_30_staffview.lua makes them and loads
-- after this file, so they're looked up when a button is clicked or
-- painted (nil until then).
local svCv = {}
local function svVar(name)
    local c = svCv[name]
    if not c then
        c = GetConVar(name)
        if c then svCv[name] = c end
    end
    return c
end
local function svSet(name, v)
    if not svVar(name) then
        Rhylib.Notify(nil, "Staff view isn't available", "bad", "Toolgun")
        return
    end
    RunConsoleCommand(name, v)
end
-- A spawn-window toggle button for one of them.
local function svToggle(text, name, tip, weight)
    return { text, function()
        local c = svVar(name)
        svSet(name, (c and c:GetBool()) and "0" or "1")
    end, { selected = function() local c = svVar(name) return c and c:GetBool() or false end, tooltip = tip, weight = weight } }
end

-- The "Rhy's" tab of the spawn window (rhylib_menus cl_85_spawn.lua):
-- our placements as tiles by category, plus count, beacon name and save.
local function buildTab(body)
    local M = Rhylib.Menus
    local K, SP = M.Kit, M.Spawn
    local S = K.S
    local C = K.C

    -- The placing controls: one plate at the bottom, a row each
    -- (caps caption on the left, buttons sharing the width).
    local ctl = vgui.Create("DPanel", body)
    ctl:Dock(BOTTOM)
    ctl:DockMargin(0, S(8), 0, 0)
    ctl:DockPadding(1, S(2), 1, S(2))
    function ctl:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        K.Ticks(0, 0, w, h)
    end
    local full = Tool.FullAccess(LocalPlayer())
    -- (rows: droid rows 3, X-ray and Staff view / Toolgun info 2 or
    -- Toolgun info 1, Droids at once 1; more than 4 get shorter so the
    -- tiles keep their room on 4:3)
    local want = (Rhylib.Droids and full and 3 or 0) + (full and 2 or 1) + 1
    local rowH = want > 4 and S(34) or S(40)
    local rowPad = want > 4 and S(4) or S(6)
    local rows = 0
    local function ctlRow(caption, sub)
        rows = rows + 1
        local first = rows == 1
        local cap = string.upper(caption)
        local r = vgui.Create("DPanel", ctl)
        r:Dock(TOP)
        r:SetTall(rowH)
        r:DockPadding(S(176), rowPad, S(10), rowPad)
        function r:Paint(w, h)
            if not first then
                K.SetCol(C.edgeDark)
                surface.DrawRect(S(8), 0, w - S(16), 1)
            end
            draw.SimpleText(cap, K.Font(12, 700), S(14), sub and h * 0.36 or h * 0.5, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if sub then draw.SimpleText(K.Fit(sub, K.Font(11), S(156)), K.Font(11), S(14), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
        return r
    end
    -- Buttons sharing a panel's width (evenly, or by opts.weight);
    -- list = { { text, fn, opts }, ... }.
    local function seg(parent, list, dock, wide)
        local p = vgui.Create("DPanel", parent)
        p.Paint = nil
        p:Dock(dock or FILL)
        if wide then p:SetWide(wide) end
        local total = 0
        for _, b in ipairs(list) do
            local o = b[3] or {}
            o.small = true
            local btn = K.Button(p, b[1], b[2], o)
            btn.segWeight = o.weight or 1
            total = total + btn.segWeight
        end
        function p:PerformLayout(w, h)
            local kids = self:GetChildren()
            local gap = S(5)
            local unit = (w - gap * (#kids - 1)) / math.max(1, total)
            local x = 0
            for _, c in ipairs(kids) do
                local bw = unit * (c.segWeight or 1)
                c:SetPos(math.floor(x), math.floor((h - c:GetTall()) * 0.5))
                c:SetWide(math.floor(bw))
                x = x + bw + gap
            end
        end
        return p
    end
    -- A caps caption inside a row (left of a control).
    local function capLabel(parent, text, wide)
        local caps = string.upper(text)
        local l = vgui.Create("DPanel", parent)
        l:Dock(LEFT)
        l:SetWide(wide)
        function l:Paint(w, h) draw.SimpleText(caps, K.Font(12, 700), w - S(10), h * 0.5, C.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        return l
    end

    -- (only with rhylib_droids: its buttons send droid messages)
    if Rhylib.Droids and Tool.FullAccess(LocalPlayer()) then
        -- The mode placed droids get.
        local list = {}
        for i, m in ipairs({ "Guard", "Patrol", "Attack", "Roam", "Assault" }) do
            list[i] = { m, function() RunConsoleCommand("rhylib_tool_droidmode", tostring(i)) end,
                { col = MODE_COLS[i], selected = function() return cvMode:GetInt() == i end,
                  tooltip = i == 4 and "Placed NPCs roam the map in twos (spread out)"
                      or i == 5 and "Placed NPCs attack the assault point (Command mode: Assault here), only them"
                      or "Mode of the droids you place (markers you placed earlier still win)" } }
        end
        seg(ctlRow("New droids", "Places as · Shift + wheel"), list)

        -- The live aggression of every droid.
        local AGGRO = (Rhylib.Droids and Rhylib.Droids.AGGRO_NAMES) or { "Retreat", "Fall back", "Moderate", "March", "Charge" }
        list = {}
        for i = 1, 5 do
            list[i] = { i .. " " .. AGGRO[i], function()
                Rhylib.Net.Start("droids.aggro")
                net.WriteUInt(i, 3)
                net.SendToServer()
            end, { selected = function() return GetGlobal2Int("rhylib_droidAggro", 3) == i end,
                   tooltip = "Every droid at once, live: 1 retreats (gets away, last stand if cornered), 2 falls back to the fallback marker / its post ... 5 charges" } }
        end
        seg(ctlRow("Aggression", "Every droid, live"), list)

        -- The alertness placed droids get (stealth).
        local TIPS = { [0] = "The server's default (Server settings > Droids & clones > Stealth)",
            "Alert: sees you at once, all round (as always; for battles)",
            "Unaware: stealth. Has to notice you first; suspicious before it fights; radios before help comes" }
        list = {}
        for i = 0, 2 do
            list[i + 1] = { i == 2 and "Unaware (stealth)" or ALERT_NAMES[i], function() RunConsoleCommand("rhylib_tool_alertness", tostring(i)) end,
                { col = i == 2 and COL_UNAWARE or nil, selected = function() return cvAlert:GetInt() == i end, tooltip = TIPS[i] } }
        end
        local r3 = ctlRow("Alertness", "Droids you place · Shift + Alt + wheel")
        seg(r3, list, LEFT, S(420))
        local note = vgui.Create("DPanel", r3)
        note:Dock(FILL)
        note:DockMargin(S(12), 0, 0, 0)
        local NOTE = "Droids only (clones always see you). Command mode's order wheel changes placed ones."
        function note:Paint(w, h)
            local f = K.Font(12, 500)
            draw.SimpleText(K.Fit(NOTE, f, w), f, 0, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Where the toolgun info goes (everyone with the toolgun).
    local infoList = {
        { "Bottom strip", function() RunConsoleCommand("rhylib_tool_info", "strip") end,
          { selected = function() return Tool.InfoLayout() == "strip" end, tooltip = "One bar near the bottom of the screen; the middle of the screen stays clear" } },
        { "Side panel", function() RunConsoleCommand("rhylib_tool_info", "panel") end,
          { selected = function() return Tool.InfoLayout() == "panel" end, tooltip = "A panel on the right edge; the middle of the screen stays clear" } },
    }
    if full then
        -- X-ray and Staff view (cl_30_staffview.lua's convars).
        local xr = ctlRow("X-ray", "Through walls, toolgun out")
        local ranges = {}
        for i, m in ipairs({ 40, 80, 150 }) do
            ranges[i] = { m .. " m", function() svSet("rhylib_tool_xray_range", tostring(m)) end,
                { selected = function() local c = svVar("rhylib_tool_xray_range") return c and c:GetInt() == m or false end,
                  tooltip = "How far X-ray reaches (" .. m .. " m)" } }
        end
        seg(xr, ranges, RIGHT, S(220))
        local tg = seg(xr, {
            svToggle("On", "rhylib_tool_xray", "X-ray on / off (also !xray)", 0.8),
            svToggle("Players", "rhylib_tool_xray_players", "Players through walls", 1.1),
            svToggle("NPCs", "rhylib_tool_xray_npcs", "Droids and clones through walls", 0.9),
            svToggle("Spawned things", "rhylib_tool_xray_spawned", "Things placed with the toolgun or the spawn window", 1.6),
            svToggle("Bombs, mines, objectives", "rhylib_tool_xray_eod", "Bombs, mines and objective markers through walls", 2.4),
        })
        tg:DockMargin(0, 0, S(12), 0)

        local sv = ctlRow("Staff view", "Toolgun out")
        seg(sv, {
            svToggle("Night vision (F)", "rhylib_tool_nv", "Night vision; F toggles it while you hold the toolgun", 1.5),
            svToggle("Names", "rhylib_tool_names", "Names (staff view, toolgun out)", 1),
            svToggle("Minimal HUD", "rhylib_tool_minhud", "A minimal HUD while you hold the toolgun", 1.3),
        }, LEFT, S(440))
        capLabel(sv, "Toolgun info", S(150))
        seg(sv, infoList)
    else
        local ti = ctlRow("Toolgun info", "Where the placing info goes")
        seg(ti, infoList, LEFT, S(330))
        local tn = vgui.Create("DPanel", ti)
        tn:Dock(FILL)
        tn:DockMargin(S(12), 0, 0, 0)
        local TNOTE = "The middle of the screen stays clear either way."
        function tn:Paint(w, h)
            local f = K.Font(12, 500)
            draw.SimpleText(K.Fit(TNOTE, f, w), f, 0, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Count, beacon name, re-save.
    local bottom = ctlRow("Droids at once", "Entries with a count")
    local counts = {}
    for i, n in ipairs({ 1, 3, 5 }) do
        counts[i] = { tostring(n), function() RunConsoleCommand("rhylib_tool_count", tostring(n)) end,
            { selected = function() return cvCount:GetInt() == n end } }
    end
    seg(bottom, counts, LEFT, S(156))
    capLabel(bottom, "Beacon name", S(130))
    local te = K.TextEntry(bottom, "e.g. Range, Killhouse A")
    te:Dock(LEFT)
    te:SetWide(S(240))
    te:SetValue(cvName:GetString())
    te.OnChange = function(self) RunConsoleCommand("rhylib_tool_name", string.sub(self:GetValue(), 1, 32)) end
    local save = K.Button(bottom, "Re-save permanent things", function()
        Rhylib.Net.Start("tool.save")
        net.SendToServer()
    end, { small = true, tooltip = "Placing doesn't save anything: use the Permanent tool (Staff tools). This saves every permanent thing again where it stands now." })
    save:Dock(RIGHT)
    save:SetWide(S(230))
    if not full then save:SetVisible(false) end
    ctl:SetTall(rows * rowH + S(4))

    local inner = vgui.Create("DPanel", body)
    inner:Dock(FILL)
    inner.Paint = nil
    local tab = SP.CatalogueTab(function()
        local items = {}
        local ents = list.Get("SpawnableEntities") or {}
        local me = LocalPlayer()
        for _, e in ipairs(Tool.Entries()) do
          if Tool.CanEntry(me, e) then
            local sp = e.class and ents[e.class] or {}
            items[#items + 1] = {
                cat = e.cat, name = e.name, extra = e.class or e.id,
                tip = e.perma and "LMB on a thing: keep it on this map for good (or save where it is now); RMB: stop keeping it.\nWhile picked, permanent things have an orange outline, the thing you aim at a light blue one."
                    or e.order and "Click: pick it; LMB sets the mode of every NPC of that side near where you aim"
                    or e.follow and "LMB: pick a clone (or all near the spot); RMB: they follow you, or the player you aim at"
                    or e.preset and "LMB: places the whole squad in a grid facing you (front row where you aim, commander and B2s at the back)"
                    or e.spawner and "LMB: places a droid spawner facing you. Right-click: Change spawner settings (its squad, orders, numbers, timing)"
                    or (e.class .. "\nClick: pick it for the toolgun (LMB places)"),
                mat = SP.IconMat({ sp.IconOverride, "entities/" .. (e.class or e.id) .. ".png" }),
                model = Tool.EntryModel(e),   -- (3D tile picture and hover preview)
                selected = function() return cvEntry:GetString() == e.id end,
                -- (right-click: the droid spawner's settings for the next ones)
                menu = e.spawner and function(m) m:AddOption("Change spawner settings", spawnerSettings) end or nil,
                run = function() pickEntry(e.id) end,   -- (back to the toolgun if something else is out)
            }
          end
        end
        return items
    end, Tool.CAT_ORDER)
    tab.build(inner)
    body.search = inner.search
end

-- Right-click "Spawn with Rhy's toolgun" in the spawn window.
local function pickForTool(spec)
    local clean = function(v) return (string.gsub(tostring(v or ""), "|", "/")) end
    -- (an NPC's weapon is picked per spawn, in Tool.Click)
    local wep = spec.wep or ""
    RunConsoleCommand("rhylib_tool_custom", table.concat({ clean(spec.kind), clean(spec.name), tostring(tonumber(spec.skin) or 0),
        clean(spec.body), clean(wep), string.sub(clean(spec.label or spec.name), 1, 48) }, "|"))
    RunConsoleCommand("rhylib_tool_entry", "@custom")
    local me = LocalPlayer()
    local tg = me:GetWeapon("rhylib_toolgun")
    if IsValid(tg) then
        if me:GetActiveWeapon() ~= tg then input.SelectWeapon(tg) end
        chat.AddText(COL, "[Toolgun] ", color_white, "LMB spawns " .. (spec.label or spec.name) .. " where you aim.")
    else
        chat.AddText(COL, "[Toolgun] ", color_white, "Picked " .. (spec.label or spec.name) .. ". Get the toolgun with !toolgun to spawn it.")
    end
end

local function addTab()
    local M = Rhylib.Menus
    if not (M and M.Spawn and M.Spawn.AddTab) then return end
    M.Spawn.PickForTool = pickForTool
    M.Spawn.AddTab("rhylib", {
        title = "Rhy's", order = 0,
        build = buildTab,
        search = function(body, q) if body.search then body.search(q) end end,
    })
end
addTab()
Rhylib.Hook.Add("InitPostEntity", "toolgun.spawntab", addTab)

-- R with the toolgun out: a tap opens the spawn window (and leaves it
-- open), holding R keeps it open only while held, a second tap closes it,
-- and two quick taps open the old Q menu instead.
local HOLD = 0.3
local DOUBLE = 0.35
local rPress, lastOpen = nil, 0

local function reloadCode()
    local key = input.LookupBinding("+reload")
    local c = key and input.GetKeyCode(key)
    return (c and c > 0) and c or KEY_R
end

local function onR(code)
    local M = Rhylib.Menus
    local SP = M and M.Spawn
    if not SP then
        chat.AddText(COL, "[Toolgun] needs rhylib_menus for the spawn window. rhylib_tool_entry <id> picks one.")
        return
    end
    local now = RealTime()
    if M.SpawnMenuOpen and M.SpawnMenuOpen() then
        M.CloseSpawnMenu()
        return
    end
    if SP.IsOpen() then
        SP.Close()
        rPress = nil
        if now - lastOpen < DOUBLE and M.OpenSpawnMenu then M.OpenSpawnMenu() end
        lastOpen = 0
        return
    end
    SP.Open()
    lastOpen = now
    rPress = { at = now, code = code or reloadCode() }
end

Rhylib.Hook.Add("PlayerBindPress", "toolgun.r", function(ply, bind, pressed, code)
    if not pressed or bind ~= "+reload" then return end
    -- (R turns items in the open inventory)
    local Inv = Rhylib.Inventory
    if Inv and IsValid(Inv.panel) then return end
    local w = ply:GetActiveWeapon()
    local SP = Rhylib.Menus and Rhylib.Menus.Spawn
    -- (also while the window is open with another tool out)
    if not ((IsValid(w) and w.ToolGun) or (SP and SP.IsOpen())) then return end
    -- (physgun mode: R is the game's reload key, used to turn what's held)
    if Tool.PhysOnLocal and Tool.PhysOnLocal() and IsValid(w) and w.ToolGun then return end
    -- (Command mode: R held is the order wheel)
    if Tool.command and Tool.CommandWheel and Rhylib.Droids and IsValid(w) and w.ToolGun then
        Tool.CommandWheel(code or reloadCode())
        return true
    end
    onR(code)
    return true
end, -30)

-- Held past HOLD: letting go closes it again (like holding Q).
Rhylib.Hook.Add("Think", "toolgun.rhold", function()
    if not rPress then return end
    if input.IsButtonDown(rPress.code) then return end
    local held = RealTime() - rPress.at
    rPress = nil
    if held >= HOLD then
        local SP = Rhylib.Menus and Rhylib.Menus.Spawn
        if SP then SP.Close() end
        lastOpen = 0
    end
end)

-- Tool.Click(wep, which): send the click ("1" LMB place/spawn, "2" RMB
-- remove / follow / stop keeping).
function Tool.Click(wep, which)
    if which == "3" then return end   -- (R is read from the key, above)
    if Tool.command and Rhylib.Droids then return end   -- (Command mode reads the mouse itself: cl_20_command)
    if Tool.PhysOnLocal and Tool.PhysOnLocal() then return end   -- (physgun mode: the server reads the buttons, sv_20_grab)
    if which == "2" then
        local f = Tool.Chosen()
        if f and f.perma then
            Rhylib.Net.Start("tool.perma")
            net.WriteBool(false)
            net.SendToServer()
            return
        end
        Rhylib.Net.Start(f and f.follow and "tool.follow" or "tool.remove")
        net.SendToServer()
        return
    end
    local e = Tool.Chosen()
    if not e then return end
    if e.custom then
        local c = e.custom
        local wep = c.wep
        if c.kind == "npc" and wep == "" then
            local SP = Rhylib.Menus and Rhylib.Menus.Spawn
            wep = (SP and SP.NpcWeapon) and SP.NpcWeapon((list.Get("NPC") or {})[c.name]) or ""
        end
        Rhylib.Net.Start("tool.spawn")
        net.WriteUInt(Tool.KINDS[c.kind], 3)
        net.WriteString(c.name)
        net.WriteUInt(math.Clamp(c.skin, 0, 63), 6)
        net.WriteString(c.body)
        net.WriteString(wep)
        net.WriteFloat(Tool.rot or 0)   -- (the preview's turn, cl_40_ghost)
        net.SendToServer()
        return
    end
    Rhylib.Net.Start("tool.place")
    net.WriteString(e.id)
    net.WriteUInt(math.Clamp(cvCount:GetInt(), 1, 5), 3)
    net.WriteString(e.named and cvName:GetString() or "")
    net.WriteUInt(math.Clamp(cvMode:GetInt(), 1, 5), 3)
    net.WriteUInt(math.Clamp(cvAggro:GetInt(), 0, 5), 3)
    net.WriteUInt(math.Clamp(cvAlert:GetInt(), 0, 2), 2)
    net.WriteFloat(Tool.rot or 0)   -- (the preview's turn, cl_40_ghost)
    if e.spawner then
        net.WriteString(cvSpPreset:GetString())
        net.WriteUInt(SP_MODES[cvSpMode:GetString()] or 1, 3)
        net.WriteUInt(math.Clamp(cvSpTotal:GetInt(), 1, 1000), 10)
        net.WriteUInt(math.Clamp(cvSpCap:GetInt(), 1, 100), 7)
        net.WriteUInt(math.Clamp(cvSpInterval:GetInt(), 5, 600), 10)
    end
    net.SendToServer()
end

--------------------------------------------------------------------------
-- Toolgun info (placing, Permanent tool, Command mode, physgun mode)
--------------------------------------------------------------------------

-- Tool.InfoLayout(): "strip" (default) or "panel" (rhylib_tool_info).
function Tool.InfoLayout() return cvInfo:GetString() == "panel" and "panel" or "strip" end

local COL_RULE = UI.Col("toolgun.infoRule", 42, 45, 41)
local COL_KEYCAP = UI.Col("toolgun.keyCap", 38, 41, 42)
local COL_KEYEDGE = UI.Col("toolgun.keyCapEdge", 58, 62, 56)

-- The crosshair tag's right end on this frame (the panel keeps clear of it).
local tagRight, tagFrame = 0, -1

local function textSize(font, s)
    surface.SetFont(font)
    return surface.GetTextSize(s)
end

-- The dark plate both layouts sit on.
local function plate(x, y, w, h)
    local C = UI.Kit.C
    UI.Kit.SetCol(C.bg, 230)
    surface.DrawRect(x, y, w, h)
    UI.Kit.SetCol(C.edgeDark)
    surface.DrawOutlinedRect(x, y, w, h)
    UI.Kit.SetCol(C.edgeLight)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
end

-- Tool.DrawTag(text, col, red): the small tag to the lower right of the
-- crosshair (a square in col, then text), and under it red text (RMB:
-- remove ...) when given.
function Tool.DrawTag(text, col, red)
    local K = UI.Kit
    local S, C = K.S, K.C
    local x, y = math.floor(ScrW() * 0.5) + S(22), math.floor(ScrH() * 0.5) + S(14)
    local f = K.Font(14, 700)
    local tw, th = textSize(f, text)
    local sq = S(8)
    local sy = y + math.floor((th - sq) * 0.5)
    K.SetCol(C.edgeDark)
    surface.DrawRect(x - 1, sy - 1, sq + 2, sq + 2)
    K.SetCol(col)
    surface.DrawRect(x, sy, sq, sq)
    local tx = x + sq + S(6)
    draw.SimpleText(text, f, tx + 1, y + 1, C.edgeDark)
    draw.SimpleText(text, f, tx, y, C.text)
    local right = tx + tw
    if red then
        local ry = y + th + S(2)
        draw.SimpleText(red, f, x + 1, ry + 1, C.edgeDark)
        local rw = draw.SimpleText(red, f, x, ry, C.bad)
        right = math.max(right, x + rw)
    end
    tagRight, tagFrame = right, FrameNumber()
end

--[[
    A spec (built by the caller only when what it shows changes):
      head        caps word for the panel header ("TOOLGUN · PLACING")
      titleLabel  the strip's first label (default head)
      title, titleCol, sub (panel only)
      rows  { { label, hint, value, col, chip, extra, only = "strip" | "panel" } }
            hint: the key, added to the strip label ("PLACES AS · SHIFT + WHEEL")
            chip: the panel shows the value on a tinted chip
      keys  { { key, stripText, panelText } }  (stripText nil: panel only;
            panelText false: strip only, nil: the strip text)
    The measured layout is kept in spec.L until the layout, screen or
    theme changes.
]]

local function prepStrip(spec, L)
    local K = UI.Kit
    local S = K.S
    L.fl, L.fv, L.fb, L.fx = K.Font(12, 700), K.Font(17, 700), K.Font(17, 800), K.Font(15, 500)
    L.fk, L.ft = K.Font(14, 700), K.Font(14, 500)
    L.padX, L.padY = S(16), S(8)
    local _, lh = textSize(L.fl, "A")
    local _, vh = textSize(L.fv, "A")
    local _, kh = textSize(L.fk, "A")
    L.lh, L.vh, L.kh = lh, vh, kh
    local secs, sum = {}, 0
    local function add(lab, val, col, bold, extra)
        local s = { lab = string.upper(lab), val = val, col = col, bold = bold, extra = extra }
        local lw = textSize(L.fl, s.lab)
        s.vw = textSize(bold and L.fb or L.fv, val)
        local ew = extra and (S(6) + textSize(L.fx, extra)) or 0
        s.w = math.max(lw, s.vw + ew) + L.padX * 2
        sum = sum + s.w
        secs[#secs + 1] = s
    end
    add(spec.titleLabel or spec.head, spec.title, spec.titleCol, true)
    for _, r in ipairs(spec.rows or {}) do
        if r.only ~= "panel" then
            add(r.hint and (r.label .. " · " .. r.hint) or r.label, r.value, r.col, r.chip, r.extra)
        end
    end
    -- The keys flow into as many lines as the screen width needs.
    local keys = {}
    local gap, inner = S(12), S(5)
    local avail = math.max(S(260), ScrW() - S(32) - sum - L.padX * 2)
    local lines, lw, widest = 1, 0, 0
    for _, k in ipairs(spec.keys or {}) do
        if k[2] then
            local kw = textSize(L.fk, k[1])
            local w = kw + inner + textSize(L.ft, k[2])
            local g = lw > 0 and gap or 0
            if lw > 0 and lw + g + w > avail then lines, lw, g = lines + 1, 0, 0 end
            keys[#keys + 1] = { k = k[1], t = k[2], kw = kw, line = lines, x = lw + g }
            lw = lw + g + w
            widest = math.max(widest, lw)
        end
    end
    L.secs, L.keys, L.inner = secs, keys, inner
    L.keysH = #keys > 0 and (lines * (kh + S(3)) - S(3)) or 0
    L.keysW = #keys > 0 and (widest + L.padX * 2) or 0
    L.secH = lh + S(2) + vh
    L.h = math.max(L.secH, L.keysH) + L.padY * 2
    L.w = sum + L.keysW
end

-- The strip's bottom: about 150 px above the screen bottom, above the
-- Simple HUD's hotbar and stamina bar, and above the visor cheeks.
local function stripBottom(x0, w, h)
    local S = UI.Kit.S
    local H = ScrH()
    local b = H - S(150)
    local hud = Rhylib.HUD
    if hud then
        local r = hud.HotbarRect
        if r and r.w > 0 and r.frame >= FrameNumber() - 2 then b = math.min(b, r.y - S(36)) end
        if hud.RealisticActive and hud.RealisticActive() and hud.RealCheekY then
            b = math.min(b, hud.RealCheekY(x0, -1) - S(10), hud.RealCheekY(x0 + w, 1) - S(10))
        elseif hud.VisorActive and hud.VisorActive() and hud.VisorCheekY then
            b = math.min(b, hud.VisorCheekY(x0, -1) - S(10), hud.VisorCheekY(x0 + w, 1) - S(10))
        end
    end
    -- (never up into the crosshair tag)
    return math.floor(math.max(b, H * 0.5 + S(60) + h))
end

local function drawStrip(L)
    local K = UI.Kit
    local S, C = K.S, K.C
    local x0 = math.floor((ScrW() - L.w) * 0.5)
    local y0 = stripBottom(x0, L.w, L.h) - L.h
    plate(x0, y0, L.w, L.h)
    local x = x0
    local ly = y0 + math.floor((L.h - L.secH) * 0.5)
    local vy = ly + L.lh + S(2)
    local n = #L.secs
    for i, s in ipairs(L.secs) do
        draw.SimpleText(s.lab, L.fl, x + L.padX, ly, C.label)
        draw.SimpleText(s.val, s.bold and L.fb or L.fv, x + L.padX, vy, s.col or C.text)
        if s.extra then
            draw.SimpleText(s.extra, L.fx, x + L.padX + s.vw + S(6), vy + L.vh, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end
        x = x + s.w
        if i < n or #L.keys > 0 then
            K.SetCol(COL_RULE)
            surface.DrawRect(x - 1, y0 + 2, 1, L.h - 3)
        end
    end
    local ky0 = y0 + math.floor((L.h - L.keysH) * 0.5)
    for _, k in ipairs(L.keys) do
        local kx = x + L.padX + k.x
        local ky = ky0 + (k.line - 1) * (L.kh + S(3))
        draw.SimpleText(k.k, L.fk, kx, ky, C.text)
        draw.SimpleText(k.t, L.ft, kx + k.kw + L.inner, ky, C.textDim)
    end
end

local function prepPanel(spec, L)
    local K = UI.Kit
    local S = K.S
    local pw, padX = S(360), S(16)
    local inW = pw - padX * 2
    L.w, L.padX = pw, padX
    L.fh, L.ftitle, L.fsub = K.Font(13, 700), K.Font(21, 700), K.Font(14, 500)
    L.fl, L.fv, L.fb, L.fx = K.Font(13, 700), K.Font(15, 500), K.Font(15, 800), K.Font(15, 500)
    L.fk, L.ft = K.Font(13, 700), K.Font(14, 500)
    L.headH, L.rowH, L.keyH, L.labW = S(36), S(26), S(23), S(124)
    L.head = "TOOLGUN · " .. string.upper(spec.head or "")
    L.title, L.titleCol = K.Fit(spec.title or "", L.ftitle, inW), spec.titleCol
    local _, th = textSize(L.ftitle, "A")
    L.titleH = th
    L.sub = spec.sub and K.Fit(spec.sub, L.fsub, inW) or nil
    local _, sh = textSize(L.fsub, "A")
    L.subH = L.sub and (sh + S(2)) or 0
    local valW = inW - L.labW
    local rows = {}
    for _, r in ipairs(spec.rows or {}) do
        if r.only ~= "strip" then
            local font = r.chip and L.fb or L.fv
            local room = valW - (r.chip and S(18) or 0)
            local v = K.Fit(r.value, font, room)
            local vw = textSize(font, v)
            local ex = r.extra and K.Fit(r.extra, L.fx, room - vw - S(6)) or nil
            rows[#rows + 1] = { lab = string.upper(r.label), val = v, vw = vw, col = r.col, chip = r.chip, extra = ex }
        end
    end
    local keys, kcol = {}, 0
    for _, k in ipairs(spec.keys or {}) do
        local t = k[3]
        if t == nil then t = k[2] end
        if t then
            local kw = textSize(L.fk, k[1])
            keys[#keys + 1] = { k = k[1], t = t, kw = kw }
            kcol = math.max(kcol, kw + S(10))
        end
    end
    for _, k in ipairs(keys) do k.t = K.Fit(k.t, L.ft, inW - kcol - S(10)) end
    L.rows, L.keys, L.kcol = rows, keys, kcol
    local h = L.headH + S(12) + L.titleH + L.subH + S(10) + #rows * L.rowH
    if #keys > 0 then h = h + S(8) + 1 + S(8) + #keys * L.keyH end
    L.h = h + S(10)
end

local function drawPanel(L)
    local K = UI.Kit
    local S, C = K.S, K.C
    local W, H = ScrW(), ScrH()
    local hud = Rhylib.HUD
    local real = hud and hud.RealisticActive and hud.RealisticActive() and hud.RealGeo and true or false
    -- (Realistic HUD: inside the visor, left of the health ladder)
    local right = W - S(24)
    if real then right = math.min(right, W - math.floor(272 * hud.RealGeo().s)) end
    local x = right - L.w
    local y = math.floor((H - L.h) * 0.5)
    if tagFrame == FrameNumber() and x < tagRight + S(12) then
        -- (too narrow to sit beside the crosshair tag: above the crosshair)
        y = math.floor(H * 0.5 - S(22) - L.h)
        local top = S(16)
        if real and hud.RealBrowY then top = math.max(hud.RealBrowY(x), hud.RealBrowY(right)) + S(8) end
        y = math.max(y, math.floor(top))
    end
    plate(x, y, L.w, L.h)
    local px = x + L.padX
    draw.SimpleText(L.head, L.fh, px, y + L.headH * 0.5, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    K.SetCol(COL_RULE)
    surface.DrawRect(x + 1, y + L.headH, L.w - 2, 1)
    local cy = y + L.headH + S(12)
    draw.SimpleText(L.title, L.ftitle, px, cy, L.titleCol or C.text)
    cy = cy + L.titleH
    if L.sub then
        draw.SimpleText(L.sub, L.fsub, px, cy + S(2), C.textDim)
        cy = cy + L.subH
    end
    cy = cy + S(10)
    local vx = px + L.labW
    for _, r in ipairs(L.rows) do
        local my = cy + L.rowH * 0.5
        draw.SimpleText(r.lab, L.fl, px, my, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tx = vx
        if r.chip and r.col then
            K.SetCol(r.col, 64)
            surface.DrawRect(vx, cy + S(3), r.vw + S(18), L.rowH - S(6))
            K.SetCol(r.col)
            surface.DrawRect(vx, cy + S(3), S(3), L.rowH - S(6))
            tx = vx + S(10)
            draw.SimpleText(r.val, L.fb, tx, my, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            tx = tx + r.vw + S(8)
        else
            draw.SimpleText(r.val, r.chip and L.fb or L.fv, tx, my, r.col or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            tx = tx + r.vw
        end
        if r.extra then draw.SimpleText(r.extra, L.fx, tx + S(6), my, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        cy = cy + L.rowH
    end
    if #L.keys > 0 then
        cy = cy + S(8)
        K.SetCol(COL_RULE)
        surface.DrawRect(px, cy, L.w - L.padX * 2, 1)
        cy = cy + 1 + S(8)
        local capR = px + L.kcol
        for _, k in ipairs(L.keys) do
            local cw = k.kw + S(10)
            local cx0 = capR - cw
            K.SetCol(COL_KEYCAP)
            surface.DrawRect(cx0, cy + S(1), cw, L.keyH - S(4))
            K.SetCol(COL_KEYEDGE)
            surface.DrawOutlinedRect(cx0, cy + S(1), cw, L.keyH - S(4))
            local my = cy + S(1) + (L.keyH - S(4)) * 0.5
            draw.SimpleText(k.k, L.fk, cx0 + cw * 0.5, my, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(k.t, L.ft, capR + S(10), my, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            cy = cy + L.keyH
        end
    end
end

-- Tool.DrawInfo(spec): draw the info in the picked layout (see above).
function Tool.DrawInfo(spec)
    if not spec then return end
    local mode = Tool.InfoLayout()
    local W, H, stamp = ScrW(), ScrH(), UI.themeStamp or 0
    local L = spec.L
    if not L or L.mode ~= mode or L.W ~= W or L.H ~= H or L.stamp ~= stamp then
        L = { mode = mode, W = W, H = H, stamp = stamp }
        if mode == "panel" then prepPanel(spec, L) else prepStrip(spec, L) end
        spec.L = L
    end
    if mode == "panel" then drawPanel(L) else drawStrip(L) end
end

-- An entry's short name for the crosshair tag: "B1 battle droid" -> "B1",
-- "Command post (logistics)" -> "Command post".
local function shortName(e)
    if e.short then return e.short end
    local n = string.match(e.name or "", "^[^%(,:]+") or e.name or ""
    n = string.Trim(n)
    local code = string.match(n, "^(%u+%d+%w*)%s")
    return code or n
end

local MODE_NAMES = { "GUARD", "PATROL", "ATTACK", "ROAM", "ASSAULT" }
local function aggroText(D, a)
    return a .. " " .. ((D and D.AGGRO_NAMES and D.AGGRO_NAMES[a]) or "")
end
local function keyName(s) return string.upper(s or "") end
local cvCmdKey   -- (cl_20_command.lua makes it, after this file)

-- The placing info, rebuilt only when something it shows changes.
local pc = {}
local function placingSpec(e)
    local D = Rhylib.Droids
    local cnt = e.count and math.Clamp(cvCount:GetInt(), 1, 5) or 0
    local droid = (e.count or e.preset) and not e.custom and D ~= nil
    local m = droid and math.Clamp(cvMode:GetInt(), 1, 5) or 0
    local a = droid and math.Clamp(cvAggro:GetInt(), 0, 5) or 0
    local al = droid and math.Clamp(cvAlert:GetInt(), 0, 2) or 0
    local ga = (D and D.AGGRO_NAMES and D.Aggro) and D.Aggro() or 0
    local nm = e.named and cvName:GetString() or ""
    local pk = cvPhysKey:GetString()
    if D and not cvCmdKey then cvCmdKey = GetConVar("rhylib_tool_command_key") end
    local ck = (D and cvCmdKey) and cvCmdKey:GetString() or ""
    if pc.spec and pc.e == e and pc.cnt == cnt and pc.m == m and pc.a == a and pc.al == al and pc.ga == ga
        and pc.nm == nm and pc.pk == pk and pc.ck == ck and pc.D == (D ~= nil) then
        return pc.spec
    end
    pc.e, pc.cnt, pc.m, pc.a, pc.al, pc.ga, pc.nm, pc.pk, pc.ck, pc.D = e, cnt, m, a, al, ga, nm, pk, ck, D ~= nil
    local times = cnt > 1 and (" ×" .. cnt) or ""
    local head = e.order and "Order" or (e.custom and "Spawning" or "Placing")
    local spec = {
        head = head, title = e.name .. times, titleCol = COL,
        sub = e.order and "LMB sets the mode of every NPC near where you aim" or e.custom and "LMB spawns it where the ring is" or "LMB places it where the ring is",
        rows = {}, keys = {},
        tag = shortName(e) .. times, tagCol = droid and MODE_COLS[m] or COL,
    }
    local rows, keys = spec.rows, spec.keys
    if e.named then rows[#rows + 1] = { label = "Name", value = "\"" .. nm .. "\"" } end
    if droid then
        rows[#rows + 1] = { label = "Places as", hint = "Shift + wheel", value = MODE_NAMES[m], col = MODE_COLS[m], chip = true }
        local sq = a == 0 and "Global" or aggroText(D, a)
        rows[#rows + 1] = { label = "Aggression", hint = "Alt + wheel", value = sq, only = "strip", extra = ga > 0 and ("· all droids " .. ga) or nil }
        rows[#rows + 1] = { label = "Aggression", value = sq, only = "panel", extra = "(squad)" }
        rows[#rows + 1] = { label = "Alertness", hint = "Shift + Alt + wheel", value = ALERT_NAMES[al] .. (al == 2 and " (stealth)" or ""), col = al == 2 and COL_UNAWARE or nil }
        if ga > 0 then rows[#rows + 1] = { label = "All droids", value = aggroText(D, ga), only = "panel" } end
        keys[#keys + 1] = { "Shift + wheel", nil, "Places as" }
        keys[#keys + 1] = { "Alt + wheel", nil, "Squad aggression" }
        keys[#keys + 1] = { "Shift + Alt + wheel", nil, "Alertness" }
    elseif ga > 0 then
        rows[#rows + 1] = { label = "All droids", value = aggroText(D, ga) }
    end
    keys[#keys + 1] = { "R", "spawn window · hold: peek · twice: Q menu", "Spawn window (hold: peek, twice: Q menu)" }
    keys[#keys + 1] = { keyName(pk), "physgun", "Physgun mode" }
    if D then keys[#keys + 1] = { keyName(ck ~= "" and ck or "x"), "command", "Command mode" } end
    keys[#keys + 1] = { "hold E", "modes", "Toolgun modes" }
    pc.spec = spec
    return spec
end

-- "RMB: remove <name>" for what you aim at (made once per thing).
local remEnt, remText = nil, nil
local function removeText(ent)
    if not (IsValid(ent) and not ent:IsPlayer()) then return nil end
    if not (ent.IsRhylibDroid or ent.IsRhylibClone or Tool.ByClass(ent:GetClass()) or ent:GetNW2Bool("rhylib_toolSpawned")) then return nil end
    if ent ~= remEnt then
        local n = ent.PrintName
        remEnt, remText = ent, "RMB: remove " .. ((n and n ~= "") and n or ent:GetClass())
    end
    return remText
end

-- Tool.DrawHUD(wep): the toolgun info and the crosshair tag (SWEP:DrawHUD
-- calls it).
function Tool.DrawHUD(wep)
    if Tool.PhysOnLocal and Tool.PhysOnLocal() and Tool.DrawPhysHUD then return Tool.DrawPhysHUD() end
    if Tool.command and Tool.DrawCommandHUD and Rhylib.Droids then return Tool.DrawCommandHUD() end
    local e = Tool.Chosen()
    if not e then return end
    if e.perma then return Tool.DrawPermaHUD() end
    local spec = placingSpec(e)
    Tool.DrawTag(spec.tag, spec.tagCol, removeText(LocalPlayer():GetEyeTrace().Entity))
    Tool.DrawInfo(spec)
end

-- Shift + wheel: placing mode, Alt + wheel: new squads' aggression,
-- Shift + Alt + wheel: alertness (with a droid entry chosen, placing).
Rhylib.Hook.Add("PlayerBindPress", "toolgun.modewheel", function(ply, bind, pressed)
    if not pressed or Tool.command then return end
    local up = string.find(bind, "invprev", 1, true)
    local down = string.find(bind, "invnext", 1, true)
    if not (up or down) then return end
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun" and Rhylib.Droids) then return end
    local e = Tool.Chosen()
    if not (e and (e.count or e.preset) and not e.custom) then return end
    local step = down and 1 or -1
    local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    local alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
    if shift and alt then
        RunConsoleCommand("rhylib_tool_alertness", tostring((math.Clamp(cvAlert:GetInt(), 0, 2) + step) % 3))
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    elseif shift then
        RunConsoleCommand("rhylib_tool_droidmode", tostring((math.Clamp(cvMode:GetInt(), 1, 5) - 1 + step) % 5 + 1))
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    elseif alt then
        RunConsoleCommand("rhylib_tool_squadaggro", tostring((math.Clamp(cvAggro:GetInt(), 0, 5) + step) % 6))
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    end
end, -36)

local function addPhysSetting()
    local M = Rhylib.Menus
    if M and M.AddSetting then
        M.AddSetting("Weapons", { id = "toolgun.physkey", order = 50, title = "Toolgun: physgun mode", kind = "key", convar = "rhylib_tool_physgun_key" })
    end
end
addPhysSetting()
Rhylib.Hook.Add("InitPostEntity", "toolgun.physsetting", addPhysSetting)

-- The Permanent tool: what you aim at and whether it's kept.
-- The aimed thing, worked out once a frame (HUD and outlines both ask).
local aimFrame, aimEnt = -1, nil
local function permaAimed(ply)
    local f = FrameNumber()
    if f ~= aimFrame then aimFrame, aimEnt = f, Tool.PermaTarget(ply) end
    return aimEnt
end

-- The Permanent tool's info (rebuilt when the aimed thing or its state changes).
local pmc = {}
function Tool.DrawPermaHUD()
    local ply = LocalPlayer()
    local ent = permaAimed(ply)
    local P = Rhylib.Perma
    if not IsValid(ent) then ent = nil end
    local kept = (ent and P and P.Is(ent)) and true or false
    if not pmc.spec or pmc.ent ~= ent or pmc.kept ~= kept then
        pmc.ent, pmc.kept = ent, kept
        local spec = { head = "Permanent", titleLabel = "Tool", title = "Permanent tool", titleCol = COL, rows = {}, keys = {} }
        if ent then
            local name = ent.PrintName and ent.PrintName ~= "" and ent.PrintName or ent:GetClass()
            local col = kept and COL_PERMA or COL_AIM
            spec.sub = kept and "It stays on this map" or "Not saved: gone after a map change"
            spec.rows[1] = { label = "Aiming at", value = name }
            spec.rows[2] = { label = "State", value = kept and "permanent" or "not saved", col = col, chip = true }
            if kept then
                spec.keys[1] = { "LMB", "save where it is now", "Save where it is now" }
                spec.keys[2] = { "RMB", "stop keeping it", "Stop keeping it" }
            else
                spec.keys[1] = { "LMB", "make it permanent", "Make it permanent" }
            end
        else
            spec.sub = "Aim at something: orange outline = permanent"
            spec.rows[1] = { label = "Aiming at", value = "Nothing", extra = "· orange outline = permanent", only = "strip" }
            spec.rows[2] = { label = "Aiming at", value = "Nothing", only = "panel" }
            spec.keys[1] = { "LMB", "make permanent / save its spot", "Make it permanent / save its spot" }
            spec.keys[2] = { "RMB", "stop keeping it", "Stop keeping it" }
        end
        spec.keys[#spec.keys + 1] = { "R", "spawn window", "Spawn window" }
        pmc.spec = spec
    end
    Tool.DrawTag("Permanent", kept and COL_PERMA or COL)
    Tool.DrawInfo(pmc.spec)
end

-- Outlines while the Permanent tool is picked: every permanent thing near
-- you orange, the (not yet permanent) thing you aim at light blue.
local permaList, permaAt = {}, 0
Rhylib.Hook.Add("PreDrawHalos", "toolgun.perma", function()
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
    local e = Tool.Chosen()
    local P = Rhylib.Perma
    if not (e and e.perma and P) then return end
    local now = RealTime()
    if now - permaAt > 0.5 then
        permaAt = now
        -- (the nearest 64 within 3000: halos redraw every entity)
        local pos, near = ply:GetPos(), {}
        for _, x in ipairs(ents.GetAll()) do
            if P.Is(x) then
                local d = x:GetPos():DistToSqr(pos)
                if d < 3000 * 3000 then near[#near + 1] = { x, d } end
            end
        end
        table.sort(near, function(a, b) return a[2] < b[2] end)
        permaList = {}
        for i = 1, math.min(#near, 64) do permaList[i] = near[i][1] end
    end
    local live = {}
    for _, x in ipairs(permaList) do
        if IsValid(x) and P.Is(x) then live[#live + 1] = x end
    end
    if #live > 0 then halo.Add(live, COL_PERMA, 2, 2, 1, true, false) end
    local aimed = permaAimed(ply)
    if IsValid(aimed) and not P.Is(aimed) then halo.Add({ aimed }, COL_AIM, 3, 3, 2, true, true) end
end)

-- Where it will go: a ring on the aimed surface.
local RING = Material("effects/select_ring")
local ringCol = Color(0, 0, 0)   -- (the brush area: COL at a lower alpha, set while drawing)
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "toolgun.aim", function(depth, sky)
    if depth or sky then return end
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit or tr.HitSky then return end
    render.SetMaterial(RING)
    render.DrawQuadEasy(tr.HitPos + tr.HitNormal * 1.5, tr.HitNormal, 40, 40, COL, 0)
    -- An order brush: the area it reaches.
    local e = Tool.Chosen()
    local D = Rhylib.Droids
    if e and (e.order or e.follow) and D then
        local r = D.Cfg("brushRadius") or 400
        ringCol.r, ringCol.g, ringCol.b, ringCol.a = COL.r, COL.g, COL.b, 90
        render.DrawQuadEasy(tr.HitPos + tr.HitNormal * 2, tr.HitNormal, r * 2, r * 2, ringCol, 0)
    end
end)

-- With the toolgun out: each droid's mode over its head (staff only see
-- this, since only they hold the toolgun).
local MODE_LABEL = { laststand = "LAST STAND" }
local SSTATE_LABEL = { "UNAWARE", "SUSPICIOUS", "SEARCHING", "ALARM" }
local droidList, droidListAt = {}, 0
Rhylib.Hook.Add("HUDPaint", "toolgun.droidmodes", function()
    local ply = LocalPlayer()
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
    local now = RealTime()
    if now > droidListAt then
        droidListAt = now + 0.5
        droidList = {}
        for _, e in ipairs(ents.GetAll()) do
            if e.IsRhylibDroid or e.IsRhylibClone then droidList[#droidList + 1] = e end
        end
    end
    local eye = EyePos()
    local font = Rhylib.UI.Font(13, 700)
    local C = UI.Kit.C
    for _, d in ipairs(droidList) do
        if IsValid(d) and d:GetPos():DistToSqr(eye) < 2000 * 2000 then
            local mode = d:GetNW2String("rhylib_dmode", "guard")
            local sp = (d:GetPos() + Vector(0, 0, 90)):ToScreen()
            if sp.visible then
                -- (squad number and its own aggression, when it has them)
                local label = MODE_LABEL[mode] or string.upper(mode)
                local sq, ag = d:GetNW2Int("rhylib_squad", 0), d:GetNW2Int("rhylib_saggro", 0)
                if sq > 0 then label = label .. "  S" .. sq end
                if ag > 0 then label = label .. "  A" .. ag end
                local ss = d:GetNW2Int("rhylib_sstate", 0)   -- (rhylib_droids stealth)
                if ss > 0 and SSTATE_LABEL[ss] then label = label .. "  " .. SSTATE_LABEL[ss] end
                draw.SimpleTextOutlined(label, font, sp.x, sp.y, MODE_COL[mode] or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, C.edgeDark)
                -- (picked with the follow tool)
                if d:GetNW2Entity("rhylib_pickBy") == ply then
                    draw.SimpleTextOutlined("PICKED", font, sp.x, sp.y - 14, PICKED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, C.edgeDark)
                end
            end
        end
    end
end)

-- Console: rhylib_toolgun (the server checks the permission).
concommand.Add("rhylib_toolgun", function()
    Rhylib.Net.Start("tool.give")
    net.SendToServer()
end)
