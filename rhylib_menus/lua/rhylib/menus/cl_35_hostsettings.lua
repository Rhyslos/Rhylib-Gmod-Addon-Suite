--[[
    Server settings page (pause menu, Staff section, superadmins).

    Left: Home, Model overrides, Changed settings, then the modules grouped
    by category (Combat, Soldiers, Units & roles, NPCs, Server &
    interface, Other), each category folding open. Right: the chosen view.
    The search box on top looks through everything.

    Home: Most used (camera mode, default HUD, weather, simplified
    medical, radar for everyone, money, droid aggression), Changed
    recently (who and when), and a short guide.
    A module: one fold per section (the first open), and an Advanced fold
    (closed) for tables, JSON, vectors and settings marked advanced.

    Controls follow the setting: on / off = a toggle; meta.options = a
    dropdown; meta.kind "rank" = a dropdown of rhylib_roster's ranks;
    numbers = a number box (with a bar when meta.min and meta.max are
    set; meta.step, meta.unit); colours = colour squares and a mixer;
    text = a text box; tables, vectors and angles = a JSON / "x y z" box.

    Nothing applies while you change it: changes wait in the bar at the
    bottom ("N changes not applied") until Apply (or Discard). Rows with a
    waiting change get an amber edge and "Not applied yet: was ...".
    Leaving the page with changes waiting asks Apply / Discard / Stay;
    closing the menu keeps them (the side bar entry shows the count).
    A value the server refuses shows in red on its row (core.cfgerr).

    Model settings (config module "models" from rhylib_core's model
    registry, and every setting whose default is a .mdl path) get a model
    row: picture, the path now, a box for a new path, Pick (the spawn
    window in pick mode), Apply, Reset. These apply on their own Apply
    button. The server refuses paths it doesn't have; things already in
    the world keep the old model until a map change (the row and the page
    say so).

    Changes go through Rhylib.Settings (rhylib_core cl_15_settings.lua);
    the server checks the permission and the value, saves it and sends it
    to everyone. Reset = back to the host file's value or the default.

    Client only. One page: "serversettings" (Staff section, order 230),
    shown to holders of rhylib.settings (superadmin by default).
    Each catalogue entry from Rhylib.Settings.list has these fields:
      m module, k key, d default, b base (host file value or default),
      o override set in game (nil = none), s description, x meta
      (see Config.Register), p true = a model change that needs a map
      change, w who changed it, t when (os.time).
    Where a module goes: Rhylib.Config.Describe(module, { name, category })
    in the owning addon; Config.Sections(module, list) or meta.section on a
    setting (Config.Register) picks its section, in Describe's order.
    Modules in no category go under "Other"; a module without sections
    shows one "General" block.
    Adds Menus.SettingsPending() (the number of changes waiting).
]]

local Menus = Rhylib.Menus
local K = Rhylib.UI.Kit
local C = K.C

-- Kept across rebuilds of the page (and while the menu is closed).
local view = { kind = "home" }          -- { kind = "module", id } / "home" / "models" / "changed"
local searchText = ""
local folded = {}                       -- [category id] = true when closed
local openSec = {}                      -- [module .. "\0" .. section] = true / false
local pending = {}                      -- [id] = { m, k, v } (v = RESET: back to the default)
local errors = {}                       -- [id] = { why = text, at = RealTime() }
local RESET = {}

local function idOf(m, k) return m .. "\0" .. k end

-- Menus.SettingsPending(): changes waiting for Apply on this page.
function Menus.SettingsPending()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------
-- How the page is organised
--------------------------------------------------------------------------

-- Side-bar categories, in order. Each module names its own category and
-- sections (Rhylib.Config.Describe / Config.Sections in its own addon); a
-- category not listed here is added after these; modules that name none
-- go under "Other".
local CATEGORIES = {
    { id = "combat", title = "Combat" },
    { id = "soldiers", title = "Soldiers" },
    { id = "units", title = "Units & roles" },
    { id = "npcs", title = "NPCs" },
    { id = "server", title = "Server & interface" },
}

local function prettyKey(k)
    local s = string.gsub(k, "(%l)(%u)", "%1 %2")
    s = string.gsub(s, "(%a)(%d)", "%1 %2")
    s = string.gsub(s, "_", " ")
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

local function described(m)
    local d = Rhylib.Config.modules and Rhylib.Config.modules[m]
    return istable(d) and d or nil
end

local function prettyModule(m)
    local d = described(m)
    return (d and d.name) or (string.upper(string.sub(m, 1, 1)) .. string.sub(m, 2))
end

local function isModelEntry(e)
    if e.m == "models" then return true end
    local d = e.d
    return isstring(d) and string.lower(string.sub(d, -4)) == ".mdl"
end

-- Gun stats keys are "<class>_<stat>": one section per gun.
local function gunSection(k)
    local class = string.match(k, "^(.-)_[^_]+$")
    if not class then return "Other" end
    local w = weapons.GetStored(class)
    return (w and w.PrintName) or class
end

local function sectionOf(e)
    if e.m == "models" then return (e.x and e.x.group) or "Other" end
    if isModelEntry(e) then return "Models" end
    if e.m == "guns" then return gunSection(e.k) end
    if istable(e.x) and isstring(e.x.section) and e.x.section ~= "" then return e.x.section end   -- (Config.Register meta / Config.Sections)
    local d = described(e.m)
    local list = d and d.sections   -- (patterns: also checked here, for keys the server alone registers)
    if not list then return d and d.order and "Other" or "General" end
    for _, s in ipairs(list) do
        for _, pat in ipairs(s[2] or {}) do
            if string.find(e.k, pat) then return s[1] end
        end
    end
    return "Other"
end

-- A value as short text for the "Default ... · host file ..." line.
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

-- The value in use: the in-game override, else the host file / default.
local function current(e)
    if e.o ~= nil then return e.o end
    return e.b
end

local function titleOf(e)
    if e.x and e.x.name then return e.x.name end
    return prettyKey(e.k)
end

-- (asked every frame by the rows: remembered for a few seconds)
local gameHas = {}
local function onYourGame(m)
    if not (isstring(m) and m ~= "") then return false end
    local c = gameHas[m]
    local now = RealTime()
    if c and c.t > now then return c.v end
    local v = util.IsValidModel(m) or file.Exists(m, "GAME")
    gameHas[m] = { v = v, t = now + 5 }
    return v
end


--------------------------------------------------------------------------
-- Waiting changes
--------------------------------------------------------------------------

local function same(a, b)
    if a == b then return true end
    if istable(a) and istable(b) then return util.TableToJSON(a) == util.TableToJSON(b) end
    if (isvector(a) and isvector(b)) or (isangle(a) and isangle(b)) then return a == b end
    return false
end

