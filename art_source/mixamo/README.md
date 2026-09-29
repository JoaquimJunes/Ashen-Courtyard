# Approved Crawling retarget

Original: `assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx`, downloaded by the user from
Mixamo. SHA-256: `c9d06ce44b709040ade754ed61910516316cc42ff3cef262097cf6a7d8d4699a`.
The source file and its animation keys have not been changed.

`crawling_ual.glb` preserves the UAL mannequin retarget reviewed in this task's
`player-crawling-preview.html` visualization on 26 September 2026. Its embedded
GLB was copied byte-for-byte; it is kept here so runtime extraction is independent
of the visualization attachment and temporary authoring files.

The preview retarget mapped Mixamo's skeleton onto the existing 65-bone UAL1
mannequin, compensated rest-axis differences, centered horizontal hip travel,
fitted hand/knee contacts and applied a constant ground offset. It was baked at
30 Hz (55 samples including endpoints, 1.8 seconds), with the existing 0.96 model
scale. This is a retargeted asset, not a native UAL animation or an unchanged copy
of the Mixamo skeleton. The mannequin mesh and source skeleton remain unchanged.

`tools/build_mixamo_crawl.py` extracts all three local transform channels per
bone into the runtime AnimationLibrary. `tools/crawl_retarget.py` applies the
`attached_shoulders_v1` correction to nine rotation tracks: spine_01 and both
clavicle/upper-arm/forearm/hand chains. The preview's collarbone motion displaced
the rigid mannequin's shoulder sockets by up to 20 cm. The correction retains
the rest sockets against the chest, pitches the torso forward by 23 degrees,
and solves each arm to preserve the original wrist position and palm rotation.
It adds no runtime IK. All joint translations, scales, remaining rotation keys,
sample times, original FBX and approved GLB remain unchanged. Interpolated wrist
deviation stays below 1.5 mm in the authoring frame.

The runtime asset includes source hashes and the correction identifier. Looping
is enabled for locomotion. Recreating the underlying FBX-to-UAL mapping remains
a separate authoring step; this builder fits the existing retarget snapshot.
The authoring GLB is excluded from Godot imports and releases.
