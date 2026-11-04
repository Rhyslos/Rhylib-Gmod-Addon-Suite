--[[
    Signal flares (server): Flare mode on a gun with SWEP.FlareGun (the
    DC-17; rhylib_base ToggleFlareMode / LoadFlare / FireFlare).

    Nets (client -> server):
      wep.flaremode  empty: Flare mode on / off (the fire-mode wheel).
                     Rate 4/s.
      wep.flareload  UInt 2 colour (0-3 = W.FLARE_COLORS 1-4): load a flare
                     of that colour (R in flare mode). The weapon checks
                     flare mode, the owner's cooldown (NW2Float
                     rhylib_flareAt) and that it isn't already loading.
                     Rate 4/s.

    W.LaunchFlare(ply, wep, colour): fires the loaded flare where the
    player aims at weapons flareSpeed (entities/rhylib_flare.lua: it lights
    itself, hangs and drifts down, and draws idle droid patrols) and starts
    the cooldown (weapons flareCooldown).
]]

local W = Rhylib.Weapons

function W.LaunchFlare(ply, wep, idx)
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive() and W.FLARE_COLORS[idx]) then return end
    if ply:GetNW2Float("rhylib_flareAt", 0) > CurTime() then return end   -- (still cooling down)
    local dir = ply:GetAimVector()
    local start = ply:GetShootPos() + dir * 24
    -- (not inside a wall right in front of you)
    local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = start, filter = ply, mask = MASK_SOLID })
    if tr.Hit then start = tr.HitPos - dir * 6 end
    local f = ents.Create("rhylib_flare")
    if not IsValid(f) then return end
    f:SetPos(start)
    f:SetOwner(ply)
    f:Spawn()
    f:SetColorIndex(idx)
    f:Launch(start, dir * Rhylib.Config.Get("weapons", "flareSpeed") + ply:GetVelocity() * 0.5)
    ply:SetNW2Float("rhylib_flareAt", CurTime() + math.max(1, Rhylib.Config.Get("weapons", "flareCooldown")))
end

local function flareGun(ply)
    local wep = IsValid(ply) and ply:Alive() and ply:GetActiveWeapon()
    if IsValid(wep) and wep.IsRhylib and wep.FlareGun then return wep end
end

Rhylib.Net.Receive("wep.flaremode", function(ply)
    local wep = flareGun(ply)
    if wep and wep.ToggleFlareMode then wep:ToggleFlareMode() end
end, { rate = 4, burst = 3 })

Rhylib.Net.Receive("wep.flareload", function(ply)
    local idx = net.ReadUInt(2) + 1
    local wep = flareGun(ply)
    local S = Rhylib.State
    if S and S.CanAct and not S.CanAct(ply) then return end
    if wep and wep.LoadFlare then wep:LoadFlare(idx) end
end, { rate = 4, burst = 3 })