-- The value a row shows: the waiting change, else the value in use.
local function shown(e)
    local p = pending[idOf(e.m, e.k)]
    if p then
        if p.v == RESET then return e.b end
        return p.v
    end
    return current(e)
end

-- Puts a change in the waiting list (or takes it out when it equals what
-- is in use). v = RESET: back to the host file / default.
local function setPending(e, v)
    local id = idOf(e.m, e.k)
    errors[id] = nil
    if v == RESET then
        if e.o == nil then pending[id] = nil else pending[id] = { m = e.m, k = e.k, v = RESET } end
        return
    end
    if same(v, current(e)) then pending[id] = nil return end
    pending[id] = { m = e.m, k = e.k, v = v }
end

local function isPending(e) return pending[idOf(e.m, e.k)] ~= nil end

-- "3 min ago" from an os.time.
local function ago(t)
    if not t then return nil end
    local d = math.max(0, os.time() - t)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local n = math.floor(d / 86400)
    return n == 1 and "yesterday" or (n .. " days ago")
end

local function isColor(v) return istable(v) and isnumber(v.r) and isnumber(v.g) and isnumber(v.b) end

-- Rows with a table / JSON / vector value go in the Advanced fold.
local function isAdvanced(e)
    if istable(e.x) and e.x.advanced then return true end
    local d = e.d
    if isColor(d) then return false end
    return istable(d) or isvector(d) or isangle(d)
end

