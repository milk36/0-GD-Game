extends Node3D
## 幸存者 + 营救 测试场景：开局摆出 10 个幸存者与玩家机，可开着飞机实地试营救手感。
## 相机、玩家高度、营救判定、起吊表现全部照抄游戏内数值（常量集中在 survivor_unit.gd）。
##
## 打开方式：编辑器打开 scenes/survivor_test.tscn → F5（运行当前场景）
## 按键：
##   方向键 / WASD  飞行（与游戏同速 24 单位/秒）
##   1 游戏尺度（正交 34 / (0,30,12)，与游戏一致）
##   2 特写（正交 8）   3 救援跟拍（低角度跟随飞机，看营救全流程）
##   4 缩放循环 0.6 → 0.9 → 1.2     5 背景明暗     6 阴影开关     7 叹号显隐
##   T 一键演示营救（飞机瞬移到第 6 个幸存者上方并自动切跟拍）
##   R 重置全部幸存者                空格 暂停挥手
##   Esc 退出

const SurvivorUnit = preload("res://scripts/voxel_eagle/survivor_unit.gd")
const RescueRing = preload("res://scripts/voxel_eagle/rescue_ring.gd")
const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const Stages = preload("res://scripts/voxel_eagle/stages.gd")

const COUNT := 10
const SPACING := 5.0            # 一字排开，间距 5 单位（正交视野宽约 60 单位）
const SCALE_STEPS := [0.6, 0.9, 1.2]

const CAM_GAME_SIZE := 34.0
const CAM_CLOSE_SIZE := 8.0

const PLAYER_SPEED := 24.0      # 与 game.gd 一致
const PLAYER_Y := 4.5           # 玩家飞行高度
const BOUND_X := 28.0
const BOUND_Z_MIN := -16.0
const BOUND_Z_MAX := 12.0

var cam: Camera3D
var sun: DirectionalLight3D
var hud: Label
var sea: MeshInstance3D
var player: Node3D
var rope: MeshInstance3D
var rescue_ring: MeshInstance3D
var ring_flash_t := 0.0
var units: Array = []           # [{n, arm_l, arm_r, ex, roping, prog, done}]
var stage: Dictionary

var t := 0.0
var paused := false
var marks_visible := true
var cam_mode := 0               # 0 游戏尺度 / 1 特写 / 2 救援跟拍
var scale_i := 0
var bright_ground := false
var rescued := 0


func _ready() -> void:
	stage = Stages.STAGES[0]    # 第 1 关配色作基准
	_build_env()
	_build_ground()
	_build_survivors()
	_build_player()
	_build_camera()
	_build_hud()
	_apply_scale()


# ---------------------------------------------------------------- 场景
func _build_env() -> void:
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
	sun.rotation_degrees = Vector3(-52, -28, 0)   # 与 _build_env 一致
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(stage["sea"])
	mat.roughness = 1.0
	sea = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	pm.material = mat
	sea.mesh = pm
	add_child(sea)


func _build_survivors() -> void:
	for i in COUNT:
		var parts := SurvivorUnit.build()
		var n: Node3D = parts["n"]
		n.name = "Survivor%02d" % (i + 1)     # 唯一命名，便于在远程树里定位
		add_child(n)
		n.position = Vector3((i - (COUNT - 1) * 0.5) * SPACING, SurvivorUnit.BASE_Y, 0.0)
		(parts["ex"] as MeshInstance3D).visible = marks_visible
		parts["roping"] = false
		parts["prog"] = 0.0
		parts["done"] = false
		units.append(parts)


