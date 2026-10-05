--[[
    Reload input and the radial reload menu (client only).

    Tap R:  reload the best magazine (same type if you have one).
    E + R:  next fire mode.   Shift + E + R: safety on/off.
    Hold R: the radial menu opens and the view stops turning. Move the
            mouse toward an option and let go of R to pick it.
            Let go in the middle to cancel.

    The client only asks; the server checks the pouch and runs the reload.
]]

local W = Rhylib.Weapons
local UI = Rhylib.UI

local R = {
    down = false,
    downTime = 0,
    open = false,
    cx = 0,              -- virtual cursor, moved by the mouse while open
    cy = 0,
    selected = nil,
}
W.Radial = R

local DEADZONE = 40      -- px at 1080p; inside this, release cancels
local CURSOR_MAX = 140
local RING = 150         -- distance of the options from the centre

local function activeRhylibWeapon()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return nil end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.IsRhylib and not wep.ToolGun then return wep end   -- (the toolgun's R opens its list)
    return nil
end

-- Options for the current weapon, laid out around the ring: magazine
-- types fanned out on the left, the power cell on the right.
-- Angles are screen space: 180 = left, 0 = right, 90 = down.
-- req is what gets sent (see W.RELOAD_REQ_* in sh_00_config.lua).
local optionCache = { class = nil, list = {} }

local function options(wep)
    local ply = LocalPlayer()
    if optionCache.class ~= wep:GetClass() then
        local list = {}
        local n = #wep.Mags
        for i, id in ipairs(wep.Mags) do
            local m = W.MagTypes[id]
            if m then
                local spread = n > 1 and (i - 1) / (n - 1) - 0.5 or 0
                list[#list + 1] = { req = m.index, mag = m, label = m.name, angle = 180 - spread * 70 }
            end
        end
        if wep.UsesCell then
            list[#list + 1] = { req = W.RELOAD_REQ_CELL, label = "Power cell", ammo = "rhylib_cell", angle = 0 }
        end
        optionCache.class, optionCache.list = wep:GetClass(), list
    end

    local list = optionCache.list
    local loaded = wep.GetMagType and wep:GetMagType() or 0
    for _, opt in ipairs(list) do
        opt.count = ply:GetAmmoCount(opt.mag and opt.mag.ammo or opt.ammo)
        opt.loaded = opt.mag and opt.mag.index == loaded
    end
    return list
end

local function sendReload(req)
    Rhylib.Net.Start("wep.reload")
    net.WriteUInt(req, W.RELOAD_REQ_BITS)
    net.SendToServer()
    -- The server starts the reload: stop predicting shots until its reload
    -- state arrives or about a round trip passes (SWEP:CanPrimaryAttack).
    -- (a tap with a full clip usually does nothing, so it doesn't hold)
    local wep = activeRhylibWeapon()
    if not wep then return end
    if req == 0 and wep.GetMagSize and wep:Clip1() >= wep:GetMagSize() then return end
    -- (nothing to load: the server refuses, so don't hold)
    if not (wep.InfiniteAmmo and wep:InfiniteAmmo()) then
        local any = false
        for _, opt in ipairs(options(wep)) do
            if opt.count > 0 and (opt.req == req or (req == 0 and opt.mag)) then any = true break end
        end
        if not any then return end
    end
    local now = CurTime()
    wep.rhylibReloadFrom = now
    wep.rhylibReloadHold = now + LocalPlayer():Ping() / 1000 + 0.3
end

local function reset()
    R.down = false
    R.open = false
    R.selected = nil
    R.cx, R.cy = 0, 0
end

local function reloadKeyHeld()
    local key = input.LookupBinding("+reload")
    local code = key and input.GetKeyCode(key)
    return code and code > 0 and input.IsKeyDown(code)
end

-- Catch R before the default reload runs.
Rhylib.Hook.Add("PlayerBindPress", "weapons.reload", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+reload", 1, true) then return end
    -- R rotates items while the inventory is open.
    if Rhylib.Inventory and IsValid(Rhylib.Inventory.panel) then return true end
    if not activeRhylibWeapon() then return end

    -- E + R: fire mode. Shift + E + R: safety.
    if ply:KeyDown(IN_USE) then
        Rhylib.Net.Start("wep.mode")
        net.WriteBool(ply:KeyDown(IN_SPEED))
        net.SendToServer()
        return true
    end
    R.down = true
    R.downTime = RealTime()
    return true
end)

Rhylib.Hook.Add("Think", "weapons.reload", function()
    if not R.down then return end

    local wep = activeRhylibWeapon()
    if not wep then
        reset()
        return
    end

    if not reloadKeyHeld() then
        if R.open then
            if R.selected then sendReload(R.selected) end
        else
            sendReload(0)  -- a tap reloads the best magazine
        end
        reset()
        return
    end

    if not R.open and RealTime() - R.downTime >= Rhylib.Config.Get("weapons", "reloadHoldTime") then
        R.open = true
        R.cx, R.cy = 0, 0
    end
end)

-- While the menu is open, the mouse moves the menu cursor instead of the view.
Rhylib.Hook.Add("InputMouseApply", "weapons.reload", function(cmd, x, y)
    if not R.open then return end
    local s = ScrH() / 1080
    R.cx = R.cx + x * 0.6
    R.cy = R.cy + y * 0.6
    local len = math.sqrt(R.cx * R.cx + R.cy * R.cy)
    local max = CURSOR_MAX * s
    if len > max then
        R.cx, R.cy = R.cx / len * max, R.cy / len * max
    end
    return true
end)

local function pickOption(list, s)
    local len = math.sqrt(R.cx * R.cx + R.cy * R.cy)
    if len < DEADZONE * s then return nil end
    local ang = math.deg(math.atan2(R.cy, R.cx))
    local best, bestD = nil, math.huge
    for _, opt in ipairs(list) do
        local d = math.abs(math.NormalizeAngle(ang - opt.angle))
        if d < bestD then
            best, bestD = opt, d
        end
    end
    return best
end

local COL_DEADZONE = Color(0, 0, 0, 120)
local COL_PICK = Color(60, 72, 88, 235)

Rhylib.Hook.Add("HUDPaint", "weapons.reload", function()
    if not R.open then return end
    local wep = activeRhylibWeapon()
    if not wep then return end

    local s = ScrH() / 1080
    local cx, cy = ScrW() * 0.5, ScrH() * 0.5
    local list = options(wep)
    local pick = pickOption(list, s)
    R.selected = pick and pick.count > 0 and pick.req or nil

    -- Centre: cancel zone.
    local dz = DEADZONE * s
    draw.RoundedBox(dz, cx - dz, cy - dz, dz * 2, dz * 2, COL_DEADZONE)
    draw.SimpleText(pick and "" or "Cancel", UI.Font(15), cx, cy, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local w, h = 200 * s, 64 * s
    for _, opt in ipairs(list) do
        local a = math.rad(opt.angle)
        local ox, oy = cx + math.cos(a) * RING * s, cy + math.sin(a) * RING * s
        local isPick = pick == opt
        local empty = opt.count <= 0

        -- House-style plate (rhylib_hud) with a coloured stripe; plain box without the HUD.
        local bx, by = ox - w * 0.5, oy - h * 0.5
        local HUD = Rhylib.HUD
        if HUD and HUD.Frame then
            HUD.Frame(bx, by, w, h, { ticks = isPick })
        else
            draw.RoundedBox(0, bx, by, w, h, UI.Colors.bg)
        end
        if isPick then
            surface.SetDrawColor(COL_PICK)
            surface.DrawRect(bx + 1, by + 1, w - 2, h - 2)
        end
        surface.SetDrawColor(empty and UI.Colors.bad or (isPick and UI.Colors.accent or UI.Colors.border))
        surface.DrawRect(bx + 1, by + 1, 3, h - 2)

        local textCol = empty and UI.Colors.textDim or UI.Colors.text
        draw.SimpleText(opt.label, UI.Font(20), ox, oy - 10 * s, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local sub = empty and "None left" or (opt.count .. " spare")
        if opt.mag and opt.mag.rounds > 1 then sub = opt.mag.rounds .. " rounds · " .. sub end
        if opt.loaded then sub = sub .. " · loaded" end
        draw.SimpleText(sub, UI.Font(15), ox, oy + 13 * s, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Menu cursor.
    draw.RoundedBox(4 * s, cx + R.cx - 4 * s, cy + R.cy - 4 * s, 8 * s, 8 * s, UI.Colors.text)
end)
