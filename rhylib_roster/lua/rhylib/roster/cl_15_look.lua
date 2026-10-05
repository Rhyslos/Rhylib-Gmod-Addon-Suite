--[[
    Looks: hair, facial hair, hair colour and skin (R.HAIR / R.FHAIR /
    R.HAIR_COLOURS / R.SKINS), picked in the character creator or later
    with !look / rhylib_look. A preview shows a clone with the helmet off.
    rhylib_gear puts hair and skin on the model (hair hidden under a helmet).

    Hair colour: each model has one hair material (e.g. "ct_trp/hair");
    the server (rhylib_gear) sets it to a tinted copy every client makes
    ($color2, values above 1 lighten), so nothing new is downloaded.
    NW2Int rhylib_haircol (0 = the model's own). (A client-only swap was
    tried first: the server's networked materials undid it.)
]]

local R = Rhylib.Roster

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end

local PREVIEW_MODEL = "models/ct_trp/pm_ct_trp.mdl"

local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "%.smd$", "")) end

-- Bodygroup option index by group and option name, or nil.
local function optionOf(ent, group, option)
    for _, g in ipairs(ent:GetBodyGroups() or {}) do
        if norm(g.name) == group then
            for i = 0, (g.num or 1) - 1 do
                if norm(g.submodels and g.submodels[i]) == option then return g.id, i end
            end
            return g.id, nil
        end
    end
end

--------------------------------------------------------------------------
-- Hair colour: the server swaps each player's hair material for
-- "!rhylib_hair_<crc>_<colour>" (rhylib_gear); every client makes those
-- materials here, a tinted copy of the model's own (all its settings
-- kept, so hair cards stay see-through), as soon as it sees that hair.
--------------------------------------------------------------------------

local made = {}   -- [name] = true

local function hairIndex(ent)
    for i, m in ipairs(ent:GetMaterials() or {}) do
        local l = string.lower(m)
        if string.sub(l, -5) == "/hair" or l == "hair" then return i - 1, m end
    end
end

local FLAG_KEYS = { [256] = "$alphatest", [2097152] = "$translucent", [8192] = "$nocull" }

local function makeTinted(orig, col)
    local name = R.HairMatName(orig, col)
    if made[name] then return name end
    local c = R.HAIR_COLOURS[col + 1]
    if not (c and c[3]) then return nil end
    local base = Material(orig)
    local kv = {}
    if base and not base:IsError() then
        for k, v in pairs(base:GetKeyValues() or {}) do
            if not string.find(k, "^%$flags") then
                local t = type(v)
                if t == "ITexture" then kv[k] = v:GetName()
                elseif t == "Vector" then kv[k] = string.format("[%f %f %f]", v.x, v.y, v.z)
                elseif t == "number" or t == "string" then kv[k] = tostring(v)
                end
            end
        end
        local flags = base:GetInt("$flags") or 0
        for bitv, key in pairs(FLAG_KEYS) do
            if bit.band(flags, bitv) ~= 0 then kv[key] = 1 end
        end
    else
        kv["$basetexture"] = orig
    end
    kv["$color2"] = string.format("[%.2f %.2f %.2f]", c[3][1], c[3][2], c[3][3])
    kv["$model"] = 1
    local shader = base and base:GetShader() or "VertexLitGeneric"
    if string.find(string.lower(shader), "vertexlitgeneric", 1, true) then shader = "VertexLitGeneric" end
    CreateMaterial(name, shader, kv)
    made[name] = true
    return name
end

-- Every colour for a hair material, the first time it's seen.
local seen = {}
local function prepare(orig)
    if seen[orig] then return end
    seen[orig] = true
    for col = 1, #R.HAIR_COLOURS - 1 do makeTinted(orig, col) end
end

-- On a clientside model (the previews): set it here directly.
function R.ApplyHairColour(ent, col)
    local idx, orig = hairIndex(ent)
    if not idx then return end
    prepare(orig)
    local name = (col or 0) > 0 and makeTinted(orig, col)
    ent:SetSubMaterial(idx, name and ("!" .. name) or "")
end

