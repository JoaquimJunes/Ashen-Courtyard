extends RefCounted
## Facts from one motor integration, including constrained moves without slide flags.
var displacement := Vector3.ZERO
var velocity := Vector3.ZERO
var grounded := false
var normal := Vector3.ZERO
var impact_speed := 0.0
var blocked := false
