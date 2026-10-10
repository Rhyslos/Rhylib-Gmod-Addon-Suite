--[[
    Weapon effects on movement (shared, predicted).

    A weapon can slow its holder through SWEP:GetMoveMult(), for example
    the Z-6 while its barrels spin. Runs in SetupMove, so it's predicted
    and costs one weapon check per player per tick.
    Any weapon can use it: define SWEP:GetMoveMult() returning 0-1
    (rhylib_base returns SpinMoveMult while the barrels spin).
]]

Rhylib.Hook.Add("SetupMove", "weapons.move", function(ply, mv)
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep.GetMoveMult) then return end
    local mult = wep:GetMoveMult()
    if mult < 1 then
        mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mult)
    end
end)
