# Item system

The item foundation is implemented for the existing sword, Azure Bolt, Violet
Burst and healing flask. The character owns an inventory and gameplay loadout;
shared Resources describe content. Categories organize the inventory; action
profiles determine behavior.

## Try it

Run the project with F5. Open **Esc → Test Grounds → Enter Character Test Grounds**,
then **Esc → Test Grounds → Item testing**. Grant a Practice Blade, equip it in
Main hand and set its upgrade to +1. Grant a second copy to compare their levels.

Use **Movement practice → Stationary target** to enable combat, then reopen Item
testing to configure items (starting a practice attempt resets the character).
Resume to use the current bindings: light/heavy attacks, 1/2 to select spells,
E to cast and R to use the selected gadget. Saved keybindings remain in effect.
A pending or active action disables item editing; resume and let it finish first.

The panel also offers a stackable healing potion, a reusable healing charm, a bow
position marker and a wooden shield. These are testing fixtures. The bow occupies
two hands and stows the shield; changing back to a sword restores the shield.
Bow attacks, blocking and bashing are not implemented. The charm deliberately
uses the existing healing behavior without consuming quantity, to test reusable
tools; it is not balanced adventure content. All changes reset on station reset
or encounter retry. No inventory data is written to disk.

## Owners and authoring resources

| Type | Responsibility |
| --- | --- |
| `ItemDefinition` | Stable ID, text/icon, category/subtype, supply policy and optional profiles |
| `ItemActionProfile` | Reusable moveset: input roles mapped to action bindings |
| `ItemActionBinding` | Existing executor, `AbilityDefinition`, presentation profile and item cost |
| `ItemEquipmentProfile` | Primary/off-hand assignment, two-handed requirement and idle role |
| `ItemPresentationProfile` | Animation role, optional animation profile, hand release and cast color |
| `ItemUpgradeProfile` | Authored damage/healing multipliers for each supported upgrade level |
| `ItemInstance` | Owned ID, definition ID, quantity, charges and upgrade level |
| `ItemCatalog` | Validate definitions and resolve IDs using a dictionary index |
| `Inventory` | Grant, merge, remove, upgrade, refill and serialize owned instances |
| `EquipmentController` | Assignments, quick-slot selections and hand availability |
| `ItemActionResolver` | Prepare equipped animation banks, capture resolved action values and pay combined costs |
| `AnimationBank` / `AnimationBinding` | Per-character qualified clip names and shared immutable source references |
| `CharacterItems` | Wire the components, starter reset and whole-record restoration |

Categories are `magic`, `gadget`, `melee`, `bow`, and `shield`. The UI labels melee
as Swords. Sword, axe, hammer, spear, greatsword and scythe are subtypes, independent
of the moveset and hand requirement. A subtype does not silently select animations.

Supply policies are reusable, stack, and charges. Reusable items and charged items
have individual owned copies. Ordinary stack grants merge with base-level stacks
of the same definition up to `max_stack`; upgraded stacks remain separate. An
exhausted stack disappears and clears its slot; an empty refillable remains equipped.

Only Inventory mutates instances in production. Shared definitions are read-only
by convention. The runtime uses dictionary lookups and bounded loadout checks;
it does not scan the inventory on each physics frame. Only equipped hand items
instantiate visual scenes. The panel enumerates inventory only when opened or
when inventory changes while it is visible.

## Add an item using an existing mechanic

1. Create an `ItemDefinition` Resource in `features/items/data/`. Give it a unique,
   stable ID; renaming the file or display name must not change that ID.
2. Assign a category, optional subtype and supply limits. For hand equipment,
   reference an equipment profile and compatible existing visual definition.
3. Reference a shared action profile, or create one with new `AbilityDefinition`
   resources for different timing, damage, mana/stamina costs or healing.
4. Use roles `light`/`heavy` for primary equipment and `use` for spells/gadgets.
   Choose the existing light, heavy, cast or heal executor. Cast delivery currently
   supports projectile and burst. Configure `item_cost` for stacks or charges;
   reusable actions use zero. New item abilities should use zero `flask_cost`.
5. Choose the matching presentation role (`melee_light`, `melee_heavy`, `spell`,
   or `heal`) and whether the action releases hands. A null animation profile
   uses the character's installed profile. To add different clips, create an action
   animation profile as described below; equipment setup validates and installs it
   before an action can spend resources.
6. Add the definition to `catalog.tres`. Catalog validation runs at character setup.
   The Test Grounds grant selector reads the catalog directly; no new menu or
   player-controller branch is required.

### Add a moveset with different animation clips

Create an `AnimationProfile` with scope `ACTIONS`, rig identifier `ual1_65_v1`
and the reference contract `assets/models/ual/rig_contract.tres`. Reference the
needed shared `AnimationLibrary` resources and map local aliases to their source
roles. Aliases use an identifier or `library/identifier`; each role must resolve
to exactly one library. Declare light-attack entries in their intended sequence,
with finite strike landmarks and blend durations, a heavy definition if needed,
or the four spell stages. Attach this profile to the matching
`ItemPresentationProfile.animations`. An action-only profile cannot replace the
character's locomotion profile.

