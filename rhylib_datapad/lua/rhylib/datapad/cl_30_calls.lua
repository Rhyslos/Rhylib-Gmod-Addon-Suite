--[[
    Quick response calls (client): the datapad's Quick response tab sends
    them; this file keeps the open calls, draws the HUD and the markers.

      Incoming   a card at the top right for 20 s (key rhylib_call_key,
                 default J, answers the newest one; or Respond on the pad)
      Markers    where the caller is, for calls you can see (MP and medic
                 calls at once; reinforcements and resupply after you answer)
      Your call  a card while it's open: who is on the way
]]

local D = Rhylib.Datapad
local UI = Rhylib.UI
local C = UI.Colors

local keyVar = CreateClientConVar("rhylib_call_key", "j", true, false, "Key that answers the newest quick response call")

D.calls = D.calls or {}   -- [id] = { id, kind, caller, name, born, items, role, showPos, pos, resp = {names}, seen }
local sent = {}           -- [kind] = RealTime of our last call

local KIND_COL = {
    mp = Color(90, 150, 235), medic = Color(230, 75, 65), reinf = Color(235, 170, 60), supply = Color(120, 205, 120),
    eod = Color(240, 140, 50),
}

local function S(n) return math.floor(n * ScrH() / 1080 + 0.5) end
local function def(c) return (D.Cfg("calls") or {})[c.kind] or {} end
local function colOf(c) return KIND_COL[def(c).id] or C.accent end

--------------------------------------------------------------------------
-- Helpers (also used by the datapad tab)
--------------------------------------------------------------------------

function D.CanCall(kind)
    return RealTime() >= (sent[kind] or -1000) + D.Cfg("callCooldown")
end

function D.SendCall(kind, items)
    if not D.CanCall(kind) then return end
    sent[kind] = RealTime()
    Rhylib.Net.Start("dp.call")
    net.WriteUInt(kind, 3)
    net.WriteUInt(items or 0, 16)
    net.SendToServer()
    surface.PlaySound("buttons/button24.wav")
end

function D.RespondCall(id)
    Rhylib.Net.Start("dp.callr")
    net.WriteUInt(id, 16)
    net.SendToServer()
end

function D.CancelCall(id)
    Rhylib.Net.Start("dp.callx")
    net.WriteUInt(id, 16)
    net.SendToServer()
end

function D.CallTitle(c) return def(c).short or def(c).name or "Call" end

-- "Medic inbound: A, B"
function D.CallInbound(c)
    return (def(c).inbound or "Help") .. " inbound: " .. table.concat(c.resp, ", ")
end

-- Live position when we can see the caller, else the last one sent.
local function posOf(c)
    if IsValid(c.caller) and not c.caller:IsDormant() and c.caller:Alive() then return c.caller:GetPos() end
    return c.pos
end

function D.CallDistance(c)
    local p = posOf(c)
    if not p then return "" end
    return math.floor(LocalPlayer():GetPos():Distance(p) * 0.019) .. " m"
end

