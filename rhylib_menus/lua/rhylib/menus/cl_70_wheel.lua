--[[
    Interaction wheel (client): hold Use (E) on another player (or their
    lying body) to see everything you can do to them. Move the mouse
    toward an action and let go of E to do it; let go in the middle to
    cancel. The view stops turning while it's open.

    On a standing player E isn't swallowed: it opens after HOLD seconds,
    so a tap and E + R (fire modes) still work. On a downed player it opens
    at once (it replaces medical's E menu). Not on a grapple rope, in the
    bacta tank, or while R is held.

    Addons add their actions each time it opens:
        Rhylib.Hook.Add("Rhylib.WheelOptions", "medical.wheel", function(target, me, add)
            add("Stabilise", function() ... end, { sub = "Pauses the bleed-out", order = 10 })
            add("Revive", nil, { disabled = "No revive kit" })   -- shown dim
        end)
    (Return nothing from the hook, so every addon's hook runs.)

    Entities with ENT.RhylibWheel = true (the chemistry bench) open their
    own wheel at once on E: hook Rhylib.WheelEntityOptions(ent, me, add).

    W.OpenList(title, list, code) opens a wheel with no target: list =
    { { label, run, sub, disabled, col } } (col: a Color for a wider strip
    on the left edge), held while button code is down (the toolgun's
    R menu uses it); let go on an option to run it.

    Menus.WheelProgress(text, secs) shows a short progress bar under the
    crosshair (for timed actions the server finishes, like cuffing).
]]

local Menus = Rhylib.Menus
local UI = Rhylib.UI

local W = Menus.Wheel or {}
Menus.Wheel = W

local RANGE = 130          -- how far you reach
local KEEP = 220           -- target further than this: the wheel closes
local DEADZONE = 44        -- px at 1080p
local CURSOR_MAX = 150
local RING = 165
local HOLD = 0.25          -- s of holding E on a standing player before it opens

-- The player you're aiming at (downed bodies by medical's wider cone).
function W.FindTarget(me)
    local Med = Rhylib.Medical
    if Med and Med.FindDowned and Med.clientDown then
        local t = Med.FindDowned(me, Med.clientDown)
        if IsValid(t) and t ~= me then return t end
    end
    local eye = me:EyePos()
    local tr = util.TraceHull({ start = eye, endpos = eye + me:GetAimVector() * RANGE, mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6),
        filter = me, mask = MASK_SHOT_HULL })
    local e = tr.Entity
    local L = Rhylib.Lying
    if IsValid(e) and L and L.Owner and L.Owner(e) then e = L.Owner(e) end
    if IsValid(e) and e:IsPlayer() and e ~= me and e:Alive() then return e end
    if IsValid(e) and e.RhylibWheel then return e end
end

local function canOpen(me)
    if not IsValid(me) or not me:Alive() or me:InVehicle() then return false end
    local L = Rhylib.Lying
    if L and L.Is and L.Is(me) then return false end
    local MP = Rhylib.MP
    if MP and MP.IsCuffed and MP.IsCuffed(me) then return false end
    local Med = Rhylib.Medical
    if Med and ((Med.Action and Med.Action(me) ~= 0) or (Med.Dragging and Med.Dragging(me))) then return false end
    local G = Rhylib.Weapons and Rhylib.Weapons.Grapple
    if G and G.Attached and G.Attached(me) then return false end   -- (E lets go of the rope)
    if IsValid(me:GetNW2Entity("rhylib_tank")) then return false end   -- (E gets out of the tank)
    if me:KeyDown(IN_RELOAD) then return false end   -- (E + R: fire mode)
    return true
end

-- Ask every addon for its actions; laid out around the ring from the top.
local function gather(target, me)
    local list = {}
    local function add(label, run, opts)
        opts = opts or {}
        list[#list + 1] = { label = label, run = run, sub = opts.sub, disabled = opts.disabled, order = opts.order or 50, n = #list }
    end
    if target:IsPlayer() then
        hook.Run("Rhylib.WheelOptions", target, me, add)
    else
        hook.Run("Rhylib.WheelEntityOptions", target, me, add)
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.n < b.n
    end)
    for i, o in ipairs(list) do o.angle = -90 + (i - 1) * 360 / #list end
    return list
