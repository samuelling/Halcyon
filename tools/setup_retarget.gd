extends SceneTree
# writes retarget settings into the .import files of character and animation scenes (run after a first import, then re-import)
const UAL := {"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03", "Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l", "LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l", "LeftIndexIntermediate": "index_02_l", "LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l", "LeftMiddleIntermediate": "middle_02_l", "LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l", "LeftRingIntermediate": "ring_02_l", "LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l", "LeftLittleIntermediate": "pinky_02_l", "LeftLittleDistal": "pinky_03_l",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l"}
const RB := {"Hips": "Bip01 Pelvis", "Spine": "Bip01 Spine", "Chest": "Bip01 Spine1", "UpperChest": "Bip01 Spine2", "Neck": "Bip01 Neck", "Head": "Bip01 Head",
	"LeftEye": "Bip01 LEye", "RightEye": "Bip01 REye", "Jaw": "Bip01 MJaw",
	"LeftShoulder": "Bip01 L Clavicle", "LeftUpperArm": "Bip01 L UpperArm", "LeftLowerArm": "Bip01 L Forearm", "LeftHand": "Bip01 L Hand",
	"LeftThumbMetacarpal": "Bip01 L Finger0", "LeftThumbProximal": "Bip01 L Finger01", "LeftThumbDistal": "Bip01 L Finger02",
	"LeftIndexProximal": "Bip01 L Finger1", "LeftIndexIntermediate": "Bip01 L Finger11", "LeftIndexDistal": "Bip01 L Finger12",
	"LeftMiddleProximal": "Bip01 L Finger2", "LeftMiddleIntermediate": "Bip01 L Finger21", "LeftMiddleDistal": "Bip01 L Finger22",
	"LeftRingProximal": "Bip01 L Finger3", "LeftRingIntermediate": "Bip01 L Finger31", "LeftRingDistal": "Bip01 L Finger32",
	"LeftLittleProximal": "Bip01 L Finger4", "LeftLittleIntermediate": "Bip01 L Finger41", "LeftLittleDistal": "Bip01 L Finger42",
	"LeftUpperLeg": "Bip01 L Thigh", "LeftLowerLeg": "Bip01 L Calf", "LeftFoot": "Bip01 L Foot", "LeftToes": "Bip01 L Toe0"}
func bonemap(d: Dictionary, kind: String) -> BoneMap:
	var bm := BoneMap.new(); bm.profile = SkeletonProfileHumanoid.new()
	for k in d:
		bm.set_skeleton_bone_name(k, d[k])
		if k.begins_with("Left"):
			var r: String = d[k]
			r = r.replace("_l", "_r") if kind == "ual" else r.replace(" L ", " R ")
			bm.set_skeleton_bone_name("Right" + k.substr(4), r)
	return bm
func _init():
	var args := OS.get_cmdline_user_args()   # pairs: path kind skeleton_node_path
	for i in range(0, args.size(), 3):
		var path := args[i] + ".import"; var kind := args[i + 1]
		var cf := ConfigFile.new(); var err := cf.load(path)
		if err != OK: print("cannot load ", path); continue
		var opts := {"retarget/bone_map": bonemap(UAL if kind == "ual" else RB, kind),
			"retarget/rest_fixer/fix_silhouette/enable": kind != "ual",
			"retarget/rest_fixer/fix_silhouette/filter": [&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head", &"LeftEye", &"RightEye", &"Jaw", &"LeftFoot", &"RightFoot", &"LeftToes", &"RightToes"] as Array[StringName],
			"retarget/bone_renamer/unique_node/skeleton_name": "Skel"}
		cf.set_value("params", "_subresources", {"nodes": {"PATH:" + args[i + 2]: opts}})
		cf.save(path); print("wrote ", path)
	quit()
