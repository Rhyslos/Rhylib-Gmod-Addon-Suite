--[[
    Rhy's Logistics (client): the build tools' ghost, build menu, keys and
    HUD (weapons/rhylib_etool.lua, rhylib_repairtool.lua). How it plays:
    sh_30_build.lua.

      - The picked structure: client convar rhylib_build_pick (its id).
      - The ghost: a see-through copy where you aim (green: can go there,
        red: too far / too steep), facing L.PlaceYaw(me, turn).
      - Keys with a build tool out (PlayerBindPress "logistics.build"):
        E (+use) / Q (+menu, its own hook at -110, before rhylib_menus' Q
        marking) turn it 45 degrees (E-tool only), Z (gmod_undo) removes the
        structure you look at (net logi.build op 2). R opens the build
        menu (the tool's Reload): rhylib_menus' list wheel while R is held
        (None at the bottom: no ghost, RMB places nothing, E / Q don't turn), or
        steps to the next structure (then None) without it.
      - Snap dots (L.SnapDots) show on the ghost and the structures close
        by; when one of the ghost's is within buildSnap of another's, the
        pair turns green and the ghost moves so they meet (L.SnapPlace);
        the HUD says "snapped". The Build wheel's
        "Snapping: ON / OFF" entry switches it (client convar
        rhylib_build_snap, userinfo: the server places the same way).
      - The HUD: what's picked, its cost and the supplies close by, the
        keys, and the hologram's progress / the structure's health you
        look at.
]]

local L = Rhylib.Logistics

-- Snapping on / off (the Build wheel's Snapping entry); userinfo, so the
-- server's placing (L.SnapPlace in sv_30_build.lua) follows it too.
local cvSnap = CreateClientConVar("rhylib_build_snap", "1", true, true, "Build tools: snap the ghost to structures close by (1 on, 0 off)")
local cvPick = CreateClientConVar("rhylib_build_pick", "barrier", true, false, "Build tools: the structure picked in the build menu (none = no ghost)")
L.buildTurn = L.buildTurn or 0

-- The picked structure, or nil for "None" (rhylib_build_pick none: no
-- ghost, RMB places nothing, E / Q don't turn).
local function picked()
    local id = cvPick:GetString()
    if id == "none" then return nil end
    return L.Structure(id) or L.STRUCTURES[1]
end
L.BuildPicked = picked

function L.SendPlace()
    local def = picked()
    if not def then return end
    Rhylib.Net.Start("logi.build")
    net.WriteUInt(1, 2)
    net.WriteUInt(def.index, 5)
    net.WriteUInt(L.buildTurn % 8, 3)
    net.SendToServer()
end

-- R: the build menu.
local menuAt = 0
function L.OpenBuildMenu()
    if RealTime() < menuAt then return end
    menuAt = RealTime() + 0.4
    local W = Rhylib.Menus and Rhylib.Menus.Wheel
    local me = LocalPlayer()
    if not (W and W.OpenList) then
        -- (no wheel: R steps through the list, then None)
        local def = picked()
        local nxt = L.STRUCTURES[(def and def.index or 0) + 1]
        RunConsoleCommand("rhylib_build_pick", nxt and nxt.id or "none")
        Rhylib.Notify(nil, "Building: " .. (nxt and nxt.name or "none (no ghost)"), "info", "Logistics")
        return
    end
    local cur = picked()
    local list = {}
    for _, def in ipairs(L.STRUCTURES) do
        local cost = L.CostFor(me, def)
        list[#list + 1] = { label = def.name, sub = (cost > 0 and (cost .. " supplies · ") or "") .. def.time .. " s to build" .. (def == cur and " · picked" or ""),
            run = function() RunConsoleCommand("rhylib_build_pick", def.id) end }
    end
    local snapOn = cvSnap:GetBool()
    table.insert(list, { label = "Snapping: " .. (snapOn and "ON" or "OFF"), col = Color(240, 120, 200), sub = snapOn and "Pick to place freely" or "Pick to line up with structures close by",
        run = function() RunConsoleCommand("rhylib_build_snap", snapOn and "0" or "1") end })
    -- (None last, turned to the bottom of the wheel)
    table.insert(list, { label = "None", col = Color(225, 60, 55), sub = "No ghost, nothing placed" .. (cur == nil and " · picked" or ""),
        run = function() RunConsoleCommand("rhylib_build_pick", "none") end })
    local key = input.LookupBinding("+reload")
    local code = key and input.GetKeyCode(key) or 0
    W.OpenList("Build", list, code, { bottom = #list })
end

-- Keys with a build tool out.
Rhylib.Hook.Add("PlayerBindPress", "logistics.build", function(ply, bind, pressed)
    if not pressed or not L.HeldTool(ply) then return end
    -- (carrying a crate: E still sets it down)
    if L.HeldPlacer(ply) and picked() and string.find(bind, "+use", 1, true) and not ply:GetNW2Bool("rhylib_carrying", false) then
        L.buildTurn = (L.buildTurn + 1) % 8
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    end
    if string.find(bind, "gmod_undo", 1, true) or bind == "undo" then
        local e = L.AimedStructure(ply, L.structures)
        if IsValid(e) then
            Rhylib.Net.Start("logi.build")
            net.WriteUInt(2, 2)
            net.WriteEntity(e)
            net.SendToServer()
        end
        return true
    end
end, -40)

-- Q (+menu) turns the ghost the other way. Runs before rhylib_menus' Q
-- handler (-100: Q marking / the spawn menu), so it needs its own hook.
Rhylib.Hook.Add("PlayerBindPress", "logistics.buildq", function(ply, bind, pressed)
    if not (L.HeldPlacer(ply) and picked()) then return end
    if not string.find(bind, "+menu", 1, true) or string.find(bind, "+menu_context", 1, true) then return end
    if pressed then
        L.buildTurn = (L.buildTurn - 1) % 8
        surface.PlaySound("buttons/lightswitch2.wav")
    end
    return true
end, -110)

-- The tools hide the crowbar they're held on (blend 0 in the tool's
-- PreDrawViewModel); the hands are drawn before the tool's
-- PostDrawViewModel, so they get the blend back here.
Rhylib.Hook.Add("PreDrawPlayerHands", "logistics.build", function()
    if L.HeldTool(LocalPlayer()) then render.SetBlend(1) end
end)

-- The ghost of the picked structure where you aim.
local ghost, ghostModel
local GOOD, BAD = Color(90, 255, 140), Color(255, 80, 70)
local DOT_GHOST, DOT_OTHER, DOT_JOINED = Color(235, 240, 245, 200), Color(235, 240, 245, 120), Color(70, 255, 110, 255)

local function aim(me)
    local reach = L.Cfg("buildReach")
    local tr = util.TraceLine({ start = me:EyePos(), endpos = me:EyePos() + me:GetAimVector() * reach, filter = me, mask = MASK_SOLID })
    return tr, tr.Hit and not tr.HitSky and tr.HitNormal.z >= 0.6
end

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "logistics.ghost", function(depth, sky)
    if depth or sky then return end
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and L.HeldPlacer(me)) then
        if IsValid(ghost) then ghost:Remove() ghost = nil end
        return
    end
    local def = picked()
    if not def then return end
    if not IsValid(ghost) or ghostModel ~= def.model then
        if IsValid(ghost) then ghost:Remove() end
        ghost = ClientsideModel(def.model, RENDERGROUP_TRANSLUCENT)
        ghostModel = def.model
        if not IsValid(ghost) then return end
        ghost:SetNoDraw(true)
    end
    local tr, ok = aim(me)
    L.ghostSnapped = false
    if not tr.Hit or tr.HitSky then return end
    local yaw = L.PlaceYaw(me, L.buildTurn)
    local mins, maxs = ghost:OBBMins(), ghost:OBBMaxs()
    local base = mins.z < 0 and (tr.HitPos - Vector(0, 0, mins.z)) or tr.HitPos
    local spos, near, joined
    local snapping = cvSnap:GetBool() and L.Cfg("buildSnap") > 0
    if snapping then spos, near, joined = L.SnapPlace(mins, maxs, base, yaw) end
    ghost:SetAngles(Angle(0, yaw, 0))
    if spos then
        ghost:SetPos(spos)
        ok = true
        L.ghostSnapped = true
    else
        ghost:SetPos(base)
    end
    local c = ok and GOOD or BAD
    render.SetBlend(0.35)
    render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255)
    ghost:DrawModel()
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    -- Snap dots: the ghost's and those of structures close by (white), the
    -- joined pair green.
    if snapping then
        render.SetColorMaterial()
        local gpos, gang = ghost:GetPos(), ghost:GetAngles()
        for _, d in ipairs(L.SnapDots(mins, maxs)) do
            render.DrawSphere(LocalToWorld(d, angle_zero, gpos, gang) + Vector(0, 0, 2), 2.5, 8, 8, DOT_GHOST)
        end
        local r = L.Cfg("buildReach") + 400
        for e in pairs(L.structures) do
            if IsValid(e) and e:GetPos():DistToSqr(gpos) < r * r then
                for _, d in ipairs(L.StructureDots(e)) do render.DrawSphere(d + Vector(0, 0, 2), 2.5, 8, 8, DOT_OTHER) end
            end
        end
        if joined then render.DrawSphere(joined + Vector(0, 0, 2), 5, 10, 10, DOT_JOINED) end
    end
end)

-- The HUD while a build tool is out: outlined lines (theme text colours)
-- and the aimed structure's bar on a small kit plate (blue: hologram
-- progress, the hologram's colour; health white / amber / red).
local UIC = Rhylib.UI.Col
local KC = Rhylib.UI.Kit.C
local WHITE, DIM, AMBER, RED = KC.text, KC.textDim, KC.warn, KC.bad
local SHADOW = UIC("logi.hudShadow", 0, 0, 0, 180)
local BLUE = UIC("logi.holo", 110, 190, 255)

function L.DrawBuildHUD(tool)
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local UI = Rhylib.UI
    local f = UI and UI.Font and UI.Font(15, 700) or "DermaDefaultBold"
    local fs = UI and UI.Font and UI.Font(12, 600) or "DermaDefault"
    local x, y = ScrW() * 0.5, ScrH() * 0.62
    local def = tool.CanPlace and picked()
    if def then
        local cost = L.CostFor(me, def)
        local tr = aim(me)
        local have = L.SuppliesNear(tr.HitPos or me:GetPos())
        local line = def.name .. "  ·  " .. (cost > 0 and (cost .. " supplies (" .. have .. " here)") or "free") .. (L.ghostSnapped and "  ·  snapped" or "")
        draw.SimpleTextOutlined(line, f, x, y, (cost > 0 and have < cost) and RED or WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    end
    local keys = tool.CanPlace and (def and "RMB place · LMB build · E / Q turn · R build menu · Z remove"
        or "Nothing picked · LMB build · R build menu (pick a structure) · Z remove")
        or "LMB help build a placed structure / repair · Z remove"
    draw.SimpleTextOutlined(keys, fs, x, y + 20, DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    -- What you look at: a hologram's progress, a structure's health.
    -- (close enough to work on it: buildWorkReach)
    local e = L.AimedStructure(me, L.structures, L.Cfg("buildWorkReach"))
    if not IsValid(e) then return end
    local sd = e:Def()
    local name = sd and sd.name or "Structure"
    local w, h = 220, 10
    local bx, by = x - w / 2, ScrH() * 0.45
    local frac, col, text
    if e:GetBuilt() then
        local max = math.max(1, e:GetSMaxHealth())
        frac = e:GetSHealth() / max
        col = frac < 0.35 and RED or (frac < 0.7 and AMBER or WHITE)
        text = name .. "  ·  " .. e:GetSHealth() .. " / " .. max .. (tool.CanRepair and frac < 1 and "  ·  hold LMB to repair" or "")
    else
        frac = e:GetProgress()
        col = BLUE
        text = name .. "  ·  " .. math.floor(frac * 100) .. "% built  ·  hold LMB"
    end
    local K = Rhylib.UI.Kit
    local pad = 3
    K.Plate(bx - pad, by - pad, w + pad * 2, h + pad * 2, { alpha = 220 })
    K.SetCol(K.C.row)
    surface.DrawRect(bx, by, w, h)
    surface.SetDrawColor(col.r, col.g, col.b, 230)
    surface.DrawRect(bx, by, w * math.Clamp(frac, 0, 1), h)
    draw.SimpleTextOutlined(text, fs, x, by - 14, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
end

-- Console rhylib_tool_tune: line up the E-tool / repair tool in your hands
-- (only on your screen, until a map change; send the printed line to have
-- it made the default). With the tool out:
--   rhylib_tool_tune vm <x> <y> <z> <pitch> <yaw> <roll>   first person
--   rhylib_tool_tune wm <x> <y> <z> <pitch> <yaw> <roll>   third person
--   rhylib_tool_tune vmscale <n> / wmscale <n>   size in first / third person
--   rhylib_tool_tune hold <holdtype>   third-person pose (melee, melee2,
--       knife, slam, physgun, passive, normal, fist, ...)
--   rhylib_tool_tune   prints the current values
local HOLDS = { melee = true, melee2 = true, knife = true, slam = true, physgun = true, passive = true, normal = true,
    fist = true, grenade = true, pistol = true, smg = true, ar2 = true, shotgun = true, crossbow = true, rpg = true, duel = true, magic = true, camera = true, revolver = true }
concommand.Add("rhylib_tool_tune", function(_, _, args)
    local me = LocalPlayer()
    local w = L.HeldTool(me)
    if not w then return print("Hold the E-tool or the field kit first") end
    local stored = weapons.GetStored(w:GetClass()) or {}
    local function set(k, v) w[k] = v stored[k] = v end
    local what = string.lower(args[1] or "")
    local n = {}
    for i = 2, 7 do n[#n + 1] = tonumber(args[i]) or 0 end
    if what == "vm" or what == "wm" then
        local up = string.upper(what)
        set(up .. "Offset", Vector(n[1], n[2], n[3]))
        set(up .. "Angle", Angle(n[4], n[5], n[6]))
    elseif what == "vmscale" or what == "wmscale" then
        local n = tonumber(args[2])
        if not n or n <= 0 or n > 5 then return print("Use: rhylib_tool_tune " .. what .. " <size, e.g. 0.7>") end
        set(what == "vmscale" and "VMScale" or "WMScale", n)
    elseif what == "hold" then
        local h = string.lower(args[2] or "")
        if not HOLDS[h] then return print("Unknown hold type: " .. h) end
        set("HoldType", h)
        w:SetHoldType(h)
    elseif what ~= "" then
        return print("Use: rhylib_tool_tune vm|wm x y z pitch yaw roll, vmscale|wmscale <n>, or hold <type>")
    end
    local function v(o, a) return string.format("%g %g %g %g %g %g", o.x, o.y, o.z, a.p, a.y, a.r) end
    print(string.format("%s: vm %s · wm %s · vmscale %g · wmscale %g · hold %s", w:GetClass(), v(w.VMOffset, w.VMAngle), v(w.WMOffset, w.WMAngle),
        w.VMScale or 1, w.WMScale or 1, w.HoldType))
end, nil, "Line up the build tool in your hands (vm / wm offsets, hold type)")
