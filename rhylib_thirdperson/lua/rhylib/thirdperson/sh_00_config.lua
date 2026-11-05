-- Third person settings (shared, so clients read the same mode).
-- Server setting (Server settings page, or Config.Set in a host file):
--   "choice" players switch with P (default), "third" everyone is always in
--   third person, "first" first person only.
Rhylib.Config.Describe("thirdperson", { name = "Third person", category = "Server & interface" })
Rhylib.Config.Register("thirdperson", "mode", "choice", "Third person: choice (players switch with P), third (always third person), first (first person only)")
Rhylib.Config.Meta("thirdperson", "mode", { name = "Camera mode", options = {
    { "choice", "Players choose (P switches)" }, { "third", "Always third person" }, { "first", "First person only" } } })

-- Limits on the players' own camera (Settings > Camera & freelook): what
-- they can pick is clamped to these, so nobody parks the camera high over
-- a wall or far behind. The camera is client side, so these keep honest
-- players inside the lines rather than lock anything down.
local function lim(key, default, desc, mn, mx)
    -- (a fresh meta table each: shared ones would all get the last range)
    Rhylib.Config.Register("thirdperson", key, default, desc, { section = "Player camera limits", min = mn, max = mx, unit = "units" })
end
lim("distMin", 40, "Closest a player may set the camera behind them (units)", 20, 62)
lim("distMax", 100, "Farthest a player may set the camera behind them (units; 62 = the default)", 62, 160)
lim("offsetMax", 34, "Furthest a player may set the camera out to the shoulder side (units; 20 = the default)", 0, 60)
lim("heightMin", -8, "Lowest a player may set the camera above or below eye height (units)", -30, 0)
lim("heightMax", 22, "Highest a player may set the camera above eye height (units; keep it low so nobody looks over walls)", 0, 48)
lim("aimDistMin", 18, "Closest a player may set the camera while aiming (units)", 10, 30)
lim("aimDistMax", 50, "Farthest a player may set the camera while aiming (units; 30 = the default)", 30, 90)

-- Old switch, still honoured: 0 = first person only.
CreateConVar("rhylib_thirdperson_allowed", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "Allow Rhy's over-the-shoulder third person (0/1)")
