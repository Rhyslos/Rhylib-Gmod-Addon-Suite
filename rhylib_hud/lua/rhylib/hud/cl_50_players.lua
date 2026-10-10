--[[
    Other players (client):
      - Look at someone within range to see their name (in their team
        colour), job with DarkRP, and health and armour bars.
      - Icons above heads while someone is talking on voice (bars that
        move with their voice volume) or typing in chat (bouncing dots).

    Target info uses the eye trace GMod already makes each frame. Icons
    loop over the players once per frame and skip anyone far away,
    dead or not being networked to you.

    Ranges are config settings (module "hud"): targetRange (name card)
    and iconRange (head icons). Armour comes from the NW2Int
    "rhylib_armor" that sv_10_armor.lua keeps up to date; the bar is
    drawn against 100. Cloaked staff (NW2Bool "rhylib_cloak",
    rhylib_admin) get no card and no icons. Typing also counts
    rhylib_chat's NW2Bool "rhylib_typing".
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI
local Config = Rhylib.Config

-- Head bone id per model, so LookupBone runs once per model, not per frame.
local headBone = {}
local UP_PLATE, UP28 = Vector(0, 0, 14), Vector(0, 0, 28)

local function headPos(ply)
    local mdl = ply:GetModel() or ""
    local bone = headBone[mdl]
    if bone == nil then
        bone = ply:LookupBone("ValveBiped.Bip01_Head1") or false
        headBone[mdl] = bone
    end
    local pos = bone and ply:GetBonePosition(bone)
    return pos or ply:EyePos()
end

local function jobOf(ply)
    if ply.getDarkRPVar then return ply:getDarkRPVar("job") end
    return nil
end

--------------------------------------------------------------------------
-- Name, health and armour when you look at someone
--------------------------------------------------------------------------

-- The card stays up 0.25 s after the trace leaves the player and fades
-- in/out over ~1/6 s, so a quick glance doesn't flicker.
local target, seenAt, fade = nil, 0, 0
local nameCol, outlineCol = Color(255, 255, 255), Color(0, 0, 0)

Rhylib.Hook.Add("HUDPaint", "hud.target", function()
    if HUD.Hidden() then return end
    local me = LocalPlayer()
    local range = Config.Get("hud", "targetRange")

    local ent = me:GetEyeTrace().Entity
    -- (invisible staff, rhylib_admin: no name card)
    if IsValid(ent) and ent:IsPlayer() and ent:Alive() and not ent:GetNW2Bool("rhylib_cloak") and ent:GetPos():DistToSqr(me:GetPos()) < range * range then
        target, seenAt = ent, RealTime()
    end

    local visible = IsValid(target) and target:Alive() and RealTime() - seenAt < 0.25
    fade = math.Approach(fade, visible and 1 or 0, FrameTime() * 6)
    if fade <= 0 or not IsValid(target) then return end

    -- (anchored on the interpolated eye position: the head bone's cached
    -- matrix trailed behind moving players and the plate lagged, owner 2026-10-07)
    local scr = (target:EyePos() + UP_PLATE):ToScreen()
    if not scr.visible then return end

    local s = HUD.Scale()
    local C = HUD.Colors
    local a = math.floor(255 * fade)
    local x, y = math.floor(scr.x), math.floor(scr.y)

    local job = jobOf(target)
    local barW, barH = math.floor(120 * s), math.max(3, math.floor(5 * s))
    local armor = target:GetNW2Int("rhylib_armor", 0)

    -- A dark plate behind it all, in the HUD's style.
    local nameFont = UI.Font(20)
    surface.SetFont(nameFont)
    local nameW = surface.GetTextSize(target:Nick())
    local plateW = math.max(nameW, barW) + math.floor(16 * s)
    local plateH = (armor > 0 and (barH + math.floor(3 * s)) or 0) + barH + math.floor(6 * s)
        + (job and math.floor(17 * s) or 0) + math.floor(22 * s) + math.floor(8 * s)
    HUD.Frame(x - plateW * 0.5, y - plateH + math.floor(4 * s), plateW, plateH, { alpha = a * 0.9, ticks = false })

    -- Stack upward from the head: bars at the bottom, name on top.
    local cy = y
    if armor > 0 then
        HUD.Bar(x - barW * 0.5, cy - barH, barW, barH, armor / 100, C.armor, a)
        cy = cy - barH - math.floor(3 * s)
    end
    local hp, maxHp = math.max(target:Health(), 0), math.max(target:GetMaxHealth(), 1)
    HUD.Bar(x - barW * 0.5, cy - barH, barW, barH, hp / maxHp, hp / maxHp < 0.3 and C.healthLow or C.health, a)
    cy = cy - barH - math.floor(6 * s)

    if job then
        HUD.Text(job, 15, x, cy, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, a)
        cy = cy - math.floor(17 * s)
    end
    local tc = team.GetColor(target:Team())
    nameCol.r, nameCol.g, nameCol.b, nameCol.a = tc.r, tc.g, tc.b, a
    outlineCol.a = a * 0.6
    draw.SimpleTextOutlined(target:Nick(), nameFont, x, cy, nameCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, outlineCol)
end)

--------------------------------------------------------------------------
-- Speaking and typing icons above heads
--------------------------------------------------------------------------

local COL_BG = Color(20, 22, 20, 200)
local COL_VOICE = Color(151, 196, 89)
local COL_TYPE = Color(228, 227, 220)
local R = 24  -- icon radius in 3D2D units

local function drawVoice(ply, t)
    draw.RoundedBox(R, -R, -R, R * 2, R * 2, COL_BG)
    local vol = math.Clamp(ply:VoiceVolume() * 3, 0.15, 1)
    surface.SetDrawColor(COL_VOICE)
    for i = -1, 1 do
        local wobble = 0.6 + 0.4 * math.abs(math.sin(t * 9 + i * 1.7))
        local h = math.max(6, 30 * vol * wobble)
        surface.DrawRect(i * 11 - 3, -h * 0.5, 6, h)
    end
end

local function drawTyping(t)
    draw.RoundedBox(R, -R, -R, R * 2, R * 2, COL_BG)
    surface.SetDrawColor(COL_TYPE)
    for i = -1, 1 do
        local bounce = math.max(0, math.sin(t * 6 - (i + 1) * 0.9)) * 6
        surface.DrawRect(i * 12 - 3, -3 - bounce, 6, 6)
    end
end

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "hud.icons", function(depth, skybox)
    if depth or skybox then return end
    local me = LocalPlayer()
    local eye = EyePos()
    local range = Config.Get("hud", "iconRange")
    local rangeSqr = range * range
    local ang = Angle(0, EyeAngles().y - 90, 90)
    local t = RealTime()

    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and not ply:IsDormant() and (ply ~= me or me:ShouldDrawLocalPlayer()) and not ply:GetNW2Bool("rhylib_cloak") then
            local speaking, typing = ply:IsSpeaking(), ply:IsTyping() or ply:GetNW2Bool("rhylib_typing")  -- (the second: rhylib_chat)
            if (speaking or typing) and ply:GetPos():DistToSqr(eye) < rangeSqr then
                local pos = headPos(ply) + UP28
                cam.Start3D2D(pos, ang, 0.12)
                    if speaking then drawVoice(ply, t) else drawTyping(t) end
                cam.End3D2D()
            end
        end
    end
end)
