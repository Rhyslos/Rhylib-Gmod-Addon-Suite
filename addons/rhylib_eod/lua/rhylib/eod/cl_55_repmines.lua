--[[
    Republic mines (client): blue outlines for every player, E on your own
    mine picks it up, and the count for the weapon's HUD line.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local BLUE = Color(80, 160, 255)
local list, listAt = {}, 0
local function repMines()
    local now = RealTime()
    if now - listAt > 0.5 then
        listAt = now
        list = ents.FindByClass("rhylib_rep_mine_planted")
    end
    return list
end

-- Your mines out, and how many you may have (for the weapon's HUD line).
-- E.RepCountClient() -> mines out, limit (client; for the HUD line).
function E.RepCountClient()
    local me = LocalPlayer()
    local n = 0
    for _, m in ipairs(repMines()) do
        if IsValid(m) and m:GetPlanter() == me then n = n + 1 end
    end
    local field = E.Skill(me, "eod_minefield")
    return n, field and (E.Cfg("repLimitField") or 6) or (E.Cfg("repLimit") or 3)
end

Rhylib.Hook.Add("PreDrawHalos", "eod.repmines", function()
    local mines = repMines()
    if #mines == 0 then return end
    local eye = EyePos()
    local near = {}
    for _, m in ipairs(mines) do
        if IsValid(m) and not m:GetNoDraw() and m:GetPos():DistToSqr(eye) < 2500 * 2500 then near[#near + 1] = m end
    end
    if #near > 0 then halo.Add(near, BLUE, 2, 2, 1, true, true) end
end)

-- Your own mine near where you look (within reach).
local function ownMineAtAim()
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    -- (looking at something else: a device, a bomb, a door, a body)
    if IsValid(tr.Entity) and not tr.Entity.IsRepMine then return nil end
    local best, bestD = nil, 24 * 24
    for _, m in ipairs(repMines()) do
        if IsValid(m) and m:GetPlanter() == ply and m:GetPos():DistToSqr(ply:GetPos()) < 140 * 140 then
            local d = m:GetPos():DistToSqr(tr.HitPos)
            if tr.Entity == m then d = 0 end
            if d < bestD then best, bestD = m, d end
        end
    end
    return best
end

-- E on your own mine: eod.reppick, and the +use is swallowed. Runs
-- early (priority -35) so it wins over other +use handlers.
Rhylib.Hook.Add("PlayerBindPress", "eod.reppick", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+use", 1, true) then return end
    local m = ownMineAtAim()
    if not m then return end
    Net.Start("eod.reppick")
    net.WriteEntity(m)
    net.SendToServer()
    return true
end, -35)

Rhylib.Hook.Add("HUDPaint", "eod.reppick", function()
    if #repMines() == 0 then return end
    local m = ownMineAtAim()
    if not m then return end
    local s = ScrH() / 1080
    local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
    draw.SimpleTextOutlined("E: PICK UP YOUR MINE", font, ScrW() * 0.5, ScrH() * 0.5 + 40 * s, BLUE,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 180))
end)
