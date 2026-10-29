--[[
    One explosion helper for every blast the weapons make (server).

    W.Explode{ pos, radius, damage, attacker, inflictor, training,
               tier, reach, kind, effect, effectData, sound, shake,
               decal, decalFilter, knock }
      pos, radius, damage   the blast (util.BlastDamage, or W.TrainingBlast
                            when training: sim health only, no knockdown)
      attacker              who gets the credit (world when missing);
      inflictor             what did it (the attacker when missing)
      tier                  set = hook Rhylib.Explosion(pos, reach or radius,
                            tier, attacker, inflictor, kind) for comms
                            jammers (never for training blasts); nil = no hook
                            (the caller runs its own, e.g. grenades only
                            count when a player threw them)
      effect                util.Effect name ("Explosion" when nil, false =
                            none); effectData = { normal, magnitude, scale,
                            radius, flags, color } (only the given ones set)
      sound                 { path, level, pitch } via sound.Play at pos
      shake                 { amplitude, frequency, duration, radius }
      decal                 true = a "Scorch" decal under pos (decalFilter)
      knock                 false = this blast never knocks anyone down
                            (sv_60_knockdown checks W.explodeNoKnock);
                            default: blasts of knockMin damage or more do
    Example (a rocket): W.Explode({ pos = at, radius = 220, damage = 150,
        attacker = owner, inflictor = gun, tier = 2, kind = "rocket",
        effectData = { normal = n, magnitude = 1, scale = 1 } })
    Every site keeps its own numbers, effects and sounds and passes them in;
    extra effects (the HE charge's second effect, EMP rings) stay at the site.
]]

local W = Rhylib.Weapons

W.explodeNoKnock = false

function W.Explode(o)
    local pos = o.pos
    local attacker = IsValid(o.attacker) and o.attacker or game.GetWorld()
    local inflictor = IsValid(o.inflictor) and o.inflictor or attacker
    -- Effect first (as the sites did), then damage.
    if o.effect ~= false then
        local ed = EffectData()
        ed:SetOrigin(pos)
        local d = o.effectData
        if d then
            if d.normal then ed:SetNormal(d.normal) end
            if d.magnitude then ed:SetMagnitude(d.magnitude) end
            if d.scale then ed:SetScale(d.scale) end
            if d.radius then ed:SetRadius(d.radius) end
            if d.flags then ed:SetFlags(d.flags) end
            if d.color then ed:SetColor(d.color) end
        end
        util.Effect(o.effect or "Explosion", ed, true, true)
    end
    if o.sound then sound.Play(o.sound[1], pos, o.sound[2] or 100, o.sound[3] or 100) end
    if o.training then
        if W.TrainingBlast then W.TrainingBlast(pos, o.radius, o.damage, attacker, inflictor) end
    else
        if o.knock == false then W.explodeNoKnock = true end
        util.BlastDamage(inflictor, attacker, pos, o.radius, o.damage)
        W.explodeNoKnock = false
        if o.tier then
            hook.Run("Rhylib.Explosion", pos, o.reach or o.radius, o.tier, attacker, inflictor, o.kind)
        end
    end
    if o.shake then util.ScreenShake(pos, o.shake[1], o.shake[2], o.shake[3], o.shake[4]) end
    if o.decal then
        util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), o.decalFilter)
    end
end
