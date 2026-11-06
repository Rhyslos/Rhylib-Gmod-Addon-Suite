--[[
    Chat, client side: replaces the default chat box.

    Closed: the newest messages float on their own (a soft dark band with
    the channel's colour on the left) and fade after 12 s. Or, pinned with
    /togglechat (rhylib_chat_pinned 1), the whole window stays on screen
    and opening the chat just lets you type.
    Open (your chat key), two looks (client convar rhylib_chat_style,
    Settings > Interface > Chat "Chat look"):
      b "Comms" (default)  a header band in the channel's colour with a
                           diamond and "COMMS · SQUAD ALPHA" (the squad
                           name and size from rhylib_radio); one row per
                           message: a rank chip edged in the sender's job
                           colour, the name, the channel in its colour,
                           the time, the text under them, the channel's
                           colour down the left; system lines dim; channel
                           buttons above the input (click to talk there).
      a "Tabs"             tabs along the top (All and each channel you
                           can use, unread counts; a tab only filters what
                           you see); one line per message with a solid
                           channel pill, rank, name, text and the time; a
                           solid channel button by the input (click to
                           pick where you talk).
    In first person under the helmet visor the chat fills the left cheek
    (its top edge follows the helmet) with one line per message and the
    channel pill, in both looks.
    Typing a channel command (/local, /public, ...) followed by a space
    switches channel straight away. Typing "/" shows matching commands
    (and player names after /pm); Tab or Enter fills one in, Up/Down picks
    (with no list open, Up/Down walks through what you sent). The mouse
    wheel scrolls back.

    Where it sits:
      helmet visor (first person)  bottom-left, in the grey cheek area; its
                                   top-right edge follows the cheek's curve
      otherwise                    bottom-left, above the corner plate

    Everything other addons print with chat.AddText (DarkRP, admin mods,
    join messages) shows up here too.

    Drawing: the window panel only paints its frame and the input box.
    The messages and pop-up lists are drawn on top afterwards in screen
    space (PostRenderVGUI), over the text entry. Wrapped lines are cached
    per message.

    Client only. Adds to Rhylib.Chat: Chat.Add, Chat.Open, Chat.Close,
    Chat.Rect, Chat.VisorEdgeX, Chat.ShowEvent, Chat.lines, Chat.current,
    Chat.history, Chat.tab (look A's tab, a channel id or nil = All),
    Chat.unread ([channel id] = new lines), Chat.panel (the open window,
    a "RhylibChat" panel).
    Replaces chat.AddText (the old one is kept in Chat.oldAddText).
    Client convars: rhylib_chat_pinned (0/1, /togglechat), rhylib_chat_style (b / a).
    Net: receives chat.msg; sends chat.send and chat.typing (see sv_10_chat).
    Other addons read Chat.Rect (rhylib_radio sizes its visor parts around it).
]]

local Chat = Rhylib.Chat
local UI = Rhylib.UI

Chat.lines = Chat.lines or {}      -- { time, segs = { { col, text }, ... }, sid = sender SteamID64 }
Chat.current = Chat.current or nil -- current channel
Chat.scroll = 0
Chat.history = Chat.history or {}  -- lines you sent this session, oldest first
Chat.unread = Chat.unread or {}    -- [channel id] = lines since its tab was looked at (look A)

local function maxLength()
    return Rhylib.Config.Get("chat", "maxLength") or 300
end

local MAX_LINES = 150              -- history kept; the oldest line goes first
local SHOW_TIME = 12               -- seconds a message stays when the chat is closed

-- The window, the closed feed, the lists and the event banner draw with
-- theme tokens (kit tokens where the colour is the kit's, else "chat.<what>").
local KC = UI.Kit.C
local Col = UI.Col
local COL_BG = Col("chat.bg", 14, 16, 15, 238)
local COL_HEADER = KC.header
local COL_EDGE_DARK = KC.edgeDark
local COL_EDGE_LIGHT = KC.edgeLight
local COL_TICK = KC.tick
local COL_INPUT = Col("chat.input", 8, 9, 8, 255)
local COL_INPUT_EDGE = Col("chat.inputEdge", 58, 62, 58, 255)
local COL_TEXT = KC.text
local COL_DIM = KC.label
local COL_SYSTEM = Col("chat.system", 170, 176, 180)
local COL_ROW = Col("chat.row", 20, 22, 21, 250)
local COL_ROW_PICK = KC.buttonHover
local COL_ROW_LINE = Col("chat.rowLine", 40, 44, 40, 255)
local COL_DIM2 = Col("chat.dim2", 109, 111, 104)
local COL_SEP = Col("chat.sep", 26, 29, 27, 255)
local COL_FEED = Col("chat.feed", 10, 12, 11, 170)
local COL_B_BG = Col("chat.commsBg", 14, 16, 15, 240)
local COL_A_BG = Col("chat.tabsBg", 12, 14, 13, 222)
local COL_B_EDGE = Col("chat.edge", 42, 45, 41, 255)
local COL_WHITE = Col("chat.chipOn", 255, 255, 255)
local COL_ACCENT = KC.accent
local COL_DARK = Col("chat.onColour", 20, 20, 19)   -- (text on a channel-coloured pill / button)
local COL_HIGHLIGHT = Col("chat.highlight", 70, 100, 140)
local COL_LIMIT = KC.bad

-- The helmet-visor frame is part of the HUD (same look as the HUD's
-- corner plates): plain colours, not theme tokens.
local VIS_BG = Color(14, 16, 15, 238)
local VIS_HEADER = Color(22, 25, 23, 255)
local VIS_EDGE_DARK = Color(0, 0, 0, 230)
local VIS_EDGE_LIGHT = Color(170, 176, 180, 70)
local VIS_INPUT = Color(8, 9, 8, 255)
local VIS_INPUT_EDGE = Color(58, 62, 58, 255)
local VIS_DIM = Color(140, 142, 136)
local VIS_PICK = Color(38, 50, 64, 255)

-- The channel plain text goes to: Chat.current, else config chat
-- defaultChannel, else Public.
local function currentChannel()
    if not Chat.current then Chat.current = Chat.byId[Rhylib.Config.Get("chat", "defaultChannel")] or Chat.CHANNELS[1] end
    return Chat.current
end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

-- Chat.Add(segs, sid, info): adds a line to the chat box (not the console).
-- segs: list of { Color, text } pieces drawn in order (lines without info).
-- sid: the sender's SteamID64 (nil for system lines).
-- info (a channel message, from chat.msg): { ch, name, nameCol, rank,
-- bnCol, text, action, to }; the line is then drawn from these.
-- Example: Rhylib.Chat.Add({ { Color(255, 200, 80), "[Squad] " }, { color_white, "Moving out" } })
function Chat.Add(segs, sid, info)
    local lines = Chat.lines
    local line = { time = RealTime(), segs = segs, sid = sid, at = os.date("%H:%M") }
    if info then
        for k, v in pairs(info) do line[k] = v end
        -- (look A: a count on the tabs you aren't looking at; not your own lines)
        local ch = info.ch
        local mine = sid and IsValid(LocalPlayer()) and sid == LocalPlayer():SteamID64()
        if ch and not mine and GetConVarString("rhylib_chat_style") == "a"
            and (not IsValid(Chat.panel) or (Chat.tab and Chat.tab ~= ch.id)) then
            Chat.unread[ch.id] = (Chat.unread[ch.id] or 0) + 1
        end
    end
    lines[#lines + 1] = line
    if #lines > MAX_LINES then table.remove(lines, 1) end
    -- (keep the view still while scrolled up; the scroll counts messages,
    -- on look A only those on the tab you look at)
    if Chat.scroll > 0 and (not Chat.tab or (line.ch and line.ch.id == Chat.tab)) then Chat.scroll = Chat.scroll + 1 end
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
    -- What the comms look draws: rank chip (rhylib_roster prefix), name, text.
    local R = Rhylib.Roster
    local rank = ""
    if IsValid(sender) and R and R.Get and R.Prefix and R.Get(sender).has then rank = R.Prefix(sender) or "" end
    local to
    if ch.private then to = (target == LocalPlayer()) and "→ you" or ("→ " .. (IsValid(target) and target:Nick() or "?")) end
    Chat.Add(segs, IsValid(sender) and sender:SteamID64() or nil, {
        ch = ch, name = name, nameCol = nameCol, rank = rank, bnCol = nameCol, text = text, action = ch.action, to = to,
    })
    if ch.id == "event" then
        Chat.ShowEvent(name, text)
        surface.PlaySound("buttons/blip1.wav")
    else
        chat.PlaySound()
    end
    MsgC(ch.color, "[" .. ch.name .. "] ", nameCol, name, COL_TEXT, (ch.action and " " or ": ") .. text .. "\n")
end)

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

-- (rhylib_hud's realistic layout has its own straight cheek pad:
-- HUD.RealCheekY, cl_62_realistic.lua)
local curveCache = { w = 0, h = 0 }
local function visorCurve()
    local W, H = ScrW(), ScrH()
    local HUD = Rhylib.HUD
    local real = HUD and HUD.RealisticActive and HUD.RealisticActive() and HUD.RealCheekY and true or false
    local tall = real and HUD.RealGeo().key or ""
    if curveCache.w == W and curveCache.h == H and curveCache.real == real and curveCache.tall == tall then return curveCache.pts end
    local pts = {}
    if real then
        local g = HUD.RealGeo()
        local xs = { 0 }
        for i = 1, 24 do xs[#xs + 1] = g.cornerX * i / 24 end
        for i = 1, 24 do xs[#xs + 1] = g.cornerX + (g.bottomX - g.cornerX) * i / 24 end
        for _, x in ipairs(xs) do pts[#pts + 1] = { x, HUD.RealCheekY(x, -1) + VISOR_INSET * H } end
    else
        for i = 0, 48 do
            local t = i / 48
            pts[#pts + 1] = { bezier(t, 0, 0.3, 0.39, 0.4) * W, (bezier(t, 0.75, 0.8, 0.86, 1.0) + VISOR_INSET) * H }
        end
    end
    curveCache = { w = W, h = H, pts = pts, real = real, tall = tall }
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
-- (Radio.CompassChatWidth). Otherwise: bottom-left, 30% of the screen
-- wide (460-620 px at 1080p), 360 px tall.
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
    local w = math.floor(math.Clamp(W * 0.3, 460 * s, 620 * s))
    w = math.min(w, math.floor(W * 0.45))
    local h = math.floor(360 * s)
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

local function setCol(col, a)
    drawCol.r, drawCol.g, drawCol.b, drawCol.a = col.r, col.g, col.b, a or col.a or 255
    surface.SetDrawColor(drawCol)
end

-- The look: "b" (comms rows, default) or "a" (tabs and channel pills).
-- Settings > Interface > Chat "Chat look" (rhylib_chat_style).
local styleVar = CreateClientConVar("rhylib_chat_style", "b", true, false, "Chat look: b = comms rows (default), a = tabs and channel pills")
local function style() return styleVar:GetString() == "a" and "a" or "b" end

-- Sizes (1080p numbers scaled). One table per look and place, rebuilt
-- when the screen height changes.
local metricsCache = {}
local function metrics(visor)
    local st = style()
    local H = ScrH()
    local key = (visor and "v" or "t") .. st
    local c = metricsCache[key]
    local stamp = UI.themeStamp or 0
    if c and c.H == H and c.stamp == stamp then return c end
    local s = H / 1080
    local function S(n) return math.floor(n * s + 0.5) end
    c = {
        H = H, s = s, st = st, visor = visor, stamp = stamp,
        font = UI.Font(visor and 16 or 17),
        small = UI.Font(visor and 14 or 15),
        nameF = UI.Font(16, 700), labelF = UI.Font(12, 700), chipF = UI.Font(13, 700), timeF = UI.Font(13),
        pillF = UI.Font(visor and 11 or 12, 700),
        lineH = S(visor and 20 or 22), smallH = S(visor and 18 or 20),
        header = visor and 0 or S(st == "b" and 40 or 38),
        inputH = S(visor and 24 or (st == "b" and 44 or 46)),
        pad = S(visor and 7 or 10),
        rowH = S(visor and 18 or 24),
        chipH = S(28),
    }
    metricsCache[key] = c
    return c
end

-- The parts of the window, in panel coordinates (kept per size and look).
local layoutCache = {}
local makeLayout
local function layout(w, h, m)
    local key = w .. "x" .. h .. (m.visor and "v" or "t") .. m.st .. m.H
    local L = layoutCache[key]
    if L then return L end
    if table.Count(layoutCache) > 8 then layoutCache = {} end
    L = makeLayout(w, h, m)
    layoutCache[key] = L
    return L
end
makeLayout = function(w, h, m)
    local s = m.s
    local function S(n) return math.floor(n * s + 0.5) end
    local L = {}
    if m.visor then
        local iy = h - m.inputH - S(3)
        L.input = { x = m.pad, y = iy, w = w - m.pad - S(6), h = m.inputH }
        L.chan = { x = m.pad + 1, y = iy + 1, w = S(70), h = m.inputH - 2 }
        L.msgs = { x = m.pad, y = math.floor(m.pad * 0.5), w = w - m.pad * 2, h = h - m.inputH - math.floor(m.pad * 1.5) }
        L.entry = { x = L.chan.x + L.chan.w + S(10), y = iy, w = w - (L.chan.x + L.chan.w + S(10)) - S(8), h = m.inputH }
        L.listBottom = h - m.inputH - S(6)
    elseif m.st == "b" then
        L.header = { x = 0, y = 0, w = w, h = m.header }
        L.input = { x = S(10), y = h - S(10) - m.inputH, w = w - S(20), h = m.inputH }
        L.chips = { x = S(10), y = L.input.y - S(6) - m.chipH, w = w - S(20), h = m.chipH }
        L.msgs = { x = 0, y = m.header, w = w, h = L.chips.y - S(4) - m.header }
        L.entry = { x = L.input.x + S(12), y = L.input.y, w = L.input.w - S(24) - S(120), h = m.inputH }
        L.listBottom = L.chips.y - S(4)
    else
        L.header = { x = 0, y = 0, w = w, h = m.header }
        L.input = { x = 0, y = h - m.inputH, w = w, h = m.inputH }
        L.chan = { x = S(10), y = L.input.y + S(8), w = S(104), h = m.inputH - S(16) }
        local ex = L.chan.x + L.chan.w + S(10)
        L.msgs = { x = S(12), y = m.header + S(8), w = w - S(24), h = L.input.y - S(8) - (m.header + S(8)) }
        L.entry = { x = ex, y = L.input.y, w = w - ex - S(110), h = m.inputH }
        L.listBottom = L.input.y - S(4)
    end
    return L
end

local function inRect(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

-- Channels you can pick (chips, tabs), with or without the private one.
local function usableChannels(withPM)
    local out = {}
    for _, ch in ipairs(Chat.CHANNELS) do
        if ch.private then
            if withPM then out[#out + 1] = ch end
        elseif Chat.CanUse(LocalPlayer(), ch) then
            out[#out + 1] = ch
        end
    end
    return out
end

-- Look B: channel chips above the input. Look A: tabs along the top
-- (All first; a filter, not the channel you send on). { x, y, w, h, ch }.
local CHIP_SKIP = { admin = true, event = true, advert = true, rp = true }
local rectCache = { at = 0 }
local function chipRects(L, m)
    if rectCache.chipsFor == L and RealTime() < rectCache.at then return rectCache.chips end
    local out = {}
    local r = L.chips
    if not r then return out end
    local x = r.x
    surface.SetFont(m.chipF)
    for _, ch in ipairs(usableChannels(false)) do
        if not CHIP_SKIP[ch.id] or ch == currentChannel() then
            local cw = surface.GetTextSize(ch.name) + math.floor(22 * m.s)
            if x + cw > r.x + r.w then break end
            out[#out + 1] = { x = x, y = r.y, w = cw, h = r.h, ch = ch }
            x = x + cw + math.floor(4 * m.s)
        end
    end
    rectCache.chipsFor, rectCache.chips, rectCache.at = L, out, RealTime() + 0.25
    return out
end
local function tabRects(L, m)
    if rectCache.tabsFor == L and RealTime() < (rectCache.tabsAt or 0) then return rectCache.tabs end
    local out = {}
    local r = L.header
    if not r then return out end
    local x = r.x
    surface.SetFont(m.chipF)
    local list = { false }
    for _, ch in ipairs(usableChannels(true)) do
        if not CHIP_SKIP[ch.id] then list[#list + 1] = ch end
    end
    for _, ch in ipairs(list) do
        local name = ch and ch.name or "All"
        local n = ch and Chat.unread[ch.id] or 0
        local cw = surface.GetTextSize(name) + math.floor(28 * m.s) + (n > 0 and math.floor(26 * m.s) or 0)
        if x + cw > r.x + r.w then break end
        out[#out + 1] = { x = x, y = r.y, w = cw, h = r.h, ch = ch or nil, all = not ch, name = name }
        x = x + cw
    end
    rectCache.tabsFor, rectCache.tabs, rectCache.tabsAt = L, out, RealTime() + 0.25
    return out
end

-- Is this line shown on the open window's tab (look A)?
local function onTab(msg)
    if not Chat.tab then return true end
    return msg.ch ~= nil and msg.ch.id == Chat.tab
end

-- The pieces of a channel line in one font (look A, the visor and the
-- closed feed): rank, name, text. Cached on the line.
local function lineSegs(msg)
    if msg.flat then return msg.flat end
    local segs = {}
    if msg.rank and msg.rank ~= "" then segs[#segs + 1] = { COL_DIM, msg.rank .. " " } end
    if msg.action then
        segs[#segs + 1] = { msg.ch.color, "* " }
        segs[#segs + 1] = { msg.nameCol or COL_TEXT, msg.name or "" }
        segs[#segs + 1] = { msg.ch.color, " " .. (msg.text or "") }
    else
        segs[#segs + 1] = { msg.nameCol or COL_TEXT, msg.name or "" }
        if msg.to then segs[#segs + 1] = { COL_DIM, msg.to } end
        segs[#segs + 1] = { msg.ch.id == "event" and msg.ch.color or COL_TEXT, "  " .. (msg.text or "") }
    end
    msg.flat = { segs = segs }
    return msg.flat
end

-- A small solid pill with the channel's name.
local pillW = {}
local function pill(ch, x, y, h, font, alpha)
    local name = string.upper(ch.name)
    local key = name .. font
    local w = pillW[key]
    if not w then
        surface.SetFont(font)
        w = surface.GetTextSize(name) + math.floor(10 * ScrH() / 1080)
        pillW[key] = w
    end
    setCol(ch.color, alpha)
    surface.DrawRect(x, y, w, h)
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(name)
    drawCol.r, drawCol.g, drawCol.b, drawCol.a = COL_DARK.r, COL_DARK.g, COL_DARK.b, alpha
    surface.SetTextColor(drawCol)
    surface.SetTextPos(x + math.floor((w - tw) * 0.5), y + math.floor((h - th) * 0.5))
    surface.DrawText(name)
    return w
end
local function pillWidth(ch, font)
    local name = string.upper(ch.name)
    local w = pillW[name .. font]
    if w then return w end
    surface.SetFont(font)
    w = surface.GetTextSize(name) + math.floor(10 * ScrH() / 1080)
    pillW[name .. font] = w
    return w
end

-- One-line messages (look A, the visor): a channel pill, then rank, name
-- and text, wrapped; the time on the right (third person). Bottom-up.
-- widthAt(lineTop): the visor narrows toward the top. Widths snap to 8 px
-- so the wrap cache stays small.
local function drawLinesA(x, y, w, h, m, open, widthAt, withTime)
    local now = RealTime()
    local yy = y + h
    local skip = open and Chat.scroll or 0
    local lineH = m.lineH
    local timeW = withTime and math.floor(48 * m.s) or 0
    local pillH = lineH - math.floor(6 * m.s)
    surface.SetFont(m.font)
    for i = #Chat.lines, 1, -1 do
        local msg = Chat.lines[i]
        local age = now - msg.time
        if not open and age > SHOW_TIME then break end
        if open and onTab(msg) and skip > 0 then
            skip = skip - 1
        elseif not open or onTab(msg) then
            local alpha = open and 255 or math.Clamp((SHOW_TIME - age) * 255, 0, 255)
            local ind = msg.ch and (pillWidth(msg.ch, m.pillF) + math.floor(8 * m.s)) or math.floor(12 * m.s)
            local avail = widthAt and math.min(w, widthAt(yy - lineH)) or w
            avail = math.floor((avail - timeW) / 8) * 8
            if avail - ind < 60 then return end
            local src = msg.ch and lineSegs(msg) or msg
            local lines = wrap(src, m.font, avail - ind)
            if widthAt and #lines > 1 then
                local topAvail = math.floor(math.min(w, widthAt(yy - #lines * lineH)) / 8) * 8
                if topAvail < avail and topAvail - ind >= 60 then lines = wrap(src, m.font, topAvail - ind) end
            end
            for k = #lines, 1, -1 do
                do
                    yy = yy - lineH
                    if yy < y then return end
                    surface.SetFont(m.font)
                    for _, part in ipairs(lines[k]) do
                        text(part[2], x + ind + part[3], yy, part[1], alpha)
                    end
                    if k == 1 then
                        if msg.ch then
                            pill(msg.ch, x, yy + math.floor((lineH - pillH) * 0.5), pillH, m.pillF, alpha)
                        else
                            setCol(COL_DIM, alpha)
                            surface.DrawRect(x + 2, yy + math.floor(lineH * 0.5) - 2, 4, 4)
                        end
                        if withTime and msg.at then
                            surface.SetFont(m.timeF)
                            local tw = surface.GetTextSize(msg.at)
                            text(msg.at, x + w - tw, yy + math.floor(2 * m.s), COL_DIM2, alpha)
                        end
                        surface.SetFont(m.font)
                    end
                end
            end
        end
    end
end

-- Look B rows: rank chip, name, channel label, time; the text under them;
-- a coloured line on the left. Returns the wrapped text and the row height.
local function blockB(msg, w, m)
    local s = m.s
    if msg.ch then
        local tx = math.floor((12 + 36 + 10) * s)
        local tw = math.floor((w - tx - math.floor(12 * s)) / 8) * 8
        msg.body = msg.body or { segs = { { msg.action and msg.ch.color or (msg.ch.id == "event" and msg.ch.color or COL_TEXT),
            msg.action and ("* " .. (msg.text or "")) or (msg.text or "") } } }
        local lines = wrap(msg.body, m.font, math.max(60, tw))
        return lines, math.floor(7 * s) + math.floor(21 * s) + #lines * m.lineH + math.floor(7 * s), tx
    end
    local lines = wrap(msg, m.small, math.max(60, math.floor((w - math.floor(28 * s)) / 8) * 8))
    return lines, math.floor(6 * s) * 2 + #lines * m.smallH, math.floor(14 * s)
end

local function drawBlockB(msg, x, y, w, bh, lines, tx, m)
    local s = m.s
    setCol(COL_SEP)
    surface.DrawRect(x, y + bh - 1, w, 1)
    if msg.ch then
        setCol(msg.ch.color)
        surface.DrawRect(x, y, math.max(2, math.floor(3 * s)), bh)
        local top = y + math.floor(7 * s)
        -- rank chip, edged in the battalion's colour
        local cx, cw, ch = x + math.floor(12 * s), math.floor(36 * s), math.floor(19 * s)
        if msg.rank and msg.rank ~= "" then
            setCol(msg.bnCol or COL_DIM)
            surface.DrawOutlinedRect(cx, top + 1, cw, ch)
            surface.SetFont(m.chipF)
            local rw, rh = surface.GetTextSize(msg.rank)
            text(msg.rank, cx + math.floor((cw - rw) * 0.5), top + 1 + math.floor((ch - rh) * 0.5), COL_TEXT, 255)
        end
        local name = msg.name or ""
        surface.SetFont(m.nameF)
        local nw = surface.GetTextSize(name)
        text(name, x + tx, top, COL_TEXT, 255)
        local lx = x + tx + nw + math.floor(8 * s)
        surface.SetFont(m.labelF)
        msg.label = msg.label or (string.upper(msg.ch.name) .. (msg.to and (" " .. msg.to) or ""))
        local label = msg.label
        text(label, lx, top + math.floor(4 * s), msg.ch.color, 255)
        if msg.at then
            surface.SetFont(m.timeF)
            local tw = surface.GetTextSize(msg.at)
            text(msg.at, x + w - math.floor(12 * s) - tw, top + math.floor(2 * s), COL_DIM2, 255)
        end
        surface.SetFont(m.font)
        local ly = top + math.floor(21 * s)
        for _, line in ipairs(lines) do
            for _, part in ipairs(line) do text(part[2], x + tx + part[3], ly, part[1], 255) end
            ly = ly + m.lineH
        end
    else
        surface.SetFont(m.small)
        local ly = y + math.floor(6 * s)
        for _, line in ipairs(lines) do
            for _, part in ipairs(line) do text(part[2], x + tx + part[3], ly, part[1], 220) end
            ly = ly + m.smallH
        end
    end
end

-- Look B messages: rows bottom-up, clipped to the area.
local function drawBlocksB(x, y, w, h, m)
    local yy = y + h
    local skip = Chat.scroll
    render.SetScissorRect(x, y, x + w, y + h, true)
    for i = #Chat.lines, 1, -1 do
        local msg = Chat.lines[i]
        if skip > 0 then
            skip = skip - 1
        else
            local lines, bh, tx = blockB(msg, w, m)
            yy = yy - bh
            drawBlockB(msg, x, yy, w, bh, lines, tx, m)
            if yy <= y then break end
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)
end

-- The closed chat: the newest lines float on their own, fading after
-- SHOW_TIME seconds; outside the visor each sits on a soft dark band
-- (one smooth gradient) with its channel's colour on the left; in the
-- visor (already on the dark cheek) no band, and every line keeps inside
-- the cheek's edge. Look A also shows the channel pill.
local GRAD = Material("vgui/gradient-l")
local function drawFeed(x, y, w, h, m, widthAt)
    local now = RealTime()
    local yy = y + h
    local lineH = m.lineH
    local s = m.s
    local padX = math.floor(10 * s)
    local gap = math.floor(4 * s)
    local pillOn = m.st == "a"
    local pillH = lineH - math.floor(6 * s)
    surface.SetFont(m.font)
    for i = #Chat.lines, 1, -1 do
        local msg = Chat.lines[i]
        local age = now - msg.time
        if age > SHOW_TIME then break end
        local alpha = math.Clamp((SHOW_TIME - age) * 255, 0, 255)
        local ind = (pillOn and msg.ch) and (pillWidth(msg.ch, m.pillF) + math.floor(8 * s)) or 0
        surface.SetFont(m.font)   -- (pillWidth may have set the pill font)
        local avail = widthAt and math.min(w, widthAt(yy - lineH)) or w
        avail = math.floor((avail - padX * 2) / 8) * 8
        if avail - ind < 60 then return end
        local src = msg.ch and lineSegs(msg) or msg
        local lines = wrap(src, m.font, avail - ind)
        local bh = #lines * lineH + math.floor(6 * s)
        -- (the visor narrows upward: fit the block's top line too)
        if widthAt and #lines > 1 then
            for _ = 1, 2 do
                local top = math.floor((math.min(w, widthAt(yy - bh)) - padX * 2) / 8) * 8
                if top >= avail or top - ind < 60 then break end
                avail = top
                lines = wrap(src, m.font, avail - ind)
                bh = #lines * lineH + math.floor(6 * s)
            end
        end
        yy = yy - bh
        if yy < y then return end
        -- (the band is as wide as its widest line)
        local bw = 0
        for _, line in ipairs(lines) do
            local last = line[#line]
            if last then
                local lw = last[3] + surface.GetTextSize(last[2])
                if lw > bw then bw = lw end
            end
        end
        bw = bw + ind + padX * 2
        if not widthAt then
            -- a dark band fading out to the right (one smooth gradient)
            setCol(COL_FEED, COL_FEED.a * alpha / 255)
            surface.SetMaterial(GRAD)
            surface.DrawTexturedRect(x, yy, bw, bh)
            draw.NoTexture()
            if msg.ch then
                setCol(msg.ch.color, alpha)
                surface.DrawRect(x, yy, math.max(2, math.floor(3 * s)), bh)
            end
        end
        local ly = yy + math.floor(3 * s)
        for k, line in ipairs(lines) do
            for _, part in ipairs(line) do text(part[2], x + padX + ind + part[3], ly, part[1], alpha) end
            if k == 1 and pillOn and msg.ch then
                pill(msg.ch, x + padX, ly + math.floor((lineH - pillH) * 0.5), pillH, m.pillF, alpha)
                surface.SetFont(m.font)
            end
            ly = ly + lineH
        end
        yy = yy - gap
    end
end

-- Your radio squad (rhylib_radio's directory), or nil.
local function mySquad()
    local R = Rhylib.Radio
    if not (R and R.SquadOf and R.dir and R.dir.squads) then return nil end
    local ok, id = pcall(R.SquadOf, LocalPlayer())
    return ok and id and R.dir.squads[id] or nil
end

-- What the look B header says: "COMMS · SQUAD ALPHA" and "4 in squad".
local function headerText(ch)
    if ch.id == "squad" then
        local sq = mySquad()
        if sq then
            local n = sq.members and #sq.members or 0
            return "COMMS  ·  SQUAD " .. string.upper(sq.name or ""), n .. " in squad"
        end
    end
    return "COMMS  ·  " .. string.upper(ch.name), ch.desc
end

local function diamond(cx, cy, r, col, inner, innerCol)
    draw.NoTexture()
    setCol(col)
    surface.DrawPoly({ { x = cx, y = cy - r }, { x = cx + r, y = cy }, { x = cx, y = cy + r }, { x = cx - r, y = cy } })
    if inner then
        setCol(innerCol)
        surface.DrawPoly({ { x = cx, y = cy - inner }, { x = cx + inner, y = cy }, { x = cx, y = cy + inner }, { x = cx - inner, y = cy } })
    end
end

-- The window's frame, drawn at ox, oy (0, 0 in the open panel, the screen
-- position when pinned). sx, sy: its screen position (the visor shape).
-- hint: text in the input when nobody types (pinned). mx, my: the mouse
-- in panel coordinates (hover), or nil.
local localPts = {}
local function drawFrame(ox, oy, sx, sy, w, h, visor, m, L, mx, my, hint, menuOpen)
    local ch = currentChannel()
    local s = m.s
    local Kit = UI.Kit
    if visor then
        -- The cheek shape (its top-right edge follows the helmet).
        local pts, top = shape(sx, sy, w, h, visor)
        for i, p in ipairs(pts) do
            localPts[i] = localPts[i] or { x = 0, y = 0 }
            localPts[i].x, localPts[i].y = p.x - sx + ox, p.y - sy + oy
        end
        for i = #pts + 1, #localPts do localPts[i] = nil end
        draw.NoTexture()
        surface.SetDrawColor(VIS_BG)
        surface.DrawPoly(localPts)
        surface.SetDrawColor(VIS_EDGE_DARK)
        for i = 1, #localPts do
            local a, b = localPts[i], localPts[i % #localPts + 1]
            surface.DrawLine(a.x, a.y, b.x, b.y)
        end
        surface.SetDrawColor(VIS_EDGE_LIGHT)
        for i = 1, #top - 1 do
            surface.DrawLine(top[i][1] - sx + ox, top[i][2] - sy + oy + 1, top[i + 1][1] - sx + ox, top[i + 1][2] - sy + oy + 1)
        end
        local r = L.input
        local iw = math.min(r.w, math.floor(Chat.VisorEdgeX(sy + r.y) - sx) - m.pad - math.floor(6 * s))
        surface.SetDrawColor(VIS_INPUT)
        surface.DrawRect(ox + r.x, oy + r.y, iw, r.h)
        surface.SetDrawColor(VIS_INPUT_EDGE)
        surface.DrawOutlinedRect(ox + r.x, oy + r.y, iw, r.h)
        local c = L.chan
        local hover = menuOpen or (mx and inRect(c, mx, my))
        surface.SetDrawColor(hover and VIS_PICK or VIS_HEADER)
        surface.DrawRect(ox + c.x, oy + c.y, c.w, c.h)
        setCol(ch.color)
        surface.DrawRect(ox + c.x, oy + c.y, 3, c.h)
        draw.SimpleText(ch.name, UI.Font(13, 700), ox + c.x + (c.w - math.floor(10 * s)) * 0.5 + 2, oy + c.y + c.h * 0.5, ch.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if Kit and Kit.Arrow then Kit.Arrow(ox + c.x + c.w - math.floor(8 * s), oy + c.y + c.h * 0.5, math.floor(7 * s), "down", ch.color) end
        if hint then draw.SimpleText(hint, m.font, ox + L.entry.x, oy + r.y + r.h * 0.5, VIS_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        return
    end

    if m.st == "b" then
        surface.SetDrawColor(COL_B_BG)
        surface.DrawRect(ox, oy, w, h)
        surface.SetDrawColor(COL_B_EDGE)
        surface.DrawOutlinedRect(ox, oy, w, h)
        -- header band: the channel's colour, a diamond, what you talk on
        local hd = L.header
        setCol(ch.color, 26)
        surface.DrawRect(ox, oy, w, hd.h)
        setCol(ch.color)
        surface.DrawRect(ox, oy, math.floor(4 * s), hd.h)
        diamond(ox + math.floor(20 * s), oy + hd.h * 0.5, math.floor(8 * s), ch.color, math.floor(5 * s), COL_B_BG)
        local title, right = headerText(ch)
        surface.SetFont(UI.Font(13))
        local rw = right and surface.GetTextSize(right) or 0
        draw.SimpleText(Kit and Kit.Fit and Kit.Fit(title, UI.Font(18, 700), w - math.floor(60 * s) - rw) or title, UI.Font(18, 700),
            ox + math.floor(38 * s), oy + hd.h * 0.5, COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if right then draw.SimpleText(right, UI.Font(13), ox + w - math.floor(12 * s), oy + hd.h * 0.5, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        -- channel chips
        for _, r in ipairs(chipRects(L, m)) do
            local on = r.ch == ch
            local hov = mx and inRect(r, mx, my)
            if on then
                setCol(r.ch.color, 30)
                surface.DrawRect(ox + r.x, oy + r.y, r.w, r.h)
            elseif hov then
                surface.SetDrawColor(COL_ROW_PICK)
                surface.DrawRect(ox + r.x, oy + r.y, r.w, r.h)
            end
            setCol(on and r.ch.color or COL_B_EDGE)
            surface.DrawOutlinedRect(ox + r.x, oy + r.y, r.w, r.h)
            draw.SimpleText(r.ch.name, on and UI.Font(13, 700) or UI.Font(13, 500), ox + r.x + r.w * 0.5, oy + r.y + r.h * 0.5,
                on and COL_WHITE or COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        -- input
        local r = L.input
        surface.SetDrawColor(COL_INPUT)
        surface.DrawRect(ox + r.x, oy + r.y, r.w, r.h)
        surface.SetDrawColor(COL_B_EDGE)
        surface.DrawOutlinedRect(ox + r.x, oy + r.y, r.w, r.h)
        draw.SimpleText("/ for commands", UI.Font(13), ox + r.x + r.w - math.floor(12 * s), oy + r.y + r.h * 0.5, COL_DIM2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if hint then draw.SimpleText(hint, m.font, ox + L.entry.x, oy + r.y + r.h * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        return
    end

    -- Look A: tabs along the top, a solid channel button by the input.
    surface.SetDrawColor(COL_A_BG)
    surface.DrawRect(ox, oy, w, h)
    surface.SetDrawColor(COL_B_EDGE)
    surface.DrawOutlinedRect(ox, oy, w, h)
    local hd = L.header
    surface.DrawRect(ox, oy + hd.h - 1, w, 1)
    for _, r in ipairs(tabRects(L, m)) do
        local on = (r.all and not Chat.tab) or (r.ch and Chat.tab == r.ch.id)
        local col = r.ch and r.ch.color or COL_ACCENT
        if mx and inRect(r, mx, my) and not on then
            surface.SetDrawColor(COL_ROW_PICK)
            surface.DrawRect(ox + r.x, oy + r.y, r.w, r.h - 1)
        end
        if on then
            setCol(col)
            surface.DrawRect(ox + r.x, oy + r.y + r.h - math.floor(2 * s), r.w, math.floor(2 * s))
        end
        local n = r.ch and Chat.unread[r.ch.id] or 0
        local tx = ox + r.x + math.floor(14 * s)
        draw.SimpleText(r.name, on and UI.Font(13, 700) or UI.Font(13, 500), tx, oy + r.y + r.h * 0.5, on and COL_WHITE or COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if n > 0 then
            surface.SetFont(on and UI.Font(13, 700) or UI.Font(13, 500))
            local tw = surface.GetTextSize(r.name)
            local label = n > 99 and "99+" or tostring(n)
            local px = tx + tw + math.floor(6 * s)
            local pw, ph = math.floor(20 * s), math.floor(16 * s)
            setCol(col)
            surface.DrawRect(px, oy + r.y + (r.h - ph) * 0.5, pw, ph)
            draw.SimpleText(label, UI.Font(10, 700), px + pw * 0.5, oy + r.y + r.h * 0.5, COL_DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local r = L.input
    surface.SetDrawColor(COL_INPUT)
    surface.DrawRect(ox + r.x + 1, oy + r.y, r.w - 2, r.h - 1)
    surface.SetDrawColor(COL_B_EDGE)
    surface.DrawRect(ox + r.x, oy + r.y, r.w, 1)
    local c = L.chan
    local hover = menuOpen or (mx and inRect(c, mx, my))
    setCol(ch.color, hover and 210 or 255)
    surface.DrawRect(ox + c.x, oy + c.y, c.w, c.h)
    draw.SimpleText(string.upper(ch.name), UI.Font(12, 700), ox + c.x + (c.w - math.floor(12 * s)) * 0.5, oy + c.y + c.h * 0.5, COL_DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if Kit and Kit.Arrow then Kit.Arrow(ox + c.x + c.w - math.floor(10 * s), oy + c.y + c.h * 0.5, math.floor(7 * s), "down", COL_DARK) end
    draw.SimpleText(hint and "" or "Enter to send", UI.Font(12), ox + r.x + r.w - math.floor(12 * s), oy + r.y + r.h * 0.5, COL_DIM2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    if hint then draw.SimpleText(hint, m.font, ox + L.entry.x, oy + r.y + r.h * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end

-- The messages for the window (open or pinned) at screen ox, oy.
local function drawWindowMessages(ox, oy, L, m, visor)
    local r = L.msgs
    local x, y = ox + r.x, oy + r.y
    if visor then
        render.SetScissorRect(x, y, x + r.w, y + r.h, true)
        drawLinesA(x, y, r.w, r.h, m, true, function(ly) return Chat.VisorEdgeX(ly) - x - m.pad end, false)
        render.SetScissorRect(0, 0, 0, 0, false)
    elseif m.st == "b" then
        drawBlocksB(x, y, r.w, r.h, m)
    else
        drawLinesA(x, y, r.w, r.h, m, true, nil, true)
    end
end

-- Closed chat. Normally: recent messages only, floating and fading.
-- Pinned (/togglechat): the whole window stays up, and opening the chat
-- just lets you type into it.
local pinVar = CreateClientConVar("rhylib_chat_pinned", "0", true, false, "Keep the chat window always visible (0/1). Toggle in chat with /togglechat")

local hintText, hintAt = "", 0
local function pinnedHint()
    if RealTime() < hintAt then return hintText end
    hintAt = RealTime() + 1
    local key = input.LookupBinding("messagemode")
    hintText = "Press " .. (key and string.upper(key) or "your chat key") .. " to type"
    return hintText
end

Rhylib.Hook.Add("HUDPaint", "chat.feed", function()
    if IsValid(Chat.panel) then return end
    local pinned = pinVar:GetBool()
    if not pinned then
        local last = Chat.lines[#Chat.lines]
        if not last or RealTime() - last.time > SHOW_TIME then return end
    end
    local x, y, w, h, visor = Chat.Rect()
    local m = metrics(visor)
    local L = layout(w, h, m)
    if pinned then
        local Rh = Rhylib.HUD
        if Rh and Rh.Hidden and Rh.Hidden() then return end
        drawFrame(x, y, x, y, w, h, visor, m, L, nil, nil, pinnedHint())
        drawWindowMessages(x, y, L, m, visor)
        return
    end
    local r = L.msgs
    if visor then
        render.SetScissorRect(x + r.x, y + r.y, x + r.x + r.w, y + r.y + r.h, true)
        drawFeed(x + r.x, y + r.y, r.w, r.h, m, function(ly) return Chat.VisorEdgeX(ly) - (x + r.x) - m.pad end)
        render.SetScissorRect(0, 0, 0, 0, false)
    else
        -- (the whole window's height: nothing else is drawn there while closed)
        drawFeed(x, y, w, h - math.floor(6 * m.s), m)
    end
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
    entry:SetHighlightColor(COL_HIGHLIGHT)
    entry:SetPaintBackground(false)
    entry.Paint = function(e, w, h)
        e:DrawTextEntryText(COL_TEXT, COL_HIGHLIGHT, COL_TEXT)
        local len = #e:GetValue()
        if len == 0 then
            local ch = currentChannel()
            local to = ch.name
            local sq = ch.id == "squad" and mySquad()
            if sq and sq.name then to = "squad " .. sq.name end
            draw.SimpleText("Message " .. to .. "…", self.m.font, 2, h * 0.5, COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        elseif len > maxLength() - 40 then
            draw.SimpleText(len .. "/" .. maxLength(), UI.Font(12), w - 4, h * 0.5, len >= maxLength() and COL_LIMIT or COL_DIM,
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
    self.st = self.m.st
    local m = self.m
    self:SetPos(x, y)
    self:SetSize(w, h)
    self.L = layout(w, h, m)
    local r = self.L.entry
    self.entry:SetFont(m.font)
    local right = r.x + r.w
    if visor then right = math.min(right, math.floor(Chat.VisorEdgeX(y + r.y) - x) - math.floor(8 * m.s)) end
    self.entry:SetPos(r.x, r.y)
    self.entry:SetSize(math.max(40, right - r.x), r.h)
end

function PANEL:UpdateSuggest()
    self.suggest = suggestions(self.entry:GetValue())
    self.pick = math.Clamp(self.pick, 1, math.max(1, #self.suggest))
end

function PANEL:Think()
    local x, y, w, h, visor = Chat.Rect()
    local px, py = self:GetPos()
    if visor ~= self.visor or x ~= px or y ~= py or w ~= self:GetWide() or h ~= self:GetTall() or style() ~= self.st or ScrH() ~= self.m.H or self.m.stamp ~= (UI.themeStamp or 0) then self:Layout() end
end

-- Rows of a pop-up list (suggestions or channels), in panel coordinates:
-- just above the input line (or the chips), inside the frame.
function PANEL:ListRows(list)
    local m, L = self.m, self.L
    local bottom = L.listBottom
    local top = L.header and L.header.h or 0
    local maxRows = math.max(1, math.floor((bottom - top) / m.rowH))
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
    local L, m = self.L, self.m
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
    if L.chan and inRect(L.chan, mx, my) then
        self.menu = channelRows()
        return
    end
    if not self.visor and self.st == "b" then
        for _, r in ipairs(chipRects(L, m)) do
            if inRect(r, mx, my) then
                surface.PlaySound("ui/buttonclick.wav")
                Chat.current = r.ch
                self.entry:RequestFocus()
                return
            end
        end
    elseif not self.visor then
        for _, r in ipairs(tabRects(L, m)) do
            if inRect(r, mx, my) then
                surface.PlaySound("ui/buttonclick.wav")
                Chat.tab = r.ch and r.ch.id or nil
                if r.ch then Chat.unread[r.ch.id] = nil end
                Chat.scroll = 0
                self.entry:RequestFocus()
                return
            end
        end
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

-- (the scroll counts messages; never past the oldest)
function PANEL:OnMouseWheeled(delta)
    Chat.scroll = math.Clamp(Chat.scroll + delta, 0, math.max(0, #Chat.lines - 1))
    return true
end

function PANEL:Paint(w, h)
    local sx, sy = self:LocalToScreen(0, 0)
    local mx, my = self:CursorPos()
    drawFrame(0, 0, sx, sy, w, h, self.visor, self.m, self.L, mx, my, nil, self.menu ~= nil)
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
    draw.SimpleText(r.item.label .. (current and "  (now)" or ""), UI.Font(14, 700), x + 10 * m.s, y + r.h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(r.item.desc, UI.Font(12), x + r.w - 8 * m.s, y + r.h * 0.5, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

-- Messages and lists, on top of the frame, in screen space (after all
-- VGUI, so they draw over the frame's children).
Rhylib.Hook.Add("PostRenderVGUI", "chat.window", function()
    local p = Chat.panel
    if not IsValid(p) then return end
    local px, py = p:LocalToScreen(0, 0)
    local w, m, L = p:GetWide(), p.m, p.L
    drawWindowMessages(px, py, L, m, p.visor)
    if Chat.scroll > 0 then
        local r = L.msgs
        local ly = py + r.y + math.floor(10 * m.s)
        local rx = px + r.x + r.w - m.pad
        if p.visor then rx = math.min(rx, Chat.VisorEdgeX(ly + math.floor(8 * m.s)) - m.pad * 2) end
        draw.SimpleText("+" .. Chat.scroll .. " newer", UI.Font(12), rx, ly, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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

-- Esc with the chat open closes the chat first (rhylib_menus' Esc handler
-- runs the UI closers before opening the pause menu).
if Rhylib.UI and Rhylib.UI.RegisterCloser then
    Rhylib.UI.RegisterCloser("chat", function()
        -- (the chat box's own Esc may have closed it a moment ago)
        if not IsValid(Chat.panel) then return Chat.hideMenuUntil ~= nil and RealTime() < Chat.hideMenuUntil end
        Chat.Close()
        Chat.hideMenuUntil = RealTime() + 0.3
        return true
    end)
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
local COL_EVENT = Col("chat.event", 255, 205, 80)

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
