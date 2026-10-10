# rhylib_inventory: Inventory, storages and items

A grid inventory that replaces "weapons in your hands". Every player has a main grid, a Back slot (backpack, jetpack or riot shield), worn gear slots, and extra grids that come with worn gear or skills. Guns, magazines, power cells, medical kits and gear parts are all items: they have a size, a weight, a stack size and a picture made from their 3D model. You pick what is on your 4-slot hotbar (6 with a backpack). Players can drop items, give them to each other, hold magazines in their hand to pass them over, and open storages next to their own inventory (lockers, crates, armouries). For a server owner it saves every inventory to the database, caps the items lying on the ground, and gives other addons one place to hand out and check gear.

## Requirements

- **Required:** `rhylib_core`.
- **Gamemode:** DarkRP (the suite's gamemode; `canDropWeapon` is a DarkRP hook).
- **Recommended:** `rhylib_weapons` (magazines, cells, guns as items), `rhylib_armoury` (armouries, lockers, crates: the storage entities), `rhylib_gear` (worn gear slots and bodygroup parts), `rhylib_menus` (picture editor widgets, interaction wheel "Give an item"), `rhylib_hud` (hotbar on the HUD, holding items), `rhylib_skills` (carry skills, cell rack, ammo belt, weight changes).
- Needed by: armoury, gear, eod (required); jetpack, mp, skills (recommended).
- No Workshop content of its own. Placeholder models are HL2 ones (backpack = suitcase, dropped item fallback = cardboard box).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_inventory.lua` | shared | Loads the module (needs rhylib_core). |
| `lua/rhylib/inventory/sh_00_items.lua` | shared | `Rhylib.Items`: item registry, weapons as items, container ids, placement rules, weight, network encoding of one item. |
| `lua/rhylib/inventory/sv_10_inventory.lua` | server | Player inventories: add, remove, move, drop, hotbar, split, combine munitions, saving, weapon pickups, weapon state in items. |
| `lua/rhylib/inventory/sv_20_cleanup.lua` | server | `rhylib_cleanhotbar`: strips weapons you hold that aren't inventory items. |
| `lua/rhylib/inventory/sv_25_icons.lua` | server | Saved item picture settings, picture redraw command, precaches item models. |
| `lua/rhylib/inventory/sv_30_storage.lua` | server | Storages (grid and depot), opening, taking, depositing, quick take, bulk buttons. |
| `lua/rhylib/inventory/sv_40_give.lua` | server | Giving items to other players; holding a hotbar item in your hand. |
| `lua/rhylib/inventory/cl_10_inventory.lua` | client | Client copy of your inventory and the open storage; every `Inv.Request*` function. |
| `lua/rhylib/inventory/cl_15_icons.lua` | client | Item pictures rendered from 3D models into texture pages; picture editor; category colours. |
| `lua/rhylib/inventory/cl_20_panel.lua` | client | The inventory window (G). |
| `lua/entities/rhylib_world_item.lua` | shared | An item lying on the ground; E picks it up. |
| `lua/entities/rhylib_item_backpack.lua` | shared | Spawn menu entry: a backpack on the ground. |
| `lua/weapons/rhylib_stowed.lua` | shared | The empty "Stowed" weapon held when no gun is out. |
| `lua/weapons/rhylib_hand.lua` | shared | Holding a hotbar item (magazine, cell): LMB gives one, RMB drops one. |

## For server owners

### Settings

Config module `"inventory"`:

| Key | Default | What it does |
|---|---|---|
| `baseCarry` | `18` | Carry cap in kg without a backpack. |
| `backpackWeightMult` | `0.8` | Items inside a backpack count at this fraction of their weight. |
| `giveRange` | `130` | How close you must be to give someone an item (units). Also the hand weapon's reach. |
| `contraband` | `{}` | Contraband item ids: players can hide up to 3 of them from searches, and they're never returned from jail. |
| `width` | `6` | Personal inventory width in cells. |
| `height` | `3` | Personal inventory height in cells. |
| `beltCells` | `2` | Power cells the belt cell pouch holds (0-2, 0 = none). |
| `saveInterval` | `2` | Seconds between saves of changed inventories. |
| `worldItemLife` | `600` | Seconds before a dropped item on the ground is removed (0 = never). |
| `issuedDropLife` | `300` | Seconds before dropped issued (armoury) gear is removed. |
| `worldItemMax` | `300` | Most dropped items on the ground at once; the oldest goes first. |
| `worldItemPerPlayer` | `15` | Most dropped items one player can have on the ground; their oldest goes first. |
| `autoHotbar` | `true` | New weapons go into the first free hotbar slot. |
| `combineTime` | `1.5` | Combining munitions: seconds per partly used magazine or cell (total at least 3 s, at most combineMax). |
| `combineMax` | `30` | Combining munitions: longest it takes (seconds). |

The models of non-weapon items (`def.model`, `def.iconModel`) also show on the Server settings Models page (group "Items: <category>"), handled by rhylib_core.

How to change them: in game on Staff > Server settings (superadmin), or in a host config file `lua/rhylib_config/*.lua` in your own addon (see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("inventory", "baseCarry", 22)
Rhylib.Config.Set("inventory", "contraband", { "rhylib_spice", "rhylib_deathstick" })
Rhylib.Config.Set("inventory", "worldItemLife", 300)
```

When a change takes effect:
- `width`, `height`, `beltCells`: for players who join after the change (their grids are made on join).
- `saveInterval`: after a map change (the save timer is made at load).
- The rest: straight away.

### Commands and permissions

| Command | Realm | Who | What it does |
|---|---|---|---|
| `rhylib_inventory` | client | anyone | Open or close the inventory window. |
| `rhylib_cleanhotbar` | server | anyone (own weapons) | Strip every weapon you hold that isn't in your inventory. |
| `rhylib_cleanhotbar auto` | server | anyone | Toggle doing that on every spawn (until you leave). |
| `rhylib_icons_redraw` (old name `rhylib_inventory_icons`) | client | anyone | Make your item pictures again. |
| `rhylib_inventory_icon_edit <item id>` | client | anyone opens it, saving needs the permission | The item picture editor. |
| `rhylib_icons_redraw_all [name]` | server | server console or `rhylib.inventory.icons` | Make the pictures again for everyone, or for the first player whose name contains `name`. |

Permission: `rhylib.inventory.icons` (default **admin**): save item pictures for everyone (inventory right-click "Adjust picture") and run `rhylib_icons_redraw_all`.

### Placing things / saving

- This addon has no fixtures to place. Storages are made by other addons (rhylib_armoury lockers, crates, armouries; rhylib_mp property lockers; rhylib_training deposit) and saved by them.
- `rhylib_item_backpack` is in the spawn menu (Entities > "Rhylib: Items & ammo").
- Inventories are saved automatically (see Saved data). Dropped items are never saved.

## For players (short)

| Key | What it does |
|---|---|
| **G** (`rhylib_inventory_key`) | Open / close the inventory. You can keep walking with it open. |
| Drag | Move an item. Drop onto a matching stack to merge. |
| **R** while dragging | Turn the item. |
| **Ctrl** + drag | Take just one off a stack. |
| Let go off the grids | Drop it on the ground ("DROP" shows). Onto an armoury / cabinet: hand it in ("HAND IN"). |
| Right-click item | Split, Equip / Unequip (hotbar), Wear / Take off, Give to the player you look at, Hide (contraband), Drop. |
| Right-click storage item | Quick take (Ctrl: just one). Several clicks queue up. |
| Drag onto the hotbar | Put it in that slot; drag it off or right-click the slot to empty it. |
| **E** on an item on the ground | Pick it up. |
| Hotbar magazine / cell selected | Held in your hand: **LMB** gives one to the player in front of you, **RMB** drops one. |
| Combine munitions (under the Back slot) | Pours partly used magazines / cells of the same kind together. |
| Interaction wheel "Give an item" (hold E on a player) | Opens your inventory to give them something. |

Client convar `rhylib_inventory_cellsize` (default 100, 48-128) sets the cell size at 1080p; the window shrinks itself if it would not fit the screen.

## For developers

The two global tables are `Rhylib.Items` (shared: item types and rules) and `Rhylib.Inventory` (server: the inventories; client: your own copy and requests).

### Container ids

| Id | Name (`Rhylib.Items.X`) | What it is | Exists when |
|---|---|---|---|
| 1 | `MAIN` | Main grid (config width x height) | Always |
| 2 | `BACK` | Backpack grid (size from the worn item's `grid`) | A backpack is worn |
| 3 | `SLOT_BACK` | Back slot, one item with `slot = "back"` | Always |
| 4 | `EXT` | The open storage (its items have their own uids) | A storage is open |
| 5 | `RACK` | Cell rack, power cells only | rhylib_skills (Load bearer) |
| 6 | `BELT` | Ammo belt, no worn items or guns 5+ cells long | rhylib_skills (Ammo belt) |
| 7 | `HOLSTER` | Holster grid (2x2), items with `holster` only | A holster is worn |
| 8 | (worn) | Kama | An item with that slot is registered (rhylib_gear) |
| 9 | (worn) | Pauldron | same |
| 10 | (worn) | Binoculars | same |
| 11 | (worn) | Rangefinder | same |
| 12 | (worn) | Helmet light | same |
| 13 | (worn) | Holster (the worn item) | same |
| 14 | (worn) | Sun visor | same |
| 15 | (worn) | Forearm | same |
| 16 | (worn) | Shoulder antenna (`comms`) | same |
| 17 | (worn) | Belt pouches (the worn item) | same |
| 18 | `POUCH` | Belt pouches' grid, ammo-belt rules | Belt pouches worn |
| 19 | `CELLPACK` | ARC backpack's side pouch, cells only | ARC backpack worn |
| 20 | `CELLBELT` | Belt cell pouch, cells only | config `beltCells` > 0 |

Worn slots (3, 8-17) are in `Items.WORN[cid] = { slot, title }`; `Items.WORN_BY_SLOT[slot]` goes the other way. Ids are sent in 5 bits (`Items.CONT_BITS`), so 0 and 21-31 are free. New items go to the first free spot in this order: their worn slot (if they have `slot`), then 20, 5, 19, 7, 1, 2, 6, 18.

### Item definition fields

| Field | Meaning |
|---|---|
| `name` | Shown name (default: the id). |
| `w`, `h` | Size in cells (default 1, 1). |
| `stack` | Most per stack (default 1). |
| `category` | `weapon`, `ammo`, `medical`, `gear`, `misc` (default), `training`: sets the colours. |
| `group` | Depot shelf group: `rifle`, `carbine`, `pistol`, `heavy`, `shotgun`, `sniper`, `weapon`, `grenade`, `training`, `ammo`, `medical`, `back`, `body`, `helmet`, `gear`, `misc`. Default: `back` for back-slot items, else the category. |
| `weight` | kg per item. |
| `model` | World model when dropped (also the picture, unless better is found). |
| `iconModel` | Model used only for the inventory picture. |
| `fill` | `true`: has a 0-1 fill level in `data.fill` (magazines, cells). Only full ones stack. |
| `rounds`, `unit` | Shown as "n / rounds unit" from the fill. |
| `large` | Not allowed in backpacks. |
| `slot` | Worn in that slot: `back`, `kama`, `pauldron`, `binos`, `rangefinder`, `light`, `holster`, `visor`, `forearm`, `comms`, `belt`. |
| `slotOnly` | Only fits its worn slot (or a storage). |
| `grid`, `gridCid`, `gridName` | A worn item that adds a `{ w, h }` grid in container `gridCid` (default 2, the backpack). |
| `extraGrids` | `{ { cid, w, h, name } }`: more grids a worn item adds. |
| `carry` | Worn: raises the carry cap by this many kg. |
| `weightMults` | Worn: `{ [itemId] = mult }` makes those items lighter. |
| `holster` | Fits the holster grid. |
| `hand` | Can be held from the hotbar with `rhylib_hand`. |
| `desc` | Extra tooltip line. |
| `note` | Carries a short text in `data.note` (sent with the item; long texts are cut to 100 characters). |
| `stackMax` | Highest stack a skill may give through `Rhylib.ItemStack`. |
| `carrySkill` | rhylib_skills skill id needed to carry it. |

Per-item `data` keys the inventory itself uses: `fill`, `issued` (from a depot; despawns sooner when dropped), `loadout` (job gear: vanishes when dropped, can't be given or stored), `hidden` (SteamID64 of the hider), `note`. Weapons keep their own state in `data` too (`clip`, `mag`, `cell`, `mode`...).

### Public functions

Shared (`Rhylib.Items`):

| Function | Returns | What it does |
|---|---|---|
| `Register(id, def)` | nothing | Adds an item type. Call on both realms at load. |
| `Get(id)` | def or nil | The item's definition. |
| `EnsureReady()` | nothing | Registers weapon items and assigns net ids if needed. |
| `RegisterWeapons()` | nothing | Turns every SWEP with `InvW` into an item. |
| `Unique(def)` | bool | A one-only weapon item (a gun, stack 1). |
| `GroupOf(def)` / `GroupRank(g)` | string / number | Depot shelf group and its sort order. |
| `StackFor(def, ply)` | number | Stack size for this player (hook `Rhylib.ItemStack`). |
| `Weight(state)` | weight, cap | kg carried and cap for a state (`Rhylib.Inventory` on the client). |
| `PlayerWeight(ply)` | weight, cap | From NW2 `rhylib_weight` / `rhylib_carry`. |
| `IsContraband(id)` | bool | In config `contraband`. |
| `CanPlace(state, id, cid, x, y, rot, ignoreUid)` | bool | Would it fit there (container rules + free cells)? |
| `ContainerAllows(cid, def)` | bool | Does this container take this kind of item at all? |
| `Fits(w, h, items, id, x, y, rot, ignoreUid)` / `FindSpot(c, id)` / `At(items, x, y)` | | Grid helpers. |
| `CanWear(ply, def)` | ok, reason | Hook `Rhylib.CanWear`. |
| `CanLeave(state, inst)` | ok, reason | A worn grid item can only come off while its grid is empty. |
| `HotbarSize(state)` | 4 or 6 | |
| `WriteInstance(inst)` / `ReadInstance()` | | One item on the wire. |

Server (`Rhylib.Inventory`):

| Function | Returns | What it does |
|---|---|---|
| `Get(ply)` | state | The player's inventory state (made and loaded on first use). |
| `AddItem(ply, id, count, data)` | count left over | Adds items, stacking first; gives weapons. |
| `AddOrDrop(ply, id, count, data)` | nothing | Same, the rest lands on the ground. |
| `CanAdd(ply, id)` | bool | Would one fit now? |
| `Count(ply, id)` / `Has(ply, id)` | number / bool | |
| `Remove(ply, uid, amount)` | inst or nil | Removes some or all of one item. |
| `TakeBest(ply, id)` | fill, issued | Takes the fullest one (reloads). |
| `Drop(ply, uid, single)` | nothing | Drop on the ground. |
| `Move(ply, uid, cid, x, y, rot, single)` | nothing | Move / merge inside the inventory (EXT = deposit). |
| `SetHotbar(ply, uid, n)` | nothing | Hotbar slot (uid 0 empties slot n). |
| `Limit / AtLimit / LimitText(ply, id)` | | Carry limit of one-only items (hook `Rhylib.CarryLimit`). |
| `MayHold(ply, id)` / `HoldReason(id)` | bool / text | Carry skill check. |
| `Locked(ply)` | bool | Hook `Rhylib.InventoryLocked`. |
| `Note(ply, text)` | nothing | A message in the inventory window. |
| `SetGrid(ply, cid, w, h)` | nothing | Add / resize / remove a skill grid. |
| `TakeOff(ply, uid)` | bool | Take a worn item off (into a grid or onto the ground). |
| `Stow(ply)` | nothing | Hold the empty Stowed weapon. |
| `SpawnWorldItem(ply, id, count, data)` | entity | Put an item on the ground in front of ply. |
| `CaptureWeapons(ply)` / `GiveAllWeapons(ply)` | nothing | Weapon state into items / weapons from items. |
| `Save(ply)` / `SendFull(ply)` / `MarkChanged(ply)` | nothing | |
| `GiveTo(ply, target, uid, single)` / `CanGive(ply, target)` | count / bool | Give to another player. |
| `CleanHotbar(ply)` | count | Strip non-inventory weapons. |
| `CreateStorage(ent, opts)` / `NewStorage(ent, opts)` | storage | Make a storage (see sv_30_storage.lua header for opts). |
| `OpenStorage(ply, ent)` / `CloseStorage(ply, quiet)` / `RefreshStorage(ent)` / `RemoveStorage(ent)` / `GetStorage(ent)` | | |
| `StorageAdd(storage, id, count, data, x, y, rot)` | count left | Fill a grid storage. |
| `StorageSerialize(storage)` / `StorageLoad(storage, rows)` | rows / nothing | Save and load a storage's contents. |
| `Internal.update(ply, st, inst)` | nothing | Send an item after changing its count or data in place. |

Client (`Rhylib.Inventory`): `cont`, `byUid`, `ext` (your copy), `Toggle()`, `HotbarItem(n)`, `GiveTarget()`, `ShowNote(text)`, and the requests `RequestMove`, `RequestDrop`, `RequestGive`, `RequestHold`, `RequestHotbar`, `RequestSplit`, `RequestCombine`, `RequestHide`, `RequestUse`, `RequestTake`, `RequestQuickTake`, `RequestExtMove`, `RequestBulk`, `CloseExt`, `RequestFull`. Pictures: `Inv.Icons.Draw(def, x, y, w, h, rot, alpha)`, `Inv.Icons.Fit(...)`, `Inv.Icons.Reset()`, `Inv.Icons.OpenEditor(id)`; colours `Inv.CATEGORY_COLORS`.

### Hooks

Fired by this addon:

| Hook | Realm | When | Return value |
|---|---|---|---|
| `Rhylib.InventoryChanged(ply)` | server | Once per tick after any change to ply's items. | ignored |
| `Rhylib.InventoryWeaponPickup(ply, class)` | server | A weapon was picked up into the inventory. | ignored |
| `Rhylib.LoadoutDropped(ply, id)` | server | Job gear was dropped or handed in to a depot. | ignored |
| `Rhylib.ItemGiven(giver, target, id, count)` | server | After a give. | ignored |
| `Rhylib.ItemStack(def, ply)` | shared | Working out a stack size. | a number (clamped to 1..max(stack, stackMax)) |
| `Rhylib.CanWear(ply, def)` | shared | Wearing a non-back slot item. | `false, reason` refuses |
| `Rhylib.CarryLimit(ply, id, def)` | server | How many of a one-only gun. | a number (default 1) |
| `Rhylib.InventoryLocked(ply)` | both | Before drop/use/give/storage (server), opening the window (client). | `true` locks |
| `Rhylib.CanTakeStock(ply, storage, id)` | server | Before taking from a storage. | `false, reason` refuses |
| `Rhylib.ItemTooltip(inst, lines)` | client | Building an item tooltip. | add to `lines`, return nothing |
| `Rhylib.ItemMenu(inst, menu)` | client | Right-click menu on your item. | add options to `menu`, return nothing |
| `Rhylib.StorageControl(action)` | client | Lock / Unclaim pressed on an owned locker (`"lock"` / `"unclaim"`). | ignored |

Listened to: `PlayerCanPickupWeapon` (weapons go into the inventory), `PlayerSpawn` (weapons given back and stowed), `PlayerInitialSpawn` (load), `canDropWeapon` and `PlayerDroppedWeapon` (no plain weapon drops), `DoPlayerDeath` (save weapon state), `PlayerDisconnected` and `ShutDown` (save), `InitPostEntity` (weapon items, precache, pictures), `Rhylib.ModelsChanged` (pictures again), `Rhylib.WheelOptions` ("Give an item").

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `inv.req` | client → server | nothing | Send me everything. |
| `inv.full` | server → owner | containers (count 6, then id 5, w 5, h 5), item count 8, items | Whole inventory. |
| `inv.upd` | server → owner (batched) | op 2: item / removed uid 16 / container id 5, w 5, h 5 | Changes. |
| `inv.note` | server → player | string | Window message. |
| `inv.busy` | server → player | float end time (0 = stopped) | Combining progress. |
| `inv.move` | client → server | uid 16, container 5, x 5, y 5, rot 1, single 1 | Move an item. |
| `inv.hotbar` | client → server | uid 16, slot 3 | Hotbar slot. |
| `inv.split` / `inv.hide` / `inv.use` | client → server | uid 16 | Split / hide / switch to weapon. |
| `inv.combine` | client → server | nothing | Combine munitions. |
| `inv.drop` | client → server | uid 16, single 1 | Drop. |
| `inv.give` | client → server | uid 16, single 1, entity | Give to a player. |
| `inv.hold` | client → server | uid 16 | Hold a hotbar item in your hand. |
| `inv.ext` | server → player | open bool; title, depot, w 5, h 5, canLock, locked, bulk mode 2, count 8, items | Storage opened / closed. |
| `inv.extupd` | server → viewers (batched) | op 1: item / removed uid 16 | Storage changes. |
| `inv.take` | client → server | storage uid 16, container 5, x 5, y 5, rot 1, single 1 | Take from storage. |
| `inv.extmove` | client → server | storage uid 16, x 5, y 5, rot 1, single 1 | Move inside a storage. |
| `inv.quick` | client → server | storage uid 16, single 1 | Quick take. |
| `inv.bulk` | client → server | action 2 | Store all / take all / empty. |
| `inv.close` | client → server | nothing | Window closed. |
| `inv.took` | server → player | nothing | Pickup sound. |
| `inv.icontunesreq` | client → server | nothing | Ask for saved picture settings (once). |
| `inv.icontunes` | server → player / all | full bool, count 12, per item settings | Picture settings. |
| `inv.icontune` | client → server | id, reset, settings | Save a picture (perm checked). |
| `inv.iconsredraw` | server → player / all | nothing | Make pictures again. |

One item on the wire (`Items.WriteInstance`): uid 16, container 5, net id 10, x 5, y 5, rot 1, count 8, issued 1, hotbar 3, hidden 1, then fill 8 (fill items) and note string (note items).

Engine-networked: NW2Float `rhylib_weight` / `rhylib_carry` (set once per tick when the inventory changes), NW2Int `rhylib_handUid` (the held item).

### Saved data

| Module / key | What's stored |
|---|---|
| `"inventory"` / SteamID64 | List of rows `{ id, x, y, rot (0/1), count, data, container id, hotbar slot }`. |
| `"inventory"` / `"icontune"` | `{ [item id] = { p, y, r, z, ox, oy } }` saved picture settings. |

A saved item whose spot no longer fits (smaller grid, removed skill grid) moves to the first free spot on load, else to the ground (job gear is dropped silently).

### Examples

**Registering your own item.** In a shared file of your addon. Inventory may load before or after you, so register now and again when it loads:

```lua
local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) or Items.Get("ration_bar") then return end
    Items.Register("ration_bar", {
        name = "Ration bar",
        w = 1, h = 1,
        stack = 4,
        weight = 0.2,
        category = "misc",
        desc = "Tastes of nothing.",
        model = "models/props_junk/garbage_metalcan001a.mdl",
    })
end
registerItems()
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "myaddon.items", function(id)
    if id == "inventory" then registerItems() end
end)

-- Server: give two, drop what doesn't fit
Rhylib.Inventory.AddOrDrop(ply, "ration_bar", 2)
```

**Making a SWEP an inventory item.** Any SWEP with `InvW` becomes an item at `InitPostEntity`; the item id is the weapon class. While the item is carried the player has the weapon; the weapon's state is kept in the item with `GetInventoryData` / `SetInventoryData`.

```lua
SWEP.PrintName = "Fusion cutter"
SWEP.InvW, SWEP.InvH = 2, 1      -- size in cells (InvW is what makes it an item)
SWEP.InvWeight = 1.2             -- kg
SWEP.InvCategory = "gear"        -- colour (default "weapon")
SWEP.InvGroup = "gear"           -- armoury shelf heading
SWEP.InvCharge = true            -- a 0-1 charge kept in data.fill, shown as %
-- SWEP.InvUses = 5              -- or: uses when full, shown as "3 / 5 uses"
-- SWEP.InvStack = 3             -- or: stacks (medical kits); weapon stripped when the last one goes
-- SWEP.InvLarge = true          -- not allowed in backpacks
-- SWEP.InvSlot = "back"         -- worn on the back slot ...
-- SWEP.InvSlotOnly = true       -- ... and only there
SWEP.InvHolster = false          -- true/false; unset = pistols up to 2x1 fit the holster
SWEP.CarrySkill = "eod_manual"   -- rhylib_skills: only players with this skill may carry it
-- Inventory picture: SWEP.InvIconModel(s), SWEP.InvIconFlip, SWEP.InvIconZoom,
-- or SWEP.PropModel (side on), else the WorldModel.

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Charge")
end

-- The returned table REPLACES the item's data (issued / loadout marks are kept).
function SWEP:GetInventoryData()
    return { fill = self:GetCharge() }
end

function SWEP:SetInventoryData(data)
    self:SetCharge(data and data.fill or 1)
end
```

Use one up from inside the weapon (server): find the item and remove it, e.g. `local Inv = Rhylib.Inventory; for uid, o in pairs(Inv.Get(owner).byUid) do if o.id == self:GetClass() then Inv.Remove(owner, uid, 1) break end end`.

**Reacting to inventory changes** (server):

```lua
Rhylib.Hook.Add("Rhylib.InventoryChanged", "myaddon.radio", function(ply)
    ply:SetNW2Bool("myaddon_hasRadio", Rhylib.Inventory.Has(ply, "my_radio"))
end)
```

**A storage entity** (server part of an ENT):

```lua
function ENT:Initialize()
    self:SetModel("models/props_junk/wood_crate001a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local s = Rhylib.Inventory.CreateStorage(self, { kind = "grid", w = 5, h = 4, title = "Supply crate" })
    Rhylib.Inventory.StorageAdd(s, "mag_medium", 6)
end
function ENT:Use(ply) Rhylib.Inventory.OpenStorage(ply, self) end
function ENT:OnRemove() Rhylib.Inventory.RemoveStorage(self) end
```

An endless armoury-style shelf is `{ kind = "depot", w = 6, title = "Ammo", stock = { "mag_small", "mag_medium", "cell" } }`.

**Allowing a second copy of a gun** (server):

```lua
Rhylib.Hook.Add("Rhylib.CarryLimit", "myaddon.twopistols", function(ply, id, def)
    if id == "rhylib_dc17" and ply:GetNW2Bool("myaddon_gunslinger") then return 2 end
end)
```

## Notes and gotchas

- **Register items the same way on both realms.** Items travel as a number from sorting all ids; a mismatch shows the wrong item on the client.
- **Weapon items are registered at `InitPostEntity`.** A SWEP added later (Lua refresh) only becomes an item after a map change. An item registered by hand with the weapon's class name wins over the automatic one.
- **`GetInventoryData` replaces `inst.data`.** Return everything you need (fill included), or it's lost when the weapon is put away.
- Two copies of one gun (an officer's two DC-17s) share one weapon entity; the lowest uid holds the live state, the other only a spare magazine.
- Picking up a weapon never puts it straight in your hands: it goes into the inventory (and onto the hotbar if `autoHotbar`). Weapons given within 2 ticks of spawning are job loadout (`data.loadout`): they vanish when dropped, can't be given or stored. Stacking kits from a loadout only top up to one stack.
- Weapons that aren't inventory items still work; they show in an overflow hotbar slot. `rhylib_cleanhotbar` removes them.
- Inventory weapons can't be dropped as plain weapons (DarkRP `/drop`, drop on death); drop them from the window.
- Depots take **anything** dragged onto them and delete it (hand in). The storage option `returnable` is still stored but nothing reads it any more.
- Storages close beyond 160 units from their entity (checked twice a second), on death, or when the entity goes.
- The issued-item tooltip always says "5 minutes"; the real time is config `issuedDropLife`.
- Grid sizes are sent in 5 bits: containers up to 31 x 31; message item counts are 8 bits (255 items per message).
- Pictures are rendered on each client into up to four 2048x2048 render targets, one per frame after loading in. If they look wrong after alt-tab or a driver hiccup, `rhylib_icons_redraw`. A model nobody has loaded yet can fail the first time; it's retried 4 times, then the console says why.
- The window lets you keep walking (keyboard isn't captured), so text boxes elsewhere aren't affected; the open key is ignored while typing or in the console.
