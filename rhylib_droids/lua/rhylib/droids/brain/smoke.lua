--[[
    Droid brain part (server): firing into smoke.

    A droid that lost its target because smoke is in the way (ENT:CanSee
    notes it in self.smokeHid) and is near a commander that still has a
    free slot (D.SmokeSlot: smokeSuppressors droids per commander) fires
    bursts at the spot it last saw the target, at blind-fire spread
    (blindSpread), for up to smokeSuppressTime seconds. It stops as soon as
    the target is in sight again (the fight goes on normally), the target
    is down, dead or gone, the commander is gone, it wants cover (shot at,
    retreat) or someone else is in sight. Stopping early frees its slot.
    No extra traces: one sight check per burst plus the normal throttled
    Look.

    ENT:SuppressSmoke(t) -> true if it suppressed (the caller then looks
    for targets again). Yields (call it inside the brain coroutine).
]]

return function(ENT, env)
    local D, valid = env.D, env.valid

    function ENT:SuppressSmoke(t)
        local aim = self.lastSeen
        if not aim or not D.SmokeSlot(self) then return false end
        local k = self:Kind()
        local stop = CurTime() + D.Cfg("smokeSuppressTime") * math.Rand(0.8, 1.1)
        local wait = 60 / math.max(D.Cfg(k.rpm), 1)
        local spot = aim + Vector(0, 0, 40)
        while CurTime() < stop and self:Health() > 0 do
            if not valid(t) then break end                    -- (down, dead or gone)
            if self:CanSee(t) then break end                  -- (back in sight: fight it)
            if not D.SmokeSlot(self) then break end           -- (commander gone)
            if self:WantsCover() then break end               -- (shot at / retreat)
            local seen = self:Look()
            if seen and seen ~= t then break end              -- (someone else in sight)
            self:Face(aim, 0.2)
            for _ = 1, math.random(k.burst[1], k.burst[2]) do
                self:FireAtPos(spot, 0, D.Cfg("blindSpread"))
                self:Face(aim, wait)
            end
            self:Face(aim, math.Rand(0.5, 1.1))
        end
        D.SmokeSlotFree(self)
        self.smokeHid = nil
        self.nextLook = 0
        return true
    end
end
