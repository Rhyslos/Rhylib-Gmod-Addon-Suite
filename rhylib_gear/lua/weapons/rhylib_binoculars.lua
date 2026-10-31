--[[
    Binoculars (handheld): held in the hands like a weapon, 1x2 upright in
    the inventory. Right or left click raises them and lowers them again:
    the same viewer as the helmet macrobinoculars (rhylib_gear optics kind
    3): zoom with the mouse wheel up to 20x, the range to what you look at,
    night vision on the flashlight key. The helmet gear key (L) only puts
    them down. Switching weapons puts them away. Clicks are read by a client
    Think hook (works in single player too, where SWEP:Think doesn't run
    on the client).

    Realm: shared SWEP. Needs rhylib_gear's optics (this addon). From the
    gear cabinet (rhylib_armoury config gearStock). Placeholder model.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Binoculars"
SWEP.Category = "Rhy's Equipment"
SWEP.Spawnable = true
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_lab/binderblue.mdl"   -- placeholder
SWEP.UseHands = true
SWEP.HoldType = "camera"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 2
SWEP.InvWeight = 0.8
SWEP.InvCategory = "gear"
SWEP.InvHolster = false

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end

if CLIENT then
    -- Clicks are read here (while looking the game blocks the attack keys).
    local CLASS = "rhylib_binoculars"
    local wasDown = false
    Rhylib.Hook.Add("Think", "gear.binoculars", function()
        local me = LocalPlayer()
        local w = IsValid(me) and me:GetActiveWeapon()
        if not (IsValid(w) and w:GetClass() == CLASS) then wasDown = false return end
        local G = Rhylib.Gear
        if not (G and G.SendOptics) then return end
        local down = input.IsMouseDown(MOUSE_RIGHT) or input.IsMouseDown(MOUSE_LEFT)
        if down and not wasDown and not vgui.CursorVisible() and not gui.IsGameUIVisible() then
            G.SendOptics(me:GetNW2Int("rhylib_optics", 0) == 3 and 0 or 3)
            surface.PlaySound("buttons/lightswitch2.wav")
        end
        wasDown = down
    end)

    local COL = Color(220, 220, 220, 200)
    function SWEP:DrawHUD()
        local me = LocalPlayer()
        if me:GetNW2Int("rhylib_optics", 0) ~= 0 then return end
        local UI = Rhylib.UI
        local font = UI and UI.Font and UI.Font(14) or "DermaDefault"
        draw.SimpleText("Click: binoculars", font, ScrW() * 0.5, ScrH() * 0.5 + 26, COL, TEXT_ALIGN_CENTER)
    end
end
