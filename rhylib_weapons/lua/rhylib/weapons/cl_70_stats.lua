--[[
    Weapon stats (client): hold C (+menu_context) with a Rhylib gun in your
    hands to see its numbers, with your skills applied. The context menu
    stays as it was with anything else in your hands (the toolgun too).
    Drawn in HUDPaint while the key is held; nothing is networked.
]]

local W = Rhylib.Weapons
local UI = Rhylib.UI

local stats = { open = false, code = nil }

local MODE_NAMES = {
    semi = "Semi", auto = "Auto", burst = "Burst", dual = "Dual", sidearm = "Sidearm",
    stun = "Stun", grapple = "Grapple", overcharge = "Overcharge",
}

local function gun(me)
    local w = IsValid(me) and me:GetActiveWeapon()
    if IsValid(w) and w.IsRhylib and not w.ToolGun and w.Mags and #w.Mags > 0 then return w end
end

-- C with a gun: show the stats instead of the context menu.
Rhylib.Hook.Add("ContextMenuOpen", "weapons.stats", function()
    local me = LocalPlayer()
    if not gun(me) then return end
    local key = input.LookupBinding("+menu_context", true)
    stats.code = key and input.GetKeyCode(key) or KEY_C
    stats.open = true
    return false
end, -50)

local function held()
    return stats.code and stats.code > 0 and input.IsButtonDown(stats.code)
end

