--[[
    Who is talking: replaces GMod's voice panels (Steam avatar + volume
    meter) with a list on the right side of the screen: the speaker's
    helmet portrait, name and job, in the house style. No volume meter.
    The stripe is white for local voice, else the radio channel's colour.

    Client only. Hooks: PlayerStartVoice / PlayerEndVoice (return true so
    GMod's own panel never shows) and HUDPaint "chat.voice". The list sits
    on the right side, 55% down the screen; newest speaker at the bottom.
    Uses Rhylib.UI.DrawPortrait (rhylib_core) and, when rhylib_radio is
    installed, Rhylib.Radio.SpeakerColor for the stripe.
]]

local UI = Rhylib.UI

local COL_BG = Color(14, 16, 15, 230)
local COL_EDGE = Color(0, 0, 0, 230)
local COL_LIGHT = Color(170, 176, 180, 70)
local COL_LOCAL = Color(233, 237, 239)   -- local voice; radio voices use their channel colour (rhylib_radio)
local COL_DIM = Color(140, 142, 136)

local FADE = 0.25      -- seconds to fade a row in or out
local speakers = {}   -- list of { ply, at, endAt }

local function find(ply)
    for i, s in ipairs(speakers) do
        if s.ply == ply then return s, i end
    end
end

-- Returning true skips GMod's own voice panel.
Rhylib.Hook.Add("PlayerStartVoice", "chat.voice", function(ply)
    if not IsValid(ply) then return true end
    local s = find(ply)
    if s then
        s.endAt = nil
    else
        speakers[#speakers + 1] = { ply = ply, at = RealTime() }
    end
    return true
end)

Rhylib.Hook.Add("PlayerEndVoice", "chat.voice", function(ply)
    local s = find(ply)
    if s and not s.endAt then s.endAt = RealTime() end
    return true
end)

-- In case the gamemode made its list before us.
Rhylib.Hook.Add("InitPostEntity", "chat.voice", function()
    if IsValid(g_VoicePanelList) then g_VoicePanelList:SetVisible(false) end
end)

Rhylib.Hook.Add("HUDPaint", "chat.voice", function()
    if #speakers == 0 then return end
    local now = RealTime()
    local s = ScrH() / 1080
    local rowH, gap = math.floor(44 * s), math.floor(5 * s)
    local w = math.floor(230 * s)
    local x = ScrW() - w - math.floor(24 * s)
    local y = math.floor(ScrH() * 0.55)
    local nameFont, jobFont = UI.Font(16, 700), UI.Font(12)

    local i = 1
    while i <= #speakers do
        local sp = speakers[i]
        local ply = sp.ply
        -- Gone, or the end event was missed: fade out.
        if IsValid(ply) and ply ~= LocalPlayer() and not sp.endAt and not ply:IsSpeaking() and now - sp.at > 0.5 then sp.endAt = now end
        local a = math.min(1, (now - sp.at) / FADE)
        if sp.endAt then a = math.min(a, 1 - (now - sp.endAt) / FADE) end
        if a <= 0 or not IsValid(ply) then
            table.remove(speakers, i)
        else
            local yy = y - (i - 1) * (rowH + gap)
            local A = 255 * a
            surface.SetDrawColor(COL_BG.r, COL_BG.g, COL_BG.b, COL_BG.a * a)
            surface.DrawRect(x, yy, w, rowH)
            -- Talking stripe on the left.
            local R = Rhylib.Radio
            local tc0 = R and R.SpeakerColor and R.SpeakerColor(ply) or COL_LOCAL
            surface.SetDrawColor(tc0.r, tc0.g, tc0.b, A)
            surface.DrawRect(x, yy, math.max(2, math.floor(3 * s)), rowH)
            local pad = math.floor(4 * s)
            local ps = rowH - pad * 2
            local px = x + math.floor(7 * s)
            UI.DrawPortrait(ply, px, yy + pad, ps, A)
            local tx = px + ps + math.floor(9 * s)
            local tc = team.GetColor(ply:Team())
            draw.SimpleText(ply:Nick(), nameFont, tx, yy + rowH * 0.36, Color(tc.r, tc.g, tc.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(team.GetName(ply:Team()) or "", jobFont, tx, yy + rowH * 0.70, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, A), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, COL_EDGE.a * a)
            surface.DrawOutlinedRect(x, yy, w, rowH)
            surface.SetDrawColor(COL_LIGHT.r, COL_LIGHT.g, COL_LIGHT.b, COL_LIGHT.a * a)
            surface.DrawLine(x + 1, yy + 1, x + w - 1, yy + 1)
            i = i + 1
        end
    end
end)
