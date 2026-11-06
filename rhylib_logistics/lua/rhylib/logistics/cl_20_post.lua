--[[
    Command post window (client; net logi.post from sv_20_post.lua). What
    shows depends on who you are (access 1 everyone, 2 field technician,
    3 officer): Respawn tickets (rhylib_spawns' shared pool), Garrison
    tickets, Logistics (nearby supplies and the armoury stock running
    low), Sensor arrays (technicians and officers), Orders (officers: the
    call-ins, each a button with its cooldown; net logi.call: Entity post,
    UInt 3 call index). Refresh asks again (logi.postreq). Esc or Close
    shuts it (UI closer "logistics.post").

    Layout: the header plate (COMMAND POST, who you see it as), three
    tiles (RESPAWN TICKETS, GARRISON, SENSOR ARRAYS: the number live, OFF
    or a dash, a line on what it means), then sections as bands with a
    diamond and a count (Logistics, Armoury stock, Sensor arrays, Orders):
    rows alternating, a coloured edge for the state (green fine / endless,
    amber low, red out / droids / jammed), the value right-aligned; an
    empty section is a dashed box with a note. Refresh / Close at the
    bottom.
]]

local L = Rhylib.Logistics

local function close()
    if IsValid(L.postPanel) then L.postPanel:Remove() return true end
    return false
end
local UI = Rhylib.UI
if UI and UI.RegisterCloser then UI.RegisterCloser("logistics.post", close) end

local ACCESS_NAMES = { "Trooper", "Field technician", "Officer" }

Rhylib.Net.Receive("logi.post", function()
    local post = net.ReadEntity()
    local access = net.ReadUInt(2)
    local len = net.ReadUInt(32)
    local data = util.JSONToTable(util.Decompress(net.ReadData(len) or "") or "") or {}
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local C, s = K.C, K.S
    close()
    local f = vgui.Create("EditablePanel")
    L.postPanel = f
    f:SetSize(math.min(s(800), ScrW() - s(40)), math.min(s(660), ScrH() - s(40)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(s(16), s(54), s(16), s(14))
    local seenAs = "You see it as: " .. (ACCESS_NAMES[access] or "Trooper")
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Command post", sub = seenAs, ticks = "all", header = s(40) })
    end
    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    bar:DockMargin(0, s(10), 0, 0)
    local cb = K.Button(bar, "Close", function() close() end)
    cb:Dock(RIGHT)
    cb:SetWide(s(110))
    local rb = K.Button(bar, "Refresh", function()
        if not IsValid(post) then return end
        Rhylib.Net.Start("logi.postreq")
        net.WriteEntity(post)
        net.SendToServer()
    end, { accent = true })
    rb:Dock(RIGHT)
    rb:SetWide(s(110))
    rb:DockMargin(0, 0, s(8), 0)
    function bar:Paint(w, h)
        K.Caps("Esc closes · Refresh to update the lists", 0, h * 0.5, C.label)
    end

    -- Tiles: caps label, a big value (valueFn() -> text, colour), a note.
    local SP = Rhylib.Spawns
    local tiles = vgui.Create("DPanel", f)
    tiles:Dock(TOP)
    tiles:SetTall(s(124))
    tiles:DockMargin(0, 0, 0, s(10))
    tiles.Paint = nil
    tiles.list = {}
    function tiles:PerformLayout(w, h)
        local n, gap = #self.list, s(8)
        local tw = math.floor((w - gap * (n - 1)) / n)
        for i, t in ipairs(self.list) do
            t:SetPos((i - 1) * (tw + gap), 0)
            t:SetSize(i == n and (w - (i - 1) * (tw + gap)) or tw, h)
        end
    end
    local function tile(label, valueFn, note)
        local t = vgui.Create("DPanel", tiles)
        tiles.list[#tiles.list + 1] = t
        t:DockPadding(s(12), s(62), s(10), s(6))
        local cap = string.upper(label)
        function t:Paint(w, h)
            K.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(C.edgeLight)
            surface.DrawLine(1, 1, w - 1, 1)
            local text, col = valueFn()
            K.SetCol(col)
            surface.DrawRect(1, 1, s(3), h - 2)
            draw.SimpleText(cap, K.Font(12, 700), s(12), s(16), C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, K.Font(24, 800), s(12), s(40), col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            K.Ticks(0, 0, w, h, false, 120)
        end
        local l = K.Label(t, note, 12, 400, C.textDim)
        l:Dock(TOP)
        return t
    end
    if SP and SP.TicketsOn and SP.TicketsOn() then
        tile("Respawn tickets", function()
            local n = SP.Tickets()
            return n .. " left", n > 0 and C.text or C.bad
        end, "Shared pool: each respawn after a death uses one.")
    elseif SP and SP.TicketsOn then
        tile("Respawn tickets", function() return "OFF", C.textDim end,
            "Not in use: respawning as normal (staff switch them on for events: !tickets on).")
    else
        tile("Respawn tickets", function() return "—", C.textDim end, "Not available (needs Rhy's Spawn Points).")
    end
    if L.GarrisonOn() then
        tile("Garrison tickets", function()
            local n = L.Garrison()
            return n .. " left", n > 0 and C.text or C.bad
        end, "Officers spend one per clone they call in.")
    else
        tile("Garrison", function() return "OFF", C.textDim end,
            "Not in use: clone squads can be called in freely (staff switch them on for events: !garrison on).")
    end
    local bs = data.beacons or {}
    if access >= L.ACCESS_TECH then
        local busy = 0
        for _, b in ipairs(bs) do if b.count > 0 then busy = busy + 1 end end
        local val = tostring(#bs)
        tile("Sensor arrays", function() return val, busy > 0 and C.bad or C.text end,
            #bs == 0 and "None out." or (busy > 0 and (busy .. " with droids inside.") or "No droids inside any."))
    else
        tile("Sensor arrays", function() return "—", C.textDim end, "Field technicians and officers see the sensor arrays here.")
    end

    local sc = K.Scroll(f)
    sc:Dock(FILL)

    -- A band: tint, thick edge, diamond, caps name, a count on the right.
    local GRAD = Material("vgui/gradient-l")
    local DIA = { {}, {}, {}, {} }
    local function band(title, right)
        local p = vgui.Create("DPanel", sc)
        p:Dock(TOP)
        p:SetTall(s(32))
        p:DockMargin(0, s(8), s(8), s(4))
        local cap = string.upper(title)
        function p:Paint(w, h)
            K.SetCol(C.accent, 40)
            surface.SetMaterial(GRAD)
            surface.DrawTexturedRect(0, 0, w * 0.7, h)
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, s(4), h)
            local cx, cy, r = s(18), h * 0.5, s(5)
            DIA[1].x, DIA[1].y = cx, cy - r
            DIA[2].x, DIA[2].y = cx + r, cy
            DIA[3].x, DIA[3].y = cx, cy + r
            DIA[4].x, DIA[4].y = cx - r, cy
            draw.NoTexture()
            K.SetCol(C.accent)
            surface.DrawPoly(DIA)
            draw.SimpleText(cap, K.Font(15, 700), s(32), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if right then draw.SimpleText(right, K.Font(12), w - s(10), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        end
        return p
    end
    local function note(t)
        local l = K.Label(sc, t, 13, 400, C.textDim)
        l:Dock(TOP)
        l:DockMargin(s(4), 0, s(8), s(6))
    end
    -- An empty section: a dashed box with the note.
    local function empty(t)
        local p = vgui.Create("DPanel", sc)
        p:Dock(TOP)
        p:DockMargin(0, 0, s(8), s(4))
        p:DockPadding(s(14), s(10), s(14), s(10))
        local l = K.Label(p, t, 13, 400, C.textDim)
        l:Dock(TOP)
        function p:Think()
            local want = l:GetTall() + s(20)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        function p:Paint(w, h)
            K.SetCol(C.tick, 140)
            local dash, gap = s(6), s(4)
            for i = 0, w - 1, dash + gap do
                local len = math.min(dash, w - i)
                surface.DrawRect(i, 0, len, 1)
                surface.DrawRect(i, h - 1, len, 1)
            end
            for j = 0, h - 1, dash + gap do
                local len = math.min(dash, h - j)
                surface.DrawRect(0, j, 1, len)
                surface.DrawRect(w - 1, j, 1, len)
            end
        end
    end
    -- A row: state edge in col, title, dim line, value right (or a
    -- control in row.right). Rows alternate.
    local nRows = 0
    local function row(title, desc, value, col)
        nRows = nRows + 1
        local alt = nRows % 2 == 0
        local r = vgui.Create("DPanel", sc)
        r:Dock(TOP)
        r:SetTall(s(48))
        r:DockMargin(0, 0, s(8), s(2))
        r:DockPadding(s(12), s(7), s(10), s(7))
        function r:Paint(w, h)
            K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(col or C.accent)
            surface.DrawRect(0, 0, s(3), h)
            local rw = IsValid(self.right) and self.right:GetWide() or 0
            local tw = w - s(14) - rw - s(20)
            draw.SimpleText(K.Fit(title, K.Font(14, 700), tw), K.Font(14, 700), s(14), h * 0.34, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(K.Fit(desc, K.Font(12), tw), K.Font(12), s(14), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if value then
                draw.SimpleText(value, K.Font(15, 700), w - s(12), h * 0.5, col or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        return r
    end

    local sup = data.supplies or {}
    band("Logistics", #sup == 1 and "1 nearby" or (#sup .. " nearby"))
    if #sup == 0 then empty("No supply crates, cabinets or armouries near this command post.") end
    for _, it in ipairs(sup) do
        local left = it.left or -1
        local col = left == -2 and C.accent or (left < 0 and C.good or (left == 0 and C.bad or C.text))
        if it.text then
            -- (a supply depot: what it holds, red when empty)
            row(it.name, it.kind .. " · " .. it.dist .. " m away", it.text, it.empty and C.bad or C.text)
        else
            row(it.name, it.kind .. " · " .. it.dist .. " m away", left == -2 and "Armoury stock" or (left < 0 and "Unlimited" or (left .. " left")), col)
        end
    end
    if data.stock then
        band("Armoury stock", #data.stock == 0 and "all above 60%" or (#data.stock .. " running low"))
        if #data.stock == 0 then empty("Every armoury item is above 60%. All armouries on the map share one stock.") end
        for _, it in ipairs(data.stock) do
            row(it.name, it.left == 0 and "out: comes back with a resupply crate" or "shared by every armoury", it.left .. " / " .. it.max,
                it.left == 0 and C.bad or C.warn)
        end
    end

    if access >= L.ACCESS_TECH then
        band("Sensor arrays", #bs == 1 and "1 out" or (#bs .. " out"))
        if #bs == 0 then empty("No sensor beacons out. Anyone with a sensor kit can set one down.") end
        for _, b in ipairs(bs) do
            local power = b.power > 0 and string.format("%d:%02d left", math.floor(b.power / 60), b.power % 60) or "no power"
            local ago = b.ago >= 0 and string.format(" · last alert %d s ago", b.ago) or ""
            local col = b.count > 0 and C.bad or (b.state == "Running" and C.good or (b.state == "Jammed" and C.bad or C.textDim))
            row(b.label .. " (" .. b.owner .. ")", b.state .. " · " .. power .. " · " .. b.dist .. " m away" .. ago,
                b.count > 0 and (b.count .. " droid" .. (b.count == 1 and "" or "s")) or "Clear", col)
        end
    end

    if access >= L.ACCESS_OFFICER then
        band("Orders", #L.CALLS .. " call-ins")
        note("Called in things arrive here after " .. math.Round(L.Cfg("callDelay")) .. " s. A clone squad falls in on you.")
        local DESC = {
            squad = function()
                local n = istable(L.Cfg("callSquad")) and #L.Cfg("callSquad") or 0
                return n .. " clones" .. (L.GarrisonOn() and (" · " .. n .. " garrison tickets") or "")
            end,
            supply = function() return "carry it to an armoury: puts back " .. math.Round(L.Cfg("resupplyAmount") * 100) .. "% of the stock" end,
            ammo = function() return "ammo crates by the post" end,
            medical = function() return "a medical crate by the post" end,
        }
        for _, c in ipairs(L.CALLS) do
            local r = row(c.title, DESC[c.id] and DESC[c.id]() or "", nil, C.accent)
            r.right = vgui.Create("DPanel", r)
            r.right:Dock(RIGHT)
            r.right:SetWide(s(190))
            r.right.Paint = nil
            local b = K.Button(r.right, "Call in", function()
                if not IsValid(post) or L.CallReady(c.id) > 0 then return end
                Rhylib.Net.Start("logi.call")
                net.WriteEntity(post)
                net.WriteUInt(c.index, 3)
                net.SendToServer()
            end, { accent = true, enabled = function() return L.CallReady(c.id) <= 0 end })
            b.label = function()
                local cd = math.ceil(L.CallReady(c.id))
                return cd > 0 and string.format("Ready in %d:%02d", math.floor(cd / 60), cd % 60) or "Call in"
            end
            b:Dock(FILL)
        end
    end
end)
