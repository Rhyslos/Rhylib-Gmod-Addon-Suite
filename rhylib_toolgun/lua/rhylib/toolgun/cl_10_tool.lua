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
    t: physgun mode on / off, cl_30_grab.lua), Settings > Weapons.
    Console: rhylib_toolgun.
    The spawn window and its tab need rhylib_menus; without it R prints a
    note and rhylib_tool_entry <id> picks an entry. The droid mode and
    aggression row needs rhylib_droids.
    R: a tap opens the window (stays open), held 0.3 s+ closes on release,
    a tap while open closes, two taps within 0.35 s open the old Q menu.
    In Command mode (cl_20_command.lua) R held is the order wheel instead.
    With a droid entry: the HUD shows PLACES AS <mode> big and coloured
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
    colours; Aggression 1-5; Alertness, Unaware in blue; Droids at once,
    Beacon name, Re-save). The HUD lines under and over the crosshair sit
    on small dark plates with a coloured left edge. Colours are theme
    tokens "toolgun.*" (cl_11_theme.lua).
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
function Tool.Chosen()
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
    local rows = 0
    local function ctlRow(caption, sub)
        rows = rows + 1
        local first = rows == 1
        local cap = string.upper(caption)
        local r = vgui.Create("DPanel", ctl)
        r:Dock(TOP)
        r:SetTall(S(40))
        r:DockPadding(S(176), S(6), S(10), S(6))
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
    -- Buttons sharing a panel's width evenly; list = { { text, fn, opts }, ... }.
    local function seg(parent, list, dock, wide)
        local p = vgui.Create("DPanel", parent)
        p.Paint = nil
        p:Dock(dock or FILL)
        if wide then p:SetWide(wide) end
        for _, b in ipairs(list) do
            local o = b[3] or {}
            o.small = true
            K.Button(p, b[1], b[2], o)
        end
        function p:PerformLayout(w, h)
            local kids = self:GetChildren()
            local gap = S(5)
            local bw = (w - gap * (#kids - 1)) / math.max(1, #kids)
            for i, c in ipairs(kids) do
                c:SetPos(math.floor((i - 1) * (bw + gap)), math.floor((h - c:GetTall()) * 0.5))
                c:SetWide(math.floor(bw))
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
    if not Tool.FullAccess(LocalPlayer()) then save:SetVisible(false) end
    ctl:SetTall(rows * S(40) + S(4))

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

-- A HUD line on a small plate (the kit's dark plate, a coloured left
-- edge): centred on cx, its top at y (its bottom when up). Returns its height.
local function hudLine(text, font, cx, y, col, edge, up)
    local K = UI.Kit
    local C = K.C
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + K.S(22), th + K.S(6)
    local x = math.floor(cx - w * 0.5)
    if up then y = y - h end
    K.SetCol(C.bg, 215)
    surface.DrawRect(x, y, w, h)
    K.SetCol(C.edgeDark)
    surface.DrawOutlinedRect(x, y, w, h)
    K.SetCol(C.edgeLight)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
    if edge then
        K.SetCol(edge)
        surface.DrawRect(x + 1, y + 1, K.S(3), h - 2)
    end
    draw.SimpleText(text, font, x + w * 0.5 + (edge and K.S(1) or 0), y + h * 0.5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return h
end

-- Tool.DrawHUD(wep): the text under the crosshair (SWEP:DrawHUD calls it).
local MODE_NAMES = { "GUARD", "PATROL", "ATTACK", "ROAM", "ASSAULT" }
local KEYS_PLACING = "Shift + wheel: mode  ·  Alt + wheel: aggression  ·  Shift + Alt + wheel: alertness"

function Tool.DrawHUD(wep)
    if Tool.PhysOnLocal and Tool.PhysOnLocal() and Tool.DrawPhysHUD then return Tool.DrawPhysHUD() end
    if Tool.command and Tool.DrawCommandHUD and Rhylib.Droids then return Tool.DrawCommandHUD() end
    local e = Tool.Chosen()
    if not e then return end
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    if e.perma then return Tool.DrawPermaHUD() end
    local C = UI.Kit.C
    local S = UI.Kit.S
    local cx = ScrW() * 0.5
    local text = e.order and e.name or ((e.custom and "Spawn: " or "Place: ") .. e.name)
    if e.count and cvCount:GetInt() > 1 then text = text .. " ×" .. cvCount:GetInt() end
    -- Droids and presets: what they'll do, big and coloured (Shift + wheel
    -- changes it, Alt + wheel the new squad's aggression).
    if (e.count or e.preset) and not e.custom and Rhylib.Droids then
        local m = math.Clamp(cvMode:GetInt(), 1, 5)
        local a = math.Clamp(cvAggro:GetInt(), 0, 5)
        local D = Rhylib.Droids
        local yy = ScrH() * 0.5 - S(66)
        local al = math.Clamp(cvAlert:GetInt(), 0, 2)
        local hk = hudLine(KEYS_PLACING, UI.Font(12, 500), cx, yy, C.textDim, nil, true)
        local hs = hudLine("Squad aggression: " .. (a == 0 and "global" or (a .. " " .. (D.AGGRO_NAMES and D.AGGRO_NAMES[a] or ""))) .. "   ·   Alertness: " .. ALERT_NAMES[al],
            UI.Font(13, 600), cx, yy - hk - S(2), al == 2 and COL_UNAWARE or C.text, al == 2 and COL_UNAWARE or nil, true)
        hudLine("PLACES AS: " .. MODE_NAMES[m], UI.Font(22, 800), cx, yy - hk - hs - S(4), MODE_COLS[m], MODE_COLS[m], true)
    end
    if e.named then text = text .. "  \"" .. cvName:GetString() .. "\"" end
    local y = ScrH() * 0.5 + S(40)
    y = y + hudLine(text, UI.Font(16, 700), cx, y, COL, COL) + S(3)
    local ent = tr.Entity
    if IsValid(ent) and not ent:IsPlayer() and (ent.IsRhylibDroid or ent.IsRhylibClone or Tool.ByClass(ent:GetClass()) or ent:GetNW2Bool("rhylib_toolSpawned")) then
        y = y + hudLine("RMB: remove " .. (ent.PrintName or ent:GetClass()), UI.Font(14, 700), cx, y, C.bad, C.bad) + S(3)
    end
    y = y + hudLine("R: spawn window  ·  hold R: peek  ·  R twice: old Q menu  ·  " .. string.upper(cvPhysKey:GetString()) .. ": physgun  ·  hold E: modes"
        .. (Rhylib.Droids and ("  ·  " .. string.upper(GetConVarString("rhylib_tool_command_key") or "x") .. ": command mode") or ""), UI.Font(13), cx, y, C.textDim) + S(3)
    local D = Rhylib.Droids
    if D and D.AGGRO_NAMES then
        local a = D.Aggro()
        hudLine("Droid aggression " .. a .. ": " .. D.AGGRO_NAMES[a], UI.Font(13), cx, math.max(y, ScrH() * 0.5 + S(102)), C.text)
    end
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

function Tool.DrawPermaHUD()
    local ply = LocalPlayer()
    local C = UI.Kit.C
    local S = UI.Kit.S
    local cx = ScrW() * 0.5
    local y = ScrH() * 0.5 + S(40)
    y = y + hudLine("Permanent tool", UI.Font(16, 700), cx, y, COL, COL) + S(3)
    local ent = permaAimed(ply)
    local P = Rhylib.Perma
    if IsValid(ent) then
        local name = ent.PrintName and ent.PrintName ~= "" and ent.PrintName or ent:GetClass()
        local kept = P and P.Is(ent)
        local col = kept and COL_PERMA or COL_AIM
        y = y + hudLine(name .. (kept and " · permanent" or " · not saved"), UI.Font(14, 700), cx, y, col, col) + S(3)
        hudLine(kept and "LMB: save where it is now  ·  RMB: stop keeping it" or "LMB: make it permanent", UI.Font(13), cx, y, C.textDim)
    else
        hudLine("Aim at something: orange outline = permanent", UI.Font(13), cx, y, C.textDim)
    end
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
