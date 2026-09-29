# ADR 003 — engine, hardware and review gates

**Accepted: 20 September 2026.**

Keep Godot 4.6.2 standard, typed GDScript and Compatibility on the reference
Iris Xe / i5-1135G7 / 8 GB laptop. Use original/permitted assets and PS1 presentation.
Target 60 FPS with adjustable internal 3D resolution and readable UI.

First preserve and refactor the existing playable character. Stop for a review
before new mechanics. Implement each movement mechanic separately, with defined
controls, animation references, transition rules and acceptance tests. Then prove
small structural collapse and a 256 × 256 m seamless procedural world before
choosing production density or map size.

Automated collision/lifecycle tests and native rendering are complementary to
hands-on feel review. A software-rendered capture or an editor frame rate does not
establish release performance. A release benchmark on the actual GPU is a separate
required gate before scale increases.
