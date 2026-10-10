--[[
    Client side of the lying ragdolls (sh_60_lying.lua): your own ragdoll
    isn't drawn in first person, ragdolls show their player's colour, and
    the engine's death ragdoll is hidden when the server ragdoll is the
    corpse.

    Soft knockdowns (sh_61_knock.lua): each client makes its own ragdoll
    from the player's pose; its pelvis is pulled towards the (hidden)
    player, so it lands where the server has them and every client sees
    it in about the same place. L.Ragdoll(ply) on the client returns it
    too (body camera). The player is hidden here, not on the server (a
    NoDraw player isn't sent to other clients at all).
]]

local L = Rhylib.Lying

--------------------------------------------------------------------------
-- Soft knockdown ragdolls
--------------------------------------------------------------------------

local softRags = {}   -- [ply] = client ragdoll
L.softRags = softRags

-- (wraps the shared L.Ragdoll: a server ragdoll first, else our own)
local serverRagdoll = L.Ragdoll
function L.Ragdoll(ply)
    local r = serverRagdoll(ply)
    if r then return r end
    r = softRags[ply]
    return IsValid(r) and r or nil
end

local PELVIS_UP = Vector(0, 0, 8)
local SNAP = 120   -- (further than this from the player: moved there at once)

local function eachPhys(rag, fn)
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then fn(phys, i) end
    end
end

local function makeSoft(ply)
    local rag = ClientsideRagdoll(ply:GetModel())
    if not IsValid(rag) then return nil end
    rag:SetSkin(ply:GetSkin())
    for _, bg in ipairs(ply:GetBodyGroups() or {}) do rag:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
    rag:SetColor(ply:GetColor())
    rag:SetMaterial(ply:GetMaterial())
    rag:SetNoDraw(false)
    rag.GetPlayerColor = function() return IsValid(ply) and ply:GetPlayerColor() or Vector(1, 1, 1) end
    rag.RenderOverride = function(self, flags)
        local me = LocalPlayer()
        if ply == me and not me:ShouldDrawLocalPlayer() then return end   -- (first person: you're inside it)
        self:DrawModel(flags)
    end
    -- From the player's pose and speed (a bone at the origin = no data).
    ply:SetupBones()
    local origin, vel = ply:GetPos(), ply:GetVelocity()
    rag:SetPos(origin)
    -- (the physics starts at the map origin: bring every part over first)
    eachPhys(rag, function(phys) phys:SetPos(phys:GetPos() + origin) end)
    eachPhys(rag, function(phys, i)
        local b = ply:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)))
        local m = b and ply:GetBoneMatrix(b)
        if m and m:GetTranslation():DistToSqr(origin) > 1 then
            phys:SetPos(m:GetTranslation())
            phys:SetAngles(m:GetAngles())
        end
        phys:SetVelocity(vel)
        phys:AddAngleVelocity(VectorRand() * 150)
        phys:Wake()
    end)
    local pb = rag:LookupBone("ValveBiped.Bip01_Pelvis")
    rag.rhylibPelvis = pb and rag:TranslateBoneToPhysBone(pb) or 0
    rag.rhylibMadeAt = RealTime()
    return rag
end

-- The player and the gun in hand are hidden while their ragdoll is out.
local function hideGun(ply, hide)
    local cur = hide and ply:GetActiveWeapon() or nil
    local old = ply.rhylibSoftGun
    if IsValid(old) and old ~= cur then old:SetNoDraw(false) end
    if IsValid(cur) then cur:SetNoDraw(true) end
    ply.rhylibSoftGun = IsValid(cur) and cur or nil
end

local function removeSoft(ply)
    local r = softRags[ply]
    if IsValid(r) then r:Remove() end
    softRags[ply] = nil
    if IsValid(ply) then
        hideGun(ply, false)
        ply:DrawShadow(true)
    end
end

Rhylib.Hook.Add("PrePlayerDraw", "core.lying.soft", function(ply)
    if IsValid(softRags[ply]) then return true end
end, -50)

-- The pelvis follows the player: their speed in the air, a pull towards
-- them along the ground (up/down is left to the physics there).
local function tether(ply, rag, ft)
    local phys = rag:GetPhysicsObjectNum(rag.rhylibPelvis or 0)
    if not IsValid(phys) then return end
    local target = ply:GetPos() + PELVIS_UP
    local d = target - phys:GetPos()
    if d:LengthSqr() > SNAP * SNAP then
        eachPhys(rag, function(p) p:SetPos(p:GetPos() + d) end)
        return
    end
    local air = not ply:OnGround()
    local want = ply:GetVelocity() + d * 5
    local v = phys:GetVelocity()
    local k = 1 - math.exp(-ft * (air and 10 or 5))
    v.x = v.x + (want.x - v.x) * k
    v.y = v.y + (want.y - v.y) * k
    if air then v.z = v.z + (want.z - v.z) * k end
    phys:SetVelocity(v)
end

Rhylib.Hook.Add("Think", "core.lying.soft", function()
    local ft = math.min(FrameTime(), 0.1)
    for _, ply in ipairs(player.GetAll()) do
        local want = ply:Alive() and not ply:IsDormant() and ply:GetNW2Bool("rhylib_knockSoft", false)
        local rag = softRags[ply]
        if want then
            if not IsValid(rag) then
                rag = makeSoft(ply)
                softRags[ply] = rag
            end
            if IsValid(rag) then
                tether(ply, rag, ft)
                hideGun(ply, true)
                ply:DrawShadow(false)
            end
        elseif rag then
            removeSoft(ply)
        end
    end
    for ply in pairs(softRags) do
        if not IsValid(ply) then removeSoft(ply) end
    end
end)

Rhylib.Hook.Add("PostCleanupMap", "core.lying.soft", function()
    for ply in pairs(softRags) do removeSoft(ply) end
end)

-- Set up each lying ragdoll once (checked a few times a second).
timer.Create("Rhylib.Lying", 0.25, 0, function()
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not rag.rhylibSetUp then
            local owner = L.Owner(rag)
            if owner then
                rag.rhylibSetUp = true
                rag.GetPlayerColor = function() return IsValid(owner) and owner:GetPlayerColor() or Vector(1, 1, 1) end
                rag.RenderOverride = function(self, flags)
                    local me = LocalPlayer()
                    if owner == me and IsValid(me) and not me:ShouldDrawLocalPlayer() and L.Ragdoll(me) == self then return end
                    -- (your own corpse while the death camera sits in it, cl_65_bodycam.lua)
                    if L.BodyCamOn and L.BodyCamOn() and IsValid(me) and me:GetNW2Entity("rhylib_corpse") == self then return end
                    self:DrawModel(flags)
                end
            end
        end
    end
end)

-- Died lying: the server ragdoll is the body; hide the engine's one.
Rhylib.Hook.Add("CreateClientsideRagdoll", "core.lying", function(ent, rag)
    if IsValid(ent) and ent:IsPlayer() and ent:GetNW2Bool("rhylib_ragCorpse") then rag:SetNoDraw(true) end
end)

Rhylib.Hook.Add("Think", "core.lying.corpse", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:Alive() and ply:GetNW2Bool("rhylib_ragCorpse") then
            local r = ply:GetRagdollEntity()
            if IsValid(r) and not r:GetNoDraw() then r:SetNoDraw(true) end
        end
    end
end)
