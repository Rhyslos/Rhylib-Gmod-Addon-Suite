--[[
    Themes (client only): the colours (and optionally the font and a few
    drawing styles) every Rhylib window and menu draws with. "dark" is the
    default and is the house style; more themes register with
    UI.RegisterTheme. Each player picks one in Settings > Interface
    (convar rhylib_theme, saved on their PC).

    How it works: every themed colour is a token, one shared Color object
    per name. Windows read the token when they draw (C.bg, UI.Col("x")),
    never copy its r/g/b at file load, so a theme change shows at once:
    UI.SetTheme writes the theme's values into the same Color objects.

        local C = Rhylib.UI.Kit.C                 -- kit tokens (kit.<key>)
        local COL_AMMO = Rhylib.UI.Col("inv.ammo", 239, 159, 39)
        surface.SetDrawColor(COL_AMMO)            -- in a Paint

      UI.Col(name, r, g, b, a)   the token's shared Color (made with this
                                 default the first time; the default is
                                 its "dark" value). UI.Col(name, Color) too.
      UI.Token(name, color)      adopt an existing Color object as a token
                                 (its current value becomes the default).
      UI.RegisterTheme(id, def)  def = { label = "Star Wars", order = 20,
                                 colors = { ["kit.bg"] = Color(...), ... },
                                 font = "Orbitron" (optional),
                                 style = { plate = "holo", ... } (optional) }
                                 Tokens a theme leaves out keep their dark value.
      UI.SetTheme(id)            switch and save the choice (also: rhylib_theme <id>).
      UI.ThemeId()               the current theme's id.
      UI.Style(key, default)     a style value of the current theme (windows
                                 that draw something theme-specific ask this).
      UI.Themes()                { {id, label}, ... } sorted by order.
    UI.themeStamp counts switches. Hook Rhylib.ThemeChanged(id) fires after a switch (windows that bake
    colours into a render target or a cached Paint rebuild then).

    Token names: "ui.<key>" for Rhylib.UI.Colors (the HUD, wheels and
    other on-screen parts draw with these), "kit.<key>" for
    Rhylib.UI.Kit.C (every window), "<addon>.<what>" for an addon's own
    colours. A window theme sets kit.* and the addons' window tokens and
    leaves ui.* alone, so the HUD keeps its look.

    HUD colours (players recolour the HUD by meaning; see the section
    below): UI.HUD_KEYS, UI.HUD_PRESETS, UI.HudCol(key, name, r, g, b, a),
    UI.HudLink(key, name), UI.HudValue / HudShown / HudPreset / HudPicked,
    UI.SetHudColour(key, col), UI.SetHudPreset(id); convars
    rhylib_hudcol_preset and rhylib_hudcol_<key>; hook
    Rhylib.HudColoursChanged().
]]

Rhylib.UI = Rhylib.UI or {}
local UI = Rhylib.UI

UI.tokens = UI.tokens or {}         -- name -> shared Color
UI.tokenDefaults = UI.tokenDefaults or {} -- name -> { r, g, b, a } (dark)
UI.themes = UI.themes or {}
UI.themeId = UI.themeId or "dark"

local cv = CreateClientConVar("rhylib_theme", "dark", true, false, "Rhylib UI theme (Settings > Interface > Theme)")

local function current() return UI.themes[UI.themeId] or UI.themes.dark end

