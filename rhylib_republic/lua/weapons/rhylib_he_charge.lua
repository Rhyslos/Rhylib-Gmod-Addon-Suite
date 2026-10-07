--[[
    High explosive charge (2026-10-07, owner): the heavy demolition charge,
    the only thing that brings down large and map-wide comms jammers.
    4 inventory cells (2x2), stacks by 2.

    LMB / RMB: stick it to the surface you look at (like a breaching
    charge, reach weapons heReach). E while holding it: the timer window
    (rhylib_menus): set the timer (default heFuse 30 s) or "Sync" (no
    timer). A synced charge waits. Placing a charge with a timer starts
    its countdown and every synced charge of yours takes the same timer,
    so any number of charges go off together (rhylib_he_charge entity).
    The setting is the weapon's NetworkVar FuseSet (0 = sync) and is kept
    on the player for the next charge (ply.rhylibHeFuse).
]]

AddCSLuaFile()

DEFINE_BASECLASS("rhylib_grenade_base")

local Config = Rhylib.Config
Config.Register("weapons", "heFuse", 30, "High explosive charge: default timer (seconds)")
Config.Register("weapons", "heMinFuse", 5, "High explosive charge: shortest timer you can set (seconds)")
Config.Register("weapons", "heMaxFuse", 120, "High explosive charge: longest timer you can set (seconds, up to 255)")
Config.Register("weapons", "heReach", 90, "High explosive charge: how far you can reach to place it (units)")

SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "High explosive charge"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.GrenadeKind = "he"
SWEP.ImpactMode = false
SWEP.ThrowDelay = 1

SWEP.InvW = 2
SWEP.InvH = 2
SWEP.InvStack = 2
SWEP.InvWeight = 2.5

-- HL2's SLAM as the charge (ships with GMod; tune with rhylib_vm_editor /
-- rhylib_wm_editor).
SWEP.WorldModel = "models/weapons/w_slam.mdl"
SWEP.PropModel = "models/weapons/w_slam.mdl"
SWEP.PropColor = Color(255, 205, 140)
SWEP.PropScale = 1
SWEP.PropVMScale = 1

function SWEP:SetupDataTables()
    BaseClass.SetupDataTables(self)
    self:NetworkVar("Int", 0, "FuseSet")   -- seconds, 0 = sync (no timer)
end

local function clampFuse(v)
    v = math.floor(tonumber(v) or 0)
    if v <= 0 then return 0 end
    local lo = math.max(1, Config.Get("weapons", "heMinFuse") or 5)
    local hi = math.Clamp(Config.Get("weapons", "heMaxFuse") or 120, lo, 255)
    return math.Clamp(v, lo, hi)
end

function SWEP:Initialize()
    BaseClass.Initialize(self)
    if SERVER then self:SetFuseSet(clampFuse(Config.Get("weapons", "heFuse") or 30)) end
end

function SWEP:Deploy()
    local o = self:GetOwner()
    if SERVER and IsValid(o) and o.rhylibHeFuse then self:SetFuseSet(o.rhylibHeFuse) end
    return BaseClass.Deploy(self)
end

function SWEP:PrimaryAttack() self:PlaceCharge() end
function SWEP:SecondaryAttack() self:PlaceCharge() end

