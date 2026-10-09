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

--------------------------------------------------------------------------
-- Squad orders (2026-10-06be): hold R with the comlink for a wheel of
-- orders to the clones following you. Commander officers only; Follow me
-- (top) takes in free clones nearby, everything else needs followers.
--------------------------------------------------------------------------

-- Index into K.SQUAD_OPS (sh_20_command) is what's sent.
local OP = {}
for i, op in ipairs(K.SQUAD_OPS) do OP[op] = i end

-- Colour strip on each option's left edge (owner: follow yellow, attack red).
local SQ_COL = {
    follow = Color(242, 209, 75),     -- yellow
    regroup = Color(250, 235, 150),   -- pale yellow
    hold = Color(79, 143, 232),       -- blue
    move = Color(240, 150, 60),       -- orange
    aggroUp = Color(232, 70, 60),     -- red (attack)
    aggroDown = Color(70, 200, 200),  -- teal
    dismiss = Color(150, 155, 165),   -- grey
}

local function sendOp(op)
    Rhylib.Net.Start("skills.squad")
    net.WriteUInt(OP[op], 3)
    net.SendToServer()
end

-- Followers and free clones near me (the server decides for real).
local function countClones(me)
    local D = Rhylib.Droids
    local r = (D and D.Cfg and D.Cfg("cmdFollowRadius")) or 900
    local r2, pos = r * r, me:GetPos()
    local mine, free = 0, 0
    for _, c in ipairs(ents.FindByClass("rhylib_ct_*")) do
        if c.IsRhylibClone and c:Health() > 0 then
            local lead = c:GetNW2Entity("rhylib_lead")
            if lead == me then
                mine = mine + 1
            elseif not IsValid(lead) and c:GetNW2String("rhylib_dmode", "") ~= "roam" and c:GetPos():DistToSqr(pos) < r2 then
                free = free + 1
            end
        end
    end
    return mine, free
end

local function squadList(me)
    local D = Rhylib.Droids
    local names = (D and D.SQUAD_AGGRO_NAMES) or {}
    local mine, free = countClones(me)
    local lock
    if not K.CanCommandSquad(me) then
        lock = "Commander officers (or Reinforcements) only"
    else
        local ok, why = K.RankOk(me, "commandRank")
        if not ok then lock = why end
    end
    local none = mine == 0 and "No clones following" or nil
    local level = me:GetNW2Int("rhylib_squadAggro", 3)
    if level < 1 or level > 5 then level = 3 end
    local followSub = mine > 0 and string.format("%d following · %d nearby", mine, free)
        or (free > 0 and string.format("%d clone%s nearby", free, free == 1 and "" or "s"))
    local list = {
        { label = "Follow me", sub = followSub, op = "follow", run = function() sendOp("follow") end,
            disabled = lock or ((mine == 0 and free == 0) and "No clones nearby" or nil) },
        { label = "Regroup", sub = "Your squad back on you", op = "regroup", run = function() sendOp("regroup") end, disabled = lock or none },
        { label = "Hold position", sub = "Stay where you are", op = "hold", run = function() sendOp("hold") end, disabled = lock or none },
        { label = "Move up there", sub = "Hold where I'm aiming", op = "move", run = function() sendOp("move") end, disabled = lock or none },
        { label = "More aggressive", sub = names[level] and ("Now: " .. names[level]),
            op = "aggroUp", run = function() sendOp("aggroUp") end, disabled = lock or none or (level >= 5 and "Already charging" or nil) },
        { label = "Less aggressive", sub = names[level] and ("Now: " .. names[level]),
            op = "aggroDown", run = function() sendOp("aggroDown") end, disabled = lock or none or (level <= 1 and "Already falling back" or nil) },
        { label = "Dismiss", sub = "They guard where they stand", op = "dismiss", run = function() sendOp("dismiss") end, disabled = lock or none },
    }
    for _, o in ipairs(list) do o.col = SQ_COL[o.op] end
    return list
end

Rhylib.Hook.Add("PlayerBindPress", "skills.squadwheel", function(ply, bind, pressed, code)
    if not pressed or not string.find(bind, "+reload", 1, true) then return end
    local W = Rhylib.Menus and Rhylib.Menus.Wheel
    if not (W and W.OpenList) then return end
    if W.open then return true end
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == "rhylib_commlink") or not ply:Alive() then return end
    if not (code and code > 0) then
        local key = input.LookupBinding("+reload")
        code = key and input.GetKeyCode(key)
    end
    if not (code and code > 0) then return end
    if W.OpenList("Squad", squadList(ply), code) then return true end
end)

-- Hand-signal commands (/advance, /group, ...) never show in chat, typed
-- or from the wheel (DarkRP calls OnPlayerChat for its chat lines too).
Rhylib.Hook.Add("OnPlayerChat", "skills.signals", function(ply, text)
    if K.IsSignalText(text) then return true end
end)
