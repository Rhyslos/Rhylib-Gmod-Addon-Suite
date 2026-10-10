# rhylib_menus: Pause menu, UI kit and staff pages

Replaces the menus players see most: Esc opens a Rhylib pause menu (Shift + Esc still gives Garry's Mod's own), with side-bar groups for Jobs & shop, Character, Unit, Settings and Staff. It brings the DarkRP F4 menu (jobs, shop, profile) into that menu, a scoreboard grouped by job, a killfeed, a Controls page with key clash warnings, a drawn keyboard layout, the hold-E interaction wheel, a restyled spawn window for staff, the Server settings page (every config key and model override, editable in game) and a live profiler page. It also ships the UI kit (`Rhylib.Menus.Kit`) that the other Rhylib addons build their windows with.

Everything is client side. Buttons only run console or chat commands; the server (DarkRP, the admin mod, Rhylib's own commands) checks rights as usual.

## Requirements

- Required: `rhylib_core`.
- Several addons need this one (see CLAUDE.md "Workshop" table): `datapad`, `radio`, `roster`, `skills`, `eod` require it; `mp`, `spawns`, `toolgun` work better with it.
- Uses if present: DarkRP (F4 pages, scoreboard groups), `rhylib_admin` (Commands page, staff wheel options, restart button), ULX or SAM (Commands page without rhylib_admin), `rhylib_medical` (downed targets for the wheel), `rhylib_toolgun` (Rhylib tab and R key for the spawn window), `rhylib_skills` (Q = Mark target).
- No Workshop content.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_menus.lua` | shared | Loads the module (needs rhylib_core). |
| `sh_00_config.lua` | shared | Makes `Rhylib.Menus`, registers the `menus` config keys. |
| `cl_00_kit.lua` | client | The UI kit (`Menus.Kit`): plates, buttons, rows, toggles, sliders, prompts... and the Esc "closers". |
| `cl_10_pause.lua` | client | The pause menu, its pages and groups (`Menus.AddPage`, `Menus.AddGroup`). |
| `cl_20_settings.lua` | client | Settings pages (Interface, Camera & motion, Audio, Controls) and `Menus.AddSetting`. |
| `cl_25_controls.lua` | client | Controls help: key clash box, fixed controls (`Menus.AddControl`), F1. |
| `cl_26_layout.lua` | client | Settings > Layout: drawn keyboard and mouse with every Rhylib key. |
| `cl_30_commands.lua` | client | Staff > Commands: player actions, bans, log, server tools (`Menus.AddCommand`). |
| `cl_35_hostsettings.lua` | client | Staff > Server settings: every config key and model override. |
| `cl_36_profiler.lua` | client | Staff > Profiler: live server numbers. |
| `cl_40_scoreboard.lua` | client | Scoreboard (Tab) and `Menus.AddStaffOptions`. |
| `cl_50_killfeed.lua` | client | Killfeed (top right). |
| `cl_60_f4.lua` | client | DarkRP F4 pages: Jobs, Shop, Profile. |
| `cl_70_wheel.lua` | client | Interaction wheel (hold E) and the progress bar. |
| `cl_80_spawnmenu.lua` | client | Turns the Q menu off (Q = Mark target); staff open it from the toolgun. |
| `cl_85_spawn.lua` | client | The spawn window (`Menus.Spawn`): Rhylib, Props, Entities, Weapons, NPCs, Vehicles, Tools. |

## For server owners

### Settings

Config module `"menus"`:

| Key | Default | What it does |
|---|---|---|
| `title` | `""` | Title on the pause menu and scoreboard (empty = the server name). |
| `killfeedTime` | `6` | Seconds a killfeed line stays. |
| `killfeedMax` | `6` | Most killfeed lines at once. |

Change them on Staff > Server settings (Server & interface > Menus), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("menus", "title", "Coruscant Guard RP")
Rhylib.Config.Set("menus", "killfeedTime", 8)
```

### The Server settings page

Staff > Server settings (holders of `rhylib.settings`, superadmin by default) lists every Rhylib config key:

- **Model overrides**: every model the suite uses, with a picture. Type a path, or **Pick from the spawn menu** (the spawn window opens in pick mode; click any model), then **Apply**. The server refuses paths it doesn't have. New spawns use the new model at once; things already placed change after a map change (the bar on top counts them and has **Restart map** for staff with the `map` permission).
- **Changed settings**: everything changed here, each with **Reset** (back to the host file value or the default).
- Modules by category (Combat, Soldiers, Units & roles, NPCs, Server & interface, Other). Big modules have section chips.
- Values: on/off switches for booleans; a text box for the rest (Enter applies; tables are JSON, vectors and angles are `x y z`). A red outline means it couldn't be read.

Changes made here are saved by rhylib_core and win over host config files.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_menu` | anyone (client) | Open or close the pause menu. |
| `rhylib_controls` | anyone (client) | Open Settings > Controls (same as F1). |
| `rhylib_f4` | anyone (client) | Same as F4. |

Which staff pages show:

| Page | Shown to |
|---|---|
| Commands | Staff: rhylib_admin level above 0, else `IsAdmin`, else ULX/SAM kick rights. |
| Server settings | `rhylib.settings` (superadmin). |
| Profiler | `rhylib.profiler` (superadmin). |

These only decide what the client shows; every action is checked again on the server.

## For players (short)

| Key | What it does |
|---|---|
| Esc | Rhylib menu (closes any open Rhylib window first). Shift + Esc: the game's menu. |
| F1 | Controls page. |
| F4 | Jobs, shop and profile (F4 again closes). |
| Tab | Scoreboard; right-click frees the mouse. |
| hold E on a player | Interaction wheel: move the mouse to an action, let go of E to do it (let go in the middle to cancel). On a downed player it opens at once. |
| Q | Mark target (with rhylib_skills). The spawn menu is off. |
| R with the toolgun (staff) | Spawn window: tap opens, R again closes, two quick taps open the old Q menu. |

## For developers

### Public functions

All client side, on `Rhylib.Menus` (`Menus`).

| Function | What it does |
|---|---|
| `Menus.AddPage(id, page)` | Adds a pause-menu page: `{ title, order, group, visible(), build(panel), sub }`. |
| `Menus.AddGroup(id, { title, order })` | Adds a side-bar submenu. Built in: `play`, `character`, `unit`, `settings`, `staff`. |
| `Menus.OpenPause()` / `ClosePause()` / `RefreshPause()` | Open / close / rebuild the current page. `Menus.pause:ShowPage(id)` switches page. |
| `Menus.AddSetting(section, setting)` | Adds a settings row bound to a client convar (toggle, choice, slider, key). |
| `Menus.RefillSettings()` | Refills the open settings tab (after a `showIf` condition changes). |
| `Menus.SettingsPageId(tab)` | Page id of a settings tab, e.g. `"settings.controls"`. |
| `Menus.AddControl(section, keys, text, need)` | Adds a fixed control to the Controls and Layout pages. |
| `Menus.OpenControls()` | Opens Settings > Controls. |
| `Menus.AddCommand(group, cmd)` | Adds a row to Staff > Commands > Server. |
| `Menus.AdminMod()` / `Menus.IsStaff()` | The admin mod found / whether to show staff pages. |
| `Menus.RunPlayerAction(verb, ply)` | Runs a ULX/SAM player action (goto, bring, kick...). |
| `Menus.AddStaffOptions(menu, ply)` | Adds the staff actions on `ply` to a `K.Menu()`. |
| `Menus.AddKill(attacker, aTeam, inflictor, victim, vTeam)` | Adds a killfeed line. |
| `Menus.RegisterCloser(id, fn)` / `Menus.CloseAll()` | What Esc closes before opening the menu. |
| `Menus.ToggleF4()` | F4 behaviour. |
| `Menus.Wheel.Open(target)` / `OpenList(title, list, code)` / `Close()` | Interaction wheel; a list wheel with no target. |
| `Menus.WheelProgress(text, secs)` / `WheelProgressStop()` | Progress bar under the crosshair. |
| `Menus.OpenSpawnMenu()` / `CloseSpawnMenu()` / `SpawnMenuOpen()` | The old Q menu (off by default). |
| `Menus.Spawn.AddTab(id, tab)` | Adds a tab to the spawn window. |
| `Menus.Spawn.Open()` / `Close()` / `IsOpen()` | The spawn window. |
| `Menus.Spawn.PickModel(cb, label)` | Opens the spawn window in pick mode; `cb(path)` gets the clicked model. |
| `Menus.Spawn.Preview(panel, info)` | The big turning model preview next to the mouse. |
| `Menus.Spawn.Tile`, `ModelTile`, `CatalogueTab`, `ModelOf`, `IconMat` | Building blocks for spawn tabs. |

### The UI kit (`Rhylib.Menus.Kit`)

Sizes are given at 1080p; `K.S(n)` scales them. Colours are in `K.C` (`text`, `textDim`, `label`, `accent`, `good`, `warn`, `bad`, `bg`, `row`, `rowAlt`, `rowHover`, `header`, `button`, `buttonHover`, `buttonDown`, `edgeDark`, `edgeLight`, `tick`, `dim`).

A complete small window, then each widget on its own:

```lua
local K = Rhylib.Menus.Kit
local C = K.C

-- A window: a plain EditablePanel painted with K.Plate.
local f = vgui.Create("EditablePanel")
f:SetSize(K.S(520), K.S(400))
f:Center()
f:MakePopup()
f:DockPadding(K.S(12), K.S(42), K.S(12), K.S(12))        -- leave room for the 30 px title bar
function f:Paint(w, h)
    K.Plate(0, 0, w, h, { title = "My window", sub = "v1", ticks = "all" })
end
-- Esc closes it (before the pause menu opens).
Rhylib.Menus.RegisterCloser("mywindow", function()
    if IsValid(f) then f:Remove() return true end
    return false
end)
```

**K.Plate** (in a Paint): dark plate, optional title bar, outline and corner ticks. Returns the y where content starts.

```lua
function panel:Paint(w, h)
    local top = K.Plate(0, 0, w, h, {
        title = "Armoury",      -- header bar (caps); leave out for a plain plate
        sub = "12 items",       -- dim text on the right of the header
        ticks = "all",          -- true = bottom corners, "all" = four corners
        rule = C.warn,          -- line under the header (default the accent)
        bg = Color(30, 30, 30), -- background (default C.bg)
        alpha = 200,            -- fade the whole plate
    })
    draw.SimpleText("Content starts here", K.Font(13), K.S(12), top + K.S(10), C.text)
end
```

**K.Ticks**, **K.Caps**, **K.Fit**, **K.SetCol** (drawing helpers, in a Paint):

```lua
function panel:Paint(w, h)
    K.SetCol(C.accent, 120)                    -- SetDrawColor with an extra alpha
    surface.DrawRect(0, 0, w, 2)
    K.Ticks(0, 0, w, h, true)                  -- ticks on all four corners
    K.Caps("Status", K.S(10), K.S(14))         -- small caps label, centred on y
    local name = K.Fit(longName, K.Font(14), w - K.S(20))   -- cut with "…" to fit
    draw.SimpleText(name, K.Font(14), K.S(10), K.S(34), C.text)
end
```

**K.Button**: returns a DButton (34 px, or 26 small). Dock or size it yourself.

```lua
local save = K.Button(f, "Save", function(btn)
    print("saved")
end, {
    accent = true,                              -- bright stripe (main action)
    enabled = function() return changed end,    -- dim and unclickable while false
    tooltip = "Save your changes",
})
save:Dock(BOTTOM)

local del = K.Button(f, "Delete", function() end, { danger = true, small = true })  -- red stripe
local tab = K.Button(f, "Orders", function() current = "orders" end,
    { small = true, selected = function() return current == "orders" end })        -- drawn pressed while selected
local med = K.Button(f, "Heal", function() end, { col = Color(91, 201, 122) })      -- colour-coded group
local live = K.Button(f, function() return "Count: " .. n end, function() end)    -- label redrawn each frame
```

**K.Label**: a wrapping label whose height follows its text.

```lua
local l = K.Label(f, "Pick a squad to join. Locked squads need an invite.", 13, nil, C.textDim)
l:Dock(TOP)
```

**K.Heading**: caps title with a rule under it (optionally colour-coded).

```lua
K.Heading(f, "Weapons"):Dock(TOP)
K.Heading(f, "Medical", Color(91, 201, 122)):Dock(TOP)   -- coloured chip, title and rule
```

**K.Scroll**: scroll panel with a thin bar; dock children TOP inside it.

```lua
local sp = K.Scroll(f)
sp:Dock(FILL)
for i = 1, 30 do
    local l = K.Label(sp, "Line " .. i, 13)
    l:Dock(TOP)
    l:DockMargin(0, 0, K.S(10), K.S(2))   -- right margin keeps clear of the bar
end
```

**K.Row**: a settings-style row; put the control in `row.right`.

```lua
local row = K.Row(sp, "Night vision", "Lights up dark areas through optics")
row:Dock(TOP)
row:DockMargin(0, 0, K.S(10), K.S(4))
row.right:SetWide(K.S(200))   -- default 320
```

**K.Toggle**: an ON/OFF switch bound to get/set.

```lua
local on = false
K.Toggle(row.right, function() return on end, function(v) on = v end):Dock(RIGHT)
```

**K.Choices**: mutually exclusive buttons.

```lua
local side = "1"
K.Choices(row.right,
    { { "-1", "Left" }, { "1", "Right" } },      -- { value, label }, left to right
    function() return side end,                 -- current value (drawn pressed)
    function(v) side = v end                    -- clicked
):Dock(FILL)
```

**K.Slider**: drag bar with the value on its right.

```lua
local vol = 0.5
K.Slider(row.right, 0, 1, 2,                     -- min, max, decimals
    function() return vol end,
    function(v) vol = v end                      -- only called when the rounded value changes
):Dock(FILL)
```

**K.TextEntry**: a one-line text box (a normal DTextEntry underneath).

```lua
local e = K.TextEntry(f, "Squad name")
e:Dock(TOP)
e.OnEnter = function(self) print("typed", self:GetValue()) end
```

**K.Menu**: a right-click menu in the house style.

```lua
local m = K.Menu()
m:AddOption("Copy SteamID", function() SetClipboardText(ply:SteamID()) end)
m:AddSpacer()
m:AddOption("Kick", function() RunConsoleCommand("ulx", "kick", ply:Nick()) end)
m:Open()   -- at the mouse
```

**K.Prompt**: ask for a line of text.

```lua
K.Prompt("Rename squad", "New name", currentName, function(text)
    text = string.Trim(text)
    if text ~= "" then RunConsoleCommand("my_rename", text) end
end)
```

**K.Tint**: give one window its own accent colour (every Kit widget inside uses it).

```lua
function f:Paint(w, h) K.Plate(0, 0, w, h, { title = "212th computer" }) end
K.Tint(f, function() return Color(230, 130, 40) end)   -- call after setting Paint
```

### Adding a pause-menu page

```lua
-- Client file in your addon. rhylib_menus may load after your addon
-- (addons load in name order), so add the page now and again at
-- InitPostEntity; adding the same id twice just replaces it.
local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and Menus.Kit) then return end
    local K = Menus.Kit
    Menus.AddPage("convoy", {
        title = "Convoy",
        group = "unit",              -- side-bar submenu: play / character / unit / settings / staff
        order = 40,                  -- lower = higher in the group
        visible = function()         -- optional: hide it for some players
            return LocalPlayer():Team() ~= TEAM_CADET
        end,
        build = function(panel)      -- runs every time the page is shown, into an empty panel
            Menus.pages.convoy.sub = "3 vehicles"     -- optional dim text on the page header
            local sp = K.Scroll(panel)
            sp:Dock(FILL)
            K.Heading(sp, "Vehicles"):Dock(TOP)
            local row = K.Row(sp, "LAAT/i", "Ready at the hangar")
            row:Dock(TOP)
            K.Button(row.right, "Request", function()
                RunConsoleCommand("convoy_request", "laat")
            end, { small = true, accent = true }):Dock(RIGHT)
        end,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "convoy.page", addPage)
```

Open it from code with `Rhylib.Menus.lastPage = "convoy"; Rhylib.Menus.OpenPause()`, or `Rhylib.Menus.pause:ShowPage("convoy")` while the menu is open.

### Adding a settings row

```lua
-- The row only shows while the convar exists, so create it first.
CreateClientConVar("convoy_markers", "1", true, false)
CreateClientConVar("convoy_marker_size", "24", true, false)
CreateClientConVar("convoy_marker_style", "dot", true, false)
CreateClientConVar("convoy_key", "n", true, false)

local Menus = Rhylib.Menus
Menus.AddSetting("Convoy", {             -- section heading
    id = "convoy.markers", order = 10,   -- id: unique; same id again replaces the row
    title = "Convoy markers", desc = "Show where the convoy vehicles are",
    kind = "toggle", convar = "convoy_markers",
})
Menus.AddSetting("Convoy", {
    id = "convoy.size", order = 20,
    title = "Marker size",
    kind = "slider", convar = "convoy_marker_size", min = 8, max = 64,   -- decimals = 1 for 0.1 steps
    preview = true,                      -- hovering it undims the game (for HUD tweaks)
    showIf = function() return GetConVar("convoy_markers"):GetBool() end,
})
Menus.AddSetting("Convoy", {
    id = "convoy.style", order = 30,
    title = "Marker style",
    kind = "choice", convar = "convoy_marker_style",
    options = { { "dot", "Dot" }, { "ring", "Ring" } },
    tab = "Interface",                   -- optional; else picked by Menus.SettingTab
})
Menus.AddSetting("Convoy", {
    id = "convoy.key", order = 40,
    title = "Call convoy key", kind = "key", convar = "convoy_key",   -- goes to the Controls tab
    short = "Convoy",                    -- label on the Settings > Layout key cap
})
-- showIf depends on another setting: refill the open tab when it changes.
cvars.AddChangeCallback("convoy_markers", function() if Rhylib.Menus.RefillSettings then Rhylib.Menus.RefillSettings() end end, "convoy")
```

Same as pages: if your addon loads before rhylib_menus, add the rows again at InitPostEntity.

### Adding a fixed control

```lua
Rhylib.Menus.AddControl("Convoy", "{+use} + {+reload}", "Board the nearest vehicle",
    function() return Rhylib.Convoy ~= nil end)      -- need(): hide the row when false
-- {+bind} shows the player's own key; [convar] shows a key setting's key:
Rhylib.Menus.AddControl("Convoy", "[convoy_key]", "Call the convoy")
```

### Adding an interaction-wheel option

```lua
-- Runs each time a wheel opens on a player. Don't return anything, so
-- every addon's hook runs.
Rhylib.Hook.Add("Rhylib.WheelOptions", "convoy.wheel", function(target, me, add)
    if not target:Alive() then return end
    local seats = Convoy.FreeSeats(me)
    add("Offer a lift", function(t)             -- t = the target, when picked
        net.Start("convoy.offer") net.WriteEntity(t) net.SendToServer()
    end, {
        order = 50,                             -- place clockwise from the top (others use 10-90)
        sub = seats .. " seats free",           -- dim second line
        disabled = seats == 0 and "No free seats" or nil,   -- reason: shown dim, can't be picked
    })
end)
```

Entities with `ENT.RhylibWheel = true` open their own wheel at once on E; add to it with hook `Rhylib.WheelEntityOptions(ent, me, add)`. A wheel with a fixed list and no target (held while a button is down):

```lua
-- (convoy_wheel_key: a key setting of your own, e.g. "v")
Rhylib.Hook.Add("PlayerBindPress", "convoy.orderwheel", function(ply, bind, pressed, code)
    if not (pressed and code == input.GetKeyCode(GetConVar("convoy_wheel_key"):GetString())) then return end
    local ok = Rhylib.Menus.Wheel.OpenList("Convoy", {
        { label = "Mount up", run = function() RunConsoleCommand("convoy_order", "mount") end, col = Color(242, 209, 75) },
        { label = "Dismount", run = function() RunConsoleCommand("convoy_order", "dismount") end, disabled = noVehicle },
    }, code)
    if ok then return true end
end)
```

For timed actions the server finishes, show `Rhylib.Menus.WheelProgress("Boarding", 2)` and call `WheelProgressStop()` if it's cancelled.

### Adding a spawn-window tab

```lua
-- A ready-made tab: categories on the left, tiles on the right, search included.
local function addTab()
    local SP = Rhylib.Menus and Rhylib.Menus.Spawn
    if not (SP and SP.AddTab) then return end
    local tab = SP.CatalogueTab(function()       -- called when the tab is first shown
        local items = {}
        for _, v in ipairs(Convoy.VEHICLES) do
            items[#items + 1] = {
                cat = v.category,               -- left column
                name = v.name,                  -- tile label (searched)
                extra = v.class,                -- shown in the preview, also searched
                model = v.model,                -- 3D tile picture and hover preview
                mat = SP.IconMat({ "entities/" .. v.class .. ".png" }),   -- icon instead, if it exists
                tip = "Click: spawn it where you look",
                run = function() RunConsoleCommand("convoy_spawn", v.class) end,
                menu = function(m) m:AddOption("Copy class", function() SetClipboardText(v.class) end) end,
            }
        end
        return items
    end, { "Transports", "Gunships" })          -- these categories first, the rest A-Z
    tab.title, tab.order = "Convoy", 5          -- after Rhylib (0), before Props (10)
    SP.AddTab("convoy", tab)
end
addTab()
Rhylib.Hook.Add("InitPostEntity", "convoy.spawntab", addTab)
```

Or a fully custom tab: `SP.AddTab("notes", { title = "Notes", order = 70, build = function(body) ... end, onShow = function(body) ... end, search = function(body, text) ... end })`. `build` runs once (the window is kept between openings); `onShow` every time the tab comes back.

### Adding a server tool button (Staff > Commands > Server)

```lua
Rhylib.Menus.AddCommand("Convoy", {       -- group = heading
    id = "convoy.reset", order = 10,
    title = "Reset the convoy", desc = "Despawns every convoy vehicle",
    run = function() RunConsoleCommand("convoy_reset") end,   -- the server checks rights
})
Rhylib.Menus.AddCommand("Convoy", {
    id = "convoy.size", order = 20, title = "Convoy size",
    choices = { { "2", "Small" }, { "4", "Large" } },
    current = function() return GetGlobal2String("convoy_size", "2") end,
    run = function(arg) RunConsoleCommand("convoy_size", arg) end,
})
```

### Hooks

Fired by this addon:

- `Rhylib.WheelOptions(target, me, add)`: a wheel is opening on player `target`; call `add(label, run, opts)` for each action.
- `Rhylib.WheelEntityOptions(ent, me, add)`: the same for an entity with `ENT.RhylibWheel`.
- `Rhylib.MarkKey()`: Q (`+menu`) was pressed while the spawn menu is shut (rhylib_skills marks a target).

Also calls the gamemode hooks `OnSpawnMenuOpen` / `OnSpawnMenuClose` and `PopulatePropMenu` (to fill spawnlists).

Listened to: `OnPauseMenuShow` (Esc), `PlayerBindPress` (F1, F4, Tab right-click, E, Q), `ScoreboardShow` / `ScoreboardHide` (other scoreboards' hooks on these are removed), `SpawnMenuOpen` (refused unless opened by `Menus.OpenSpawnMenu`), `InputMouseApply` (view frozen while the wheel is open), `OnTextEntryGetFocus` / `LoseFocus` (spawn window keyboard), `Initialize` / `InitPostEntity` (killfeed takes over `GAMEMODE.AddDeathNotice`), `DarkRPFinishedLoading` (F4 takes over DarkRP's menu functions). It adds the "Staff" option to its own wheel hook.

### Network messages

rhylib_menus registers none. The Profiler page sends `rhylib.core.profsub` (bool) and reads `rhylib.core.profdata` (UInt 16 length + compressed JSON); the Server settings page goes through `Rhylib.Settings` (rhylib_core's `core.cfg*` messages). Everything else runs console or chat commands.

### Saved data

None on the server. The last page and settings tab are kept for the session only (`Menus.lastPage`, `Menus.settingsTab`). Settings rows write other addons' client convars.

### Examples

Reopen the menu on your page after an action:

```lua
Rhylib.Menus.lastPage = "convoy"
Rhylib.Menus.OpenPause()
```

Rebuild your page when data arrives:

```lua
net.Receive("convoy.list", function()
    Convoy.list = net.ReadTable()
    local p = Rhylib.Menus.pause
    if IsValid(p) and p.pageId == "convoy" then Rhylib.Menus.RefreshPause() end
end)
```

Let a model setting be picked from the spawn window (the Server settings page does this):

```lua
Rhylib.Menus.Spawn.PickModel(function(path)
    entry:SetText(path)
end, "Convoy truck model")
```

## Notes and gotchas

- **Load order**: addons load in folder name order, so anything before `rhylib_menus` alphabetically (admin, armoury, chat, datapad, droids, eod, gear, hud, inventory, jetpack, medical) runs its client files before `Rhylib.Menus` exists. Add pages, settings, controls, tabs and closers both at file load (for Lua refresh) and in an `InitPostEntity` hook. All the Add functions replace by id, so calling twice is safe.
- Every page is rebuilt from scratch each time it's shown; keep state you need outside the build function.
- Pages are all the same width (`min(ScrW − 440, 980)` at 1080p). A `wide` option was tried and dropped.
- A settings row is hidden while its convar doesn't exist; that's how rows for addons that aren't installed disappear.
- Key rows store `string.lower(input.GetKeyName(code))`; Esc cancels the rebind. Two Rhylib keys on one key, or a Rhylib key on Use/Reload/Jump/..., show in the KEY CLASHES box and turn the key button red.
- Esc order: model pick mode in the spawn window, then every registered closer (prompts, inventory, spawn window, scoreboard mouse, your windows), then the pause menu. Register a closer for any window that should close on Esc.
- The interaction wheel doesn't swallow E on a standing player (it opens after 0.25 s), so E + R and a plain tap still work. It won't open while you're lying, cuffed, in a medical action or drag, on a grapple rope, in the bacta tank, or with R held.
- Turning the Q menu off is client side only: players the server lets spawn can still use `gm_spawn` and the other sandbox commands from the console.
- Model checks on the client use `util.IsValidModel(m) or file.Exists(m, "GAME")`: `IsValidModel` alone is false for installed models nobody has loaded yet.
- The spawn window is hidden, not removed, between openings; it's rebuilt only when a new tab is added or the screen size changes. It moves sandbox tool settings panels into its own scroll and hands them back before a rebuild.
- The scoreboard removes every other `ScoreboardShow` / `ScoreboardHide` hook at InitPostEntity (and 5 s after a refresh) so other scoreboards can't win the race for Tab.
