# Retro PSX Nature Pack

- Creator: Elegant Crow
- Source: https://elegantcrow.itch.io/retro-psx-nature-pack
- Free download, official upload 5829435; downloaded 2026-09-24 UTC.
- 40 original GLB models extracted with textures and included text documents.
- Complete unmodified archive: `source/nature-assets.zip` (excluded from Godot import).
- Archive SHA-256: `ff390aacfd1ecda2ba7124a95e05080f3ad0ce498a54fa7fbf31bb15f576a1c8`.
- Publisher license statement: [LICENSE_SOURCE.txt](LICENSE_SOURCE.txt).
- Models and textures are unchanged; no gameplay integration.

In Godot, expand this folder in FileSystem and drag a `.glb` into a 3D scene.
Nature seasonal textures may need manual material assignment.

## Upstream export issue

`models/glTF/trees/tree02_winter.glb` contains no nodes or meshes in the original archive. It is preserved unchanged. The original FBX export was also tested and could not be imported by Godot, so it remains only in the source archive. The other 39 GLBs contain geometry. Use another winter tree variant.
