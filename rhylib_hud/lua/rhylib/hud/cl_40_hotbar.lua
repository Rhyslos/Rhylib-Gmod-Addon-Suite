--[[
    Hotbar (client). Replaces the default weapon selection. Third person:
    a row at the bottom centre. Helmet visor with rhylib_inventory: drawn
    by the f4/f5 layouts (HUD.DrawVisorLayout in cl_42_layouts.lua); the
    older "console" plate next to the ammo box (drawConsole below) is only
    a fallback if that file is missing.

    With rhylib_inventory: fixed numbered slots that you fill yourself by
    dragging items onto the hotbar row in the inventory window (4 slots,
    6 with a backpack). A slot can hold any item; for now only weapons do
    something when picked (grenades and handing out ammo come later).
    Anything you hold that isn't in your inventory (force-given, like the
    physgun or a sandbox loadout) sits in an overflow slot after them:
    its key cycles through them.

    Without rhylib_inventory: one box per weapon you hold, by weapon slot.

    Number keys pick a slot. An empty slot, or the slot you're already
    holding, puts your gun away (the empty "Stowed" weapon). The scroll
    wheel steps through every weapon on the bar, the "lastinv" bind swaps
    to the previous one. The bar
    is bright right after switching and fades back after a moment.

    The bar is rebuilt five times a second (or at once if a weapon on it
    was removed), not every frame.

    Client convar rhylib_hud_hotbar_fade (default 1, Settings): fade the
    bar when you're not switching.
    Shares HUD.HotbarRect with the stamina bar (cl_45_stamina.lua).
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI

local fadeVar = CreateClientConVar("rhylib_hud_hotbar_fade", "1", true, false, "Fade the hotbar when you're not switching weapons (0/1)")

-- Where the hotbar was last drawn (screen pixels) and on which frame.
-- The stamina bar sits on top of it; it checks `frame` so a stale rect
-- (hotbar not drawn) isn't used.
HUD.HotbarRect = HUD.HotbarRect or { x = 0, y = 0, w = 0, h = 0, frame = 0 }

-- entries[i] = { key = number shown, wep = weapon or nil, name, sub, empty, overflow = { weapons } }
-- (also hold = item uid for hand-held items like magazines, see rebuild)
local entries = {}
local nextBuild = 0
local lastSwitch = 0
local previous = nil

local STOWED = "rhylib_stowed"   -- the empty "hands" weapon (rhylib_inventory)

local function inventory()
    local Inv = Rhylib.Inventory
    return Inv and Inv.HotbarItem and Rhylib.Items and Inv or nil
end

local function selectWeapon(wep)
    local ply = LocalPlayer()
    local active = ply:GetActiveWeapon()
    if not IsValid(wep) or wep == active then return end
    previous = active
    input.SelectWeapon(wep)
    lastSwitch = RealTime()
end

-- Put the gun away (hold the empty Stowed weapon), if the player has it.
local function stow(ply)
    local w = ply:GetWeapon(STOWED)
    if IsValid(w) then selectWeapon(w) end
end

local function itemSub(inst, def)
    if inst.count > 1 then return "x" .. inst.count end
    if def.rounds and def.rounds > 1 then return math.floor((inst.data.fill or 1) * def.rounds + 0.5) .. "/" .. def.rounds end
    if def.fill then return math.ceil((inst.data.fill or 1) * 100) .. "%" end
end

local function rebuild(ply)
    entries = {}
    local Inv = inventory()
    local weps = ply:GetWeapons()

    if not Inv then
        -- No inventory: one box per held weapon, by weapon slot.
        local list = {}
        for _, w in ipairs(weps) do
            if IsValid(w) then list[#list + 1] = w end
        end
        table.sort(list, function(a, b)
            local sa, sb = a:GetSlot(), b:GetSlot()
            if sa ~= sb then return sa < sb end
            return a:GetSlotPos() < b:GetSlotPos()
        end)
        for i, w in ipairs(list) do
            entries[i] = { key = i, wep = w, name = w:GetPrintName() or w:GetClass() }
        end
        return
    end

    local Items = Rhylib.Items
    local n = Items.HotbarSize(Inv)
    for k = 1, n do
        local inst = Inv.HotbarItem(k)
        local def = inst and Items.Get(inst.id)
        if def then
            local wep = def.weapon and ply:GetWeapon(def.weapon)
            local hold
            if def.hand then
                -- Held with the hand weapon (rhylib_inventory): active when it holds this item.
                hold = inst.uid
                local hw = ply:GetWeapon(Rhylib.Inventory.HAND or "rhylib_hand")
                wep = (IsValid(hw) and ply:GetNW2Int("rhylib_handUid", 0) == inst.uid) and hw or nil
            end
            entries[k] = { key = k, wep = IsValid(wep) and wep or nil, hold = hold, name = def.name, sub = itemSub(inst, def) }
        else
            entries[k] = { key = k, empty = true }
        end
    end

    -- Overflow: held weapons that aren't inventory items.
    local inInv = {}
    for _, inst in pairs(Inv.byUid) do inInv[inst.id] = true end
    local over = {}
    local HAND = Rhylib.Inventory.HAND or "rhylib_hand"
    for _, w in ipairs(weps) do
        if IsValid(w) and not inInv[w:GetClass()] and w:GetClass() ~= STOWED and w:GetClass() ~= HAND then over[#over + 1] = w end
    end
    if #over > 0 then
        local active = ply:GetActiveWeapon()
        local shown = over[1]
        for _, w in ipairs(over) do
            if w == active then shown = w end
        end
        entries[n + 1] = {
            key = n + 1, wep = shown, overflow = over,
            name = shown:GetPrintName() or shown:GetClass(),
            sub = #over > 1 and ("+" .. (#over - 1) .. " more") or nil,
        }
    end
end

-- Every weapon on the bar, in order (for the scroll wheel).
local function cycleList()
    local list = {}
    for _, e in ipairs(entries) do
        if e.hold then
            -- Held items (magazines) are picked with their slot key only.
        elseif e.overflow then
            for _, w in ipairs(e.overflow) do list[#list + 1] = w end
        elseif e.wep then
            list[#list + 1] = e.wep
        end
    end
    return list
end

-- True while number keys / the wheel belong to something else: the
-- inventory window or the weapons' radial menu is open.
local function busy()
    local Inv = Rhylib.Inventory
    return (Inv and IsValid(Inv.panel)) or (Rhylib.Weapons and Rhylib.Weapons.Radial and Rhylib.Weapons.Radial.open)
end

-- Slot keys (slot1..), the scroll wheel (invnext/invprev) and lastinv.
-- Returning true swallows the bind so the default weapon selection
-- never runs.
Rhylib.Hook.Add("PlayerBindPress", "hud.hotbar", function(ply, bind, pressed)
    if not pressed or not ply:Alive() or ply:InVehicle() then return end

    local slot = string.match(bind, "^slot(%d+)")
    local isNext = string.find(bind, "invnext", 1, true)
    local isPrev = string.find(bind, "invprev", 1, true)
    local isLast = string.find(bind, "lastinv", 1, true)
    if not (slot or isNext or isPrev or isLast) then return end

    -- Let the physgun use the scroll wheel while holding something.
    local active = ply:GetActiveWeapon()
    if (isNext or isPrev) and IsValid(active) and active:GetClass() == "weapon_physgun" and ply:KeyDown(IN_ATTACK) then return end
    if busy() then return true end

    rebuild(ply)
    lastSwitch = RealTime()

    if slot then
        local e = entries[tonumber(slot)]
        if not e then return true end
        if e.hold and e.wep ~= active then
            -- An item you hold in your hand (magazines, cells).
            Rhylib.Inventory.RequestHold(e.hold)
            previous = active
        elseif e.overflow then
            -- Cycle through the overflow weapons.
            local pick = e.overflow[1]
            for i, w in ipairs(e.overflow) do
                if w == active then pick = e.overflow[i % #e.overflow + 1] end
            end
            selectWeapon(pick)
        elseif e.wep and e.wep ~= active then
            selectWeapon(e.wep)
        elseif inventory() and (e.empty or e.wep == active) then
            -- Empty slot, or the gun you're already holding: put it away.
            -- (Non-weapon items do nothing yet.)
            stow(ply)
        end
    elseif isLast then
        if IsValid(previous) and previous:GetOwner() == ply then selectWeapon(previous) end
    else
        local list = cycleList()
        local n = #list
        if n == 0 then return true end
        local i = 0
        for k, w in ipairs(list) do
            if w == active then i = k end
        end
        i = isNext and (i % n + 1) or ((i - 2) % n + 1)
        selectWeapon(list[i])
    end
    return true
end)

local function fit(text, font, maxW)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= maxW then return text end
    while #text > 1 and surface.GetTextSize(text .. "…") > maxW do text = string.sub(text, 1, -2) end
    return text .. "…"
end

local rectPool = {}
local function rect(i)
    local r = rectPool[i]
    if not r then
        r = {}
        rectPool[i] = r
    end
    return r
end

--[[
    Where each entry's box goes (third person, or the visor without the
    inventory). Third person: one row, centred between the corner plates.
    The visor with the inventory uses the console below instead.
]]
local function layout(visor, s)
    local rects = {}
    local count = #entries

    if not visor then
        local gap = math.floor(6 * s)
        local space = ScrW() * 0.44
        local bw = math.floor(math.Clamp((space - gap * (count - 1)) / count, 56 * s, 104 * s))
        local bh = math.floor(76 * s)
        local total = count * bw + (count - 1) * gap
        local x = math.floor((ScrW() - total) * 0.5)
        local _, my = HUD.Margins("hotbar")
        local y = ScrH() - bh - my
        for i = 1, count do
            local r = rect(i)
            r.x, r.y, r.w, r.h = x + (i - 1) * (bw + gap), y, bw, bh
            rects[i] = r
        end
        return rects
    end

    for i = 1, count do
        local r = rect(i)
        local w = math.floor(70 * s)
        r.x, r.y, r.w, r.h = ScrW() * 0.62 + (i - 1) * (w + 6 * s), ScrH() - math.floor(90 * s), w, math.floor(62 * s)
        rects[i] = r
    end
    return rects
end

--------------------------------------------------------------------------
-- Helmet visor console (with the inventory): one plate built like the
-- ammo box, right next to it and as tall. Slots 1-4 are cells in it.
-- Above slots 2-4 a tab holds the overflow slot ("OTHER") and the
-- backpack slots 5 and 6, each group under its own header.
--------------------------------------------------------------------------

local CELL_W = 100           -- cell width at 1080p (narrower if the cheek is in the way)
local COL_PLATE = Color(28, 32, 31, 236)     -- a little lighter than the helmet shell
local COL_HEADER = Color(40, 45, 43, 250)
local COL_DIVIDER = Color(170, 176, 180, 60)
local COL_HEAD_TEXT = Color(165, 168, 160)

--[[
    Smallest x for a plate from y0 to y1 that stays clear of the bars and
    the stamina strip along the right cheek. The plate's top-left corner
    is cut cutW wide and cutH high, so it can tuck in under the curve.
]]
local function clearLeft(y0, y1, cutW, cutH, s)
    local gap = 8 * s
    local strip = HUD.VisorStrip and HUD.VisorStrip(1, 0.012, 0.4, 0.005, 0.009, 48)
    if not strip then
        return (HUD.VisorCheekX and HUD.VisorCheekX(y0 + cutH, 1) or ScrW() * 0.6) + ScrH() * 0.042
    end
    local x = 0
    for _, list in ipairs({ strip.outer, strip.inner }) do
        for _, p in ipairs(list) do
            local py = p[2]
            if py >= y0 and py <= y1 then
                local need = p[1] + gap
                if cutH > 0 and py < y0 + cutH then need = need - cutW * (1 - (py - y0) / cutH) end
                if need > x then x = need end
            end
        end
    end
    return x
end
local tcol = Color(0, 0, 0)

local function txt(text, size, weight, x, y, col, ax, ay, a)
    tcol.r, tcol.g, tcol.b, tcol.a = col.r, col.g, col.b, (col.a or 255) * a / 255
    return draw.SimpleText(text, UI.Font(size, weight), x, y, tcol, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_CENTER)
end

local function fill(col, a, x, y, w, h)
    surface.SetDrawColor(col.r, col.g, col.b, (col.a or 255) * a / 255)
    surface.DrawRect(x, y, w, h)
end

local tabItems = {}
local headerVerts = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }

local function drawConsole(active, alpha, s)
    local C = HUD.Colors
    local S = HUD.Style
    local ax, ay, _, ah = HUD.VisorAmmoRect()
    local right = ax - math.floor(10 * s)
    -- A wide, shallow cut on the top-left corner, about the slope of the
    -- cheek there, so the plate reaches further left.
    local cutW, cutH = math.floor(60 * s), math.floor(30 * s)

    -- The plate: as tall as the ammo box, as wide as four cells allow.
    local y, h = ay, ah
    local x = math.floor(math.max(clearLeft(y, y + h, cutW, cutH, s), right - CELL_W * 4 * s))
    local w = right - x
    local cw = w / 4

    local r = HUD.HotbarRect
    r.x, r.y, r.w, r.h, r.frame = x, y, w, h, FrameNumber()

    HUD.Frame(x, y, w, h, { alpha = alpha, cut = cutW, cutH = cutH, cutLeft = true, bg = COL_PLATE })
    local inset = math.floor(4 * s)
    local barH = math.max(2, math.floor(3 * s))
    for i = 1, 4 do
        local e = entries[i]
        local bx = math.floor(x + (i - 1) * cw)
        local bw = math.floor(x + i * cw) - bx
        if i > 1 then fill(COL_DIVIDER, alpha, bx, y + math.floor(10 * s), 1, h - math.floor(20 * s)) end
        if e then
            local isActive = e.wep ~= nil and e.wep == active
            local a = isActive and math.min(255, alpha * 2) or alpha
            if isActive then
                fill(C.accent, a * 0.1, bx + inset, y + inset, bw - inset * 2, h - inset * 2)
                fill(C.accent, a, bx + inset, y + h - inset - barH, bw - inset * 2, barH)
            end
            -- The first cell's number sits clear of the cut corner.
            local tx = bx + math.floor(10 * s) + (i == 1 and math.floor(cutW * (1 - 20 * s / cutH)) or 0)
            local tw = bx + bw - tx - math.floor(6 * s)
            txt(tostring(e.key), 14, 700, tx, y + math.floor(20 * s), isActive and C.accent or C.dim, nil, nil, a)
            local mid = y + h * 0.52
            if e.empty then
                txt("Empty", 14, 400, tx, mid, C.dim, nil, nil, a * 0.5)
            else
                txt(fit(e.name, UI.Font(15, isActive and 500 or 400), tw), 15, isActive and 500 or 400, tx, mid, isActive and C.text or C.dim, nil, nil, a)
                if e.sub then txt(e.sub, 12, 400, tx, mid + math.floor(20 * s), C.dim, nil, nil, a * 0.8) end
            end
        end
    end

    -- The tab above: overflow first, then the backpack slots.
    local n = #tabItems
    for k = 1, n do tabItems[k] = nil end
    local count = #entries
    local over = entries[count] and entries[count].overflow and entries[count] or nil
    local packs = 0
    if over then tabItems[#tabItems + 1] = over end
    for i = 5, 6 do
        if entries[i] and not entries[i].overflow then
            tabItems[#tabItems + 1] = entries[i]
            packs = packs + 1
        end
    end
    n = #tabItems
    if n == 0 then return end

    -- The tab also has a cut top-left corner, so it reaches in under the
    -- curve and its cells stay roomy.
    local th = math.floor(34 * s)
    local hh = math.floor(14 * s)
    local ty = y - math.floor(6 * s) - th
    local tcutW, tcutH = math.floor(60 * s), math.floor(30 * s)
    -- Right-aligned over the last cells, and clear of the cheek.
    local tx0 = math.floor(math.max(right - n * cw, x + cw, clearLeft(ty, ty + th, tcutW, tcutH, s)))
    local tw = right - tx0
    local tcw = tw / n
    -- The tab's left edge at a height (inside the cut it slopes).
    local function leftAt(yy)
        local d = yy - ty
        if d >= tcutH then return tx0 end
        return tx0 + tcutW * (1 - d / tcutH)
    end
    HUD.Frame(tx0, ty, tw, th, { alpha = alpha, ticks = false, bg = COL_PLATE, cut = tcutW, cutH = tcutH, cutLeft = true })

    -- Header band, cut to the same slope.
    local hv = headerVerts
    hv[1].x, hv[1].y = leftAt(ty + 1), ty + 1
    hv[2].x, hv[2].y = right - 1, ty + 1
    hv[3].x, hv[3].y = right - 1, ty + hh
    hv[4].x, hv[4].y = leftAt(ty + hh), ty + hh
    surface.SetDrawColor(COL_HEADER.r, COL_HEADER.g, COL_HEADER.b, COL_HEADER.a * alpha / 255)
    draw.NoTexture()
    surface.DrawPoly(hv)

    -- Header labels, each with a rule under its group.
    local others = over and 1 or 0
    local ruleX = math.floor(leftAt(ty + hh))
    local labelY = ty + 1 + hh * 0.5
    local pad = math.floor(6 * s)
    if over then
        fill(S.tick, alpha * 0.6, ruleX + 1, ty + hh, math.floor(tx0 + tcw) - ruleX - 2, 1)
        txt("OTHER", 10, 700, math.max(tx0, leftAt(labelY)) + pad, labelY, COL_HEAD_TEXT, nil, nil, alpha)
    end
    if packs > 0 then
        local px = math.floor(tx0 + others * tcw)
        local rx = math.max(px, ruleX)
        fill(C.accent, alpha * 0.7, rx + 1, ty + hh, right - rx - 2, 1)
        txt("BACKPACK", 10, 700, math.max(px, leftAt(labelY)) + pad, labelY, COL_HEAD_TEXT, nil, nil, alpha)
    end

    local cy = ty + hh + (th - hh) * 0.5
    for k, e in ipairs(tabItems) do
        local bx = math.floor(tx0 + (k - 1) * tcw)
        local bw = math.floor(tx0 + k * tcw) - bx
        if k > 1 then fill(COL_DIVIDER, alpha, bx, ty + hh + math.floor(3 * s), 1, th - hh - math.floor(6 * s)) end
        local isActive = e.wep ~= nil and e.wep == active
        if e.overflow then
            for _, wp in ipairs(e.overflow) do
                if wp == active then isActive = true end
            end
        end
        local a = isActive and math.min(255, alpha * 2) or alpha
        if isActive then fill(C.accent, a, bx + 2, ty + th - 3, bw - 4, 2) end
        local lx = math.floor(math.max(bx, leftAt(cy - 6 * s))) + math.floor(8 * s)
        local kw = txt(tostring(e.key), 11, 700, lx, cy, isActive and C.accent or C.dim, nil, nil, a)
        local nx = lx + kw + math.floor(6 * s)
        local extra = e.overflow and #e.overflow > 1 and ("+" .. (#e.overflow - 1)) or nil
        local room = bx + bw - nx - math.floor(6 * s)
        if extra then
            local ew = txt(extra, 11, 400, bx + bw - math.floor(6 * s), cy, C.dim, TEXT_ALIGN_RIGHT, nil, a)
            room = room - ew - math.floor(4 * s)
        end
        if e.empty then
            txt("Empty", 12, 400, nx, cy, C.dim, nil, nil, a * 0.5)
        elseif room > 8 * s then
            txt(fit(e.name, UI.Font(12, 400), room), 12, 400, nx, cy, isActive and C.text or C.dim, nil, nil, a)
        end
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.hotbar", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    -- Rebuild five times a second, or straight away if a weapon on the bar
    -- was removed (dying, dropping, being stripped).
    local stale = RealTime() >= nextBuild
    for i = 1, #entries do
        local w = entries[i].wep
        if w ~= nil and not IsValid(w) then stale = true break end
    end
    if stale then
        rebuild(ply)
        nextBuild = RealTime() + 0.2
    end
    local count = #entries
    if count == 0 then return end

    local s = HUD.Scale()
    local C = HUD.Colors
    local active = ply:GetActiveWeapon()

    local since = RealTime() - lastSwitch
    local visor = HUD.VisorActive and HUD.VisorActive()
    local alpha = 255
    if fadeVar:GetBool() then
        alpha = since < 2.5 and 255 or math.max(90, 255 - (since - 2.5) * 400)
    end

    if visor and inventory() then
        -- Visor layouts (picked by an admin with rhylib_hud_layout).
        local layout = HUD.VisorLayout and HUD.VisorLayout() or "console"
        if layout ~= "console" and HUD.DrawVisorLayout then
            HUD.DrawVisorLayout(layout, entries, active, alpha, s)
            return
        end
        if HUD.VisorAmmoRect then
            drawConsole(active, alpha, s)
            return
        end
    end

    -- One rect per entry: rects[i] = { x, y, w, h }.
    local rects = layout(visor, s)
    local r0, rl = rects[1], rects[#rects]

    -- Shared with the stamina bar, which sits on top (even while this fades out).
    local r = HUD.HotbarRect
    r.x, r.y, r.w, r.h, r.frame = r0.x, r0.y, rl.x + rl.w - r0.x, r0.h, FrameNumber()

    if alpha <= 0 then return end
    local font = UI.Font(14)
    local barH = math.max(2, math.floor(3 * s))

    for i, e in ipairs(entries) do
        local rc = rects[i]
        local bx, by, bw, bh = rc.x, rc.y, rc.w, rc.h
        local isActive = e.wep ~= nil and e.wep == active
        local a = isActive and math.min(255, alpha * 2) or alpha
        if e.empty then a = a * 0.5 end
        HUD.Frame(bx, by, bw, bh, { alpha = a, ticks = isActive })
        if isActive then
            surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, a)
            surface.DrawRect(bx, by + bh - barH, bw, barH)
        end
        HUD.Text(e.overflow and (e.key .. " +") or tostring(e.key), 13, bx + math.floor(7 * s), by + math.floor(5 * s), C.dim, nil, nil, a)
        if not e.empty then
            local small = bh < 50 * s
            HUD.Text(fit(e.name, font, bw - 10 * s), 14, bx + bw * 0.5, by + bh * (small and 0.62 or 0.5), isActive and C.text or C.dim,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, a)
            if e.sub and not small then
                HUD.Text(e.sub, 12, bx + bw * 0.5, by + bh * 0.76, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, a)
            end
        end
    end
end)