-- Rows: { label, text, bar 0-1 or nil }
local function build(w, me)
    local rows = {}
    local K = Rhylib.Skills
    local function add(label, text, bar) rows[#rows + 1] = { label, text, bar } end

    local pellets = w.Pellets or 1
    local dmg = (w.Damage or 0) * (w.GetCellDamageMult and w:GetCellDamageMult() or 1)
    if K and K.ModeDamageMult then dmg = dmg * K.ModeDamageMult(me, w) end   -- (Overcharge)
    local rpm = w.CurrentFireRate and w:CurrentFireRate() or w.FireRate or 0
    local mode = w.GetFireModeName and w:GetFireModeName() or "semi"
    add("Damage", pellets > 1 and (math.Round(dmg) .. " × " .. pellets .. " pellets") or tostring(math.Round(dmg)),
        math.Clamp(dmg * pellets / 150, 0, 1))
    add("Fire rate", math.Round(rpm) .. " rpm", math.Clamp(rpm / 900, 0, 1))
    if mode ~= "stun" and mode ~= "grapple" then
        add("Damage / second", tostring(math.Round(dmg * pellets * rpm / 60)), math.Clamp(dmg * pellets * rpm / 60 / 450, 0, 1))
    end
    local Cfg = Rhylib.Config
    add("Head / limbs", "×" .. (Cfg.Get("weapons", "headMult") or 2) .. "  /  ×" .. (Cfg.Get("weapons", "limbMult") or 0.75))

    -- Accuracy: resting cone, hip and aimed (smaller is better).
    local sp = w.Spread or {}
    local sm = W.Spread and W.Spread.SkillMult and W.Spread.SkillMult(w) or 1
    local hip, aim = (sp.hip or 0) * sm, (sp.aim or 0) * sm
    add("Spread (hip)", string.format("%.2f°", hip), 1 - math.Clamp(hip / 3, 0, 1))
    if not w.NoAim then add("Spread (aimed)", string.format("%.2f°", aim), 1 - math.Clamp(aim / 3, 0, 1)) end
    local rc = w.Recoil or {}
    local rm = (K and K.RecoilMult and K.RecoilMult(me, w) or 1) * (Cfg.Get("weapons", "recoilMult") or 1)
    local kick = (rc.up or 0) * rm
    add("Kick", string.format("%.2f", kick), 1 - math.Clamp(kick / 1.5, 0, 1))
    local speed = (w.BoltSpeed or 7000) * (w.Explosive and 1 or (Cfg.Get("weapons", "boltSpeedMult") or 1))
    add("Bolt speed", math.Round(speed * 0.019) .. " m/s", math.Clamp(speed / 20000, 0, 1))
    local cap = W.BoltRange and W.BoltRange() or 0
    if cap > 0 and not w.Scope and not w.Explosive then add("Reach", math.Round(cap * 0.019) .. " m") end

    -- Ammo.
    local m = w.GetMag and w:GetMag()
    if m then add("Loaded", m.name .. ": " .. w:Clip1() .. " / " .. w:GetMagSize()) end
    local takes = {}
    for _, id in ipairs(w.Mags or {}) do
        local mt = W.MagTypes[id]
        if mt then
            local ok = not (K and K.MagAllowed) or K.MagAllowed(me, w, id)
            takes[#takes + 1] = mt.short .. " " .. (w.MagRounds and w:MagRounds(mt) or mt.rounds) .. (ok and "" or " (skill)")
        end
    end
    if #takes > 0 then add("Magazines", table.concat(takes, ", ")) end
    if w.UsesCell then
        local shots = (w.CellShots or 0) * (K and K.CellMult and K.CellMult(me) or 1)
        if K and K.CellDrainMult then shots = shots / K.CellDrainMult(me, w) end
        add("Power cell", math.Round(shots) .. " shots, " .. math.Round((w.GetCell and w:GetCell() or 0) * 100) .. "% left")
    end
    if w.ReloadTime then add("Reload", string.format("%.1f s", w.ReloadTime)) end

    -- Fire modes you can use.
    local modes = {}
    for i, name in ipairs(w.FireModes or {}) do
        if not w.ModeAllowed or w:ModeAllowed(i) then
            local n = MODE_NAMES[name] or name
            modes[#modes + 1] = name == mode and ("[" .. n .. "]") or n
        end
    end
    if #modes > 0 then add("Fire modes", table.concat(modes, "  ")) end

    -- Carrying.
    local Items = Rhylib.Items
    local def = Items and Items.defs and Items.defs[w:GetClass()]
    if def then add("Size / weight", def.w .. "×" .. def.h .. "  ·  " .. (def.weight or 0) .. " kg") end
    return rows
end

local BAR = Color(133, 183, 235)

Rhylib.Hook.Add("HUDPaint", "weapons.stats", function()
    if not stats.open then return end
    local me = LocalPlayer()
    local w = gun(me)
    if not (w and held() and me:Alive()) then
        stats.open = false
        return
    end
    local rows = build(w, me)
    local s = ScrH() / 1080
    local pw = math.floor(380 * s)
    local rh = math.floor(26 * s)
    local head = math.floor(52 * s)
    local ph = head + #rows * rh + math.floor(16 * s)
    local x = ScrW() - pw - math.floor(40 * s)
    local y = math.floor((ScrH() - ph) * 0.45)
    local C = UI.Colors
    local HUD = Rhylib.HUD
    if HUD and HUD.Frame then
        HUD.Frame(x, y, pw, ph)
    else
        draw.RoundedBox(0, x, y, pw, ph, C.bg)
    end
    local pad = math.floor(14 * s)
    draw.SimpleText(string.upper(w.PrintName or w:GetClass()), UI.Font(20, 700), x + pad, y + math.floor(12 * s), C.text)
    draw.SimpleText("Weapon stats · with your skills", UI.Font(12), x + pad, y + math.floor(34 * s), C.textDim)
    local labelW = math.floor(130 * s)
    local barW = math.floor(70 * s)
    draw.NoTexture()
    for i, r in ipairs(rows) do
        local ry = y + head + (i - 1) * rh
        draw.SimpleText(r[1], UI.Font(13), x + pad, ry + rh * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tx = x + pad + labelW
        if r[3] then
            local bx, by, bh = x + pw - pad - barW, ry + math.floor(rh * 0.5 - 3 * s), math.max(4, math.floor(6 * s))
            surface.SetDrawColor(255, 255, 255, 25)
            surface.DrawRect(bx, by, barW, bh)
            local acc = C.accent or BAR
            surface.SetDrawColor(acc.r, acc.g, acc.b, 220)
            surface.DrawRect(bx, by, math.floor(barW * r[3]), bh)
        end
        local maxW = pw - pad * 2 - labelW - (r[3] and barW + math.floor(8 * s) or 0)
        local text = r[2]
        local K = Rhylib.Menus and Rhylib.Menus.Kit
        if K and K.Fit then text = K.Fit(text, UI.Font(14, 600), maxW) end
        draw.SimpleText(text, UI.Font(14, 600), tx, ry + rh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end)

Rhylib.Hook.Add("InitPostEntity", "weapons.stats", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.AddControl then
        Menus.AddControl("Combat", "{+menu_context}", "Hold with a gun out: weapon stats")
    end
end)
