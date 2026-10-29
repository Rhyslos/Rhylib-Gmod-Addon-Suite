--[[
    Status text for the local player: stunned, cuffed (or bound by a
    bounty hunter), escorted, jailed, awaiting processing. One small plate
    under the crosshair area, house style. Counts down rhylib_cuffFree
    ("Free in m:ss if nobody comes for you") and rhylib_jailProc
    ("Processed automatically in m:ss").
    Client only. Reads the NW2 state from sh_00_config; no messages.
]]


local MP = Rhylib.MP
local UI = Rhylib.UI

local COL_BG = Color(14, 16, 15, 225)
local COL_EDGE = Color(0, 0, 0, 230)
local COL_STUN = Color(120, 200, 255)
local COL_CUFF = Color(239, 159, 39)

local function fmt(sec)
    sec = math.max(0, math.ceil(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

Rhylib.Hook.Add("HUDPaint", "mp.status", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local title, sub, col
    if MP.IsStunned(ply) then
        title, sub, col = "STUNNED", math.ceil(ply:GetNW2Float(Rhylib.NW.STUN_END, 0) - CurTime()) .. " s", COL_STUN
    elseif MP.IsCuffed(ply) then
        local by = MP.EscortedBy(ply)
        local free = ply:GetNW2Float("rhylib_cuffFree", 0)
        sub = by and ("Escorted by " .. by:Nick())
            or (free > 0 and ("Free in " .. fmt(free - CurTime()) .. " if nobody comes for you")) or ""
        title, col = ply:GetNW2Bool("rhylib_bound", false) and "BOUND" or "CUFFED", COL_CUFF
    elseif MP.IsJailed(ply) and ply:GetNW2Bool("rhylib_jailAwait", false) then
        local proc = ply:GetNW2Float("rhylib_jailProc", 0)
        title, sub, col = "AWAITING PROCESSING", proc > 0 and ("An MP can process you now · automatically in " .. fmt(proc - CurTime()))
            or "An MP at the jail terminal will process you out", COL_CUFF
    elseif MP.IsJailed(ply) then
        title, sub, col = "JAILED  " .. fmt(MP.JailLeft(ply)), ply:GetNW2String("rhylib_jailWhy", ""), COL_CUFF
    else
        return
    end
    local s = ScrH() / 1080
    local w, h = math.floor(320 * s), math.floor((sub ~= "" and 52 or 34) * s)
    local x, y = math.floor((ScrW() - w) * 0.5), math.floor(ScrH() * 0.68)
    surface.SetDrawColor(COL_BG)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(COL_EDGE)
    surface.DrawOutlinedRect(x, y, w, h)
    surface.SetDrawColor(col)
    surface.DrawRect(x + 1, y + 1, math.max(2, math.floor(3 * s)), h - 2)
    draw.SimpleText(title, UI.Font(16, 700), x + w * 0.5, y + math.floor(17 * s), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if sub ~= "" then
        draw.SimpleText(sub, UI.Font(13), x + w * 0.5, y + math.floor(37 * s), UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)
