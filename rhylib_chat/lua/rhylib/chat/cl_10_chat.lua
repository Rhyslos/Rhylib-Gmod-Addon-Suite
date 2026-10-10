--[[
    Chat, client side: replaces the default chat box.

    Closed: the last messages fade out after a while. Or, pinned with
    /togglechat (rhylib_chat_pinned 1), the whole window stays on screen
    and opening the chat just lets you type.
    Open (your chat key): a dark frame in the HUD's style with a header,
    the history (scroll with the mouse wheel), the input line, and your
    current channel on the left of it. Click the channel name to pick
    another. Typing a channel command (/local, /public, ...) followed by a
    space switches channel straight away. Typing "/" shows matching
    commands (and player names after /pm); Tab or Enter fills one in,
    Up/Down picks (with no list open, Up/Down walks through what you sent).
    Messages from players show the sender's model portrait, or their Steam
    avatar if they have left.

    Where it sits:
      helmet visor (first person)  bottom-left, in the grey cheek area; its
                                   top-right edge follows the cheek's curve
      otherwise                    bottom-left, above the corner plate

    Everything other addons print with chat.AddText (DarkRP, admin mods,
    join messages) shows up here too.

    Drawing: the window panel only paints its frame and the input box.
    The messages, avatars and pop-up lists are drawn on top afterwards in
    screen space (PostRenderVGUI), because avatar images can only be drawn
    by hand there. Nothing allocates per frame.

    Client only. Adds to Rhylib.Chat: Chat.Add, Chat.Open, Chat.Close,
    Chat.Rect, Chat.VisorEdgeX, Chat.ShowEvent, Chat.lines, Chat.current,
    Chat.history, Chat.panel (the open window, a "RhylibChat" panel).
    Replaces chat.AddText (the old one is kept in Chat.oldAddText).
    Client convar: rhylib_chat_pinned (0/1, /togglechat).
    Net: receives chat.msg; sends chat.send and chat.typing (see sv_10_chat).
    Other addons read Chat.Rect (rhylib_radio sizes its visor parts around it).
]]

local Chat = Rhylib.Chat
local UI = Rhylib.UI

Chat.lines = Chat.lines or {}      -- { time, segs = { { col, text }, ... }, sid = sender SteamID64 }
Chat.current = Chat.current or nil -- current channel
Chat.scroll = 0
Chat.history = Chat.history or {}  -- lines you sent this session, oldest first

local function maxLength()
    return Rhylib.Config.Get("chat", "maxLength") or 300
end

local MAX_LINES = 150              -- history kept; the oldest line goes first
local SHOW_TIME = 12               -- seconds a message stays when the chat is closed

-- Same look as the HUD's corner plates.
local COL_BG = Color(14, 16, 15, 238)
local COL_HEADER = Color(22, 25, 23, 255)
local COL_EDGE_DARK = Color(0, 0, 0, 230)
local COL_EDGE_LIGHT = Color(170, 176, 180, 70)
local COL_TICK = Color(170, 176, 180, 150)
local COL_INPUT = Color(8, 9, 8, 255)
local COL_INPUT_EDGE = Color(58, 62, 58, 255)
local COL_TEXT = Color(228, 227, 220)
local COL_DIM = Color(140, 142, 136)
local COL_SYSTEM = Color(170, 176, 180)
local COL_ROW = Color(20, 22, 21, 250)
local COL_ROW_PICK = Color(38, 50, 64, 255)
local COL_ROW_LINE = Color(40, 44, 40, 255)

-- The channel plain text goes to: Chat.current, else config chat
-- defaultChannel, else Public.
local function currentChannel()
    if not Chat.current then Chat.current = Chat.byId[Rhylib.Config.Get("chat", "defaultChannel")] or Chat.CHANNELS[1] end
    return Chat.current
end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

