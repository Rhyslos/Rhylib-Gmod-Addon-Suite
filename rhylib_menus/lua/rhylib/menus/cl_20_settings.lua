--[[
    Settings page. Each setting is bound to a client convar and only shows
    when that convar exists (its addon is installed).

        Rhylib.Menus.AddSetting("HUD", {
            id = "hud.fade", order = 20,
            tab = "Interface",              -- optional (see Menus.SettingTab)
            title = "Hotbar fades", desc = "Dim the hotbar when you're not switching weapons",
            kind = "toggle",                -- toggle, choice, slider or key
            convar = "rhylib_hud_hotbar_fade",
            -- choice: options = { { "value", "Label" }, ... }, get/set optional
            -- slider: min, max, decimals
            -- preview = true: hovering/dragging it shows the HUD undimmed
            -- showIf = function() return bool end: hidden unless true
            --   (call Menus.RefillSettings() after it changes)
        })

    More setting fields: get() / set(v) instead of the convar (then
    convar may be left out), wide (px at 1080p for a choice row's right
    side, default 460), short (key-cap label on Settings > Layout, key
    rows only), shareWith (key rows: { [convar] = true } of key settings
    it may share a key with on purpose, so Controls doesn't warn). Same id again = replaces the old row (refresh-safe).
    The order of sections is the order they were first added.

    The Settings page (one page, "settings"): a search box, the groups on
    the left (Menus.SETTING_GROUPS: HUD, Crosshair, Weapons, Camera &
    freelook, Radio, Audio, Weather, then other sections, Controls and
    Keyboard map) and the group's rows on the right. Menus.SettingGroup
    decides a row's group (st.group, else from its tab and id, else its
    section). A row changed from its convar's default has an accent edge
    and a Reset; the group shows how many are changed. Choices with more
    than three options are a dropdown; kind "colour" (swatches = { Color
    ... }, get / set with Colors) is colour squares and a mixer.
    Menus.SettingsPageId(tab) returns "settings" (an old tab name picks
    the group); Menus.settingsGroup is the group it opens on.
    Menus.SettingGroupTop(group, fn(sp)) puts something above a group's
    rows (the crosshair's live preview). preview = true on a row: hovering
    or dragging it clears the menu so the HUD shows; preview =
    "thirdperson": also shows your third-person camera while you do.
    Client only.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.settings = Menus.settings or {}          -- [section] = list of settings
Menus.sectionOrder = Menus.sectionOrder or {}  -- section names, first added first

-- Menus.AddSetting(section, setting): adds a row to the Settings pages.
-- See the header for the fields; the row only shows if its convar exists.
function Menus.AddSetting(section, setting)
    local list = Menus.settings[section]
    if not list then
        list = {}
        Menus.settings[section] = list
        Menus.sectionOrder[#Menus.sectionOrder + 1] = section
    end
    for i, s in ipairs(list) do
        if s.id == setting.id then
            list[i] = setting
            return
        end
    end
    list[#list + 1] = setting
end

local function cvGet(name)
    local cv = GetConVar(name)
    return cv and cv:GetString() or ""
end

-- Puts the control for setting st into row.right. Values go through the
-- convar (RunConsoleCommand) unless the setting has its own get/set.
local function control(row, st)
    local get = st.get or function() return cvGet(st.convar) end
    local set = st.set or function(v) RunConsoleCommand(st.convar, tostring(v)) end

    if st.kind == "toggle" then
        local t = K.Toggle(row.right, function() return tobool(get()) end, function(on) set(on and 1 or 0) end)
        t:Dock(RIGHT)
    elseif st.kind == "choice" and #(st.options or {}) > 3 then
        -- (more than three choices: a dropdown)
        local d = K.Dropdown(row.right, st.options, function() return tostring(get()) end, set, { width = K.S(260) })
        d:Dock(RIGHT)
    elseif st.kind == "choice" then
        local c = K.Choices(row.right, st.options or {}, function() return tostring(get()) end, set)
        c:Dock(FILL)
    elseif st.kind == "colour" and K.Swatches then
        local sw = K.Swatches(row.right, st.swatches or {}, get, set)
        sw:Dock(RIGHT)
    elseif st.kind == "slider" then
        local sl = K.Slider(row.right, st.min, st.max, st.decimals,
            function() return tonumber(get()) or st.min end, set)
        sl:Dock(FILL)
    elseif st.kind == "key" then
        -- Click, then press a key (Esc cancels).
        local b = vgui.Create("DButton", row.right)
        b:Dock(RIGHT)
        b:SetWide(K.S(120))
        b:SetText("")
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            self.trapping = true
            Menus.keyTrapping = true
            input.StartKeyTrapping()
        end
        function b:Think()
            if not self.trapping or not input.IsKeyTrapping() then
                if self.trapping and not input.IsKeyTrapping() then self.trapping = false Menus.keyTrapping = false end
                return
            end
            local code = input.CheckKeyTrapping()
            if code then
                self.trapping = false
                -- Cleared a moment later, so the Esc that cancelled doesn't
                -- also open or close the menu.
                timer.Simple(0.2, function() Menus.keyTrapping = false end)
                if code ~= KEY_ESCAPE then
                    local name = input.GetKeyName(code)
                    if name then
                        set(string.lower(name))
                        -- (conflict warnings, cl_25_controls.lua)
                        timer.Simple(0.1, function() if Menus.RefillSettings then Menus.RefillSettings() end end)
                    end
                end
            end
        end
        function b:OnRemove()
            if self.trapping then input.StopKeyTrapping() Menus.keyTrapping = false end
        end
        function b:Paint(w, h)
            K.SetCol(self:IsHovered() and C.buttonHover or C.button)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            local label = self.trapping and "PRESS A KEY" or string.upper(get())
            if label == "" then label = "NOT SET" end
            local clash = Menus.keyConflicts and Menus.keyConflicts[st.convar]
            draw.SimpleText(label, K.Font(13, 700), w * 0.5, h * 0.5, self.trapping and C.accent or (clash and C.bad or C.text), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return true
        end
    end
end

--[[
    Tabs. A setting goes in its own `tab` if it names one; keys go in
    Controls (with every fixed control listed, cl_25_controls.lua); a few sounds in Audio; camera and motion settings in Camera
    & motion; everything else in Interface. Within a tab the settings stay
    under their section headings.
]]
Menus.SETTING_TABS = { "Interface", "Camera & motion", "Audio", "Controls" }
-- Setting ids that go to Audio / Camera & motion without naming a tab.
local AUDIO = { ["wep.hitsound"] = true, ["hud.dmgvolume"] = true, ["hud.dmgring"] = true, ["hud.whizz"] = true }
local CAMERA_SECTIONS = { ["Third person"] = true }
local CAMERA = { ["hud.dmgshake"] = true }

-- Menus.SettingTab(section, st): the tab name a setting shows under.
function Menus.SettingTab(section, st)
    if st.tab then return st.tab end
    if st.kind == "key" then return "Controls" end
    if AUDIO[st.id] then return "Audio" end
    if CAMERA[st.id] or CAMERA_SECTIONS[section] or string.sub(st.id or "", 1, 5) == "core." then return "Camera & motion" end
    return "Interface"
end

-- Groups on the Settings page, in this order; sections that fit none of
-- them get a group of their own (before Controls).
Menus.SETTING_GROUPS = { "HUD", "Crosshair", "Weapons", "Camera & freelook", "Radio", "Audio", "Weather" }
local TAB_GROUP = { ["Camera & motion"] = "Camera & freelook", Audio = "Audio", Controls = "Controls", Layout = "Keyboard map" }

-- Menus.SettingGroup(section, st): the group a setting shows under:
-- st.group if set; keys in Controls; Audio and Camera & motion tab rows
-- there; crosshair rows (ids "wep.xh...") in Crosshair; else its section.
function Menus.SettingGroup(section, st)
    if st.group then return st.group end
    local tab = Menus.SettingTab(section, st)
    if TAB_GROUP[tab] then return TAB_GROUP[tab] end
    if string.sub(st.id or "", 1, 6) == "wep.xh" then return "Crosshair" end
    return section
end

Menus.settingsGroup = Menus.settingsGroup or "HUD"
local searchText = ""

-- Menus.SettingsPageId(tab): the Settings page id ("settings"); an old tab
-- name ("Controls", "Audio", "Camera & motion", "Layout") also picks the
-- group it opens on. Example: Rhylib.Menus.pause:ShowPage(Rhylib.Menus.SettingsPageId("Controls"))
function Menus.SettingsPageId(tab)
    if tab and TAB_GROUP[tab] then Menus.settingsGroup = TAB_GROUP[tab] end
    return "settings"
end

-- Every setting row that can show now: { section, st, group }.
local function allRows()
    local out = {}
    for _, section in ipairs(Menus.sectionOrder) do
        local list = {}
        for _, st in ipairs(Menus.settings[section]) do
            if (not st.convar or ConVarExists(st.convar)) and (not st.showIf or st.showIf()) then list[#list + 1] = st end
        end
        table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
        for _, st in ipairs(list) do out[#out + 1] = { section = section, st = st, group = Menus.SettingGroup(section, st) } end
    end
    return out
end

-- The groups that have something, in order (Controls and Keyboard map last).
local function groups(rows)
    local has, order, seen = {}, {}, {}
    for _, r in ipairs(rows) do has[r.group] = true end
    for _, g in ipairs(Menus.SETTING_GROUPS) do
        if has[g] then order[#order + 1] = g seen[g] = true end
    end
    for _, r in ipairs(rows) do
        if not seen[r.group] and r.group ~= "Controls" then order[#order + 1] = r.group seen[r.group] = true end
    end
    order[#order + 1] = "Controls"
    if Menus.BuildKeyboardMap then order[#order + 1] = "Keyboard map" end
    return order
end

-- Is a setting changed from its convar's default? Returns the default too.
local function changedFromDefault(st)
    if not st.convar then return false end
    local cv = GetConVar(st.convar)
    if not cv then return false end
    local def = cv:GetDefault()
    local now = cv:GetString()
    if now == def then return false, def end
    local a, b = tonumber(now), tonumber(def)
    if a and b and math.abs(a - b) < 1e-6 then return false, def end
    return true, def
end

-- One row: the control, and a Reset while it differs from the default
-- (an accent edge marks it).
local function addRow(sp, st)
    local row = K.Row(sp, st.title, st.desc)
    row.rhylibPreview = st.preview   -- (HUD shape: the pause menu stops dimming, cl_10_pause.lua)
    row:Dock(TOP)
    row:DockMargin(0, 0, K.S(10), K.S(4))
    local wide = st.kind == "choice" and #(st.options or {}) <= 3 and (st.wide or 460) or (st.kind == "choice" and 340 or 400)
    row.right:SetWide(K.S(wide))
    local paint = row.Paint
    function row:Paint(w, h)
        paint(self, w, h)
        if changedFromDefault(st) then
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, K.S(3), h)
        end
    end
    if st.convar and st.kind ~= "key" then
        local reset = K.Button(row.right, "Reset", function()
            local _, def = changedFromDefault(st)
            if def ~= nil then RunConsoleCommand(st.convar, def) end
        end, { small = true, enabled = function() return (changedFromDefault(st)) end, tooltip = "Back to the default" })
        reset:Dock(RIGHT)
        reset:SetWide(K.S(58))
        reset:DockMargin(K.S(8), K.S(7), 0, K.S(7))
    end
    control(row, st)
    return row
end

-- Menus.SettingGroupTop(group, fn(sp)): something drawn above a group's
-- rows (a live preview). Same group again = replaced.
-- Example: Rhylib.Menus.SettingGroupTop("Crosshair", function(sp) ... end)
Menus.settingGroupTop = Menus.settingGroupTop or {}
function Menus.SettingGroupTop(group, fn) Menus.settingGroupTop[group] = fn end

-- Fills the page's right side with one group (or the search results).
local function fillGroup(sp, rows, group, q)
    sp:Clear()
    Menus.RefillSettings = function() if IsValid(sp) then fillGroup(sp, allRows(), group, q) end end
    if q and q ~= "" then
        q = string.lower(q)
        local any = false
        -- (one heading per group, in the side list's order)
        local byG = {}
        for _, r in ipairs(rows) do
            local st = r.st
            local hay = string.lower((st.title or "") .. " " .. (st.desc or "") .. " " .. r.section .. " " .. r.group)
            if string.find(hay, q, 1, true) then
                byG[r.group] = byG[r.group] or {}
                table.insert(byG[r.group], st)
            end
        end
        for _, g in ipairs(groups(rows)) do
            if byG[g] then
                local h = K.Heading(sp, g)
                h:Dock(TOP)
                h:DockMargin(0, K.S(6), K.S(10), K.S(6))
                for _, st in ipairs(byG[g]) do addRow(sp, st) end
                any = true
            end
        end
        if not any then K.Label(sp, "Nothing matches \"" .. q .. "\".", 14, nil, C.textDim):Dock(TOP) end
        return
    end
    if group == "Controls" and Menus.ControlsTop then Menus.ControlsTop(sp) end
    local top = Menus.settingGroupTop[group]
    if top then
        local ok, err = pcall(top, sp)
        if not ok then Rhylib.Error("menus", "settings top %s: %s", group, tostring(err)) end
    end
    -- (a group made of several sections keeps their headings)
    local secs, bySec = {}, {}
    for _, r in ipairs(rows) do
        if r.group == group then
            if not bySec[r.section] then bySec[r.section] = {} secs[#secs + 1] = r.section end
            table.insert(bySec[r.section], r.st)
        end
    end
    for _, sec in ipairs(secs) do
        if #secs > 1 or sec ~= group then
            local h = K.Heading(sp, sec)
            h:Dock(TOP)
            h:DockMargin(0, K.S(6), K.S(10), K.S(6))
        end
        for _, st in ipairs(bySec[sec]) do addRow(sp, st) end
    end
    if group == "Controls" and Menus.ControlsBottom then Menus.ControlsBottom(sp) end
    if #secs == 0 and group ~= "Controls" then K.Label(sp, "Nothing here yet.", 14, nil, C.textDim):Dock(TOP) end
end

-- The Settings page: search on top, the groups on the left, the group's
-- rows on the right (Keyboard map draws the keyboard there).
Menus.AddPage("settings", {
    title = "Settings",
    order = 100,
    section = "options",
    icon = "settings",
    key = "F1",
    build = function(page)
        local S = K.S
        local rows = allRows()
        local list = groups(rows)
        local found = false
        for _, g in ipairs(list) do if g == Menus.settingsGroup then found = true end end
        if not found then Menus.settingsGroup = list[1] end

        local right, nav, body, kb
        local function show()
            if IsValid(kb) then kb:Remove() end
            if Menus.settingsGroup == "Keyboard map" and searchText == "" then
                body:SetVisible(false)
                kb = vgui.Create("DPanel", right)
                kb:Dock(FILL)
                kb.Paint = nil
                Menus.BuildKeyboardMap(kb)
                Menus.RefillSettings = nil
            else
                body:SetVisible(true)
                fillGroup(body, allRows(), Menus.settingsGroup, searchText)
            end
        end

        local search = K.Search(page, "Search: crosshair, freelook, radio volume…", function(t)
            searchText = t
            show()
        end)
        search:Dock(TOP)
        search:DockMargin(0, 0, 0, S(10))
        search:SetText(searchText)

        nav = K.Scroll(page)
        nav:Dock(LEFT)
        nav:SetWide(S(200))
        nav:DockMargin(0, 0, S(12), 0)
        for _, g in ipairs(list) do
            local b = vgui.Create("DButton", nav)
            b:SetText("")
            b:Dock(TOP)
            b:SetTall(S(38))
            b:DockMargin(0, 0, S(8), S(2))
            local n, nAt = 0, 0
            function b:Paint(w, h)
                -- (the changed count, a couple of times a second)
                if RealTime() > nAt then
                    nAt = RealTime() + 0.5
                    n = 0
                    for _, r in ipairs(rows) do if r.group == g and changedFromDefault(r.st) then n = n + 1 end end
                    self:SetTooltip(n > 0 and (n .. " changed from the default") or false)
                end
                local on = searchText == "" and Menus.settingsGroup == g
                if on then
                    K.SetCol(C.buttonDown)
                    surface.DrawRect(0, 0, w, h)
                    K.SetCol(C.accent)
                    surface.DrawRect(0, 0, S(3), h)
                elseif self:IsHovered() then
                    K.SetCol(C.buttonHover, 160)
                    surface.DrawRect(0, 0, w, h)
                end
                draw.SimpleText(g, K.Font(14, on and 700 or 500), S(14), h * 0.5, on and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if n > 0 then
                    draw.SimpleText(tostring(n), K.Font(11, 700), w - S(10), h * 0.5, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
                return true
            end
            function b:DoClick()
                surface.PlaySound("ui/buttonclick.wav")
                Menus.settingsGroup = g
                if searchText ~= "" then
                    searchText = ""
                    search:SetText("")
                end
                show()
            end
        end

        right = vgui.Create("DPanel", page)
        right:Dock(FILL)
        right.Paint = nil
        body = K.Scroll(right)
        body:Dock(FILL)
        show()
    end,
})
-- (the old tab pages)
for _, id in ipairs({ "settings.interface", "settings.cameramotion", "settings.audio", "settings.controls", "settings.layout" }) do Menus.pages[id] = nil end
Menus.PAGE_ALIAS["settings.interface"] = "settings"
Menus.PAGE_ALIAS["settings.cameramotion"] = function() Menus.settingsGroup = "Camera & freelook" return "settings" end
Menus.PAGE_ALIAS["settings.audio"] = function() Menus.settingsGroup = "Audio" return "settings" end
Menus.PAGE_ALIAS["settings.controls"] = function() Menus.settingsGroup = "Controls" return "settings" end
Menus.PAGE_ALIAS["settings.layout"] = function() Menus.settingsGroup = "Keyboard map" return "settings" end
Menus.PAGE_ALIAS.settings = nil

--------------------------------------------------------------------------
-- The settings Rhylib's addons have
-- (rows for addons that have no settings file of their own; each only
-- shows when that addon's convar exists)
--------------------------------------------------------------------------

Menus.AddSetting("HUD", {
    id = "hud.firstperson", order = 10, wide = 560,
    title = "First-person HUD",
    desc = "How the hotbar and ammo look in first person",
    kind = "choice", convar = "rhylib_hud_firstperson",
    options = { { "", "Server default" }, { "f5", "F5 tiles" }, { "f4", "F4 strip" }, { "real", "Realistic" }, { "thirdperson", "Third-person" } },
    get = function()
        local v = cvGet("rhylib_hud_firstperson")
        local HUD = Rhylib.HUD
        if HUD and HUD.Layouts and not HUD.Layouts[v] then return "" end
        return v
    end,
    -- (refill: the realistic layout's own row shows only with it picked)
    set = function(v)
        RunConsoleCommand("rhylib_hud_firstperson", v)
        timer.Simple(0.1, function() if Menus.RefillSettings then Menus.RefillSettings() end end)
    end,
})
Menus.AddSetting("HUD", {
    id = "hud.fade", order = 20,
    title = "Hotbar fades", desc = "Dim the hotbar when you're not switching weapons",
    kind = "toggle", convar = "rhylib_hud_hotbar_fade",
})

Menus.AddSetting("Third person", {
    id = "tp.on", order = 10,
    title = "Third person", desc = "Over-the-shoulder camera",
    kind = "toggle", convar = "rhylib_thirdperson",
    -- (only when the server lets players choose)
    showIf = function()
        local TP = Rhylib.ThirdPerson
        return not (TP and TP.Mode) or TP.Mode() == "choice"
    end,
})
Menus.AddSetting("Third person", {
    id = "tp.side", order = 20,
    title = "Shoulder",
    kind = "choice", convar = "rhylib_thirdperson_side",
    options = { { "-1", "Left" }, { "1", "Right" } },
})
Menus.AddSetting("Third person", {
    id = "tp.key", order = 30,
    title = "Toggle key", kind = "key", convar = "rhylib_thirdperson_key",
})
Menus.AddSetting("Third person", {
    id = "tp.swapkey", order = 40,
    title = "Swap shoulder key", kind = "key", convar = "rhylib_thirdperson_swapkey",
})
Menus.AddSetting("Third person", {
    id = "tp.crouch", order = 50,
    title = "Camera rise when crouching", desc = "So the camera clears your arms",
    kind = "slider", convar = "rhylib_thirdperson_crouchup", min = 0, max = 30,
})

Menus.AddSetting("Chat", {
    id = "chat.pinned", order = 10,
    title = "Keep the chat visible", desc = "Same as /togglechat",
    kind = "toggle", convar = "rhylib_chat_pinned",
})
Menus.AddSetting("Chat", {
    id = "chat.style", order = 20,
    title = "Chat look", desc = "Comms: one row per message with rank and channel, channel buttons above the line you type in. Tabs: one line per message, tabs to filter by channel",
    kind = "choice", convar = "rhylib_chat_style", options = { { "b", "Comms" }, { "a", "Tabs" } },
})

Menus.AddSetting("Inventory", {
    id = "inv.key", order = 10,
    title = "Inventory key", kind = "key", convar = "rhylib_inventory_key",
})
Menus.AddSetting("Inventory", {
    id = "inv.cell", order = 20,
    title = "Cell size", desc = "Size of the inventory grid; reopen the inventory to apply",
    kind = "slider", convar = "rhylib_inventory_cellsize", min = 48, max = 128,
})

-- Rows for other addons' console-only options (shown only when the
-- convar exists, i.e. that addon is installed).
Menus.AddSetting("HUD", { id = "hud.visor", order = 38, title = "Helmet visor",
    desc = "The clone helmet visor around the first-person HUD (rhylib_hud_visor)", kind = "toggle", convar = "rhylib_hud_visor" })