-- A new colour: make its copies straight away.
Rhylib.Hook.Add("EntityNetworkedVarChanged", "roster.haircol", function(ent, name)
    if name ~= "rhylib_haircol" or not (IsValid(ent) and ent:IsPlayer()) then return end
    local _, orig = hairIndex(ent)
    if orig then prepare(orig) end
end)

-- Players' hair materials get their tinted copies made ahead of time.
timer.Create("Rhylib.Roster.HairColour", 1, 0, function()
    for _, p in ipairs(player.GetAll()) do
        local mdl = p:GetModel() or ""
        if p.rhylibHairModel ~= mdl then
            p.rhylibHairModel = mdl
            local _, orig = hairIndex(p)
            if orig then prepare(orig) end
        end
    end
end)

--------------------------------------------------------------------------
-- Preview and controls
--------------------------------------------------------------------------

-- A model panel showing the look (helmet off), slowly turning.
-- getLook() returns { hair, fhair, hcol, skin }.
function R.LookPreview(parent, getLook)
    local mdl = vgui.Create("DModelPanel", parent)
    local model = util.IsValidModel(PREVIEW_MODEL) and PREVIEW_MODEL or LocalPlayer():GetModel()
    mdl:SetModel(model)
    mdl:SetFOV(28)
    local ent = mdl.Entity
    if IsValid(ent) then
        local seq = ent:LookupSequence("idle_all_01")
        if seq and seq > 0 then ent:SetSequence(seq) end
        ent:SetupBones()
        local head = ent:LookupBone("ValveBiped.Bip01_Head1")
        local pos = head and ent:GetBonePosition(head) or Vector(0, 0, 64)
        mdl:SetLookAt(pos)
        mdl:SetCamPos(pos + Vector(40, 0, 2))
    end
    local lastCol
    function mdl:LayoutEntity(e)
        local look = getLook()
        e:SetAngles(Angle(0, 20 + math.sin(RealTime() * 0.6) * 30, 0))
        local id, i = optionOf(e, "helmet", "trooper_head")
        if id and i and e:GetBodygroup(id) ~= i then e:SetBodygroup(id, i) end
        for _, pair in ipairs({ { "hair", look.hair }, { "fhair", look.fhair } }) do
            local gid, idx = optionOf(e, pair[1], pair[2] ~= "" and pair[2] or "empty")
            if gid then e:SetBodygroup(gid, idx or 0) end
        end
        if (look.skin or 0) < (e:SkinCount() or 1) then e:SetSkin(look.skin or 0) end
        if lastCol ~= look.hcol then
            lastCol = look.hcol
            R.ApplyHairColour(e, look.hcol)
        end
    end
    return mdl
end

