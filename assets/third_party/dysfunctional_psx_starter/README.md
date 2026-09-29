# PSX Starter Kit 0.6

Source: https://dysfunctional-games.itch.io/psx-starter-kit

Downloaded 24 September 2026. Publisher permits commercial game use under the custom terms in LICENSE_SOURCE.txt.

Original archive, publisher-page snapshot and SHA-256 provenance are in `source/`, excluded from Godot imports. Extracted FBX models and PNG/JPG textures retain source-relative paths. Blender source files and preview GIFs remain in the original starter archive. No gameplay integration or model edits.

30 FBX files; some files contain multiple meshes. The source starter README predates version 0.6.

## Model inventory

- `models/Characters/Chibi/BaconLeaf(Legend)/Baconleaf.fbx`
- `models/Characters/Realistic/CustomMaleRealistic/Male_Custom_PS1.fbx`
- `models/Props/Angelic Demon Statue/AngelicDemonStatue.fbx`
- `models/Props/Apple/Apple.fbx`
- `models/Props/BigTree/FBX/PS1_BigTree.fbx`
- `models/Props/Bush/FBX/Bush.fbx`
- `models/Props/CaseFile/FBX/PS1_CaseFile.fbx`
- `models/Props/DoubleBed/DoubleBed.fbx`
- `models/Props/Fence Wood/FenceWood_Collection.fbx`
- `models/Props/GraveyardFence/FBX/GraveyardFenceSet.fbx`
- `models/Props/Polybucks Coffee/PS1_CoffeePlaybucks.fbx`
- `models/Props/Rocks/FBX/RockB_1.fbx`
- `models/Props/StickGrave/FBX/GraveDirt.fbx`
- `models/Props/StickGrave/FBX/StickGrave.fbx`
- `models/Props/StoneWall/StoneWall_Set.fbx`
- `models/Props/WoodChair/WoodChair.fbx`
- `models/Props/Xmas Tree/XmasTree.fbx`
- `models/Tools/Axe/Axe.fbx`
- `models/Tools/Flashlight/Flashlight.fbx`
- `models/Tools/FlashlightChest/FlashlightChest.fbx`
- `models/Tools/FlashlightGun/FlashlightGun.fbx`
- `models/Tools/OldCamera/FBX/PS1_Camera.fbx`
- `models/Tools/Spade/Spade.fbx`
- `models/Weapons/BaseballBat/BaseballBat.fbx`
- `models/Weapons/Claymore/Claymore.fbx`
- `models/Weapons/Deagle/FBX/Deagle.fbx`
- `models/Weapons/Flintlock/Flintlock.fbx`
- `models/Weapons/GladiatorBaton/FBX/PS1_GBaton.fbx`
- `models/Weapons/Glock-17/Glock17.fbx`
- `models/Weapons/Katana/Katana.fbx`

## Godot 4.6.2 verification

- Outer RAR and all 29 nested archives passed libarchive extraction/checksum checks.
- 29 of 30 FBX scenes loaded and instantiated successfully.
- `models/Characters/Chibi/BaconLeaf(Legend)/Baconleaf.fbx` failed import: the
  importer reports no root nodes. The source Blender file remains in the archive.
  That character's folder now contains `.gdignore` so editor scans stop retrying
  this invalid import. Original files are preserved; no gameplay scene uses it.
- Texture-reference warnings (original files preserved without repairs):
  - OldCamera: `N_Camera.png` is absent from the source archive.
  - Deagle: `N_Deagle.png` is supplied in `Texture/`, but the FBX importer searches `FBX/`.
  - GladiatorBaton: `N_TVGladiator.png` is absent from the source archive.
  - Angelic Demon Statue: `D_Brazier.jpg` is absent from the source archive.
  - Bush: `D_Bush.png` is supplied in `Texture/`, but the FBX importer searches `FBX/`.
  - StickGrave: `N_Gravestone.png` is absent from the source archive.
- Successful loading does not mean every material is complete. These source issues
  are recorded for later repair; no replacement textures or model edits were made.
- Import and load logs are retained in `source/`.
