--[[
    Keyboard layout (Settings > Layout): a drawn keyboard and mouse with
    every key Rhylib uses, coloured by section, a short label on each key
    and, on hover, everything that key does (combos included). Keys that
    only have a game bind show it dimly so the board is easy to read.

    Sources (only what's installed):
      - rebindable keys: Menus.AddSetting rows with kind = "key" (their
        convar; optional `short` label);
      - fixed controls: Menus.AddControl(section, keys, text) from
        cl_25_controls.lua. keys may hold {game bind}, [convar], ESC, F1-F12,
        Ctrl, Shift, Alt, Tab, right-click, wheel. "A / B" pairs up with
        "text a / text b" (Fire / aim). In a combo the last key is the main
        one, the others are modifiers.
    Rebuilt when the page opens and every 2 s while it's open (rebinds).
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

-- Short key-cap labels for rebindable keys (by convar) and fixed controls (by text).
local SHORT = {
    rhylib_optics_key = "Helmet gear", rhylib_optics_mode_key = "Optics mode", rhylib_medical_key = "Injuries",
    rhylib_radio_key = "Radio talk", rhylib_radio_switchkey = "Radio channel", rhylib_radio_menukey = "Radio page",
    rhylib_radio_mutekey = "Radio mute", rhylib_radio_deafkey = "Radio deafen", rhylib_radio_powerkey = "Radio power",
    rhylib_call_key = "Answer call", rhylib_thirdperson_key = "Third person", rhylib_thirdperson_swapkey = "Swap shoulder",
    rhylib_inventory_key = "Inventory",
    ["Reload the best magazine"] = "Reload",
    ["Magazine wheel: pick which magazine to load"] = "Mag wheel",
    ["Next fire mode (grenades: timed, impact, breach)"] = "Fire mode",
    ["Rhylib menu (Shift + Esc: the game's own menu)"] = "Menu",
    ["This controls page"] = "Controls",
    ["Jobs, shop and character"] = "Jobs & shop",
    ["Scoreboard (right-click frees the mouse)"] = "Scoreboard",
    ["Hold with a gun out: weapon stats"] = "Gun stats",
    ["Mark target (Officer skill; the spawn menu is off, staff open it from the toolgun)"] = "Mark target",
    ["Open the datapad (while holding it)"] = "Datapad",
}

-- Section colours, handed out in order.
local PALETTE = {
    Color(90, 160, 235), Color(235, 150, 60), Color(110, 200, 120), Color(225, 90, 90), Color(180, 120, 230),
    Color(80, 200, 200), Color(230, 200, 70), Color(235, 120, 180), Color(150, 170, 110), Color(160, 160, 175),
}

-- Friendly names for game binds (dim labels on keys Rhylib doesn't use).
local GAME = {
    ["+forward"] = "Forward", ["+back"] = "Back", ["+moveleft"] = "Left", ["+moveright"] = "Right",
    ["+jump"] = "Jump", ["+duck"] = "Crouch", ["+speed"] = "Sprint", ["+walk"] = "Walk", ["+use"] = "Use",
    ["+reload"] = "Reload", ["+attack"] = "Fire", ["+attack2"] = "Aim", ["+attack3"] = "Attack 3",
    ["+voicerecord"] = "Voice", ["messagemode"] = "Chat", ["messagemode2"] = "Team chat",
    ["+showscores"] = "Scores", ["impulse 100"] = "Flashlight", ["+menu"] = "Spawn menu",
    ["+menu_context"] = "Context", ["+zoom"] = "Suit zoom", ["noclip"] = "Noclip", ["toggleconsole"] = "Console",
    ["invnext"] = "Next weapon", ["invprev"] = "Prev weapon", ["lastinv"] = "Last weapon",
    ["gm_showhelp"] = "Help", ["gm_showteam"] = "Team", ["gm_showspare1"] = "Spare 1", ["gm_showspare2"] = "Spare 2",
    ["jpeg"] = "Screenshot", ["cancelselect"] = "Cancel", ["undo"] = "Undo", ["gmod_undo"] = "Undo",
}
for i = 0, 9 do GAME["slot" .. i] = "Slot " .. i end

-- Words in a keys string that name a key.
local LIT = {
    esc = KEY_ESCAPE, escape = KEY_ESCAPE, ctrl = KEY_LCONTROL, shift = KEY_LSHIFT, alt = KEY_LALT, tab = KEY_TAB,
    ["right-click"] = MOUSE_RIGHT, ["left-click"] = MOUSE_LEFT, wheel = MOUSE_WHEEL_UP,
}
for i = 1, 12 do LIT["f" .. i] = _G["KEY_F" .. i] end

-- Codes drawn on another cap (wheel down on the wheel).
local ALIAS = { [MOUSE_WHEEL_DOWN] = MOUSE_WHEEL_UP }

--------------------------------------------------------------------------
-- The board: rows of { code, label, width in units } (false code = gap)
--------------------------------------------------------------------------

local function letters(s)
    local out = {}
    for ch in string.gmatch(s, ".") do out[#out + 1] = { _G["KEY_" .. ch], ch, 1 } end
    return out
end
local function join(...)
    local out = {}
    for _, t in ipairs({ ... }) do
        for _, v in ipairs(t) do out[#out + 1] = v end
    end
    return out
end

local ROWS = {
    join({ { KEY_ESCAPE, "Esc", 1 }, { false, "", 1 } },
        { { KEY_F1, "F1", 1 }, { KEY_F2, "F2", 1 }, { KEY_F3, "F3", 1 }, { KEY_F4, "F4", 1 }, { false, "", 0.5 } },
        { { KEY_F5, "F5", 1 }, { KEY_F6, "F6", 1 }, { KEY_F7, "F7", 1 }, { KEY_F8, "F8", 1 }, { false, "", 0.5 } },
        { { KEY_F9, "F9", 1 }, { KEY_F10, "F10", 1 }, { KEY_F11, "F11", 1 }, { KEY_F12, "F12", 1 } }),
    join({ { KEY_BACKQUOTE, "`", 1 } }, letters("1234567890"),
        { { KEY_MINUS, "-", 1 }, { KEY_EQUAL, "=", 1 }, { KEY_BACKSPACE, "Backspace", 2 } }),
    join({ { KEY_TAB, "Tab", 1.5 } }, letters("QWERTYUIOP"),
        { { KEY_LBRACKET, "[", 1 }, { KEY_RBRACKET, "]", 1 }, { KEY_BACKSLASH, "\\", 1.5 } }),
    join({ { KEY_CAPSLOCK, "Caps", 1.75 } }, letters("ASDFGHJKL"),
        { { KEY_SEMICOLON, ";", 1 }, { KEY_APOSTROPHE, "'", 1 }, { KEY_ENTER, "Enter", 2.25 } }),
    join({ { KEY_LSHIFT, "Shift", 2.25 } }, letters("ZXCVBNM"),
        { { KEY_COMMA, ",", 1 }, { KEY_PERIOD, ".", 1 }, { KEY_SLASH, "/", 1 }, { KEY_RSHIFT, "Shift", 2.75 } }),
    { { KEY_LCONTROL, "Ctrl", 1.5 }, { false, "", 1 }, { KEY_LALT, "Alt", 1.5 }, { KEY_SPACE, "Space", 7 },
        { KEY_RALT, "Alt", 1.5 }, { false, "", 0.5 }, { KEY_RCONTROL, "Ctrl", 1.5 } },
}
local BOARD_W = 15        -- units
local MOUSE_X = 15.6      -- units from the left
local GAP0 = 0.35         -- extra gap under the function row

-- Mouse caps: code, label, x, y (units inside the mouse block), w, h.
local MOUSE = {
    { MOUSE_LEFT, "Left", 0, 0, 1.4, 2 },
    { MOUSE_MIDDLE, "M3", 1.4, 0, 0.8, 1 },
    { MOUSE_WHEEL_UP, "Wheel", 1.4, 1, 0.8, 1 },
    { MOUSE_RIGHT, "Right", 2.2, 0, 1.4, 2 },
    { MOUSE_4, "M4", 0, 2.2, 1.8, 1 },
    { MOUSE_5, "M5", 1.8, 2.2, 1.8, 1 },
}

--------------------------------------------------------------------------
-- What each key does
--------------------------------------------------------------------------

local function bindCode(bind)
    local k = input.LookupBinding(bind)
    local code = k and input.GetKeyCode(k)
    return code and code > 0 and code or nil
end

local function cap1(s)
    s = string.Trim(s or "")
    return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- A short label from a description: up to the first ":", "(" or ";".
local function derive(text)
    return cap1(string.match(text, "^([^:%(;]+)") or text)
end

-- Codes in one keys string ("{+use} + {+reload}", "Ctrl + drag", "[rhylib_x]").
local function codesOf(keys)
    local out = {}
    for bind in string.gmatch(keys, "{([^}]+)}") do
        local c = bindCode(bind)
        if c then out[#out + 1] = c end
    end
    local rest = string.gsub(keys, "{[^}]+}", " ")
    for cv in string.gmatch(rest, "%[([%w_]+)%]") do
        local v = ConVarExists(cv) and GetConVar(cv):GetString() or ""
        local c = v ~= "" and input.GetKeyCode(v)
        if c and c > 0 then out[#out + 1] = c end
    end
    rest = string.gsub(rest, "%[[%w_]+%]", " ")
    for word in string.gmatch(rest, "[%w%-]+") do
        local c = LIT[string.lower(word)]
        if c then out[#out + 1] = c end
    end
    return out
end

-- Pretty key text with the player's own keys.
local function keyText(keys)
    local s = string.gsub(keys, "{([^}]+)}", function(bind)
        local k = input.LookupBinding(bind)
        return k and string.upper(k) or ("[" .. bind .. "]")
    end)
    s = string.gsub(s, "%[([%w_]+)%]", function(cv)
        local v = ConVarExists(cv) and GetConVar(cv):GetString() or ""
        return v ~= "" and string.upper(v) or "unbound"
    end)
    return s
end

local function split(s, sep)
    local out, from = {}, 1
    while true do
        local a, b = string.find(s, sep, from, true)
        if not a then out[#out + 1] = s:sub(from) break end
        out[#out + 1] = s:sub(from, a - 1)
        from = b + 1
    end
    return out
end

-- Every entry: { section, text, short, keys (shown), codes, main, rebind }.
local function collect()
    local list = {}
    -- Rebindable keys.
    for _, section in ipairs(Menus.sectionOrder or {}) do
        for _, st in ipairs(Menus.settings[section] or {}) do
            if st.kind == "key" and st.convar and ConVarExists(st.convar) and (not st.showIf or st.showIf()) then
                local v = GetConVar(st.convar):GetString()
                local code = v ~= "" and input.GetKeyCode(v) or 0
                if code and code > 0 then
                    list[#list + 1] = { section = section, text = st.title, short = st.short or SHORT[st.convar] or derive(st.title),
                        keys = string.upper(v), codes = { code }, main = code, rebind = true }
                end
            end
        end
    end
    -- Fixed controls.
    for _, section in ipairs(Menus.controlOrder or {}) do
        for _, c in ipairs(Menus.controls[section] or {}) do
            if not c.need or c.need() then
                local alts = split(c.keys, " / ")
                local pre, body = string.match(c.text, "^([^:/]+:%s*)(.+)$")
                local parts = split(body or c.text, " / ")
                for i, alt in ipairs(alts) do
                    local text = keyText(#alts > 1 and #parts == #alts and ((pre or "") .. parts[i]) or c.text)
                    local codes = codesOf(alt)
                    if #codes > 0 then
                        list[#list + 1] = { section = section, text = cap1(text), short = SHORT[c.text] and #alts == 1 and SHORT[c.text] or derive(text),
                            keys = keyText(alt), codes = codes, main = codes[#codes] }
                    end
                end
            end
        end
    end
    return list
end

--------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------

-- Up to two lines of text that fit maxW.
local function wrap2(text, font, maxW)
    surface.SetFont(font)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if surface.GetTextSize(try) <= maxW or cur == "" then
            cur = try
        else
            lines[#lines + 1] = cur
            cur = word
            if #lines == 2 then break end
        end
    end
    if #lines < 2 and cur ~= "" then lines[#lines + 1] = cur end
    for i, l in ipairs(lines) do lines[i] = K.Fit(l, font, maxW) end
    return lines
end

local function build(page)
    local S = K.S
    local sp = K.Scroll(page)
    sp:Dock(FILL)

    local head = K.Label(sp, "Every key Rhylib uses on your keyboard and mouse. Hover a key to see everything it does; hover a section to light up its keys. Change keys on the Controls page.", 13, nil, C.textDim)
    head:Dock(TOP)
    head:DockMargin(0, 0, S(10), S(8))
    head:SetWrap(true)
    head:SetAutoStretchVertical(true)

    local board = vgui.Create("DPanel", sp)
    board:Dock(TOP)
    board:DockMargin(0, 0, S(10), S(10))
    board:SetTall(S(500))

    local L = { caps = {}, byCode = {}, sections = {}, colours = {}, entries = {}, other = {} }

    local function refresh()
        L.entries = collect()
        L.byCode, L.sections, L.colours = {}, {}, {}
        for _, e in ipairs(L.entries) do
            if not L.colours[e.section] then
                L.sections[#L.sections + 1] = e.section
                L.colours[e.section] = PALETTE[(#L.sections - 1) % #PALETTE + 1]
            end
            local seen = {}
            for _, c in ipairs(e.codes) do
                c = ALIAS[c] or c
                if not seen[c] then
                    seen[c] = true
                    L.byCode[c] = L.byCode[c] or {}
                    table.insert(L.byCode[c], e)
                end
            end
        end
        -- Per key: main-key single entries first (rebindable keys first of all).
        local most = 0
        for c, list in pairs(L.byCode) do
            for i, e in ipairs(list) do e.rank = (e.rebind and 0 or 2) + (((ALIAS[e.main] or e.main) == c and #e.codes == 1) and 0 or 1) + i * 0.001 end
            table.sort(list, function(a, b) return a.rank < b.rank end)
            most = math.max(most, #list)
        end
        L.most = most
        L.dirty = true
        L.nextRefresh = RealTime() + 2
    end

    -- Places the caps for width w; returns the height used by caps.
    local function layout(w)
        local u = math.floor(math.min(w / 19.4, S(64)))
        L.u = u
        L.caps = {}
        local y = 0
        local placed = {}
        for r, row in ipairs(ROWS) do
            local x = 0
            for _, k in ipairs(row) do
                local kw = k[3] * u
                if k[1] then
                    L.caps[#L.caps + 1] = { code = k[1], label = k[2], x = x + 2, y = y + 2, w = kw - 4, h = u - 4 }
                    placed[k[1]] = true
                end
                x = x + kw
            end
            y = y + u + (r == 1 and math.floor(GAP0 * u) or 0)
        end
        local mx, my = math.floor(MOUSE_X * u), u + math.floor(GAP0 * u)
        for _, m in ipairs(MOUSE) do
            L.caps[#L.caps + 1] = { code = m[1], label = m[2], x = mx + math.floor(m[3] * u) + 2, y = my + math.floor(m[4] * u) + 2,
                w = math.floor(m[5] * u) - 4, h = math.floor(m[6] * u) - 4, mouse = true }
            placed[m[1]] = true
        end
        L.capsH = math.max(y, my + math.floor(3.2 * u))
        L.placed = placed
        -- Labels per cap (worked out once per layout / refresh).
        local f = K.Font(math.max(10, math.floor(u * 0.2 / K.Scale())), 600)   -- (u is pixels; the kit scales fonts again)
        L.capFont = f
        for _, cp in ipairs(L.caps) do
            local list = L.byCode[cp.code]
            local bind = input.LookupKeyBinding(cp.code)
            cp.game = bind and GAME[bind] or nil
            cp.list = list
            local text = list and list[1].short or cp.game
            cp.lines = text and wrap2(text, f, cp.w - S(8)) or nil
            -- Colours and the sections on this key (not worked out per frame).
            local col = list and L.colours[list[1].section] or nil
            cp.col = col
            cp.body = col and Color(col.r * 0.3 + 20, col.g * 0.3 + 20, col.b * 0.3 + 20, 255) or (cp.game and C.button or C.row)
            cp.secs = nil
            if list then
                local secs, seen = {}, {}
                for _, e in ipairs(list) do
                    if not seen[e.section] then seen[e.section] = true secs[#secs + 1] = L.colours[e.section] or C.textDim end
                end
                cp.secs = secs
            end
        end
        -- Rhylib keys that aren't on the drawn board.
        L.other = {}
        for c, list in pairs(L.byCode) do
            if not placed[c] then
                local name = input.GetKeyName(c) or ("#" .. c)
                L.other[#L.other + 1] = string.upper(name) .. ": " .. list[1].short
            end
        end
        table.sort(L.other)
        return L.capsH
    end

    function board:PerformLayout(w)
        -- (sized as if the scroll bar were always there, so it showing or
        -- hiding can't change the height and flicker)
        local avail = sp:GetWide() - sp:GetVBar():GetWide() - S(10)
        if avail > 0 then w = math.min(w, avail) end
        if not L.entries[1] and not L.refreshed then
            L.refreshed = true
            refresh()
        end
        local capsH = layout(w)
        L.legendY = capsH + S(14)
        -- Legend chips.
        surface.SetFont(K.Font(12, 600))
        local x, y = 0, L.legendY
        L.chips = {}
        for _, s in ipairs(L.sections) do
            local tw = surface.GetTextSize(s)
            local cw = tw + S(26)
            if x + cw > w then x, y = 0, y + S(24) end
            L.chips[#L.chips + 1] = { section = s, x = x, y = y, w = cw, h = S(20) }
            x = x + cw + S(6)
        end
        L.detailY = y + S(32)
        local want = L.detailY + S(46) + math.max(L.most or 0, 4) * S(20) + (#L.other > 0 and S(40) or 0)
        if self:GetTall() ~= want then self:SetTall(want) end
        L.dirty = false
    end

    function board:Think()
        if RealTime() > (L.nextRefresh or 0) then
            refresh()
            self:InvalidateLayout(true)
        end
        -- Hover: a key cap or a legend chip.
        local mx, my = self:CursorPos()
        local hov, chip
        if self:IsHovered() then
            for _, cp in ipairs(L.caps) do
                if mx >= cp.x and mx < cp.x + cp.w and my >= cp.y and my < cp.y + cp.h then hov = cp break end
            end
            for _, ch in ipairs(L.chips or {}) do
                if mx >= ch.x and mx < ch.x + ch.w and my >= ch.y and my < ch.y + ch.h then chip = ch.section break end
            end
        end
        L.hover, L.chip = hov, chip
    end

    local function inSection(cp, s)
        for _, e in ipairs(cp.list or {}) do
            if e.section == s then return true end
        end
        return false
    end

    function board:Paint(w, h)
        if not L.u then return end
        local u = L.u
        local fKey = K.Font(math.max(10, math.floor(u * 0.19 / K.Scale())), 700)
        local fCount = K.Font(10, 700)
        local am = surface.GetAlphaMultiplier()   -- (the pause menu fades panels with it)
        draw.NoTexture()
        for _, cp in ipairs(L.caps) do
            local list = cp.list
            local dim = L.chip and not inSection(cp, L.chip)
            if dim then surface.SetAlphaMultiplier(am * 0.3) end
            local col = cp.col
            draw.RoundedBox(4, cp.x, cp.y, cp.w, cp.h, cp.body)
            -- Section stripes along the top (one per section on this key).
            if cp.secs then
                local sw = (cp.w - 8) / #cp.secs
                for i, sc in ipairs(cp.secs) do
                    surface.SetDrawColor(sc)
                    surface.DrawRect(cp.x + 4 + math.floor((i - 1) * sw), cp.y + 3, math.ceil(sw) - 1, 3)
                end
            end
            -- Key name, count, label.
            draw.SimpleText(cp.label, fKey, cp.x + S(5), cp.y + S(7), col and C.text or (cp.game and C.textDim or C.edgeLight), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if list and #list > 1 then
                draw.SimpleText("+" .. (#list - 1), fCount, cp.x + cp.w - S(4), cp.y + S(8), col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end
            if cp.lines then
                local lh = draw.GetFontHeight(L.capFont)
                local ly = cp.y + cp.h - S(5) - #cp.lines * lh
                for i, l in ipairs(cp.lines) do
                    draw.SimpleText(l, L.capFont, cp.x + cp.w * 0.5, ly + (i - 1) * lh, col and C.text or C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                end
            end
            if L.hover == cp then
                surface.SetDrawColor(C.accent)
                surface.DrawOutlinedRect(cp.x - 1, cp.y - 1, cp.w + 2, cp.h + 2, 2)
            end
            if dim then surface.SetAlphaMultiplier(am) end
        end

        -- Legend.
        for _, ch in ipairs(L.chips or {}) do
            local on = L.chip == ch.section
            draw.RoundedBox(4, ch.x, ch.y, ch.w, ch.h, on and C.buttonHover or C.button)
            surface.SetDrawColor(L.colours[ch.section] or C.textDim)
            surface.DrawRect(ch.x + S(7), ch.y + ch.h * 0.5 - S(4), S(8), S(8))
            draw.SimpleText(ch.section, K.Font(12, 600), ch.x + S(20), ch.y + ch.h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        -- Details of the hovered key.
        local y = L.detailY
        surface.SetDrawColor(C.row)
        surface.DrawRect(0, y, w, h - y)
        local cp = L.hover
        if not cp then
            draw.SimpleText("Hover a key to see what it does.", K.Font(14, 600), S(12), y + S(12), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if #L.other > 0 then
                local t = K.Fit("Also used (not on this board): " .. table.concat(L.other, " · "), K.Font(13), w - S(24))
                draw.SimpleText(t, K.Font(13), S(12), y + S(38), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            return
        end
        local title = cp.label .. (cp.game and ("  ·  game bind: " .. cp.game) or "")
        draw.SimpleText(title, K.Font(16, 700), S(12), y + S(10), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + S(38)
        if not cp.list then
            draw.SimpleText("Rhylib doesn't use this key.", K.Font(13), S(12), y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return
        end
        local keysW = S(230)
        for _, e in ipairs(cp.list) do
            surface.SetDrawColor(L.colours[e.section] or C.textDim)
            surface.DrawRect(S(12), y + S(5), S(8), S(8))
            draw.SimpleText(K.Fit(e.section, K.Font(12, 700), S(110)), K.Font(12, 700), S(28), y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(K.Fit(e.keys .. (e.rebind and "  (rebindable)" or ""), K.Font(13, 700), keysW - S(8)), K.Font(13, 700), S(144), y, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(K.Fit(e.text, K.Font(13), w - S(144) - keysW - S(12)), K.Font(13), S(144) + keysW, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            y = y + S(20)
        end
    end

    local go = K.Button(sp, "Change keys (Controls page)", function()
        if IsValid(Menus.pause) then Menus.pause:ShowPage(Menus.SettingsPageId("Controls")) end
    end, { small = true })
    go:Dock(TOP)
    go:DockMargin(0, 0, S(10), S(10))
end

Menus.AddPage("settings.layout", {
    title = "Layout",
    group = "settings",
    order = 100 + #Menus.SETTING_TABS + 1,   -- (right after Controls)
    build = build,
})
