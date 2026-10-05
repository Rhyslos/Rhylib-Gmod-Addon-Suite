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
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.settings = Menus.settings or {}
Menus.sectionOrder = Menus.sectionOrder or {}

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

local function control(row, st)
    local get = st.get or function() return cvGet(st.convar) end
    local set = st.set or function(v) RunConsoleCommand(st.convar, tostring(v)) end

    if st.kind == "toggle" then
        local t = K.Toggle(row.right, function() return tobool(get()) end, function(on) set(on and 1 or 0) end)
        t:Dock(RIGHT)
    elseif st.kind == "choice" then
        local c = K.Choices(row.right, st.options, function() return tostring(get()) end, set)
        c:Dock(FILL)
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
local AUDIO = { ["wep.hitsound"] = true, ["hud.dmgvolume"] = true, ["hud.dmgring"] = true, ["hud.whizz"] = true }
local CAMERA_SECTIONS = { ["Third person"] = true }
local CAMERA = { ["hud.dmgshake"] = true }

function Menus.SettingTab(section, st)
    if st.tab then return st.tab end
    if st.kind == "key" then return "Controls" end
    if AUDIO[st.id] then return "Audio" end
    if CAMERA[st.id] or CAMERA_SECTIONS[section] or string.sub(st.id or "", 1, 5) == "core." then return "Camera & motion" end
    return "Interface"
end

Menus.settingsTab = Menus.settingsTab or "Interface"
if Menus.settingsTab == "Keybinds" then Menus.settingsTab = "Controls" end

local function fill(sp, tab)
    sp:Clear()
    Menus.RefillSettings = function() if IsValid(sp) then fill(sp, tab) end end
    local any = false
    local controls = tab == "Controls" and Menus.ControlsTop
    if controls then
        Menus.ControlsTop(sp)
        any = true
    end
    for _, section in ipairs(Menus.sectionOrder) do
        local list = {}
        for _, st in ipairs(Menus.settings[section]) do
            if (not st.convar or ConVarExists(st.convar)) and (not st.showIf or st.showIf()) and Menus.SettingTab(section, st) == tab then list[#list + 1] = st end
        end
        table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
        if #list > 0 then
            any = true
            local h = K.Heading(sp, section)
            h:Dock(TOP)
            h:DockMargin(0, K.S(6), K.S(10), K.S(6))
            for _, st in ipairs(list) do
                local row = K.Row(sp, st.title, st.desc)
                row.rhylibPreview = st.preview   -- (HUD shape: the pause menu stops dimming, cl_10_pause.lua)
                row:Dock(TOP)
                row:DockMargin(0, 0, K.S(10), K.S(4))
                if st.kind == "choice" then row.right:SetWide(K.S(st.wide or 460)) end
                control(row, st)
            end
        end
    end
    if controls and Menus.ControlsBottom then Menus.ControlsBottom(sp) end
    if not any then
        local l = K.Label(sp, "Nothing here yet.", 14, nil, C.textDim)
        l:Dock(TOP)
    end
end

-- One page per tab, in the Settings submenu of the pause menu.
function Menus.SettingsPageId(tab)
    return "settings." .. string.lower(string.gsub(tab or "Interface", "[^%w]+", ""))
end
for i, tab in ipairs(Menus.SETTING_TABS) do
    Menus.AddPage(Menus.SettingsPageId(tab), {
        title = tab,
        group = "settings",
        order = 100 + i,
        build = function(page)
            Menus.settingsTab = tab
            local sp = K.Scroll(page)
            sp:Dock(FILL)
            fill(sp, tab)
        end,
    })
end
Menus.pages.settings = nil   -- (the old single page)

--------------------------------------------------------------------------
-- The settings Rhylib's addons have
--------------------------------------------------------------------------

Menus.AddSetting("HUD", {
    id = "hud.firstperson", order = 10, wide = 560,
    title = "First-person HUD",
    desc = "How the hotbar and ammo look in first person",
    kind = "choice", convar = "rhylib_hud_firstperson",
    options = { { "", "Server default" }, { "f5", "F5 tiles" }, { "f4", "F4 strip" }, { "thirdperson", "Third-person" } },
    get = function()
        local v = cvGet("rhylib_hud_firstperson")
        local HUD = Rhylib.HUD
        if HUD and HUD.Layouts and not HUD.Layouts[v] then return "" end
        return v
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

Menus.AddSetting("Inventory", {
    id = "inv.key", order = 10,
    title = "Inventory key", kind = "key", convar = "rhylib_inventory_key",
})
Menus.AddSetting("Inventory", {
    id = "inv.cell", order = 20,
    title = "Cell size", desc = "Size of the inventory grid; reopen the inventory to apply",
    kind = "slider", convar = "rhylib_inventory_cellsize", min = 48, max = 128,
})
