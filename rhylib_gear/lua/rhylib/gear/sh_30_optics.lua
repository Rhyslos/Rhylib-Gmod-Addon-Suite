--[[
    Optics: macrobinoculars (kind 1) and the rangefinder (kind 2), worn on
    the helmet, and handheld binoculars (kind 3, the rhylib_binoculars
    weapon: right or left click raises / lowers them, zoom to 20x). The optics key raises them (they flip down on the model):
    zoom (mouse wheel), the range to what you look at, night vision (the
    flashlight key). No shooting or sprinting while you look through them;
    weapon mode (mode key) keeps them down with night vision but gives the
    normal view and HUD so you can fight.
    NW2Int rhylib_optics = the kind in use (0 = none). Both use the same
    viewer (cl_30_optics.lua); the rangefinder zooms half as far.
    Shared: the state readers below and the StartCommand block (it runs on
    both realms so prediction agrees). Server side is sv_30_optics.lua.
]]

local G = Rhylib.Gear

G.OPTICS_SLOT = { [1] = "binos", [2] = "rangefinder" }
-- Kind 3: handheld binoculars (SWEP rhylib_binoculars), held in the hands
-- instead of worn: allowed while they're the weapon out.
G.HELD_BINOCS = "rhylib_binoculars"
-- Zoom per kind: { min, max, start }. The rangefinder is a weaker module:
-- half the macrobinoculars'. The handheld binoculars go furthest.
G.ZOOM_RANGE = { [1] = { 2, 12, 4 }, [2] = { 1, 6, 2 }, [3] = { 2, 20, 4 } }

-- G.OpticsAllowed(ply, kind): the part for that kind is worn and active
-- (kind 3: the handheld binoculars are the weapon out).
function G.OpticsAllowed(ply, kind)
    if kind == 3 then
        local w = ply:GetActiveWeapon()
        return IsValid(w) and w:GetClass() == G.HELD_BINOCS
    end
    local slot = G.OPTICS_SLOT[kind]
    return slot ~= nil and G.Active(ply, slot)
end

-- The sun visor down: a red tactical view over the normal HUD (from the
-- clones' helmet view): NW2Bool rhylib_visorDown.
-- Separate from rhylib_optics, so you keep shooting and the HUD stays.
function G.VisorDown(ply)
    return ply:GetNW2Bool("rhylib_visorDown", false)
end

-- G.OpticsUp(ply): optics of any kind up (looking or weapon mode).
function G.OpticsUp(ply)
    return ply:GetNW2Int("rhylib_optics", 0) ~= 0
end

-- Up and looking through them (not in weapon mode: NW2Bool rhylib_opticsFire,
-- where you shoot with the normal HUD and 1x view, night vision still on).
function G.Looking(ply)
    return ply:GetNW2Int("rhylib_optics", 0) ~= 0 and not ply:GetNW2Bool("rhylib_opticsFire", false)
end

local band, bnot, bor = bit.band, bit.bnot, bit.bor
local BLOCK = bor(IN_ATTACK, IN_ATTACK2, IN_SPEED)

-- While looking: no primary / secondary attack and no sprint.
Rhylib.Hook.Add("StartCommand", "gear.optics", function(ply, cmd)
    if G.Looking(ply) then
        cmd:SetButtons(band(cmd:GetButtons(), bnot(BLOCK)))
    end
end)
