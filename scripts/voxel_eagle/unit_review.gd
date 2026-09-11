extends Node3D
## 单位审查场景：全部单位（player / boss / E1~E10）摆成 4×3 阵列，快捷键切机位认物。
## 核心用途：spec 管线造新单位后的视觉验收——「认物」必须看游戏真实相机
## （正交 34 / (0,30,12)），等距图只看层次。
##
## 打开方式：编辑器打开 scenes/unit_review.tscn → F5（运行当前场景）
## 按键：
##   1 游戏尺度（正交 34 / (0,30,12)，与 game.gd 完全一致）★认物用这个
##   2 等距机位（看层次 / 高度）
##   3 特写（正交 8，看块面与配色）
##   ←/→  切换选中单位（单看模式居中）
##   S    全家福 / 单看 切换
##   R    选中单位自转开关
##   Esc  退出
## 旋翼单位（E3/E7）的旋翼层持续旋转、E1 炮头缓慢扫摆——看实际运行观感。

const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const Stages = preload("res://scripts/voxel_eagle/stages.gd")

const CAM_GAME_SIZE := 34.0    # 与 game.gd 一致
const CAM_ISO_SIZE := 46.0
const CAM_CLOSE_SIZE := 8.0

const AIR_Y := 4.3             # 空中单位飞行高度（与 game.gd 一致）
const ENEMY_SCALE := 0.3
const BOSS_SCALE := 0.5

## 单位清单：键 = ENEMY_VOX 键；rotor = 旋翼层文件；head = E1 炮头
const UNITS := [
	{"k": "player", "scale": ENEMY_SCALE},
	{"k": "boss", "scale": BOSS_SCALE},
	{"k": "E1", "scale": ENEMY_SCALE, "ground": true, "head": "E1H"},
	{"k": "E2", "scale": ENEMY_SCALE},
	{"k": "E3", "scale": ENEMY_SCALE, "rotor": "E3R"},
	{"k": "E4", "scale": ENEMY_SCALE},
	{"k": "E5", "scale": ENEMY_SCALE},
	{"k": "E6", "scale": ENEMY_SCALE},
	{"k": "E7", "scale": ENEMY_SCALE, "rotor": "E7R"},
	{"k": "E8", "scale": ENEMY_SCALE},
	{"k": "E9", "scale": ENEMY_SCALE},
	{"k": "E10", "scale": ENEMY_SCALE},
]

const COLS := 4
const GRID_X := 14.0          # 4 列 × 14 → x ∈ [-21, 21]，正交 34 视野宽约 60
const GRID_Z := 12.0          # 3 行 × 12 → z ∈ [-12, 12]

var cam: Camera3D
var sun: DirectionalLight3D
var hud: Label
var entries: Array = []        # [{k, n, rotor, head, spin_speed}]
var sel := 0
var solo := false
var spin := false
var cam_mode := 0              # 0 游戏尺度 / 1 等距 / 2 特写
var t := 0.0


func _ready() -> void:
	var stage: Dictionary = Stages.STAGES[0]    # 第 1 关配色作基准
	_build_env(stage)
	_build_ground(stage)
	_build_units()
	_build_camera()
	_build_hud()
	_apply_solo()


# ---------------------------------------------------------------- 场景