-- Write the current theme's value (or the default) into one token.
local function applyOne(name)
    local col, def = UI.tokens[name], UI.tokenDefaults[name]
    if not (col and def) then return end
    local th = current()
    local v = th and th.colors and th.colors[name]
    if v then
        col.r, col.g, col.b, col.a = v.r, v.g, v.b, v.a or 255
    else
        col.r, col.g, col.b, col.a = def[1], def[2], def[3], def[4]
    end
    -- (a HUD colour the player picked: its colour, the token's own alpha)
    local key = UI.hudLinks and UI.hudLinks[name]
    local hv = key and UI.HudValue and UI.HudValue(key)
    if hv then col.r, col.g, col.b = hv.r, hv.g, hv.b end
end

-- UI.Token(name, color): adopt an existing Color object as the token
-- (its value now is the dark default). Returns the token's Color.
-- Example: Rhylib.UI.Token("ui.text", Rhylib.UI.Colors.text)
function UI.Token(name, color)
    local have = UI.tokens[name]
    if have then return have end
    UI.tokens[name] = color
    UI.tokenDefaults[name] = { color.r, color.g, color.b, color.a or 255 }
    applyOne(name)
    return color
end

-- UI.Col(name, r, g, b, a) or UI.Col(name, Color): the token's shared
-- Color (made with that default the first time). Read it when drawing.
-- Example: local COL_WARN = Rhylib.UI.Col("eod.warn", 239, 159, 39)
function UI.Col(name, r, g, b, a)
    local have = UI.tokens[name]
    if have then return have end
    if istable(r) then r, g, b, a = r.r, r.g, r.b, r.a end
    return UI.Token(name, Color(r or 255, g or 255, b or 255, a or 255))
end

-- UI.RegisterTheme(id, def): add or replace a theme (see the header).
-- The player's saved theme applies itself as soon as it registers (also
-- from an addon that loads after core), and re-registering the shown one
-- (a Lua refresh) applies its new values.
function UI.RegisterTheme(id, def)
    def = def or {}
    def.id = id
    def.label = def.label or id
    def.order = def.order or 50
    def.colors = def.colors or {}
    def.style = def.style or {}
    UI.themes[id] = def
    if id == UI.wantTheme or id == UI.themeId then UI.SetTheme(id, true) end
end

-- UI.Themes(): { { id, label }, ... } sorted by order.
function UI.Themes()
    local out = {}
    for id, t in pairs(UI.themes) do out[#out + 1] = { id = id, label = t.label, order = t.order } end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return out
end

function UI.ThemeId() return UI.themeId end

-- UI.Style(key, default): the current theme's style value for key.
-- Example: if Rhylib.UI.Style("plate") == "holo" then ... end
function UI.Style(key, default)
    local th = current()
    local v = th and th.style and th.style[key]
    if v == nil then return default end
    return v
end

-- UI.Family(): the font family the current theme draws text in.
function UI.Family()
    local th = current()
    return th and th.font or "Roboto"
end

-- UI.SetTheme(id, keepChoice): switch theme now (an unknown id shows dark
-- until a theme with that id registers). The player's choice (convar
-- rhylib_theme) is saved, unless keepChoice (applying a registered or
-- loaded theme never overwrites what the player picked).
function UI.SetTheme(id, keepChoice)
    if not keepChoice then UI.wantTheme = id end
    local show = UI.themes[id] and id or "dark"
    local oldFamily = UI.Family()
    UI.themeId = show
    -- (K.ThemedText labels compare this to re-apply their colour and font)
    UI.themeStamp = (UI.themeStamp or 0) + 1
    for name in pairs(UI.tokens) do applyOne(name) end
    -- (a different font family: build the fonts again)
    if UI.Family() ~= oldFamily then UI.fonts = {} end
    if not keepChoice and cv:GetString() ~= id then RunConsoleCommand("rhylib_theme", id) end
    hook.Run("Rhylib.ThemeChanged", show)
end

-- The player's saved choice (a theme from a later addon applies itself when
-- it registers under that id).
UI.wantTheme = cv:GetString() ~= "" and cv:GetString() or "dark"

UI.RegisterTheme("dark", { label = "Dark (default)", order = 0 })

-- The shared palette becomes tokens "ui.<key>" (on a refresh of cl_10_ui
-- its table is new: put the tokens back into it).
for k, col in pairs(UI.Colors) do
    UI.Colors[k] = UI.Token("ui." .. k, col)
end

