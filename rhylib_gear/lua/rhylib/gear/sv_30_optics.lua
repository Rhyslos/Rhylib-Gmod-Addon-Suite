--[[
    Optics (server): gear.optics (kind 2 bits, 0 = down) raises or lowers
    them if that part is worn and you can use your hands.
]]

local G = Rhylib.Gear

Rhylib.Net.Register("gear.optics")

-- Lying, downed or in a vehicle: no optics.
local function busy(ply)
    if not ply:Alive() or ply:InVehicle() then return true end
    local Med, L = Rhylib.Medical, Rhylib.Lying
    if Med and Med.IsDown and Med.IsDown(ply) then return true end
    if L and L.Is and L.Is(ply) then return true end
    return false
end

function G.SetOptics(ply, kind)
    if ply:GetNW2Int("rhylib_optics", 0) == kind then return end
    ply:SetNW2Int("rhylib_optics", kind)
    G.Apply(ply)
end

Rhylib.Net.Receive("gear.optics", function(ply)
    local kind = net.ReadUInt(2)
    if kind ~= 0 and (busy(ply) or not G.OpticsAllowed(ply, kind)) then kind = 0 end
    G.SetOptics(ply, kind)
end, { rate = 6, burst = 6 })

-- Put down when you go down, lie down or die.
timer.Create("Rhylib.Gear.Optics", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNW2Int("rhylib_optics", 0) ~= 0 and busy(ply) then G.SetOptics(ply, 0) end
    end
end)
Rhylib.Hook.Add("PlayerDeath", "gear.optics", function(ply) ply:SetNW2Int("rhylib_optics", 0) end)
