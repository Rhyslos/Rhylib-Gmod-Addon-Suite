# rhylib_hud: HUD, helmet visor and damage feedback

Replaces Garry's Mod's health, armour, ammo and weapon selection HUD (and DarkRP's health/job box and names over heads). In first person, players look out through a clone helmet visor: armour (blue) and health (red) run along the cheeks as four bars each, the hotbar and ammo sit on the right cheek in one of two layouts, and the stamina bar follows the cheek edges down to the chin. In third person (or with the visor off) the same information is on two corner plates and a hotbar row. On top of that: name, health and armour of the player you look at, voice and typing icons over heads, damage direction markers, hit flashes, hit sounds, visor cracks from head hits, a low-health heartbeat, and a "last magazine" warning under the crosshair.

For server owners there is little to set: two ranges and the default first-person layout. Everything else is a per-player setting.

## Requirements

- Required: `rhylib_core`.
- Works better with:
  - `rhylib_inventory`: the fixed-slot hotbar (filled from the inventory window) and the f4/f5 visor layouts. Without it the hotbar is one box per weapon you hold, and the visor shows a separate ammo box.
  - `rhylib_weapons`: magazine types, power cells, fire modes and armour costs on the HUD; the near-miss whizz (its own convar, listed in the HUD settings).
  - `rhylib_stamina`: the stamina bar. Without it no bar is drawn.
  - `rhylib_menus`: the settings rows (Settings > Interface / Audio / Camera & motion).
  - `rhylib_training`: sim health in yellow while holding a training gun, sim hit markers.
  - `rhylib_gear`: helmet off and binoculars in weapon mode turn the visor off.
  - `rhylib_medical`: health as a percent with the simplified medical system; the low-health pulse stops while downed.
- No Workshop content. Sounds and materials are from HL2 / GMod.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_hud.lua` | shared | Loads the module through `Rhylib.LoadModule("hud")`. |
| `lua/rhylib/hud/sh_00_config.lua` | shared | `Rhylib.HUD` table, config keys, the list of first-person layouts, `HUD.ServerLayout` / `HUD.VisorLayout`. |
| `lua/rhylib/hud/sv_10_armor.lua` | server | Copies each player's armour into NW2Int `rhylib_armor` 4 times a second (only on change) so others can see it; turns off the engine's voice icons. |
| `lua/rhylib/hud/sv_20_layout.lua` | server | `rhylib_hud_layout` command: the server's default first-person layout, saved. |
| `lua/rhylib/hud/sv_30_damage.lua` | server | Sends every hit a player takes to them (`hud.dmg`), with direction and armour lost. `HUD.SendHit`. |
| `lua/rhylib/hud/cl_05_draw.lua` | client | Drawing helpers other addons use too: `HUD.Frame`, `HUD.Bar`, `HUD.Text`, `HUD.Plate`, `HUD.Margins`, colours and the house style. |
| `lua/rhylib/hud/cl_10_hide.lua` | client | Hides the default HUD parts and DarkRP's own. |
| `lua/rhylib/hud/cl_20_status.lua` | client | Third person: health and armour (and DarkRP job and money) on the bottom-left plate. |
| `lua/rhylib/hud/cl_30_ammo.lua` | client | Ammo counter (third-person plate, or a box on the visor cheek); `HUD.AmmoInfo`. |
| `lua/rhylib/hud/cl_40_hotbar.lua` | client | Hotbar and weapon switching (number keys, wheel, last weapon). |
| `lua/rhylib/hud/cl_42_layouts.lua` | client | The visor layouts f4 and f5 (hotbar and ammo together on the right cheek). |
| `lua/rhylib/hud/cl_45_stamina.lua` | client | Stamina bar (on top of the hotbar, or two strips along the visor cheeks). |
| `lua/rhylib/hud/cl_50_players.lua` | client | Name card of the player you look at; voice and typing icons over heads. |
| `lua/rhylib/hud/cl_60_visor.lua` | client | The helmet visor shell, armour and health bars, and the cheek helpers (`HUD.VisorActive`, `HUD.VisorCheekY`, `HUD.VisorStrip`...). |
| `lua/rhylib/hud/cl_70_damage.lua` | client | Damage feedback: markers, flash, shake, sounds, ear ringing, low-health pulse and heartbeat, visor cracks. |
| `lua/rhylib/hud/cl_75_lowammo.lua` | client | "LAST MAGAZINE" / "OUT OF AMMO" / "CELL LOW" / "CELL EMPTY" under the crosshair. |

## For server owners

### Settings

Config module `"hud"`:

| Key | Default | What it does |
|---|---|---|
| `targetRange` | `700` | How close you must be to see a player's name and health when looking at them (units). |
| `iconRange` | `1500` | How far away speaking and typing icons are drawn (units). |

Change them on the Staff > Server settings page (Server & interface > HUD), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("hud", "targetRange", 500)
```

### Default first-person layout

| Name | What it looks like |
|---|---|
| `f5` (default) | Curve tiles over a wide ammo plate. Slots 1-4 are tiles whose tops follow the cheek, the overflow and backpack slots sit in a strip under them, the ammo plate is below. |
| `f4` | Ammo strip on an even hotbar row: a row of tiles, a line of round ticks on top, one row of weapon info above. |
| `thirdperson` | The third-person HUD in first person: no helmet visor. |

The visor layouts need `rhylib_inventory`. Players can pick their own in Settings > Interface ("First-person HUD"); "Server default" uses yours.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_hud_layout` | anyone | Prints the server's default layout and the choices. |
| `rhylib_hud_layout <name>` | `rhylib.hud.layout` (default admin), or the server console | Sets the default layout. Saved in Data `"hud"` / `"layout"`, survives restarts. |

The Staff > Commands page has a row for it too (rhylib_menus).

## For players (short)

- Number keys pick a hotbar slot. Picking the slot you're holding, or an empty one, puts your gun away. The mouse wheel steps through everything on the bar; whatever key you have bound to `lastinv` swaps back to the last weapon. The overflow slot (things you hold that aren't inventory items, like the physgun) cycles on repeated presses.
- The hotbar is bright right after switching and fades after a moment.
- Look at a player to see their name, job, health and armour.

Client settings (Settings pages, rhylib_menus):

| Convar | Default | What it does |
|---|---|---|
| `rhylib_hud_firstperson` | `""` | Your first-person layout: `f5`, `f4`, `thirdperson`, or empty for the server default. |
| `rhylib_hud_visor` | `1` | Helmet visor in first person (console only, no settings row). |
| `rhylib_hud_hotbar_fade` | `1` | Fade the hotbar when you're not switching. |
| `rhylib_visorbrow_edge` / `_centre` / `_curve` | `0.015` / `0.045` / `1` | Visor brow shape (Settings > Interface, behind "Adjust the visor brow"). |
| `rhylib_lowammo` | `1` | Low ammo warning under the crosshair. |
| `rhylib_dmg_markers` | `1` | Damage direction arcs around the crosshair. |
| `rhylib_dmg_flash` | `1` | Screen edge flash when hit. |
| `rhylib_dmg_shake` | `1` | Short camera shake when hit (your aim doesn't move). |
| `rhylib_dmg_lowhp` | `1` | Red pulse and heartbeat under 30% health. |
| `rhylib_dmg_volume` | `1` | Volume of hit sounds, beeps and the heartbeat (0 = silent). |
| `rhylib_dmg_ring` | `1` | Ear ringing after big explosions. |
| `rhylib_dmg_cracks` | `1` | Visor cracks from head hits (first person). |

## For developers

The module table is `Rhylib.HUD` (`HUD` below). Most functions are client only; other addons should always check they exist (`if HUD and HUD.VisorActive then`), since the HUD is a separate Workshop item.

### Public functions

| Function | Realm | What it does |
|---|---|---|
| `HUD.ServerLayout()` → name | shared | The server's default layout (Global2String `rhylib_hud_layout`). |
| `HUD.VisorLayout()` → name | shared | The layout in use: the player's own choice, else the server's. |
| `HUD.SendHit(ply, amount, armour, from, flags)` | server | Tells a player's HUD they were hit. `from` = world position or nil (no direction), `flags` = `HUD.DMG_SIM / DMG_BLAST / DMG_NODIR / DMG_HEAD` bits. Real damage is sent automatically; use this for damage the engine never sees. |
| `HUD.VisorActive()` → bool | client | The visor is showing (first person, alive, helmet on, setting on, not "thirdperson"...). Ask this to pick a visor or a third-person look. |
| `HUD.Hidden()` → bool | client | The HUD shouldn't draw (dead, camera out). |
| `HUD.Scale()` → number | client | `ScrH() / 1080`. Write sizes for 1080p and multiply. |
| `HUD.Frame(x, y, w, h, opts)` → contentY | client | A plate in the house style. opts: `alpha`, `title`, `rule`, `cut`, `cutH`, `cutLeft`, `bg`, `ticks`. |
| `HUD.Bar(x, y, w, h, frac, col, alpha)` | client | A flat bar with a dark track. |
| `HUD.Text(text, size, x, y, col, ax, ay, alpha)` → w, h | client | Text in the Rhylib font. |
| `HUD.Panel(x, y, w, h, alpha)` | client | Plain plate (no title, no ticks). |
| `HUD.Plate(side)` → x, y, w, h | client | Draws a third-person corner plate (`-1` left, `1` right) and returns its content box. |
| `HUD.Margins(kind)` → side, bottom | client | Distance from the screen edges for `"ammo"`, `"hotbar"` or `"status"` (smaller in the visor). |
| `HUD.SimHealth(ply)` → hp, max or nil | client | Sim health while holding a training gun. |
| `HUD.AmmoInfo(ply, wep)` → table | client | What the ammo readouts show (name, mode, clip, spare, cell...). Reuses one table. |
| `HUD.LowAmmo(ply, wep)` → text, colour or nil | client | The low ammo warning for that weapon. |
| `HUD.AddCrack(from)` | client | Adds a visor crack toward the side `from` is on. |
| `HUD.VisorCheekX(y, side)` / `HUD.VisorCheekY(x, side)` | client | Where the cheek edge is (side `-1` left, `1` right). |
| `HUD.VisorStrip(side, fx0, fx1, offset, thick, steps)` → strip | client | Quads for a strip along a cheek edge (`strip.quads`, `strip.outer`, `strip.inner`). Cached, read only. |
| `HUD.VisorShellTris()` → tris or nil | client | The visor shell's triangles (for masking), while the visor shows. |
| `HUD.OpticsWeaponMode()` → bool | client | Binoculars are in weapon mode (rhylib_gear). |
| `HUD.VisorAmmoRect()` → x, y, w, h | client | The visor ammo box. |
| `HUD.LayoutDrawsAmmo()` → bool | client | A visor layout is drawing the ammo (the ammo box then skips). |
| `HUD.DrawVisorLayout(name, entries, active, alpha, s)` | client | Draws layout f5 or f4 (called by the hotbar). |

Shared values: `HUD.Colors` (health, armor, sim, accent, text, dim, bad...), `HUD.Style` (plate colours), `HUD.Layouts`, `HUD.LAYOUT_ORDER`, `HUD.DEFAULT_LAYOUT`, `HUD.HotbarRect` (where the hotbar was drawn and on which frame), `HUD.VISOR_BAR_FROM / _TO / _OFFSET / _THICK` (where the armour and health bars sit, as screen shares), `HUD.PLATE_W / PLATE_H`.

Weapon fields the ammo readout asks for (optional): `SWEP:HUDModeText()` (text instead of the fire mode name), `SWEP:HUDSpare()` → count, label (instead of spare magazines; the grenade launcher counts thermals).

### Hooks

Fired by this addon: none.

Listened to (all through `Rhylib.Hook.Add`): `HUDPaint` (visor at -10, stamina at -9, the rest at 0), `HUDShouldDraw`, `HUDDrawTargetID`, `PlayerBindPress` (hotbar keys), `PostDrawTranslucentRenderables` (head icons), `PostEntityTakeDamage` (server: armour cost at -1001, the hit report at 0), `PlayerDisconnected`, `Initialize`, `InitPostEntity` (settings rows).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `hud.dmg` | server → the player hit (Rhylib.Net batch, flushed once a tick) | per hit: health lost (UInt 8), armour lost (UInt 8), flags (UInt 4: SIM 1, BLAST 2, NODIR 4, HEAD 8), source position (vector, unless NODIR) | Damage feedback. |

Networked values: NW2Int `rhylib_armor` on every player (their armour, for the name card), Global2String `rhylib_hud_layout` (the default layout).

### Saved data

| Data module / key | What's stored |
|---|---|
| `"hud"` / `"layout"` | The server's default first-person layout name. |

### Examples

Report a hit the engine never sees (here a scripted trap) so the player gets a marker and a flash (server):

```lua
local HUD = Rhylib.HUD
if HUD and HUD.SendHit then
    HUD.SendHit(victim, 25, 0, trap:WorldSpaceCenter(), HUD.DMG_BLAST)
end
```

Draw your own plate in the house style, placed for the visor or third person:

```lua
Rhylib.Hook.Add("HUDPaint", "myaddon.plate", function()
    local HUD = Rhylib.HUD
    if not (HUD and HUD.Frame) or HUD.Hidden() then return end
    local s = HUD.Scale()
    local visor = HUD.VisorActive and HUD.VisorActive()
    local y = visor and ScrH() * 0.2 or ScrH() * 0.3
    local top = HUD.Frame(24 * s, y, 220 * s, 70 * s, { title = "Objective" })
    HUD.Text("Hold the bridge", 15, 32 * s, top + 8 * s, HUD.Colors.text)
end)
```

Sit something along the left cheek, just under the armour bars (what the radio meter does):

```lua
local HUD = Rhylib.HUD
if HUD.VisorActive() then
    local strip = HUD.VisorStrip(-1, HUD.VISOR_BAR_TO + 0.006, 0.4, HUD.VISOR_BAR_OFFSET, HUD.VISOR_BAR_THICK, 28)
    draw.NoTexture()
    surface.SetTexture(0)
    surface.SetDrawColor(255, 255, 255, 40)
    for _, q in ipairs(strip.quads) do surface.DrawPoly(q) end
end
```

Show the same low ammo text in your own HUD element:

```lua
local HUD = Rhylib.HUD
local ply = LocalPlayer()
local text, col = HUD.LowAmmo(ply, ply:GetActiveWeapon())
if text then draw.SimpleText(text, Rhylib.UI.Font(14, 700), 20, 20, col) end
```

## Notes and gotchas

- Damage feedback for real hits reads rhylib_weapons' armour record at `PostEntityTakeDamage` -1001, just before armour puts the value back at -1000. A hook between those two priorities that changes armour will confuse the "armour lost" number.
- Any `surface.DrawPoly` HUD code that runs after textured draws (portraits, crosshair, gradients) should call `draw.NoTexture()` and `surface.SetTexture(0)` first, or the fill comes out much too dark. `surface.DrawPoly` only draws clockwise polygons; the helpers here wind them for you.
- `HUD.HotbarRect` is written by the hotbar, which draws after the stamina bar; the stamina bar uses the rect from the frame before (it checks `frame` so a stale one isn't used).
- The visor shell is built once per screen size and brow setting; changing resolution or the brow sliders rebuilds it.
- The name card draws the armour bar against 100.
- The console hotbar plate in `cl_40_hotbar.lua` (`drawConsole`) is only a fallback if `cl_42_layouts.lua` is missing; the "console" layout itself is gone.
- `rhylib_hud_layout` saves its choice in Data; a `Rhylib.Config.Set` can't set it (it isn't a config key).
