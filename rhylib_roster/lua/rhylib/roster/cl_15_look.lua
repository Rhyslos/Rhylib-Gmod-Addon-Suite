--[[
    Looks: hair, facial hair, hair colour and skin (R.HAIR / R.FHAIR /
    R.HAIR_COLOURS / R.SKINS), picked in the character creator or later
    with !look / rhylib_look. A preview stage shows a clone with the helmet
    off (dark box, soft accent glow, corner ticks); each look is a row with
    its place in the list ("3 / 12"), < and > and the name between them (a
    click lists every option; hair colours with a swatch).
    rhylib_gear puts hair and skin on the model (hair hidden under a helmet).

    Hair colour: each model has one hair material (e.g. "ct_trp/hair");
    the server (rhylib_gear) sets it to a tinted copy every client makes
    ($color2, values above 1 lighten), so nothing new is downloaded.
    NW2Int rhylib_haircol (0 = the model's own). (A client-only swap was
    tried first: the server's networked materials undid it.)
    Client only. Adds: R.ApplyHairColour, R.LookPreview, R.LookStage,
    R.LookStepper, R.LookControls, R.WriteLook, R.OpenLook, console
    rhylib_look, the pause menu page Trooper > Appearance (stage on the
    left, the rows and Save on the right).
]]

local R = Rhylib.Roster

local function K() return Rhylib.UI and Rhylib.UI.Kit end

-- (used if R.PREVIEW has no model; the preview falls back to your own
-- model when that one isn't installed)
local PREVIEW_DEFAULT = "models/ct_trp/pm_ct_trp.mdl"

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

-- $flags bits that CreateMaterial needs as their own keys (MATERIAL_VAR_
-- ALPHATEST, TRANSLUCENT, NOCULL), so hair cards stay see-through.
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

-- R.ApplyHairColour(ent, col): tint the hair of a clientside model (the
-- previews) directly. col = index into R.HAIR_COLOURS minus one (0 = natural).
-- Example: Rhylib.Roster.ApplyHairColour(modelPanel.Entity, 5)   -- blond
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

-- Theme tokens (dark defaults; roster.stage is made in cl_10_creator.lua).
local COL_STAGE = Rhylib.UI.Col("roster.stage", 18, 21, 20, 255)

-- What each hair colour roughly looks like (the swatch beside its name).
-- Real hair colours, not theme colours.
local HAIR_SWATCH = {
    [1] = Color(35, 30, 28), [2] = Color(70, 48, 34), [3] = Color(115, 80, 50), [4] = Color(140, 62, 34),
    [5] = Color(210, 175, 110), [6] = Color(150, 150, 150), [7] = Color(225, 225, 222),
}

-- R.LookPreview(parent, getLook): a DModelPanel showing the look (helmet
-- off), slowly turning. getLook() returns { hair, fhair, hcol, skin } and
-- is read every frame, so changes show at once. Returns the panel.
function R.LookPreview(parent, getLook)
    local mdl = vgui.Create("DModelPanel", parent)
    local want = (R.PREVIEW and R.PREVIEW.model) or PREVIEW_DEFAULT
    local model = (util.IsValidModel(want) or file.Exists(want, "GAME")) and want or LocalPlayer():GetModel()
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
    local ang = Angle(0, 0, 0)
    function mdl:LayoutEntity(e)
        local look = getLook()
        ang.y = 20 + math.sin(RealTime() * 0.6) * 30
        e:SetAngles(ang)
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

-- R.LookStage(parent, getLook, caption): the preview in a stage box (dark,
-- a soft glow in the accent, corner ticks, "PREVIEW" and caption on top).
-- Returns the box (size / dock it yourself); box.model is the DModelPanel.
function R.LookStage(parent, getLook, caption)
    local k = K()
    local s = k.S
    local C = k.C
    local D = R.Draw
    local box = vgui.Create("DPanel", parent)
    function box:Paint(w, h)
        k.SetCol(COL_STAGE)
        surface.DrawRect(0, 0, w, h)
        if D and D.Glow then D.Glow(0, 0, w, h, C.accent, 34) end
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.Ticks(0, 0, w, h, true)
        k.Caps("Preview", s(14), s(18))
        if caption then draw.SimpleText(caption, k.Font(12), w - s(14), s(18), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
    end
    box.model = R.LookPreview(box, getLook)
    box.model:Dock(FILL)
    box.model:DockMargin(1, s(34), 1, 1)
    return box
end

-- R.LookStepper(parent, title, list, get, set): a row with < name > to step
-- through a list of { value, label }; get() returns the current value,
-- set(v) stores a new one. A click on the name lists them all. Returns
-- the row (not docked).
function R.LookStepper(parent, title, list, get, set)
    local k = K()
    local s = k.S
    local C = k.C
    local swatch = list == R.HAIR_COLOURS
    local row = vgui.Create("DPanel", parent)
    row:SetTall(s(44))
    row:DockPadding(s(12), s(7), s(8), s(7))
    local function idx()
        for i, o in ipairs(list) do if o[1] == get() then return i end end
        return 1
    end
    function row:Paint(w, h)
        k.SetCol(self:IsHovered() and C.rowAlt or C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local f = k.Font(14, 600)
        draw.SimpleText(title, f, s(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(f)
        local tw = surface.GetTextSize(title)
        local i = idx()
        if self.cntIdx ~= i then self.cntIdx, self.cntText = i, i .. " / " .. #list end
        draw.SimpleText(self.cntText, k.Font(11, 700), s(12) + tw + s(10), h * 0.5, C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local right = vgui.Create("DPanel", row)
    right:Dock(RIGHT)
    right:SetWide(s(250))
    right.Paint = nil
    local prev = k.Button(right, "<", function() set(list[(idx() - 2) % #list + 1][1]) end, { small = true })
    prev:Dock(LEFT)
    prev:SetWide(s(34))
    local nextB = k.Button(right, ">", function() set(list[idx() % #list + 1][1]) end, { small = true })
    nextB:Dock(RIGHT)
    nextB:SetWide(s(34))
    local name = vgui.Create("DButton", right)
    name:SetText("")
    name:Dock(FILL)
    name:DockMargin(s(4), 0, s(4), 0)
    name:SetTooltip("Pick from the list")
    function name:Paint(w, h)
        k.SetCol(C.bg)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(self:IsHovered() and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local o = list[idx()]
        local f = k.Font(14, 700)
        local label = k.Fit(o[2], f, w - s(swatch and 36 or 12))
        if swatch then
            surface.SetFont(f)
            local tw = surface.GetTextSize(label)
            local sz = s(12)
            local x = math.floor((w - tw - sz - s(8)) * 0.5)
            local sc = HAIR_SWATCH[o[1]]
            if sc then
                surface.SetDrawColor(sc.r, sc.g, sc.b, 255)
                surface.DrawRect(x, math.floor((h - sz) * 0.5), sz, sz)
                k.SetCol(C.edgeLight)
                surface.DrawOutlinedRect(x, math.floor((h - sz) * 0.5), sz, sz)
            elseif R.Draw and R.Draw.Dashed then
                R.Draw.Dashed(x, math.floor((h - sz) * 0.5), sz, sz, C.tick)
            end
            draw.SimpleText(label, f, x + sz + s(8), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(label, f, w * 0.5, h * 0.5, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function name:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        local m = (R.Draw and R.Draw.Menu) and R.Draw.Menu() or k.Menu()
        for _, o in ipairs(list) do m:AddOption(o[2], function() set(o[1]) end) end
        m:Open()
    end
    return row
end

-- R.LookControls(parent, look): the four look rows (hair, colour, facial
-- hair, skin), docked to the top of parent; they edit the look table.
function R.LookControls(parent, look)
    local k = K()
    local rows = {
        { "Hair", R.HAIR, "hair" }, { "Hair colour", R.HAIR_COLOURS, "hcol" },
        { "Facial hair", R.FHAIR, "fhair" }, { "Skin", R.SKINS, "skin" },
    }
    for _, r in ipairs(rows) do
        local row = R.LookStepper(parent, r[1], r[2], function() return look[r[3]] end, function(v) look[r[3]] = v end)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, k.S(4))
    end
end

-- R.WriteLook(look): writes the look into the current net message (hair,
-- fhair strings, hair colour UInt 4, skin UInt 4), as roster.create and
-- roster.look read it.
function R.WriteLook(look)
    net.WriteString(look.hair)
    net.WriteString(look.fhair)
    net.WriteUInt(look.hcol or 0, 4)
    net.WriteUInt(look.skin or 0, 4)
end

local function myLook()
    local me = LocalPlayer()
    return { hair = me:GetNW2String("rhylib_hair", "hair_reg"), fhair = me:GetNW2String("rhylib_fhair", ""),
        hcol = me:GetNW2Int("rhylib_haircol", 0), skin = me:GetNW2Int("rhylib_skin", 0) }
end

-- The dim note under the rows.
local function helmetNote(parent)
    local k = K()
    local l = k.Label(parent, "Hair and facial hair are hidden while you wear a helmet.", 12, 400, k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, k.S(6), 0, 0)
    return l
end

-- R.OpenLook(): the "Your looks" window (also console rhylib_look and /look).
local lookWin
function R.OpenLook()
    local k = K()
    if not k then return end
    if IsValid(lookWin) then lookWin:Remove() end
    local s = k.S
    local UI = Rhylib.UI
    local look = myLook()
    local f = vgui.Create("EditablePanel")
    lookWin = f
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(math.min(ScrW() - s(40), s(860)), math.min(ScrH() - s(40), s(540)))
    f:Center()
    f:MakePopup()
    local headH = s(36)
    f:DockPadding(s(16), headH + s(16), s(16), s(16))
    function f:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "Your looks", sub = R.FullName and R.FullName(LocalPlayer()) or nil, ticks = "all", header = headH })
    end
    local prev = R.LookStage(f, function() return look end, "Helmet off")
    prev:Dock(LEFT)
    prev:SetWide(math.floor(f:GetWide() * 0.4))
    prev:DockMargin(0, 0, s(18), 0)
    local bar = vgui.Create("DPanel", f)
    bar:Dock(BOTTOM)
    bar:SetTall(s(38))
    bar.Paint = nil
    local save = k.Button(bar, "Save", function()
        Rhylib.Net.Start("roster.look")
        R.WriteLook(look)
        net.SendToServer()
        f:Remove()
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(150))
    local close = k.Button(bar, "Cancel", function() f:Remove() end)
    close:Dock(RIGHT)
    close:SetWide(s(120))
    close:DockMargin(0, 0, s(8), 0)
    local h = k.Heading(f, "Looks")
    h:Dock(TOP)
    h:DockMargin(0, 0, 0, s(8))
    R.LookControls(f, look)
    helmetNote(f)
end

concommand.Add("rhylib_look", function() R.OpenLook() end)

-- The same as a pause menu page: Trooper > Appearance.
local function addLookPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage and K()) then return end
    Menus.AddPage("looks", {
        title = "Appearance",
        order = 11,
        group = "trooper",
        visible = function() return LocalPlayer():GetNW2Bool("rhylib_char", false) end,
        build = function(page)
            local k = K()
            local s = k.S
            Menus.pages.looks.sub = "Shown with the helmet off"
            local look = myLook()
            -- (the page is 980 px wide at most; on 4:3 much less)
            local pw = page:GetWide() - s(32)
            local prev = R.LookStage(page, function() return look end, R.FullName and R.FullName(LocalPlayer()) or nil)
            prev:Dock(LEFT)
            prev:SetWide(math.max(s(220), math.min(s(380), math.floor(pw * 0.42))))
            prev:DockMargin(0, 0, s(18), 0)
            local h = k.Heading(page, "Looks")
            h:Dock(TOP)
            h:DockMargin(0, 0, 0, s(8))
            R.LookControls(page, look)
            local save = k.Button(page, "Save", function()
                Rhylib.Net.Start("roster.look")
                R.WriteLook(look)
                net.SendToServer()
                Rhylib.Notify(nil, "Looks saved", "good", "Roster")
            end, { accent = true })
            save:Dock(TOP)
            save:SetTall(s(38))
            save:DockMargin(0, s(10), 0, 0)
            helmetNote(page)
        end,
    })
end
addLookPage()
Rhylib.Hook.Add("InitPostEntity", "roster.lookpage", addLookPage)

-- /look on the server (roster.lookopen, empty).
Rhylib.Net.Receive("roster.lookopen", function() R.OpenLook() end)
