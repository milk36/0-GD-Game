extends Object
## 幸存者单位：网格 + 双臂支点 + 头顶叹号的唯一构建入口。
## 游戏（game.gd）与测试场景（survivor_test.gd）共用同一份定义，避免两处走样。
##
## 用法：
##   const SurvivorUnit = preload("res://scripts/voxel_eagle/survivor_unit.gd")
##   var parts := SurvivorUnit.build()          # {n, arm_l, arm_r, ex}
##   SurvivorUnit.pose(parts["arm_l"], parts["arm_r"], t, roping)
##   SurvivorUnit.mark_bob(parts["ex"], t)

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")

# ---- 造型 ----
const ART_LEG := "D"
const ART_TORSO := "O"
const ART_HEAD := "S"
const ART_MARK := "R"
const PAL := {
	"D": Color("3a3a4a"),   # 裤腿
	"O": Color("ffa03c"),   # 躯干（高饱和橙，远视角可读）
	"S": Color("e8b88a"),   # 头
	"R": Color("ff2a6d"),   # 头顶叹号
}
const ARM_COLOR := Color("f5f9ff")

# ---- 尺寸 / 姿态 ----
const SCALE := 0.6              # 游戏内缩放：小人比战机小一号
const BASE_Y := 0.5             # 出生高度
const ARM_PIVOT := Vector3(0.62, 3.1, 0.0)   # 肩部支点（左侧取负 x）
const ARM_OFFSET := Vector3(0.0, 0.55, 0.0)  # 网格上移半格 → 支点落在肩部
const ARM_SIZE := Vector3(0.34, 1.2, 0.34)
const MARK_Y := 6.4             # 叹号悬浮高度（局部坐标）
const MARK_SCALE := 0.55
const ARM_WAVE := 2.4           # 挥手抬臂角
const ARM_WAVE_WOBBLE := 0.45
const ARM_ROPE := 0.5           # 攀爬抱绳角

# ---- 营救参数（游戏与测试场景共用同一套数值）----
const RESCUE_TRIGGER := 4.5     # 悬停进入距离（XZ 平面，同时是进度圈的半径）
const RESCUE_LEAVE := 6.0       # 超过此距离视为松开绳索
const RESCUE_TIME := 0.6        # 从起吊到救起所需秒数
const RESCUE_LIFT := 2.2        # 起吊高度
const RESCUE_SHRINK := 0.75     # 完成时缩到 (1 - 0.75) = 0.25 倍
const ROPE_HEAD_Y := 2.7        # 绳索起点：小人举手高度（0.6 缩放）
const ROPE_COLOR := Color("f5f9ff")

static var _body_mesh: ArrayMesh = null
static var _mark_mesh: ArrayMesh = null


## 本体网格（缓存，重复生成不重建）
static func mesh() -> ArrayMesh:
	if _body_mesh == null:
		_body_mesh = VoxelModel.build_multi([
			{"art": ART_LEG, "pal": {"D": PAL["D"]}, "y": 0, "layers": 1},
			{"art": ART_TORSO, "pal": {"O": PAL["O"]}, "y": 1, "layers": 2},
			{"art": ART_HEAD, "pal": {"S": PAL["S"]}, "y": 3, "layers": 1},
		])
	return _body_mesh


## 头顶叹号网格（竖条 + 间隙 + 点，远视角醒目）
static func mark_mesh() -> ArrayMesh:
	if _mark_mesh == null:
		_mark_mesh = VoxelModel.build_multi([
			{"art": ART_MARK, "pal": {"R": PAL["R"]}, "y": 2, "layers": 3},
			{"art": ART_MARK, "pal": {"R": PAL["R"]}, "y": 0, "layers": 1},
		])
	return _mark_mesh


## 构建一个可挂载的幸存者节点。scale 可覆盖（测试场景用来对比大小）。
static func build(scale := SCALE) -> Dictionary:
	var n := MeshInstance3D.new()
	n.name = "Survivor"
	n.mesh = mesh()
	n.material_override = VoxelModel.unshaded_material()  # 无光照高亮：远视角可读
	n.scale = Vector3.ONE * scale

	# 双臂：肩部支点 + 上举手臂，待救时高举挥动呼叫
	var arms := {}
	for s in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.name = "ArmL" if s < 0.0 else "ArmR"
		piv.position = Vector3(s * ARM_PIVOT.x, ARM_PIVOT.y, ARM_PIVOT.z)
		n.add_child(piv)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = ARM_SIZE
		var amat := StandardMaterial3D.new()
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amat.albedo_color = ARM_COLOR
		am.material = amat
		arm.mesh = am
		arm.position = ARM_OFFSET
		piv.add_child(arm)
		arms["L" if s < 0.0 else "R"] = piv

	# 头顶叹号（默认隐藏，由调用方按距离/状态决定显隐）
	var ex := MeshInstance3D.new()
	ex.name = "Mark"
	ex.mesh = mark_mesh()
	ex.material_override = VoxelModel.unshaded_material()
	ex.scale = Vector3.ONE * MARK_SCALE
	ex.position = Vector3(0, MARK_Y, 0)
	ex.visible = false
	ex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 指示标不投影（悬浮过高会拉出大片黑影）
	n.add_child(ex)

	return {"n": n, "arm_l": arms["L"], "arm_r": arms["R"], "ex": ex}


## 挥动/抱绳姿态（公式与 game.gd 原实现一致）
static func pose(arm_l: Node3D, arm_r: Node3D, t: float, roping: bool) -> void:
	if roping:
		arm_l.rotation.z = ARM_ROPE
		arm_r.rotation.z = -ARM_ROPE
	else:
		var wob := sin(t * 8.0)
		arm_l.rotation.z = ARM_WAVE + wob * ARM_WAVE_WOBBLE
		arm_r.rotation.z = -ARM_WAVE + wob * ARM_WAVE_WOBBLE


## 叹号上下轻浮动
static func mark_bob(ex: MeshInstance3D, t: float) -> void:
	ex.position.y = MARK_Y + sin(t * 4.0) * 0.25


## 被起吊中的位移/缩放：prog 0→1 表示从地面升到顶。返回 true = 已完成
static func apply_rescue_progress(n: Node3D, prog: float) -> bool:
	n.position.y = BASE_Y + prog * RESCUE_LIFT
	n.scale = Vector3.ONE * (SCALE * (1.0 - prog * RESCUE_SHRINK))
	return prog >= 1.0


## 松开绳索：回到地面原状
static func reset_rescue(n: Node3D) -> void:
	n.position.y = BASE_Y
	n.scale = Vector3.ONE * SCALE


## 绳索位姿：从幸存者举手高度连到玩家。近乎垂直，不能用 look_at（方向与 UP 平行会报错），
## 手动构建正交基。返回 {"xf": Transform3D, "len": float}
static func rope_pose(sur_gp: Vector3, player_pos: Vector3) -> Dictionary:
	var top := sur_gp + Vector3(0, ROPE_HEAD_Y, 0)
	var dz := player_pos - top
	var zz := dz.normalized()
	var xx := zz.cross(Vector3.FORWARD)
	if xx.length_squared() < 0.001:
		xx = zz.cross(Vector3.RIGHT)
	xx = xx.normalized()
	var yy := zz.cross(xx)
	return {
		"xf": Transform3D(Basis(xx, yy, zz), (top + player_pos) * 0.5),
		"len": dz.length(),
	}