-- Options of a setting: meta.options (or the ranks for kind "rank") as
-- { { value, label }, ... }, or nil.
local function optionsOf(e)
    local x = istable(e.x) and e.x or nil
    if not x then return nil end
    if istable(x.options) then
        local out = {}
        for _, o in ipairs(x.options) do
            if istable(o) then out[#out + 1] = { o[1], o[2] or tostring(o[1]) } else out[#out + 1] = { o, tostring(o) } end
        end
        return out
    end
    if x.kind == "rank" then
        local R = Rhylib.Roster
        if not (R and R.Ranks) then return nil end
        local out = {}
        for _, r in ipairs(R.Ranks()) do out[#out + 1] = { r[1], r[1] .. "  ·  " .. r[2] } end
        return out
    end
    return nil
end

local function labelOf(e, v)
    local opts = optionsOf(e)
    if opts then
        for _, o in ipairs(opts) do if o[1] == v then return o[2] end end
    end
    return show(v)
end

-- Number control settings: meta first, then a guess from the default.
local function numberOpts(e)
    local x = istable(e.x) and e.x or {}
    local d = e.d
    local o = { min = x.min, max = x.max, step = x.step, unit = x.unit, width = K.S(300) }
    if o.min == nil and not x.signed and d >= 0 then o.min = 0 end
    local frac = function(n) return n and math.abs(n - math.floor(n)) > 1e-9 end
    -- (a fraction in the default, step, host file value or override: decimals)
    local b = isnumber(e.b) and e.b or d
    local ov = isnumber(e.o) and e.o or d
    if x.decimals then
        o.decimals = x.decimals
    elseif frac(d) or frac(x.step) or frac(b) or frac(ov) or (x.max and x.max <= 1) then
        o.decimals = (frac(d * 100) or frac((x.step or 0) * 100) or frac(b * 100) or frac(ov * 100)) and 3 or 2
    else
        o.decimals = 0
    end
    if not o.step then o.step = o.decimals == 0 and 1 or (o.decimals == 2 and 0.05 or 0.005) end
    if not o.unit and isstring(e.s) then
        if string.find(e.s, "%(units") or string.find(e.s, " units[%);,]") then o.unit = "units"
        elseif string.find(e.s, "^Seconds") or string.find(e.s, "%(seconds") or string.find(e.s, "%(s[%);]") then o.unit = "s" end
    end
    return o
end

local SWATCHES = { Color(255, 255, 255), Color(133, 183, 235), Color(91, 210, 122), Color(240, 166, 74), Color(226, 75, 74), Color(194, 123, 224) }

-- The control for one plain entry, in holder (docked RIGHT, before
-- Reset). Changes only go to the waiting list. Returns a refresh function.
local function control(holder, e)
    local d = e.d
    local function get() return shown(e) end
    local function set(v) setPending(e, v) end
    if isbool(d) then
        local t = K.Toggle(holder, function() return get() == true end, function(v) set(v) end)
        t:Dock(RIGHT)
        return function() end
    end
    if d == nil then return function() end end
    local opts = optionsOf(e)
    if opts then
        local dd = K.Dropdown(holder, opts, get, set, { width = K.S(300) })
        dd:Dock(RIGHT)
        return function() end
    end
    if isnumber(d) then
        local n = K.Number(holder, numberOpts(e), function() return tonumber(get()) or 0 end, set)
        n:Dock(RIGHT)
        return function() end
    end
    if isColor(d) then
        local sw = K.Swatches(holder, SWATCHES, function() local c = get() return isColor(c) and c or d end,
            function(c) set(Color(c.r, c.g, c.b, d.a or 255)) end)
        sw:Dock(RIGHT)
        return function() end
    end

    -- Text: strings as they are; tables as JSON; vectors / angles "x y z".
    local entry = K.TextEntry(holder, istable(d) and "JSON" or ((isvector(d) or isangle(d)) and "x y z" or ""))
    entry:Dock(FILL)
    entry:SetUpdateOnType(true)
    local function text()
        local v = get()
        if istable(v) then return util.TableToJSON(v) or "" end
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
    local function read(raw)
        if isstring(d) then return raw end
        if istable(d) then return util.JSONToTable(raw) end
        local a, b, c = string.match(raw, "^%s*(%S+)[%s,]+(%S+)[%s,]+(%S+)%s*$")
        a, b, c = tonumber(a), tonumber(b), tonumber(c)
        if a and b and c then return isvector(d) and Vector(a, b, c) or Angle(a, b, c) end
        return nil
    end
    function entry:OnValueChange(raw)
        if self.filling then return end
        local v = read(raw or "")
        if v == nil then self.bad = true return end
        self.bad = false
        set(v)
    end
    return function()
        if not entry:HasFocus() then
            entry.filling = true
            entry:SetText(text())
            entry.filling = false
            entry.bad = false
        end
    end
end

-- A row's frame: an accent edge when changed here, amber while a change
-- waits, red after a refused one.
local function rowFrame(parent, e, tall)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, K.S(6), K.S(4))
    row.minTall = tall
    function row:PaintFrame(w, h)
        local id = idOf(e.m, e.k)
        surface.SetDrawColor(e.o ~= nil and C.rowAlt or C.row)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local edge = errors[id] and C.bad or (pending[id] and C.warn or (e.o ~= nil and C.accent or nil))
        if edge then
            surface.SetDrawColor(edge)
            surface.DrawRect(0, 0, K.S(3), h)
        end
    end
    -- (its height follows its text; folds round it need to know)
    function row:SetWantTall(want)
        if self:GetTall() == want then return end
        self:SetTall(want)
        local p = self:GetParent()
        for _ = 1, 4 do
            if not IsValid(p) then break end
            p:InvalidateLayout()
            p = p:GetParent()
        end
    end
    return row
end

-- A plain setting row: title (and the raw key), description and a status
-- line on the left; the control and Reset on the right.
local function makeRow(parent, e, refreshers, showModule)
    local row = rowFrame(parent, e, K.S(66))
    row:DockPadding(K.S(14), K.S(28), K.S(12), K.S(8))
    local title = (istable(e.x) and e.x.name) or prettyKey(e.k)
    local tag = showModule and (prettyModule(e.m) .. " · " .. e.k) or e.k
    function row:Paint(w, h)
        self:PaintFrame(w, h)
        draw.SimpleText(title, K.Font(14, 600), K.S(14), K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetFont(K.Font(14, 600))
        local tw = surface.GetTextSize(title)
        draw.SimpleText(tag, K.Font(11), K.S(22) + tw, K.S(10), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local right = vgui.Create("DPanel", row)
    right:Dock(RIGHT)
    right:SetWide(K.S(400))
    right:DockMargin(K.S(12), 0, 0, 0)
    right.Paint = nil
    local holder = vgui.Create("DPanel", right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local id = idOf(e.m, e.k)
    local reset = K.Button(holder, function() return pending[id] and "Undo" or "Reset" end, function()
        if pending[id] then
            pending[id] = nil
            errors[id] = nil
        else
            setPending(e, RESET)
        end
    end, { small = true, danger = true, enabled = function() return pending[id] ~= nil or e.o ~= nil end,
          tooltip = "Reset: back to the host file's value or the default (after Apply). Undo: drop the waiting change" })
    reset:Dock(RIGHT)
    reset:SetWide(K.S(64))
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
        local err = errors[id]
        local s, col
        if err then
            s, col = "Refused: " .. err.why, C.bad
        elseif pending[id] then
            local p = pending[id]
            s = p.v == RESET and ("Not applied yet: back to " .. labelOf(e, e.b)) or ("Not applied yet: was " .. labelOf(e, current(e)))
            col = C.warn
        else
            s = "Default " .. labelOf(e, e.d)
            if e.b ~= e.d and not (istable(e.b) and istable(e.d)) then s = s .. "   ·   host file " .. labelOf(e, e.b) end
            if e.o ~= nil then
                local when = ago(e.t)
                s = s .. "   ·   changed here" .. (e.w and (" by " .. e.w) or "") .. (when and (", " .. when) or "")
            end
            col = C.textDim
        end
        draw.SimpleText(K.Fit(s, K.Font(12), w), K.Font(12), 0, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function row:Think()
        self:SetWantTall(math.max(K.S(28) + desc:GetTall() + K.S(4) + vals:GetTall() + K.S(8), self.minTall))
    end
    refreshers[id] = refresh
    return row
end

--------------------------------------------------------------------------
-- Model rows
--------------------------------------------------------------------------

-- Model pictures are made a couple a frame, only once a row is seen
-- (each one renders a spawn icon the first time).
local picQueue = {}
local function queuePic(p) picQueue[#picQueue + 1] = p end
Rhylib.Hook.Add("Think", "menus.hostsettings.pics", function()
    if #picQueue == 0 then return end
    for _ = 1, 2 do
        local p = table.remove(picQueue, 1)
        if not p then break end
        if IsValid(p) and p.wantModel then p:Build() end
    end
end)

local function modelPicture(parent)
    local pic = vgui.Create("DPanel", parent)
    pic.Paint = function(self, w, h)
        surface.SetDrawColor(C.header)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(self.preview and C.warn or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if not self.queued and self.wantModel and self.failedFor ~= self.wantModel
            and not (IsValid(self.mi) and self.builtFor == self.wantModel) then
            self.queued = true
            queuePic(self)
        end
        if not IsValid(self.mi) then
            draw.SimpleText(self.wantModel and "..." or "?", K.Font(13), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    function pic:PaintOver(w, h)
        if self.preview then
            draw.SimpleText("PREVIEW", K.Font(9, 700), w * 0.5, h - K.S(2), C.warn, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end
    function pic:Build()
        self.queued = false
        local m = self.wantModel
        if m == self.builtFor and IsValid(self.mi) then return end
        if IsValid(self.mi) then self.mi:Remove() end
        if not onYourGame(m) then
            self.failedFor = m   -- (not queued again until the wanted model changes)
            return
        end
        util.PrecacheModel(m)
        local mi = vgui.Create("ModelImage", self)
        mi:SetMouseInputEnabled(false)
        mi:SetModel(m)
        local pad = K.S(3)
        mi:SetPos(pad, pad)
        mi:SetSize(self:GetWide() - pad * 2, self:GetTall() - pad * 2)
        self.mi = mi
        self.builtFor = m
    end
    function pic:SetWant(m, preview)
        self.preview = preview
        if m == self.wantModel then return end
        self.wantModel = m
        self.failedFor = nil
        self.queued = false
        if IsValid(self.mi) and self.builtFor ~= m then self.mi:Remove() end
    end
    -- (hover: the spawn window's big turning preview, if it's there)
    function pic:OnCursorEntered()
        local SP = Menus.Spawn
        if SP and SP.Preview and onYourGame(self.wantModel) then
            SP.Preview(self, { model = self.wantModel, title = string.GetFileFromFilename(self.wantModel), sub = self.wantModel })
        end
    end
    pic:SetMouseInputEnabled(true)
    return pic
end

-- A model setting row: picture, title, "Now:" / "Ships with" lines, and a
-- path box with Pick / Apply / Reset and a status line. The picture shows
-- the typed path (marked PREVIEW) while it is a real model on your game.
local function makeModelRow(parent, e, refreshers, showModule)
    local S = Rhylib.Settings
    local row = rowFrame(parent, e, K.S(124))
    local pad = K.S(10)
    local picSize = K.S(84)
    row:DockPadding(pad + picSize + K.S(12), K.S(30), K.S(12), K.S(8))
    local title = titleOf(e)
    local tag
    if e.m == "models" then
        tag = showModule and ("Model · " .. ((e.x and e.x.group) or "")) or ""
    else
        tag = (showModule and (prettyModule(e.m) .. " · ") or "") .. e.k
    end

    local pic = modelPicture(row)
    pic:SetPos(pad, pad)
    pic:SetSize(picSize, picSize)

    function row:Paint(w, h)
        self:PaintFrame(w, h)
        local x = pad + picSize + K.S(12)
        draw.SimpleText(title, K.Font(14, 600), x, K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetFont(K.Font(14, 600))
        local tw = surface.GetTextSize(title)
        draw.SimpleText(tag, K.Font(11), x + tw + K.S(8), K.S(10), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    row.right = vgui.Create("DPanel", row)
    row.right:Dock(RIGHT)
    row.right:SetWide(K.S(380))
    row.right:DockMargin(K.S(12), 0, 0, 0)
    row.right.Paint = nil
    local holder = vgui.Create("DPanel", row.right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local entry = K.TextEntry(holder, "models/folder/name.mdl")
    local status = vgui.Create("DPanel", row.right)
    status:Dock(TOP)
    status:SetTall(K.S(20))
    status:DockMargin(0, K.S(4), 0, 0)
    local btns = vgui.Create("DPanel", row.right)
    btns:Dock(TOP)
    btns:SetTall(K.S(26))
    btns:DockMargin(0, K.S(2), 0, 0)
    btns.Paint = nil

    local function typed() return string.Trim((string.gsub(entry:GetValue() or "", "\\", "/"))) end
    local function apply()
        local v = typed()
        if v == "" or v == current(e) then return end
        if not string.match(string.lower(v), "%.mdl$") then
            entry.bad = true
            surface.PlaySound("buttons/button10.wav")
            return
        end
        entry.bad = false
        S.Set(e.m, e.k, v)
    end
    local reset = K.Button(btns, "Reset", function() S.Set(e.m, e.k, nil) end,
        { small = true, danger = true, enabled = function() return e.o ~= nil end, tooltip = "Back to the model it ships with (or the host file's)" })
    reset:Dock(RIGHT)
    reset:SetWide(K.S(70))
    local applyB = K.Button(btns, "Apply", apply,
        { small = true, accent = true, enabled = function() local v = typed() return v ~= "" and v ~= current(e) end })
    applyB:Dock(RIGHT)
    applyB:SetWide(K.S(70))
    applyB:DockMargin(0, 0, K.S(6), 0)
    local pick = K.Button(btns, "Pick from the spawn menu", function()
        local SP = Menus.Spawn
        if not (SP and SP.PickModel) then return end
        SP.PickModel(function(m)
            if IsValid(entry) then
                entry:SetText((string.gsub(m, "\\", "/")))
                entry.bad = false
            end
        end, title)
    end, { small = true, enabled = function() return Menus.Spawn and Menus.Spawn.PickModel ~= nil end,
        tooltip = "Opens the spawn window: click any model (props, addons, entities) to put its path here, then Apply" })
    pick:Dock(FILL)
    pick:DockMargin(0, 0, K.S(6), 0)

    entry:Dock(FILL)
    entry:SetText(tostring(current(e) or ""))
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
    function entry:OnEnter() apply() end

    -- What the box says about the typed path.
    function status:Paint(w, h)
        local v = typed()
        local txt, col
        if v ~= "" and v ~= current(e) then
            if onYourGame(v) then txt, col = "Not applied yet: press Apply (or Enter)", C.warn
            else txt, col = "Not found on your game: check the path, and that its addon is installed", C.bad end
        elseif e.p then
            txt, col = "Changed: things already in the world keep the old model until a map change", C.warn
        elseif not onYourGame(current(e)) then
            txt, col = "This model isn't on your game (its addon may be missing)", C.bad
        end
        if txt then draw.SimpleText(K.Fit(txt, K.Font(11), w), K.Font(11), 0, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end

    local left = vgui.Create("DPanel", row)
    left:Dock(FILL)
    left.Paint = nil
    local descText = (e.m ~= "models" and e.s ~= "") and e.s or nil
    local desc = descText and K.Label(left, descText, 13, nil, C.label)
    if desc then desc:Dock(TOP) end
    local vals = vgui.Create("DPanel", left)
    vals:Dock(TOP)
    vals:SetTall(K.S(36))
    vals:DockMargin(0, K.S(2), 0, 0)
    function vals:Paint(w, h)
        local cur = tostring(current(e) or "")
        draw.SimpleText(K.Fit("Now: " .. cur, K.Font(12), w), K.Font(12), 0, K.S(9), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local s = "Ships with " .. tostring(e.d)
        if e.b ~= e.d then s = s .. "   ·   host file " .. tostring(e.b) end
        draw.SimpleText(K.Fit(s, K.Font(11), w), K.Font(11), 0, K.S(27), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    function row:Think()
        local want = K.S(30) + (desc and (desc:GetTall() + K.S(2)) or 0) + vals:GetTall() + K.S(12)
        self:SetWantTall(math.max(want, self.minTall))
        -- picture: the typed path while it's a real model, else the current one
        local v = typed()
        if v ~= "" and v ~= current(e) and onYourGame(v) then pic:SetWant(v, true) else pic:SetWant(current(e), false) end
    end
    refreshers[e.m .. "\0" .. e.k] = function()
        if not entry:HasFocus() then
            entry:SetText(tostring(current(e) or ""))
            entry.bad = false
        end
    end
    return row
end

local function addRow(parent, e, refreshers, showModule)
    if isModelEntry(e) then return makeModelRow(parent, e, refreshers, showModule) end
    return makeRow(parent, e, refreshers, showModule)
end

local function matches(e, q)
    if q == "" then return true end
    q = string.lower(q)
    local function has(s) return s and string.find(string.lower(s), q, 1, true) end
    return has(e.k) or has(prettyKey(e.k)) or has(e.s) or has(e.m) or has(prettyModule(e.m))
        or has(e.x and e.x.name) or has(e.x and e.x.group) or (isModelEntry(e) and has(tostring(current(e))))
end

-- Home > Most used: { module, key } in order (missing ones are skipped),
-- and "hud.layout" = the default first-person HUD (a Staff > Commands
-- server tool, applied with the rest).
local MOST_USED = {
    { "thirdperson", "mode" },
    { "cmd", "hud.layout" },
    { "weather", "kind" },
    { "weather", "intensity" },
    { "medical", "simplified" },
    { "radio", "showEveryone" },
    { "roster", "money" },
    { "droids", "aggression" },
}

-- A Staff > Commands server tool (Menus.AddCommand) as a settings row:
-- { title, desc, choices, current(), run(arg) }; its change waits too.
local function commandEntry(id)
    for _, c in ipairs((Menus.commands and Menus.commands.Server) or {}) do
        if c.id == id and c.choices then return c end
    end
end
local function makeCommandRow(parent, c)
    local fake = { m = "cmd", k = c.id, d = nil, b = nil, x = { name = c.title, options = c.choices }, s = c.desc or "" }
    local function cur() return c.current and c.current() end
    fake.o = nil
    local row = rowFrame(parent, fake, K.S(66))
    row:DockPadding(K.S(14), K.S(28), K.S(12), K.S(8))
    function row:Paint(w, h)
        self:PaintFrame(w, h)
        draw.SimpleText(c.title, K.Font(14, 600), K.S(14), K.S(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    local right = vgui.Create("DPanel", row)
    right:Dock(RIGHT)
    right:SetWide(K.S(400))
    right:DockMargin(K.S(12), 0, 0, 0)
    right.Paint = nil
    local holder = vgui.Create("DPanel", right)
    holder:Dock(TOP)
    holder:SetTall(K.S(30))
    holder.Paint = nil
    local id = idOf("cmd", c.id)
    local undo = K.Button(holder, "Undo", function() pending[id] = nil end,
        { small = true, danger = true, enabled = function() return pending[id] ~= nil end })
    undo:Dock(RIGHT)
    undo:SetWide(K.S(64))
    undo:DockMargin(K.S(8), 0, 0, 0)
    local dd = K.Dropdown(holder, c.choices, function()
        local p = pending[id]
        if p then return p.v end
        return cur()
    end, function(v)
        if v == cur() then pending[id] = nil else pending[id] = { m = "cmd", k = c.id, v = v, run = c.run } end
    end, { width = K.S(300) })
    dd:Dock(RIGHT)
    local left = vgui.Create("DPanel", row)
    left:Dock(FILL)
    left.Paint = nil
    local desc = K.Label(left, c.desc or "", 13, nil, C.label)
    desc:Dock(TOP)
    local vals = vgui.Create("DPanel", left)
    vals:Dock(TOP)
    vals:SetTall(K.S(18))
    vals:DockMargin(0, K.S(4), 0, 0)
    function vals:Paint(w, h)
        local s, col = "A server tool (also on Staff > Commands)", C.textDim
        if pending[id] then
            local was = cur()
            for _, o in ipairs(c.choices) do if o[1] == was then was = o[2] end end
            s, col = "Not applied yet: was " .. tostring(was or "?"), C.warn
        end
        draw.SimpleText(K.Fit(s, K.Font(12), w), K.Font(12), 0, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function row:Think()
        self:SetWantTall(math.max(K.S(28) + desc:GetTall() + K.S(4) + vals:GetTall() + K.S(8), self.minTall))
    end
    return row
end

-- Sends every waiting change. Refused ones come back as errors on their
-- rows. The server takes about 8 a second (core.cfgset burst 32): the
-- first 24 go now, the rest 6 a second.
local sendQueue = {}
local function pump()
    local S = Rhylib.Settings
    for _ = 1, 6 do
        local p = table.remove(sendQueue, 1)
        if not p then return end
        if S then S.Set(p.m, p.k, p.v) end
    end
    if #sendQueue > 0 then timer.Create("Rhylib.Menus.SettingsSend", 1, 1, pump) end
end
local function applyAll()
    local n = 0
    for id, p in pairs(pending) do
        if p.m == "cmd" then
            if p.run then p.run(p.v) end
        else
            -- (not "a and b or nil": false is a value)
            local v = p.v
            if v == RESET then v = nil end
            sendQueue[#sendQueue + 1] = { m = p.m, k = p.k, v = v }
        end
        pending[id] = nil
        n = n + 1
    end
    local S = Rhylib.Settings
    for _ = 1, 24 do
        local p = table.remove(sendQueue, 1)
        if not p then break end
        if S then S.Set(p.m, p.k, p.v) end
    end
    if #sendQueue > 0 then timer.Create("Rhylib.Menus.SettingsSend", 1, 1, pump) end
    if n > 0 then surface.PlaySound("buttons/button14.wav") end
    return n
end
local function discardAll()
    for id in pairs(pending) do pending[id] = nil end
end

-- Apply / Discard / Stay, when leaving the page with changes waiting.
-- go() runs after Apply or Discard.
local function askLeave(go)
    local UI = Rhylib.UI
    local f = vgui.Create("EditablePanel")
    UI.prompts = UI.prompts or {}
    UI.prompts[f] = true
    f:SetSize(ScrW(), ScrH())
    f:MakePopup()
    f:SetDrawOnTop(true)
    local n = Menus.SettingsPending()
    function f:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
    end
    local box = vgui.Create("DPanel", f)
    box:SetSize(K.S(460), K.S(170))
    box:Center()
    box:DockPadding(K.S(16), K.S(46), K.S(16), K.S(14))
    function box:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Server settings", ticks = "all", header = K.S(34) })
    end
    local l = K.Label(box, n .. " change" .. (n == 1 and " hasn't" or "s haven't") .. " been applied yet.", 15, 600)
    l:Dock(TOP)
    local btns = vgui.Create("DPanel", box)
    btns:Dock(BOTTOM)
    btns:SetTall(K.S(34))
    btns.Paint = nil
    local function close() UI.prompts[f] = nil if IsValid(f) then f:Remove() end end
    local stay = K.Button(btns, "Stay", close)
    stay:Dock(RIGHT)
    stay:SetWide(K.S(110))
    local disc = K.Button(btns, "Discard", function() close() discardAll() go() end, { danger = true })
    disc:Dock(RIGHT)
    disc:SetWide(K.S(110))
    disc:DockMargin(0, 0, K.S(8), 0)
    local ap = K.Button(btns, "Apply", function() close() applyAll() go() end, { accent = true })
    ap:Dock(RIGHT)
    ap:SetWide(K.S(110))
    ap:DockMargin(0, 0, K.S(8), 0)
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

local function viewKey(v) return v.kind .. ":" .. tostring(v.id or "") end

-- The page: search on top, the side bar (views and modules) on the left,
-- a header and the rows on the right, the Apply bar at the bottom.
local function build(page)
    local S = Rhylib.Settings
    if not S then
        K.Label(page, "The settings service isn't loaded (rhylib_core is too old).", 14, nil, C.bad):Dock(TOP)
        return
    end

    -- The Apply bar (shown while changes wait).
    local bar = vgui.Create("DPanel", page)
    bar:Dock(BOTTOM)
    bar:SetTall(K.S(46))
    bar:DockMargin(0, K.S(8), 0, 0)
    function bar:Paint(w, h)
        surface.SetDrawColor(C.warn.r, C.warn.g, C.warn.b, 26)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(C.warn)
        surface.DrawRect(0, 0, K.S(3), h)
        surface.DrawOutlinedRect(0, 0, w, h)
        local n = Menus.SettingsPending()
        draw.SimpleText(n .. " change" .. (n == 1 and "" or "s") .. " not applied yet", K.Font(15, 700), K.S(16), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function bar:Think()
        local want = Menus.SettingsPending() > 0
        if self:IsVisible() ~= want then
            self:SetVisible(want)
            if IsValid(page) then page:InvalidateLayout() end
        end
    end
    local applyB = K.Button(bar, "Apply", function() applyAll() end, { accent = true })
    applyB:Dock(RIGHT)
    applyB:SetWide(K.S(130))
    applyB:DockMargin(0, K.S(6), K.S(6), K.S(6))
    local discB = K.Button(bar, "Discard", function() discardAll() end, { danger = true })
    discB:Dock(RIGHT)
    discB:SetWide(K.S(110))
    discB:DockMargin(0, K.S(6), K.S(8), K.S(6))
    bar:SetVisible(Menus.SettingsPending() > 0)

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(K.S(36))
    top:DockMargin(0, 0, 0, K.S(8))
    top.Paint = nil
    local note = K.Label(top, "Changes wait until you press Apply. Most work at once; models and a few others after a map change.", 12, nil, C.textDim)
    note:Dock(RIGHT)
    note:SetWide(K.S(300))
    note:DockMargin(K.S(12), 0, 0, 0)
    note:SetAutoStretchVertical(false)
    note:SetContentAlignment(4)
    local fill
    local search = K.Search(top, "Search all settings and models", function(t)
        if t == searchText then return end
        searchText = t
        if fill then fill() end
    end)
    search:Dock(FILL)
    search:SetText(searchText)

    local side = K.Scroll(page)
    side:Dock(LEFT)
    side:SetWide(K.S(220))
    side:DockMargin(0, 0, K.S(10), 0)
    local right = vgui.Create("DPanel", page)
    right:Dock(FILL)
    right.Paint = nil
    local head = vgui.Create("DPanel", right)
    head:Dock(TOP)
    head:SetTall(K.S(10))
    head:DockMargin(0, 0, K.S(10), K.S(6))
    head.Paint = nil
    local body = K.Scroll(right)
    body:Dock(FILL)

    local refreshers = {}

    local function entriesOf(pred)
        local out = {}
        for _, e in ipairs(S.list or {}) do
            if pred(e) then out[#out + 1] = e end
        end
        return out
    end
    local function find(m, k)
        for _, e in ipairs(S.list or {}) do
            if e.m == m and e.k == k then return e end
        end
    end
    local function modules()
        local seen = {}
        for _, e in ipairs(S.list or {}) do
            if e.m ~= "models" then seen[e.m] = true end
        end
        return seen
    end
    local function countChanged(pred)
        local n = 0
        for _, e in ipairs(S.list or {}) do
            if e.o ~= nil and pred(e) then n = n + 1 end
        end
        return n
    end
    local function pendingCount()
        local n = 0
        for _, e in ipairs(S.list or {}) do
            if e.p then n = n + 1 end
        end
        return n
    end

    local function choose(v)
        view = v
        if searchText ~= "" then
            searchText = ""
            search:SetText("")
        end
        fill()
    end

    local function sideButton(label, v, indent, icon)
        local b = vgui.Create("DButton", side)
        b:SetText("")
        b:Dock(TOP)
        b:SetTall(K.S(30))
        b:DockMargin(indent and K.S(10) or 0, 0, K.S(8), K.S(2))
        function b:Paint(w, h)
            local on = searchText == "" and viewKey(view) == viewKey(v)
            if on then
                surface.SetDrawColor(C.buttonDown)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(C.accent)
                surface.DrawRect(0, 0, K.S(3), h)
            elseif self:IsHovered() then
                surface.SetDrawColor(C.buttonHover.r, C.buttonHover.g, C.buttonHover.b, 160)
                surface.DrawRect(0, 0, w, h)
            end
            local x = K.S(12)
            if icon then
                K.Icon(icon, x, (h - K.S(16)) * 0.5, K.S(16), on and C.accent or C.textDim)
                x = x + K.S(24)
            end
            local text, count = label()
            local f = K.Font(13, on and 700 or 500)
            local rightX = w - K.S(8)
            if count and count > 0 then
                draw.SimpleText(tostring(count), K.Font(11, 700), rightX, h * 0.5, C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                rightX = rightX - K.S(22)
            end
            draw.SimpleText(K.Fit(text, f, rightX - x), f, x, h * 0.5, on and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return true
        end
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            choose(v)
        end
        return b
    end

    local function buildSide()
        side:Clear()
        local has = modules()
        sideButton(function() return "Home" end, { kind = "home" }, false, "staffhome")
        sideButton(function() return "Model overrides", countChanged(isModelEntry) end, { kind = "models" }, false, "trooper")
        sideButton(function() return "Changed settings", countChanged(function() return true end) end, { kind = "changed" }, false, "editor")

        local placed = {}
        local cats = {}
        -- (Config.Describe categories first: a module that names one goes
        -- there, a category the page doesn't know is added after the rest)
        local byTitle, extra = {}, {}
        for _, c in ipairs(CATEGORIES) do byTitle[string.lower(c.title)] = c.id byTitle[c.id] = c.id end
        local wantCat = {}
        for m in pairs(has) do
            local d = described(m)
            if d and isstring(d.category) and d.category ~= "" then
                local id = byTitle[string.lower(d.category)]
                if not id then
                    id = "x_" .. string.lower(d.category)
                    if not extra[id] then extra[id] = { id = id, title = d.category, mods = {} } extra[#extra + 1] = extra[id] end
                    table.insert(extra[id].mods, m)
                end
                wantCat[m] = id
            end
        end
        local byName = function(a, b2) return prettyModule(a) < prettyModule(b2) end
        for _, c in ipairs(CATEGORIES) do
            local mods = {}
            for m, id in pairs(wantCat) do
                if id == c.id and not placed[m] then mods[#mods + 1] = m placed[m] = true end
            end
            table.sort(mods, byName)
            if #mods > 0 then cats[#cats + 1] = { id = c.id, title = c.title, mods = mods } end
        end
        for _, c in ipairs(extra) do
            table.sort(c.mods, byName)
            for _, m in ipairs(c.mods) do placed[m] = true end
            cats[#cats + 1] = c
        end
        local other = {}
        for m in pairs(has) do if not placed[m] then other[#other + 1] = m end end
        table.sort(other)
        if #other > 0 then cats[#cats + 1] = { id = "other", title = "Other", mods = other } end

        for _, c in ipairs(cats) do
            -- (categories start folded; the one holding the open module stays open)
            if folded[c.id] == nil then
                local holds = false
                for _, m in ipairs(c.mods) do if view.kind == "module" and view.id == m then holds = true end end
                folded[c.id] = not holds
            end
            local h = vgui.Create("DButton", side)
            h:SetText("")
            h:Dock(TOP)
            h:SetTall(K.S(26))
            h:DockMargin(0, K.S(8), K.S(8), K.S(2))
            function h:Paint(w, hh)
                local n = countChanged(function(e) for _, m in ipairs(c.mods) do if e.m == m then return true end end return false end)
                K.Arrow(K.S(6), hh * 0.5, K.S(8), folded[c.id] and "right" or "down", C.textDim)
                draw.SimpleText(string.upper(c.title), K.Font(12, 700), K.S(16), hh * 0.5,
                    self:IsHovered() and C.text or C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if n > 0 then draw.SimpleText(tostring(n), K.Font(11, 700), w - K.S(8), hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
                return true
            end
            function h:DoClick()
                folded[c.id] = not folded[c.id]
                buildSide()
            end
            if not folded[c.id] then
                for _, m in ipairs(c.mods) do
                    sideButton(function()
                        return prettyModule(m), countChanged(function(e) return e.m == m end)
                    end, { kind = "module", id = m }, true)
                end
            end
        end
    end

    -- Header: title, sub line and a pending-map-change bar.
    local function buildHead(title, sub)
        head:Clear()
        local h = K.S(30)
        local t = vgui.Create("DPanel", head)
        t:Dock(TOP)
        t:SetTall(K.S(30))
        function t:Paint(w, hh)
            draw.SimpleText(string.upper(title), K.Font(18, 800), 0, hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if sub then
                surface.SetFont(K.Font(18, 800))
                local tw = surface.GetTextSize(string.upper(title))
                draw.SimpleText(K.Fit(sub, K.Font(12), w - tw - K.S(16)), K.Font(12), tw + K.S(12), hh * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        local pend = pendingCount()
        if pend > 0 then
            local mb = vgui.Create("DPanel", head)
            mb:Dock(TOP)
            mb:SetTall(K.S(30))
            mb:DockMargin(0, K.S(4), 0, 0)
            h = h + K.S(34)
            function mb:Paint(w, hh)
                surface.SetDrawColor(C.warn.r, C.warn.g, C.warn.b, 30)
                surface.DrawRect(0, 0, w, hh)
                surface.SetDrawColor(C.warn)
                surface.DrawRect(0, 0, K.S(3), hh)
                draw.SimpleText(pendingCount() .. " model change" .. (pendingCount() == 1 and "" or "s")
                    .. " this map: new spawns use them now, things already placed after a map change",
                    K.Font(12, 600), K.S(12), hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local A = Rhylib.Admin
            if A and A.Run and A.Has and A.Has(LocalPlayer(), "map") then
                local armed = 0
                local rb = K.Button(mb, function()
                    return CurTime() < armed and "Click again: restart" or "Restart map"
                end, function()
                    if CurTime() < armed then
                        A.Run("restartmap", {})
                        armed = 0
                    else
                        armed = CurTime() + 3
                    end
                end, { small = true, danger = true, tooltip = "Reloads this map after a 10 s countdown (everyone is told)" })
                rb:Dock(RIGHT)
                rb:SetWide(K.S(150))
                rb:DockMargin(0, K.S(2), K.S(2), K.S(2))
            end
        end
        head:SetTall(h)
    end

    local function heading(parent, text, col)
        local hd = K.Heading(parent, text, col)
        hd:Dock(TOP)
        hd:DockMargin(0, K.S(8), K.S(10), K.S(6))
    end
    local function empty(parent, text)
        local l = K.Label(parent, text, 14, nil, C.textDim)
        l:Dock(TOP)
        l:DockMargin(0, K.S(4), 0, K.S(4))
    end
    local function fold(title, count, open, onToggle, dashed)
        local f = K.Fold(body, title, { open = open, count = count, dashed = dashed, onToggle = onToggle })
        f:Dock(TOP)
        f:DockMargin(0, 0, K.S(10), K.S(8))
        f.body:DockPadding(K.S(8), K.S(6), K.S(2), K.S(4))
        return f
    end

    -- Entries split into sections in a stable order (the module's own
    -- order, then Other, then Models).
    local function grouped(list, orderFor)
        local by, order = {}, {}
        for _, e in ipairs(list) do
            local s = sectionOf(e)
            if not by[s] then by[s] = {} order[#order + 1] = s end
            table.insert(by[s], e)
        end
        if orderFor then
            local rank = {}
            for i, s in ipairs(orderFor) do rank[s] = i end
            table.sort(order, function(a, b)
                local ra = rank[a] or (a == "Models" and 10000 or (a == "Other" and 9999 or 5000))
                local rb = rank[b] or (b == "Models" and 10000 or (b == "Other" and 9999 or 5000))
                if ra ~= rb then return ra < rb end
                return a < b
            end)
        else
            table.sort(order)
        end
        return by, order
    end

    local MAX_ROWS = 250

    local function fillHome()
        buildHead("Server settings", "Pick a module on the left, or search")
        heading(body, "Most used")
        for _, mu in ipairs(MOST_USED) do
            if mu[1] == "cmd" then
                local c = commandEntry(mu[2])
                if c then makeCommandRow(body, c) end
            else
                local e = find(mu[1], mu[2])
                if e then addRow(body, e, refreshers, true) end
            end
        end
        -- Changed recently: the newest overrides, with who and when.
        local list = entriesOf(function(e) return e.o ~= nil end)
        table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
        heading(body, "Changed recently")
        if #list == 0 then empty(body, "Nothing has been changed here yet: everything runs on the host file and the defaults.") end
        for i, e in ipairs(list) do
            if i > 8 then break end
            local r = vgui.Create("DButton", body)
            r:SetText("")
            r:Dock(TOP)
            r:SetTall(K.S(34))
            r:DockMargin(0, 0, K.S(10), K.S(2))
            local title = (istable(e.x) and e.x.name) or prettyKey(e.k)
            function r:Paint(w, h)
                surface.SetDrawColor(self:IsHovered() and C.rowHover or C.row)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(C.accent)
                surface.DrawRect(0, 0, K.S(3), h)
                local left = prettyModule(e.m) .. "  ·  " .. title
                draw.SimpleText(K.Fit(left, K.Font(13, 600), w * 0.45), K.Font(13, 600), K.S(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(K.Fit(labelOf(e, current(e)), K.Font(13), w * 0.25), K.Font(13), w * 0.47, h * 0.5, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local who = (e.w or "someone") .. (ago(e.t) and ("  ·  " .. ago(e.t)) or "")
                draw.SimpleText(K.Fit(who, K.Font(12), w * 0.26), K.Font(12), w - K.S(10), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                return true
            end
            function r:DoClick()
                surface.PlaySound("ui/buttonclick.wav")
                if isModelEntry(e) then choose({ kind = "models" }) else choose({ kind = "module", id = e.m }) end
            end
        end
        if #list > 8 then
            local b = K.Button(body, "All " .. #list .. " changed settings", function() choose({ kind = "changed" }) end, { small = true })
            b:Dock(TOP)
            b:DockMargin(0, K.S(4), K.S(10), 0)
        end
        heading(body, "How it works")
        empty(body, "Changes wait in the bar at the bottom until you press Apply. Reset puts a setting back to the host file's value or the default. "
            .. "An amber edge marks a change not applied yet, a blue edge one changed here, red one the server refused.")
    end

    fill = function()
        body:Clear()
        refreshers = {}
        if not S.list then
            buildHead("Loading", nil)
            empty(body, "Loading settings...")
            return
        end
        if #S.list == 0 then
            buildHead("Server settings", nil)
            empty(body, "Nothing to show: you may not have the rhylib.settings permission.")
            return
        end

        local q = searchText
        if q ~= "" then
            local list = entriesOf(function(e) return matches(e, q) end)
            buildHead("Search", #list .. " match" .. (#list == 1 and "" or "es") .. " for \"" .. q .. "\"")
            local lastM
            for i, e in ipairs(list) do
                if i > MAX_ROWS then empty(body, "More matches: narrow the search.") break end
                if e.m ~= lastM then
                    lastM = e.m
                    heading(body, prettyModule(e.m))
                end
                addRow(body, e, refreshers, false)
            end
            if #list == 0 then empty(body, "Nothing matches.") end
            return
        end

        if view.kind == "home" then return fillHome() end

        if view.kind == "models" then
            -- Every model: the registry's ("models") and model settings of
            -- every module, by group, one fold each.
            local list = entriesOf(isModelEntry)
            local by, order = {}, {}
            for _, e in ipairs(list) do
                local g = e.m == "models" and ((e.x and e.x.group) or "Other") or ("Settings: " .. prettyModule(e.m))
                if not by[g] then by[g] = {} order[#order + 1] = g end
                table.insert(by[g], e)
            end
            table.sort(order)
            for _, g in ipairs(order) do
                table.sort(by[g], function(a, b) return titleOf(a) < titleOf(b) end)
            end
            buildHead("Model overrides", "Swap any model the suite uses for one you have installed. Hover a picture to turn it.")
            for _, g in ipairs(order) do
                local key = idOf("models", g)
                local f = fold(g, tostring(#by[g]), openSec[key] == true, function(o) openSec[key] = o end)
                -- (pictures are made only for folds that are open)
                local built = false
                local function build1()
                    if built then return end
                    built = true
                    for _, e in ipairs(by[g]) do addRow(f.body, e, refreshers, false) end
                    f:InvalidateLayout(true)
                    if IsValid(f:GetParent()) then f:GetParent():InvalidateLayout() end
                end
                if f.open then build1() end
                local old = f.Think
                function f:Think()
                    if old then old(self) end
                    if self.open and not built then build1() end
                end
            end
            if #list == 0 then empty(body, "No models found yet: the list fills in once the map has loaded.") end
            return
        end

        if view.kind == "changed" then
            local list = entriesOf(function(e) return e.o ~= nil end)
            buildHead("Changed settings", #list .. " changed here (Reset puts one back)")
            local lastM
            for _, e in ipairs(list) do
                if e.m ~= lastM then
                    lastM = e.m
                    heading(body, prettyModule(e.m))
                end
                addRow(body, e, refreshers, false)
            end
            if #list == 0 then empty(body, "Nothing has been changed from the server settings page yet.") end
            return
        end

        -- A module: one fold per section (the first open), Advanced last.
        local m = view.id
        local list = entriesOf(function(e) return e.m == m end)
        if #list == 0 then
            view = { kind = "home" }
            return fill()
        end
        local normal, adv = {}, {}
        for _, e in ipairs(list) do
            if isAdvanced(e) and not isModelEntry(e) then adv[#adv + 1] = e else normal[#normal + 1] = e end
        end
        local d = described(m)
        local by, order = grouped(normal, d and d.order)
        buildHead(prettyModule(m), #list .. " setting" .. (#list == 1 and "" or "s"))
        for i, s in ipairs(order) do
            local key = idOf(m, s)
            local open = openSec[key]
            if open == nil then open = (i == 1) or #order <= 2 end
            local changedN = 0
            for _, e in ipairs(by[s]) do if e.o ~= nil then changedN = changedN + 1 end end
            local count = #by[s] .. (changedN > 0 and ("  ·  " .. changedN .. " changed") or "")
            local f = fold(#order == 1 and (s == "General" and prettyModule(m) or s) or s, count, open, function(o) openSec[key] = o end)
            for _, e in ipairs(by[s]) do addRow(f.body, e, refreshers, false) end
        end
        if #adv > 0 then
            local key = idOf(m, "\1advanced")
            local f = fold("Advanced", #adv .. "  ·  lists, tables and positions (JSON / x y z)", openSec[key] == true,
                function(o) openSec[key] = o end, true)
            for _, e in ipairs(adv) do addRow(f.body, e, refreshers, false) end
        end
    end

    -- (only while this page is open: the panels own the callbacks)
    S.onList = function()
        if not IsValid(body) then return end
        buildSide()
        fill()
    end
    S.onChanged = function(m, k)
        errors[idOf(m, k)] = nil
        if not IsValid(body) then return end
        -- (the map-change bar, the Changed list and the counts follow a change)
        local modelChange = false
        for _, e in ipairs(S.list or {}) do
            if e.m == m and e.k == k then modelChange = isModelEntry(e) break end
        end
        if modelChange or view.kind == "changed" then
            timer.Create("Rhylib.Menus.SettingsRefill", 0.1, 1, function()
                if not (IsValid(body) and searchText == "") then return end
                local y = body:GetVBar():GetScroll()
                fill()
                timer.Simple(0, function() if IsValid(body) then body:GetVBar():SetScroll(y) end end)
            end)
        end
        local r = refreshers[idOf(m, k)]
        if r then r() end
    end
    S.onError = function(m, k, why)
        errors[idOf(m, k)] = { why = why, at = RealTime() }
        if not IsValid(body) then return false end
        surface.PlaySound("buttons/button10.wav")
        return refreshers[idOf(m, k)] ~= nil
    end

    if S.list then buildSide() end
    fill()
    S.Request()   -- (always fresh: base values may differ from last time)
end

Menus.AddPage("serversettings", {
    title = "Server settings",
    order = 230,
    section = "staff",
    icon = "server",
    badge = function() local n = Menus.SettingsPending() return n > 0 and n or nil end,
    visible = function()
        local me = LocalPlayer()
        if not IsValid(me) then return false end
        local A = Rhylib.Admin
        if A and A.Has then return A.Has(me, "rhylib.settings", "superadmin") end
        return me:IsSuperAdmin()
    end,
    -- (leaving with changes waiting: Apply / Discard / Stay)
    beforeLeave = function(go)
        if Menus.SettingsPending() == 0 then return true end
        askLeave(go)
        return false
    end,
    build = build,
})

-- Closing the menu with changes waiting: they're kept, and you're told.
Rhylib.Hook.Add("Think", "menus.hostsettings.closed", function()
    local open = IsValid(Menus.pause) and Menus.pause.pageId == "serversettings"
    if Menus.hsWasOpen and not open and not IsValid(Menus.pause) and Menus.SettingsPending() > 0 then
        local n = Menus.SettingsPending()
        if Rhylib.Notify then
            Rhylib.Notify(nil, n .. " server setting change" .. (n == 1 and " is" or "s are") .. " waiting: open Server settings and press Apply", "info", "Settings")
        end
    end
    Menus.hsWasOpen = open
end)
