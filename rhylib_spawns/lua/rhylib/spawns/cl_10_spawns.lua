--[[
    Spawn points (client): the respawn list while dead and the staff edit
    menu. Both need the UI kit (Rhylib.UI.Kit, in core); without it no list
    shows and players respawn at the default point.

    Respawn list: a plate on the right (RESPAWN POINT, how many to pick
    from), one row per point (up to 9): the number key in a small box, the
    name, an amber EVENT chip on event spawns, the distance right-aligned.
    The highlighted row (blue stripe, tint, YOU COME BACK HERE) is where
    you'll come back. Number keys 1-9 pick; the panel takes no mouse, so
    clicking still respawns. A caps hint line at the bottom.

    Staff edit menu (E on a point): a kit menu (its submenus in the same
    look, S.StyleSub) and a kit confirm box for Teleport everyone here.
]]

local S = Rhylib.Spawns

-- Event spawns' colour (the event spawn entity is orange too).
local COL_EVENT = Rhylib.UI.Col("spawns.event", 255, 190, 80)

local win

local function close()
    if IsValid(win) then win:Remove() end
    win = nil
end

local function pick(idx)
    Rhylib.Net.Start("spawn.pick")
    net.WriteUInt(idx or 0, 13)
    net.SendToServer()
end

local current   -- the list shown: { idx, name, event, dist }

