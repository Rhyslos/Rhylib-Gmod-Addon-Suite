--[[
    Med bay, client: the chemistry bench menu (chem.open -> recipes,
    chem.make), the mixing progress bar, the bacta tank screen, and the
    floating labels over tanks and benches.
]]

local Med = Rhylib.Medical
local UI = Rhylib.UI
local C = UI.Colors

local function S(n) return math.floor(n * ScrH() / 1080 + 0.5) end

local function carried(id)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.byUid) then return 0 end
    local n = 0
    for _, o in pairs(Inv.byUid) do
        if o.id == id then n = n + (o.count or 1) end
    end
    return n
end

--------------------------------------------------------------------------
-- Labels over med bay entities (close up only)
--------------------------------------------------------------------------

local LABEL_RANGE = 250
function Med.DrawEntLabel(ent, title, sub)
    local eye = EyePos()
    local top = ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z + 12)
    if eye:DistToSqr(top) > LABEL_RANGE * LABEL_RANGE then return end
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(top, ang, 0.08)
        draw.SimpleTextOutlined(title, UI.Font(44, 700), 0, 0, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined(sub, UI.Font(30, 500), 0, 6, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 2, Color(0, 0, 0, 200))
    cam.End3D2D()
end

--------------------------------------------------------------------------
-- Chemistry bench menu
--------------------------------------------------------------------------

local openM
Rhylib.Net.Receive("chem.open", function()
    local bench = net.ReadEntity()
    if not IsValid(bench) then return end
    if IsValid(openM) then openM:Remove() end
    local Kit = Rhylib.Menus and Rhylib.Menus.Kit
    local m = Kit and Kit.Menu() or DermaMenu()
    openM = m
    local have = carried(Med.SUPPLIES)
    local batch = Med.Skill(LocalPlayer(), "batch_brewing")
    m:AddOption("Medical supplies: " .. have .. (batch and "  ·  batches make twice as much" or ""), function() end)
    m:AddSpacer()
    for i, r in ipairs(Med.Cfg("chemRecipes") or {}) do
        local def = Rhylib.Items and Rhylib.Items.Get(r[1])
        if def then
            local cost = tonumber(r[2]) or 1
            local amount = tonumber(r[3]) or 1
            local o = m:AddOption(def.name .. (amount > 1 and (" ×" .. amount) or "") .. "  ·  " .. cost .. " suppl" .. (cost == 1 and "y" or "ies"), function()
                if not IsValid(bench) then return end
                Rhylib.Net.Start("chem.make")
                net.WriteEntity(bench)
                net.WriteUInt(i, 5)
                net.SendToServer()
            end)
            if have < cost and o.SetTextColor then o:SetTextColor(C.textDim) end
        end
    end
    m:Open(ScrW() * 0.5 + S(24), ScrH() * 0.5)
end)

Rhylib.Hook.Add("InitPostEntity", "medical.chemmenu", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.RegisterCloser then
        Menus.RegisterCloser("chem", function()
            if IsValid(openM) then openM:Remove() return true end
            return false
        end)
    end
end)

--------------------------------------------------------------------------
-- HUD: mixing and the tank
--------------------------------------------------------------------------

local COL_BACTA = Color(90, 170, 240)

local function bar(x, y, w, h, frac, col)
    surface.SetDrawColor(255, 255, 255, 28)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, math.floor(w * math.Clamp(frac, 0, 1) + 0.5), h)
end

local function text(str, size, x, y, col, weight)
    draw.SimpleTextOutlined(str, UI.Font(size, weight or 500), x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
end

Rhylib.Hook.Add("HUDPaint", "medical.medbay", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local W, H = ScrW(), ScrH()

    local e = ply:GetNW2Float("rhylib_craftE", 0)
    if e > 0 then
        local s = ply:GetNW2Float("rhylib_craftS", 0)
        local w = S(260)
        text("Mixing " .. ply:GetNW2String("rhylib_craftN", ""), 15, W / 2, H * 0.58, C.text, 600)
        bar(W / 2 - w / 2, H * 0.58 + S(14), w, S(4), (CurTime() - s) / math.max(0.01, e - s), C.good)
        text("Stay at the bench", 12, W / 2, H * 0.58 + S(30), C.textDim)
    end

    if Med.InTank(ply) then
        local w = S(300)
        local y = H * 0.7
        text("BACTA TANK", 14, W / 2, y, COL_BACTA, 700)
        text("Health " .. ply:Health() .. " / " .. ply:GetMaxHealth(), 15, W / 2, y + S(22), C.text, 600)
        bar(W / 2 - w / 2, y + S(36), w, S(4), ply:Health() / math.max(1, ply:GetMaxHealth()), COL_BACTA)
        local jump = string.upper(input.LookupBinding("+jump") or "SPACE")
        text(jump .. " or E to climb out", 12, W / 2, y + S(54), C.textDim)
    end
end)

-- A soft blue tint inside the tank.
Rhylib.Hook.Add("RenderScreenspaceEffects", "medical.tank", function()
    local ply = LocalPlayer()
    if not (IsValid(ply) and Med.InTank(ply)) then return end
    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0.02, ["$pp_colour_addb"] = 0.08,
        ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0.7,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
    })
end)
