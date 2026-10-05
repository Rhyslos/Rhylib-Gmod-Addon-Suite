--[[
    Optics (server): gear.optics (kind 2 bits, 0 = down) raises or lowers
    them if that part is worn and you can use your hands.
]]

local G = Rhylib.Gear

Rhylib.Net.Register("gear.optics")
Rhylib.Net.Register("gear.visor")

-- Lying, downed or in a vehicle: no optics.
local function busy(ply)
    if not ply:Alive() or ply:InVehicle() then return true end
    local Med, L = Rhylib.Medical, Rhylib.Lying
    if Med and Med.IsDown and Med.IsDown(ply) then return true end
    if L and L.Is and L.Is(ply) then return true end
    return false
end

-- The sun visor down or up (one or the other with the optics: same mount).
function G.SetVisor(ply, on)
    on = on == true
    if on then G.SetOptics(ply, 0) end
    if ply:GetNW2Bool("rhylib_visorDown", false) == on then return end
    ply:SetNW2Bool("rhylib_visorDown", on)
    ply:EmitSound("buttons/lightswitch2.wav", 50, on and 95 or 80)
end

function G.SetOptics(ply, kind, fire)
    fire = kind ~= 0 and fire == true
    if kind ~= 0 and ply:GetNW2Bool("rhylib_visorDown", false) then ply:SetNW2Bool("rhylib_visorDown", false) end
    if ply:GetNW2Int("rhylib_optics", 0) == kind and ply:GetNW2Bool("rhylib_opticsFire", false) == fire then return end
    ply:SetNW2Int("rhylib_optics", kind)
    ply:SetNW2Bool("rhylib_opticsFire", fire)
    G.Apply(ply)
end

-- kind 2 bits (0 = down), weapon mode bit.
Rhylib.Net.Receive("gear.optics", function(ply)
    local kind, fire = net.ReadUInt(2), net.ReadBool()
    if kind ~= 0 and (busy(ply) or not G.OpticsAllowed(ply, kind)) then kind = 0 end
    G.SetOptics(ply, kind, fire)
end, { rate = 8, burst = 8 })

Rhylib.Net.Receive("gear.visor", function(ply)
    local on = net.ReadBool()
    if on and (busy(ply) or not G.Active(ply, "visor")) then on = false end
    G.SetVisor(ply, on)
end, { rate = 6, burst = 6 })

-- Put down when you go down, lie down or die (the visor goes up).
timer.Create("Rhylib.Gear.Optics", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNW2Int("rhylib_optics", 0) ~= 0 and busy(ply) then G.SetOptics(ply, 0) end
        if ply:GetNW2Bool("rhylib_visorDown", false) and (busy(ply) or not G.Active(ply, "visor")) then G.SetVisor(ply, false) end
    end
end)
Rhylib.Hook.Add("PlayerDeath", "gear.optics", function(ply)
    ply:SetNW2Int("rhylib_optics", 0)
    ply:SetNW2Bool("rhylib_opticsFire", false)
    ply:SetNW2Bool("rhylib_visorDown", false)
end)