end

-- The button that opened it (mouse buttons and second binds too).
local function useHeld()
    if W.code and W.code > 0 then return input.IsButtonDown(W.code) end
    local key = input.LookupBinding("+use")
    local code = key and input.GetKeyCode(key)
    return code and code > 0 and input.IsButtonDown(code)
end

function W.Close()
    W.open, W.target, W.list, W.pick, W.pending, W.title = false, nil, nil, nil, nil, nil
end

-- A wheel from a fixed list, no target (held with button code).
function W.OpenList(title, list, code)
    if W.open or #list == 0 then return false end
    for i, o in ipairs(list) do o.angle = -90 + (i - 1) * 360 / #list end
    W.open, W.target, W.list, W.title, W.code = true, nil, list, title, code
    W.cx, W.cy = 0, 0
    W.openedAt = RealTime()
    surface.PlaySound("ui/buttonrollover.wav")
    return true
end

function W.Open(target)
    local me = LocalPlayer()
    local list = gather(target, me)
    if #list == 0 then return false end
    W.open, W.target, W.list = true, target, list
    W.cx, W.cy = 0, 0
    W.openedAt = RealTime()
    surface.PlaySound("ui/buttonrollover.wav")
    return true
end

local function isDown(t)
    local Med = Rhylib.Medical
    return Med and Med.IsDown and Med.IsDown(t)
end

