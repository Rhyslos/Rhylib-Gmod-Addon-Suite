--[[
    Health and armour on a plate in the bottom-left corner (third person).
    With DarkRP, also job and money. In the helmet visor the armour and
    health blocks replace this, so nothing is drawn here then.
]]

local HUD = Rhylib.HUD

local shown = { hp = 100, ar = 0 }  -- smoothed values so bars slide instead of jump

Rhylib.Hook.Add("HUDPaint", "hud.status", function()
    if HUD.Hidden() then return end
    if HUD.VisorActive and HUD.VisorActive() then return end
    local ply = LocalPlayer()
    local s = HUD.Scale()
    local C = HUD.Colors

    local hp, maxHp = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1)
    local simHp, simMax = HUD.SimHealth(ply)   -- (training gun in hand: sim health, yellow)
    if simHp then hp, maxHp = simHp, simMax end
    local ar = ply:Armor()
    local maxAr = ply.GetMaxArmor and ply:GetMaxArmor() or 100
    if maxAr <= 0 then maxAr = 100 end

    local ft = math.min(FrameTime() * 8, 1)
    shown.hp = Lerp(ft, shown.hp, hp)
    shown.ar = Lerp(ft, shown.ar, ar)

    local darkrp = DarkRP and ply.getDarkRPVar
    local rowH = math.floor(30 * s)
    local x, y, w = HUD.Plate(-1)

    local labelW = math.floor(48 * s)
    local barH = math.floor(10 * s)
    local barW = w - labelW

    local function row(value, frac, col, textCol)
        HUD.Text(tostring(value), 24, x, y + rowH * 0.5, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        HUD.Bar(x + labelW, y + math.floor((rowH - barH) * 0.5), barW, barH, frac, col)
        y = y + rowH
    end

    local low = hp / maxHp < 0.3
    local hc, hl = C.health, C.healthLow
    if simHp then hc, hl = C.sim, C.simLow end
    row(hp, shown.hp / maxHp, low and hl or hc, low and hl or C.text)
    if ar > 0 then row(ar, shown.ar / maxAr, C.armor, C.text) end

    if darkrp then
        local job = ply:getDarkRPVar("job") or team.GetName(ply:Team())
        local money = ply:getDarkRPVar("money") or 0
        local moneyText = DarkRP.formatMoney and DarkRP.formatMoney(money) or ("$" .. money)
        HUD.Text(job, 15, x, y + math.floor(3 * s), C.dim)
        HUD.Text(moneyText, 15, x + w, y + math.floor(3 * s), C.text, TEXT_ALIGN_RIGHT)
    end
end)
