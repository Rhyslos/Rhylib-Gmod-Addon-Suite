--[[
    rhylib_pose_editor (client): make body poses (Rhylib.Poses, rhylib_core
    sh_74_poses.lua) on your own player model, with the orbit camera.
      Bones: drawn on the model in groups (spine & head, arms, fingers,
      legs; tick which show). Click a dot to pick it, then drag the
      gizmo: Rotate (E) rings, Move (W) arrows, Q local / world axes; hold
      Shift while dragging to snap (15° turns, 0.5 moves, from where the
      drag started; Shift+Ctrl: 5° turns). The selected bone's numbers are
      in the rows too; a pink dot's numbers (position, and turn where it
      has one) are its stored value in its own frame (gun from its anchor,
      spot from its parent, hand IK target from its frame, elbow point from
      the chest, sling from its bone, muzzle in the gun's axes).
      Pose: Add (turns on top of the animation, so walking and aiming
      still show) or Set (the listed bones take exactly this turn). Loop
      plays the keys over Length seconds; not looping holds the first key.
      Keys: a timeline (each key a numbered mark at its time, its shape
      its ease: diamond smooth, triangle linear, square snap; the yellow
      playhead): click a key to show it, drag it to change its time (0.05 s
      steps, Shift 0.25 s; past another it reorders; key 1 stays put),
      click / drag the bar to scrub, right-click a key for copy / paste /
      delete / its ease. Play loop, + Key here (at the playhead, the pose
      as shown there; on a key: halfway to the next, a copy of it), - Key,
      the key's time; each key's ease into the next (Linear / Smooth /
      Snap = hold, then jump).
      Fades (Pose tab): fade in / out seconds (0 snaps) and the curve
      (Linear / Smooth); Test fade plays it in on the preview, holds 1 s
      and fades it out.
      Children follow: off = turning a bone leaves the bones under it
      where they are (their turn is made up for).
      Mirror: copy one side onto the other (whole side or the selected
      bone), matched against the model's reference pose.
      Copy from an animation: any sequence of your model at a point in it,
      for the shown groups or the selected bone.
      Undo (Ctrl+Z) / Redo (Ctrl+Y, Ctrl+Shift+Z): the pose and the
      weapon's settings (Po.gear: spots, grip, locks, sling, muzzle, gun
      model, recoil; re-sent when undone); a new change clears redo.
      Reset bone, Clear key.
      Copy / paste (kept while the editor is open): a key (Keys tab: its
      bones, gun, hand and elbow data; the time stays), a bone's values
      (Bone tab, onto any bone), a hand (Hands tab: its fingers and hand
      IK target; onto the other hand it's mirrored). A saved hand pose can
      be mirrored to the other hand (a copy named "... (mirrored)").
      Weapon poses: pick a weapon (it's given to you and held, perm
      rhylib.poses.edit), "Use this pose here" adds the saved pose to its
      list; tick when it plays (Stance / Moving / Gun / Doing, Po.FILTERS);
      the first entry that fits wins (a green PLAYING chip on the row that
      plays on you now, greyed rows don't fit now; Po.WeaponPoseIndex);
      Up / Down order them. "Pause the
      editor's pose" shows them playing on you as others see them.
      Pose on: Me, or a stand-in (a model path, or "Model of what I look
      at": an NPC / droid) spawned in front of you, playing its idle; the
      camera circles it.
      Gun in the pose (you, holding the weapon): ON keeps the gun where it
      is held now in every key; pink dots: Gun (move / rotate the gun),
      Left grip (where the left hand holds it: for the weapon, all its
      poses, or this pose only), Right / Left elbow (where each bends
      toward, per key). "Gun moves with" chest / hips / right hand / left
      hand; Right / Left hand on the gun (off: that arm poses freely; an
      anchor hand isn't moved onto the gun). Rifle grip fingers curls both
      hands' fingers as a rifle hold has them.
      Spots and hand IK (the weapon in your hands): named spots on the gun
      or on another spot (New spot starts at your left hand; on the weapon
      or in this pose), each a pink dot to move / rotate (a spot is where
      the hand goes and how it turns); Left / Right hand IK: the spot each
      hand stays on, for the weapon (always while held, every animation,
      also with no pose) or for this pose (over the weapon's, or off);
      keep the weapon's lock while reloading / lowered.
      Sling spot: for the weapon picked under Weapon poses, a bone and a
      see-through copy to drag (Edit spot); shown on anyone carrying it
      while it isn't in their hands.
      Save sends it to the server (perm rhylib.poses.edit, superadmins);
      !pose <name> plays it. Rename (on the server: weapon pose lists and
      recoil poses using it follow), Duplicate (a server copy "<name>
      copy"). Snapshots: copies of the pose being edited kept on this
      computer (data/rhylib_pose_snapshots.json, at most 50), restored or
      deleted from the list. The pose being edited is also kept in
      data/rhylib_pose_edit.json, so closing the window loses nothing.
    Hooks "devtools.posegizmo": HUDPaint, GUIMousePressed,
    GUIMouseReleased, Think; "devtools.posepuppet" Think;
    "devtools.posesling" / "devtools.poselines" PostDrawTranslucentRenderables;
    "devtools.posefire" Think (the fire loop); "devtools.posebase"
    CalcMainActivity / UpdateAnimation (50: the animation played under the
    pose, Keys tab "Play under it"). Window: Rhylib.Devtools.UI (cl_15_ui.lua): tabs Pose (pose on, saved
    poses: Load, Start from = a copy under a new name, Rename, Duplicate,
    snapshots, mode / loop / length, fades), Keys (timeline, ease), Bone (numbers, gizmo, children
    follow, bones shown), Hands (hand IK per hand: the hand's dot is a
    target kept from the chest, hips or gun; elbows bend toward their
    dots; a hand pose per hand: the fingers from an animation or a saved
    hand pose, data/rhylib_hand_presets.json), Gun model (the weapon's third-person hold, size and muzzle point,
    per weapon on the server over its file; Copy lines), Recoil (the weapon's fire
    gesture, recoil pose and kick; a visual fire loop; aim lines: blue the
    bolt path, red the barrel line, yellow the muzzle, and how many degrees
    apart), Gun, Spots & IK, Weapon poses, Sling, Tools
    (mirror, copy from an animation); the camera on the right.
]]

local DT = Rhylib.Devtools
local editor

local GROUPS = {
    { id = "spine", name = "Spine & head", on = true },
    { id = "larm", name = "Left arm", on = true },
    { id = "rarm", name = "Right arm", on = true },
    { id = "lfing", name = "Left fingers", on = false },
    { id = "rfing", name = "Right fingers", on = false },
    { id = "legs", name = "Legs", on = true },
    { id = "other", name = "Other bones", on = false },
}
local function groupOf(name)
    local n = string.lower(name)
    if string.find(n, "finger", 1, true) then return string.find(n, "_l_", 1, true) and "lfing" or "rfing" end
    if string.find(n, "thigh", 1, true) or string.find(n, "calf", 1, true) or string.find(n, "foot", 1, true) or string.find(n, "toe", 1, true) then return "legs" end
    if string.find(n, "clavicle", 1, true) or string.find(n, "upperarm", 1, true) or string.find(n, "forearm", 1, true) or string.find(n, "_hand", 1, true) then
        return string.find(n, "_l_", 1, true) and "larm" or "rarm"
    end
    if string.find(n, "pelvis", 1, true) or string.find(n, "spine", 1, true) or string.find(n, "neck", 1, true) or string.find(n, "head", 1, true) then return "spine" end
    return "other"
end
local function otherSide(name)
    if string.find(name, "_L_", 1, true) then return (string.gsub(name, "_L_", "_R_")) end
    if string.find(name, "_R_", 1, true) then return (string.gsub(name, "_R_", "_L_")) end
    return nil
end

local function copyPose(p) return util.JSONToTable(util.TableToJSON(p)) end
local function newPose() return { mode = "add", loop = false, length = 2, keys = { { t = 0, bones = {} } } } end

concommand.Add("rhylib_pose_editor", function()
    if IsValid(editor) then editor:Remove() return end
    local Po = Rhylib.Poses
    if not (Po and Po.Apply and DT and DT.UI and DT.UI.Window) then print("Needs Rhy's Core with poses (sh_74_poses.lua)") return end
    local me = LocalPlayer()
    local orbit = DT.orbit
    -- T: the model being posed (you, or the stand-in)
    local T = me

    -- The pose being edited (from the local backup, if there is one).
    local E = { name = "", key = 1, playing = false, scrub = nil, sel = nil, mode = "rotate", space = "local", follow = true, undo = {}, redo = {}, clip = {} }
    local saved = util.JSONToTable(file.Read("rhylib_pose_edit.json", "DATA") or "")
    E.pose = istable(saved) and Po.Clean(saved.pose) or newPose()
    E.name = istable(saved) and isstring(saved.name) and saved.name or ""
    local shown = {}
    for _, g in ipairs(GROUPS) do shown[g.id] = g.on end

    local DU = DT.UI
    local S = Rhylib.UI.Kit.S
    local f = DU.Window("Pose editor", { camera = { bone = "ValveBiped.Bip01_Spine2", dist = 110, head = "Camera (your chest)" } })
    editor = f
    local refreshAll = function() end
    local playStart = RealTime()

    local function backup()
        timer.Create("Rhylib.PoseEditorBackup", 0.5, 1, function()
            file.Write("rhylib_pose_edit.json", util.TableToJSON({ name = E.name, pose = E.pose }) or "")
        end)
    end
    local function heldClass() local w = me:GetActiveWeapon() return IsValid(w) and w:GetClass() or nil end
    -- An undo step: the pose and the gear (JSON) of the held and the picked
    -- weapon, so settings saved straight to the server undo too.
    local function capture(classes)
        local st = { pose = copyPose(E.pose), gear = {} }
        for c in pairs(classes) do
            local g = Po.gear[c]
            st.gear[c] = g and next(g) and (util.TableToJSON(g) or "") or ""
        end
        return st
    end
    -- noLive: a weapon setting only (doesn't switch the editor's pose back on)
    local function pushUndo(noLive)
        if not noLive then E.live = false end
        -- (a held - / + button: one step for the whole hold)
        local DUr = Rhylib.Devtools.UI
        if DUr and DUr.repeating then
            if E.undoRep then return end
            E.undoRep = true
        else
            E.undoRep = nil
        end
        local cls = {}
        local h = heldClass()
        if h then cls[h] = true end
        if E.wpn then cls[E.wpn] = true end
        E.undo[#E.undo + 1] = capture(cls)
        if #E.undo > 60 then table.remove(E.undo, 1) end
        E.redo = {}
    end
    local function curKey()
        E.key = math.Clamp(E.key, 1, #E.pose.keys)
        return E.pose.keys[E.key]
    end
    local function boneData(name, make)
        -- (handles like @gun aren't bones: a throwaway table, nothing stored)
        if string.sub(name, 1, 1) == "@" then return make and { a = { 0, 0, 0 }, v = { 0, 0, 0 } } or nil end
        local k = curKey()
        local b = k.bones[name]
        if not b and make then
            b = { a = { 0, 0, 0 }, v = { 0, 0, 0 } }
            k.bones[name] = b
        end
        if b then b.a = b.a or { 0, 0, 0 } b.v = b.v or { 0, 0, 0 } end
        return b
    end

    -- The preview: the shown key exactly, or the loop while playing / scrubbing.
    local single, looped = {}, {}
    local function updatePreview()
        local p = E.pose
        -- (Test fade: in over fadeIn, 1 s held, out over fadeOut)
        if E.testFade then
            local fi, fo = tonumber(p.fadeIn) or 0.25, tonumber(p.fadeOut) or 0.25
            local el = RealTime() - E.testFade
            if el > fi + 1 + fo + 0.4 then E.testFade = nil end
            if E.testFade then
                local lin = 0
                if el < fi then lin = el / fi
                elseif el < fi + 1 then lin = 1
                elseif el < fi + 1 + fo then lin = 1 - (el - fi - 1) / fo end
                local faded = {}
                for kk, vv in pairs(p) do faded[kk] = vv end
                if not p.loop then faded.keys = { p.keys[1] } end
                Po.preview = { ent = T, pose = faded, t = el, w = Po.FadeWeight and Po.FadeWeight(p, lin) or lin }
                return
            end
        end
        if E.live then
            -- (off: you show what others see, e.g. the weapon poses)
            Po.preview = nil
        elseif E.playing or E.scrub then
            -- (played as a loop even with Loop off, to see the keys run)
            looped.mode, looped.loop, looped.length, looped.keys = p.mode, true, p.length, p.keys
            looped.anchor, looped.hands, looped.grip, looped.spots, looped.lock, looped.ik = p.anchor, p.hands, p.grip, p.spots, p.lock, p.ik
            Po.preview = { ent = T, pose = looped, t = E.playing and (RealTime() - playStart) or E.scrub }
        else
            single.mode, single.loop, single.length, single.keys = p.mode, false, p.length, { curKey() }
            single.anchor, single.hands, single.grip, single.spots, single.lock, single.ik = p.anchor, p.hands, p.grip, p.spots, p.lock, p.ik
            Po.preview = { ent = T, pose = single, t = 0 }
        end
    end
    local function rebuild()
        updatePreview()
        T:InvalidateBoneCache()
        T:SetupBones()
    end
    Po.Hook(T)

    local function info() return Po.ModelInfo(T) end
    --------------------------------------------------------------------
    -- Handles that aren't bones: @gun (the held gun), @lgrip (where the
    -- left hand holds it), @relbow / @lelbow (the points the elbows bend
    -- toward), @sling (the weapon's spot on the body while carried)
    --------------------------------------------------------------------
    local function mat(pos, ang) local m = Matrix() m:SetTranslation(pos) m:SetAngles(ang) return m end
    local function vt(v) return { math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2) } end
    local function at(a) return { math.Round(a.p, 2), math.Round(a.y, 2), math.Round(a.r, 2) } end
    E.gripTo = "weapon"
    local slingCtl   -- (set by the sling rows: { class, bone, p, a })
    local function dbg() return IsValid(T) and T.rhylibPoseDbg or nil end
    -- (the gun now: where the pose puts it, else in the right hand)
    local function gunWorld()
        if T ~= me then return nil end
        local d = dbg()
        if E.pose.anchor and d and d.G then return d.G end
        local w = me:GetActiveWeapon()
        local b = me:LookupBone("ValveBiped.Bip01_R_Hand")
        local RH = b and me:GetBoneMatrix(b)
        if not (IsValid(w) and RH) then return nil end
        local hp, ha = Po.GunHold(w)
        return mat(RH:GetTranslation(), RH:GetAngles()) * mat(hp, ha)
    end
    -- spotOwner(name) -> the table holding that spot (the pose's or the weapon's)
    local function spotOwner(name)
        if E.pose.spots and E.pose.spots[name] then return E.pose.spots, "pose" end
        local class = heldClass()
        local g = class and Po.gear[class]
        if g and g.spots and g.spots[name] then return g.spots, "weapon", class end
        return nil
    end
    local function specialWorld(name)
        if name == "@sling" then
            local sc = slingCtl and slingCtl()
            if not sc then return nil end
            local b = me:LookupBone(sc.bone)
            local m = b and me:GetBoneMatrix(b)
            if not m then return nil end
            local pos, ang = LocalToWorld(Vector(sc.p[1], sc.p[2], sc.p[3]), Angle(sc.a[1], sc.a[2], sc.a[3]), m:GetTranslation(), m:GetAngles())
            return mat(pos, ang)
        end
        if string.sub(name, 1, 6) == "@spot:" then
            local G = gunWorld()
            local class = heldClass()
            if not (G and class) then return nil end
            local lk = Po.LockFor(Po.gear[class] or {}, E.pose)
            return Po.SpotWorld(lk.spots, string.sub(name, 7), G)
        end
        if name == "@muzzle" then
            if not E.muzzleEdit or T ~= me then return nil end
            local G = gunWorld()
            local w = me:GetActiveWeapon()
            if not (G and IsValid(w)) then return nil end
            local _, _, _, mp = Po.WeaponProp(w)
            return mat(G:GetTranslation() + G:GetForward() * mp.x + G:GetRight() * -mp.y + G:GetUp() * mp.z, G:GetAngles())
        end
        local d = dbg()
        if not d then return nil end
        -- (hand IK targets and the elbows work with or without the gun)
        if name == "@rhandik" then return E.pose.ik and E.pose.ik.r and d.HR or nil end
        if name == "@lhandik" then return E.pose.ik and E.pose.ik.l and d.HL or nil end
        local ikOn = E.pose.ik and (E.pose.ik.r or E.pose.ik.l)
        if (name == "@relbow" or name == "@lelbow") and d.chest and (E.pose.anchor or ikOn) then
            local e = name == "@relbow" and d.ER or d.EL
            return e and mat(e, d.chest:GetAngles()) or nil
        end
        if not E.pose.anchor then return nil end
        if name == "@gun" then return d.G end
        if name == "@lgrip" then
            -- (hidden while the left hand is locked to a spot: that's where it goes)
            local class = heldClass()
            if E.pose.ik and E.pose.ik.l then return nil end
            if class and Po.LockFor(Po.gear[class] or {}, E.pose).l then return nil end
            return d.L
        end
        return nil
    end
    local sendGear   -- (the weapon rows set it)
    -- Put a handle at the world matrix Wn (written into the key, the pose
    -- or the weapon's gear).
    local function setSpecial(name, Wn)
        if name == "@sling" then
            local sc = slingCtl and slingCtl()
            if not sc then return end
            local b = me:LookupBone(sc.bone)
            local m = b and me:GetBoneMatrix(b)
            if not m then return end
            local lp, la = WorldToLocal(Wn:GetTranslation(), Wn:GetAngles(), m:GetTranslation(), m:GetAngles())
            sc.p, sc.a = vt(lp), at(la)
            if sc.save then sc.save() end
            return
        end
        if string.sub(name, 1, 6) == "@spot:" then
            local nm = string.sub(name, 7)
            local tbl, where, class = spotOwner(nm)
            local G = gunWorld()
            if not (tbl and G) then return end
            local sp = tbl[nm]
            local lk = Po.LockFor(Po.gear[heldClass()] or {}, E.pose)
            local P = sp.parent == "@gun" and G or Po.SpotWorld(lk.spots, sp.parent, G)
            if not P then return end
            local l = P:GetInverseTR() * Wn
            sp.p, sp.a = vt(l:GetTranslation()), at(l:GetAngles())
            if where == "weapon" and sendGear then sendGear(class) end
            return
        end
        if name == "@muzzle" then
            local G = gunWorld()
            local class = heldClass()
            if not (G and class) then return end
            local lp = WorldToLocal(Wn:GetTranslation(), angle_zero, G:GetTranslation(), G:GetAngles())
            Po.gear[class] = Po.gear[class] or {}
            Po.gear[class].muzzle = vt(lp)
            if sendGear then sendGear(class) end
            return
        end
        local d = dbg()
        if not d then return end
        if name == "@gun" then
            local l = d.A:GetInverseTR() * Wn
            curKey().gun = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
        elseif name == "@lgrip" then
            local l = d.G:GetInverseTR() * Wn
            local g = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
            if E.gripTo == "pose" or E.pose.grip then
                -- (a pose with its own grip wins: that's the one you see move)
                if E.gripTo ~= "pose" and not E.gripWarned then
                    E.gripWarned = true
                    chat.AddText(Color(255, 200, 100), "This pose has its own left grip, so that one moves (Clear pose grip to edit the weapon's).")
                end
                E.pose.grip = { l = g }
            else
                local class = heldClass()
                if not class then return end
                Po.gear[class] = Po.gear[class] or {}
                Po.gear[class].lgrip = g
                if sendGear then sendGear(class) end
            end
        elseif name == "@rhandik" or name == "@lhandik" then
            local side = name == "@rhandik" and "r" or "l"
            local F = d[name == "@rhandik" and "FR" or "FL"]
            if not F then return end
            local l = F:GetInverseTR() * Wn
            local k = curKey()
            k.hand = k.hand or {}
            k.hand[side] = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
        elseif (name == "@relbow" or name == "@lelbow") and d.chest then
            local l = d.chest:GetInverseTR() * Wn
            local k = curKey()
            k.elbow = k.elbow or {}
            k.elbow[name == "@relbow" and "r" or "l"] = vt(l:GetTranslation())
        end
    end

    -- handleRef(name) -> { pos, ang, turn, class, frame } or nil: a handle's
    -- stored value (pos / ang: the stored arrays, written in place; nil
    -- while not stored yet), whether it has a turn, the weapon whose gear
    -- holds it (saved with sendGear) and what it's measured from.
    local SHORT = { chest = "the chest", hips = "the hips", rhand = "the right hand", lhand = "the left hand", gun = "the gun" }
    local function handleRef(name)
        local k = curKey()
        if name == "@gun" then
            return { pos = k.gun and k.gun.p, ang = k.gun and k.gun.a, turn = true, frame = "from " .. (SHORT[E.pose.anchor] or "its anchor") }
        end
        if name == "@lgrip" then
            if E.gripTo == "pose" or E.pose.grip then
                local g = E.pose.grip and E.pose.grip.l
                return { pos = g and g.p, ang = g and g.a, turn = true, frame = "from the gun (this pose)" }
            end
            local class = heldClass()
            local g = class and Po.gear[class] and Po.gear[class].lgrip
            return { pos = g and g.p, ang = g and g.a, turn = true, class = class, frame = "from the gun (the weapon)" }
        end
        if name == "@rhandik" or name == "@lhandik" then
            local side = name == "@rhandik" and "r" or "l"
            local h = k.hand and k.hand[side]
            local c = E.pose.ik and E.pose.ik[side]
            return { pos = h and h.p, ang = h and h.a, turn = true, frame = "from " .. (SHORT[c and c.rel or "chest"] or "the chest") }
        end
        if name == "@relbow" or name == "@lelbow" then
            return { pos = k.elbow and k.elbow[name == "@relbow" and "r" or "l"], turn = false, frame = "from the chest" }
        end
        if string.sub(name, 1, 6) == "@spot:" then
            local nm = string.sub(name, 7)
            local tbl, where, class = spotOwner(nm)
            local sp = tbl and tbl[nm]
            if not sp then return nil end
            return { pos = sp.p, ang = sp.a, turn = true, class = where == "weapon" and class or nil, frame = "from " .. (sp.parent == "@gun" and "the gun" or sp.parent) }
        end
        if name == "@sling" then
            local g = E.wpn and Po.gear[E.wpn]
            local sl = g and g.sling
            if not sl then return nil end
            return { pos = sl.p, ang = sl.a, turn = true, class = E.wpn, frame = "from " .. string.gsub(sl.bone or "", "^ValveBiped%.Bip01_", "") }
        end
        if name == "@muzzle" then
            local class = heldClass()
            local g = class and Po.gear[class]
            return { pos = g and g.muzzle, turn = false, class = class, frame = "in the gun model's axes" }
        end
        return nil
    end
    -- (a handle not stored yet: where it is now, in its frame; once a frame)
    local nowF, nowName, nowP, nowA
    local function handleNow(name)
        if nowF == FrameNumber() and nowName == name then return nowP, nowA end
        nowF, nowName, nowP, nowA = FrameNumber(), name, nil, nil
        local d = dbg()
        if name == "@relbow" or name == "@lelbow" then
            local W = specialWorld(name)
            if d and d.chest and W then nowP = (d.chest:GetInverseTR() * W):GetTranslation() end
        elseif name == "@gun" then
            local W = specialWorld(name)
            if d and d.A and W then
                local l = d.A:GetInverseTR() * W
                nowP, nowA = l:GetTranslation(), l:GetAngles()
            end
        elseif name == "@rhandik" or name == "@lhandik" then
            local W = specialWorld(name)
            local F = d and d[name == "@rhandik" and "FR" or "FL"]
            if F and W then
                local l = F:GetInverseTR() * W
                nowP, nowA = l:GetTranslation(), l:GetAngles()
            end
        elseif name == "@lgrip" then
            if d and d.G and d.L then
                local l = d.G:GetInverseTR() * d.L
                nowP, nowA = l:GetTranslation(), l:GetAngles()
            end
        elseif name == "@muzzle" then
            local w = me:GetActiveWeapon()
            if IsValid(w) then nowP = select(4, Po.WeaponProp(w)) end
        end
        return nowP, nowA
    end

    local function worldOf(name)
        if string.sub(name, 1, 1) == "@" then return specialWorld(name) end
        local inf = info()
        local id = inf and inf.ids[name]
        return id and T:GetBoneMatrix(id)
    end
    local function rotOnly(a) local m = Matrix() m:SetAngles(a) return m end

    -- setWorldAng(name, ang): turn a bone so it faces ang in the world
    -- (writes the key's value for the pose's mode).
    -- (a hand placed by hand IK or a gun grip: its numbers are a fine
    -- offset on top, Add-style, whatever the pose's mode)
    local function handPlaced(name)
        local side = name == "ValveBiped.Bip01_R_Hand" and "r" or name == "ValveBiped.Bip01_L_Hand" and "l"
        if not side then return false end
        if E.pose.ik and E.pose.ik[side] then return true end
        local anc = side == "r" and "rhand" or "lhand"
        return E.pose.anchor ~= nil and E.pose.anchor ~= anc and not (E.pose.hands and E.pose.hands[side] == false)
    end
    local function setWorldAng(name, target)
        rebuild()
        if string.sub(name, 1, 1) == "@" then
            local W = specialWorld(name)
            if W then setSpecial(name, mat(W:GetTranslation(), target)) end
            return
        end
        local inf = info()
        local id = inf and inf.ids[name]
        local W = id and T:GetBoneMatrix(id)
        if not W then return end
        local na
        if E.pose.mode == "set" and not handPlaced(name) then
            local pid = inf.parent[id]
            local P = pid and pid >= 0 and T:GetBoneMatrix(pid)
            if not P then
                if not E.rootWarned then chat.AddText(Color(255, 120, 100), "The root bone can't be set in Set mode: use Add mode for it.") end
                E.rootWarned = true
                return
            end
            na = (rotOnly(P:GetAngles()):GetInverseTR() * rotOnly(target)):GetAngles()
        else
            local b = boneData(name, false)
            local cur = b and Angle(b.a[1], b.a[2], b.a[3]) or Angle()
            na = (rotOnly(cur) * rotOnly(W:GetAngles()):GetInverseTR() * rotOnly(target)):GetAngles()
        end
        local b = boneData(name, true)
        b.a = { math.Round(na.p, 2), math.Round(na.y, 2), math.Round(na.r, 2) }
    end

    -- Turn a bone and (children follow off) put its children back.
    local function turnBone(name, target)
        local keep = {}
        if not E.follow and string.sub(name, 1, 1) ~= "@" and info() then
            local inf = info()
            local id = inf.ids[name]
            for cid, pid in pairs(inf.parent) do
                if pid == id then
                    local m = T:GetBoneMatrix(cid)
                    if m then keep[#keep + 1] = { inf.names[cid], m:GetAngles() } end
                end
            end
        end
        setWorldAng(name, target)
        for _, c in ipairs(keep) do setWorldAng(c[1], c[2]) end
    end

    local function moveBone(name, delta)
        rebuild()
        if string.sub(name, 1, 1) == "@" then
            local W = specialWorld(name)
            if W then setSpecial(name, mat(W:GetTranslation() + delta, W:GetAngles())) end
            return
        end
        local inf = info()
        local id = inf and inf.ids[name]
        local W = id and T:GetBoneMatrix(id)
        if not W then return end
        local frame = W:GetAngles()
        if E.pose.mode == "set" and not handPlaced(name) then
            local pid = inf.parent[id]
            local P = pid and pid >= 0 and T:GetBoneMatrix(pid)
            if not P then
                if not E.rootWarned then chat.AddText(Color(255, 120, 100), "The root bone can't be set in Set mode: use Add mode for it.") end
                E.rootWarned = true
                return
            end
            frame = P:GetAngles()
        end
        local lv = WorldToLocal(delta, angle_zero, vector_origin, frame)
        local b = boneData(name, true)
        b.v = { math.Round(b.v[1] + lv.x, 2), math.Round(b.v[2] + lv.y, 2), math.Round(b.v[3] + lv.z, 2) }
    end

    local function changed()
        backup()
        rebuild()
    end

    -- A handle's number row: writes its stored value (made from where it
    -- is now first, if it isn't stored yet), saves the weapon's gear.
    local function handleSet(name, which, i, v)
        local ref = handleRef(name)
        if not ref then return end
        if name == "@muzzle" and not (IsValid(me:GetActiveWeapon()) and heldClass()) then return end
        -- (weapon-only handles leave "Pause the editor's pose" as it is)
        pushUndo(ref.class ~= nil)
        if not ref.pos then
            if name == "@muzzle" then
                local w, class = me:GetActiveWeapon(), heldClass()
                if not (IsValid(w) and class) then return end
                local m = select(4, Po.WeaponProp(w))
                Po.gear[class] = Po.gear[class] or {}
                Po.gear[class].muzzle = { m.x, m.y, m.z }
            else
                rebuild()
                local W = specialWorld(name)
                if W then setSpecial(name, W) end
            end
            ref = handleRef(name)
            if not (ref and ref.pos) then return end
        end
        local arr = which == "a" and ref.ang or ref.pos
        if not arr then return end
        arr[i] = math.Round(v, 2)
        if ref.class and sendGear then sendGear(ref.class) end
        changed()
    end

    -- The model's reference pose (for mirroring) and an animation frame
    -- (for copying): bone angles in the model's own axes.
    local function sampleModel(seqName, cycle)
        local out = {}
        local cm = ClientsideModel(T:GetModel(), RENDERGROUP_OPAQUE)
        if not IsValid(cm) then return out end
        cm:SetNoDraw(true)
        cm:SetPos(vector_origin)
        cm:SetAngles(angle_zero)
        local seq = cm:LookupSequence(seqName or "reference")
        cm:ResetSequence(seq and seq >= 0 and seq or 0)
        cm:SetCycle(cycle or 0)
        cm:SetupBones()
        for i = 0, cm:GetBoneCount() - 1 do
            local m = cm:GetBoneMatrix(i)
            if m then out[cm:GetBoneName(i)] = m:GetAngles() end
        end
        cm:Remove()
        return out
    end
    local function entFrame() return T:GetPos(), Angle(0, T:GetRenderAngles().y, 0) end
    -- (bone names parents first, so a parent is set before its children)
    local function ordered(filter)
        local inf = info()
        local out = {}
        for _, id in ipairs(inf.order) do
            local n = inf.names[id]
            if filter(n) then out[#out + 1] = n end
        end
        return out
    end

    -- Mirror: the source bone's turn reflected across the body's middle,
    -- then corrected by how the two sides differ in the reference pose.
    local function reflect(a)
        local f1, u1 = a:Forward(), a:Up()
        f1.y, u1.y = -f1.y, -u1.y
        return f1:AngleEx(u1)
    end
    -- (how the other side differs in the reference pose ref: dst's turn
    -- from the reflected src)
    local function refDiff(ref, src, dst)
        local _, k = WorldToLocal(vector_origin, ref[dst], vector_origin, reflect(ref[src]))
        return k
    end
    -- mirrorRel: a bone's turn from its hand (rel, on the src side) as the
    -- other side's bone's turn from the other hand, with the same maths as
    -- mirror() (it doesn't depend on where the hands are).
    local function mirrorRel(ref, srcHand, dstHand, src, dst, rel)
        local kH, kB = refDiff(ref, srcHand, dstHand), refDiff(ref, src, dst)
        return (rotOnly(kH):GetInverseTR() * rotOnly(reflect(rel)) * rotOnly(kB)):GetAngles()
    end
    local function mirror(sources)
        local ref = sampleModel("reference", 0)
        local pos, ang = entFrame()
        pushUndo()
        for _, src in ipairs(sources) do
            local dst = otherSide(src)
            local W = worldOf(src)
            if dst and W and ref[src] and ref[dst] and info().ids[dst] then
                local _, kRef = WorldToLocal(vector_origin, ref[dst], vector_origin, reflect(ref[src]))
                local _, la = WorldToLocal(vector_origin, W:GetAngles(), pos, ang)
                local _, target = LocalToWorld(vector_origin, kRef, vector_origin, reflect(la))
                local _, wt = LocalToWorld(vector_origin, target, pos, ang)
                setWorldAng(dst, wt)
                rebuild()
            end
        end
        changed()
        refreshAll()
    end

    local function copyAnim(seqName, cycle, names)
        local smp = sampleModel(seqName, cycle)
        local pos, ang = entFrame()
        pushUndo()
        for _, n in ipairs(names) do
            if smp[n] then
                local _, wt = LocalToWorld(vector_origin, smp[n], pos, ang)
                setWorldAng(n, wt)
            end
        end
        changed()
        refreshAll()
    end

    local oldRemove = f.OnRemove
    function f:OnRemove()
        file.Write("rhylib_pose_edit.json", util.TableToJSON({ name = E.name, pose = E.pose }) or "")
        Po.preview = nil
        Po.onChanged = nil
        Po.onWeaponsChanged = nil
        Po.gearHold = nil
        if oldRemove then oldRemove(self) end
    end

    --------------------------------------------------------------------
    -- Shared state the tabs use
    --------------------------------------------------------------------
    local function msg(text) chat.AddText(Color(255, 120, 100), text) end
    local function info2(text) chat.AddText(Color(120, 200, 255), text) end
    local function gearOf(class)
        Po.gear[class] = Po.gear[class] or {}
        return Po.gear[class]
    end

    -- Pose on: you, or a stand-in model in front of you (NPCs, droids).
    local puppet
    local seqName = "reference"
    local function setTarget(e)
        if IsValid(puppet) and puppet ~= e then puppet:Remove() puppet = nil end
        Po.preview = nil
        T = e
        orbit.ent = (e ~= me) and e or nil
        -- (the camera's Front is the stand-in's front)
        orbit.baseYaw = (e ~= me) and e:GetAngles().y or nil
        E.sel = nil
        Po.Hook(T)
        seqName = T:LookupSequence("idle_all_01") >= 0 and "idle_all_01" or "reference"
        changed()
    end
    local function makePuppet(mdl)
        if not mdl or mdl == "" or not (util.IsValidModel(mdl) or file.Exists(mdl, "GAME")) then
            msg("No such model: " .. tostring(mdl))
            return
        end
        util.PrecacheModel(mdl)
        local cm = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
        if not IsValid(cm) then return end
        local fwd = Angle(0, me:EyeAngles().y, 0):Forward()
        local tr = util.TraceLine({ start = me:GetPos() + fwd * 90 + Vector(0, 0, 40), endpos = me:GetPos() + fwd * 90 - Vector(0, 0, 200), filter = me })
        cm:SetPos(tr.HitPos)
        cm:SetAngles(Angle(0, me:EyeAngles().y + 180, 0))
        local seq = cm:LookupSequence("idle_all_01")
        if seq < 0 then seq = cm:LookupSequence("idle") end
        if seq < 0 then
            for i, n in pairs(cm:GetSequenceList() or {}) do
                if string.find(string.lower(n), "idle", 1, true) then seq = i break end
            end
        end
        cm:ResetSequence(seq >= 0 and seq or 0)
        cm.rhylibStart = RealTime()
        if IsValid(puppet) then puppet:Remove() end
        puppet = cm
        setTarget(cm)
        if E.base and E.setBase then E.setBase(E.base) end
    end
    Rhylib.Hook.Add("Think", "devtools.posepuppet", function()
        if not IsValid(editor) then
            if IsValid(puppet) then puppet:Remove() end
            Rhylib.Hook.Remove("Think", "devtools.posepuppet")
            return
        end
        if IsValid(puppet) and puppet.rhylibFrozen then
            puppet:SetCycle(puppet.rhylibFrozen)
            puppet:InvalidateBoneCache()
        elseif IsValid(puppet) then
            local len = math.max(0.1, puppet:SequenceDuration())
            puppet:SetCycle(((RealTime() - puppet.rhylibStart) * (E.baseSpeed or 1) / len) % 1)
            puppet:InvalidateBoneCache()
        end
    end)
    local mdlPath = ""
    -- The animation under the pose (preview only, on your screen): idle,
    -- walking, running... with the held weapon's hold, or any sequence; on
    -- a stand-in, its own versions. nil = your real movement.
    local BASE = {
        { "idle", "Idle", ACT_MP_STAND_IDLE, ACT_HL2MP_IDLE, false },
        { "walk", "Walking", ACT_MP_WALK, ACT_HL2MP_WALK, true },
        { "run", "Running", ACT_MP_RUN, ACT_HL2MP_RUN, true },
        { "crouch", "Crouching", ACT_MP_CROUCH_IDLE, ACT_HL2MP_IDLE_CROUCH, false },
        { "crouchwalk", "Crouch walking", ACT_MP_CROUCHWALK, ACT_HL2MP_WALK_CROUCH, true },
        { "jump", "In the air", ACT_MP_JUMP, ACT_HL2MP_JUMP, false },
        { "swim", "Swimming", ACT_MP_SWIM, ACT_HL2MP_SWIM, true },
    }
    local BASE_BY = {}
    for _, b in ipairs(BASE) do BASE_BY[b[1]] = b end
    E.base, E.baseSpeed = nil, 1
    local frozen   -- { seq, cycle } while frozen (Freeze, below)
    local function baseSeq(ent, isPly)
        local b = E.base
        if not b then return nil end
        if string.sub(b, 1, 4) == "seq:" then return ent:LookupSequence(string.sub(b, 5)), false end
        local d = BASE_BY[b]
        if not d then return nil end
        local act = d[4]
        if isPly then act = ent:TranslateWeaponActivity(d[3]) end
        local seq = ent:SelectWeightedSequence(act)
        if (not seq or seq < 0) and isPly then seq = ent:SelectWeightedSequence(d[4]) end
        return seq, d[5]
    end
    local function setBase(v)
        E.base = v
        frozen = nil
        if IsValid(puppet) then
            local seq, moving = baseSeq(puppet, false)
            if not seq or seq < 0 then
                seq = puppet:LookupSequence("idle_all_01")
                if seq < 0 then seq = 0 end
            end
            puppet:ResetSequence(seq)
            puppet:SetPoseParameter("move_x", moving and 1 or 0)
            puppet:SetPoseParameter("move_y", 0)
            puppet.rhylibStart = RealTime()
        end
    end
    E.setBase = setBase
    -- Freeze: the animation stops where it is (breathing, idle sway, the
    -- walk cycle...), so lining things up holds still; your pose still plays.
    E.freeze = false
    local function setFreeze(on)
        E.freeze = on
        frozen = nil
        if IsValid(puppet) then puppet.rhylibFrozen = on and puppet:GetCycle() or nil end
    end
    Rhylib.Hook.Add("CalcMainActivity", "devtools.posebase", function(ply)
        if ply ~= me or not IsValid(editor) or T ~= me then return end
        if E.freeze then
            frozen = frozen or { seq = ply:GetSequence(), cycle = ply:GetCycle() }
            return ply:GetSequenceActivity(frozen.seq), frozen.seq
        end
        if not E.base then return end
        local seq = baseSeq(ply, true)
        if not seq or seq < 0 then return end
        return ply:GetSequenceActivity(seq), seq
    end, 50)
    Rhylib.Hook.Add("UpdateAnimation", "devtools.posebase", function(ply)
        if ply ~= me or not IsValid(editor) or T ~= me then return end
        if E.freeze then
            frozen = frozen or { seq = ply:GetSequence(), cycle = ply:GetCycle() }
            ply:SetPlaybackRate(0)
            ply:SetCycle(frozen.cycle)
            -- (the gesture layers too: firing, typing...)
            for i = 0, 15 do
                if ply:IsValidLayer(i) then ply:SetLayerPlaybackRate(i, 0) end
            end
            return true
        end
        if not E.base then return end
        local _, moving = baseSeq(ply, true)
        ply:SetPoseParameter("move_x", moving and 1 or 0)
        ply:SetPoseParameter("move_y", 0)
        ply:SetPlaybackRate(E.baseSpeed or 1)
        return true
    end, 50)


    -- Weapon poses: the list per weapon (edited here, sent to the server).
    local wlist = {}
    for _, w in ipairs(weapons.GetList()) do
        if w.ClassName and not string.find(w.ClassName, "_base", 1, true) and (w.Spawnable or w.AdminSpawnable or string.find(w.ClassName, "^rhylib_")) then
            wlist[#wlist + 1] = { w.ClassName, (w.PrintName and w.PrintName ~= "" and w.PrintName or w.ClassName) .. "  (" .. w.ClassName .. ")" }
        end
    end
    table.sort(wlist, function(a, b) return string.lower(a[2]) < string.lower(b[2]) end)
    local held0 = heldClass()
    for _, w in ipairs(wlist) do if w[1] == held0 then E.wpn = E.wpn or held0 end end
    local entries = {}
    local pending = 0
    local function wpnReload()
        local cur = E.wpn and Po.weapons[E.wpn]
        entries = cur and table.Copy(cur) or {}
        if E.wsel and not entries[E.wsel] then E.wsel = nil end
    end
    wpnReload()
    local function sendWpn()
        if not E.wpn then return end
        local class = E.wpn
        timer.Create("Rhylib.PoseEditorWpn", 0.3, 1, function()
            pending = pending + 1   -- (each send gets one reply)
            Rhylib.Net.Start("poses.wpnset")
            net.WriteString(class)
            net.WriteString(#entries > 0 and (util.TableToJSON(entries) or "") or "")
            net.SendToServer()
        end)
    end
    local function give()
        if not E.wpn then return end
        Rhylib.Net.Start("poses.give")
        net.WriteString(E.wpn)
        net.SendToServer()
    end
    Po.onWeaponsChanged = function()
        pending = math.max(0, pending - 1)
        if pending > 0 or timer.Exists("Rhylib.PoseEditorWpn") then return end
        wpnReload()
    end
    -- (gear: left grip, spots, locks, sling, ...; sent after a burst of
    -- edits, each weapon changed in it once; ours are kept over replies
    -- meanwhile)
    local gearDirty = {}
    sendGear = function(class)
        if not class then return end
        gearDirty[class] = true
        local hold = istable(Po.gearHold) and Po.gearHold or {}
        hold[class] = true
        Po.gearHold = hold
        timer.Remove("Rhylib.PoseEditorGearHold")
        timer.Create("Rhylib.PoseEditorGear", 0.3, 1, function()
            local list = gearDirty
            gearDirty = {}
            for c in pairs(list) do
                pending = pending + 1   -- (its reply comes as a poses.wpn too)
                local g = Po.gear[c]
                Rhylib.Net.Start("poses.gearset")
                net.WriteString(c)
                net.WriteString(g and next(g) and (util.TableToJSON(g) or "") or "")
                net.SendToServer()
            end
            timer.Create("Rhylib.PoseEditorGearHold", 1.5, 1, function() Po.gearHold = nil end)
        end)
    end

    -- The gun in the pose.
    local ANCH_BONE = { chest = "Spine4", hips = "Pelvis", rhand = "R_Hand", lhand = "L_Hand" }
    local function boneM(short) return worldOf("ValveBiped.Bip01_" .. short) end
    local function gunNow()
        local w = me:GetActiveWeapon()
        local RH = boneM("R_Hand")
        if not (IsValid(w) and RH) then return nil end
        local hp, ha = Po.GunHold(w)
        return mat(RH:GetTranslation(), RH:GetAngles()) * mat(hp, ha)
    end
    local function storeGunAllKeys(anchor, getG)
        local keep = E.key
        for i, k in ipairs(E.pose.keys) do
            E.key = i
            rebuild()
            local G = getG(i)
            local A = boneM(ANCH_BONE[anchor])
            if G and A then
                local l = mat(A:GetTranslation(), A:GetAngles()):GetInverseTR() * G
                k.gun = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
            end
        end
        E.key = keep
    end
    local ikSetRel   -- (the Hands tab's, below)
    local function gunToggle(keepLeft)
        if T ~= me then msg("The gun is only on your own model (Pose tab: Me).") return end
        if not IsValid(me:GetActiveWeapon()) then msg("Hold the weapon first (Weapon poses: Hold it).") return end
        pushUndo()
        E.playing, E.scrub, E.live = false, nil, false
        if E.pose.anchor then
            -- (hands kept from the gun move to the chest first, staying put)
            for _, side in ipairs({ "r", "l" }) do
                local c = E.pose.ik and E.pose.ik[side]
                if c and c.rel == "gun" and ikSetRel then ikSetRel(side, "chest", true) end
            end
            E.pose.anchor, E.pose.hands, E.pose.grip = nil, nil, nil
            for _, k in ipairs(E.pose.keys) do
                k.gun = nil
                -- (elbow points of hands with IK stay)
                if k.elbow then
                    for _, side in ipairs({ "r", "l" }) do
                        if not (E.pose.ik and E.pose.ik[side]) then k.elbow[side] = nil end
                    end
                    if not next(k.elbow) then k.elbow = nil end
                end
            end
        else
            storeGunAllKeys("chest", function() return gunNow() end)
            local leftOn = true
            if keepLeft then leftOn = E.pose.ik and E.pose.ik.l and true or false end
            E.pose.anchor, E.pose.hands = "chest", { r = true, l = leftOn }
            E.sel = "@gun"
        end
        changed()
    end
    local function setAnchor(id)
        if not E.pose.anchor or id == E.pose.anchor then return end
        local side = id == "rhand" and "r" or id == "lhand" and "l"
        local c = side and E.pose.ik and E.pose.ik[side]
        if c and c.rel == "gun" then msg("That hand is kept on the gun (Hands tab): set it to the chest first.") return end
        pushUndo()
        E.playing, E.scrub, E.live = false, nil, false
        local d0, l0 = {}, {}
        local keep = E.key
        for i in ipairs(E.pose.keys) do
            E.key = i
            rebuild()
            local d = dbg()
            d0[i] = d and d.G and mat(d.G:GetTranslation(), d.G:GetAngles())
            local LH = boneM("L_Hand")
            l0[i] = d and d.G and LH and mat(LH:GetTranslation(), LH:GetAngles()):GetInverseTR() * d.G
        end
        E.key = keep
        E.pose.anchor = id
        if id == "rhand" then
            local hp, ha = Po.GunHold(me:GetActiveWeapon())
            for _, k in ipairs(E.pose.keys) do k.gun = { p = vt(hp), a = at(ha) } end
        elseif id == "lhand" then
            for i, k in ipairs(E.pose.keys) do
                if l0[i] then k.gun = { p = vt(l0[i]:GetTranslation()), a = at(l0[i]:GetAngles()) } end
            end
        else
            storeGunAllKeys(id, function(i) return d0[i] end)
        end
        changed()
    end
    local function rifleFingers()
        local seq = "idle_ar2"
        if T:LookupSequence(seq) < 0 then seq = "idle_rpg" end
        if T:LookupSequence(seq) < 0 then msg("This model has no rifle hold to take the fingers from.") return end
        local smp = sampleModel(seq, 0)
        pushUndo()
        for _, side in ipairs({ "L", "R" }) do
            local hand = "ValveBiped.Bip01_" .. side .. "_Hand"
            local hs = smp[hand]
            if hs then
                for _, n in ipairs(ordered(function(n) return string.find(n, side .. "_Finger", 1, true) ~= nil end)) do
                    local Hw = worldOf(hand)
                    if smp[n] and Hw then
                        local _, rel = WorldToLocal(vector_origin, smp[n], vector_origin, hs)
                        local _, wt = LocalToWorld(vector_origin, rel, vector_origin, Hw:GetAngles())
                        setWorldAng(n, wt)
                    end
                end
            end
        end
        changed()
    end

    -- Sling spot of the weapon picked under Weapon poses.
    local SLING_BONES = { "Spine4", "Spine2", "Spine1", "Pelvis", "R_Thigh", "L_Thigh", "R_Clavicle", "L_Clavicle" }
    local ghost
    local function slingOf(class)
        local g = class and Po.gear[class]
        return g and g.sling
    end
    slingCtl = function()
        local sl = slingOf(E.wpn)
        if not sl or not E.slingEdit then return nil end
        local class = E.wpn
        local c = { bone = sl.bone, p = sl.p, a = sl.a }
        c.save = function()
            local s2 = slingOf(class)
            if not s2 then return end
            s2.p, s2.a = c.p, c.a
            sendGear(class)
        end
        return c
    end
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "devtools.posesling", function(_, sky)
        if sky then return end
        if not IsValid(editor) then
            if IsValid(ghost) then ghost:Remove() end
            Rhylib.Hook.Remove("PostDrawTranslucentRenderables", "devtools.posesling")
            return
        end
        local W = E.slingEdit and specialWorld("@sling")
        local sw = E.wpn and weapons.Get(E.wpn)
        local mdl = sw and (sw.PropModel or sw.WorldModel)
        if not (W and mdl and mdl ~= "") then return end
        if not IsValid(ghost) or ghost:GetModel() ~= mdl then
            if IsValid(ghost) then ghost:Remove() end
            ghost = ClientsideModel(mdl, RENDERGROUP_TRANSLUCENT)
            if not IsValid(ghost) then return end
            ghost:SetNoDraw(true)
            ghost:SetModelScale(sw.PropScale or 1, 0)
        end
        ghost:SetPos(W:GetTranslation())
        ghost:SetAngles(W:GetAngles())
        ghost:SetupBones()
        render.SetBlend(0.6)
        ghost:DrawModel()
        render.SetBlend(1)
    end)

    -- Spots and hand IK.
    E.spotTo, E.lockTo = "weapon", "weapon"
    local function allSpots()
        local class = heldClass()
        if not class then return {}, nil end
        return Po.LockFor(Po.gear[class] or {}, E.pose).spots, class
    end
    local function lockTable(make)
        if E.lockTo == "pose" then
            if make then E.pose.lock = E.pose.lock or {} end
            return E.pose.lock
        end
        local class = heldClass()
        if not class then return nil end
        local g = gearOf(class)
        if make then g.lock = g.lock or {} end
        return g.lock, class
    end
    local function newSpot()
        if not (heldClass() and gunWorld()) then msg("Hold the weapon first (Weapon poses: Hold it).") return end
        Rhylib.UI.Kit.Prompt("New spot", "Name the spot (e.g. Foregrip)", "", function(txt)
            local nm = Po.CleanName(txt)
            local class, G = heldClass(), gunWorld()
            if nm == "" or not (class and G) then return end
            local spots = allSpots()
            local parent = (E.spotSel and spots[E.spotSel]) and E.spotSel or "@gun"
            local P = parent == "@gun" and G or Po.SpotWorld(spots, parent, G)
            -- (starts where your left hand is now)
            local LH = worldOf("ValveBiped.Bip01_L_Hand")
            if not (P and LH) then return end
            local l = P:GetInverseTR() * mat(LH:GetTranslation(), LH:GetAngles())
            local sp = { parent = parent, p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
            if E.spotTo == "pose" then
                pushUndo()
                E.pose.spots = E.pose.spots or {}
                E.pose.spots[nm] = sp
                changed()
            else
                pushUndo(true)
                local g = gearOf(class)
                g.spots = g.spots or {}
                g.spots[nm] = sp
                sendGear(class)
            end
            E.spotSel, E.sel = nm, "@spot:" .. nm
        end)
    end
    local function deleteSpot()
        local nm = E.spotSel
        local tbl, where, class = spotOwner(nm or "")
        if not tbl then return end
        pushUndo(where ~= "pose")
        tbl[nm] = nil
        local function unref(t)
            if not t then return end
            for _, sp in pairs(t.spots or {}) do if sp.parent == nm then sp.parent = "@gun" end end
            if t.lock then
                if t.lock.r == nm then t.lock.r = nil end
                if t.lock.l == nm then t.lock.l = nil end
            end
        end
        unref(E.pose)
        local hc = class or heldClass()
        if hc then unref(Po.gear[hc]) end
        if where == "pose" then
            if E.pose.spots and not next(E.pose.spots) then E.pose.spots = nil end
            changed()
        else
            sendGear(class)
        end
        E.spotSel = nil
        if E.sel == "@spot:" .. nm then E.sel = nil end
    end

    --------------------------------------------------------------------
    -- The window and its tabs
    --------------------------------------------------------------------
    local function resort(k)
        table.sort(E.pose.keys, function(a, b) return a.t < b.t end)
        for i, kk in ipairs(E.pose.keys) do if kk == k then E.key = i end end
    end
    -- Key actions (the Keys tab's buttons and the timeline's menu).
    local MAX_KEYS = 32
    local EASES = { { "linear", "Linear" }, { "smooth", "Smooth" }, { "snap", "Snap" } }
    local function copyKey() E.clip.key = copyPose(curKey()) end
    local function pasteKey()
        if not E.clip.key then return end
        pushUndo()
        -- (everything of the copied key but its time)
        local k, c = curKey(), copyPose(E.clip.key)
        for fld in pairs(k) do if fld ~= "t" then k[fld] = nil end end
        for fld, v in pairs(c) do if fld ~= "t" then k[fld] = v end end
        k.bones = k.bones or {}
        changed()
    end
    local function deleteKey()
        if #E.pose.keys <= 1 then return end
        pushUndo()
        table.remove(E.pose.keys, E.key)
        changed()
    end
    local function setEase(v)
        local k = curKey()
        if (k.ease or "smooth") == v then return end
        pushUndo()
        k.ease = v ~= "smooth" and v or nil
        changed()
    end
    -- (the playhead: the loop's time while playing, the scrub, else the key)
    local function playheadT()
        if E.playing then return (RealTime() - playStart) % math.max(0.1, E.pose.length) end
        if E.scrub then return math.min(E.scrub, E.pose.length) end
        return curKey().t
    end
    local function addKeyHere()
        if #E.pose.keys >= MAX_KEYS then msg("At most " .. MAX_KEYS .. " keys.") return end
        local ph = E.playing and playheadT() or E.scrub
        if not ph then
            -- (showing a key: halfway to the next one, a copy of it)
            local cur, nxt = curKey(), E.pose.keys[E.key + 1]
            local t = math.Round((cur.t + (nxt and nxt.t or E.pose.length)) * 0.5, 2)
            if t - cur.t < 0.05 then msg("No room for a key after this one: make Length longer or move a key's time.") return end
            pushUndo()
            local k = copyPose(cur)
            k.t = t
            table.insert(E.pose.keys, k)
            resort(k)
            changed()
            return
        end
        ph = math.Round(math.Clamp(ph, 0, E.pose.length), 2)
        E.playing, E.scrub, E.live = false, nil, false
        for i, k in ipairs(E.pose.keys) do
            if math.abs(k.t - ph) < 0.03 then
                E.key = i
                changed()
                info2("There's a key here already: showing it.")
                return
            end
        end
        pushUndo()
        -- (the pose as the loop shows it there)
        local smp, ex = Po.Sample({ loop = true, length = E.pose.length, keys = E.pose.keys }, ph)
        local k = { t = ph, bones = {} }
        for n, b in pairs(smp) do k.bones[n] = { a = at(b.a), v = vt(b.v) } end
        if ex.gun and ex.gun.p and ex.gun.a then k.gun = { p = vt(ex.gun.p), a = at(ex.gun.a) } end
        if ex.er or ex.el then k.elbow = { r = ex.er and vt(ex.er) or nil, l = ex.el and vt(ex.el) or nil } end
        local function hd(h) return h and { p = vt(h.p), a = at(h.a) } or nil end
        if ex.hr or ex.hl then k.hand = { r = hd(ex.hr), l = hd(ex.hl) } end
        -- (it eases on as the key before it did)
        local prev
        for _, kk in ipairs(E.pose.keys) do if kk.t <= ph then prev = kk end end
        k.ease = prev and prev.ease or nil
        table.insert(E.pose.keys, k)
        resort(k)
        changed()
    end

    -- The timeline (Keys tab): a custom row on the page.
    local Kit = Rhylib.UI.Kit
    local KC = Kit.C
    local PLAYHEAD, KEYSEL, KEYOFF = Color(255, 200, 70), Color(90, 160, 230), Color(160, 164, 160)
    local function shapePts(ease, x, y, s)
        if ease == "linear" then return { { x = x - s * 0.8, y = y - s }, { x = x + s, y = y }, { x = x - s * 0.8, y = y + s } } end
        if ease == "snap" then
            local q = s * 0.8
            return { { x = x - q, y = y - q }, { x = x + q, y = y - q }, { x = x + q, y = y + q }, { x = x - q, y = y + q } }
        end
        return { { x = x, y = y - s }, { x = x + s, y = y }, { x = x, y = y + s }, { x = x - s, y = y } }
    end
    local function outline(pts, col)
        surface.SetDrawColor(col)
        for i = 1, #pts do
            local a, b = pts[i], pts[i % #pts + 1]
            surface.DrawLine(a.x, a.y, b.x, b.y)
        end
    end
    local function keyMenu()
        local m = Kit.Menu and Kit.Menu() or DermaMenu()
        m:AddOption("Copy key", copyKey)
        m:AddOption(E.clip.key and "Paste key" or "Paste key (nothing copied)", pasteKey)
        m:AddOption("Delete key", deleteKey)
        local sub = m:AddSubMenu("Ease")
        local cur = curKey().ease or "smooth"
        for _, e in ipairs(EASES) do
            sub:AddOption(e[2] .. (cur == e[1] and "  ✓" or ""), function() setEase(e[1]) end)
        end
        m:Open()
    end
    local function timeline(pg)
        local r = vgui.Create("DPanel", pg.canvas)
        r:Dock(TOP)
        r:DockMargin(0, 0, S(8), S(4))
        local LAB, TRK, PAD = S(16), S(54), S(12)
        r:SetTall(LAB + TRK + S(22))
        -- (the bar spans the length rounded up to 0.5 s, at least 1 s)
        local function span() return math.max(1, math.ceil(E.pose.length * 2 - 1e-4) / 2) end
        local function xOf(t, w) return PAD + (w - PAD * 2) * t / span() end
        local function tOf(x, w) return (x - PAD) / math.max(1, w - PAD * 2) * span() end
        local function keyAt(mx, my, w)
            if my < LAB - S(4) or my > LAB + TRK + S(2) then return nil end
            local best, bd
            for i, k in ipairs(E.pose.keys) do
                local d = math.abs(xOf(k.t, w) - mx)
                if d <= S(10) and (not bd or d < bd or (d == bd and i == E.key)) then best, bd = i, d end
            end
            return best
        end
        local function scrubAt(mx, w)
            E.playing, E.live, E.testFade = false, false, nil
            E.scrub = math.Clamp(math.Round(tOf(mx, w), 2), 0, E.pose.length)
            updatePreview()
        end
        function r:Paint(w, h)
            local len, sp = E.pose.length, span()
            local cy = LAB + TRK * 0.5
            draw.NoTexture()
            surface.SetDrawColor(KC.row)
            surface.DrawRect(0, LAB, w, TRK)
            local xl = xOf(len, w)
            if xl < w then
                surface.SetDrawColor(0, 0, 0, 110)
                surface.DrawRect(xl, LAB, w - xl, TRK)
            end
            surface.SetDrawColor(KC.edgeDark)
            surface.DrawOutlinedRect(0, LAB, w, TRK)
            -- (second ticks, thinned out so the labels stay apart)
            local stepT = 10
            for _, st in ipairs({ 0.5, 1, 2, 5, 10 }) do
                if (w - PAD * 2) * st / sp >= S(30) then stepT = st break end
            end
            local font = Kit.Font(11)
            for i = 0, math.floor(sp / stepT + 1e-4) do
                local t = i * stepT
                local x = xOf(t, w)
                surface.SetDrawColor(255, 255, 255, 28)
                surface.DrawLine(x, LAB + 1, x, LAB + TRK - 1)
                draw.SimpleText(i == 0 and "0" or string.format("%.1f", t), font, x, LAB - S(2), KC.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            end
            -- (a line through the keys)
            local keys = E.pose.keys
            if #keys > 1 then
                surface.SetDrawColor(255, 255, 255, 40)
                surface.DrawLine(xOf(keys[1].t, w), cy, xOf(keys[#keys].t, w), cy)
            end
            local s = S(10)
            local nf = Kit.Font(11, 700)
            for i, k in ipairs(keys) do
                local x = xOf(k.t, w)
                local pts = shapePts(k.ease, x, cy, s)
                local sel = i == E.key
                draw.NoTexture()
                surface.SetDrawColor(sel and KEYSEL or KC.header)
                surface.DrawPoly(pts)
                outline(pts, sel and KEYSEL or KEYOFF)
                draw.SimpleText(tostring(i), nf, x, cy, sel and Color(15, 20, 28) or KEYOFF, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            -- (the playhead)
            local ph = playheadT()
            local px = xOf(ph, w)
            surface.SetDrawColor(PLAYHEAD)
            surface.DrawRect(px - 1, LAB, 2, TRK)
            draw.NoTexture()
            surface.DrawPoly({ { x = px - S(5), y = LAB }, { x = px + S(5), y = LAB }, { x = px, y = LAB + S(6) } })
            local ty = LAB + TRK + S(11)
            draw.SimpleText(string.format("Key %d · %.2f s", E.key, curKey().t), Kit.Font(12, 700), 0, ty, KC.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("▲ %.2f s", ph), Kit.Font(12, 700), w, ty, PLAYHEAD, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        function r:OnMousePressed(code)
            local mx, my = self:CursorPos()
            local w = self:GetWide()
            local i = keyAt(mx, my, w)
            if code == MOUSE_RIGHT then
                if i then
                    E.key, E.playing, E.scrub, E.live, E.testFade = i, false, nil, false, nil
                    changed()
                    keyMenu()
                end
                return
            end
            if code ~= MOUSE_LEFT then return end
            if i then
                E.key, E.playing, E.scrub, E.live, E.testFade = i, false, nil, false, nil
                changed()
                self.drag = { key = E.pose.keys[i], x = mx, first = i == 1 }
            elseif my <= LAB + TRK then
                self.drag = { scrub = true }
                scrubAt(mx, w)
            else
                return
            end
            self:MouseCapture(true)
        end
        function r:OnMouseReleased()
            self.drag = nil
            self:MouseCapture(false)
        end
        function r:Think()
            local d = self.drag
            if not d then
                -- (the cursor says what a click does)
                local mx, my = self:CursorPos()
                local i = self:IsHovered() and keyAt(mx, my, self:GetWide())
                local want = i and (i == 1 and "hand" or "sizewe") or "arrow"
                if self.rhylibCur ~= want then self.rhylibCur = want self:SetCursor(want) end
                return
            end
            if not input.IsMouseDown(MOUSE_LEFT) then self.drag = nil self:MouseCapture(false) return end
            local mx = self:CursorPos()
            local w = self:GetWide()
            if d.scrub then scrubAt(mx, w) return end
            -- (key 1 stays where it is; a small wobble isn't a drag)
            if d.first or not E.pose.keys[1] then return end
            if not d.moved and math.abs(mx - d.x) < S(3) then return end
            local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
            local stp = shift and 0.25 or 0.05
            local t = math.Round(math.Clamp(math.Round(tOf(mx, w) / stp) * stp, 0.05, E.pose.length), 2)
            if not d.moved then
                d.moved = true
                pushUndo()
            end
            if d.key.t ~= t then
                d.key.t = t
                resort(d.key)
                changed()
            end
        end
        return r
    end
    -- "This key's ease": three buttons with their curves drawn.
    local function easeRow(pg)
        local r = vgui.Create("DPanel", pg.canvas)
        r:Dock(TOP)
        r:DockMargin(0, 0, S(8), S(4))
        r:SetTall(S(50))
        function r:Paint(w)
            draw.SimpleText("This key's ease (into the next key)", Kit.Font(13), 0, S(8), KC.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local curve = {
            linear = function(x) return x end,
            smooth = function(x) return x * x * (3 - 2 * x) end,
            snap = function(x) return x < 1 and 0 or 1 end,
        }
        local btns = {}
        for i, e in ipairs(EASES) do
            local b = vgui.Create("DButton", r)
            b:SetText("")
            function b:Paint(w, h)
                local on = (curKey().ease or "smooth") == e[1]
                surface.SetDrawColor(on and KEYSEL or (self:IsHovered() and KC.rowHover or KC.row))
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(KC.edgeDark)
                surface.DrawOutlinedRect(0, 0, w, h)
                local col = on and Color(15, 20, 28) or KC.text
                local ix, iw, ih = S(6), S(18), S(12)
                local iy = math.floor(h * 0.5 + ih * 0.5)
                surface.SetDrawColor(col)
                local fn = curve[e[1]]
                local N = 12
                local lx, ly = ix, iy
                for j = 1, N do
                    local xx = j / N
                    local nx, ny = ix + iw * xx, iy - ih * fn(xx)
                    if e[1] == "snap" and j == N then
                        surface.DrawLine(lx, ly, nx, ly)
                        surface.DrawLine(nx, ly, nx, ny)
                        surface.DrawLine(nx - 1, ly, nx - 1, ny)
                    else
                        surface.DrawLine(lx, ly, nx, ny)
                        surface.DrawLine(lx, ly - 1, nx, ny - 1)
                    end
                    lx, ly = nx, ny
                end
                draw.SimpleText(string.upper(e[2]), Kit.Font(12, 700), ix + iw + S(6), h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() setEase(e[1]) end
            btns[i] = b
        end
        function r:PerformLayout(w)
            local gap = S(4)
            local bw = math.floor((w - gap * 2) / 3)
            for i, b in ipairs(btns) do
                b:SetPos((i - 1) * (bw + gap), S(18))
                b:SetSize(i == 3 and (w - 2 * (bw + gap)) or bw, S(30))
            end
        end
        return r
    end
    -- (a text box: the kit's prompt)
    local function askText(title, desc, default, fn)
        if Kit.Prompt then Kit.Prompt(title, desc, default, fn) else Derma_StringRequest(title, desc, default, fn) end
    end
    -- (undo / redo: the pose and those weapons' gear; changed gear is sent)
    local function restore(st)
        E.pose = st.pose
        for c, js in pairs(st.gear) do
            local g = Po.gear[c]
            local now = g and next(g) and (util.TableToJSON(g) or "") or ""
            if now ~= js then
                Po.gear[c] = js ~= "" and util.JSONToTable(js) or nil
                sendGear(c)
            end
        end
        E.undoRep = nil
        changed()
        refreshAll()
    end
    local function step(from, to)
        local st = table.remove(from)
        if not st then return end
        local cls = {}
        for c in pairs(st.gear) do cls[c] = true end
        to[#to + 1] = capture(cls)
        if #to > 60 then table.remove(to, 1) end
        restore(st)
    end
    local function undo() step(E.undo, E.redo) end
    local function redo() step(E.redo, E.undo) end
    f.onKey = function(k)
        local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
        local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
        if k == KEY_W then E.mode = "move"
        elseif k == KEY_E then E.mode = "rotate"
        elseif k == KEY_Q then E.space = E.space == "local" and "world" or "local"
        elseif k == KEY_Z and ctrl then if shift then redo() else undo() end
        elseif k == KEY_Y and ctrl then redo() end
    end

    f:AddTab("Pose", function(pg)
        pg:Heading("Pose on")
        pg:Buttons({
            { "Me", function() setTarget(me) end, { selected = function() return T == me end } },
            { "Stand-in from what I look at", function()
                local e = me:GetEyeTrace().Entity
                if not IsValid(e) or not e:GetModel() then msg("Look at an NPC, droid or player.") return end
                mdlPath = e:GetModel()
                makePuppet(mdlPath)
            end },
        })
        pg:Text("models/... (a stand-in model)", function() return mdlPath end, function(v) mdlPath = v end)
        pg:Buttons({ { "Use this model as the stand-in", function() makePuppet(string.Trim(mdlPath)) end } })
        pg:Note(function() return T == me and "Posing: you." or ("Posing: a stand-in (" .. tostring(T:GetModel()) .. ").") end)

        pg:Heading("Saved poses")
        pg:Choice("Load", function()
            local out = {}
            for n in SortedPairs(Po.defs) do out[#out + 1] = { n, n } end
            return out
        end, function() return E.name end, function(n)
            local p = Po.defs[n]
            if not p then return end
            pushUndo()
            E.pose, E.name, E.key, E.scrub, E.playing = copyPose(p), n, 1, nil, false
            changed()
        end)
        -- (a saved pose copied as the start of a new one: the original stays
        -- as it is; the copy gets a new name to save under)
        local startFrom = ""
        pg:Choice("Start from", function()
            local out = {}
            for n in SortedPairs(Po.defs) do out[#out + 1] = { n, n } end
            return out
        end, function() return startFrom end, function(n)
            local p = Po.defs[n]
            if not p then return end
            pushUndo()
            local base = n .. " copy"
            local nm, i = base, 2
            while Po.defs[nm] do nm = base .. " " .. i i = i + 1 end
            E.pose, E.name, E.key, E.scrub, E.playing = copyPose(p), string.sub(nm, 1, 40), 1, nil, false
            startFrom = n
            changed()
            info2("Started from \"" .. n .. "\" as \"" .. E.name .. "\": rename it if you like, then Save to server.")
        end)
        pg:Text("pose name", function() return E.name end, function(v) E.name = v backup() end)
        pg:Buttons({
            { "New", function()
                pushUndo()
                E.pose, E.key, E.scrub, E.playing, E.name = newPose(), 1, nil, false, ""
                changed()
            end },
            { "Save to server", function()
                local n = Po.CleanName(E.name)
                if n == "" then msg("Give the pose a name first (letters, digits, spaces, _ and -).") return end
                local js = util.TableToJSON(E.pose)
                if not js or #js > 60000 then msg("That pose is too big to send.") return end
                Rhylib.Net.Start("poses.save")
                net.WriteString(n)
                net.WriteString(js)
                net.SendToServer()
                info2("Pose \"" .. n .. "\" sent to the server. Play it with !pose " .. n)
            end, { accent = true } },
            { "Delete", function()
                local n = Po.CleanName(E.name)
                if not Po.defs[n] then msg("No saved pose called \"" .. n .. "\".") return end
                Derma_Query("Delete the saved pose \"" .. n .. "\" from the server?", "Delete pose", "Delete", function()
                    Rhylib.Net.Start("poses.del")
                    net.WriteString(n)
                    net.SendToServer()
                end, "Cancel")
            end, { danger = true } },
            { "Undo (Ctrl+Z)", undo, { enabled = function() return #E.undo > 0 end } },
            { "Redo (Ctrl+Y)", redo, { enabled = function() return #E.redo > 0 end } },
        })
        pg:Buttons({
            { "Rename", function()
                local n = Po.CleanName(E.name)
                if not Po.defs[n] then msg("No saved pose called \"" .. n .. "\": load one first.") return end
                askText("Rename pose", "A new name for \"" .. n .. "\" (on the server)", n, function(v)
                    local to = Po.CleanName(v)
                    if to == "" or to == n then return end
                    if Po.defs[to] then msg("There's already a pose called \"" .. to .. "\".") return end
                    Rhylib.Net.Start("poses.ren")
                    net.WriteString(n)
                    net.WriteString(to)
                    net.SendToServer()
                    -- (the editor takes the new name once the server has the
                    -- renamed pose; refused, it keeps the old one)
                    local tries = 0
                    timer.Create("Rhylib.PoseEditorRename", 0.2, 25, function()
                        tries = tries + 1
                        if not IsValid(editor) then timer.Remove("Rhylib.PoseEditorRename") return end
                        if Po.defs[to] and not Po.defs[n] then
                            if Po.CleanName(E.name) == n then E.name = to backup() end
                            timer.Remove("Rhylib.PoseEditorRename")
                        elseif tries >= 25 then
                            msg("The server didn't rename \"" .. n .. "\".")
                        end
                    end)
                end)
            end },
            { "Duplicate", function()
                local n = Po.CleanName(E.name)
                local src = Po.defs[n]
                if not src then msg("No saved pose called \"" .. n .. "\": load one first.") return end
                if table.Count(Po.defs) >= (Po.MAX_POSES or 200) then msg("Too many poses saved: delete some first.") return end
                local base = string.Trim(string.sub(n, 1, 32)) .. " copy"
                local nm, i = base, 2
                while Po.defs[nm] do nm = base .. " " .. i i = i + 1 end
                local js = util.TableToJSON(src)
                if not js then return end
                Rhylib.Net.Start("poses.save")
                net.WriteString(nm)
                net.WriteString(js)
                net.SendToServer()
                info2("Saved a copy of \"" .. n .. "\" as \"" .. nm .. "\".")
            end },
        }, { wrap = true })

        -- Snapshots of the pose being edited, on this computer.
        pg:Heading("Snapshots (this computer)")
        local SNAP = "rhylib_pose_snapshots.json"
        local snapList = util.JSONToTable(file.Read(SNAP, "DATA") or "")
        if not istable(snapList) then snapList = {} end
        local snapSel
        local function writeSnaps() file.Write(SNAP, util.TableToJSON(snapList) or "[]") end
        pg:Buttons({
            { "Save snapshot", function()
                local stamp = os.date("%H:%M:%S")
                askText("Save snapshot", "A name for this snapshot", stamp .. (E.name ~= "" and (" " .. E.name) or ""), function(v)
                    v = string.Trim(v or "")
                    snapList[#snapList + 1] = { name = string.sub(v ~= "" and v or stamp, 1, 40), at = os.date("%H:%M"), poseName = E.name, pose = copyPose(E.pose) }
                    while #snapList > 50 do table.remove(snapList, 1) end
                    writeSnaps()
                    snapSel = #snapList
                end)
            end, { accent = true } },
        })
        pg:List({ { "Snapshot", 0.5 }, { "Pose", 0.32 }, { "At", 0.18 } }, function()
            local out = {}
            for i = #snapList, 1, -1 do
                local sn = snapList[i]
                out[#out + 1] = { i, { sn.name or ("Snapshot " .. i), sn.poseName or "", sn.at or "" } }
            end
            return out
        end, function() return snapSel end, function(id) snapSel = id end, S(110))
        pg:Buttons({
            { "Restore", function()
                local sn = snapSel and snapList[snapSel]
                local p = sn and Po.Clean(sn.pose)
                if not p then return end
                pushUndo()
                E.pose, E.key, E.scrub, E.playing = p, 1, nil, false
                if isstring(sn.poseName) and sn.poseName ~= "" then E.name = sn.poseName end
                changed()
                refreshAll()
            end, { enabled = function() return snapSel ~= nil and snapList[snapSel] ~= nil end } },
            { "Delete", function()
                if not (snapSel and snapList[snapSel]) then return end
                table.remove(snapList, snapSel)
                writeSnaps()
                snapSel = nil
            end, { danger = true, enabled = function() return snapSel ~= nil and snapList[snapSel] ~= nil end } },
        }, { wrap = true })

        pg:Heading("How it plays")
        pg:Choice("Mode", { { "add", "Add: on top of the animation" }, { "set", "Set: exact turns" } }, function() return E.pose.mode end, function(v)
            if v == E.pose.mode then return end
            pushUndo()
            E.pose.mode = v
            changed()
        end)
        pg:Toggle("Loop (off: holds key 1)", function() return E.pose.loop end, function(v)
            pushUndo()
            E.pose.loop = v
            changed()
        end)
        pg:Number("Length (s)", 0.1, 0.1, 60, function() return E.pose.length end, function(v)
            pushUndo()
            E.pose.length = math.Round(v, 2)
            local k = curKey()
            for _, kk in ipairs(E.pose.keys) do kk.t = math.min(kk.t, E.pose.length) end
            resort(k)
            changed()
        end)
        -- (fades: kept only when not the default 0.25 s / linear)
        for _, fd in ipairs({ { "fadeIn", "Fade in (s)" }, { "fadeOut", "Fade out (s)" } }) do
            pg:Number(fd[2], 0.05, 0, 2, function() return tonumber(E.pose[fd[1]]) or 0.25 end, function(v)
                v = math.Round(v, 2)
                if v == (tonumber(E.pose[fd[1]]) or 0.25) then return end
                pushUndo()
                E.pose[fd[1]] = v ~= 0.25 and v or nil
                changed()
            end)
        end
        pg:Choice("Fade curve", { { "linear", "Linear" }, { "smooth", "Smooth" } }, function() return E.pose.fadeCurve or "linear" end, function(v)
            if v == (E.pose.fadeCurve or "linear") then return end
            pushUndo()
            E.pose.fadeCurve = v == "smooth" and "smooth" or nil
            changed()
        end)
        pg:Buttons({ { "Test fade", function()
            E.playing, E.scrub, E.live = false, nil, false
            E.testFade = RealTime()
            updatePreview()
        end } })
        pg:Note("How it eases in and out when it starts and stops playing (0 = snaps). Test fade: in, held 1 s, out, on the preview.")
    end)

    f:AddTab("Keys", function(pg)
        pg:Heading("Timeline")
        timeline(pg)
        pg:Buttons({
            { function() return E.playing and "Stop" or "Play loop" end, function()
                E.playing = not E.playing
                E.scrub, E.live, E.testFade = nil, false, nil
                playStart = RealTime()
                changed()
            end, { accent = true } },
            { "+ Key here", addKeyHere },
            { "− Key", deleteKey, { danger = true } },
        }, { wrap = true })
        pg:Note("Click a key to show it, drag it to move it (Shift: 0.25 s steps), right-click it for more; click or drag the bar to scrub.")
        pg:Heading("This key")
        easeRow(pg)
        pg:Number("Key time (s)", 0.05, 0, 60, function() return curKey().t end, function(v)
            pushUndo()
            local k = curKey()
            k.t = math.Clamp(math.Round(v, 2), 0, E.pose.length)
            resort(k)
            changed()
        end)
        pg:Buttons({
            { "Copy key", copyKey },
            { "Paste key", pasteKey, { enabled = function() return E.clip.key ~= nil end } },
        }, { wrap = true })
        pg:Note("Keys after the first only play with Loop on (Pose tab). Snap holds this key, then jumps to the next at its time.")
        pg:Heading("Animation under it")
        pg:Toggle("Freeze the animation (breathing, sway, walk cycle)", function() return E.freeze end, function(v) setFreeze(v) end)
        pg:Choice("Play under it", function()
            local out = { { "@real", "Your real movement" } }
            for _, b in ipairs(BASE) do out[#out + 1] = { b[1], b[2] } end
            local seqs = {}
            for _, sq in pairs(T:GetSequenceList() or {}) do seqs[#seqs + 1] = sq end
            table.sort(seqs)
            for _, sq in ipairs(seqs) do out[#out + 1] = { "seq:" .. sq, "· " .. sq } end
            return out
        end, function() return E.base or "@real" end, function(v) setBase(v ~= "@real" and v or nil) end)
        pg:Slider("Its speed", 0, 2, 2, function() return E.baseSpeed end, function(v) E.baseSpeed = v end)
        pg:Note("Only on your screen, with the weapon you hold (its hold type). Stand still while it plays; the stand-in plays its own version.")
    end)

    f:AddTab("Bone", function(pg)
        pg:Heading("Selected (click a dot on the model)")
        pg:Note(function()
            if not E.sel then return "Nothing picked." end
            if string.sub(E.sel, 1, 1) == "@" then
                local ref = handleRef(E.sel)
                return "Handle: " .. string.gsub(E.sel, "^@", "") .. (ref and (" · its numbers " .. ref.frame) or " (drag it with the gizmo)")
            end
            return string.gsub(E.sel, "^ValveBiped%.Bip01_", "") .. (boneData(E.sel) and "  (in this key)" or "") .. (handPlaced(E.sel) and " · placed by IK: these turn / move it a little on top" or "")
        end)
        local function selNum(text, part, i, step, lim)
            return pg:Number(text, step, -lim, lim, function()
                local b = E.sel and boneData(E.sel)
                return b and b[part][i] or 0
            end, function(v, bone)
                -- (bone: the one picked when you started typing)
                bone = bone or E.sel
                if not bone or string.sub(bone, 1, 1) == "@" then return end
                pushUndo()
                local b = boneData(bone, true)
                b[part][i] = v
                changed()
            end, function() return E.sel end)
        end
        local function isHandle() return E.sel ~= nil and string.sub(E.sel, 1, 1) == "@" end
        local boneRows = {}
        boneRows[1] = selNum("Turn pitch", "a", 1, 1, 360)
        boneRows[2] = selNum("Turn yaw", "a", 2, 1, 360)
        boneRows[3] = selNum("Turn roll", "a", 3, 1, 360)
        boneRows[4] = selNum("Move x", "v", 1, 0.1, 50)
        boneRows[5] = selNum("Move y", "v", 2, 0.1, 50)
        boneRows[6] = selNum("Move z", "v", 3, 0.1, 50)
        for _, r in ipairs(boneRows) do DU.ShowIf(r, function() return not isHandle() end) end
        -- (a pink dot: its stored value; rows it hasn't got fold away)
        local function handleNum(text, which, i, step, lim)
            local r = pg:Number(text, step, -lim, lim, function()
                local ref = isHandle() and handleRef(E.sel)
                if not ref then return 0 end
                local arr = which == "a" and ref.ang or ref.pos
                if arr then return arr[i] or 0 end
                local p, a = handleNow(E.sel)
                if which == "a" then return a and ({ a.p, a.y, a.r })[i] or 0 end
                return p and ({ p.x, p.y, p.z })[i] or 0
            end, function(v, h)
                h = h or E.sel
                if not h or string.sub(h, 1, 1) ~= "@" then return end
                handleSet(h, which, i, v)
            end, function() return E.sel end)
            DU.ShowIf(r, function()
                local ref = isHandle() and handleRef(E.sel)
                return ref and (which == "p" or ref.turn) or false
            end)
        end
        handleNum("Position x", "p", 1, 0.1, 100)
        handleNum("Position y", "p", 2, 0.1, 100)
        handleNum("Position z", "p", 3, 0.1, 100)
        handleNum("Turn pitch", "a", 1, 1, 360)
        handleNum("Turn yaw", "a", 2, 1, 360)
        handleNum("Turn roll", "a", 3, 1, 360)
        pg:Buttons({
            { "Reset bone", function()
                if not E.sel then return end
                pushUndo()
                curKey().bones[E.sel] = nil
                changed()
            end },
            { "Clear key", function()
                pushUndo()
                curKey().bones = {}
                changed()
            end, { danger = true } },
        })
        local function short(n) return (string.gsub(n, "^ValveBiped%.Bip01_", "")) end
        pg:Buttons({
            { "Copy bone", function()
                if not E.sel or isHandle() then msg("Pick a bone first (not a pink dot).") return end
                local b = boneData(E.sel)
                E.clip.bone = { from = E.sel, a = b and table.Copy(b.a), v = b and table.Copy(b.v) }
            end },
            { function() return E.clip.bone and ("Paste bone (" .. short(E.clip.bone.from) .. ")") or "Paste bone" end, function()
                local c = E.clip.bone
                if not c then return end
                if not E.sel or isHandle() then msg("Pick the bone to paste onto first.") return end
                pushUndo()
                -- (a bone that wasn't in its key: this one isn't either)
                if not c.a then
                    curKey().bones[E.sel] = nil
                else
                    local b = boneData(E.sel, true)
                    b.a, b.v = table.Copy(c.a), table.Copy(c.v)
                end
                changed()
            end, { enabled = function() return E.clip.bone ~= nil end } },
        }, { wrap = true })
        pg:Heading("Gizmo")
        pg:Buttons({
            { "Rotate (E)", function() E.mode = "rotate" end, { selected = function() return E.mode == "rotate" end } },
            { "Move (W)", function() E.mode = "move" end, { selected = function() return E.mode == "move" end } },
            { function() return E.space == "local" and "Axes: local (Q)" or "Axes: world (Q)" end, function() E.space = E.space == "local" and "world" or "local" end },
        })
        pg:Note("Shift: snap 15° / 0.5 · Shift+Ctrl: 5° (from where the drag started).")
        pg:Toggle("Children follow (off: the bones under it keep their turn)", function() return E.follow end, function(v) E.follow = v end)
        pg:Heading("Bones shown")
        local opts = {}
        for _, g in ipairs(GROUPS) do opts[#opts + 1] = { g.id, g.name } end
        pg:Chips(opts, function(id) return shown[id] end, function(id) shown[id] = not shown[id] end)
    end)

    -- Hand IK: switch it on per hand (every key starts with the hand where
    -- it is now), and what its target is kept from.
    local IK_FRAME = { chest = "Spine4", hips = "Pelvis" }
    local function ikFrame(rel)
        if rel == "gun" then
            local inf = info()
            return inf and Po.GunWorldOf(T, inf) or nil
        end
        return boneM(IK_FRAME[rel] or "Spine4")
    end
    -- worldOf each key's hand -> stored from the frame rel
    local function storeHandAllKeys(side, rel, getH)
        local keep = E.key
        for i, k in ipairs(E.pose.keys) do
            E.key = i
            rebuild()
            local H, F = getH(i), ikFrame(rel)
            if H and F then
                local l = mat(F:GetTranslation(), F:GetAngles()):GetInverseTR() * H
                k.hand = k.hand or {}
                k.hand[side] = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
            end
        end
        E.key = keep
    end
    local function ikNeedsGun(side, rel)
        if rel ~= "gun" then return false end
        if E.pose.anchor == (side == "r" and "rhand" or "lhand") then
            msg("The gun moves with this hand (Gun tab), so the hand can't also follow the gun.")
            return true
        end
        if T ~= me or not IsValid(me:GetActiveWeapon()) then msg("Hold the weapon to keep a hand on it.") return true end
        if side ~= "r" or E.pose.anchor then return false end
        info2("The right hand holds the gun, so the gun now moves with the pose (Gun tab: Gun in the pose).")
        gunToggle(true)
        return false
    end
    local function ikToggle(side, on)
        pushUndo()
        E.playing, E.scrub, E.live = false, nil, false
        E.pose.ik = E.pose.ik or {}
        if on then
            local rel = "chest"
            local bn = "ValveBiped.Bip01_" .. (side == "r" and "R" or "L") .. "_Hand"
            storeHandAllKeys(side, rel, function() local H = worldOf(bn) return H and mat(H:GetTranslation(), H:GetAngles()) end)
            E.pose.ik[side] = { on = true, rel = rel }
            E.sel = "@" .. side .. "handik"
        else
            E.pose.ik[side] = nil
            for _, k in ipairs(E.pose.keys) do if k.hand then k.hand[side] = nil if not next(k.hand) then k.hand = nil end end end
        end
        if not next(E.pose.ik) then E.pose.ik = nil end
        changed()
    end
    ikSetRel = function(side, rel, noUndo)
        local cfg = E.pose.ik and E.pose.ik[side]
        if not cfg or cfg.rel == rel then return end
        if ikNeedsGun(side, rel) then return end
        if not noUndo then pushUndo() end
        E.playing, E.scrub, E.live = false, nil, false
        -- (the hand stays where it is in every key; only what it's kept from changes)
        local snap = {}
        local keep = E.key
        local key = side == "r" and "HR" or "HL"
        for i in ipairs(E.pose.keys) do
            E.key = i
            rebuild()
            local d = dbg()
            snap[i] = d and d[key] and mat(d[key]:GetTranslation(), d[key]:GetAngles())
        end
        E.key = keep
        for i in ipairs(E.pose.keys) do
            if not snap[i] then msg("Couldn't read the hand in key " .. i .. ": nothing changed.") return end
        end
        local old = cfg.rel
        cfg.rel = rel
        storeHandAllKeys(side, rel, function(i) return snap[i] end)
        -- (a frame that isn't there now, e.g. no gun: put it back)
        if not ikFrame(rel) then cfg.rel = old msg("Nothing to keep it from right now: nothing changed.") end
        changed()
    end

    -- Hand poses per hand: the fingers as an animation has them (or a saved
    -- hand preset), copied into the key from the hand, so they sit right
    -- wherever the hand is. Presets: data/rhylib_hand_presets.json,
    -- { [name] = { side = "R"|"L", fingers = { [bone] = { p, y, r } } } }
    -- (each finger's turn from the hand).
    local PRESETS = "rhylib_hand_presets.json"
    local function loadPresets() return util.JSONToTable(file.Read(PRESETS, "DATA") or "") or {} end
    local handPose = { r = { src = "seq:idle_ar2", cycle = 0 }, l = { src = "seq:idle_ar2", cycle = 0 } }
    local function fingerNames(SIDE)
        return ordered(function(n) return string.find(n, SIDE .. "_Finger", 1, true) ~= nil end)
    end
    -- the fingers' turns from the hand, for one hand, from a source
    local function fingerRel(SIDE, src, cycle)
        local hand = "ValveBiped.Bip01_" .. SIDE .. "_Hand"
        if string.sub(src, 1, 4) == "seq:" then
            local smp = sampleModel(string.sub(src, 5), cycle)
            local hs = smp[hand]
            if not hs then return nil end
            local out = {}
            for _, n in ipairs(fingerNames(SIDE)) do
                if smp[n] then
                    local _, rel = WorldToLocal(vector_origin, smp[n], vector_origin, hs)
                    out[n] = rel
                end
            end
            return out
        end
        local pr = loadPresets()[string.sub(src, 8)]
        if not pr or pr.side ~= SIDE then return nil end
        local out = {}
        for n, a in pairs(pr.fingers or {}) do out[n] = Angle(a[1], a[2], a[3]) end
        return out
    end
    local function applyHandPose(side, allKeys)
        local SIDE = side == "r" and "R" or "L"
        local hp = handPose[side]
        local rel = fingerRel(SIDE, hp.src, hp.cycle)
        if not rel or not next(rel) then msg("That hand pose has no fingers for this hand / model.") return end
        pushUndo()
        E.playing, E.scrub, E.live = false, nil, false
        local hand = "ValveBiped.Bip01_" .. SIDE .. "_Hand"
        local keep = E.key
        local first, last = E.key, E.key
        if allKeys then first, last = 1, #E.pose.keys end
        for i = first, last do
            E.key = i
            for _, n in ipairs(fingerNames(SIDE)) do
                rebuild()
                local Hw = worldOf(hand)
                if rel[n] and Hw then
                    local _, wt = LocalToWorld(vector_origin, rel[n], vector_origin, Hw:GetAngles())
                    setWorldAng(n, wt)
                end
            end
        end
        E.key = keep
        changed()
    end
    local function savePreset(side)
        local SIDE = side == "r" and "R" or "L"
        local hand = "ValveBiped.Bip01_" .. SIDE .. "_Hand"
        Rhylib.UI.Kit.Prompt("Save hand pose", "Name it (e.g. Rifle grip " .. (side == "r" and "right" or "left") .. ")", "", function(txt)
            local nm = Po.CleanName(txt)
            if nm == "" then return end
            rebuild()
            local Hw = worldOf(hand)
            if not Hw then return end
            local fingers = {}
            for _, n in ipairs(fingerNames(SIDE)) do
                local W = worldOf(n)
                if W then
                    local _, rel = WorldToLocal(vector_origin, W:GetAngles(), vector_origin, Hw:GetAngles())
                    fingers[n] = { math.Round(rel.p, 2), math.Round(rel.y, 2), math.Round(rel.r, 2) }
                end
            end
            local all = loadPresets()
            all[nm] = { side = SIDE, fingers = fingers }
            file.Write(PRESETS, util.TableToJSON(all, true) or "")
            handPose[side].src = "preset:" .. nm
            info2("Hand pose \"" .. nm .. "\" saved (" .. (side == "r" and "right" or "left") .. " hand).")
        end)
    end
    local function handPoseOptions(side)
        local SIDE = side == "r" and "R" or "L"
        local out = {}
        for nm, pr in SortedPairs(loadPresets()) do
            if pr.side == SIDE then out[#out + 1] = { "preset:" .. nm, "★ " .. nm } end
        end
        local seqs = {}
        for _, sq in pairs(T:GetSequenceList() or {}) do seqs[#seqs + 1] = sq end
        table.sort(seqs)
        for _, sq in ipairs(seqs) do out[#out + 1] = { "seq:" .. sq, sq } end
        return out
    end

    -- Copy / paste a hand (the shown key): its fingers and its hand IK
    -- target. Onto the same hand: the values as they are; onto the other
    -- hand: mirrored (fingers from the hand, the target across the body).
    local function handBone(SIDE) return "ValveBiped.Bip01_" .. SIDE .. "_Hand" end
    local function copyHand(side)
        local SIDE = side == "r" and "R" or "L"
        local k = curKey()
        -- (copy what the key shows, not the loop or the weapon's pose)
        E.playing, E.scrub, E.live = false, nil, false
        rebuild()
        local Hw = worldOf(handBone(SIDE))
        local c = { side = side, bones = {}, rel = {} }
        for _, n in ipairs(fingerNames(SIDE)) do
            if k.bones[n] then c.bones[n] = copyPose(k.bones[n]) end
            local W = worldOf(n)
            if W and Hw then
                local _, r = WorldToLocal(vector_origin, W:GetAngles(), vector_origin, Hw:GetAngles())
                c.rel[n] = r
            end
        end
        if E.pose.ik and E.pose.ik[side] and k.hand and k.hand[side] then
            c.ik = copyPose(k.hand[side])
            local d = dbg()
            local Hm = d and d[side == "r" and "HR" or "HL"]
            if Hm then
                local pos, ang = entFrame()
                local lp, la = WorldToLocal(Hm:GetTranslation(), Hm:GetAngles(), pos, ang)
                c.ikEnt = { lp, la }
            end
        end
        E.clip.hand = c
    end
    local function pasteHand(side)
        local c = E.clip.hand
        if not c then return end
        local SIDE = side == "r" and "R" or "L"
        local ikOn = E.pose.ik and E.pose.ik[side]
        local ref
        if c.side ~= side then
            ref = sampleModel("reference", 0)
            if not (ref[handBone("R")] and ref[handBone("L")]) then msg("This model has no hands to mirror with.") return end
        end
        pushUndo()
        E.playing, E.scrub, E.live = false, nil, false
        local k = curKey()
        if c.side == side then
            for _, n in ipairs(fingerNames(SIDE)) do k.bones[n] = c.bones[n] and copyPose(c.bones[n]) or nil end
            if c.ik and ikOn then
                k.hand = k.hand or {}
                k.hand[side] = copyPose(c.ik)
            end
            changed()
            return
        end
        local srcH, dstH = handBone(SIDE == "R" and "L" or "R"), handBone(SIDE)
        -- (the target first, reflected across the body's middle)
        if c.ikEnt and ikOn then
            local lp, la = c.ikEnt[1], c.ikEnt[2]
            local _, ma = LocalToWorld(vector_origin, refDiff(ref, srcH, dstH), vector_origin, reflect(la))
            local pos, ang = entFrame()
            local wp, wa = LocalToWorld(Vector(lp.x, -lp.y, lp.z), ma, pos, ang)
            rebuild()
            local F = ikFrame(ikOn.rel)
            if F then
                local l = mat(F:GetTranslation(), F:GetAngles()):GetInverseTR() * mat(wp, wa)
                k.hand = k.hand or {}
                k.hand[side] = { p = vt(l:GetTranslation()), a = at(l:GetAngles()) }
            end
        end
        for _, n in ipairs(fingerNames(SIDE)) do
            local src = otherSide(n)
            local r = src and c.rel[src]
            if r and ref[src] and ref[n] then
                local rel2 = mirrorRel(ref, srcH, dstH, src, n, r)
                rebuild()
                local Hw = worldOf(dstH)
                if Hw then
                    local _, wt = LocalToWorld(vector_origin, rel2, vector_origin, Hw:GetAngles())
                    setWorldAng(n, wt)
                end
            end
        end
        changed()
    end
    -- A saved hand pose mirrored for the other hand (a new saved one).
    local function mirrorPreset(side)
        local src = handPose[side].src
        if string.sub(src, 1, 7) ~= "preset:" then msg("Pick a saved hand pose (★) first.") return end
        local nm = string.sub(src, 8)
        local all = loadPresets()
        local pr = all[nm]
        if not pr or (pr.side ~= "R" and pr.side ~= "L") then return end
        local OTHER = pr.side == "R" and "L" or "R"
        local ref = sampleModel("reference", 0)
        local srcH, dstH = handBone(pr.side), handBone(OTHER)
        if not (ref[srcH] and ref[dstH]) then msg("This model has no hands to mirror with.") return end
        local fingers = {}
        for n, a in pairs(pr.fingers or {}) do
            local dst = otherSide(n)
            if dst and ref[n] and ref[dst] and istable(a) then
                local r = mirrorRel(ref, srcH, dstH, n, dst, Angle(tonumber(a[1]) or 0, tonumber(a[2]) or 0, tonumber(a[3]) or 0))
                fingers[dst] = { math.Round(r.p, 2), math.Round(r.y, 2), math.Round(r.r, 2) }
            end
        end
        if not next(fingers) then msg("That hand pose has no fingers this model can mirror.") return end
        local newName = nm .. " (mirrored)"
        all[newName] = { side = OTHER, fingers = fingers }
        file.Write(PRESETS, util.TableToJSON(all, true) or "")
        handPose[OTHER == "R" and "r" or "l"].src = "preset:" .. newName
        info2("Hand pose \"" .. newName .. "\" saved (" .. (OTHER == "R" and "right" or "left") .. " hand).")
    end

    f:AddTab("Hands", function(pg)
        pg:Heading("Hand IK")
        pg:Note("With Hand IK on, the hand's pink dot is a target: Move (W) puts the hand there, Rotate (E) turns it, and the shoulder and elbow follow. The elbow dots choose which way each arm bends. Every key has its own target.")
        for _, sd in ipairs({ { "r", "Right" }, { "l", "Left" } }) do
            local side = sd[1]
            pg:Heading(sd[2] .. " hand")
            pg:Toggle(sd[2] .. " hand IK", function() return E.pose.ik and E.pose.ik[side] and true or false end, function(v) ikToggle(side, v) end)
            pg:Choice("Kept from", { { "chest", "The chest (moves with the upper body)" }, { "hips", "The hips" }, { "gun", "The gun (a point on the weapon)" } },
                function() local c = E.pose.ik and E.pose.ik[side] return c and c.rel or "chest" end,
                function(v)
                    if not (E.pose.ik and E.pose.ik[side]) then msg("Switch " .. sd[2] .. " hand IK on first.") return end
                    ikSetRel(side, v)
                end)
            pg:Buttons({
                { "Pick its dot", function() if E.pose.ik and E.pose.ik[side] then E.sel = "@" .. side .. "handik" end end },
                { "Reset its elbow (this key)", function()
                    local k = curKey()
                    if not (k.elbow and k.elbow[side]) then return end
                    pushUndo()
                    k.elbow[side] = nil
                    if not next(k.elbow) then k.elbow = nil end
                    changed()
                end },
            })
            pg:Note(sd[2] .. " hand pose (the fingers): an animation's, or a saved one (★).")
            pg:Choice("Hand pose", function() return handPoseOptions(side) end, function() return handPose[side].src end, function(v) handPose[side].src = v end)
            pg:Slider("Point in it", 0, 1, 2, function() return handPose[side].cycle end, function(v) handPose[side].cycle = v end)
            pg:Buttons({
                { "Apply to this key", function() applyHandPose(side, false) end, { accent = true } },
                { "Apply to all keys", function() applyHandPose(side, true) end },
                { "Save this hand as a hand pose", function() savePreset(side) end },
                { "Delete the picked saved one", function()
                    local src = handPose[side].src
                    if string.sub(src, 1, 7) ~= "preset:" then msg("Pick a saved hand pose (★) first.") return end
                    local all = loadPresets()
                    all[string.sub(src, 8)] = nil
                    file.Write(PRESETS, util.TableToJSON(all, true) or "")
                    handPose[side].src = "seq:idle_ar2"
                end, { danger = true } },
                { "Mirror the picked saved one to the other hand", function() mirrorPreset(side) end },
            })
            pg:Buttons({
                { "Copy hand", function() copyHand(side) end },
                { function()
                    local c = E.clip.hand
                    if c and c.side ~= side then return "Paste hand (mirrored)" end
                    return "Paste hand"
                end, function() pasteHand(side) end, { enabled = function() return E.clip.hand ~= nil end } },
            }, { wrap = true })
        end
        pg:Note("Both hands on points of the gun: set each to \"The gun\". The right hand then needs the gun to move with the pose (it's switched on for you); the left works with the gun as held. Hand IK wins over Gun-tab grips and Spots locks for that hand.")
    end)

    -- Recoil and aim lines (the weapon in your hands): the weapon's fire
    -- gesture, recoil pose and kick (Po.gear[class].recoil), a visual fire
    -- loop, and lines for where bolts go vs where the barrel points.
    local function rcOf(class, make)
        local g = class and (make and gearOf(class) or Po.gear[class])
        if not g then return nil end
        if make and not g.recoil then g.recoil = { back = 0, up = 0, side = 0, length = 0.2, strength = 1 } end
        return g.recoil
    end
    local function rcSet(key, v)
        local class = heldClass()
        if not class then msg("Hold the weapon first (Weapon poses: Hold it).") return end
        pushUndo(true)
        local rc = rcOf(class, true)
        rc[key] = v
        sendGear(class)
    end
    local function rcGet(key, d)
        local rc = rcOf(heldClass(), false)
        local v = rc and rc[key]
        if v == nil then return d end
        return v
    end
    E.fire, E.fireRPM = false, nil
    E.lines = { bolt = true, barrel = true, muzzle = true }
    local nextShot, flashUntil = 0, 0
    local function fireSound(w)
        local snd = w.FireSound
        if istable(snd) then snd = snd[math.random(#snd)] end
        return isstring(snd) and snd or nil
    end
    Rhylib.Hook.Add("Think", "devtools.posefire", function()
        if not IsValid(editor) then
            E.fire = false
            Rhylib.Hook.Remove("Think", "devtools.posefire")
            return
        end
        if not E.fire then return end
        local w = me:GetActiveWeapon()
        if not IsValid(w) then return end
        local now = CurTime()
        if now < nextShot then return end
        local rpm = math.Clamp(E.fireRPM or (w.CurrentFireRate and w:CurrentFireRate()) or w.FireRate or 600, 20, 1500)
        nextShot = now + 60 / rpm
        -- (visual only: the recoil, gesture, flash and sound; no bolt, no ammo)
        Po.fakeShot[me] = now
        flashUntil = RealTime() + 0.05
        local rc = rcOf(w:GetClass(), false)
        local gest = rc and rc.gesture
        local act
        if gest == "none" then
            act = nil
        elseif gest then
            act = _G[gest]
        elseif w.TranslateActivity then
            act = w:TranslateActivity(me:Crouching() and ACT_MP_ATTACK_CROUCH_PRIMARYFIRE or ACT_MP_ATTACK_STAND_PRIMARYFIRE)
            if not act or act < 0 then act = w.ActivityTranslate and w.ActivityTranslate[ACT_MP_ATTACK_STAND_PRIMARYFIRE] end
        end
        if isnumber(act) and act > 0 then me:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, act, true) end
        local snd = fireSound(w)
        if snd then me:EmitSound(snd, math.min(w.FireSoundLevel or 75, 100), 100 * (w.FireSoundPitch or 1), 0.6, CHAN_WEAPON) end
    end)
    -- The lines: blue = where bolts really go (from your eyes along your
    -- aim), red = straight out of the barrel, yellow = the muzzle point.
    local FLASH = Material("sprites/light_glow02_add")
    local function gunAndMuzzle()
        local w = me:GetActiveWeapon()
        local inf = Po.ModelInfo(me)
        if not (IsValid(w) and inf) then return nil end
        local G = Po.GunWorldOf(me, inf)
        if not G then return nil end
        local muzzle = w.propMuzzleWM
        if not muzzle or (w.rhylibMuzzleF or 0) < FrameNumber() - 2 then
            local _, _, _, mp = Po.WeaponProp(w)
            muzzle = G:GetTranslation() + G:GetForward() * mp.x + G:GetRight() * -mp.y + G:GetUp() * mp.z
        end
        return G, muzzle
    end
    local aimOff
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "devtools.poselines", function(depth, sky)
        if depth or sky then return end
        if not IsValid(editor) then
            Rhylib.Hook.Remove("PostDrawTranslucentRenderables", "devtools.poselines")
            return
        end
        aimOff = nil
        if T ~= me then return end
        local G, muzzle = gunAndMuzzle()
        local eye, dir = me:GetShootPos(), me:GetAimVector()
        local tr = util.TraceLine({ start = eye, endpos = eye + dir * 4000, filter = me })
        render.SetColorMaterial()
        if E.lines.bolt then
            render.DrawBeam(eye + dir * 20, tr.HitPos, 0.4, 0, 1, Color(80, 170, 255, 230))
            render.DrawSphere(tr.HitPos, 1.5, 8, 8, Color(80, 170, 255, 230))
        end
        if G and muzzle then
            local bdir = G:GetForward()
            if E.lines.barrel then
                local tb = util.TraceLine({ start = muzzle, endpos = muzzle + bdir * 4000, filter = me })
                render.DrawBeam(muzzle, tb.HitPos, 0.4, 0, 1, Color(255, 80, 70, 230))
                render.DrawSphere(tb.HitPos, 1.5, 8, 8, Color(255, 80, 70, 230))
            end
            if E.lines.muzzle then render.DrawSphere(muzzle, 0.8, 8, 8, Color(255, 220, 60, 255)) end
            -- (how far the barrel points off the bolts' aim point)
            local want = (tr.HitPos - muzzle):GetNormalized()
            aimOff = math.deg(math.acos(math.Clamp(want:Dot(bdir), -1, 1)))
            if RealTime() < flashUntil then
                render.SetMaterial(FLASH)
                render.DrawSprite(muzzle, 14, 14, Color(140, 200, 255, 255))
            end
        end
    end)

    -- Gun model: the weapon's third-person hold, size and muzzle point,
    -- saved per weapon on the server over the weapon file's values.
    local pg_wm
    local function wmOf(class, make)
        local g = class and (make and gearOf(class) or Po.gear[class])
        if not g then return nil end
        if make and not g.wm then
            local w = me:GetActiveWeapon()
            local p0, a0, s0 = Po.WeaponProp(w)
            g.wm = { p = { p0.x, p0.y, p0.z }, a = { a0.p, a0.y, a0.r }, s = s0 }
        end
        return g.wm
    end
    local function wmNum(text, key, i, step, lo, hi)
        pg_wm:Number(text, step, lo, hi, function()
            local w = me:GetActiveWeapon()
            if not IsValid(w) then return 0 end
            local p0, a0, s0 = Po.WeaponProp(w)
            if key == "s" then return s0 end
            local v = key == "p" and p0 or a0
            return key == "p" and ({ v.x, v.y, v.z })[i] or ({ v.p, v.y, v.r })[i]
        end, function(v)
            local class = heldClass()
            if not class then msg("Hold the weapon first (Weapon poses: Hold it).") return end
            pushUndo(true)
            local o = wmOf(class, true)
            if key == "s" then o.s = math.Round(v, 3) else o[key][i] = math.Round(v, 2) end
            sendGear(class)
        end)
    end
    local function muzNum(text, i, step)
        pg_wm:Number(text, step, -200, 200, function()
            local w = me:GetActiveWeapon()
            if not IsValid(w) then return 0 end
            local _, _, _, m = Po.WeaponProp(w)
            return ({ m.x, m.y, m.z })[i]
        end, function(v)
            local class = heldClass()
            if not class then msg("Hold the weapon first (Weapon poses: Hold it).") return end
            local w = me:GetActiveWeapon()
            local _, _, _, m = Po.WeaponProp(w)
            pushUndo(true)
            local g = gearOf(class)
            g.muzzle = g.muzzle or { m.x, m.y, m.z }
            g.muzzle[i] = math.Round(v, 2)
            sendGear(class)
        end)
    end
    f:AddTab("Gun model", function(pg)
        pg_wm = pg
        pg:Heading("The weapon in your hands")
        pg:Note(function() return heldClass() and ("Weapon: " .. heldClass() .. ". Saved for that weapon on the server, for everyone, over the weapon file's numbers.") or "Hold the weapon first (Weapon poses: Hold it)." end)
        pg:Heading("Third-person hold (from the right hand)")
        wmNum("Forward", "p", 1, 0.1, -100, 100)
        wmNum("Right", "p", 2, 0.1, -100, 100)
        wmNum("Up", "p", 3, 0.1, -100, 100)
        wmNum("Pitch", "a", 1, 1, -360, 360)
        wmNum("Yaw", "a", 2, 1, -360, 360)
        wmNum("Roll", "a", 3, 1, -360, 360)
        wmNum("Size", "s", 1, 0.01, 0.05, 5)
        pg:Heading("Muzzle point (where bolts and the flash start)")
        pg:Note("In the gun model's axes: X along the barrel, Y left, Z up. Only where bolts show; where they hit always comes from your aim.")
        muzNum("Muzzle X", 1, 0.25)
        muzNum("Muzzle Y", 2, 0.25)
        muzNum("Muzzle Z", 3, 0.25)
        pg:Toggle("Drag the muzzle (yellow dot, Move / W)", function() return E.muzzleEdit == true end, function(v)
            E.muzzleEdit = v
            E.mode = "move"
            E.sel = v and "@muzzle" or (E.sel ~= "@muzzle" and E.sel or nil)
        end)
        pg:Buttons({
            { "Copy lines for the weapon file", function()
                local w = me:GetActiveWeapon()
                if not IsValid(w) then return end
                local p0, a0, s0, m = Po.WeaponProp(w)
                local text = string.format("SWEP.PropWMPos = Vector(%g, %g, %g)\nSWEP.PropWMAng = Angle(%g, %g, %g)\nSWEP.PropScale = %g\nSWEP.PropMuzzle = Vector(%g, %g, %g)",
                    p0.x, p0.y, p0.z, a0.p, a0.y, a0.r, s0, m.x, m.y, m.z)
                SetClipboardText(text)
                print(text)
                info2("Copied (also printed in the console).")
            end, { accent = true } },
            { "Back to the weapon file's numbers", function()
                local class = heldClass()
                if not (class and Po.gear[class]) then return end
                pushUndo(true)
                Po.gear[class].wm, Po.gear[class].muzzle = nil, nil
                sendGear(class)
            end, { danger = true } },
        })
        pg:Note("Size here is the third-person model; the first-person gun keeps its own. While these are set, rhylib_wm_editor's changes don't show for this weapon (Back to the file's numbers first).")
    end)

    f:AddTab("Recoil", function(pg)
        pg:Heading("Recoil (the weapon in your hands)")
        pg:Note(function() return heldClass() and ("Weapon: " .. heldClass() .. ". Saved for that weapon, for everyone.") or "Hold the weapon first (Weapon poses: Hold it)." end)
        local gopts = { { "@default", "The hold type's own" }, { "none", "None" } }
        for _, g in ipairs(Po.GESTURES or {}) do gopts[#gopts + 1] = { g, (string.gsub(g, "^ACT_HL2MP_GESTURE_RANGE_ATTACK_", "")) } end
        pg:Choice("Fire gesture", gopts, function() return rcGet("gesture", "@default") end, function(v) rcSet("gesture", v ~= "@default" and v or nil) end)
        pg:Choice("Recoil pose", function()
            local out = { { "@none", "None" } }
            for n in SortedPairs(Po.defs) do out[#out + 1] = { n, n } end
            return out
        end, function() return rcGet("pose", "@none") end, function(v) rcSet("pose", v ~= "@none" and v or nil) end)
        pg:Note("A recoil pose is a saved pose (Add mode, key 1) put on top at each shot, eased with the kick: shoulders giving, head flinching...")
        pg:Number("Kick back", 0.1, 0, 20, function() return rcGet("back", 0) end, function(v) rcSet("back", math.Round(v, 2)) end)
        pg:Number("Kick up (°)", 0.5, -30, 30, function() return rcGet("up", 0) end, function(v) rcSet("up", math.Round(v, 2)) end)
        pg:Number("Kick sideways (°, + = muzzle left)", 0.5, -30, 30, function() return rcGet("side", 0) end, function(v) rcSet("side", math.Round(v, 2)) end)
        pg:Number("Length (s)", 0.01, 0.05, 1, function() return rcGet("length", 0.2) end, function(v) rcSet("length", math.Round(v, 3)) end)
        pg:Number("Strength", 0.05, 0, 2, function() return rcGet("strength", 1) end, function(v) rcSet("strength", math.Round(v, 2)) end)
        pg:Buttons({ { "Remove this weapon's recoil", function()
            local class = heldClass()
            if not (class and Po.gear[class]) then return end
            pushUndo(true)
            Po.gear[class].recoil = nil
            sendGear(class)
        end, { danger = true } } })
        pg:Heading("Fire loop (visual only)")
        pg:Toggle("Fire loop: recoil, gesture, flash, sound (no bolts, no ammo)", function() return E.fire end, function(v) E.fire = v nextShot = 0 end)
        pg:Number("Shots a minute", 10, 20, 1500, function()
            local w = me:GetActiveWeapon()
            return E.fireRPM or (IsValid(w) and (w.CurrentFireRate and w:CurrentFireRate() or w.FireRate)) or 600
        end, function(v) E.fireRPM = math.Round(v) end)
        pg:Heading("Aim lines")
        pg:Toggle("Bolt path (blue: from your eyes along your aim)", function() return E.lines.bolt end, function(v) E.lines.bolt = v end)
        pg:Toggle("Barrel line (red: straight out of the muzzle)", function() return E.lines.barrel end, function(v) E.lines.barrel = v end)
        pg:Toggle("Muzzle point (yellow)", function() return E.lines.muzzle end, function(v) E.lines.muzzle = v end)
        pg:Note(function()
            if not aimOff then return "Hold a weapon to see the lines." end
            return string.format("The barrel points %.1f° off the bolts' aim point. Turn the Gun dot (Gun tab) until the red line meets the blue dot.", aimOff)
        end)
    end)

    f:AddTab("Gun", function(pg)
        pg:Heading("The gun in this pose")
        pg:Note("Hold the weapon (Weapon poses: Hold it). Pink dots: Gun, Left grip, Right / Left elbow.")
        pg:Toggle("Gun in the pose", function() return E.pose.anchor ~= nil end, function() gunToggle() end)
        pg:Choice("Gun moves with", { { "chest", "Chest" }, { "hips", "Hips" }, { "rhand", "Right hand" }, { "lhand", "Left hand" } },
            function() return E.pose.anchor or "chest" end, setAnchor)
        local function handOn(side) return not E.pose.hands or E.pose.hands[side] ~= false end
        local function handSet(side, v)
            if not E.pose.anchor then return end
            pushUndo()
            E.pose.hands = E.pose.hands or { r = true, l = true }
            E.pose.hands[side] = v
            changed()
        end
        pg:Toggle("Right hand on the gun", function() return handOn("r") end, function(v) handSet("r", v) end)
        pg:Toggle("Left hand on the gun", function() return handOn("l") end, function(v) handSet("l", v) end)
        pg:Note("Off: that arm poses freely. A hand the gun moves with isn't pulled onto it.")
        pg:Heading("Left grip and elbows")
        pg:Choice("Left grip edits", { { "weapon", "The weapon (all its poses)" }, { "pose", "This pose only" } }, function() return E.gripTo end, function(v) E.gripTo = v end)
        pg:Buttons({
            { "Clear pose grip", function()
                if not E.pose.grip then return end
                pushUndo()
                E.pose.grip = nil
                changed()
            end },
            { "Reset elbows (this key)", function()
                pushUndo()
                curKey().elbow = nil
                changed()
            end },
            { "Rifle grip fingers", rifleFingers },
        })
    end)

    f:AddTab("Spots & IK", function(pg)
        pg:Heading("Spots (the weapon in your hands)")
        pg:Note("A spot is where a hand goes and how it turns. Each is a pink dot to move / rotate.")
        pg:List({ { "Spot", 0.45 }, { "On", 0.3 }, { "Kept in", 0.25 } }, function()
            local spots = allSpots()
            local out = {}
            for n, sp in SortedPairs(spots) do
                local where = (E.pose.spots and E.pose.spots[n]) and "pose" or "weapon"
                out[#out + 1] = { n, { n, sp.parent == "@gun" and "gun" or sp.parent, where } }
            end
            return out
        end, function() return E.spotSel end, function(n) E.spotSel = n E.sel = "@spot:" .. n end, S(110))
        pg:Buttons({
            { function()
                local spots = allSpots()
                return (E.spotSel and spots[E.spotSel]) and ("New spot on " .. E.spotSel) or "New spot on the gun"
            end, newSpot, { accent = true } },
            { "Delete spot", deleteSpot, { danger = true } },
        })
        pg:Choice("New spots go", { { "weapon", "On the weapon" }, { "pose", "In this pose" } }, function() return E.spotTo end, function(v) E.spotTo = v end)
        pg:Heading("Hand IK")
        pg:Choice("Set for", { { "weapon", "The weapon (always while held)" }, { "pose", "This pose (over the weapon's)" } }, function() return E.lockTo end, function(v) E.lockTo = v end)
        local function lockOptions()
            local out = {}
            if E.lockTo == "pose" then
                out[#out + 1] = { "@weapon", "The weapon's" }
                out[#out + 1] = { "@off", "Off in this pose" }
            else
                out[#out + 1] = { "@weapon", "Off" }
            end
            for n in SortedPairs((allSpots())) do out[#out + 1] = { n, "On " .. n } end
            return out
        end
        local function lockGet(side)
            local lt = lockTable(false)
            local v = lt and lt[side]
            if v == false then return "@off" end
            return v or "@weapon"
        end
        local function lockSet(side, v)
            local lt, class = lockTable(true)
            if not lt then msg("Hold the weapon first.") return end
            pushUndo(E.lockTo ~= "pose")
            if v == "@weapon" then lt[side] = nil elseif v == "@off" then lt[side] = false else lt[side] = v end
            if E.lockTo == "pose" then
                if next(lt) == nil then E.pose.lock = nil end
                changed()
            else
                sendGear(class)
            end
        end
        pg:Choice("Left hand", lockOptions, function() return lockGet("l") end, function(v) lockSet("l", v) end)
        pg:Choice("Right hand", lockOptions, function() return lockGet("r") end, function(v) lockSet("r", v) end)
        local function tickGet(key)
            local class = heldClass()
            local lk = class and Po.gear[class] and Po.gear[class].lock
            return lk and lk[key] == true or false
        end
        local function tickSet(key, v)
            local class = heldClass()
            if not class then return end
            pushUndo(true)
            local g = gearOf(class)
            g.lock = g.lock or {}
            g.lock[key] = v or nil
            sendGear(class)
        end
        pg:Toggle("Keep the lock while reloading", function() return tickGet("reload") end, function(v) tickSet("reload", v) end)
        pg:Toggle("Keep it while lowered / on safety", function() return tickGet("lowered") end, function(v) tickSet("lowered", v) end)
        pg:Note("The right hand holds the gun, so its lock only works while a pose moves the gun (Gun tab).")
    end)

    f:AddTab("Weapon poses", function(pg)
        pg:Heading("Weapon")
        pg:Choice(nil, wlist, function() return E.wpn end, function(class)
            timer.Remove("Rhylib.PoseEditorWpn")
            E.wpn, E.wsel = class, nil
            give()
            wpnReload()
        end)
        pg:Buttons({ { "Hold it", give } })
        pg:Heading("Poses it plays (first that fits wins)")
        local function whenText(e)
            local parts = {}
            for _, g in ipairs(Po.FILTERS) do
                local on = {}
                for _, o in ipairs(g.opts) do if e.when[o[1]] then on[#on + 1] = o[2] end end
                parts[#parts + 1] = #on == #g.opts and "any" or #on == 0 and "never" or table.concat(on, "/")
            end
            return table.concat(parts, ", ")
        end
        -- (which row plays on you now, as the runtime picks it: a few times
        -- a second, not each frame)
        E.wplay = nil
        timer.Create("Rhylib.PoseEditorPlaying", 0.25, 0, function()
            if not IsValid(editor) then timer.Remove("Rhylib.PoseEditorPlaying") return end
            local fits, playing = {}, nil
            local st = Po.State(me)
            for i, e in ipairs(entries) do
                fits[i] = Po.EntryFits(e, st) and Po.defs[e.pose] ~= nil
            end
            if E.wpn and heldClass() == E.wpn then playing = Po.WeaponPoseIndex(me, entries) end
            E.wplay = { fits = fits, playing = playing }
        end)
        local PLAY_STYLE = { chip = "PLAYING", chipCol = Color(80, 200, 100) }
        local DIM_STYLE = { dim = true }
        pg:List({ { "Pose", 0.3 }, { "When", 0.7 } }, function()
            local out = {}
            for i, e in ipairs(entries) do out[#out + 1] = { i, { e.pose, whenText(e) } } end
            return out
        end, function() return E.wsel end, function(i) E.wsel = i end, S(110), function(i)
            local wp = E.wplay
            if not wp then return nil end
            if wp.playing == i then return PLAY_STYLE end
            if wp.fits[i] == false then return DIM_STYLE end
            return nil
        end)
        pg:Note(function()
            if not E.wpn or #entries == 0 then return "" end
            local held = heldClass()
            if held ~= E.wpn then return "Hold it (Hold it, above) to see which row plays on you now." end
            local wp = E.wplay
            local i = wp and wp.playing
            if not i then return "Greyed rows don't fit what you do now; none fits, so no weapon pose plays." end
            local t = "Row " .. i .. " is the first that fits: it plays on you"
            if me:GetNW2String("rhylib_pose", "") ~= "" then return t .. ", but a !pose plays over it." end
            if not E.live then return t .. " once the editor's pose is paused (below)." end
            return t .. "."
        end)
        pg:Buttons({
            { "Use this pose here", function()
                local n = Po.CleanName(E.name)
                if not E.wpn then msg("Pick a weapon first.") return end
                if not Po.defs[n] then msg("Save the pose to the server first (it needs a name).") return end
                if #entries >= 16 then msg("A weapon can have 16 poses at most.") return end
                entries[#entries + 1] = { pose = n, when = table.Copy(Po.DEFAULT_WHEN) }
                E.wsel = #entries
                sendWpn()
            end, { accent = true } },
            { "Remove", function()
                if not E.wsel or not entries[E.wsel] then return end
                table.remove(entries, E.wsel)
                E.wsel = nil
                sendWpn()
            end, { danger = true } },
            { "Up", function()
                local i = E.wsel
                if not i or i <= 1 then return end
                entries[i], entries[i - 1] = entries[i - 1], entries[i]
                E.wsel = i - 1
                sendWpn()
            end },
            { "Down", function()
                local i = E.wsel
                if not i or i >= #entries then return end
                entries[i], entries[i + 1] = entries[i + 1], entries[i]
                E.wsel = i + 1
                sendWpn()
            end },
        })
        pg:Heading("When the picked row plays")
        for _, g in ipairs(Po.FILTERS) do
            pg:Note(g.name)
            local opts = {}
            for _, o in ipairs(g.opts) do opts[#opts + 1] = { o[1], o[2] } end
            pg:Chips(opts, function(id)
                local e = E.wsel and entries[E.wsel]
                return e and e.when[id] or false
            end, function(id)
                local e = E.wsel and entries[E.wsel]
                if not e then msg("Pick a row first.") return end
                e.when[id] = (not e.when[id]) or nil
                sendWpn()
            end)
        end
        pg:Space(6)
        pg:Toggle("Pause the editor's pose (see the weapon poses play on you)", function() return E.live == true end, function(v) E.live = v updatePreview() end)
    end)

    f:AddTab("Sling", function(pg)
        pg:Heading("Sling spot")
        pg:Note(function() return "For the weapon picked under Weapon poses" .. (E.wpn and (": " .. E.wpn) or " (none yet)") .. ". It shows on the body while carried but not held." end)
        local opts = {}
        for _, b in ipairs(SLING_BONES) do opts[#opts + 1] = { "ValveBiped.Bip01_" .. b, b } end
        pg:Choice("On bone", function()
            local out = { { "", slingOf(E.wpn) and "—" or "No spot" } }
            for _, o in ipairs(opts) do out[#out + 1] = o end
            return out
        end, function() local sl = slingOf(E.wpn) return sl and sl.bone or "" end, function(bone)
            if not E.wpn or bone == "" then return end
            pushUndo(true)
            local g = gearOf(E.wpn)
            local sl = g.sling
            g.sling = { bone = bone, p = sl and sl.p or { 0, 0, 0 }, a = sl and sl.a or { 0, 0, 0 } }
            E.slingEdit, E.sel = true, "@sling"
            sendGear(E.wpn)
        end)
        pg:Buttons({
            { function() return E.slingEdit and "Stop editing spot" or "Edit spot" end, function()
                if not slingOf(E.wpn) then msg("Pick a bone first.") return end
                E.slingEdit = not E.slingEdit
                E.sel = E.slingEdit and "@sling" or nil
            end },
            { "Remove spot", function()
                if not (E.wpn and Po.gear[E.wpn]) then return end
                pushUndo(true)
                Po.gear[E.wpn].sling = nil
                E.slingEdit = false
                if E.sel == "@sling" then E.sel = nil end
                sendGear(E.wpn)
            end, { danger = true } },
        })
    end)

    f:AddTab("Tools", function(pg)
        pg:Heading("Mirror")
        pg:Note("In Add mode it's matched to the animation playing now.")
        local function sideBones(side)
            return ordered(function(n) return string.find(n, side, 1, true) ~= nil and shown[groupOf(n)] end)
        end
        pg:Buttons({
            { "Left → right", function() mirror(sideBones("_L_")) end },
            { "Right → left", function() mirror(sideBones("_R_")) end },
            { "Selected → other side", function() if E.sel and otherSide(E.sel) then mirror({ E.sel }) end end },
        })
        pg:Heading("Copy from an animation")
        pg:Choice("Animation", function()
            local out = {}
            for _, s in pairs(T:GetSequenceList() or {}) do out[#out + 1] = { s, s } end
            table.sort(out, function(a, b) return a[1] < b[1] end)
            return out
        end, function() return seqName end, function(v) seqName = v end)
        local cycle = 0.5
        pg:Slider("Point in it", 0, 1, 2, function() return cycle end, function(v) cycle = v end)
        pg:Buttons({
            { "Copy shown groups", function() copyAnim(seqName, cycle, ordered(function(n) return shown[groupOf(n)] end)) end },
            { "Copy selected bone", function() if E.sel then copyAnim(seqName, cycle, { E.sel }) end end },
        })
        pg:Note("In Add mode the copy sits on top of the animation playing now.")
    end)

    f:Show("Pose")
    refreshAll = function() end
    changed()

    --------------------------------------------------------------------
    -- The bones on the model, and the gizmo
    --------------------------------------------------------------------
    local AXCOL = { Color(235, 70, 70), Color(80, 220, 90), Color(80, 140, 255) }
    local function scr(v) local t = v:ToScreen() return t.x, t.y, t.visible end
    local function segDist(px, py, ax, ay, bx, by)
        local vx, vy = bx - ax, by - ay
        local l2 = vx * vx + vy * vy
        local t = l2 > 0 and math.Clamp(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1) or 0
        return math.sqrt((px - ax - vx * t) ^ 2 + (py - ay - vy * t) ^ 2)
    end
    local function ringPts(p, axis, r)
        local u = axis:Cross(math.abs(axis.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)):GetNormalized()
        local v = axis:Cross(u)
        local pts = {}
        for i = 0, 32 do
            local a = i / 32 * math.pi * 2
            pts[#pts + 1] = p + u * (math.cos(a) * r) + v * (math.sin(a) * r)
        end
        return pts
    end
    local function gizmoLen() return math.max(3, orbit.dist * 0.12) end
    -- Snapping while Shift is held (Ctrl too: fine turns).
    local function snapKeys()
        local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
        local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
        return shift, shift and ctrl
    end
    local function snapTo(v, s) return math.Round(v / s) * s end
    local function axes(name)
        if E.space == "world" then return { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1) } end
        local W = worldOf(name)
        local a = W and W:GetAngles() or Angle()
        return { a:Forward(), a:Right(), a:Up() }
    end
    local function visibleBones()
        local inf = info()
        local out = {}
        if not inf then return out end
        for id, n in pairs(inf.names) do
            if shown[groupOf(n)] then
                local m = T:GetBoneMatrix(id)
                if m then out[#out + 1] = { id = id, name = n, pos = m:GetTranslation() } end
            end
        end
        local list = { { "@muzzle", "Muzzle" }, { "@rhandik", "Right hand IK" }, { "@lhandik", "Left hand IK" }, { "@gun", "Gun" }, { "@lgrip", "Left grip" }, { "@relbow", "Right elbow" }, { "@lelbow", "Left elbow" }, { "@sling", "Sling spot" } }
        local class = heldClass()
        if class and T == me then
            local lk = Po.LockFor(Po.gear[class] or {}, E.pose)
            for n in SortedPairs(lk.spots) do list[#list + 1] = { "@spot:" .. n, "Spot: " .. n } end
        end
        for _, sp in ipairs(list) do
            local m = specialWorld(sp[1])
            if m then out[#out + 1] = { id = -1, name = sp[1], label = sp[2], pos = m:GetTranslation(), special = true } end
        end
        return out
    end

    Rhylib.Hook.Add("HUDPaint", "devtools.posegizmo", function()
        if not IsValid(editor) then return end
        local inf = info()
        if not inf then return end
        local key = curKey()
        local vis = visibleBones()
        local byId = {}
        for _, b in ipairs(vis) do if not b.special then byId[b.id] = b end end
        surface.SetDrawColor(255, 255, 255, 120)
        for _, b in ipairs(vis) do
            local p = not b.special and byId[inf.parent[b.id]]
            if p then
                local x1, y1 = scr(b.pos)
                local x2, y2 = scr(p.pos)
                surface.DrawLine(x1, y1, x2, y2)
            end
        end
        for _, b in ipairs(vis) do
            local x, y = scr(b.pos)
            local on = b.name == E.sel
            local col = on and Color(255, 210, 60) or b.special and Color(255, 140, 220) or key.bones[b.name] and Color(90, 210, 255) or Color(230, 235, 240, 200)
            draw.RoundedBox(b.special and 2 or 3, x - (b.special and 6 or 4), y - (b.special and 6 or 4), b.special and 12 or 8, b.special and 12 or 8, col)
            if b.special then
                draw.SimpleTextOutlined(b.label, "DermaDefault", x + 9, y - 9, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black)
            elseif on then
                draw.SimpleTextOutlined(string.gsub(b.name, "^ValveBiped%.Bip01_", ""), "DermaDefault", x + 8, y - 8, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black)
            end
        end
        if not E.sel then return end
        local W = worldOf(E.sel)
        if not W then return end
        local pos, L, ax = W:GetTranslation(), gizmoLen(), axes(E.sel)
        local px, py = scr(pos)
        for i = 1, 3 do
            local c = (E.drag and E.drag.axis == i) and Color(255, 230, 80) or AXCOL[i]
            surface.SetDrawColor(c)
            if E.mode == "move" then
                local qx, qy = scr(pos + ax[i] * L)
                surface.DrawLine(px, py, qx, qy)
                surface.DrawLine(px + 1, py, qx + 1, qy)
                draw.RoundedBox(2, qx - 3, qy - 3, 6, 6, c)
            else
                local pts = ringPts(pos, ax[i], L)
                for k = 1, #pts - 1 do
                    local x1, y1 = scr(pts[k])
                    local x2, y2 = scr(pts[k + 1])
                    surface.DrawLine(x1, y1, x2, y2)
                end
            end
        end
        if E.mode == "move" then
            surface.SetDrawColor(255, 255, 255, E.drag and E.drag.plane and 255 or 150)
            surface.DrawOutlinedRect(px - 5, py - 5, 10, 10)
        end
        -- (while dragging: how far so far, and the snap keys)
        local dr = E.drag
        local snap, fine = snapKeys()
        local txt
        if dr and dr.plane then
            txt = string.format("%+.2f, %+.2f", dr.sx, dr.sy)
        elseif dr then
            txt = E.mode == "move" and string.format("%+.2f", dr.done) or string.format("%+.1f°", dr.done)
        end
        if txt then
            txt = txt .. (snap and (E.mode == "move" and "  snap 0.5" or (fine and "  snap 5°" or "  snap 15°")) or "  (Shift: snap · Shift+Ctrl: 5°)")
            draw.SimpleTextOutlined(txt, "DermaDefault", px + 12, py + 12, Color(255, 230, 80), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
        end
    end)

    Rhylib.Hook.Add("GUIMousePressed", "devtools.posegizmo", function(code)
        if not IsValid(editor) or code ~= MOUSE_LEFT then return end
        -- (clicks on the window itself are for the window)
        local hov = vgui.GetHoveredPanel()
        if IsValid(hov) and hov ~= vgui.GetWorldPanel() then return end
        local mx, my = gui.MouseX(), gui.MouseY()
        if E.sel then
            local W = worldOf(E.sel)
            if W then
                local pos, L, ax = W:GetTranslation(), gizmoLen(), axes(E.sel)
                local px, py = scr(pos)
                if E.mode == "move" and math.abs(mx - px) <= 7 and math.abs(my - py) <= 7 then
                    pushUndo()
                    E.drag = { plane = true, x = mx, y = my, tx = 0, ty = 0, sx = 0, sy = 0 }
                    return
                end
                for i = 1, 3 do
                    local hit = false
                    if E.mode == "move" then
                        local qx, qy = scr(pos + ax[i] * L)
                        hit = segDist(mx, my, px, py, qx, qy) <= 7
                    else
                        local pts = ringPts(pos, ax[i], L)
                        for k = 1, #pts - 1 do
                            local x1, y1 = scr(pts[k])
                            local x2, y2 = scr(pts[k + 1])
                            if segDist(mx, my, x1, y1, x2, y2) <= 7 then hit = true break end
                        end
                    end
                    if hit then
                        pushUndo()
                        -- (total: the whole drag so far; done: what's been applied,
                        -- snapped while Shift is held)
                        E.drag = { axis = i, x = mx, y = my, total = 0, done = 0 }
                        return
                    end
                end
            end
        end
        -- (the nearest bone dot under the mouse)
        -- (dots on top of each other, e.g. a hand and its pink IK dot: the
        -- first click picks the pink one, clicking again steps to the next)
        local hits = {}
        for _, b in ipairs(visibleBones()) do
            local x, y = scr(b.pos)
            local d = math.max(math.abs(mx - x), math.abs(my - y))
            if d < 10 then hits[#hits + 1] = { name = b.name, d = d, special = b.special } end
        end
        table.sort(hits, function(a, b)
            if math.abs(a.d - b.d) > 3 then return a.d < b.d end
            if (a.special and true or false) ~= (b.special and true or false) then return a.special and true or false end
            return a.name < b.name
        end)
        local best = hits[1] and hits[1].name
        for i, h in ipairs(hits) do
            if h.name == E.sel and #hits > 1 then best = hits[i % #hits + 1].name break end
        end
        E.sel = best
        refreshAll()
    end)
    Rhylib.Hook.Add("GUIMouseReleased", "devtools.posegizmo", function(code)
        if code == MOUSE_LEFT and E.drag then
            E.drag = nil
            updatePreview()
            backup()
            refreshAll()
        end
    end)
    Rhylib.Hook.Add("Think", "devtools.posegizmo", function()
        if not IsValid(editor) then
            E.drag = nil
            Rhylib.Hook.Remove("HUDPaint", "devtools.posegizmo")
            Rhylib.Hook.Remove("GUIMousePressed", "devtools.posegizmo")
            Rhylib.Hook.Remove("GUIMouseReleased", "devtools.posegizmo")
            Rhylib.Hook.Remove("Think", "devtools.posegizmo")
            return
        end
        if E.playing or E.testFade then updatePreview() end
        local dr = E.drag
        if not dr or not E.sel then return end
        if not input.IsMouseDown(MOUSE_LEFT) then E.drag = nil return end
        local mx, my = gui.MouseX(), gui.MouseY()
        local dx, dy = mx - dr.x, my - dr.y
        if dx == 0 and dy == 0 then return end
        -- (editing shows the key, not the loop)
        E.playing, E.scrub = false, nil
        rebuild()
        local W = worldOf(E.sel)
        if not W then return end
        local pos = W:GetTranslation()
        local snap, fine = snapKeys()
        if dr.plane then
            local va = orbit.viewAng or EyeAngles()
            local k = orbit.dist * 0.0025
            dr.tx, dr.ty = dr.tx + dx * k, dr.ty - dy * k
            local wx, wy = dr.tx, dr.ty
            if snap then wx, wy = snapTo(wx, 0.5), snapTo(wy, 0.5) end
            local mx2, my2 = wx - dr.sx, wy - dr.sy
            if mx2 ~= 0 or my2 ~= 0 then moveBone(E.sel, va:Right() * mx2 + va:Up() * my2) end
            dr.sx, dr.sy = wx, wy
        elseif E.mode == "move" then
            local ax = axes(E.sel)[dr.axis]
            local L = gizmoLen()
            local px, py = scr(pos)
            local qx, qy = scr(pos + ax * L)
            local sx, sy = qx - px, qy - py
            local l2 = sx * sx + sy * sy
            if l2 > 1 then
                dr.total = dr.total + (dx * sx + dy * sy) / l2 * L
                local want = snap and snapTo(dr.total, 0.5) or dr.total
                if want ~= dr.done then moveBone(E.sel, ax * (want - dr.done)) end
                dr.done = want
            end
        else
            local ax = axes(E.sel)[dr.axis]
            local px, py = scr(pos)
            local dA = math.deg(math.atan2(my - py, mx - px) - math.atan2(dr.y - py, dr.x - px))
            dA = (dA + 180) % 360 - 180
            local facing = ax:Dot((orbit.viewPos or EyePos()) - pos) > 0
            dr.total = dr.total + (facing and -dA or dA)
            local want = snap and snapTo(dr.total, fine and 5 or 15) or dr.total
            if want ~= dr.done then
                local target = W:GetAngles()
                target:RotateAroundAxis(ax, want - dr.done)
                turnBone(E.sel, target)
            end
            dr.done = want
        end
        dr.x, dr.y = mx, my
        rebuild()
    end)
end)
