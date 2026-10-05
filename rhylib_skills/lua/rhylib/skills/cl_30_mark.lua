--[[
    Mark target on the client: Q asks the server to mark (hook
    Rhylib.MarkKey from rhylib_menus), and marks sent to us (ours or a
    squad mate's) are drawn over the target until they run out or the
    target dies. Through optics, one Q marks several (sv_30_mark).
]]

local K = Rhylib.Skills
local UI = Rhylib.UI

K.clientMarks = K.clientMarks or {}   -- [entity index] = { by, untilT }

local COL = Color(242, 160, 60)
local COL_OUT = Color(0, 0, 0, 170)

Rhylib.Hook.Add("Rhylib.MarkKey", "skills.mark", function()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and K.Has(me, "mark_target")) then return end
    local G = Rhylib.Gear
    local optics = G and G.Looking and G.Looking(me) or false
    Rhylib.Net.Start("skills.markreq")
    net.WriteBool(optics)
    net.WriteUInt(math.Clamp(math.floor((optics and G.opticsFov or 0) * 10), 0, 1023), 10)
    net.SendToServer()
end)

Rhylib.Net.Receive("skills.mark", function()
    local by = net.ReadUInt(13)   -- (who marked)
    local replace = net.ReadBool()
    local secs = net.ReadUInt(6)
    local n = net.ReadUInt(3)
    -- A new Q replaces that player's older marks.
    if replace then
        for t, mk in pairs(K.clientMarks) do
            if mk.by == by then K.clientMarks[t] = nil end
        end
    end
    for _ = 1, n do
        K.clientMarks[net.ReadUInt(13)] = { by = by, untilT = CurTime() + secs }
    end
    surface.PlaySound(by == LocalPlayer():EntIndex() and "buttons/blip1.wav" or "buttons/blip2.wav")
end)

local function alive(e)
    if not IsValid(e) then return false end
    if e:IsPlayer() then return e:Alive() end
    return e:Health() > 0
end

-- A diamond outline at x, y.
local function diamond(x, y, r, col)
    surface.SetDrawColor(col)
    surface.DrawLine(x, y - r, x + r, y)
    surface.DrawLine(x + r, y, x, y + r)
    surface.DrawLine(x, y + r, x - r, y)
    surface.DrawLine(x - r, y, x, y - r)
end

Rhylib.Hook.Add("HUDPaint", "skills.marks", function()
    if next(K.clientMarks) == nil then return end
    local me = LocalPlayer()
    local now = CurTime()
    local s = ScrH() / 1080
    draw.NoTexture()
    for idx, mk in pairs(K.clientMarks) do
        local e = Entity(idx)
        if mk.untilT <= now or (IsValid(e) and not alive(e)) then
            K.clientMarks[idx] = nil
        elseif IsValid(e) and not e:IsDormant() then
            local top = e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 14)
            local sp = top:ToScreen()
            if sp.visible then
                local col = COL
                local left = mk.untilT - now
                local a = left < 1 and left or 1
                local r = 9 * s
                diamond(sp.x, sp.y, r + 1, ColorAlpha(COL_OUT, COL_OUT.a * a))
                diamond(sp.x, sp.y, r, ColorAlpha(col, 255 * a))
                diamond(sp.x, sp.y, r - 3 * s, ColorAlpha(col, 160 * a))
                local m = math.Round(top:Distance(me:EyePos()) * 0.019)
                local text = m .. " m"
                draw.SimpleTextOutlined(text, UI.Font(12, 600), sp.x, sp.y + r + 3 * s, ColorAlpha(col, 255 * a),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, ColorAlpha(COL_OUT, COL_OUT.a * a))
            end
        end
    end
end)
