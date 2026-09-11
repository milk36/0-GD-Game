extends Node3D
## 玩家机：8 向移动 + Roll/Pitch 倾斜。手感参数对齐方块雄鹰（对照实验控制变量）：
## 速度 24 / 横移边界 ±15 / 飞行高度 4.5 / 倾斜系数 0.32·0.12（game.gd:915-916 同值）。

const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")

const SPEED := 24.0
const HALF_W := 15.0
const Z_MIN := -8.0
const Z_MAX := 10.0
const PLAYER_Y := 4.5

var _vel := Vector2.ZERO
var _flame: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxReader.read_mesh("res://assets/vox/units/player.vox")
	mi.scale = Vector3.ONE * 0.3          # 15×19×6 体素 × 0.3 ≈ 4.5×5.7×1.8
	mi.material_override = VoxelModel.shaded_material()
	add_child(mi)

	_flame = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.5, 0.5, 1.4)
	_flame.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("ffe600")
	_flame.material_override = fmat
	_flame.position = Vector3(0, 0, 3.2)
	add_child(_flame)

	position = Vector3(0, PLAYER_Y, 6)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y -= 1.0
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	_vel = _vel.lerp(dir * SPEED, 1.0 - exp(-delta / 0.08))   # 加速 ~0.08s 到全速
	position.x = clampf(position.x + _vel.x * delta, -HALF_W, HALF_W)
	position.z = clampf(position.z - _vel.y * delta, Z_MIN, Z_MAX)

	# 倾斜：满杆 Roll ±0.32rad，前后微俯仰（与方块雄鹰一致）
	rotation.z = lerpf(rotation.z, -dir.x * 0.32, 10.0 * delta)
	rotation.x = lerpf(rotation.x, dir.y * 0.12, 10.0 * delta)

	_t += delta
	_flame.scale = Vector3.ONE * (0.9 + 0.25 * sin(_t * 14.0))