func _build_env(stage: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(stage["sky"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(stage["ambient"])
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(stage["sun"])
	sun.light_energy = float(stage["sun_energy"])
	sun.rotation_degrees = Vector3(-52, -28, 0)   # 与 game.gd 一致
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground(stage: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(stage["sea"])
	mat.roughness = 1.0
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	pm.material = mat
	sea.mesh = pm
	add_child(sea)


func _build_units() -> void:
	for i in UNITS.size():
		var def: Dictionary = UNITS[i]
		var n := Node3D.new()
		n.name = String(def["k"])
		add_child(n)
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(String(def["k"]))
		mi.scale = Vector3.ONE * float(def["scale"])
		mi.material_override = VoxelModel.shaded_material()
		n.add_child(mi)

		var entry := {"k": String(def["k"]), "n": n, "rotor": null, "head": null}
		# 旋翼层：底面落在机身顶面（AABB 反推，子节点继承缩放不另乘）
		if def.has("rotor"):
			var rotor := MeshInstance3D.new()
			rotor.mesh = _mesh(String(def["rotor"]))
			rotor.material_override = VoxelModel.shaded_material()
			rotor.position = Vector3(0, mi.mesh.get_aabb().end.y - rotor.mesh.get_aabb().position.y, 0)
			n.add_child(rotor)
			entry["rotor"] = rotor
		# E1 炮头：同规则叠在基座顶面
		if def.has("head"):
			var head := MeshInstance3D.new()
			head.mesh = _mesh(String(def["head"]))
			head.material_override = VoxelModel.shaded_material()
			head.position = Vector3(0, mi.mesh.get_aabb().end.y - head.mesh.get_aabb().position.y, 0)
			n.add_child(head)
			entry["head"] = head

		# 摆位：地面单位贴海面，空中单位与游戏同高；网格 4×3
		var col := i % COLS
		var row := i / COLS
		var px := (col - (COLS - 1) * 0.5) * GRID_X
		var pz := (row - 1.0) * GRID_Z
		var py := AIR_Y
		if def.has("ground"):
			py = -mi.mesh.get_aabb().position.y * float(def["scale"]) - 0.15
		n.position = Vector3(px, py, pz)
		entries.append(entry)


func _mesh(key: String) -> ArrayMesh:
	var m: ArrayMesh = VoxReader.read_mesh("res://assets/vox/units/%s.vox" % key)
	if m == null or m.get_surface_count() == 0:
		push_warning("%s.vox 加载失败，退化为占位方块" % key)
		var fm := BoxMesh.new()
		fm.size = Vector3(4.5, 1.8, 5.7)
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fm.surface_get_arrays(0))
		return am
	return m


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)                      # 必须先入树，look_at 依赖全局变换
	_apply_cam()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(hud)
	_update_hud()


# ---------------------------------------------------------------- 机位与模式

func _apply_cam() -> void:
	var focus := (entries[sel]["n"] as Node3D).position if solo else Vector3.ZERO
	match cam_mode:
		0:  # ★ 游戏尺度：正交 34 / (0,30,12)，与 game.gd 完全一致——认物用这个
			cam.size = CAM_GAME_SIZE
			cam.position = Vector3(0, 30, 12) + focus
		1:  # 等距：看层次与高度
			cam.size = CAM_ISO_SIZE if solo else CAM_ISO_SIZE + 8.0
			cam.position = Vector3(38, 38, 38) + focus
		2:  # 特写：看块面与配色
			cam.size = CAM_CLOSE_SIZE
			cam.position = Vector3(0, 30, 12) * 0.35 + focus
	cam.look_at(focus)


func _apply_solo() -> void:
	for i in entries.size():
		(entries[i]["n"] as Node3D).visible = (not solo) or i == sel
	_apply_cam()
	_update_hud()


func _update_hud() -> void:
	var cam_name: String = ["游戏尺度(正交34·认物)", "等距(看层次)", "特写(看块面)"][cam_mode]
	var e: Dictionary = entries[sel]
	hud.text = "【单位审查】%s · 1/2/3 机位（当前：%s） · ←/→ 切单位 · S %s · R 自转%s · Esc 退出\n选中：%s" % [
		"单看" if solo else "全家福",
		cam_name,
		"切全家福" if solo else "切单看",
		"开" if spin else "关",
		String(e["k"]),
	]


# ---------------------------------------------------------------- 输入与帧

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			cam_mode = 0
			_apply_cam()
		KEY_2:
			cam_mode = 1
			_apply_cam()
		KEY_3:
			cam_mode = 2
			_apply_cam()
		KEY_LEFT:
			sel = (sel - 1 + entries.size()) % entries.size()
			_apply_solo()
		KEY_RIGHT:
			sel = (sel + 1) % entries.size()
			_apply_solo()
		KEY_S:
			solo = not solo
			_apply_solo()
		KEY_R:
			spin = not spin
		KEY_ESCAPE:
			get_tree().quit()
	_update_hud()


func _process(delta: float) -> void:
	t += delta
	for e in entries:
		var rotor: Node3D = e.get("rotor")
		if rotor != null and ((entries[sel] == e) or not solo):
			rotor.rotate_y(delta * (14.0 if e["k"] == "E3" else 12.0))
		var head: Node3D = e.get("head")
		if head != null and ((entries[sel] == e) or not solo):
			# 炮头缓慢扫摆（游戏内 look_at 玩家，这里演示朝向特征）
			var gp := head.global_position
			head.look_at(Vector3(sin(t * 0.6) * 20.0, gp.y, 20.0))
	if spin:
		(entries[sel]["n"] as Node3D).rotate_y(delta * 1.2)
