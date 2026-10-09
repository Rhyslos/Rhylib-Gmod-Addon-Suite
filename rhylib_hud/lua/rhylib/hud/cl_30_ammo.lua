--[[
    Ammo counter.
      Third person: on a plate in the bottom-right corner.
      Helmet visor: a box on the lower-right cheek.
    Both are always the same size, whatever they hold.

    Rhylib weapons: shots in the magazine, spare magazines and (for cell
    weapons) the power cell charge. Other weapons: clip and reserve.
    The box always stays: holding nothing (or your guns stowed) it says
    "Unarmed"; weapons without ammo (physgun, tool gun) show their name.

    Rows, top to bottom:
        weapon name
        big shot count / magazine size        spare count + "magazines"
        Cell 73%                               1 spare      (cell weapons)
        cell bar                                             (cell weapons)
]]

local HUD = Rhylib.HUD

-- Fire mode text (long names shortened so they fit beside the gun name).
local SHORT = { overcharge = "OVERCH", lockon = "LOCK-ON" }
local function modeLabel(wep)
    if wep.HUDModeText then return wep:HUDModeText() end   -- (e.g. the grenade launcher's range)
    local m = wep:GetFireModeName()
    return SHORT[m] or string.upper(m)
end

local function drawContent(ply, wep, x, y, w, sizes)
    local s = HUD.Scale()
    local C = HUD.Colors
    local right = x + w
    local clip = wep:Clip1()
    local ammoType = wep:GetPrimaryAmmoType()

    -- Weapon name, and the fire mode on the right
    HUD.Text(wep:GetPrintName() or "", 16, x, y, C.dim)
    if wep.GetFireModeName then
        local safe = wep:GetSafety()
        local label = safe and "SAFE" or modeLabel(wep)
        HUD.Text(label, 14, right, y + math.floor(1 * s), safe and C.fuel or C.accent, TEXT_ALIGN_RIGHT)
    end
    y = y + sizes.name

    -- Shots / magazine size, spares on the right
    local maxClip = wep.GetMagSize and wep:GetMagSize() or wep:GetMaxClip1()
    local low = maxClip > 0 and clip / maxClip <= 0.2
    local clipCol = clip == 0 and C.bad or (low and C.fuel or C.text)
    local mid = y + sizes.count * 0.5
    if clip >= 0 then
        local cw = HUD.Text(tostring(clip), 36, x, mid, clipCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if maxClip > 0 then
            HUD.Text("/ " .. maxClip, 18, x + cw + math.floor(6 * s), mid + math.floor(6 * s), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    if wep.HUDSpare then
        -- (weapons with their own ammo, e.g. the grenade launcher: count, label)
        local reserve, label = wep:HUDSpare()
        HUD.Text(tostring(reserve), 24, right, y + math.floor(2 * s), reserve > 0 and C.text or C.bad, TEXT_ALIGN_RIGHT)
        label = string.lower(label or "") .. (reserve ~= 1 and label and "s" or "")
        HUD.Text(label, 13, right, y + sizes.count - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif wep.IsRhylib and wep.GetMag then
        -- Spares of the loaded type, then other types this gun takes.
        local mag = wep:GetMag()
        local reserve = mag and ply:GetAmmoCount(mag.ammo) or 0
        local label = mag and string.lower(mag.short) or ""
        if mag and mag.rounds > 1 then label = label .. (reserve == 1 and " mag" or " mags") end
        if mag and mag.rounds == 1 and reserve ~= 1 then label = label .. "s" end
        for _, id in ipairs(wep.Mags) do
            local other = Rhylib.Weapons.MagTypes[id]
            if other and other ~= mag then
                local n = ply:GetAmmoCount(other.ammo)
                if n > 0 then label = label .. " · +" .. n .. " " .. string.lower(other.short) end
            end
        end
        HUD.Text(tostring(reserve), 24, right, y + math.floor(2 * s), reserve > 0 and C.text or C.bad, TEXT_ALIGN_RIGHT)
        HUD.Text(label, 13, right, y + sizes.count - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif ammoType >= 0 then
        local reserve = ply:GetAmmoCount(ammoType)
        HUD.Text(tostring(reserve), 24, right, mid, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    y = y + sizes.count

    -- Power cell
    if sizes.cell > 0 then
        local charge = wep:GetCell()
        local lowCell = charge < (Rhylib.Config.Get("weapons", "lowCellThreshold") or 0.2)
        local cells = ply:GetAmmoCount("rhylib_cell")
        HUD.Text(string.format("Cell %d%%", math.ceil(charge * 100)), 14, x, y + math.floor(4 * s), lowCell and C.bad or C.dim)
        HUD.Text(cells .. " spare", 14, right, y + math.floor(4 * s), C.dim, TEXT_ALIGN_RIGHT)
        HUD.Bar(x, y + sizes.cell - math.floor(10 * s), w, math.floor(6 * s), charge, lowCell and C.bad or C.armor)
    end
end

local sizes = {}  -- reused every frame

--[[
    What the ammo readouts show, gathered once (for the visor layouts in
    cl_42_layouts.lua). Reuses one table.
      unarmed, noAmmo   holding nothing / a weapon without ammo
      name, mode, safe  weapon name, fire mode label, safety on
      clip, maxClip     shots in the magazine and its size
      magShort          loaded magazine type ("Med"), or nil
      spare             spare magazines of the loaded type (or reserve)
      others            "+2 small" for other types this gun takes, or nil
      cell, cells       power cell charge 0-1 and spares (cell weapons), or nil
]]
local info = {}
function HUD.AmmoInfo(ply, wep)
    for k in pairs(info) do info[k] = nil end
    local unarmed = not IsValid(wep) or wep.IsRhylibStowed
    info.unarmed = unarmed
    if unarmed then
        info.name = "Stowed"
        return info
    end
    info.name = wep:GetPrintName() or ""
    if wep:Clip1() < 0 and wep:GetPrimaryAmmoType() < 0 then
        info.noAmmo = true
        return info
    end
    if wep.GetFireModeName then
        info.safe = wep:GetSafety()
        info.mode = info.safe and "SAFE" or modeLabel(wep)
    end
    info.clip = math.max(wep:Clip1(), 0)
    info.maxClip = wep.GetMagSize and wep:GetMagSize() or wep:GetMaxClip1()
    if wep.IsRhylib and wep.GetMag then
        local mag = wep:GetMag()
        info.magShort = mag and mag.short or nil
        info.magRounds = mag and mag.rounds or nil
        info.spare = mag and ply:GetAmmoCount(mag.ammo) or 0
        local extra
        for _, id in ipairs(wep.Mags) do
            local other = Rhylib.Weapons.MagTypes[id]
            if other and other ~= mag then
                local n = ply:GetAmmoCount(other.ammo)
                if n > 0 then extra = (extra and extra .. " " or "") .. "+" .. n .. " " .. string.lower(other.short) end
            end
        end
        info.others = extra
        if wep.HUDSpare then
            info.spare, info.magShort = wep:HUDSpare()
            info.magRounds = 1   -- (one round each: "THERMALS", not "MAGS")
        end
        if wep.UsesCell then
            info.cell = wep:GetCell()
            info.cells = ply:GetAmmoCount("rhylib_cell")
        end
    elseif wep:GetPrimaryAmmoType() >= 0 then
        info.spare = ply:GetAmmoCount(wep:GetPrimaryAmmoType())
    end
    return info
end

-- The visor ammo box: always its full size (room for the cell rows), like
-- the third-person plate. The hotbar console lines up with it.
function HUD.VisorAmmoRect()
    local s = HUD.Scale()
    local pad = math.floor(12 * s)
    local w = math.floor(240 * s)
    local h = math.floor(20 * s) + math.floor(46 * s) + math.floor(34 * s) + pad * 2
    local mx, my = HUD.Margins("ammo")
    return ScrW() - w - mx, ScrH() - h - my, w, h
end

-- Holding nothing, or a weapon without ammo: just a name and a line.
local function drawEmpty(wep, x, y, w, sizes)
    local s = HUD.Scale()
    local C = HUD.Colors
    local unarmed = not IsValid(wep) or wep.IsRhylibStowed
    HUD.Text(unarmed and "Stowed" or (wep:GetPrintName() or ""), 16, x, y, C.dim)
    y = y + sizes.name
    HUD.Text(unarmed and "UNARMED" or "—", 30, x, y + sizes.count * 0.5, unarmed and C.dim or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if unarmed then
        HUD.Text("pick a hotbar slot", 13, x + w, y + sizes.count - math.floor(2 * s), C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.ammo", function()
    if HUD.Hidden() then return end
    -- The visor layouts f4/f5 draw the ammo with the hotbar (cl_42_layouts.lua).
    if HUD.LayoutDrawsAmmo and HUD.LayoutDrawsAmmo() then return end
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    local empty = not IsValid(wep) or wep.IsRhylibStowed or (wep:Clip1() < 0 and wep:GetPrimaryAmmoType() < 0)

    local s = HUD.Scale()
    sizes.name = math.floor(20 * s)
    sizes.count = math.floor(46 * s)
    sizes.cell = (not empty and wep.IsRhylib and wep.UsesCell) and math.floor(34 * s) or 0

    if HUD.VisorActive and HUD.VisorActive() then
        local pad = math.floor(12 * s)
        local x, y, w, h = HUD.VisorAmmoRect()
        HUD.Frame(x, y, w, h, { cut = math.floor(12 * s), cutLeft = true })
        if empty then drawEmpty(wep, x + pad, y + pad, w - pad * 2, sizes) else drawContent(ply, wep, x + pad, y + pad, w - pad * 2, sizes) end
    else
        local x, y, w = HUD.Plate(1)
        if empty then drawEmpty(wep, x, y, w, sizes) else drawContent(ply, wep, x, y, w, sizes) end
    end
end)
