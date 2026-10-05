--[[
    Low ammo warning under the crosshair (Rhylib guns): "LAST MAGAZINE"
    when no spare magazine the gun takes is left, "OUT OF AMMO" when the
    clip is empty too, "CELL LOW" / "CELL EMPTY" when the power cell is
    under 15% with no spare cell. Not with test ammo or the Open up order.
    Client convar rhylib_lowammo (Settings > HUD).
]]

local HUD = Rhylib.HUD

local cv = CreateClientConVar("rhylib_lowammo", "1", true, false, "Low ammo warning under the crosshair (0/1)")

local AMBER = Color(255, 190, 60)
local RED = Color(255, 80, 70)
local CELL_LOW = 0.15

-- text, colour (most urgent first), or nil
local function warning(ply, wep)
    if not (IsValid(wep) and wep.IsRhylib and istable(wep.Mags) and #wep.Mags > 0) or wep.ToolGun then return nil end
    if (wep.InfiniteAmmo and wep:InfiniteAmmo()) or (wep.NoAmmoUse and wep:NoAmmoUse()) then return nil end
    local W = Rhylib.Weapons
    local spare = 0
    for _, id in ipairs(wep.Mags) do
        local m = W and W.MagTypes and W.MagTypes[id]
        if m and m.ammo then spare = spare + ply:GetAmmoCount(m.ammo) end
    end
    local clip = wep:Clip1()
    local cellLeft, cells
    if wep.UsesCell and wep.GetCell then
        cellLeft = wep:GetCell()
        cells = ply:GetAmmoCount("rhylib_cell")
    end
    if spare <= 0 and clip <= 0 then return "OUT OF AMMO", RED end
    if cellLeft and cells <= 0 and cellLeft <= 0 then return "CELL EMPTY", RED end
    if spare <= 0 then return "LAST MAGAZINE", AMBER end
    if cellLeft and cells <= 0 and cellLeft < CELL_LOW then return "CELL LOW", AMBER end
    return nil
end
HUD.LowAmmo = warning

Rhylib.Hook.Add("HUDPaint", "hud.lowammo", function()
    if not cv:GetBool() or HUD.Hidden() then return end
    local ply = LocalPlayer()
    local G = Rhylib.Gear
    if G and G.Looking and G.Looking(ply) then return end   -- (looking through binoculars)
    local text, col = warning(ply, ply:GetActiveWeapon())
    if not text then return end
    local s = HUD.Scale()
    -- A slow pulse, quicker when it's urgent.
    local speed = col == RED and 6 or 3
    local a = 150 + 105 * (0.5 + 0.5 * math.sin(RealTime() * speed))
    draw.SimpleTextOutlined(text, Rhylib.UI.Font(15, 700), ScrW() * 0.5, ScrH() * 0.5 + math.floor(64 * s),
        ColorAlpha(col, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, a * 0.8))
end)

Rhylib.Hook.Add("InitPostEntity", "hud.lowammo.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("HUD", { id = "hud.lowammo", order = 25, title = "Low ammo warning",
        desc = "\"Last magazine\" / \"Cell low\" under the crosshair", kind = "toggle", convar = "rhylib_lowammo" })
end)
