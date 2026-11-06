--[[
    Map picker: every map on the server as a tile (thumbnail from
    maps/thumb/<map>.png when the client has it), search box, current map
    marked. Admin.MapPicker(done(map)); the staff menu's Change map row and
    a bare !map open it. Needs rhylib_menus (the kit).
    Client only. The list comes from the server (Admin.RequestList(0), at
    most 255 maps); picking a map calls done(map), which runs !map.
]]

local Admin = Rhylib.Admin

-- Thumbnail per map: Material, or false when there is none (so the file
-- checks run only once per map). Tries maps/thumb/<map>.png, then
-- maps/<map>.png, each as given and with "../" in front.
local mats = {}
local function thumb(m)
    local c = mats[m]
    if c ~= nil then return c or nil end
    local found = false
    for _, path in ipairs({ "maps/thumb/" .. m .. ".png", "maps/" .. m .. ".png" }) do
        if file.Exists(path, "GAME") then
            for _, try in ipairs({ path, "../" .. path }) do
                local mat = Material(try, "smooth")
                if mat and not mat:IsError() then found = mat break end
            end
            if found then break end
        end
    end
    mats[m] = found
    return found or nil
end

-- "rp_venator_v3" -> "rp", "venator v3"
local function split(m)
    local pre, rest = string.match(m, "^(%a+)_(.+)$")
    if not pre then return "", m end
    return string.upper(pre), string.gsub(rest, "_", " ")
end

