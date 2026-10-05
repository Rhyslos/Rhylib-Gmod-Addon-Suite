--[[
    Spawn window (Menus.Spawn): our restyled Q menu, opened from the
    toolgun's R (rhylib_toolgun). Tabs: other addons' first (the toolgun
    adds "Rhylib"), then Props (spawnlists), Entities, Weapons, NPCs,
    Vehicles and Tools (with the tool's own settings panel). Everything
    spawns through the normal sandbox commands, so the server's spawn
    rights still apply.

    Kept between openings (hidden, not removed), so tabs, scroll and the
    chosen tool stay. The mouse is free but the keyboard stays with the
    game (walk while it's open) until you click a text box.

    Menus.Spawn.AddTab(id, { title, order, build(body), onShow(body),
        search(body, text) }) adds a tab; Open / Close / IsOpen.
]]

local Menus = Rhylib.Menus
Menus.Spawn = Menus.Spawn or {}
local SP = Menus.Spawn
SP.tabs = SP.tabs or {}

local K = Menus.Kit
local C = K.C

-- "#tool.weld.name" style names to text.
local function L(s)
    s = tostring(s or "")
    if string.sub(s, 1, 1) == "#" then return language.GetPhrase(string.sub(s, 2)) end
    return s
end
SP.L = L

local function lower(s) return string.lower(L(s)) end

-- Icon materials, cached (false = none).
local mats = {}
local function iconMat(paths)
    for _, p in ipairs(paths) do
        if p and p ~= "" then
            local m = mats[p]
            if m == nil then
                local mat = Material(p, "smooth")
                m = (mat and not mat:IsError()) and mat or false
                mats[p] = m
            end
            if m then return m end
        end
    end
    return nil
end
SP.IconMat = iconMat

function SP.AddTab(id, def)
    def.id = id
    if not SP.tabs[id] then SP.dirty = true end   -- (a re-add of the same tab needs no rebuild)
    SP.tabs[id] = def
end

--------------------------------------------------------------------------
-- Tiles and catalogue tabs
--------------------------------------------------------------------------

-- A square tile: icon (or initials) and name. it = { name, mat, run,
-- menu(m), admin, selected() , tip }.
function SP.Tile(parent, it)
    local S = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetSize(S(104), S(104))
    if it.tip then b:SetTooltip(it.tip) end
    local name = L(it.name)
    local initials = string.upper(string.sub(name, 1, 2))
    function b:Paint(w, h)
        local sel = it.selected and it.selected()
        surface.SetDrawColor(self:IsHovered() and C.rowHover or C.row)
        surface.DrawRect(0, 0, w, h)
        local is = h - S(26)
        if it.mat then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(it.mat)
            local pad = S(8)
            surface.DrawTexturedRect((w - is) * 0.5 + pad, pad, is - pad * 2, is - pad * 2)
        else
            draw.SimpleText(initials, K.Font(26, 700), w * 0.5, is * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        if it.admin then
            draw.SimpleText("ADMIN", K.Font(10, 700), w - S(4), S(3), C.warn, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
        surface.SetDrawColor(C.header)
        surface.DrawRect(0, h - S(24), w, S(24))
        draw.SimpleText(K.Fit(name, K.Font(12, 600), w - S(8)), K.Font(12, 600), w * 0.5, h - S(12), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(sel and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h, sel and 2 or 1)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclickrelease.wav")
        if it.run then it.run() end
    end
    function b:DoRightClick()
        if not (it.menu or (it.spec and SP.PickForTool)) then return end
        local m = K.Menu()
        SP.AddToolOption(m, it.spec)
        if it.menu then it.menu(m) end
        m:Open()
    end
    return b
end

-- "Spawn with Rhy's toolgun" (rhylib_toolgun sets SP.PickForTool):
-- spec = { kind = prop|entity|npc|vehicle|weapon, name, skin, body, wep, label }.
function SP.AddToolOption(m, spec)
    if not (spec and SP.PickForTool) then return end
    m:AddOption("Spawn with Rhy's toolgun", function() SP.PickForTool(spec) end)
    m:AddSpacer()
end

-- A model tile (props): the engine's spawn icon with our outline.
function SP.ModelTile(parent, model, skin, body, run)
    local S = K.S
    local ic = vgui.Create("SpawnIcon", parent)
    ic:SetSize(S(84), S(84))
    ic:SetModel(model, skin or 0, body ~= "" and body or nil)
    ic:SetTooltip(model)
    ic.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        run()
    end
    ic.OpenMenu = function()
        local m = K.Menu()
        SP.AddToolOption(m, { kind = "prop", name = model, skin = skin or 0, body = body or "", label = string.GetFileFromFilename(model) })
        m:AddOption("Copy model path", function() SetClipboardText(model) end)
        m:Open()
    end
    function ic:PaintOver(w, h)
        surface.SetDrawColor(self:IsHovered() and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    return ic
end

-- A tab with categories on the left and tiles on the right.
-- getItems() = { { cat, name, ...tile fields } } (built when first shown).
-- A search shows matches from every category.
function SP.CatalogueTab(getItems)
    local tab = {}
    function tab.build(body)
        local S = K.S
        local items = getItems()
        local cats, order = {}, {}
        for _, it in ipairs(items) do
            local c = L(it.cat or "Other")
            if not cats[c] then cats[c] = {} order[#order + 1] = c end
            table.insert(cats[c], it)
        end
        table.sort(order, function(a, b) return string.lower(a) < string.lower(b) end)
        for _, c in ipairs(order) do
            table.sort(cats[c], function(a, b) return lower(a.name) < lower(b.name) end)
        end

        local side = K.Scroll(body)
        side:Dock(LEFT)
        side:SetWide(S(220))
        side:DockMargin(0, 0, S(10), 0)
        local grid = K.Scroll(body)
        grid:Dock(FILL)
        local layout = vgui.Create("DIconLayout", grid)
        layout:Dock(TOP)
        layout:SetSpaceX(S(6))
        layout:SetSpaceY(S(6))
        layout:DockMargin(0, 0, S(8), 0)

        local chosen = order[1]
        local query = ""
        local function fill()
            layout:Clear()
            local n = 0
            for _, c in ipairs(order) do
                if query ~= "" or c == chosen then
                    for _, it in ipairs(cats[c]) do
                        if query == "" or string.find(lower(it.name), query, 1, true)
                            or (it.extra and string.find(string.lower(it.extra), query, 1, true)) then
                            layout:Add(SP.Tile(layout, it))
                            n = n + 1
                        end
                    end
                end
            end
            if n == 0 then
                local l = K.Label(layout, query ~= "" and "Nothing matches." or "Nothing here.", 14, nil, C.textDim)
                l:SetWide(S(300))
                layout:Add(l)
            end
            layout:InvalidateLayout(true)
            grid:GetVBar():SetScroll(0)
        end
        for _, c in ipairs(order) do
            local b = K.Button(side, c .. "  (" .. #cats[c] .. ")", function()
                chosen = c
                fill()
            end, { align = "left", small = true, selected = function() return query == "" and chosen == c end })
            b:Dock(TOP)
            b:DockMargin(0, 0, S(8), S(3))
        end
        if #order == 0 then K.Label(side, "Nothing installed.", 13, nil, C.textDim):Dock(TOP) end
        body.search = function(q)
            query = string.lower(q or "")
            fill()
        end
        fill()
    end
    function tab.search(body, q) if body.search then body.search(q) end end
    return tab
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- The window is kept in SP.win (not a local), so a Lua refresh doesn't orphan it.

local function sortedTabs()
    local list = {}
    for _, t in pairs(SP.tabs) do list[#list + 1] = t end
    table.sort(list, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
        return a.id < b.id
    end)
    return list
end

local function build()
    if IsValid(SP.win) then
        -- (hand tool settings panels back first: sandbox keeps them and
        -- would hand out a removed panel otherwise)
        for _, b in pairs(SP.win.bodies or {}) do
            if IsValid(b) and IsValid(b.panelScroll) then
                for _, ch in ipairs(b.panelScroll:GetCanvas():GetChildren()) do
                    if ch.ClassName == "ControlPanel" or ch.GetInitialized then
                        ch:SetVisible(false)
                        ch:SetParent(vgui.GetWorldPanel())
                    end
                end
            end
        end
        SP.win:Remove()
    end
    local S = K.S
    local f = vgui.Create("EditablePanel")
    SP.win = f
    f:SetSize(math.min(S(1500), ScrW() - S(80)), math.min(S(900), ScrH() - S(80)))
    f:Center()
    f:SetVisible(false)
    f:DockPadding(S(12), S(46), S(12), S(12))
    f.bodies = {}
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Spawn", sub = "R: close · hold R: peek · R twice: the old Q menu · Esc: close", ticks = "all", header = S(34) })
    end
    -- (clicking the window takes the keyboard back from a text box)
    function f:OnMousePressed()
        local fp = vgui.GetKeyboardFocus()
        if IsValid(fp) then fp:KillFocus() end
        self:SetKeyboardInputEnabled(false)
    end

    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(S(32))
    bar:DockMargin(0, 0, 0, S(10))
    bar.Paint = nil
    local search = K.TextEntry(bar, "Search this tab...")
    search:Dock(RIGHT)
    search:SetWide(S(280))
    search:SetUpdateOnType(true)
    f.searchBox = search

    local content = vgui.Create("DPanel", f)
    content:Dock(FILL)
    content.Paint = nil

    local function show(id)
        f.tabId = id
        for tid, b in pairs(f.bodies) do b:SetVisible(tid == id) end
        local def = SP.tabs[id]
        if not def then return end
        local body = f.bodies[id]
        if not IsValid(body) then
            body = vgui.Create("DPanel", content)
            body:Dock(FILL)
            body.Paint = nil
            f.bodies[id] = body
            local ok, err = pcall(def.build, body)
            if not ok then
                K.Label(body, "This tab failed to build: " .. tostring(err), 13, nil, C.bad):Dock(TOP)
                ErrorNoHalt("[Rhylib] spawn tab " .. id .. ": " .. tostring(err) .. "\n")
            end
        end
        body:SetVisible(true)
        if def.onShow then def.onShow(body) end
        search:SetText(body.lastSearch or "")
    end
    f.ShowTab = show

    function search:OnValueChange(v)
        local body = f.bodies[f.tabId]
        local def = SP.tabs[f.tabId]
        if not (IsValid(body) and def and def.search) then return end
        if v == (body.lastSearch or "") then return end
        body.lastSearch = v
        def.search(body, v)
    end

    for _, def in ipairs(sortedTabs()) do
        surface.SetFont(K.Font(13, 700))
        local b = K.Button(bar, def.title, function() show(def.id) end,
            { selected = function() return f.tabId == def.id end })
        b:Dock(LEFT)
        b:SetWide(surface.GetTextSize(string.upper(def.title)) + S(36))
        b:DockMargin(0, 0, S(4), 0)
    end
    SP.dirty = false
    show((SP.lastTab and SP.tabs[SP.lastTab]) and SP.lastTab or sortedTabs()[1].id)
end

function SP.IsOpen() return IsValid(SP.win) and SP.win:IsVisible() end

function SP.Open()
    if not IsValid(SP.win) or SP.dirty or SP.win.builtW ~= ScrW() or SP.win.builtH ~= ScrH() then
        build()
        SP.win.builtW, SP.win.builtH = ScrW(), ScrH()
    end
    SP.win:SetVisible(true)
    SP.win:MakePopup()
    SP.win:SetKeyboardInputEnabled(false)
    local def = SP.tabs[SP.win.tabId]
    if def and def.onShow and IsValid(SP.win.bodies[SP.win.tabId]) then def.onShow(SP.win.bodies[SP.win.tabId]) end
end

function SP.Close()
    if not SP.IsOpen() then return false end
    SP.lastTab = SP.win.tabId
    CloseDermaMenus()
    local fp = vgui.GetKeyboardFocus()
    if IsValid(fp) and fp:HasParent(SP.win) then fp:KillFocus() end
    SP.win:SetKeyboardInputEnabled(false)
    SP.win:SetMouseInputEnabled(false)
    SP.win:SetVisible(false)
    return true
end

-- Esc closes it first.
Menus.RegisterCloser("spawn", function() return SP.Close() end)

-- Text boxes inside (search, tool settings) get the keyboard while focused.
Rhylib.Hook.Add("OnTextEntryGetFocus", "menus.spawn", function(p)
    if SP.IsOpen() and IsValid(p) and p:HasParent(SP.win) then SP.win:SetKeyboardInputEnabled(true) end
end)
Rhylib.Hook.Add("OnTextEntryLoseFocus", "menus.spawn", function(p)
    if SP.IsOpen() and IsValid(p) and p:HasParent(SP.win) then SP.win:SetKeyboardInputEnabled(false) end
end)

--------------------------------------------------------------------------
-- The sandbox tabs
--------------------------------------------------------------------------

local function adminOnly(t) return t.AdminOnly and true or false end

-- The NPC's weapon: the player's choice, else one of its own (as sandbox).
function SP.NpcWeapon(n)
    local wcv = GetConVar("gmod_npcweapon")
    local w = wcv and wcv:GetString() or ""
    if w == "" and n and istable(n.Weapons) and #n.Weapons > 0 then w = table.Random(n.Weapons) or "" end
    return w
end

SP.AddTab("entities", SP.CatalogueTab(function()
    local items = {}
    for class, e in pairs(list.Get("SpawnableEntities") or {}) do
        local cls = e.ClassName or class
        items[#items + 1] = {
            cat = e.Category or "Other", name = e.PrintName or cls, extra = cls, admin = adminOnly(e), tip = cls,
            mat = iconMat({ e.IconOverride, "entities/" .. cls .. ".png", "vgui/entities/" .. cls }),
            run = function() RunConsoleCommand("gm_spawnsent", class) end,
            spec = { kind = "entity", name = class, label = L(e.PrintName or cls) },
            menu = function(m) m:AddOption("Copy class name", function() SetClipboardText(cls) end) end,
        }
    end
    return items
end))
SP.tabs.entities.title, SP.tabs.entities.order = "Entities", 20

SP.AddTab("weapons", SP.CatalogueTab(function()
    local items = {}
    for _, w in pairs(list.Get("Weapon") or {}) do
        if w.Spawnable and w.ClassName then
            local cls = w.ClassName
            items[#items + 1] = {
                cat = w.Category or "Other", name = w.PrintName or cls, extra = cls, admin = adminOnly(w), tip = cls .. "\nClick: give · right-click: more",
                mat = iconMat({ w.IconOverride, "entities/" .. cls .. ".png", "vgui/entities/" .. cls }),
                run = function() RunConsoleCommand("gm_giveswep", cls) end,
                spec = { kind = "weapon", name = cls, label = L(w.PrintName or cls) },
                menu = function(m)
                    m:AddOption("Give to me", function() RunConsoleCommand("gm_giveswep", cls) end)
                    m:AddOption("Spawn on the ground", function() RunConsoleCommand("gm_spawnswep", cls) end)
                    m:AddOption("Copy class name", function() SetClipboardText(cls) end)
                end,
            }
        end
    end
    return items
end))
SP.tabs.weapons.title, SP.tabs.weapons.order = "Weapons", 30

SP.AddTab("npcs", SP.CatalogueTab(function()
    local items = {}
    for key, n in pairs(list.Get("NPC") or {}) do
        items[#items + 1] = {
            cat = n.Category or "Other", name = n.Name or key, extra = key, admin = adminOnly(n), tip = key,
            mat = iconMat({ n.IconOverride, "entities/" .. key .. ".png", "vgui/entities/" .. key }),
            run = function() RunConsoleCommand("gmod_spawnnpc", key, SP.NpcWeapon(n)) end,
            spec = { kind = "npc", name = key, label = L(n.Name or key), npc = n },
        }
    end
    return items
end))
SP.tabs.npcs.title, SP.tabs.npcs.order = "NPCs", 40

SP.AddTab("vehicles", SP.CatalogueTab(function()
    local items = {}
    for key, v in pairs(list.Get("Vehicles") or {}) do
        items[#items + 1] = {
            cat = v.Category or "Other", name = v.Name or key, extra = key, admin = adminOnly(v), tip = key,
            mat = iconMat({ v.IconOverride, "entities/" .. key .. ".png", "vgui/entities/" .. key }),
            run = function() RunConsoleCommand("gm_spawnvehicle", key) end,
            spec = { kind = "vehicle", name = key, label = L(v.Name or key) },
        }
    end
    return items
end))
SP.tabs.vehicles.title, SP.tabs.vehicles.order = "Vehicles", 50

-- Props: a tree with two groups, collapsible: "Base game" (the spawnlists
-- and the mounted games' model folders) and "Workshop & addons" (every
-- mounted Workshop addon with models, and local addons in addons/).
local open = SP.propsOpen or { base = true, work = true, lists = true }
SP.propsOpen = open
local modelCache = {}   -- [node id] = { models } (addons, listed once)

local MAX_TILES = 600

-- Every .mdl under a folder (path ID), up to a cap.
local function findModels(folder, pathId, out, cap)
    out = out or {}
    if #out >= cap then return out end
    local files, dirs = file.Find(folder .. "*", pathId)
    for _, f in ipairs(files or {}) do
        if string.sub(f, -4) == ".mdl" then
            out[#out + 1] = folder .. f
            if #out >= cap then return out end
        end
    end
    for _, d in ipairs(dirs or {}) do findModels(folder .. d .. "/", pathId, out, cap) end
    return out
end

-- Models in one folder only (games are browsed folder by folder).
local function folderModels(folder, pathId)
    local out = {}
    local files = file.Find(folder .. "*.mdl", pathId)
    for _, f in ipairs(files or {}) do out[#out + 1] = folder .. f end
    return out
end

local function folderNode(id, label, folder, pathId)
    return {
        id = id, label = label,
        kids = function()
            local _, dirs = file.Find(folder .. "*", pathId)
            local list = {}
            for _, d in ipairs(dirs or {}) do
                list[#list + 1] = folderNode(id .. "/" .. d, d, folder .. d .. "/", pathId)
            end
            return list
        end,
        models = function() return folderModels(folder, pathId) end,
    }
end

-- One spawnlist table as a tree (ids are only unique within a table).
local function listTree(tbl, prefix, all)
    local lists = {}
    for _, sl in pairs(tbl or {}) do
        lists[#lists + 1] = sl
        all[#all + 1] = sl
    end
    local kids, roots = {}, {}
    for _, sl in ipairs(lists) do
        local p = tonumber(sl.parentid) or 0
        if p == 0 then roots[#roots + 1] = sl else kids[p] = kids[p] or {} table.insert(kids[p], sl) end
    end
    local function byId(x, y) return (tonumber(x.id) or 0) < (tonumber(y.id) or 0) end
    local seen = {}
    local function make(sl)
        if seen[sl] then return nil end   -- (a broken parent loop)
        seen[sl] = true
        local ch = kids[tonumber(sl.id) or -1]
        local node = { id = prefix .. tostring(sl.id) .. ":" .. tostring(sl.name), label = L(sl.name or "?"), sl = sl }
        if ch then
            table.sort(ch, byId)
            local list = {}
            for _, c in ipairs(ch) do list[#list + 1] = make(c) end   -- (nil from a loop just ends the list)
            node.kids = list
        end
        return node
    end
    table.sort(roots, byId)
    local out = {}
    for _, r in ipairs(roots) do out[#out + 1] = make(r) end
    return out
end

local function spawnlistNodes()
    local all = {}
    -- (filled when the Q menu is first shown; that's off here, so ask)
    local okT, tbl = pcall(spawnmenu.GetPropTable)
    if okT and istable(tbl) and next(tbl) == nil then
        pcall(hook.Run, "PopulatePropMenu")
        okT, tbl = pcall(spawnmenu.GetPropTable)
    end
    local nodes = listTree(okT and tbl or {}, "s:", all)
    if spawnmenu.GetCustomPropTable then
        local okC, ctbl = pcall(spawnmenu.GetCustomPropTable)
        local custom = listTree(okC and ctbl or {}, "c:", all)
        if #custom > 0 then nodes[#nodes + 1] = { id = "addonlists", label = "Addon spawnlists", kids = custom } end
    end
    return nodes, all
end

local function gameNodes()
    local out = {}
    local ok, games = pcall(engine.GetGames)
    for _, g in ipairs(ok and games or {}) do
        if g.mounted and g.folder then
            out[#out + 1] = folderNode("g:" .. g.folder, L(g.title or g.folder), "models/", g.folder)
        end
    end
    table.sort(out, function(x, y) return string.lower(x.label) < string.lower(y.label) end)
    return out
end

local function addonNodes()
    local out = {}
    local ok, addons = pcall(engine.GetAddons)
    for _, a in ipairs(ok and addons or {}) do
        if a.mounted and (tonumber(a.models) or 0) > 0 and a.title then
            local title = a.title
            out[#out + 1] = {
                id = "w:" .. tostring(a.wsid or title), label = title .. "  (" .. a.models .. ")", search = true,
                models = function() return findModels("models/", title, nil, MAX_TILES * 4) end,
            }
        end
    end
    -- Local (legacy) addons: folders in addons/ with models.
    local _, dirs = file.Find("addons/*", "MOD")
    for _, d in ipairs(dirs or {}) do
        local base = "addons/" .. d .. "/"
        local _, md = file.Find(base .. "models", "MOD")
        if md and #md > 0 then
            out[#out + 1] = {
                id = "l:" .. d, label = d .. "  (local)", search = true,
                models = function()
                    local list = findModels(base .. "models/", "MOD", nil, MAX_TILES * 4)
                    -- (spawn by the game path, not the addon's folder)
                    for i, m in ipairs(list) do list[i] = string.sub(m, #base + 1) end
                    return list
                end,
            }
        end
    end
    table.sort(out, function(x, y) return string.lower(x.label) < string.lower(y.label) end)
    return out
end

SP.AddTab("props", {
    title = "Props", order = 10,
    build = function(body)
        local S = K.S
        modelCache = {}   -- (re-listed each build: addons can mount later)
        local slNodes, allLists = spawnlistNodes()
        local workKids
        local tree = {
            { id = "base", label = "Base game", group = true, kids = {
                { id = "lists", label = "Spawnlists", kids = slNodes },
                { id = "games", label = "Games", kids = gameNodes },
            } },
            { id = "work", label = "Workshop & addons", group = true, kids = function()
                workKids = workKids or addonNodes()
                return workKids
            end },
        }

        local side = K.Scroll(body)
        side:Dock(LEFT)
        side:SetWide(S(260))
        side:DockMargin(0, 0, S(10), 0)
        local grid = K.Scroll(body)
        grid:Dock(FILL)
        local layout = vgui.Create("DIconLayout", grid)
        layout:Dock(TOP)
        layout:SetSpaceX(S(4))
        layout:SetSpaceY(S(4))
        layout:DockMargin(0, 0, S(8), 0)

        local chosen = slNodes[1]
        local query = ""

        local function kidsOf(node)
            if isfunction(node.kids) then
                node.kidsCache = node.kidsCache or node.kids()
                return node.kidsCache
            end
            return node.kids
        end
        local function modelsOf(node)
            if not node.models then return nil end
            modelCache[node.id] = modelCache[node.id] or node.models()
            return modelCache[node.id]
        end

        local function note(text)
            local l = K.Label(layout, text, 14, nil, C.textDim)
            l.OwnLine = true
            l:SetWide(K.S(700))
            layout:Add(l)
        end
        local function header(text)
            local h = vgui.Create("DPanel", layout)
            h.OwnLine = true
            h:SetTall(S(26))
            function h:Paint(w, hh)
                draw.SimpleText(string.upper(text), K.Font(13, 700), 0, hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 100)
                surface.DrawRect(0, hh - 2, w, 1)
            end
            layout:Add(h)
        end
        local function modelTile(model, skin, bg)
            layout:Add(SP.ModelTile(layout, model, skin, bg, function()
                RunConsoleCommand("gm_spawn", model, tostring(skin or 0), bg or "")
            end))
        end

        -- Spawnlist contents in key order, as sandbox reads them.
        local function ordered(sl)
            local keys, out = {}, {}
            for k in pairs(sl.contents or {}) do keys[#keys + 1] = k end
            table.sort(keys, function(x, y) return (tonumber(x) or 0) < (tonumber(y) or 0) end)
            for _, k in ipairs(keys) do out[#out + 1] = sl.contents[k] end
            return out
        end
        local CMD = { entity = "gm_spawnsent", weapon = "gm_giveswep", npc = "gmod_spawnnpc", vehicle = "gm_spawnvehicle" }
        local function addSpawnlist(sl, n)
            for _, c in ipairs(ordered(sl)) do
                if n >= MAX_TILES then return n end
                if c.type == "model" and c.model then
                    if query == "" or string.find(string.lower(c.model), query, 1, true) then
                        -- (saved bodygroups are "B" .. digits)
                        modelTile(c.model, c.skin, c.body and string.Trim(tostring(c.body), "B") or "")
                        n = n + 1
                    end
                elseif c.type == "header" and query == "" then
                    header(L(c.text))
                elseif CMD[c.type] and c.spawnname then
                    local name = L(c.nicename or c.spawnname)
                    if query == "" or string.find(string.lower(name), query, 1, true) then
                        local sn, kind = c.spawnname, c.type
                        local npc = kind == "npc" and (list.Get("NPC") or {})[sn] or nil
                        layout:Add(SP.Tile(layout, { name = name, tip = sn,
                            mat = iconMat({ c.material, "entities/" .. sn .. ".png" }),
                            spec = { kind = kind, name = sn, label = name, npc = npc },
                            run = function()
                                if kind == "npc" then RunConsoleCommand(CMD[kind], sn, SP.NpcWeapon(npc))
                                else RunConsoleCommand(CMD[kind], sn) end
                            end }))
                        n = n + 1
                    end
                end
            end
            return n
        end
        local function addModels(list, n)
            for _, m in ipairs(list or {}) do
                if n >= MAX_TILES then return n end
                if query == "" or string.find(string.lower(m), query, 1, true) then
                    modelTile(m, 0, "")
                    n = n + 1
                end
            end
            return n
        end

        local function fill()
            layout:Clear()
            local n = 0
            if query ~= "" then
                -- (spawnlists and every Workshop/local addon; game folders are too big)
                for _, sl in ipairs(allLists) do n = addSpawnlist(sl, n) end
                workKids = workKids or addonNodes()
                for _, node in ipairs(workKids) do
                    if n >= MAX_TILES then break end
                    n = addModels(modelsOf(node), n)
                end
                if n == 0 then note("No model matches. (Search covers the spawnlists and addons; games: open their folders.)") end
            elseif chosen and chosen.sl then
                n = addSpawnlist(chosen.sl, n)
                if n == 0 and next(chosen.sl.contents or {}) == nil then note("This spawnlist is empty.") end
            elseif chosen and chosen.models then
                local list = modelsOf(chosen)
                n = addModels(list, n)
                if n == 0 then note(chosen.kids and "No models in this folder: open a folder below it." or "No models found.") end
            end
            if n >= MAX_TILES then note("Showing the first " .. MAX_TILES .. ". Search to narrow it down.") end
            layout:InvalidateLayout(true)
            grid:GetVBar():SetScroll(0)
        end

        local buildSide
        local function addRow(node, depth)
            local hasKids = istable(node.kids) and #node.kids > 0
                or (isfunction(node.kids) and (node.kidsCache == nil or #node.kidsCache > 0))
            local isOpen = open[node.id]
            local label = node.label
            if hasKids then label = (isOpen and "−  " or "+  ") .. label end
            local b = K.Button(side, label, function()
                -- (a click opens a closed node; clicking the shown one again closes it)
                if hasKids and (chosen == node or not open[node.id] or not (node.sl or node.models)) then
                    open[node.id] = not open[node.id]
                end
                if node.sl or node.models then
                    chosen = node
                    if query == "" then fill() end
                end
                if hasKids then buildSide() end
            end, { align = "left", small = not node.group, accent = node.group,
                selected = function() return query == "" and chosen == node end })
            b:Dock(TOP)
            b:DockMargin(S(12) * depth, node.group and S(6) or 0, S(8), S(3))
            if hasKids and isOpen then
                for _, k in ipairs(kidsOf(node) or {}) do addRow(k, depth + 1) end
            end
        end
        buildSide = function()
            local y = side:GetVBar():GetScroll()
            side:Clear()
            for _, node in ipairs(tree) do addRow(node, 0) end
            side:InvalidateLayout(true)
            timer.Simple(0, function() if IsValid(side) then side:GetVBar():SetScroll(y) end end)
        end
        buildSide()

        -- (after a short pause in typing: a search can list a lot)
        body.search = function(q)
            query = string.lower(q or "")
            timer.Create("Rhylib.Spawn.PropSearch", 0.35, 1, function() if IsValid(layout) then fill() end end)
        end
        -- (headers need the grid's width, known after the first layout)
        timer.Simple(0, function() if IsValid(layout) then fill() end end)
    end,
    search = function(body, q) if body.search then body.search(q) end end,
})

-- Tools: the tool list on the left, the chosen tool's own settings panel
-- (the same panel the Q menu shows) on the right.
SP.AddTab("tools", {
    title = "Tools", order = 60,
    build = function(body)
        local S = K.S
        local side = K.Scroll(body)
        side:Dock(LEFT)
        side:SetWide(S(260))
        side:DockMargin(0, 0, S(10), 0)
        local right = vgui.Create("DPanel", body)
        right:Dock(FILL)
        function right:Paint(w, h)
            surface.SetDrawColor(C.row)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        right:DockPadding(S(8), S(8), S(8), S(8))
        local panelScroll = K.Scroll(right)
        panelScroll:Dock(FILL)
        body.panelScroll = panelScroll
        local hint = K.Label(panelScroll, "Pick a tool on the left. Its settings show here, like in the Q menu.", 14, nil, C.textDim)
        hint:Dock(TOP)

        local current, pickedName
        local function attach(cp)
            if not IsValid(cp) then return end
            -- (hand the old one back, as the Q menu does, so it isn't removed)
            for _, ch in ipairs(panelScroll:GetCanvas():GetChildren()) do
                if ch ~= cp and ch ~= hint then
                    ch:SetVisible(false)
                    ch:SetParent(vgui.GetWorldPanel())
                end
            end
            hint:SetVisible(false)
            if cp:GetParent() ~= panelScroll:GetCanvas() then panelScroll:AddItem(cp) end
            cp:Dock(TOP)
            cp:SetVisible(true)
            current = cp
        end
        body.reattach = function() if IsValid(current) then attach(current) end end

        local function pick(item)
            pickedName = item.ItemName
            if item.Command and item.Command ~= "" then LocalPlayer():ConCommand(item.Command) end
            if not (controlpanel and controlpanel.Get) then return end
            local ok, cp = pcall(controlpanel.Get, item.ItemName)
            if not (ok and IsValid(cp)) then return end
            if cp.GetInitialized and not cp:GetInitialized() and cp.FillViaTable then
                pcall(cp.FillViaTable, cp, { Text = item.Text, ControlPanelBuildFunction = item.CPanelFunction, Controls = item.Controls })
            end
            attach(cp)
        end

        local rows = {}
        local okT, tabs = pcall(spawnmenu.GetTools)
        for _, t in ipairs(okT and tabs or {}) do
            local h = K.Heading(side, L(t.Label or t.Name or "Tools"))
            h:Dock(TOP)
            h:DockMargin(0, S(6), S(8), S(4))
            rows[#rows + 1] = { head = h }
            for _, cat in ipairs(t.Items or {}) do
                local cl = K.Label(side, string.upper(L(cat.Text or cat.ItemName or "")), 12, 700, C.label)
                cl:Dock(TOP)
                cl:DockMargin(S(2), S(6), S(8), S(2))
                rows[#rows + 1] = { head = cl }
                local items = {}
                for _, item in ipairs(cat) do items[#items + 1] = item end
                table.sort(items, function(a, b) return lower(a.Text) < lower(b.Text) end)
                for _, item in ipairs(items) do
                    local text = L(item.Text or item.ItemName)
                    local b = K.Button(side, text, function() pick(item) end, { align = "left", small = true, selected = function()
                        if item.Command and string.find(item.Command, "gmod_tool", 1, true) then
                            local w = LocalPlayer():GetActiveWeapon()
                            local cv = GetConVar("gmod_toolmode")
                            return IsValid(w) and w:GetClass() == "gmod_tool" and cv and cv:GetString() == item.ItemName
                        end
                        return pickedName == item.ItemName
                    end })
                    b:Dock(TOP)
                    b:DockMargin(0, 0, S(8), S(2))
                    rows[#rows + 1] = { btn = b, text = string.lower(text) }
                end
            end
        end
        if #rows == 0 then K.Label(side, "No tools found.", 13, nil, C.textDim):Dock(TOP) end
        body.search = function(q)
            q = string.lower(q or "")
            for _, r in ipairs(rows) do
                if r.head then r.head:SetVisible(q == "") end
                if r.btn then r.btn:SetVisible(q == "" or string.find(r.text, q, 1, true) ~= nil) end
            end
            side:InvalidateLayout()
            side:GetCanvas():InvalidateLayout()
        end
    end,
    -- (the real Q menu may have taken the settings panel meanwhile)
    onShow = function(body) if body.reattach then body.reattach() end end,
    search = function(body, q) if body.search then body.search(q) end end,
})
