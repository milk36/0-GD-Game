extends Node3D
## 玩家机：8 向移动 + Roll/Pitch 倾斜。手感参数对齐方块雄鹰（对照实验控制变量）：
## 速度 24 / 横移边界 ±15 / 倾斜系数 0.32·0.12（game.gd:915-916 同值）。
## **飞行高度是唯一一处与方块雄鹰不同**：M1 起取 altitude.gd 的 AIR（7.5，原 4.5）。
## 这不破坏"手感对照"——判定平面是 XZ，高度只影响表现层（视差与影子错位），
## 详见 altitude.gd 头注的投影推导。

const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const Altitude = preload("res://scripts/tile_eagle/altitude.gd")

const SPEED := 24.0
const HALF_W := 15.0
const Z_MIN := -8.0
const Z_MAX := 10.0
const PLAYER_Y := Altitude.AIR

var _vel := Vector2.ZERO
var _flame: MeshInstance3D
var body: MeshInstance3D              # 机身（受击无敌期由 game.gd 控制闪烁）
var _t := 0.0


func _ready() -> void:
	body = MeshInstance3D.new()
	body.mesh = VoxReader.read_mesh("res://assets/vox/units/player.vox")
	body.scale = Vector3.ONE * 0.3        # 15×19×6 体素 × 0.3 ≈ 4.5×5.7×1.8
	body.material_override = VoxelModel.shaded_material()
	add_child(body)

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


## 受击无敌期的闪烁（只隐机身，尾焰照旧——否则整机会"缺一块"）
func set_blink(hidden: bool) -> void:
	body.visible = not hidden