-- Admin.MapPicker(done): opens the map window (only one at a time).
-- Returns the panel, or nil without rhylib_menus (a chat hint instead).
-- Example: Rhylib.Admin.MapPicker(function(m) Rhylib.Admin.Run("map", { m }) end)
local picker
function Admin.MapPicker(done)
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then
        chat.AddText(Color(230, 170, 70), "[Admin] ", Color(225, 225, 225), "Type !map <name> (the map list needs the UI kit)")
        return
    end
    if IsValid(picker) then picker:Remove() end
    local C, S = K.C, K.S

    local f = vgui.Create("EditablePanel")
    picker = f
    Rhylib.UI.prompts[f] = true
    f.OnRemove = function(self) Rhylib.UI.prompts[self] = nil end
    f:SetSize(math.min(S(980), ScrW() - S(40)), math.min(S(680), ScrH() - S(40)))
    f:Center()
    f:MakePopup()
    f:DockPadding(S(14), S(42), S(14), S(14))
    f.count = nil
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Change map", sub = self.count and (self.count .. " maps · current: " .. game.GetMap()) or "Loading...", ticks = "all" })
    end

    local top = vgui.Create("DPanel", f)
    top:Dock(TOP)
    top:SetTall(S(30))
    top:DockMargin(0, S(4), 0, S(10))
    top.Paint = nil
    local close = K.Button(top, "Close", function() f:Remove() end, { small = true })
    close:Dock(RIGHT)
    close:SetWide(S(90))
    local restart = K.Button(top, "Restart this map", function()
        f:Remove()
        Admin.Run("restartmap", {})
    end, { small = true })
    restart:Dock(RIGHT)
    restart:SetWide(S(160))
    restart:DockMargin(0, 0, S(8), 0)
    local search = K.TextEntry(top, "Search maps...")
    search:Dock(FILL)
    search:DockMargin(0, 0, S(8), 0)
    search:SetTall(S(30))

    local sp = K.Scroll(f)
    sp:Dock(FILL)
    local grid = vgui.Create("DIconLayout", sp)
    -- TOP, not FILL: in a scroll panel FILL takes the canvas's height, which
    -- comes from its children, so the grid stayed a few pixels tall.
    grid:Dock(TOP)
    grid:SetSpaceX(S(8))
    grid:SetSpaceY(S(8))

    local maps = {}
    local current = string.lower(game.GetMap())
    local TW, TH = S(172), S(150)

    local function pick(m)
        local menu = K.Menu()
        menu:AddOption("Change to " .. m .. " (10 s countdown)", function()
            if IsValid(f) then f:Remove() end
            done(m)
        end)
        menu:AddOption("Cancel", function() end)
        menu:Open()
    end

    local function fill()
        grid:Clear()
        local q = string.lower(string.Trim(search:GetText() or ""))
        local shown = 0
        for _, m in ipairs(maps) do
            if q == "" or string.find(m, q, 1, true) then
                shown = shown + 1
                local b = grid:Add("DButton")
                b:SetText("")
                b:SetSize(TW, TH)
                local pre, rest = split(m)
                local isCur = m == current
                function b:Paint(w, h)
                    local ih = h - S(38)
                    K.SetCol(C.row)
                    surface.DrawRect(0, 0, w, h)
                    local mat = thumb(m)
                    if mat then
                        surface.SetDrawColor(255, 255, 255, self:IsHovered() and 255 or 215)
                        surface.SetMaterial(mat)
                        -- Thumbs are square: crop to the tile's shape.
                        local v = (1 - ih / w) * 0.5
                        surface.DrawTexturedRectUV(1, 1, w - 2, ih - 1, 0, v, 1, 1 - v)
                    else
                        K.SetCol(C.header)
                        surface.DrawRect(1, 1, w - 2, ih - 1)
                        draw.SimpleText(pre ~= "" and pre or "MAP", K.Font(26, 800), w * 0.5, ih * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                    K.SetCol(isCur and C.accent or (self:IsHovered() and C.buttonHover or C.header))
                    surface.DrawRect(0, ih, w, h - ih)
                    draw.SimpleText(K.Fit(rest, K.Font(13, 700), w - S(12)), K.Font(13, 700), S(6), ih + S(11), isCur and C.bg or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(isCur and "CURRENT MAP" or K.Fit(m, K.Font(11), w - S(12)), K.Font(11, isCur and 700 or 400), S(6), ih + S(27), isCur and C.bg or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    K.SetCol(self:IsHovered() and C.accent or C.edgeDark)
                    surface.DrawOutlinedRect(0, 0, w, h)
                    return true
                end
                b:SetTooltip(m)
                function b:DoClick()
                    surface.PlaySound("ui/buttonclick.wav")
                    pick(m)
                end
            end
        end
        if shown == 0 then
            local l = grid:Add("DLabel")
            K.ThemedText(l, C.textDim, 14)
            l:SetText(#maps == 0 and "Loading maps..." or "No map matches \"" .. q .. "\"")
            l:SizeToContents()
        end
        grid:Layout()
    end
    search.OnChange = fill
    search.OnEnter = function()
        -- Enter with exactly one match picks it.
        local q = string.lower(string.Trim(search:GetText() or ""))
        local only
        for _, m in ipairs(maps) do
            if string.find(m, q, 1, true) then
                if only then return end
                only = m
            end
        end
        if only then pick(only) end
    end
    search:RequestFocus()
    fill()

    Admin.RequestList(0, "", function(rows)
        if not IsValid(f) then return end
        maps = {}
        for _, r in ipairs(rows) do maps[#maps + 1] = r[1] end
        f.count = #maps
        fill()
    end)
    return f
end

--------------------------------------------------------------------------
-- Staff > Maps page (pause menu, rhylib_menus): the current map with
-- Restart (10 s countdown) and Force restart, a search box, Favourites
-- (stars kept on your computer: data/rhylib_map_favs.json), Last played
-- (from the server's map history, Data "admin" "mapHistory") and every
-- map. Click a map: "Change in 10 s" / favourite / Cancel; "Cancel a map
-- change" stops a countdown (!cancelmap).
--------------------------------------------------------------------------

local FAV_FILE = "rhylib_map_favs.json"
local favs
local function loadFavs()
    if favs then return favs end
    favs = {}
    local raw = file.Read(FAV_FILE, "DATA")
    local t = raw and util.JSONToTable(raw)
    if istable(t) then for _, m in ipairs(t) do if isstring(m) then favs[m] = true end end end
    return favs
end
local function toggleFav(m)
    loadFavs()
    favs[m] = not favs[m] or nil
    local list = {}
    for k in pairs(favs) do list[#list + 1] = k end
    table.sort(list)
    file.Write(FAV_FILE, util.TableToJSON(list) or "[]")
end

local function agoText(t)
    t = tonumber(t)
    if not t or t <= 0 then return nil end
    local d = math.max(0, os.time() - t)
    if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local n = math.floor(d / 86400)
    return n == 1 and "yesterday" or (n .. " days ago")
end

local pageMaps            -- rows { name, current, lastPlayed } from the server
local pageSearch = ""

local function buildMapsPage(page)
    local K = Rhylib.UI.Kit
    local C, S = K.C, K.S

    local function confirm(m)
        local menu = K.Menu()
        menu:AddOption("Change to " .. m .. " in 10 s", function() Admin.Run("map", { m }) end)
        menu:AddOption((loadFavs()[m] and "Remove from" or "Add to") .. " favourites", function()
            toggleFav(m)
            if page.fillMaps then page.fillMaps() end
        end)
        menu:AddOption("Cancel", function() end)
        menu:Open()
    end

    -- The current map.
    local cur = string.lower(game.GetMap())
    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(S(128))
    function top:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local ts = h - S(16)
        local mat = thumb(cur)
        if mat then
            surface.SetDrawColor(255, 255, 255)
            surface.SetMaterial(mat)
            surface.DrawTexturedRect(S(8), S(8), ts, ts)
        else
            K.SetCol(C.header)
            surface.DrawRect(S(8), S(8), ts, ts)
            local pre = split(cur)
            draw.SimpleText(pre ~= "" and pre or "MAP", K.Font(22, 800), S(8) + ts * 0.5, S(8) + ts * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local x = S(8) + ts + S(16)
        K.Caps("Current map", x, S(22))
        draw.SimpleText(cur, K.Font(22, 700), x, S(48), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local up = math.floor(CurTime() / 60)
        draw.SimpleText(player.GetCount() .. " / " .. game.MaxPlayers() .. " players  ·  up " .. (up >= 60 and (math.floor(up / 60) .. " h " .. (up % 60) .. " min") or (up .. " min")),
            K.Font(13), x, S(74), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local btns = vgui.Create("DPanel", top)
    btns:Dock(RIGHT)
    btns:SetWide(S(220))
    btns:DockPadding(0, S(10), S(12), S(10))
    btns.Paint = nil
    local armed = 0
    local force = K.Button(btns, function() return CurTime() < armed and "Click again: now" or "Force restart (no countdown)" end, function()
        if CurTime() < armed then
            Admin.Run("fmaprestart", {})
            armed = 0
        else
            armed = CurTime() + 3
        end
    end, { small = true, danger = true })
    force:Dock(BOTTOM)
    local restart = K.Button(btns, "Restart map in 10 s", function() Admin.Run("restartmap", {}) end, { accent = true })
    restart:Dock(TOP)
    local cancel = K.Button(btns, "Cancel a map change", function() Admin.Run("cancelmap", {}) end, { small = true })
    cancel:Dock(TOP)
    cancel:DockMargin(0, S(4), 0, 0)

    local search = K.Search(page, "Search maps", function(t)
        pageSearch = t
        if page.fillMaps then page.fillMaps() end
    end)
    search:Dock(TOP)
    search:DockMargin(0, S(10), 0, S(8))
    search:SetText(pageSearch)

    local sp = K.Scroll(page)
    sp:Dock(FILL)
    local TW, TH = S(166), S(140)

    local function tile(parent, row)
        local m = row[1]
        local b = parent:Add("DButton")
        b:SetText("")
        b:SetSize(TW, TH)
        local pre, rest = split(m)
        local isCur = m == cur
        local last = agoText(row[3])
        function b:Paint(w, h)
            local ih = h - S(38)
            K.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            local mat = thumb(m)
            if mat then
                surface.SetDrawColor(255, 255, 255, self:IsHovered() and 255 or 215)
                surface.SetMaterial(mat)
                local v = (1 - ih / w) * 0.5
                surface.DrawTexturedRectUV(1, 1, w - 2, ih - 1, 0, v, 1, 1 - v)
            else
                K.SetCol(C.header)
                surface.DrawRect(1, 1, w - 2, ih - 1)
                draw.SimpleText(pre ~= "" and pre or "MAP", K.Font(24, 800), w * 0.5, ih * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            if loadFavs()[m] then
                -- (a small amber corner: a favourite)
                draw.NoTexture()
                K.SetCol(C.warn)
                surface.DrawPoly({ { x = w - S(22), y = 1 }, { x = w - 1, y = 1 }, { x = w - 1, y = S(22) } })
            end
            K.SetCol(isCur and C.accent or (self:IsHovered() and C.buttonHover or C.header))
            surface.DrawRect(0, ih, w, h - ih)
            draw.SimpleText(K.Fit(rest, K.Font(13, 700), w - S(12)), K.Font(13, 700), S(6), ih + S(11), isCur and C.bg or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local sub = isCur and "CURRENT MAP" or (last and ("played " .. last) or m)
            draw.SimpleText(K.Fit(sub, K.Font(11), w - S(12)), K.Font(11, isCur and 700 or 400), S(6), ih + S(27), isCur and C.bg or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            K.SetCol(self:IsHovered() and C.accent or C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            return true
        end
        b:SetTooltip(m .. "  (right-click: favourite)")
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            if isCur then return end
            confirm(m)
        end
        function b:DoRightClick()
            toggleFav(m)
            surface.PlaySound("ui/buttonclick.wav")
            if page.fillMaps then page.fillMaps() end
        end
    end

    local function section(title, rows)
        if #rows == 0 then return end
        local h = K.Heading(sp, title)
        h:Dock(TOP)
        h:DockMargin(0, S(6), S(10), S(6))
        local grid = vgui.Create("DIconLayout", sp)
        grid:Dock(TOP)
        grid:DockMargin(0, 0, S(10), S(6))
        grid:SetSpaceX(S(8))
        grid:SetSpaceY(S(8))
        for _, r in ipairs(rows) do tile(grid, r) end
        grid:Layout()
    end

    function page.fillMaps()
        if not IsValid(sp) then return end
        sp:Clear()
        if not pageMaps then
            K.Label(sp, "Loading maps...", 14, nil, C.textDim):Dock(TOP)
            return
        end
        local q = string.lower(string.Trim(pageSearch or ""))
        local function match(r) return q == "" or string.find(r[1], q, 1, true) end
        if q == "" then
            local fav, recent = {}, {}
            for _, r in ipairs(pageMaps) do
                if loadFavs()[r[1]] then fav[#fav + 1] = r end
                if (tonumber(r[3]) or 0) > 0 and r[1] ~= cur then recent[#recent + 1] = r end
            end
            table.sort(recent, function(a, b) return (tonumber(a[3]) or 0) > (tonumber(b[3]) or 0) end)
            for i = #recent, 7, -1 do recent[i] = nil end
            section("Favourites", fav)
            section("Last played", recent)
        end
        local all = {}
        for _, r in ipairs(pageMaps) do if match(r) then all[#all + 1] = r end end
        section(q == "" and ("All maps  ·  " .. #all) or (#all .. " match" .. (#all == 1 and "" or "es")), all)
        if #all == 0 then K.Label(sp, "No map matches \"" .. q .. "\"", 14, nil, C.textDim):Dock(TOP) end
        if q == "" and not next(loadFavs()) then
            K.Label(sp, "Right-click a map to make it a favourite.", 12, nil, C.textDim):Dock(TOP)
        end
    end
    page.fillMaps()
    Admin.RequestList(0, "", function(rows)
        pageMaps = rows
        if IsValid(page) and page.fillMaps then page.fillMaps() end
    end)
end

local function addMapsPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and Rhylib.UI and Rhylib.UI.Kit) then return end
    Menus.AddPage("maps", {
        title = "Maps",
        order = 220,
        section = "staff",
        icon = "maps",
        visible = function()
            local me = LocalPlayer()
            return IsValid(me) and Admin.Has and Admin.Has(me, "map") or false
        end,
        build = buildMapsPage,
    })
end
-- (rhylib_menus loads after rhylib_admin)
if Rhylib.After then Rhylib.After("menus", addMapsPage) else addMapsPage() end
Rhylib.Hook.Add("InitPostEntity", "admin.mapspage", addMapsPage)
