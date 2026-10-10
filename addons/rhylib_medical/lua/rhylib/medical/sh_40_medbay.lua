--[[
    Med bay, shared: who is in a bacta tank (NW2Entity rhylib_tank on the
    player) or on a med sofa (NW2Entity rhylib_sofa). Inside / lying there,
    no shooting and no walking (StartCommand "medical.tank"); Jump or E
    gets out (sv_40_medbay.lua).
]]

local Med = Rhylib.Medical

-- Med.InTank(ply): the bacta tank ply is in, or nil.
function Med.InTank(ply)
    local t = ply:GetNW2Entity("rhylib_tank")
    return IsValid(t) and t or nil
end

local band, bnot, bor = bit.band, bit.bnot, bit.bor
local STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_DUCK, IN_SPEED, IN_WALK)

-- Med.OnSofa(ply): the med sofa ply lies on, or nil.
function Med.OnSofa(ply)
    local s = ply:GetNW2Entity("rhylib_sofa")
    return IsValid(s) and s or nil
end

Rhylib.Hook.Add("StartCommand", "medical.tank", function(ply, cmd)
    if not (Med.InTank(ply) or Med.OnSofa(ply)) then return end
    cmd:SetButtons(band(cmd:GetButtons(), bnot(STRIP)))
    cmd:ClearMovement()
end)
