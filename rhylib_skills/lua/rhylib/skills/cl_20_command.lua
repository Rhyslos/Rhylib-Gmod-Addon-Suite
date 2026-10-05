--[[
    Command orders on the client: while one is active on you the HUD takes
    its colour (Rhylib.UI.Tint for the crosshair, the UI accent swapped for
    the length of HUDPaint, a soft edge glow) and a bar near the top shows
    the order, who gave it and the time left.
]]

local K = Rhylib.Skills
local UI = Rhylib.UI

-- Soft edge glow: thin strips whose alpha falls off smoothly towards the
-- middle (drawn untextured: the gradient materials showed as flat blocks).
local STRIPS = 28
local function edgeGlow(col, alpha, w, h)
    local e = math.floor(h * 0.11)
    local step = math.max(1, math.ceil(e / STRIPS))
    draw.NoTexture()
    surface.SetTexture(0)
    for i = 0, e - 1, step do
        local t = 1 - i / e
        local a = alpha * t * t * t   -- (eased: bright at the edge, gone well before the middle)
        surface.SetDrawColor(col.r, col.g, col.b, a)
        surface.DrawRect(0, i, w, step)            -- top
        surface.DrawRect(0, h - i - step, w, step) -- bottom
        surface.DrawRect(i, 0, step, h)            -- left
        surface.DrawRect(w - i - step, 0, step, h) -- right
    end
end

K.orderFrom = K.orderFrom or ""

Rhylib.Net.Receive("skills.order", function()
    local o = K.ORDERS[net.ReadUInt(3)]
    local by = net.ReadEntity()
    if not o then return end
    K.orderFrom = IsValid(by) and by:Nick() or ""
    surface.PlaySound("npc/combine_soldier/vo/off1.wav")
end)

-- The tint follows the order, set once per frame before the HUD draws.
-- The real accents are kept once (so an error mid-HUD can't lose them)
-- and put back every frame at the end of HUDPaint.
local baseUI, baseHUD
local function hudColors()
    local H = Rhylib.HUD
    return H and H.Colors
end
Rhylib.Hook.Add("HUDPaint", "skills.ordertint", function()
    local me = LocalPlayer()
    local o = IsValid(me) and me:Alive() and K.Order(me)
    UI.Tint = o and o.col or nil
    local HC0 = hudColors()
    if not o then
        -- (put back here too, in case the end hook didn't run)
        if baseUI then UI.Colors.accent = baseUI end
        if HC0 and baseHUD then HC0.accent = baseHUD end
        return
    end
    baseUI = baseUI or UI.Colors.accent
    UI.Colors.accent = o.col
    local HC = hudColors()
    if HC then
        baseHUD = baseHUD or HC.accent
        HC.accent = o.col
    end
end, -10000)

Rhylib.Hook.Add("HUDPaint", "skills.orderhud", function()
    if baseUI then UI.Colors.accent = baseUI end
    local HC = hudColors()
    if HC and baseHUD then HC.accent = baseHUD end
    local me = LocalPlayer()
    local o = IsValid(me) and me:Alive() and K.Order(me)
    if not o then return end
    local w, h = ScrW(), ScrH()
    local left = K.OrderLeft(me)
    local total = math.max(me:GetNW2Float("rhylib_orderLen", 0) > 0 and me:GetNW2Float("rhylib_orderLen", 0) or K.Cfg("commandTime"), 0.1)
    local fade = math.Clamp(left / 0.6, 0, 1)

    -- Edge glow: a brighter pulse as the order lands, then a soft steady glow.
    local since = total - left
    local pulse = since < 0.8 and (1 - since / 0.8) or 0
    edgeGlow(o.col, (32 + 50 * pulse) * fade, w, h)

    -- The bar: name, who gave it, time left.
    local bw, bh = math.floor(w * 0.18), math.max(4, math.floor(h * 0.005))
    local x, y = math.floor((w - bw) * 0.5), math.floor(h * 0.085)
    local title = string.upper(o.name) .. (K.orderFrom ~= "" and ("  ·  " .. K.orderFrom) or "")
    draw.SimpleTextOutlined(title, UI.Font(17, 700), w * 0.5, y - 4, ColorAlpha(o.col, 255 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 160 * fade))
    draw.NoTexture()
    surface.SetDrawColor(0, 0, 0, 150 * fade)
    surface.DrawRect(x - 1, y - 1, bw + 2, bh + 2)
    surface.SetDrawColor(o.col.r, o.col.g, o.col.b, 230 * fade)
    surface.DrawRect(x, y, math.floor(bw * math.Clamp(left / total, 0, 1)), bh)
    draw.SimpleText(o.text, UI.Font(13), w * 0.5, y + bh + 4, Color(230, 230, 225, 200 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end, 10000)
