"""Baked shoulder fitting for the rigid UAL mannequin; no runtime IK required.

The approved preview allowed Mixamo clavicle protraction to move the shoulder
sockets outside the mannequin's rigid chest. Keep its rest sockets, pitch the
spine forward enough for both arms to reach, then preserve the authored wrists
with a two-bone solve. Source transforms and the skeleton remain untouched.
"""
from bisect import bisect_right
from math import acos, cos, radians, sin, sqrt

TORSO_LEAN_DEGREES = 23.0
CORRECTED_BONES = ('spine_01', 'clavicle_l', 'upperarm_l', 'lowerarm_l', 'hand_l',
                   'clavicle_r', 'upperarm_r', 'lowerarm_r', 'hand_r')


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, s): return tuple(x * s for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def length(a): return sqrt(dot(a, a))
def unit(a): return mul(a, 1 / length(a))
def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def qmul(a, b):
    v = add(add(mul(b[:3], a[3]), mul(a[:3], b[3])), cross(a[:3], b[:3]))
    return (*v, a[3]*b[3]-dot(a[:3], b[:3]))


def inverse(q): return (-q[0], -q[1], -q[2], q[3])


def rotate(q, v): return qmul(qmul(q, (*v, 0)), inverse(q))[:3]


def between(a, b):
    a, b = unit(a), unit(b)
    cosine = max(-1.0, min(1.0, dot(a, b)))
    if cosine < -0.999999:
        axis = unit(cross(a, (1, 0, 0) if abs(a[0]) < 0.8 else (0, 1, 0)))
        return (*axis, 0)
    return unit((*cross(a, b), 1 + cosine))


def slerp(a, b, weight):
    a, b = unit(a), unit(b)
    cosine = dot(a, b)
    if cosine < 0:
        b, cosine = mul(b, -1), -cosine
    if cosine > 0.9995:
        return unit(add(mul(a, 1-weight), mul(b, weight)))
    angle = acos(max(-1.0, min(1.0, cosine)))
    return add(mul(a, sin((1-weight)*angle)/sin(angle)), mul(b, sin(weight*angle)/sin(angle)))


def sample(channel, time, rotation=False):
    times, values, interpolation = channel
    index = max(0, min(len(times)-1, bisect_right(times, time)-1))
    if index == len(times)-1 or interpolation == 'STEP': return values[index]
    weight = (time-times[index])/(times[index+1]-times[index])
    if rotation: return slerp(values[index], values[index+1], weight)
    return add(mul(values[index], 1-weight), mul(values[index+1], weight))


def pose_at(nodes, channels, time):
    result = {}
    for index, node in enumerate(nodes):
        position = node.get('translation', (0, 0, 0))
        rotation = node.get('rotation', (0, 0, 0, 1))
        if (index, 'translation') in channels:
            position = sample(channels[index, 'translation'], time)
        if (index, 'rotation') in channels:
            rotation = sample(channels[index, 'rotation'], time, True)
        result[index] = (tuple(position), unit(rotation))
    return result


def world_pose(pose, parents, bone):
    position, rotation = pose[bone]
    if bone in parents:
        p, q = world_pose(pose, parents, parents[bone])
        position, rotation = add(p, rotate(q, position)), qmul(q, rotation)
    return position, unit(rotation)


def set_world_rotation(pose, parents, bone, rotation):
    parent = world_pose(pose, parents, parents[bone])[1] if bone in parents else (0, 0, 0, 1)
    pose[bone] = (pose[bone][0], unit(qmul(inverse(parent), rotation)))


def fit_pose(nodes, parents, ids, original):
    pose = original.copy()
    targets = {side: world_pose(original, parents, ids['hand_'+side]) for side in ('l', 'r')}
    elbows = {side: world_pose(original, parents, ids['lowerarm_'+side])[0] for side in ('l', 'r')}
    spine = ids['spine_01']
    angle = radians(TORSO_LEAN_DEGREES)/2
    # Snapshot is in the mannequin's +Z-facing, Y-up authoring frame. Uniform
    # armature scale is irrelevant to this rigid transform/reach solve.
    pitch = (sin(angle), 0, 0, cos(angle))
    set_world_rotation(pose, parents, spine, qmul(pitch, world_pose(pose, parents, spine)[1]))
    for side in ('l', 'r'):
        clavicle, upper, lower, hand = (ids[name+'_'+side] for name in ('clavicle', 'upperarm', 'lowerarm', 'hand'))
        pose[clavicle] = (pose[clavicle][0], unit(nodes[clavicle]['rotation']))
        shoulder = world_pose(pose, parents, upper)[0]
        target, hand_rotation = targets[side]
        reach = sub(target, shoulder)
        distance = length(reach)
        a, b = length(pose[lower][0]), length(pose[hand][0])
        if not abs(a-b)+1e-6 < distance < a+b-1e-6:
            raise ValueError(f'{side} wrist unreachable without stretching the arm: {distance} / {a+b}')
        axis = unit(reach)
        bend = sub(elbows[side], shoulder)
        pole = unit(sub(bend, mul(axis, dot(bend, axis))))
        along = (a*a-b*b+distance*distance)/(2*distance)
        elbow = add(shoulder, add(mul(axis, along), mul(pole, sqrt(max(0, a*a-along*along)))))
        current_elbow = world_pose(pose, parents, lower)[0]
        upper_rotation = world_pose(pose, parents, upper)[1]
        set_world_rotation(pose, parents, upper, qmul(between(sub(current_elbow, shoulder), sub(elbow, shoulder)), upper_rotation))
        current_hand = world_pose(pose, parents, hand)[0]
        current_elbow, lower_rotation = world_pose(pose, parents, lower)
        set_world_rotation(pose, parents, lower, qmul(between(sub(current_hand, current_elbow), sub(target, current_elbow)), lower_rotation))
        set_world_rotation(pose, parents, hand, hand_rotation)
    return pose


def corrected_rotations(document, channels):
    nodes = document['nodes']
    ids = {node.get('name'): i for i, node in enumerate(nodes)}
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    times = channels[ids['spine_01'], 'rotation'][0]
    result = {ids[name]: [] for name in CORRECTED_BONES}
    for time in times:
        pose = fit_pose(nodes, parents, ids, pose_at(nodes, channels, time))
        for bone, values in result.items():
            rotation = pose[bone][1]
            if values and dot(values[-1], rotation) < 0: rotation = mul(rotation, -1)
            values.append(rotation)
    return times, result
