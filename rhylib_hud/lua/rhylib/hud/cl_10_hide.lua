-- Hide the default HUD parts that Rhylib replaces (client).
-- HUDShouldDraw returns false for the names in HIDE; HUDDrawTargetID
-- returning false stops sandbox's look-at name text (cl_50_players.lua
-- draws our own).

local HIDE = {
    CHudHealth = true,
    CHudBattery = true,
    CHudAmmo = true,
    CHudSecondaryAmmo = true,
    CHudWeaponSelection = true,
    CHudQuickInfo = true,          -- HL2's yellow health/ammo brackets around the crosshair
    DarkRP_LocalPlayerHUD = true,  -- DarkRP health, job and money box
    DarkRP_EntityDisplay = true,   -- DarkRP names above heads
}

Rhylib.Hook.Add("HUDShouldDraw", "hud.hide", function(name)
    if HIDE[name] then return false end
end)

-- Sandbox's "name and health when you look at someone" text.
Rhylib.Hook.Add("HUDDrawTargetID", "hud.hide", function()
    return false
end)