local function itemsText(c)
    if c.items == 0 then return nil end
    local names = D.Cfg("supplyItems") or {}
    local out = {}
    for i, name in ipairs(names) do
        if math.floor(c.items / 2 ^ (i - 1)) % 2 == 1 then out[#out + 1] = name end
    end
    return table.concat(out, ", ")
end
D.CallItems = itemsText

--------------------------------------------------------------------------
-- Network
--------------------------------------------------------------------------

Rhylib.Net.Receive("dp.callu", function()
    local id = net.ReadUInt(16)
    local active = net.ReadBool()
    if not active then
        D.calls[id] = nil
        if D.PadRebuild then D.PadRebuild("comms") end
        return
    end
    local c = { id = id, resp = {} }
    c.kind = net.ReadUInt(3)
    c.caller = net.ReadEntity()
    c.name = net.ReadString()
    c.born = RealTime() - net.ReadUInt(16)
    c.items = net.ReadUInt(16)
    c.role = net.ReadUInt(2)
    c.showPos = net.ReadBool()
    if c.showPos then c.pos = net.ReadVector() end
    for i = 1, net.ReadUInt(5) do c.resp[i] = net.ReadString() end
    local old = D.calls[id]
    c.seen = old and old.seen or RealTime()
    if not old and c.role == 0 then surface.PlaySound("buttons/blip1.wav") end
    if old and c.role == 2 and #c.resp > #old.resp then surface.PlaySound("buttons/button17.wav") end
    D.calls[id] = c
    if D.PadRebuild then D.PadRebuild("comms") end
end)

Rhylib.Net.Receive("dp.callp", function()
    local id, pos = net.ReadUInt(16), net.ReadVector()
    local c = D.calls[id]
    if c then c.pos = pos end
end)

--------------------------------------------------------------------------
-- Answer key
--------------------------------------------------------------------------

local function newestPending()
    local best
    for _, c in pairs(D.calls) do
        if c.role == 0 and RealTime() - c.seen < 20 and (not best or c.seen > best.seen) then best = c end
    end
    return best
end

local wasDown = false
Rhylib.Hook.Add("Think", "datapad.callkey", function()
    local code = input.GetKeyCode(keyVar:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    if down and not wasDown and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible() and not gui.IsConsoleVisible() then
        local c = newestPending()
        if c then
            D.RespondCall(c.id)
            surface.PlaySound("buttons/button14.wav")
        end
    end
    wasDown = down
end)

Rhylib.Hook.Add("InitPostEntity", "datapad.callkey", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.AddSetting then
        Menus.AddSetting("Datapad", { id = "dp.callkey", order = 10, title = "Answer a quick response call", kind = "key", convar = "rhylib_call_key" })
    end
end)

--------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------

local COL_BG = Color(14, 16, 15, 235)
local COL_EDGE = Color(0, 0, 0, 230)

local function card(x, y, w, h, col, title, lines)
    local HUD = Rhylib.HUD
    if HUD and HUD.Frame then
        HUD.Frame(x, y, w, h, { title = title, rule = col })
    else
        surface.SetDrawColor(COL_BG)
        surface.DrawRect(x, y, w, h)
        surface.SetDrawColor(COL_EDGE)
        surface.DrawOutlinedRect(x, y, w, h)
        draw.SimpleText(string.upper(title), UI.Font(12, 700), x + S(8), y + S(9), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, S(3), h)
    local ly = y + S(24)
    for _, l in ipairs(lines) do
        draw.SimpleText(l[1], UI.Font(l[3] or 14, l[4] or 500), x + S(12), ly, l[2] or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        ly = ly + S((l[3] or 14) + 5)
    end
end

local function cardHeight(n) return S(30) + n * S(19) end

local function drawMarker(c, eye)
    local p = posOf(c)
    if not p then return end
    local pos = p + Vector(0, 0, 80)
    local sp = pos:ToScreen()
    if not sp.visible then return end
    local x, y = math.floor(sp.x), math.floor(sp.y)
    local col = colOf(c)
    local r = S(9)
    draw.NoTexture()
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawPoly({ { x = x, y = y - r - 2 }, { x = x + r + 2, y = y }, { x = x, y = y + r + 2 }, { x = x - r - 2, y = y } })
    local pulse = 0.75 + 0.25 * math.sin(RealTime() * 5)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * pulse)
    surface.DrawPoly({ { x = x, y = y - r }, { x = x + r, y = y }, { x = x, y = y + r }, { x = x - r, y = y } })
    local dist = math.floor(eye:Distance(p) * 0.019)
    draw.SimpleTextOutlined(D.CallTitle(c) .. " · " .. c.name, UI.Font(13, 700), x, y + r + S(4), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_EDGE)
    draw.SimpleTextOutlined(dist .. " m", UI.Font(12), x, y + r + S(20), C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, COL_EDGE)
end

Rhylib.Hook.Add("HUDPaint", "datapad.calls", function()
    if next(D.calls) == nil then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local eye = ply:EyePos()
    local list = {}
    for _, c in pairs(D.calls) do list[#list + 1] = c end
    table.sort(list, function(a, b) return a.seen > b.seen end)

    -- Markers.
    for _, c in ipairs(list) do
        if c.role ~= 2 and c.showPos then drawMarker(c, eye) end
    end

    -- Cards: your own calls, then new incoming ones (20 s).
    local w = S(330)
    local x, y = ScrW() - w - S(24), S(150)
    local key = string.upper(keyVar:GetString())
    local shown = 0
    for _, c in ipairs(list) do
        if shown >= 4 then break end
        if c.role == 2 then
            local lines = { { #c.resp > 0 and D.CallInbound(c) or "Waiting for a response…", #c.resp > 0 and C.good or C.textDim } }
            local h = cardHeight(#lines)
            card(x, y, w, h, colOf(c), "Your call · " .. D.CallTitle(c), lines)
            y = y + h + S(6)
            shown = shown + 1
        end
    end
    local firstPending = newestPending()
    for _, c in ipairs(list) do
        if shown >= 4 then break end
        if c.role ~= 2 and RealTime() - c.seen < 20 then
            local where = c.showPos and D.CallDistance(c) or "answer to see where"
            local lines = { { c.name .. "  ·  " .. where } }
            local items = itemsText(c)
            if items then lines[#lines + 1] = { "Needs: " .. items, C.text, 13 } end
            if c.role == 1 then
                lines[#lines + 1] = { "You're responding", C.good, 12, 700 }
            elseif c == firstPending then
                lines[#lines + 1] = { "[" .. key .. "] Respond", colOf(c), 12, 700 }
            end
            local h = cardHeight(#lines)
            card(x, y, w, h, colOf(c), D.CallTitle(c) .. " call", lines)
            y = y + h + S(6)
            shown = shown + 1
        end
    end
end)
