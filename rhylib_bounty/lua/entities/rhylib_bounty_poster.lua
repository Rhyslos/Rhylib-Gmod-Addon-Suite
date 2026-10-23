--[[
    Wanted poster (rhylib_bounty): a board that shows the open bounties one
    at a time (every 6 s): the target's face (their model), name, reward
    and dead / alive. Staff place it with the toolgun (Bounty) and keep it
    with the Permanent tool. Reads the client's copy of the board
    (Rhylib.Bounty.board, from bounty.list).
    Model: config bounty posterModel.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Wanted poster"
ENT.Category = "Rhy's Bounty hunters"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelFromConfig = true

function ENT:WantedModel()
    local m = Rhylib.Config.Get("bounty", "posterModel")
    if isstring(m) and (util.IsValidModel(m) or (CLIENT and file.Exists(m, "GAME"))) then return m end
    return "models/hunter/plates/plate1x1.mdl"
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self:WantedModel())
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

-- Face the board toward `normal` (a wall's), upright: the plate's thin
-- axis (Up) along the normal, its Forward straight up. Used by the toolgun.
function ENT.FaceAngles(normal)
    local m = Matrix()
    local up = Vector(0, 0, 1)
    if math.abs(normal.z) > 0.9 then normal = Vector(1, 0, 0) end
    local n = Vector(normal.x, normal.y, 0)
    n:Normalize()
    m:SetForward(up)
    m:SetUp(n)
    m:SetRight(up:Cross(n))
    return m:GetAngles()
end

if CLIENT then
    local W, H, SCALE = 360, 480, 0.09   -- (about 32 x 43 game units on the 47 x 47 plate)

    function ENT:Draw()
        self:DrawModel()
        local me = LocalPlayer()
        if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 1200 * 1200 then return end
        -- The face is the plate's Up side; across = its Right, down = -Forward.
        local F, R, U = self:GetForward(), self:GetRight(), self:GetUp()
        if (me:EyePos() - self:GetPos()):Dot(U) < 0 then return end   -- (back side)
        local m = Matrix()
        m:SetForward(R)
        m:SetRight(-F)
        m:SetUp(U)
        local centre = self:WorldSpaceCenter() + U * (self:OBBMaxs().z + 0.3)
        local origin = centre - R * (W * SCALE * 0.5) + F * (H * SCALE * 0.5)
        cam.Start3D2D(origin, m:GetAngles(), SCALE)
            self:DrawPoster()
        cam.End3D2D()
    end

    function ENT:DrawPoster()
        local B = Rhylib.Bounty
        local list = B and B.board or {}
        surface.SetDrawColor(232, 220, 190, 255)
        surface.DrawRect(0, 0, W, H)
        surface.SetDrawColor(120, 90, 50, 255)
        surface.DrawOutlinedRect(6, 6, W - 12, H - 12, 4)
        draw.SimpleText("WANTED", Rhylib.UI.Font(64, 900), W * 0.5, 50, Color(90, 40, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if #list == 0 then
            draw.SimpleText("No open bounties", Rhylib.UI.Font(26, 600), W * 0.5, H * 0.5, Color(90, 60, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end
        local b = list[math.floor(CurTime() / 6) % #list + 1]
        surface.SetDrawColor(60, 50, 40, 255)
        surface.DrawRect(W * 0.5 - 110, 92, 220, 220)
        local who = b.tidx > 0 and Entity(b.tidx) or nil
        if not IsValid(who) then who = b.model end
        if who and who ~= "" then Rhylib.UI.DrawPortrait(who, W * 0.5 - 106, 96, 212, 255) end
        draw.SimpleText(b.name, Rhylib.UI.Font(36, 800), W * 0.5, 345, Color(40, 25, 15), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local label = b.mode == "dead" and "DEAD" or (b.mode == "alive" and "ALIVE" or "DEAD OR ALIVE")
        draw.SimpleText(label, Rhylib.UI.Font(30, 800), W * 0.5, 385, Color(150, 30, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(B.FormatMoney(b.reward), Rhylib.UI.Font(40, 900), W * 0.5, 430, Color(40, 25, 15), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText((list[1] and #list or 0) .. " open  ·  Bounty Office", Rhylib.UI.Font(16, 500), W * 0.5, H - 20, Color(90, 60, 40), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
