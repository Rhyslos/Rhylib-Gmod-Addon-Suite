# rhylib_thirdperson: Third person

An over-the-shoulder third-person camera. P switches it on and off, N swaps the shoulder, holding right mouse (aiming) pulls the camera in. Shots still land on the crosshair: the camera traces where the crosshair points and turns your real aim toward that spot, so bolts, spread and lag compensation work exactly like first person. If cover is between your gun and the crosshair, a small red X shows where the shot will really hit. Server owners can force everyone into third person or first person only.

## Requirements

- Required: rhylib_core.
- Recommended: rhylib_menus (settings rows and key rebinding in the pause menu), rhylib_weapons (its crosshair is drawn in third person).
- No Workshop content.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_thirdperson.lua` | shared | Loads the module. |
| `lua/rhylib/thirdperson/sh_00_config.lua` | shared | The `mode` setting and the old `rhylib_thirdperson_allowed` convar. |
| `lua/rhylib/thirdperson/cl_10_camera.lua` | client | Camera, mouse, aim correction, HUD marker, keys; `Rhylib.ThirdPerson`. |

## For server owners

### Settings

Config module `thirdperson`:

| Key | Default | What it does |
|---|---|---|
| `mode` | `"choice"` | Third person: choice (players switch with P), third (always third person), first (first person only). |

```lua
Rhylib.Config.Set("thirdperson", "mode", "first")
```

Or Staff > Server settings (type `choice`, `third` or `first`). The old server convar `rhylib_thirdperson_allowed 0` (replicated, default 1) still means first person only.

### Commands and permissions

None for staff.

## For players (short)

| Key / command | What it does |
|---|---|
| P (`rhylib_thirdperson_key`) | Toggle third person (in "choice" mode). |
| N (`rhylib_thirdperson_swapkey`) | Swap shoulder. |
| Right mouse | Aim: camera comes closer. |
| `rhylib_thirdperson 0/1` | Third person off/on. |
| `rhylib_thirdperson_side 1/-1` | Right / left shoulder. |
| `rhylib_thirdperson_crouchup` (14) | How far the camera rises while crouching, so it clears the arms. |
| `rhylib_thirdperson_crouchmove` (0.5) | While moving crouched, how far the camera rises back toward standing height (0-1). |
| `rhylib_thirdperson_toggle`, `rhylib_thirdperson_swap` | Console commands for binds. |

Third person pauses while you look through binoculars (rhylib_gear), in a vehicle, dead or spectating. In noclip the body simply looks where the camera looks.

## For developers

### Public functions (`Rhylib.ThirdPerson`, client)

| Function / field | Returns | Description |
|---|---|---|
| `Mode()` | string | `"choice"`, `"third"` or `"first"`. |
| `Wanted()` | bool | Third person wanted (mode, else the player's switch). |
| `Active()` | bool | In use right now (wanted, alive, not in a vehicle/spectating/optics). |
| `Toggle()`, `SwapShoulder()` | — | What the keys do. |
| `camAng` | Angle | Where the camera looks (driven by the mouse). Turn it to kick the view. |
| `camPos`, `aimPoint` | Vector | Last camera position; world point under the crosshair. |
| `aimFrac`, `side`, `camHeight` | number | Smoothed aim blend, shoulder (−1..1), camera height. |

```lua
-- view recoil that works in both views
local TP = Rhylib.ThirdPerson
if TP and TP.Active() and TP.camAng then
    TP.camAng.p = TP.camAng.p - kick
else
    ply:SetEyeAngles(ply:EyeAngles() - Angle(kick, 0, 0))
end
```

### How the aim works

- `InputMouseApply` (priority 10) turns `camAng` instead of the player.
- `CreateMove` traces from the camera through the crosshair (starting level with the player, so walls behind the shoulder don't count), then sets the command's view angles from the eyes toward that point. Movement keys are turned so you still walk relative to the camera (exact for walking; swimming solves the 3D case).
- `CalcView` places the camera behind the shoulder, pulled in by a hull trace from the eyes so it never goes through walls.
- Switching off makes you face where the camera looked.

### Hooks

Listens to (client): `InputMouseApply`, `CreateMove`, `CalcView` ("thirdperson.camera", priority 0), `PreDrawViewModel` (hides the first-person gun), `HUDPaint` (Rhylib crosshair + blocked-shot X), `Think` (keys). Fires none. rhylib_core's body camera (CalcView -50) steps aside while `Wanted()` is true.

### Network messages / saved data

None. Everything is client side; the server only sees normal eye angles.

### Examples

Force third person while a player is in a vehicle-like contraption of yours (client):

```lua
local TP = Rhylib.ThirdPerson
if TP and not TP.Active() and TP.Mode() == "choice" then TP.Toggle() end
```

## Notes and gotchas

- `mode` is read every frame, so a change on the Server settings page applies at once.
- Weapons that change mouse sensitivity (`SWEP:AdjustMouseSensitivity`) are respected.
- Things that turn the player's eye angles directly have no effect while third person is active (the next CreateMove overwrites them); turn `camAng` instead.