Rhylib.Hook.Add("PlayerBindPress", "menus.wheel", function(ply, bind, pressed, code)
    if not pressed or not string.find(bind, "+use", 1, true) then return end
    if W.open then return true end
    if not canOpen(ply) then return end
    local t = W.FindTarget(ply)
    if not t then return end
    W.code = code
    -- Downed: at once (instead of medical's E menu). Standing: after a hold.
    if not t:IsPlayer() or isDown(t) then
        if W.Open(t) then return true end
        return
    end
    W.pending = { target = t, at = RealTime() + HOLD }
end, -20)

Rhylib.Hook.Add("Think", "menus.wheel", function()
    local me = LocalPlayer()
    local p = W.pending
    if p and not W.open then
        if not useHeld() or not canOpen(me) or W.FindTarget(me) ~= p.target then
            W.pending = nil
        elseif RealTime() >= p.at then
            W.pending = nil
            W.Open(p.target)
        end
        return
    end
    if not W.open then return end
    local t = W.target
    if W.title then
        -- (a list wheel: only the key matters)
        W.pick = W.PickOption(ScrH() / 1080)
        if not me:Alive() then
            W.Close()
            return
        end
        if not (W.code and W.code > 0 and input.IsButtonDown(W.code)) then
            local pick = W.pick
            W.Close()
            if pick and pick.run and not pick.disabled then
                surface.PlaySound("ui/buttonclick.wav")
                pick.run()
            end
        end
        return
    end
    if not IsValid(t) or not canOpen(me) or t:GetPos():DistToSqr(me:GetPos()) > KEEP * KEEP then
        W.Close()
        return
    end
    W.pick = W.PickOption(ScrH() / 1080)
    if not useHeld() then
        local pick = W.pick
        W.Close()
        if pick and pick.run and not pick.disabled then
            surface.PlaySound("ui/buttonclick.wav")
            pick.run(t)
        end
    end
end)

Rhylib.Hook.Add("InputMouseApply", "menus.wheel", function(cmd, x, y)
    if not W.open then return end
    local s = ScrH() / 1080
    W.cx = W.cx + x * 0.6
    W.cy = W.cy + y * 0.6
    local len = math.sqrt(W.cx * W.cx + W.cy * W.cy)
    local max = CURSOR_MAX * s
    if len > max then W.cx, W.cy = W.cx / len * max, W.cy / len * max end
    return true
end, -40)

function W.PickOption(s)
    if not W.list then return nil end
    local len = math.sqrt(W.cx * W.cx + W.cy * W.cy)
    if len < DEADZONE * s then return nil end
    local ang = math.deg(math.atan2(W.cy, W.cx))
    local best, bestD
    for _, o in ipairs(W.list) do
        local d = math.abs(math.NormalizeAngle(ang - o.angle))
        if not bestD or d < bestD then best, bestD = o, d end
    end
    return best
end

local COL_DEAD = Color(0, 0, 0, 140)
local COL_PICK = Color(60, 72, 88, 235)

Rhylib.Hook.Add("HUDPaint", "menus.wheel", function()
    if not W.open or not W.list then return end
    local s = ScrH() / 1080
    local cx, cy = ScrW() * 0.5, ScrH() * 0.5
    local pick = W.pick

    local dz = DEADZONE * s
    draw.RoundedBox(dz, cx - dz, cy - dz, dz * 2, dz * 2, COL_DEAD)
    draw.SimpleText(pick and "" or "Cancel", UI.Font(14), cx, cy + 9 * s, UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if W.title then
        draw.SimpleText(W.title, UI.Font(15, 700), cx, cy - 9 * s, UI.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif IsValid(W.target) then
        draw.SimpleText(W.target:IsPlayer() and W.target:Nick() or (W.target.PrintName or ""), UI.Font(15, 700), cx, cy - 9 * s, UI.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local w, h = 210 * s, 58 * s
    local ring = RING * (#W.list > 6 and 1.32 or 1)   -- (7+ options: wider, so they don't overlap)
    local HUD = Rhylib.HUD
    for _, o in ipairs(W.list) do
        local a = math.rad(o.angle)
        local ox, oy = cx + math.cos(a) * ring * s, cy + math.sin(a) * ring * s
        local bx, by = ox - w * 0.5, oy - h * 0.5
        local isPick = pick == o
        if HUD and HUD.Frame then
            HUD.Frame(bx, by, w, h, { ticks = isPick })
        else
            draw.RoundedBox(0, bx, by, w, h, UI.Colors.bg)
        end
        if isPick then
            surface.SetDrawColor(COL_PICK)
            surface.DrawRect(bx + 1, by + 1, w - 2, h - 2)
        end
        if o.col then
            -- (colour-coded option: a wider strip in its colour, faded when unavailable)
            surface.SetDrawColor(o.disabled and ColorAlpha(o.col, 70) or o.col)
            surface.DrawRect(bx + 1, by + 1, math.max(4, math.floor(6 * s)), h - 2)
        else
            surface.SetDrawColor(o.disabled and UI.Colors.bad or (isPick and UI.Colors.accent or UI.Colors.border))
            surface.DrawRect(bx + 1, by + 1, 3, h - 2)
        end
        local sub = o.disabled or o.sub
        draw.SimpleText(o.label, UI.Font(17, 600), ox, sub and oy - 9 * s or oy, o.disabled and UI.Colors.textDim or UI.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if sub then
            draw.SimpleText(sub, UI.Font(13), ox, oy + 12 * s, o.disabled and UI.Colors.bad or UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    draw.RoundedBox(4 * s, cx + W.cx - 4 * s, cy + W.cy - 4 * s, 8 * s, 8 * s, UI.Colors.text)
end)

--------------------------------------------------------------------------
-- A short progress bar under the crosshair (timed actions)
--------------------------------------------------------------------------

function Menus.WheelProgress(text, secs)
    W.prog = { text = text, from = RealTime(), to = RealTime() + secs }
end

function Menus.WheelProgressStop()
    W.prog = nil
end

Rhylib.Hook.Add("HUDPaint", "menus.wheel.progress", function()
    local p = W.prog
    if not p then return end
    local now = RealTime()
    if now > p.to + 0.2 then W.prog = nil return end
    local s = ScrH() / 1080
    local f = math.Clamp((now - p.from) / (p.to - p.from), 0, 1)
    local w, h = 260 * s, 6 * s
    local x, y = (ScrW() - w) * 0.5, ScrH() * 0.56
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(x - 1, y - 1, w + 2, h + 2)
    surface.SetDrawColor(UI.Colors.accent)
    surface.DrawRect(x, y, w * f, h)
    draw.SimpleText(string.upper(p.text), UI.Font(13, 700), ScrW() * 0.5, y - 12 * s, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
