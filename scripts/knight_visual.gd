extends Node3D
## A small node rig: combat owns WeaponPivot; this script only animates idle limbs.
## This leaves attack timings, damage, and collisions entirely in Combatant.
@onready var rig: Node3D = $Rig
@onready var left_leg: Node3D = $Rig/KnightRig/LeftLeg
@onready var right_leg: Node3D = $Rig/KnightRig/RightLeg
@onready var left_arm: Node3D = $Rig/KnightRig/LeftArm
@onready var cape: Node3D = $Rig/KnightRig/Cape
var gait := 0.0
var casting := false

func _process(delta: float) -> void:
 var actor = get_parent()
 if not actor is CharacterBody3D or actor.dead: return
 var speed := Vector2(actor.velocity.x,actor.velocity.z).length()
 gait += delta*(5.0+speed*1.4)
 var amount := minf(speed/4.0,1.0)*0.48
 left_leg.rotation.x = lerpf(left_leg.rotation.x,sin(gait)*amount,minf(delta*15,1))
 right_leg.rotation.x = lerpf(right_leg.rotation.x,-sin(gait)*amount,minf(delta*15,1))
 var arm_angle := 1.25 if casting else -sin(gait)*amount*0.6
 left_arm.rotation.x = lerp_angle(left_arm.rotation.x,arm_angle,minf(delta*14,1))
 # Gentle cloth sway is local to the cape, not the collision body.
 cape.rotation.x = sin(gait*0.5)*0.025+amount*0.12
 cape.rotation.z = sin(gait*0.6)*0.025