## 玩家机 + 尾焰 + 救援绳索（尺寸/材质/缩放照抄 game.gd::_build_player）
func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxReader.read_mesh("res://assets/vox/units/player.vox")
	mi.scale = Vector3.ONE * 0.3
	mi.material_override = VoxelModel.shaded_material()
	player.add_child(mi)

	var fm := BoxMesh.new()
	fm.size = Vector3(0.5, 0.5, 1.4)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("ffe600")
	fm.material = fmat
	var flame := MeshInstance3D.new()
	flame.mesh = fm
	flame.position = Vector3(0, 0, 3.2)
	player.add_child(flame)

	var rm := BoxMesh.new()
	rm.size = Vector3(0.16, 0.16, 1.0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = SurvivorUnit.ROPE_COLOR
	rm.material = rmat
	rope = MeshInstance3D.new()
	rope.mesh = rm
	rope.visible = false
	add_child(rope)

	# 营救进度计时圈（与游戏一致：挂在机上、半径=触发距离、救起后闪 0.3s）
	rescue_ring = RescueRing.build()
	player.add_child(rescue_ring)

	player.position = Vector3(0, PLAYER_Y, 6)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)                      # 必须先入树，look_at 依赖全局变换
	_apply_cam_mode(0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(hud)
	_update_hud()


func _update_hud() -> void:
	var hovering := 0.0
	for u in units:
		if bool(u["roping"]):
			hovering = float(u["prog"])
	var cam_name: String = ["游戏尺度", "特写", "救援跟拍"][cam_mode]
	hud.text = "【幸存者营救测试】方向键/WASD 飞行 · T 演示营救 · R 重置 · Esc 退出\n1 游戏尺度 / 2 特写 / 3 救援跟拍（当前：%s） · 4 缩放 %.1f× · 5 背景%s · 6 阴影%s · 7 叹号%s\n已救 %d/%d%s" % [
		cam_name,
		SCALE_STEPS[scale_i],
		"亮" if bright_ground else "海底色",
		"开" if sun.shadow_enabled else "关",
		"开" if marks_visible else "关",
		rescued, COUNT,
		"   起吊中 %d%%" % int(hovering * 100.0) if hovering > 0.0 else "",
	]


# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_apply_cam_mode(0)
		KEY_2:
			_apply_cam_mode(1)
		KEY_3:
			_apply_cam_mode(2)
		KEY_4:
			scale_i = (scale_i + 1) % SCALE_STEPS.size()
			_apply_scale()
		KEY_5:
			bright_ground = not bright_ground
			var pm := (sea.mesh as PlaneMesh)
			(pm.material as StandardMaterial3D).albedo_color = Color("9aa4b0") if bright_ground else Color(stage["sea"])
		KEY_6:
			sun.shadow_enabled = not sun.shadow_enabled
		KEY_7:
			marks_visible = not marks_visible
			for u in units:
				(u["ex"] as MeshInstance3D).visible = marks_visible
		KEY_T:
			demo_rescue()
		KEY_R:
			reset_all()
		KEY_SPACE:
			paused = not paused
		KEY_ESCAPE:
			get_tree().quit()
	_update_hud()


## 一键演示：把飞机瞬移到第 6 个幸存者上方并开始起吊。
## start_prog > 0 时直接定格在该进度（截图用），否则从 0 开始播完整过程。
func demo_rescue(start_prog := 0.0) -> void:
	if units.size() < 6:
		return
	var u: Dictionary = units[5]
	var n: Node3D = u["n"]
	n.visible = true
	player.position = Vector3(n.position.x, PLAYER_Y, n.position.z)
	u["roping"] = true
	u["prog"] = start_prog
	u["done"] = false
	_apply_cam_mode(2)          # 自动切到救援跟拍，否则机身会挡住被吊起的人
	if start_prog > 0.0:
		paused = true           # 定格在该进度（截图用，否则未限帧时几帧就跑完了）
		SurvivorUnit.apply_rescue_progress(n, start_prog)
		rope.visible = true
		_rope_pose(n)
		_update_rescue_ring(start_prog, 0.0)   # 定格时也把进度圈画出来
	_update_hud()


func reset_all() -> void:
	for u in units:
		if not is_instance_valid(u["n"]):
			continue
		u["roping"] = false
		u["prog"] = 0.0
		u["done"] = false
		var n: Node3D = u["n"]
		n.visible = true
		SurvivorUnit.reset_rescue(n)
	rescued = 0
	paused = false
	ring_flash_t = 0.0
	if rescue_ring != null:
		rescue_ring.visible = false
	rope.visible = false
	player.position = Vector3(0, PLAYER_Y, 6)
	_update_hud()


func _apply_cam_mode(mode: int) -> void:
	cam_mode = mode
	match mode:
		1:
			cam.size = CAM_CLOSE_SIZE
			cam.position = Vector3(0, 7, 9)
			cam.look_at(Vector3(0, 1.2, 0))
		2:
			_update_follow_cam()
		_:
			cam.size = CAM_GAME_SIZE
			cam.position = Vector3(0, 30, 12)
			cam.look_at(Vector3.ZERO)


## 救援跟拍：低角度斜视，飞机、绳索、被吊起的幸存者都在画面里
## （游戏尺度是近乎俯视，机身会投影成一条线并挡住被吊起的人）
func _update_follow_cam() -> void:
	cam.size = 15.0
	# 3/4 侧前方：正上方俯视会把机身投影成一条线并挡住被吊起的人
	cam.position = player.position + Vector3(11.0, 6.0, 11.0)
	cam.look_at(player.position + Vector3(0, -2.2, 0))


func _apply_scale() -> void:
	var s: float = SCALE_STEPS[scale_i]
	for u in units:
		(u["n"] as Node3D).scale = Vector3.ONE * s


# ---------------------------------------------------------------- 逐帧
func _process(delta: float) -> void:
	if not paused:
		t += delta
	_fly(delta)
	if cam_mode == 2:
		_update_follow_cam()
	var ring_prog := -1.0
	for u in units:
		if not paused:              # 暂停/定格时不推进营救（截图定格靠这个）
			_update_unit(u, delta)
		if bool(u["roping"]):
			ring_prog = maxf(ring_prog, float(u["prog"]))
		SurvivorUnit.mark_bob(u["ex"], t)
		SurvivorUnit.pose(u["arm_l"], u["arm_r"], t, bool(u["roping"]))
	_update_rescue_ring(ring_prog, delta)


## 进度圈刷新（逻辑与 game.gd 一致）
func _update_rescue_ring(prog: float, delta: float) -> void:
	if rescue_ring == null:
		return
	if prog >= 0.0:
		rescue_ring.visible = true
	elif ring_flash_t > 0.0:
		ring_flash_t -= delta
		prog = 1.0
		if ring_flash_t <= 0.0:
			rescue_ring.visible = false
			return
	else:
		rescue_ring.visible = false
		return
	RescueRing.aim(rescue_ring, cam, player.global_position)
	RescueRing.set_progress(rescue_ring, clampf(prog, 0.0, 1.0))


func _fly(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if dir != Vector3.ZERO:
		player.position += dir.normalized() * PLAYER_SPEED * delta
	player.position.x = clampf(player.position.x, -BOUND_X, BOUND_X)
	player.position.z = clampf(player.position.z, BOUND_Z_MIN, BOUND_Z_MAX)
	player.position.y = PLAYER_Y


## 单个幸存者的营救状态机（阈值与 game.gd 一致，只是没有滚动/敌人）
func _update_unit(u: Dictionary, delta: float) -> void:
	if not is_instance_valid(u["n"]):
		return
	var n: Node3D = u["n"]
	var d := _xz_dist(n.global_position, player.position)
	if bool(u["roping"]):
		if d > SurvivorUnit.RESCUE_LEAVE:
			u["roping"] = false
			u["prog"] = 0.0
			SurvivorUnit.reset_rescue(n)
			rope.visible = false
			return
		u["prog"] = float(u["prog"]) + delta / SurvivorUnit.RESCUE_TIME
		if SurvivorUnit.apply_rescue_progress(n, float(u["prog"])):
			rescued += 1
			SFX.play("eagle_rescue")   # 与游戏同一音效（上行琶音）
			n.visible = false          # 救起即隐藏（游戏里是 queue_free，这里保留以便 R 重置）
			u["roping"] = false
			u["prog"] = 0.0
			u["done"] = true
			rope.visible = false
			ring_flash_t = RescueRing.FLASH_TIME
			_update_hud()
			return
		rope.visible = true
		_rope_pose(n)
	elif not bool(u["done"]) and d < SurvivorUnit.RESCUE_TRIGGER:
		u["roping"] = true
		u["prog"] = 0.0


func _rope_pose(n: Node3D) -> void:
	var rp := SurvivorUnit.rope_pose(n.global_position, player.position)
	rope.global_transform = rp["xf"]
	rope.scale = Vector3(1, 1, rp["len"])


func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
