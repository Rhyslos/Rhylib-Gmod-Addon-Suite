--[[
    Spawn points (client): the respawn list while dead (number keys 1-9
    pick; the highlighted one is where you'll come back; the panel takes no
    mouse, so clicking still respawns) and the staff edit menu. Both need
    rhylib_menus (Menus.Kit); without it no list shows and players respawn
    at the default point.
]]

local S = Rhylib.Spawns

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

local COL_EVENT = Color(255, 190, 80)
local current   -- the list shown: { idx, name, event, dist }

-- Shown while dead without taking the mouse (clicking still respawns);
-- number keys pick.
local function open(list, chosen)
    close()
    local M = Rhylib.Menus
    local K = M and M.Kit
    if not K then return end
    current = list
    local S2 = K.S
    local f = vgui.Create("DPanel")
    win = f
    local rows = math.min(#list, 9)
    f:SetSize(S2(360), S2(78) + rows * S2(30))
    f:SetPos(ScrW() - f:GetWide() - S2(40), ScrH() * 0.5 - f:GetTall() * 0.5)
    f:SetMouseInputEnabled(false)
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Respawn point", sub = "Number keys pick · respawn as usual", ticks = "all", header = S2(34) })
        for i = 1, rows do
            local row = list[i]
            local y = S2(56) + (i - 1) * S2(30)
            local sel = row.idx == chosen
            if sel then
                K.SetCol(K.C.accent, 60)
                surface.DrawRect(S2(8), y, w - S2(16), S2(26))
            end
            draw.SimpleText(i, K.Font(14, 700), S2(20), y + S2(13), K.C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(row.name .. "  ·  " .. row.dist .. " m", K.Font(14, sel and 700 or 500), S2(36), y + S2(13),
                row.event and COL_EVENT or K.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    function f:Think()
        if LocalPlayer():Alive() then close() end
    end
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

net.Receive(Rhylib.Net.Name("spawn.list"), function()
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

net.Receive(Rhylib.Net.Name("spawn.edit"), function()
    local ent = net.ReadEntity()
    local M = Rhylib.Menus
    local K = M and M.Kit
    if not (IsValid(ent) and K) then return end
    local m = K.Menu()
    m:AddOption("Rename (" .. ent:GetBeaconName() .. ")", function()
        K.Prompt("Rename", "Name shown in the respawn list", ent:GetBeaconName(), function(v) if IsValid(ent) then send(ent, 0, v) end end)
    end)
    if ent.Event then
        m:AddOption(ent:GetActive() and "Close the event spawn" or "Open the event spawn", function() if IsValid(ent) then send(ent, 2) end end)
        m:AddOption("Teleport everyone here", function()
            Derma_Query("Teleport every living player to " .. ent:GetBeaconName() .. "?", "Event teleport",
                "Teleport", function() if IsValid(ent) then send(ent, 3) end end, "Cancel")
        end)
    else
        local sub = m:AddSubMenu("Battalion (" .. (ent:GetBattalion() ~= "" and ent:GetBattalion() or "everyone") .. ")")
        sub:AddOption("Everyone", function() if IsValid(ent) then send(ent, 1, "") end end)
        for _, bn in ipairs(battalions()) do
            sub:AddOption(bn, function() if IsValid(ent) then send(ent, 1, bn) end end)
        end
    end
    m:Open()
end)
