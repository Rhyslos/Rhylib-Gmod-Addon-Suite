--[[
    Event tools (client): the respawn ticket count on the HUD (top middle,
    while tickets are on), the "no tickets left" line while dead, the
    objective markers (a diamond with the name and the distance in metres,
    clamped to the screen edge when off screen), and the staff edit menu
    for objective markers (net spawn.objedit / spawn.objset).
    HUDPaint "spawns.events".
]]

local S = Rhylib.Spawns
S.objectives = S.objectives or {}

local GOLD, RED, WHITE, SHADOW = Color(255, 200, 70), Color(235, 80, 70), Color(235, 238, 240), Color(0, 0, 0, 200)

local function font(size, weight)
    return Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(size, weight) or "DermaDefaultBold"
end

local function diamond(x, y, m, col)
    draw.NoTexture()
    surface.SetDrawColor(0, 0, 0, 160)
    surface.DrawPoly({ { x = x, y = y - m - 2 }, { x = x + m + 2, y = y }, { x = x, y = y + m + 2 }, { x = x - m - 2, y = y } })
    surface.SetDrawColor(col)
    surface.DrawPoly({ { x = x, y = y - m }, { x = x + m, y = y }, { x = x, y = y + m }, { x = x - m, y = y } })
end

Rhylib.Hook.Add("HUDPaint", "spawns.events", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local w, h = ScrW(), ScrH()
    local s = h / 1080

    -- Respawn tickets.
    if S.TicketsOn() then
        local n = S.Tickets()
        draw.SimpleTextOutlined("RESPAWN TICKETS  " .. n, font(math.floor(16 * s), 800), w * 0.5, 12 * s, n > 0 and WHITE or RED,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, SHADOW)
        if not me:Alive() and n <= 0 and me:GetNW2Bool("rhylib_ticketDue", false) then
            draw.SimpleTextOutlined("No respawn tickets left: wait for staff", font(math.floor(26 * s), 800), w * 0.5, h * 0.3, RED,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, SHADOW)
        end
    end

    -- Objective markers.
    if not next(S.objectives) then return end
    local eye = me:EyePos()
    local margin = 40 * s
    for e in pairs(S.objectives) do
        if IsValid(e) and S.ObjectiveFor(me, e) then
            local pos = e:GetPos() + Vector(0, 0, 24)
            local metres = math.floor(eye:Distance(pos) * 0.01905 + 0.5)
            local sp = pos:ToScreen()
            local behind = (pos - eye):Dot(me:EyeAngles():Forward()) < 0
            local x, y = sp.x, sp.y
            if behind then x, y = w - x, h - y end
            local off = behind or x < margin or x > w - margin or y < margin or y > h - margin
            if off then
                -- (clamped to the edge, toward where it is)
                local dx, dy = x - w * 0.5, y - h * 0.5
                if behind and dx == 0 and dy == 0 then dy = 1 end
                local k = math.min((w * 0.5 - margin) / math.max(math.abs(dx), 1), (h * 0.5 - margin) / math.max(math.abs(dy), 1))
                x, y = w * 0.5 + dx * k, h * 0.5 + dy * k
            end
            local m = math.floor(9 * s)
            diamond(x, y, m, GOLD)
            draw.SimpleTextOutlined(e:GetBeaconName(), font(math.floor(15 * s), 700), x, y - m - 4 * s, GOLD, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, SHADOW)
            draw.SimpleTextOutlined(metres .. " m", font(math.floor(14 * s), 600), x, y + m + 3 * s, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, SHADOW)
        end
    end
end)

--------------------------------------------------------------------------
-- Staff edit menu (E on an objective marker)
--------------------------------------------------------------------------

local function send(ent, op, text)
    Rhylib.Net.Start("spawn.objset")
    net.WriteEntity(ent)
    net.WriteUInt(op, 2)
    if op == 0 or op == 1 then net.WriteString(text or "") end
    net.SendToServer()
end

-- (battalions: the jobs' roster battalions, then the DarkRP job categories)
local function battalions()
    local out, seen = {}, {}
    for _, j in pairs(RPExtraTeams or {}) do
        local b = isstring(j.battalion) and j.battalion ~= "" and j.battalion or nil
        if b and not seen[b] then seen[b] = true out[#out + 1] = b end
    end
    for _, j in pairs(RPExtraTeams or {}) do
        local c = isstring(j.category) and j.category or nil
        if c and not seen[c] then seen[c] = true out[#out + 1] = c end
    end
    table.sort(out)
    return out
end

Rhylib.Net.Receive("spawn.objedit", function()
    local ent = net.ReadEntity()
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not (IsValid(ent) and K) then return end
    local m = K.Menu()
    m:AddOption("Rename (" .. ent:GetBeaconName() .. ")", function()
        K.Prompt("Rename", "Name shown on the HUD", ent:GetBeaconName(), function(v) if IsValid(ent) then send(ent, 0, v) end end)
    end)
    local sub = m:AddSubMenu("Who sees it (" .. (ent:GetBattalion() ~= "" and ent:GetBattalion() or "everyone") .. ")")
    sub:AddOption("Everyone", function() if IsValid(ent) then send(ent, 1, "") end end)
    for _, bn in ipairs(battalions()) do
        sub:AddOption(bn, function() if IsValid(ent) then send(ent, 1, bn) end end)
    end
    m:AddOption(ent:GetShowJammed() and "Shown while jammed: ON (click: hide it from jammed players)" or "Shown while jammed: OFF (click: show it to jammed players too)",
        function() if IsValid(ent) then send(ent, 2) end end)
    m:Open()
end)
