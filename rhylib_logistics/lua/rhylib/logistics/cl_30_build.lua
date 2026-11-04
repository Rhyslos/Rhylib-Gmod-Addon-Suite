--[[
    Rhy's Logistics (client): the build tools' ghost, build menu, keys and
    HUD (weapons/rhylib_etool.lua, rhylib_repairtool.lua). How it plays:
    sh_30_build.lua.

      - The picked structure: client convar rhylib_build_pick (its id).
      - The ghost: a see-through copy where you aim (green: can go there,
        red: too far / too steep), facing L.PlaceYaw(me, turn).
      - Keys with a build tool out (PlayerBindPress "logistics.build"):
        E (+use) / Q (+menu) turn it 45 degrees, Z (gmod_undo) removes the
        structure you look at (net logi.build op 2). R opens the build
        menu (the tool's Reload): rhylib_menus' list wheel while R is held,
        or steps to the next structure without it.
      - The HUD: what's picked, its cost and the supplies close by, the
        keys, and the hologram's progress / the structure's health you
        look at.
]]

local L = Rhylib.Logistics

local cvPick = CreateClientConVar("rhylib_build_pick", "barrier", true, false, "Build tools: the structure picked in the build menu")
L.buildTurn = L.buildTurn or 0

local function picked()
    return L.Structure(cvPick:GetString()) or L.STRUCTURES[1]
end

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
        -- (no wheel: R steps through the list)
        local def = picked()
        local nxt = L.STRUCTURES[(def and def.index or 0) % #L.STRUCTURES + 1]
        RunConsoleCommand("rhylib_build_pick", nxt.id)
        Rhylib.Notify(nil, "Building: " .. nxt.name, "info", "Logistics")
        return
    end
    local list = {}
    local cur = picked()
    for _, def in ipairs(L.STRUCTURES) do
        local cost = L.CostFor(me, def)
        list[#list + 1] = { label = def.name, sub = (cost > 0 and (cost .. " supplies · ") or "") .. def.time .. " s to build" .. (def == cur and " · picked" or ""),
            run = function() RunConsoleCommand("rhylib_build_pick", def.id) end }
    end
    local key = input.LookupBinding("+reload")
    local code = key and input.GetKeyCode(key) or 0
    W.OpenList("Build", list, code)
end

-- Keys with a build tool out.
Rhylib.Hook.Add("PlayerBindPress", "logistics.build", function(ply, bind, pressed)
    if not pressed or not L.HeldTool(ply) then return end
    -- (carrying a crate: E still sets it down)
    if string.find(bind, "+use", 1, true) and not ply:GetNW2Bool("rhylib_carrying", false) then
        L.buildTurn = (L.buildTurn + 1) % 8
        surface.PlaySound("buttons/lightswitch2.wav")
        return true
    end
    if string.find(bind, "+menu", 1, true) and not string.find(bind, "+menu_context", 1, true) then
        L.buildTurn = (L.buildTurn - 1) % 8
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

-- The tools hide the crowbar they're held on (blend 0 in the tool's
-- PreDrawViewModel); the hands are drawn before the tool's
-- PostDrawViewModel, so they get the blend back here.
Rhylib.Hook.Add("PreDrawPlayerHands", "logistics.build", function()
    if L.HeldTool(LocalPlayer()) then render.SetBlend(1) end
end)

-- The ghost of the picked structure where you aim.
local ghost, ghostModel
local GOOD, BAD = Color(90, 255, 140), Color(255, 80, 70)

local function aim(me)
    local reach = L.Cfg("buildReach")
    local tr = util.TraceLine({ start = me:EyePos(), endpos = me:EyePos() + me:GetAimVector() * reach, filter = me, mask = MASK_SOLID })
    return tr, tr.Hit and not tr.HitSky and tr.HitNormal.z >= 0.6
end

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "logistics.ghost", function(depth, sky)
    if depth or sky then return end
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive() and L.HeldTool(me)) then
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
    if not tr.Hit then return end
    ghost:SetPos(tr.HitPos)
    ghost:SetAngles(Angle(0, L.PlaceYaw(me, L.buildTurn), 0))
    local mins = ghost:OBBMins()
    if mins.z < 0 then ghost:SetPos(tr.HitPos - Vector(0, 0, mins.z)) end
    local c = ok and GOOD or BAD
    render.SetBlend(0.35)
    render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255)
    ghost:DrawModel()
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
end)

-- The HUD while a build tool is out.
local WHITE, DIM, BLUE, AMBER, RED, SHADOW = Color(235, 238, 240), Color(170, 180, 186), Color(110, 190, 255), Color(255, 200, 100), Color(255, 90, 80), Color(0, 0, 0, 180)

function L.DrawBuildHUD(tool)
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local UI = Rhylib.UI
    local f = UI and UI.Font and UI.Font(15, 700) or "DermaDefaultBold"
    local fs = UI and UI.Font and UI.Font(12, 600) or "DermaDefault"
    local x, y = ScrW() * 0.5, ScrH() * 0.62
    local def = picked()
    if def then
        local cost = L.CostFor(me, def)
        local tr = aim(me)
        local have = L.SuppliesNear(tr.HitPos or me:GetPos())
        local line = def.name .. "  ·  " .. (cost > 0 and (cost .. " supplies (" .. have .. " here)") or "free")
        draw.SimpleTextOutlined(line, f, x, y, (cost > 0 and have < cost) and RED or WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    end
    local keys = tool.CanRepair and "RMB place · LMB build / repair · E / Q turn · R build menu · Z remove"
        or "RMB place · LMB build · E / Q turn · R build menu · Z remove"
    draw.SimpleTextOutlined(keys, fs, x, y + 20, DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    -- What you look at: a hologram's progress, a structure's health.
    local e = L.AimedStructure(me, L.structures)
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
    surface.SetDrawColor(0, 0, 0, 170)
    surface.DrawRect(bx - 1, by - 1, w + 2, h + 2)
    surface.SetDrawColor(col.r, col.g, col.b, 230)
    surface.DrawRect(bx, by, w * math.Clamp(frac, 0, 1), h)
    draw.SimpleTextOutlined(text, fs, x, by - 12, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
end