function SWEP:PlaceCharge()
    local o = self:GetOwner()
    if not IsValid(o) or not o:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    local tr = util.TraceLine({
        start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * (Config.Get("weapons", "heReach") or 90),
        filter = o, mask = MASK_SOLID,
    })
    local e = tr.Entity
    local ok = tr.Hit and not tr.HitSky and (tr.HitWorld or (IsValid(e) and not e:IsPlayer() and not e:IsNPC() and not e:IsNextBot()))
    if not ok then
        if SERVER then o:ChatPrint("Look at a wall, the floor or an object close by to place the charge") end
        return
    end
    self:SetNextPrimaryFire(CurTime() + self.ThrowDelay)
    self:SetNextSecondaryFire(CurTime() + self.ThrowDelay)
    self:SetLastThrow(CurTime())
    self:SetNeedDraw(true)
    self:SendWeaponAnim(ACT_VM_THROW)
    o:SetAnimation(PLAYER_ATTACK1)
    if CLIENT then return end
    local c = ents.Create("rhylib_he_charge")
    if not IsValid(c) then return end
    -- lying flat on the surface (the SLAM's top facing out)
    local ang = tr.HitNormal:Angle()
    ang:RotateAroundAxis(ang:Right(), -90)
    c:SetPos(tr.HitPos + tr.HitNormal * 1.5)
    c:SetAngles(ang)
    c.fuse = self:GetFuseSet()
    c.planter = o
    c.stuckTo = (IsValid(e) and not e:IsWorld()) and e or nil
    c:Spawn()
    o:EmitSound("weapons/slam/mine_mode.wav", 65, 100)
    self:UseOne(o)
end

if SERVER then
    -- Timer window: seconds (0 = sync) for the charge in hand.
    Rhylib.Net.Receive("he.set", function(ply)
        local v = clampFuse(net.ReadUInt(8))
        local w = ply:GetActiveWeapon()
        if not (IsValid(w) and w:GetClass() == "rhylib_he_charge") then return end
        w:SetFuseSet(v)
        ply.rhylibHeFuse = v
        ply:EmitSound("weapons/slam/mine_mode.wav", 55, 120)
    end, { rate = 6, burst = 6 })
end

if CLIENT then
    local function send(v)
        Rhylib.Net.Start("he.set")
        net.WriteUInt(math.Clamp(v, 0, 255), 8)
        net.SendToServer()
    end

    -- The timer window (rhylib_menus); without it E cycles 15 / 30 / 60 / sync.
    local win
    local function openWindow(w)
        local M = Rhylib.Menus
        local K = M and M.Kit
        if not K then
            local cur = w:GetFuseSet()
            send(cur == 0 and 15 or cur < 30 and 30 or cur < 60 and 60 or 0)
            return
        end
        if IsValid(win) then win:Remove() return end
        local lo = math.max(1, Config.Get("weapons", "heMinFuse") or 5)
        local hi = math.Clamp(Config.Get("weapons", "heMaxFuse") or 120, lo, 255)
        local pick = w:GetFuseSet() > 0 and w:GetFuseSet() or math.Clamp(Config.Get("weapons", "heFuse") or 30, lo, hi)
        local f = vgui.Create("EditablePanel")
        win = f
        M.prompts[f] = true
        f.OnRemove = function(self) M.prompts[self] = nil end
        f:SetSize(K.S(400), K.S(200))
        f:Center()
        f:MakePopup()
        f:DockPadding(K.S(14), K.S(42), K.S(14), K.S(14))
        function f:Paint(pw, ph)
            K.Plate(0, 0, pw, ph, { title = "High explosive charge", ticks = "all" })
            local now = IsValid(w) and w:GetFuseSet() or 0
            draw.SimpleText(now > 0 and ("Now: timer " .. now .. " s") or "Now: sync (no timer)", K.Font(13), K.S(14), K.S(54), Color(200, 205, 210), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        function f:Think()
            if not IsValid(w) or LocalPlayer():GetActiveWeapon() ~= w then self:Remove() end
        end
        local row = K.Row(f, "Timer (seconds)")
        row:Dock(TOP)
        row:DockMargin(0, K.S(22), 0, K.S(10))
        row.right:SetWide(K.S(210))
        local s = K.Slider(row.right, lo, hi, 0, function() return pick end, function(v) pick = v end)
        s:Dock(FILL)
        local btns = vgui.Create("DPanel", f)
        btns:Dock(BOTTOM)
        btns:SetTall(K.S(34))
        btns.Paint = nil
        local set = K.Button(btns, "Set timer", function() send(pick) f:Remove() end, { accent = true,
            tooltip = "Placing this charge starts the countdown, and your synced charges take the same timer" })
        set:Dock(RIGHT)
        set:SetWide(K.S(130))
        local sync = K.Button(btns, "Sync", function() send(0) f:Remove() end, {
            tooltip = "No timer: the charge waits and goes off with the next charge you place with a timer" })
        sync:Dock(RIGHT)
        sync:SetWide(K.S(110))
        sync:DockMargin(0, 0, K.S(8), 0)
        local close = K.Button(btns, "Close", function() f:Remove() end)
        close:Dock(LEFT)
        close:SetWide(K.S(90))
    end

    -- E with the charge in hand opens the window (before the interaction wheel).
    Rhylib.Hook.Add("PlayerBindPress", "weapons.hecharge", function(ply, bind, pressed)
        if not pressed or not string.find(bind, "+use", 1, true) then return end
        local w = ply:GetActiveWeapon()
        if not (IsValid(w) and w:GetClass() == "rhylib_he_charge") then return end
        -- (E on a player / downed body / door / anything close stays E)
        local Wh = Rhylib.Menus and Rhylib.Menus.Wheel
        if Wh and Wh.FindTarget and Wh.FindTarget(ply) then return end
        local tr = ply:GetEyeTrace()
        if IsValid(tr.Entity) and tr.HitPos:DistToSqr(ply:GetShootPos()) < 100 * 100 then return end
        openWindow(w)
        return true
    end, -30)

    function SWEP:DrawHUD()
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        local v = self:GetFuseSet()
        local text = v > 0 and ("HE CHARGE  ·  TIMER " .. v .. " S  ·  E: SET") or "HE CHARGE  ·  SYNC (NO TIMER)  ·  E: SET"
        local x, y = ScrW() * 0.5, ScrH() * 0.55
        draw.SimpleTextOutlined(text, font, x, y, Color(235, 205, 150, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
        local n = LocalPlayer():GetNW2Int("rhylib_heSynced", 0)
        if n > 0 then
            draw.SimpleTextOutlined(n .. " synced charge" .. (n == 1 and "" or "s") .. " waiting for a timer", font, x, y + ScrH() * 0.022,
                Color(200, 205, 210, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
        end
    end
end
