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

cvars.AddChangeCallback("rhylib_theme", function(_, _, new)
    if new ~= UI.wantTheme then UI.SetTheme(new) end
end, "rhylib.theme")

UI.SetTheme(UI.wantTheme, true)