--------------------------------------------------------------------------
-- HUD colours (Settings > HUD colours): players recolour the HUD by
-- meaning (health, armour, squad...), e.g. for colour blindness. Each
-- meaning is a key; HUD code makes its colours with UI.HudCol(key, name,
-- r, g, b, a) (a token linked to that key) or links a token it already
-- has with UI.HudLink(key, name). With the Default preset and nothing
-- picked every token keeps its own default (the HUD looks as it always
-- did); otherwise every token of a key takes the key's colour (r, g, b;
-- each keeps its own alpha). Convars (saved on the player's PC):
-- rhylib_hudcol_preset (default / rg / by / hc) and rhylib_hudcol_<key>
-- ("" = the preset's, else "rrggbb"). Hook Rhylib.HudColoursChanged()
-- fires after a change (render targets that bake HUD colours rebuild).
--------------------------------------------------------------------------

-- { id, label, what it colours, default colour shown in Settings }
UI.HUD_KEYS = {
    { "text", "HUD text and lines", "Numbers, ticks, compass, the visor rim", Color(232, 241, 247) },
    { "health", "Health", "Health bar and number", Color(214, 88, 76) },
    { "critical", "Health critical", "Under 30%, the red pulse, downed timer", Color(255, 60, 50) },
    { "armour", "Armour", "Armour bar and number", Color(90, 150, 255) },
    { "warn", "Warning", "Low ammo, low stamina, mode in use", Color(239, 159, 39) },
    { "danger", "Danger", "Empty, exhausted, spotted, jammed", Color(226, 75, 74) },
    { "selected", "Selected", "The weapon in your hands, picked items", Color(133, 183, 235) },
    { "squad", "Squad mates", "Radar, SQ square, squad voice", Color(92, 214, 125) },
    { "friend", "Other friendlies", "Everyone else on the radar", Color(79, 175, 255) },
    { "enemy", "Enemy marks", "Q-marks, flagged mines, sensor alerts", Color(235, 60, 50) },
    { "objective", "Objectives and leader", "Objective markers, your squad leader", Color(255, 200, 70) },
    { "sim", "Training health", "Sim health with a training gun", Color(240, 200, 60) },
}
UI.hudKeyIndex = {}
for i, k in ipairs(UI.HUD_KEYS) do UI.hudKeyIndex[k[1]] = i end

-- Presets: { id, label, { key = Color } } (Default changes nothing).
UI.HUD_PRESETS = {
    { "default", "Default", nil },
    { "rg", "Red-green", { text = Color(255, 255, 255), health = Color(230, 159, 0), critical = Color(255, 90, 0), armour = Color(86, 180, 233),
        warn = Color(240, 228, 66), danger = Color(213, 94, 0), selected = Color(154, 209, 245), squad = Color(86, 180, 233),
        friend = Color(194, 204, 255), enemy = Color(255, 122, 26), objective = Color(240, 228, 66), sim = Color(240, 228, 66) } },
    { "by", "Blue-yellow", { text = Color(255, 255, 255), health = Color(232, 71, 91), critical = Color(255, 42, 42), armour = Color(46, 196, 182),
        warn = Color(255, 154, 162), danger = Color(215, 38, 61), selected = Color(94, 234, 212), squad = Color(163, 230, 53),
        friend = Color(46, 196, 182), enemy = Color(255, 51, 102), objective = Color(255, 179, 193), sim = Color(255, 179, 193) } },
    { "hc", "High contrast", { text = Color(255, 255, 255), health = Color(255, 64, 64), critical = Color(255, 0, 0), armour = Color(0, 183, 255),
        warn = Color(255, 208, 0), danger = Color(255, 0, 0), selected = Color(0, 255, 255), squad = Color(0, 255, 102),
        friend = Color(0, 183, 255), enemy = Color(255, 0, 170), objective = Color(255, 208, 0), sim = Color(255, 208, 0) } },
}
local presetById = {}
for _, p in ipairs(UI.HUD_PRESETS) do presetById[p[1]] = p end

UI.hudLinks = UI.hudLinks or {}   -- token name -> key
UI.hudLinked = UI.hudLinked or {} -- key -> { token names }

local cvPreset = CreateClientConVar("rhylib_hudcol_preset", "default", true, false, "HUD colour preset: default, rg (red-green), by (blue-yellow), hc (high contrast)")
local cvKey = {}
for _, k in ipairs(UI.HUD_KEYS) do
    cvKey[k[1]] = CreateClientConVar("rhylib_hudcol_" .. k[1], "", true, false, "HUD colour for " .. k[2] .. ": rrggbb, or empty for the preset's")
end

local function parseHex(s)
    s = string.gsub(tostring(s or ""), "[^%x]", "")
    if #s ~= 6 then return nil end
    return Color(tonumber(string.sub(s, 1, 2), 16), tonumber(string.sub(s, 3, 4), 16), tonumber(string.sub(s, 5, 6), 16))
end
local cache = {}  -- key -> Color or false (rebuilt on a change)
local function rebuildCache()
    local p = presetById[cvPreset:GetString()] or presetById.default
    for _, k in ipairs(UI.HUD_KEYS) do
        local id = k[1]
        cache[id] = parseHex(cvKey[id]:GetString()) or (p[3] and p[3][id]) or false
    end
end
rebuildCache()

-- UI.HudValue(key): the colour the player's choice gives that key, or nil
-- (Default preset, nothing picked: tokens keep their own colours).
function UI.HudValue(key) return cache[key] or nil end

-- UI.HudShown(key): the colour to show for a key in Settings (the
-- picked / preset one, else the key's default).
function UI.HudShown(key)
    local v = cache[key]
    if v then return v end
    local i = UI.hudKeyIndex[key]
    return i and UI.HUD_KEYS[i][4] or color_white
end

-- UI.HudPreset(): the current preset id. UI.HudPicked(key): true when the
-- player picked that key's colour (not the preset's).
function UI.HudPreset() return presetById[cvPreset:GetString()] and cvPreset:GetString() or "default" end
function UI.HudPicked(key) return parseHex(cvKey[key] and cvKey[key]:GetString()) ~= nil end

local function applyKey(key)
    for _, name in ipairs(UI.hudLinked[key] or {}) do applyOne(name) end
end
local function applyAll()
    rebuildCache()
    for _, k in ipairs(UI.HUD_KEYS) do applyKey(k[1]) end
    hook.Run("Rhylib.HudColoursChanged")
end

-- UI.HudLink(key, name): link an existing token to a HUD colour key.
function UI.HudLink(key, name)
    if not UI.hudKeyIndex[key] or not UI.tokens[name] then return end
    if UI.hudLinks[name] == key then return end
    UI.hudLinks[name] = key
    local list = UI.hudLinked[key] or {}
    UI.hudLinked[key] = list
    list[#list + 1] = name
    applyOne(name)
end

-- UI.HudCol(key, name, r, g, b, a): a token (UI.Col) linked to a HUD key:
-- its default is the HUD's look today, the player's choice recolours it.
-- Example: local COL_HP = Rhylib.UI.HudCol("health", "hud.health", 214, 88, 76)
function UI.HudCol(key, name, r, g, b, a)
    local col = UI.Col(name, r, g, b, a)
    UI.HudLink(key, name)
    return col
end

-- UI.SetHudColour(key, col): pick a colour for one key (nil = back to the
-- preset's). UI.SetHudPreset(id): pick a preset (clears picked colours).
function UI.SetHudColour(key, col)
    if not cvKey[key] then return end
    RunConsoleCommand("rhylib_hudcol_" .. key, col and string.format("%02x%02x%02x", col.r, col.g, col.b) or "")
end
function UI.SetHudPreset(id)
    if not presetById[id] then return end
    for _, k in ipairs(UI.HUD_KEYS) do
        if cvKey[k[1]]:GetString() ~= "" then RunConsoleCommand("rhylib_hudcol_" .. k[1], "") end
    end
    RunConsoleCommand("rhylib_hudcol_preset", id)
end

-- (convars change a frame after RunConsoleCommand; a preset clears many
-- at once: apply once, a frame later)
local applyQueued = false
local function queueApply()
    if applyQueued then return end
    applyQueued = true
    timer.Simple(0, function() applyQueued = false applyAll() end)
end
cvars.AddChangeCallback("rhylib_hudcol_preset", queueApply, "rhylib.hudcol")
for _, k in ipairs(UI.HUD_KEYS) do
    cvars.AddChangeCallback("rhylib_hudcol_" .. k[1], queueApply, "rhylib.hudcol")
end

-- The shared palette's HUD meanings.
UI.HudLink("text", "ui.text")
UI.HudLink("warn", "ui.warn")
UI.HudLink("danger", "ui.bad")
UI.HudLink("selected", "ui.accent")

cvars.AddChangeCallback("rhylib_theme", function(_, _, new)
    if new ~= UI.wantTheme then UI.SetTheme(new) end
end, "rhylib.theme")

UI.SetTheme(UI.wantTheme, true)