-- Shown while dead without taking the mouse (clicking still respawns);
-- number keys pick.
local function open(list, chosen)
    close()
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local C = K.C
    current = list
    local s = K.S
    local f = vgui.Create("DPanel")
    win = f
    local rows = math.min(#list, 9)
    for i = 1, rows do
        local row = list[i]
        row.key = tostring(i)
        row.distText = row.dist .. " m"
    end
    local HEAD, ROW, FOOT = s(40), s(38), s(30)
    local sub = rows == 1 and "1 point" or (rows .. " points")
    f:SetSize(s(380), HEAD + s(8) + rows * ROW + FOOT)
    f:SetPos(ScrW() - f:GetWide() - s(40), ScrH() * 0.5 - f:GetTall() * 0.5)
    f:SetMouseInputEnabled(false)
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Respawn point", sub = sub, ticks = "all", header = HEAD })
        local x0, rw = s(8), w - s(16)
        for i = 1, rows do
            local row = list[i]
            local y = HEAD + s(4) + (i - 1) * ROW
            local sel = row.idx == chosen
            K.SetCol(i % 2 == 0 and C.rowAlt or C.row)
            surface.DrawRect(x0, y, rw, ROW - s(2))
            if sel then
                K.SetCol(C.accent, 40)
                surface.DrawRect(x0, y, rw, ROW - s(2))
                K.SetCol(C.accent)
                surface.DrawRect(x0, y, s(3), ROW - s(2))
            end
            local cy = y + (ROW - s(2)) * 0.5
            -- (the number key in a small box)
            local kb = s(20)
            K.SetCol(C.header)
            surface.DrawRect(x0 + s(10), cy - kb * 0.5, kb, kb)
            K.SetCol(sel and C.accent or C.edgeLight)
            surface.DrawOutlinedRect(x0 + s(10), cy - kb * 0.5, kb, kb)
            draw.SimpleText(row.key, K.Font(13, 700), x0 + s(10) + kb * 0.5, cy, sel and C.accent or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            -- (distance right, then the name in what's left)
            local right = x0 + rw - s(10)
            draw.SimpleText(row.distText, K.Font(13, 700), right, cy, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            right = right - s(56)
            local nx = x0 + s(40)
            local maxW = right - nx
            local chipW = 0
            if row.event then chipW = s(50) end
            local nf = K.Font(14, sel and 700 or 500)
            local name = K.Fit(row.name, nf, math.max(s(40), maxW - chipW))
            draw.SimpleText(name, nf, nx, sel and cy - s(6) or cy, row.event and COL_EVENT or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetFont(nf)
            local cx = nx + surface.GetTextSize(name) + s(8)
            if row.event then
                local cw, ch = s(44), s(16)
                K.SetCol(COL_EVENT, 40)
                surface.DrawRect(cx, cy - ch * 0.5 - (sel and s(6) or 0), cw, ch)
                K.SetCol(COL_EVENT, 150)
                surface.DrawOutlinedRect(cx, cy - ch * 0.5 - (sel and s(6) or 0), cw, ch)
                draw.SimpleText("EVENT", K.Font(10, 700), cx + cw * 0.5, cy - (sel and s(6) or 0), COL_EVENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            if sel then
                K.Caps("You come back here", nx, cy + s(9), C.accent)
            end
        end
        K.Caps("Number keys 1-9 pick · respawn as usual", s(14), h - FOOT * 0.5, C.label)
    end
    function f:Think()
        if LocalPlayer():Alive() then close() end
    end
end

-- S.StyleSub(K, menu, text): menu:AddSubMenu(text) on a K.Menu (styled by
-- the kit). Returns the submenu.
-- Also used by cl_20_events.lua.
function S.StyleSub(K, m, text)
    -- (K.Menu styles its submenus itself now)
    local sub = m:AddSubMenu(text)
    return sub
end

-- A small kit yes / no box (Esc or Cancel closes it: UI.prompts).
local function confirm(K, title, text, yes, fn)
    local C, s = K.C, K.S
    local UI = Rhylib.UI
    local f = vgui.Create("EditablePanel")
    if UI.prompts then UI.prompts[f] = true end
    f.OnRemove = function(self) if UI.prompts then UI.prompts[self] = nil end end
    f:SetSize(s(440), s(160))
    f:Center()
    f:MakePopup()
    f:DoModal()
    f:DockPadding(s(14), s(46), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title, ticks = "all", rule = C.warn })
    end
    local l = K.Label(f, text, 14, 500, C.text)
    l:Dock(TOP)
    local row = vgui.Create("DPanel", f)
    row:Dock(BOTTOM)
    row:SetTall(s(32))
    row.Paint = nil
    local ok = K.Button(row, yes, function() f:Remove() fn() end, { accent = true })
    ok:Dock(RIGHT)
    ok:SetWide(s(120))
    local cancel = K.Button(row, "Cancel", function() f:Remove() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(100))
    cancel:DockMargin(0, 0, s(8), 0)
    return f
end

-- slot1-9 while the list is up pick that row.
Rhylib.Hook.Add("PlayerBindPress", "spawns.pick", function(ply, bind, pressed)
    if not pressed or not IsValid(win) or ply:Alive() then return end
    local n = tonumber(string.match(bind, "^slot(%d)$") or "")
    if n and current and current[n] then
        pick(current[n].idx)
        surface.PlaySound("ui/buttonclick.wav")
        return true
    end
end, -30)

Rhylib.Net.Receive("spawn.list", function()
    if not net.ReadBool() then return close() end
    local list = {}
    for i = 1, net.ReadUInt(6) do
        list[i] = { idx = net.ReadUInt(13), name = net.ReadString(), event = net.ReadBool(), dist = net.ReadUInt(16) }
    end
    local chosen = net.ReadUInt(13)
    open(list, chosen)
end)

--------------------------------------------------------------------------
-- Staff edit menu (E on a point)
--------------------------------------------------------------------------

local function send(ent, op, text)
    Rhylib.Net.Start("spawn.set")
    net.WriteEntity(ent)
    net.WriteUInt(op, 3)
    if op == 0 or op == 1 then net.WriteString(text or "") end
    net.SendToServer()
end

-- Battalions to pick from: jobs' roster battalions, then DarkRP job
-- categories (a point matches either, S.InBattalion).
local function battalions()
    local out, seen = {}, {}
    for _, j in pairs(RPExtraTeams or {}) do
        if isstring(j.battalion) and j.battalion ~= "" and not seen[j.battalion] then
            seen[j.battalion] = true
            out[#out + 1] = j.battalion
        end
    end
    table.sort(out)
    local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories()
    for _, c in ipairs(cats and cats.jobs or {}) do
        if c.name and c.name ~= "" and not seen[c.name] then
            seen[c.name] = true
            out[#out + 1] = c.name
        end
    end
    return out
end

Rhylib.Net.Receive("spawn.edit", function()
    local ent = net.ReadEntity()
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not (IsValid(ent) and K) then return end
    local m = K.Menu()
    m:AddOption("Rename (" .. ent:GetBeaconName() .. ")", function()
        K.Prompt("Rename", "Name shown in the respawn list", ent:GetBeaconName(), function(v) if IsValid(ent) then send(ent, 0, v) end end)
    end)
    if ent.Event then
        m:AddOption(ent:GetActive() and "Close the event spawn" or "Open the event spawn", function() if IsValid(ent) then send(ent, 2) end end)
        m:AddOption("Teleport everyone here", function()
            confirm(K, "Event teleport", "Teleport every living player to " .. ent:GetBeaconName() .. "?",
                "Teleport", function() if IsValid(ent) then send(ent, 3) end end)
        end)
    else
        local sub = S.StyleSub(K, m, "Battalion (" .. (ent:GetBattalion() ~= "" and ent:GetBattalion() or "everyone") .. ")")
        sub:AddOption("Everyone", function() if IsValid(ent) then send(ent, 1, "") end end)
        for _, bn in ipairs(battalions()) do
            sub:AddOption(bn, function() if IsValid(ent) then send(ent, 1, bn) end end)
        end
    end
    m:Open()
end)