-- A row with < name > to step through a list of { value, label }.
function R.LookStepper(parent, title, list, get, set)
    local k = K()
    local row = k.Row(parent, title)
    row.right:SetWide(k.S(260))
    local function idx()
        for i, o in ipairs(list) do if o[1] == get() then return i end end
        return 1
    end
    local prev = k.Button(row.right, "<", function() set(list[(idx() - 2) % #list + 1][1]) end, { small = true })
    prev:Dock(LEFT)
    prev:SetWide(k.S(34))
    local nextB = k.Button(row.right, ">", function() set(list[idx() % #list + 1][1]) end, { small = true })
    nextB:Dock(RIGHT)
    nextB:SetWide(k.S(34))
    local name = vgui.Create("DPanel", row.right)
    name:Dock(FILL)
    function name:Paint(w, h)
        draw.SimpleText(list[idx()][2], k.Font(14, 700), w * 0.5, h * 0.5, k.C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return row
end

-- The four look rows, docked to the top of parent.
function R.LookControls(parent, look)
    local k = K()
    local rows = {
        { "Hair", R.HAIR, "hair" }, { "Hair colour", R.HAIR_COLOURS, "hcol" },
        { "Facial hair", R.FHAIR, "fhair" }, { "Skin", R.SKINS, "skin" },
    }
    for _, r in ipairs(rows) do
        local row = R.LookStepper(parent, r[1], r[2], function() return look[r[3]] end, function(v) look[r[3]] = v end)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, k.S(6))
    end
end

function R.WriteLook(look)
    net.WriteString(look.hair)
    net.WriteString(look.fhair)
    net.WriteUInt(look.hcol or 0, 4)
    net.WriteUInt(look.skin or 0, 4)
end

-- Change your looks later.
local lookWin
function R.OpenLook()
    local k = K()
    if not k then return end
    if IsValid(lookWin) then lookWin:Remove() end
    local s = k.S
    local me = LocalPlayer()
    local look = { hair = me:GetNW2String("rhylib_hair", "hair_reg"), fhair = me:GetNW2String("rhylib_fhair", ""),
        hcol = me:GetNW2Int("rhylib_haircol", 0), skin = me:GetNW2Int("rhylib_skin", 0) }
    local f = vgui.Create("EditablePanel")
    lookWin = f
    Rhylib.Menus.prompts[f] = true
    f.OnRemove = function(self) Rhylib.Menus.prompts[self] = nil end
    f:SetSize(s(640), s(380))
    f:Center()
    f:MakePopup()
    f:DockPadding(s(14), s(48), s(14), s(14))
    function f:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "Your looks", sub = "Shown with the helmet off", ticks = "all", header = s(36) })
    end
    local prev = R.LookPreview(f, function() return look end)
    prev:Dock(LEFT)
    prev:SetWide(s(230))
    prev:DockMargin(0, 0, s(12), 0)
    R.LookControls(f, look)
    local save = k.Button(f, "Save", function()
        Rhylib.Net.Start("roster.look")
        R.WriteLook(look)
        net.SendToServer()
        f:Remove()
    end, { accent = true })
    save:Dock(BOTTOM)
    save:SetTall(s(36))
    local close = k.Button(f, "Cancel", function() f:Remove() end)
    close:Dock(BOTTOM)
    close:DockMargin(0, 0, 0, s(6))
end

concommand.Add("rhylib_look", function() R.OpenLook() end)

-- The same as a pause menu page: Character > Appearance.
local function addLookPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and K()) then return end
    Menus.AddPage("looks", {
        title = "Appearance",
        order = 21,
        group = "character",
        visible = function() return LocalPlayer():GetNW2Bool("rhylib_char", false) end,
        build = function(page)
            local k = K()
            local s = k.S
            local me = LocalPlayer()
            Menus.pages.looks.sub = "Shown with the helmet off"
            local look = { hair = me:GetNW2String("rhylib_hair", "hair_reg"), fhair = me:GetNW2String("rhylib_fhair", ""),
                hcol = me:GetNW2Int("rhylib_haircol", 0), skin = me:GetNW2Int("rhylib_skin", 0) }
            local prev = R.LookPreview(page, function() return look end)
            prev:Dock(LEFT)
            prev:SetWide(s(300))
            prev:DockMargin(0, 0, s(16), 0)
            R.LookControls(page, look)
            local save = k.Button(page, "Save", function()
                Rhylib.Net.Start("roster.look")
                R.WriteLook(look)
                net.SendToServer()
                notification.AddLegacy("Looks saved", NOTIFY_GENERIC, 2)
            end, { accent = true })
            save:Dock(TOP)
            save:SetTall(s(36))
            save:DockMargin(0, s(10), 0, 0)
        end,
    })
end
addLookPage()
Rhylib.Hook.Add("InitPostEntity", "roster.lookpage", addLookPage)

-- Hair colour check: your model's materials, which one is the hair, and
-- what's swapped (paste the output when a colour lands on the wrong part).
concommand.Add("rhylib_hair_debug", function()
    local me = LocalPlayer()
    print("Model " .. me:GetModel() .. "  skin " .. me:GetSkin() .. "  hair colour " .. me:GetNW2Int("rhylib_haircol", 0)
        .. "  helmet " .. (me:GetNW2Bool("rhylib_helmetOff", false) and "off" or "on"))
    local hi = hairIndex(me)
    for i, m in ipairs(me:GetMaterials() or {}) do
        local sub = me:GetSubMaterial(i - 1) or ""
        print(string.format("  [%d] %s%s%s", i - 1, m, hi == i - 1 and "   <- hair" or "", sub ~= "" and ("   swapped for " .. sub) or ""))
    end
end)
net.Receive(Rhylib.Net.Name("roster.lookopen"), function() R.OpenLook() end)