-- Chat.Add(segs, sid): adds a line to the chat box (not the console).
-- segs: list of { Color, text } pieces drawn in order.
-- sid: the sender's SteamID64, for the portrait/avatar (nil for system lines).
-- Example: Rhylib.Chat.Add({ { Color(255, 200, 80), "[Squad] " }, { color_white, "Moving out" } })
function Chat.Add(segs, sid)
    local lines = Chat.lines
    -- The sender's model now, for their portrait (falls back to the Steam avatar).
    local p = sid and player.GetBySteamID64(sid)
    lines[#lines + 1] = { time = RealTime(), segs = segs, sid = sid, model = IsValid(p) and p:GetModel() or nil }
    if #lines > MAX_LINES then table.remove(lines, 1) end
    if Chat.scroll > 0 then Chat.scroll = Chat.scroll + 1 end  -- keep the view still while scrolled up
end

-- Everything chat.AddText receives (colours, strings, players) lands here too.
-- A player argument becomes their name in team colour and sets the line's
-- portrait. The original chat.AddText still runs, for the console.
Chat.oldAddText = Chat.oldAddText or chat.AddText
function chat.AddText(...)
    local segs, col, sid = {}, COL_TEXT, nil
    for _, v in ipairs({ ... }) do
        if IsColor(v) or (istable(v) and v.r and v.g and v.b) then
            col = Color(v.r, v.g, v.b)
        elseif isentity(v) and IsValid(v) and v:IsPlayer() then
            segs[#segs + 1] = { team.GetColor(v:Team()), v:Nick() }
            sid = sid or v:SteamID64()
        else
            segs[#segs + 1] = { col, tostring(v) }
        end
    end
    Chat.Add(segs, sid)
    Chat.oldAddText(...)  -- still prints to the console
end

-- Join/leave and other engine messages.
Rhylib.Hook.Add("ChatText", "chat.engine", function(_, _, text, kind)
    if kind == "chat" then return end  -- player chat arrives through chat.AddText
    Chat.Add({ { COL_SYSTEM, text } })
    return true
end)

-- chat.msg from the server: channel index (0 = system note), sender,
-- target, text. Builds the coloured line and plays a sound.
net.Receive(Rhylib.Net.Name("chat.msg"), function()
    local ch = Chat.CHANNELS[net.ReadUInt(Chat.CHANNEL_BITS)]
    local sender = net.ReadEntity()
    local target = net.ReadEntity()
    local text = net.ReadString()
    if not ch then
        Chat.Add({ { COL_SYSTEM, text } })
        return
    end
    local name = IsValid(sender) and sender:Nick() or "?"
    local nameCol = IsValid(sender) and team.GetColor(sender:Team()) or COL_DIM
    local segs = { { ch.color, "[" .. ch.name .. "] " } }
    if ch.action then
        -- RP: an action, "* Name does something".
        segs[#segs + 1] = { ch.color, "* " }
        segs[#segs + 1] = { nameCol, name }
        segs[#segs + 1] = { ch.color, " " .. text }
    else
        segs[#segs + 1] = { nameCol, name }
        if ch.private then
            local to = IsValid(target) and target:Nick() or "?"
            segs[#segs + 1] = { COL_DIM, (target == LocalPlayer() and " → you" or (" → " .. to)) }
        end
        segs[#segs + 1] = { ch.id == "event" and ch.color or COL_TEXT, ": " .. text }
    end
    Chat.Add(segs, IsValid(sender) and sender:SteamID64() or nil)
    if ch.id == "event" then
        Chat.ShowEvent(name, text)
        surface.PlaySound("buttons/blip1.wav")
    else
        chat.PlaySound()
    end
    MsgC(ch.color, "[" .. ch.name .. "] ", nameCol, name, COL_TEXT, (ch.action and " " or ": ") .. text .. "\n")
end)

--------------------------------------------------------------------------
-- Avatars: one AvatarImage per sender, drawn by hand.
--------------------------------------------------------------------------

local avatars, avatarCount = {}, 0

local function avatarFor(sid)
    local a = avatars[sid]
    if IsValid(a) then return a end
    if avatarCount > 64 then  -- plenty for a busy chat; start over rather than grow forever
        for _, p in pairs(avatars) do
            if IsValid(p) then p:Remove() end
        end
        avatars, avatarCount = {}, 0
    end
    a = vgui.Create("AvatarImage")
    a:SetPaintedManually(true)
    a:SetSize(32, 32)
    a:SetSteamID(sid, 32)
    avatars[sid] = a
    avatarCount = avatarCount + 1
    return a
end

--------------------------------------------------------------------------
-- Layout and shape
--------------------------------------------------------------------------

-- The helmet's cheek curve (same numbers as cl_60_visor.lua), moved down
-- by VISOR_INSET so the chat sits just inside the helmet's edge. In
-- first person the chat fills the cheek: left screen edge, bottom, and
-- this curve as its top-right edge.
local VISOR_INSET = 0.02   -- share of the screen height

local function bezier(t, p0, p1, p2, p3)
    local u = 1 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
end

local curveCache = { w = 0, h = 0 }
local function visorCurve()
    local W, H = ScrW(), ScrH()
    if curveCache.w == W and curveCache.h == H then return curveCache.pts end
    local pts = {}
    for i = 0, 48 do
        local t = i / 48
        pts[#pts + 1] = { bezier(t, 0, 0.3, 0.39, 0.4) * W, (bezier(t, 0.75, 0.8, 0.86, 1.0) + VISOR_INSET) * H }
    end
    curveCache = { w = W, h = H, pts = pts }
    return pts
end

-- Chat.VisorEdgeX(y): x of the chat's curved edge at screen height y (the
-- chat is left of it). Only meaningful for the visor layout.
function Chat.VisorEdgeX(y)
    local pts = visorCurve()
    if y <= pts[1][2] then return pts[1][1] end
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if y >= a[2] and y <= b[2] then
            return a[1] + (b[1] - a[1]) * ((y - a[2]) / math.max(b[2] - a[2], 0.001))
        end
    end
    return pts[#pts][1]
end

-- Height of the curved edge at screen x.
local function visorEdgeY(x)
    local pts = visorCurve()
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if x >= a[1] and x <= b[1] then
            return a[2] + (b[2] - a[2]) * ((x - a[1]) / math.max(b[1] - a[1], 0.001))
        end
    end
    return pts[1][2]
end

-- Chat.Rect(): x, y, w, h of the chat area in screen pixels, and whether
-- it's the visor version (true while rhylib_hud's helmet visor is drawn).
-- Visor: the left cheek; its width leaves room for rhylib_radio's compass
-- (Radio.CompassChatWidth). Otherwise: bottom-left, 22% of the screen wide.
-- Example: local x, y, w, h, visor = Rhylib.Chat.Rect()
function Chat.Rect()
    local W, H = ScrW(), ScrH()
    local s = H / 1080
    local HUD = Rhylib.HUD
    if HUD and HUD.VisorActive and HUD.VisorActive() then
        local mx, my = HUD.Margins("ammo")  -- same margins as the ammo box on the other cheek
        local bottom = H - my
        local top = math.floor(visorEdgeY(mx))
        local w = math.floor(W * 0.25)
        -- Up to the radio's compass / squares (rhylib_radio).
        local R = Rhylib.Radio
        if R and R.CompassChatWidth then
            w = R.CompassChatWidth() or w
        elseif R and R.RadarOn and R.RadarOn() then
            w = math.floor(W * 0.125)
        end
        return mx, top, w, bottom - top, true
    end
    local w, h = math.floor(W * 0.22), math.floor(260 * s)
    return math.floor(24 * s), H - math.floor(210 * s) - h, w, h, false
end


-- Outline of the frame, clockwise, in screen px. Visor: the top-right
-- corner follows the cheek curve (shifted down into the box). Otherwise
-- a small cut corner, like the HUD plates.
local shapeCache = { key = "" }
local function shape(x, y, w, h, visor)
    local key = x .. "," .. y .. "," .. w .. "," .. h .. "," .. tostring(visor)
    if shapeCache.key == key then return shapeCache.pts, shapeCache.top end
    local x1, y1 = x + w, y + h
    local pts, top = { { x = x, y = y } }, { { x, y } }

    if visor then
        -- Along the curve from the top-left corner to the right edge, then
        -- straight down. Both ends sit exactly on the curve (y is rounded),
        -- or the outline would dent inward and the fill would draw wrong.
        local cy = visorEdgeY(x)
        pts[1].y, top[1][2] = cy, cy
        for _, c in ipairs(visorCurve()) do
            if c[1] > x and c[1] < x1 and c[2] > cy and c[2] < y1 then
                pts[#pts + 1] = { x = c[1], y = c[2] }
                top[#top + 1] = { c[1], c[2] }
            end
        end
        local ey = math.min(visorEdgeY(x1), y1)
        pts[#pts + 1] = { x = x1, y = ey }
        top[#top + 1] = { x1, ey }
    else
        local cut = math.floor(14 * ScrH() / 1080)
        pts[#pts + 1] = { x = x1 - cut, y = y }
        pts[#pts + 1] = { x = x1, y = y + cut }
        top[#top + 1] = { x1 - cut, y }
        top[#top + 1] = { x1, y + cut }
    end
    pts[#pts + 1] = { x = x1, y = y1 }
    pts[#pts + 1] = { x = x, y = y1 }
    shapeCache = { key = key, pts = pts, top = top }
    return pts, top
end

--------------------------------------------------------------------------
-- Messages: wrapping and drawing
--------------------------------------------------------------------------

-- Word-wraps a message into lines of { { col, text, x } } for width w.
-- Words of the same colour on a line are joined into one piece, so a line
-- is a handful of draw calls. Cached until the width or font changes.
local function wrap(msg, font, w)
    local key = font .. w
    local cache = msg.wraps
    if cache and cache[key] then return cache[key] end
    if not cache or cache.n > 6 then
        cache = { n = 0 }
        msg.wraps = cache
    end
    surface.SetFont(font)
    local spaceW = surface.GetTextSize(" ")
    local lines, line, x = {}, {}, 0
    for _, seg in ipairs(msg.segs) do
        local run = nil  -- the piece words of this segment are joining
        local pendingSpace = 0
        for word, space in string.gmatch(seg[2], "(%S*)(%s*)") do
            -- A word wider than a whole line (someone holding a key down)
            -- is cut into pieces that each fit, carrying on on the next line.
            local ww = word ~= "" and surface.GetTextSize(word) or 0
            while ww > w do
                local room = w - (x > 0 and (x + pendingSpace * spaceW) or 0)
                -- Characters, not bytes; text that isn't valid UTF-8 is cut by byte.
                local chars = utf8.len(word)
                local function prefix(n)
                    if not chars then return string.sub(word, 1, n) end
                    return string.sub(word, 1, (utf8.offset(word, n + 1) or (#word + 1)) - 1)
                end
                local piece = ""
                for n = 1, chars or #word do
                    local nextPiece = prefix(n)
                    if surface.GetTextSize(nextPiece) > room then break end
                    piece = nextPiece
                end
                if piece == "" and x == 0 then piece = prefix(1) end  -- always place at least one character
                if piece ~= "" then
                    x = x + pendingSpace * spaceW
                    if run then run[2] = run[2] .. string.rep(" ", pendingSpace) .. piece else
                        run = { seg[1], piece, x }
                        line[#line + 1] = run
                    end
                    word = string.sub(word, #piece + 1)
                    ww = surface.GetTextSize(word)
                end
                lines[#lines + 1] = line
                line, x, run, pendingSpace = {}, 0, nil, 0
            end
            if word ~= "" then
                if x > 0 and x + pendingSpace * spaceW + ww > w then
                    lines[#lines + 1] = line
                    line, x, run, pendingSpace = {}, 0, nil, 0
                end
                x = x + pendingSpace * spaceW
                if run then
                    run[2] = run[2] .. string.rep(" ", pendingSpace) .. word
                else
                    run = { seg[1], word, x }
                    line[#line + 1] = run
                end
                x = x + ww
                pendingSpace = 0
            end
            pendingSpace = pendingSpace + #space
        end
        x = x + pendingSpace * spaceW  -- trailing space before the next segment
    end
    lines[#lines + 1] = line
    cache[key] = lines
    cache.n = cache.n + 1
    return lines
end

-- Reused colours, so drawing allocates nothing.
local drawCol, shadowCol = Color(255, 255, 255), Color(0, 0, 0)

local function text(str, x, y, col, alpha)
    shadowCol.a = alpha * 0.8
    surface.SetTextColor(shadowCol)
    surface.SetTextPos(x + 1, y + 1)
    surface.DrawText(str)
    drawCol.r, drawCol.g, drawCol.b, drawCol.a = col.r, col.g, col.b, alpha
    surface.SetTextColor(drawCol)
    surface.SetTextPos(x, y)
    surface.DrawText(str)
end

-- Draws messages bottom-up into the box (screen px); open = all, scrollable.
-- widthAt(lineTop): optional, the width a line at that height may use
-- (the visor chat narrows toward the top). Widths snap to 8 px so the
-- wrap cache stays small.
local function drawMessages(x, y, w, h, font, lineH, open, widthAt)
    local now = RealTime()
    local yy = y + h
    local skip = open and Chat.scroll or 0
    local avSize = lineH - 2
    local indent = avSize + math.floor(lineH * 0.3)
    surface.SetFont(font)
    for i = #Chat.lines, 1, -1 do
        local msg = Chat.lines[i]
        local age = now - msg.time
        if not open and age > SHOW_TIME then break end
        local alpha = open and 255 or math.Clamp((SHOW_TIME - age) * 255, 0, 255)
        local ind = msg.sid and indent or 0
        local avail = widthAt and math.min(w, widthAt(yy - lineH)) or w
        avail = math.floor(avail / 8) * 8
        if avail - ind < 60 then return end  -- no room left up here
        local lines = wrap(msg, font, avail - ind)
        if widthAt and #lines > 1 then
            -- Its top line sits higher, where there may be less room.
            local topAvail = math.floor(math.min(w, widthAt(yy - #lines * lineH)) / 8) * 8
            if topAvail < avail and topAvail - ind >= 60 then lines = wrap(msg, font, topAvail - ind) end
        end
        for k = #lines, 1, -1 do
            if skip > 0 then
                skip = skip - 1
            else
                yy = yy - lineH
                if yy < y then return end
                for _, part in ipairs(lines[k]) do
                    text(part[2], x + ind + part[3], yy, part[1], alpha)
                end
                if k == 1 and msg.sid and alpha > 20 then
                    if msg.model and UI.DrawPortrait then
                        UI.DrawPortrait(msg.model, x, yy + 1, avSize, alpha)
                    else
                        local av = avatarFor(msg.sid)
                        av:SetAlpha(alpha)
                        av:SetPos(x, yy + 1)
                        av:SetSize(avSize, avSize)
                        av:PaintManual()
                    end
                    surface.SetFont(font)  -- (painting may change it)
                end
            end
        end
    end
end

-- Sizes shared by the open window and the closed feed, so lines don't jump.
local function metrics(visor)
    local s = ScrH() / 1080
    return {
        s = s,
        font = UI.Font(visor and 17 or 18),
        lineH = math.floor((visor and 21 or 23) * s),
        header = visor and 0 or math.floor(20 * s),  -- the visor chat has no header bar (its top is the curve)
        inputH = math.floor((visor and 24 or 28) * s),
        pad = math.floor(7 * s),
        rowH = math.floor((visor and 18 or 22) * s),
    }
end

-- The message area inside the frame (screen px).
local function messageArea(x, y, w, h, m)
    return x + m.pad, y + m.header + m.pad * 0.5, w - m.pad * 2, h - m.header - m.inputH - m.pad * 1.5
end

-- Frame: dark plate, header bar, edges and corner ticks, input box and
-- channel button. Drawn at origin (ox, oy): 0, 0 inside the window panel,
-- or the screen position when the chat is pinned but closed.
-- hint: text in the input box when it isn't being typed in.
local localPts = {}
local function drawFrame(ox, oy, sx, sy, w, h, visor, m, chanW, hover, hint)
    local pts, top = shape(sx, sy, w, h, visor)
    for i, p in ipairs(pts) do
        localPts[i] = localPts[i] or { x = 0, y = 0 }
        localPts[i].x, localPts[i].y = p.x - sx + ox, p.y - sy + oy
    end
    for i = #pts + 1, #localPts do localPts[i] = nil end

    draw.NoTexture()
    surface.SetDrawColor(COL_BG)
    surface.DrawPoly(localPts)

    -- Header bar: a band along the top, under the shaped edge (third person).
    local headW = visor and 0 or math.min(w, (top[2] and top[2][1] or sx + w) - sx)
    local ch = currentChannel()
    if headW > 0 then
    surface.SetDrawColor(COL_HEADER)
    surface.DrawRect(ox, oy, headW, m.header)
    surface.SetDrawColor(ch.color.r, ch.color.g, ch.color.b, 170)
    surface.DrawRect(ox, oy + m.header - 1, headW, 1)
    draw.SimpleText("COMMS", UI.Font(12, 700), ox + m.pad, oy + m.header * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.upper(ch.name), UI.Font(12, 700), ox + m.pad + math.floor(48 * m.s), oy + m.header * 0.5, ch.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Edges: dark outline with a light line along the top and the slope.
    surface.SetDrawColor(COL_EDGE_DARK)
    for i = 1, #localPts do
        local a, b = localPts[i], localPts[i % #localPts + 1]
        surface.DrawLine(a.x, a.y, b.x, b.y)
    end
    surface.SetDrawColor(COL_EDGE_LIGHT)
    for i = 1, #top - 1 do
        surface.DrawLine(top[i][1] - sx + ox, top[i][2] - sy + oy + 1, top[i + 1][1] - sx + ox, top[i + 1][2] - sy + oy + 1)
    end

    -- Corner ticks, bottom-left and bottom-right.
    local t = math.floor(8 * m.s)
    surface.SetDrawColor(COL_TICK)
    surface.DrawRect(ox, oy + h - 2, t, 2)
    surface.DrawRect(ox, oy + h - t, 2, t)
    surface.DrawRect(ox + w - t, oy + h - 2, t, 2)
    surface.DrawRect(ox + w - 2, oy + h - t, 2, t)

    -- Input line and the channel button.
    local iy = oy + h - m.inputH - math.floor(3 * m.s)
    local iw = w - m.pad - math.floor(6 * m.s)
    if visor then  -- stop short of the curved edge at the input's top
        iw = math.min(iw, math.floor(Chat.VisorEdgeX(sy + (iy - oy)) - sx) - m.pad - math.floor(6 * m.s))
    end
    surface.SetDrawColor(COL_INPUT)
    surface.DrawRect(ox + m.pad, iy, iw, m.inputH)
    surface.SetDrawColor(COL_INPUT_EDGE)
    surface.DrawOutlinedRect(ox + m.pad, iy, iw, m.inputH)
    surface.SetDrawColor(hover and COL_ROW_PICK or COL_HEADER)
    surface.DrawRect(ox + m.pad + 1, iy + 1, chanW, m.inputH - 2)
    surface.SetDrawColor(ch.color)
    surface.DrawRect(ox + m.pad + 1, iy + 1, 3, m.inputH - 2)
    draw.SimpleText(ch.name .. " ▾", UI.Font(visor and 13 or 14, 700), ox + m.pad + 1 + (chanW + 3) * 0.5, iy + m.inputH * 0.5,
        ch.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if hint then
        draw.SimpleText(hint, m.font, ox + m.pad + chanW + math.floor(12 * m.s), iy + m.inputH * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- Width of the channel button on the left of the input line.
local function chanWidth(visor, m)
    return math.floor((visor and 70 or 80) * m.s)
end

-- Closed chat. Normally: recent messages only, fading, no frame. Pinned
-- (/togglechat): the whole window stays up, and opening the chat just
-- lets you type into it.
local pinVar = CreateClientConVar("rhylib_chat_pinned", "0", true, false, "Keep the chat window always visible (0/1). Toggle in chat with /togglechat")

local function bindName()
    local key = input.LookupBinding("messagemode")
    return key and string.upper(key) or "your chat key"
end

Rhylib.Hook.Add("HUDPaint", "chat.feed", function()
    if IsValid(Chat.panel) then return end
    local pinned = pinVar:GetBool()
    local x, y, w, h, visor = Chat.Rect()
    local m = metrics(visor)
    if pinned then
        local Rh = Rhylib.HUD
        if Rh and Rh.Hidden and Rh.Hidden() then return end
        drawFrame(x, y, x, y, w, h, visor, m, chanWidth(visor, m), false, "Press " .. bindName() .. " to type")
    else
        local last = Chat.lines[#Chat.lines]
        if not last or RealTime() - last.time > SHOW_TIME then return end
    end
    local ax, ay, aw, ah = messageArea(x, y, w, h, m)
    drawMessages(ax, ay, aw, ah, m.font, m.lineH, pinned, visor and function(ly) return Chat.VisorEdgeX(ly) - ax - m.pad end)
end)

Rhylib.Hook.Add("HUDShouldDraw", "chat.hidedefault", function(name)
    if name == "CHudChat" then return false end
end)

--------------------------------------------------------------------------
-- Suggestions and the channel list
--------------------------------------------------------------------------

-- What to list above the input line for the text typed so far:
-- player names after "/pm " or "/w ", else channel commands matching "/x"
-- (only channels you can use) and /togglechat. Rows: { label, desc, fill, col }.
local function suggestions(textValue)
    local out = {}
    local pmName = string.match(textValue, '^/[pP][mM]%s+"?([^"%s]*)$') or string.match(textValue, "^/[wW]%s+(%S*)$")
    if pmName then
        local cmd = string.match(textValue, "^(/%S+)")
        for _, p in ipairs(player.GetAll()) do
            if p ~= LocalPlayer() and string.find(string.lower(p:Nick()), string.lower(pmName), 1, true) then
                local nick = p:Nick()
                local fill = string.find(nick, " ", 1, true) and ('"' .. nick .. '" ') or (nick .. " ")
                out[#out + 1] = { label = nick, desc = "private message", fill = cmd .. " " .. fill, col = Chat.byId.pm.color }
            end
        end
        return out
    end
    local typed = string.match(textValue, "^/(%S*)$")
    if not typed then return out end
    typed = string.lower(typed)
    for _, ch in ipairs(Chat.CHANNELS) do
        for _, cmd in ipairs(Chat.CanUse(LocalPlayer(), ch) and ch.cmds or {}) do
            if string.sub(cmd, 1, #typed) == typed then
                out[#out + 1] = { label = "/" .. cmd, desc = ch.desc, fill = "/" .. cmd .. " ", col = ch.color }
                break
            end
        end
    end
    if string.sub("togglechat", 1, #typed) == typed then
        out[#out + 1] = { label = "/togglechat", desc = "keep the chat on screen (or not)", fill = "/togglechat" }
    end
    return out
end

-- Channel picker rows (when the channel name is clicked).
local function channelRows()
    local out = {}
    for _, ch in ipairs(Chat.CHANNELS) do
        if ch.private then
            out[#out + 1] = { label = "Private message", desc = "/pm name", col = ch.color, pm = true }
        elseif not Chat.CanUse(LocalPlayer(), ch) then
            -- (squad / battalion / command you're not in: not listed)
        else
            out[#out + 1] = { label = ch.name, desc = ch.desc, col = ch.color, ch = ch }
        end
    end
    return out
end

--------------------------------------------------------------------------
-- The open window
--------------------------------------------------------------------------

-- chat.typing to the server (NW2Bool rhylib_typing for the HUD's icon).
local function sendTyping(on)
    Rhylib.Net.Start("chat.typing")
    net.WriteBool(on)
    net.SendToServer()
end

-- Sends a line. Returns true if the window should stay open (a channel switch).
local function submit(str)
    str = string.Trim(str)
    if str == "" then return false end
    -- Remember it for Up/Down (no repeats in a row, the last 30).
    local hist = Chat.history
    if hist[#hist] ~= str then
        hist[#hist + 1] = str
        if #hist > 30 then table.remove(hist, 1) end
    end
    -- Chat's own settings, handled here (never sent).
    local low = string.lower(str)
    if low == "/togglechat" or low == "/pinchat" then
        local on = not pinVar:GetBool()
        RunConsoleCommand("rhylib_chat_pinned", on and "1" or "0")
        Chat.Add({ { COL_SYSTEM, on and "Chat pinned: it stays on screen. /togglechat to undo." or "Chat unpinned: it fades when closed." } })
        return true
    end
    local kind, a, b, c = Chat.Parse(str, currentChannel())
    if kind == "pass" then
        RunConsoleCommand("say", str)  -- DarkRP and admin mod commands
    elseif kind == "switch" then
        local ok, why = Chat.CanUse(LocalPlayer(), a)
        if not ok then
            Chat.Add({ { COL_SYSTEM, why } })
            return true
        end
        if not a.private then Chat.current = a end
        return true
    elseif kind == "usage" then
        Chat.Add({ { COL_SYSTEM, a } })
        return true
    elseif kind == "send" then
        -- (e.g. still on Squad after leaving the squad: say so, don't send it elsewhere)
        local ok, why = Chat.CanUse(LocalPlayer(), a)
        if not ok then
            Chat.Add({ { COL_SYSTEM, why .. ". Pick another channel (click the channel name)." } })
            return true
        end
        local target = NULL
        if a.private then
            target = Chat.FindPlayer(c)
            if not IsValid(target) then
                Chat.Add({ { COL_SYSTEM, "No player called \"" .. c .. "\"" } })
                return true
            end
        end
        Rhylib.Net.Start("chat.send")
        net.WriteUInt(a.index, Chat.CHANNEL_BITS)
        net.WriteEntity(target)
        net.WriteString(b)
        net.SendToServer()
    end
    return false
end

-- The open chat window ("RhylibChat"): a frame with a DTextEntry. The
-- frame is painted here; messages and pop-up lists are drawn in
-- PostRenderVGUI "chat.window" below.
local PANEL = {}

function PANEL:Init()
    self.pick = 1
    self.suggest = {}
    self.menu = nil  -- channel picker rows while open

    local entry = vgui.Create("DTextEntry", self)
    entry:SetTextColor(COL_TEXT)
    entry:SetCursorColor(COL_TEXT)
    entry:SetHighlightColor(Color(70, 100, 140))
    entry:SetPaintBackground(false)
    entry.Paint = function(e, w, h)
        e:DrawTextEntryText(COL_TEXT, Color(70, 100, 140), COL_TEXT)
        local len = #e:GetValue()
        if len == 0 then
            draw.SimpleText("Message " .. currentChannel().name .. "…", self.m.font, 2, h * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        elseif len > maxLength() - 40 then
            draw.SimpleText(len .. "/" .. maxLength(), UI.Font(12), w - 4, h * 0.5, len >= maxLength() and Color(226, 75, 74) or COL_DIM,
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    -- Character limit (the server cuts longer messages anyway).
    entry.AllowInput = function(e)
        if #e:GetValue() >= maxLength() then return true end
    end
    entry.OnEnter = function(e)
        local value = e:GetValue()
        local pick = self.suggest[self.pick]
        -- Enter on a half-typed command fills it in first.
        if pick and string.match(value, "^/%S*$") and value ~= string.Trim(pick.fill) then
            self:Fill(pick.fill)
            return
        end
        if submit(value) then
            e:SetText("")
            self:UpdateSuggest()
            e:RequestFocus()
            return
        end
        Chat.Close()
    end
    entry.OnChange = function(e)
        local value = e:GetValue()
        if #value > maxLength() then  -- pasted past the limit
            e:SetText(string.sub(value, 1, maxLength()))
            e:SetCaretPos(maxLength())
        end
        self.menu = nil
        self:CheckSwitch()
        self:UpdateSuggest()
        hook.Run("ChatTextChanged", e:GetValue())
    end
    entry.OnKeyCodeTyped = function(e, code)
        if code == KEY_ESCAPE then
            Chat.Close()
            Chat.hideMenuUntil = RealTime() + 0.3
            return true
        elseif code == KEY_TAB then
            local pick = self.suggest[self.pick]
            if pick then self:Fill(pick.fill) end
            timer.Simple(0, function() if IsValid(e) then e:RequestFocus() end end)
            return true
        elseif code == KEY_UP and #self.suggest > 0 then
            self.pick = math.max(1, self.pick - 1)
            return true
        elseif code == KEY_DOWN and #self.suggest > 0 then
            self.pick = math.min(#self.suggest, self.pick + 1)
            return true
        elseif code == KEY_UP or code == KEY_DOWN then
            -- Your earlier messages: Up goes back, Down comes forward.
            local hist = Chat.history
            if #hist == 0 then return true end
            local i = (self.histIndex or (#hist + 1)) + (code == KEY_UP and -1 or 1)
            i = math.Clamp(i, 1, #hist + 1)
            self.histIndex = i
            local value = hist[i] or ""
            e:SetText(value)
            e:SetCaretPos(#value)
            self.suggest = {}
            return true
        elseif code == KEY_ENTER or code == KEY_PAD_ENTER then
            e:OnEnter()
            return true
        end
    end
    self.entry = entry
    self:Layout()
end

function PANEL:Fill(str)
    self.entry:SetText(str)
    self.entry:SetCaretPos(#str)
    self.entry:RequestFocus()
    self:CheckSwitch()
    self:UpdateSuggest()
end

-- "/local " (a channel command and a space) switches channel at once.
function PANEL:CheckSwitch()
    local value = self.entry:GetValue()
    local cmd = string.match(value, "^/(%S+)%s$")
    local ch = (value == "// " and Chat.byId.public) or (cmd and Chat.byCmd[string.lower(cmd)])
    if ch and not ch.private and Chat.CanUse(LocalPlayer(), ch) then
        Chat.current = ch
        self.entry:SetText("")
    end
end

function PANEL:Layout()
    local x, y, w, h, visor = Chat.Rect()
    self.visor = visor
    self.m = metrics(visor)
    local m = self.m
    self:SetPos(x, y)
    self:SetSize(w, h)
    self.chanW = chanWidth(visor, m)
    local ix = self.chanW + math.floor(10 * m.s)
    self.entry:SetFont(m.font)
    local iy = h - m.inputH - math.floor(3 * m.s)
    local right = w
    if visor then right = math.min(w, math.floor(Chat.VisorEdgeX(y + iy) - x)) end
    self.entry:SetPos(ix, iy)
    self.entry:SetSize(right - ix - math.floor(8 * m.s), m.inputH)
end

function PANEL:UpdateSuggest()
    self.suggest = suggestions(self.entry:GetValue())
    self.pick = math.Clamp(self.pick, 1, math.max(1, #self.suggest))
end

function PANEL:Think()
    local x, y, w, h, visor = Chat.Rect()
    if visor ~= self.visor or w ~= self:GetWide() then self:Layout() end
end

function PANEL:ChannelButtonHit(mx, my)
    local h, m = self:GetTall(), self.m
    return mx >= m.pad and mx <= m.pad + self.chanW and my >= h - m.inputH - math.floor(3 * m.s) and my <= h
end

-- Rows of a pop-up list (suggestions or channels), in panel coordinates:
-- just above the input line, inside the frame.
function PANEL:ListRows(list)
    local m = self.m
    local h = self:GetTall()
    local bottom = h - m.inputH - math.floor(6 * m.s)
    local maxRows = math.max(1, math.floor((bottom - m.header) / m.rowH))
    local n = math.min(#list, maxRows)
    local rows = {}
    local sx, sy = self:LocalToScreen(0, 0)
    for i = 1, n do
        local ry = bottom - (n - i + 1) * m.rowH
        local rw = self:GetWide() - m.pad * 2
        if self.visor then rw = math.min(rw, Chat.VisorEdgeX(sy + ry) - sx - m.pad * 2) end
        rows[i] = { x = m.pad, y = ry, w = rw, h = m.rowH, item = list[i] }
    end
    return rows
end

function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT then return end
    local mx, my = self:CursorPos()
    if self.menu then
        for _, r in ipairs(self:ListRows(self.menu)) do
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                if r.item.pm then
                    self:Fill("/pm ")
                else
                    Chat.current = r.item.ch
                end
                break
            end
        end
        self.menu = nil
        self.entry:RequestFocus()
        return
    end
    if self:ChannelButtonHit(mx, my) then
        self.menu = channelRows()
        return
    end
    for i, r in ipairs(self:ListRows(self.suggest)) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            self.pick = i
            self:Fill(r.item.fill)
            return
        end
    end
    self.entry:RequestFocus()
end

function PANEL:OnMouseWheeled(delta)
    Chat.scroll = math.max(0, Chat.scroll + delta * 3)
    return true
end

function PANEL:Paint(w, h)
    local sx, sy = self:LocalToScreen(0, 0)
    local mx, my = self:CursorPos()
    local hover = self:ChannelButtonHit(mx, my) or self.menu ~= nil
    drawFrame(0, 0, sx, sy, w, h, self.visor, self.m, self.chanW, hover)
end

-- One row of a pop-up list.
local function drawRow(px, py, r, picked, m)
    local x, y = px + r.x, py + r.y
    surface.SetDrawColor(picked and COL_ROW_PICK or COL_ROW)
    surface.DrawRect(x, y, r.w, r.h)
    surface.SetDrawColor(COL_ROW_LINE)
    surface.DrawRect(x, y + r.h - 1, r.w, 1)
    local col = r.item.col or COL_TEXT
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, 3, r.h)
    local current = r.item.ch and r.item.ch == currentChannel()
    draw.SimpleText(r.item.label .. (current and "  ●" or ""), UI.Font(14, 700), x + 10 * m.s, y + r.h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(r.item.desc, UI.Font(12), x + r.w - 8 * m.s, y + r.h * 0.5, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

-- Messages, avatars and lists, on top of the frame, in screen space
-- (after all VGUI, so avatars can be painted by hand).
Rhylib.Hook.Add("PostRenderVGUI", "chat.window", function()
    local p = Chat.panel
    if not IsValid(p) then return end
    local px, py = p:LocalToScreen(0, 0)
    local w, h, m = p:GetWide(), p:GetTall(), p.m
    local ax, ay, aw, ah = messageArea(px, py, w, h, m)
    drawMessages(ax, ay, aw, ah, m.font, m.lineH, true, p.visor and function(ly) return Chat.VisorEdgeX(ly) - ax - m.pad end)
    if Chat.scroll > 0 then
        draw.SimpleText("▲ " .. Chat.scroll, UI.Font(12), px + w - m.pad, py + m.header * 0.5, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local list = p.menu or p.suggest
    if #list > 0 then
        local mx, my = p:CursorPos()
        for i, r in ipairs(p:ListRows(list)) do
            local hovered = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
            drawRow(px, py, r, hovered or (not p.menu and i == p.pick), m)
        end
    end
end)

vgui.Register("RhylibChat", PANEL, "EditablePanel")

-- Chat.Open(): opens the chat window with the keyboard on it (what the chat
-- key does). Fires the StartChat hook and tells the server you're typing.
function Chat.Open()
    if IsValid(Chat.panel) then return end
    Chat.scroll = 0
    local p = vgui.Create("RhylibChat")
    p:MakePopup()
    p.entry:RequestFocus()
    Chat.panel = p
    hook.Run("StartChat", false)
    sendTyping(true)
end

-- Chat.Close(): closes it again (Enter, Esc). Fires FinishChat.
function Chat.Close()
    if not IsValid(Chat.panel) then return end
    Chat.panel:Remove()
    Chat.panel = nil
    Chat.scroll = 0  -- a pinned chat shows the newest lines again
    hook.Run("FinishChat")
    hook.Run("ChatTextChanged", "")
    sendTyping(false)
end

-- Escape closes the chat; don't let it open the game menu too
-- (for 0.3 s after Esc, any game menu that opened is hidden again).
Rhylib.Hook.Add("Think", "chat.escape", function()
    if Chat.hideMenuUntil and RealTime() < Chat.hideMenuUntil and gui.IsGameUIVisible() then
        gui.HideGameUI()
    end
end)

-- The chat keys open ours instead of the default box.
Rhylib.Hook.Add("PlayerBindPress", "chat.open", function(_, bind, pressed)
    if not pressed then return end
    if string.find(bind, "messagemode", 1, true) then
        Chat.Open()
        return true
    end
end)

--------------------------------------------------------------------------
-- Event banner: the latest event, top centre, for a few seconds.
--------------------------------------------------------------------------

local EVENT_TIME = 9
local event
local COL_EVENT = Color(255, 205, 80)

-- Chat.ShowEvent(by, text): shows the gold Event banner at the top centre
-- for EVENT_TIME seconds (replaces any banner showing). Client only.
-- Example: Rhylib.Chat.ShowEvent("Admin", "Training starts in 5 minutes")
function Chat.ShowEvent(by, text)
    event = { by = by, text = text, at = CurTime() }
end

Rhylib.Hook.Add("HUDPaint", "chat.event", function()
    if not event then return end
    local age = CurTime() - event.at
    if age > EVENT_TIME then
        event = nil
        return
    end
    local a = math.min(1, age * 4, (EVENT_TIME - age) * 1.5)
    local s = ScrH() / 1080
    local font, small = UI.Font(math.floor(20 * s + 0.5), 700), UI.Font(math.floor(13 * s + 0.5))
    surface.SetFont(font)
    local tw = surface.GetTextSize(event.text)
    local w = math.min(math.max(tw + 60 * s, 360 * s), ScrW() * 0.7)
    local h = 62 * s
    local x, y = math.floor((ScrW() - w) * 0.5), math.floor(90 * s)
    surface.SetDrawColor(COL_BG.r, COL_BG.g, COL_BG.b, COL_BG.a * a)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(COL_EVENT.r, COL_EVENT.g, COL_EVENT.b, 255 * a)
    surface.DrawRect(x, y, w, math.max(2, math.floor(2 * s)))
    surface.SetDrawColor(COL_EDGE_DARK.r, COL_EDGE_DARK.g, COL_EDGE_DARK.b, COL_EDGE_DARK.a * a)
    surface.DrawOutlinedRect(x, y, w, h)
    draw.SimpleText("EVENT · " .. string.upper(event.by), small, x + w * 0.5, y + 16 * s, ColorAlpha(COL_EVENT, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    -- Long text is cut to the banner width (the full line is in the chat).
    local text = event.text
    if tw > w - 30 * s then
        while #text > 1 and surface.GetTextSize(text .. "…") > w - 30 * s do
            text = string.sub(text, 1, (utf8.offset(text, -1) or #text) - 1)  -- drop one whole character
        end
        text = text .. "…"
        event.text, tw = text, surface.GetTextSize(text)
    end
    draw.SimpleText(text, font, x + w * 0.5, y + 40 * s, ColorAlpha(COL_TEXT, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