Catalog validation checks authored data. Equipping additionally checks the actual
character's rig hierarchy, rest transforms, semantic roles and pose-track targets.
A failed change leaves the old equipment and animation libraries available and
reports the compatibility error. Callback/property tracks are not permitted in
pose libraries: gameplay remains responsible for costs, damage and spell release.

Each character prepares a private namespace for the equipped profile. Two items
can use the same alias for different clips without overwriting each other or the
base character bank. Accepted actions capture the resolved binding; execution
never loads or installs assets. Unequipped banks are released after their active
action finishes, and scene exit disconnects the bank observers.

Light sequences use the number of authored entries and restart on a moveset
change. The default remains A → B → A. Queue depth remains one follow-up, every
attack requires a fresh press, and cost is charged when that attack starts.
Changing quick-slot selection cannot rewrite an accepted spell sequence.

`tests/run_animation_banks.gd` checks alias collisions, a three-entry sequence,
custom spell phases, independent characters, rejected profiles, cleanup and retry.

Practice Blade demonstrates a second item sharing the sword moveset and mesh.
The tests also give a spell an entirely new item ID and ability ID, then verify
its animation, hand release, payment and projectile payload through the real player.

Godot resource duplication can retain external nested references. When creating
an editable variant in code, explicitly duplicate every nested resource you will
modify. Prefer authored `.tres` assets. Runtime accepted abilities and their
presentation values are copied, so upgrades or later selection cannot alter them.

The sample upgrade profile supports +1 damage ×1.1 and +2 ×1.2, each relative to
base stats. The panel exposes these authored levels; it does not implement an
upgrade currency, blacksmith or progression system.

## Action and presentation integration

The existing action queue is still authoritative. Requesting an action does not
spend anything. The physics tick first pays ongoing exertion, revalidates the
request, captures the selected item and commits the full cost. Failed validation
spends nothing. Inventory costs and stamina/mana are deducted synchronously
without notifications between them; inventory observers run after the lifecycle
has installed/resolved the accepted action. Interruptions do not refund costs.

`active_item` contains the instance ID, definition ID, upgrade level, executor,
effective ability and presentation snapshot. Execution never rereads quick-slot
selection. Consuming a final potion therefore cannot lose its already accepted
healing effect. The ordinary action lifecycle clears active item ownership on
completion, cancellation, reset, death and unload.

The shared lifecycle provides `can_pay`, `capture_definition`, `pay_cost` and
`notify_cost_changed` extension points. The Warden keeps its existing default
resource payment; player item actions override those hooks. Legacy tuning and
flask access remain adapters. Player flask access delegates to the original
owned flask instance; using a potion does not spend a flask as well.

Gameplay assignments are separate from visual sockets. The equipment bridge
observes loadout and action signals and updates existing visual controllers.
It validates held and stowed layouts before accepting assignments. Casting and
traversal can overlap hand-release reasons; releasing one reason cannot override
another. Death freezes visuals before cancellation observers restore anything.
The UAL appearance-review scene deliberately retains its independent artist
layouts; normal player models opt into gameplay equipment.

A genuinely new mechanic needs a reusable executor plus its data/presentation
contract and tests. Keep its action timing, interruption and payment inside the
shared lifecycle, and route physical movement through the motor. Item IDs and
categories must not become execution branches. New content can then reuse that
executor without adding item-specific code.

## Persistence boundary and API

Each player exposes `items.inventory`, `items.equipment` and `items.resolver`.
For example, while idle:

```gdscript
var copies = player.items.inventory.grant(&"practice_blade", 2)
player.items.equipment.assign(&"primary", copies[0])
player.items.inventory.set_upgrade(copies[0], 1)
player.items.equipment.select(&"spell", 1)
```

`ItemLoadoutDefinition` configures starter definition IDs and quick-slot counts.
The default starter has one primary weapon, an empty off hand, two spells and one
flask. Reset expands it into fresh owned copies and publishes the complete result.

`player.items.to_record()` returns version 1 with item records, equipment
assignments, selections and the legacy flask reference. `restore(record)` stages
and validates both inventory and loadout before replacing either. Unknown IDs,
missing references, invalid counts, unsupported upgrades and unsupported versions
reject the entire restore with `last_error`; the previous state stays intact.
This is a serialization contract, not a disk-save or checkpoint system.

## Validation

From the project directory:

```sh
python3 tools/run_tests.py --suite run_items --suite run_item_actions --suite run_item_panel
python3 tools/run_tests.py --timeout 120
```

The suites cover definition validation, independent copies, stack/charge policies,
atomic payment, snapshot isolation, slot compatibility, two-handed stowing,
interruption/death/reset/unload, JSON record round trips and invalid restore
atomicity. Production action integration runs at 30/60/120 Hz. GUI tests dispatch
actual mouse and keyboard events. Scale coverage loads 1,000 definitions and
5,000 instances without creating scene nodes for inventory entries.

Deferred work: functional bow/shield/hook mechanics, additional melee movesets,
full inventory UI, pickups/loot, crafting, upgrade economy, durability, random
rolls, disk saves and checkpoint integration. No dual wielding is implemented.
