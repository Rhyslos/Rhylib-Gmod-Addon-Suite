--[[
    Optics: macrobinoculars (kind 1) and the rangefinder (kind 2), worn on
    the helmet. The optics key raises them (they flip down on the model):
    zoom (mouse wheel), the range to what you look at, night vision (the
    flashlight key). No shooting or sprinting while you look through them.
    NW2Int rhylib_optics = the kind in use (0 = none). Both use the same
    viewer (cl_30_optics.lua); the rangefinder zooms half as far.
]]

local G = Rhylib.Gear

G.OPTICS_SLOT = { [1] = "binos", [2] = "rangefinder" }
-- Zoom per kind: { min, max, start }. The rangefinder is a weaker module: half the binoculars'.
G.ZOOM_RANGE = { [1] = { 2, 12, 4 }, [2] = { 1, 6, 2 } }

function G.OpticsAllowed(ply, kind)
    local slot = G.OPTICS_SLOT[kind]
    return slot ~= nil and G.Worn(ply, slot) ~= nil
end

function G.OpticsUp(ply)
    return ply:GetNW2Int("rhylib_optics", 0) ~= 0
end

local band, bnot, bor = bit.band, bit.bnot, bit.bor
local BLOCK = bor(IN_ATTACK, IN_ATTACK2, IN_SPEED)

Rhylib.Hook.Add("StartCommand", "gear.optics", function(ply, cmd)
    if ply:GetNW2Int("rhylib_optics", 0) ~= 0 then
        cmd:SetButtons(band(cmd:GetButtons(), bnot(BLOCK)))
    end
end)
