--[[
    Map picker: every map on the server as a tile (thumbnail from
    maps/thumb/<map>.png when the client has it), search box, current map
    marked. Admin.MapPicker(done(map)); the staff menu's Change map row and
    a bare !map open it. Needs rhylib_menus (the kit).
]]

local Admin = Rhylib.Admin

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

local picker
function Admin.MapPicker(done)
    local Menus = Rhylib.Menus
    local K = Menus and Menus.Kit
    if not K then
        chat.AddText(Color(230, 170, 70), "[Admin] ", Color(225, 225, 225), "Type !map <name> (the map list needs rhylib_menus)")
        return
    end
    if IsValid(picker) then picker:Remove() end
    local C, S = K.C, K.S

    local f = vgui.Create("EditablePanel")
    picker = f
    Menus.prompts[f] = true
    f.OnRemove = function(self) Menus.prompts[self] = nil end
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
            l:SetFont(K.Font(14))
            l:SetTextColor(C.textDim)
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
