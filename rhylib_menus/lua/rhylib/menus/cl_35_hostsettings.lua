--[[
    Server settings page (pause menu, Staff group, superadmins). Lists
    every registered config value by module with its description, default
    and host-file value, and lets staff change it in game (not the admin module's own settings). Changes go
    through Rhylib.Settings (rhylib_core cl_15_settings.lua); the server
    checks the permission and the value's type, saves it and sends it to
    everyone. Reset = back to the host file's value or the default.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

-- Kept across rebuilds of the page.
local chosenModule, searchText = nil, ""

local function prettyKey(k)
    local s = string.gsub(k, "(%l)(%u)", "%1 %2")
    s = string.gsub(s, "(%a)(%d)", "%1 %2")
    s = string.gsub(s, "_", " ")
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

local function prettyModule(m)
    return string.upper(string.sub(m, 1, 1)) .. string.sub(m, 2)
end

local function show(v)
    if v == nil then return "none" end
    if isbool(v) then return v and "on" or "off" end
    if isnumber(v) then return tostring(math.Round(v, 4)) end
    if isstring(v) then return v == "" and "(empty)" or ('"' .. v .. '"') end
    if isvector(v) or isangle(v) then return string.format("%g %g %g", v[1], v[2], v[3]) end
    if istable(v) then
        local j = util.TableToJSON(v) or "?"
        if #j > 60 then j = string.sub(j, 1, 57) .. "..." end
        return j
    end
    return tostring(v)
end

local function current(e)
    if e.o ~= nil then return e.o end
    return e.b
end

-- The control for one entry, in holder. Returns a refresh function.
local function control(holder, e)
    local S = Rhylib.Settings
    local d = e.d
    if isbool(d) then
        local t = K.Toggle(holder, function() return current(e) == true end, function(v) S.Set(e.m, e.k, v) end)
        t:Dock(RIGHT)
        return function() end
    end
    if d == nil then return function() end end

    local entry = K.TextEntry(holder, istable(d) and "JSON" or ((isvector(d) or isangle(d)) and "x y z" or ""))
    entry:Dock(FILL)
    local function text()
        local v = current(e)
        if istable(v) then return util.TableToJSON(v) or "" end
        if isnumber(v) then return tostring(math.Round(v, 6)) end
        if isvector(v) or isangle(v) then return string.format("%g %g %g", v[1], v[2], v[3]) end
        return tostring(v == nil and "" or v)
    end
    entry:SetText(text())
    entry.bad = false
    local paint = entry.Paint
    function entry:Paint(w, h)
        paint(self, w, h)
        if self.bad then
            surface.SetDrawColor(C.bad)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
    end
    function entry:OnChange() self.bad = false end
    function entry:OnEnter()
        local raw = self:GetValue()
        local v
        if isnumber(d) then
            v = tonumber(raw)
            if v and (v ~= v or v == math.huge or v == -math.huge) then v = nil end
        elseif isstring(d) then
            v = raw
        elseif istable(d) then
            v = util.JSONToTable(raw)
        elseif isvector(d) or isangle(d) then
            local a, b, c = string.match(raw, "^%s*(%S+)[%s,]+(%S+)[%s,]+(%S+)%s*$")
            a, b, c = tonumber(a), tonumber(b), tonumber(c)
            if a and b and c then v = isvector(d) and Vector(a, b, c) or Angle(a, b, c) end
        end
        if v == nil then
            self.bad = true
            surface.PlaySound("buttons/button10.wav")
            return
        end
        self.bad = false
        S.Set(e.m, e.k, v)
    end
    return function()
        if not entry:HasFocus() then
            entry:SetText(text())
            entry.bad = false
        end
    end
end

local function makeRow(parent, e, refreshers)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, K.S(10), K.S(4))
    row:DockPadding(K.S(12), K.S(28), K.S(12), K.S(8))
    local title = prettyKey(e.k)
    function row:Paint(w, h)
        surface.SetDrawColor(e.o ~= nil and C.rowAlt or C.row)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if e.o ~= nil then
            surface.SetDrawColor(C.accent)
            surface.DrawRect(0, 0, K.S(3), h)
        end
        draw.SimpleText(title, K.Font(14, 600), K.S(12), K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetFont(K.Font(14, 600))
        local tw = surface.GetTextSize(title)
        draw.SimpleText(e.k, K.Font(11), K.S(20) + tw, K.S(10), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    row.right = vgui.Create("DPanel", row)
    row.right:Dock(RIGHT)
    row.right:SetWide(K.S(300))
    row.right:DockMargin(K.S(12), 0, 0, 0)
    row.right.Paint = nil
    -- (a fixed-height strip, so the box doesn't grow with the row)
    local holder = vgui.Create("DPanel", row.right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local reset = K.Button(holder, "Reset", function() Rhylib.Settings.Set(e.m, e.k, nil) end,
        { small = true, danger = true, enabled = function() return e.o ~= nil end,
          tooltip = "Back to the host file's value, or the default" })
    reset:Dock(RIGHT)
    reset:SetWide(K.S(70))
    reset:DockMargin(K.S(8), 0, 0, 0)
    local refresh = control(holder, e)

    local left = vgui.Create("DPanel", row)
    left:Dock(FILL)
    left.Paint = nil
    local desc = K.Label(left, e.s ~= "" and e.s or "(no description)", 13, nil, C.label)
    desc:Dock(TOP)
    local vals = vgui.Create("DPanel", left)
    vals:Dock(TOP)
    vals:SetTall(K.S(18))
    vals:DockMargin(0, K.S(4), 0, 0)
    function vals:Paint(w, h)
        local s = "Default " .. show(e.d)
        if e.b ~= e.d and not (istable(e.b) and istable(e.d)) then s = s .. "   ·   host file " .. show(e.b) end
        if e.o ~= nil then s = s .. "   ·   changed here" end
        draw.SimpleText(K.Fit(s, K.Font(12), w), K.Font(12), 0, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    -- (grow with the wrapped description)
    function row:Think()
        local want = K.S(28) + desc:GetTall() + K.S(4) + vals:GetTall() + K.S(8)
        want = math.max(want, K.S(70))
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    refreshers[e.m .. "\0" .. e.k] = refresh
    return row
end

local function matches(e, q)
    if q == "" then return true end
    q = string.lower(q)
    return string.find(string.lower(e.k), q, 1, true) or string.find(string.lower(prettyKey(e.k)), q, 1, true)
        or string.find(string.lower(e.s or ""), q, 1, true) or string.find(string.lower(e.m), q, 1, true)
end

local function build(page)
    local S = Rhylib.Settings
    if not S then
        K.Label(page, "The settings service isn't loaded (rhylib_core is too old).", 14, nil, C.bad):Dock(TOP)
        return
    end

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(K.S(30))
    top:DockMargin(0, 0, 0, K.S(6))
    top.Paint = nil
    local search = K.TextEntry(top, "Search all settings...")
    search:Dock(LEFT)
    search:SetWide(K.S(320))
    search:SetText(searchText)
    search:SetUpdateOnType(true)
    local note = K.Label(top, "Press Enter to apply a value. Most changes apply at once; a few only after a map change. "
        .. "Changes are saved and win over the host config files.", 12, nil, C.textDim)
    note:Dock(FILL)
    note:DockMargin(K.S(12), 0, 0, 0)
    note:SetAutoStretchVertical(false)
    note:SetContentAlignment(4)

    local side = K.Scroll(page)
    side:Dock(LEFT)
    side:SetWide(K.S(190))
    side:DockMargin(0, 0, K.S(10), 0)
    local body = K.Scroll(page)
    body:Dock(FILL)

    local refreshers = {}
    local fill

    local function modules()
        local seen, list = {}, {}
        for _, e in ipairs(S.list or {}) do
            if not seen[e.m] then seen[e.m] = true list[#list + 1] = e.m end
        end
        return list, seen
    end
    -- (counted live, so the side bar follows changes)
    local function changedIn(m)
        local n = 0
        for _, e in ipairs(S.list or {}) do
            if e.m == m and e.o ~= nil then n = n + 1 end
        end
        return n
    end

    local function buildSide()
        side:Clear()
        local list, has = modules()
        if not chosenModule or not has[chosenModule] then chosenModule = list[1] end
        for _, m in ipairs(list) do
            local b = K.Button(side, function()
                local n = changedIn(m)
                return prettyModule(m) .. (n > 0 and ("  (" .. n .. ")") or "")
            end, function()
                chosenModule = m
                search:SetText("")
                searchText = ""
                fill()
            end, { align = "left", small = true, selected = function() return searchText == "" and chosenModule == m end })
            b:Dock(TOP)
            b:DockMargin(0, 0, K.S(8), K.S(3))
        end
    end

    fill = function()
        body:Clear()
        refreshers = {}
        if not S.list then
            K.Label(body, "Loading settings...", 14, nil, C.textDim):Dock(TOP)
            return
        end
        local q = searchText
        local shown = 0
        local h = K.Heading(body, q ~= "" and ("Search: " .. q) or prettyModule(chosenModule or ""))
        h:Dock(TOP)
        h:DockMargin(0, 0, K.S(10), K.S(6))
        local lastM
        for _, e in ipairs(S.list) do
            local want = (q ~= "" and matches(e, q)) or (q == "" and e.m == chosenModule)
            if want then
                if q ~= "" and e.m ~= lastM then
                    lastM = e.m
                    local sub = K.Label(body, prettyModule(e.m), 13, 700, C.accent)
                    sub:Dock(TOP)
                    sub:DockMargin(0, K.S(6), 0, K.S(4))
                end
                makeRow(body, e, refreshers)
                shown = shown + 1
                if shown >= 200 then break end  -- (keep a broad search cheap)
            end
        end
        if #S.list == 0 then
            K.Label(body, "Nothing to show: you may not have the rhylib.settings permission.", 14, nil, C.textDim):Dock(TOP)
        elseif shown == 0 then
            K.Label(body, "Nothing matches.", 14, nil, C.textDim):Dock(TOP)
        end
    end

    function search:OnValueChange(v)
        if v == searchText then return end
        searchText = v
        fill()
    end

    -- (only while this page is open: the panels own the callbacks)
    S.onList = function()
        if not IsValid(body) then return end
        buildSide()
        fill()
    end
    S.onChanged = function(m, k)
        if not IsValid(body) then return end
        local r = refreshers[m .. "\0" .. k]
        if r then r() end
    end

    if S.list then buildSide() end
    fill()
    S.Request()   -- (always fresh: base values may differ from last time)
end

Menus.AddPage("serversettings", {
    title = "Server settings",
    order = 60,
    group = "staff",
    visible = function()
        local me = LocalPlayer()
        if not IsValid(me) then return false end
        local A = Rhylib.Admin
        if A and A.Has then return A.Has(me, "rhylib.settings", "superadmin") end
        return me:IsSuperAdmin()
    end,
    build = build,
})
