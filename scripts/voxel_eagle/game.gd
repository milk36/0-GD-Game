extends Node3D
## 方块雄鹰 M0 快速验证原型：体素纵版弹幕射击。
## 玩家 WASD/方向键移动 + 自动射击 + 空格炸弹；敌波循环刷出 5 类敌人。
## 调试键：F1/F2 相机 68°/90° A/B 对比，F3 阴影开关，F4 弹幕压测（300 发）。
## 一切视觉资源由代码生成（字符画体素 + 纯色材质），零外部资源依赖。

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const VoxelPool = preload("res://scripts/voxel_eagle/pools.gd")

# ---- 数值 ----
const SCROLL := 7.0            # 世界滚动速度 VU/s
const PLAYER_SPEED := 24.0
const ARENA_HALF_W := 15.0     # 玩家横移边界
const PLAYER_Z_MIN := -8.0
const PLAYER_Z_MAX := 10.0
const FIRE_INTERVAL := 0.11
const BULLET_SPEED := 46.0
const ENEMY_BULLET_Y := 1.0    # 敌弹飞行高度（与玩家判定平面一致）
const STAR_LIFE := 9.0

const COL_CYAN := Color("00f0ff")
const COL_PINK := Color("ff2a6d")
const COL_YELLOW := Color("ffe600")
const COL_WHITE := Color("f5f9ff")

const ART_PLAYER := "
   W
  BCB
 BCCCB
BCCCCCB
 BCCCB
  BBB
  B B
"
const PAL_PLAYER := {"B": Color("2979ff"), "C": COL_CYAN, "W": COL_WHITE}

const ART_TURRET := "
GGG
GRG
GGG
"
const ART_RING := "
SSS
SRS
SSS
"
const ART_DRONE := "
MM
MM
"
const ART_WING := "
 G
GCG
 G
 G
"
const ART_RAIDER := "
  D
 DDD
DDDDD
  D
"
const PAL_ENEMY := {
	"G": Color("6a7488"), "R": Color("ff2a6d"), "S": Color("8a7a52"),
	"M": Color("ff2a6d"), "C": Color("ffb0c8"), "D": Color("b03050"),
}

# ---- 场景节点 ----
var world: Node3D
var player: Node3D
var player_mesh: MeshInstance3D
var flame: MeshInstance3D
var cam: Camera3D
var sun: DirectionalLight3D
var pb: MultiMeshInstance3D   # 自机弹
var eb: MultiMeshInstance3D   # 敌弹
var pickups: MultiMeshInstance3D  # 星星
var fx: MultiMeshInstance3D    # 碎片/闪光
var enemies: Array = []        # [{n,t,hp,ft,age,x0,...}]
var waves: Array = []         # 波浪装饰 Node3D
var islands: Array = []       # 岛 Node3D

# ---- HUD ----
var hud_score: Label
var hud_armor: Label
var hud_info: Label
var hud_center: Label

# ---- 状态 ---- （M0 原型：全部状态集中在根脚本，M1 拆分）
var score := 0
var star_cnt := 0
var armor := 3
var bombs := 2
var invuln := 0.0
var dead := false
var paused := false
var fire_cd := 0.0
var elapsed := 0.0
var wave_t := 0.0
var wave_idx := 0
var shake := 0.0
var cam_mode := 0             # 0=68° 斜俯视 1=90° 纯俯视
var stress := false
var hud_cd := 0.0
var _meshes := {}             # 敌型号 → 共享 ArrayMesh


func _ready() -> void:
	_build_env()
	_build_ground()
	_build_player()
	_build_pools()
	_build_hud()
	_meshes = {
		"E1": VoxelModel.build(ART_TURRET, PAL_ENEMY, 2),
		"E2": VoxelModel.build(ART_RING, PAL_ENEMY, 3),
		"E3": VoxelModel.build(ART_DRONE, PAL_ENEMY, 1),
		"E4": VoxelModel.build(ART_WING, PAL_ENEMY, 2),
		"E5": VoxelModel.build(ART_RAIDER, PAL_ENEMY, 2),
	}


# ================= 场景构建 =================

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("050810")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("223050")
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = 1  # DEPTH
	env.fog_light_color = Color("0a2540")
	env.fog_depth_begin = 46.0
	env.fog_depth_end = 120.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff2e0")
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 0  # ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	cam = Camera3D.new()
	cam.projection = 1  # ORTHOGONAL
	cam.size = 26.0
	cam.near = 0.5
	cam.far = 260.0
	add_child(cam)
	cam.position = Vector3(0, 30, 12)
	cam.look_at(Vector3.ZERO)


func _build_ground() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	# 海面：纯色大平面（无纹理，运动感由波浪块/岛提供）
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color("0a2540")
	sea_mat.roughness = 1.0
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(72, 300)
	pm.material = sea_mat
	sea.mesh = pm
	sea.position = Vector3(0, 0, -110)
	add_child(sea)

	# 波浪装饰块：挂 World 随滚动流动，滚出下缘后回绕
	var wave_box := BoxMesh.new()
	wave_box.size = Vector3(2.0, 0.14, 2.0)
	wave_box.material = VoxelModel.shaded_material()
	for i in 46:
		var w := MeshInstance3D.new()
		w.mesh = wave_box
		w.position = Vector3(randf_range(-26, 26), 0.07, randf_range(-200, 24))
		world.add_child(w)
		waves.append(w)

	# 体素小岛：草块 + 二层 + 沙边
	for i in 7:
		islands.append(_make_island())


func _make_island() -> Node3D:
	var blocks := {}
	var half := randi_range(1, 2)
	for x in range(-half - 1, half + 2):
		for z in range(-half - 1, half + 2):
			var edge := absi(x) > half or absi(z) > half
			blocks[Vector3i(x, 0, z)] = Color("8a7a52") if edge else Color("1f6f3f")
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			if (x + z) % 2 == 0:
				blocks[Vector3i(x, 1, z)] = Color("2a8a4f")
	var n := MeshInstance3D.new()
	n.mesh = VoxelModel.build_blocks(blocks)
	n.material_override = VoxelModel.shaded_material()
	n.position = Vector3(randf_range(-22, 22), 0, randf_range(-200, 24))
	world.add_child(n)
	return n


func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	player_mesh = MeshInstance3D.new()
	player_mesh.mesh = VoxelModel.build(ART_PLAYER, PAL_PLAYER, 3)
	player_mesh.material_override = VoxelModel.shaded_material()
	player.add_child(player_mesh)
	player.position = Vector3(0, 1.4, 6)

	flame = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.5, 0.5, 1.4)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = COL_YELLOW
	fm.material = fmat
	flame.mesh = fm
	flame.position = Vector3(0, 0, 3.2)
	player.add_child(flame)


func _build_pools() -> void:
	var unshaded := VoxelModel.unshaded_material()
	pb = VoxelPool.new()
	add_child(pb)
	pb.setup(64, unshaded)
	eb = VoxelPool.new()
	add_child(eb)
	eb.setup(512, unshaded)
	pickups = VoxelPool.new()
	add_child(pickups)
	pickups.setup(256, unshaded)
	fx = VoxelPool.new()
	add_child(fx)
	fx.setup(320, unshaded)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_score = _mk_label(layer, Vector2(24, 16), 22, COL_CYAN)
	hud_armor = _mk_label(layer, Vector2(24, 52), 18, COL_PINK)
	hud_info = _mk_label(layer, Vector2(24, 690), 14, Color("8a93b8"))
	hud_center = _mk_label(layer, Vector2(360, 300), 30, COL_YELLOW)


func _mk_label(parent: Node, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


# ================= 主循环 =================

func _process(delta: float) -> void:
	if paused:
		return
	elapsed += delta
	shake = maxf(0.0, shake - delta)
	invuln = maxf(0.0, invuln - delta)

	# 世界滚动 + 地面装饰回绕
	world.position.z += SCROLL * delta
	for w in waves:
		if world.position.z + w.position.z > 26.0:
			w.position.z -= 224.0
			w.position.x = randf_range(-26, 26)
	for isl in islands:
		if world.position.z + isl.position.z > 30.0:
			isl.position.z -= 230.0
			isl.position.x = randf_range(-22, 22)

	if not dead:
		_update_player(delta)
		_update_waves(delta)
		_update_enemies(delta)
	_update_bullets(delta)
	_update_pickups(delta)
	fx.update(delta)
	_update_camera(delta)

	hud_cd -= delta
	if hud_cd <= 0.0:
		hud_cd = 0.15
		_refresh_hud()


# ================= 玩家 =================

func _update_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	dir = dir.normalized()
	player.position.x = clampf(player.position.x + dir.x * PLAYER_SPEED * delta, -ARENA_HALF_W, ARENA_HALF_W)
	player.position.z = clampf(player.position.z + dir.y * PLAYER_SPEED * delta, PLAYER_Z_MIN, PLAYER_Z_MAX)

	# 机身倾斜 + 尾焰脉动
	player.rotation.z = lerp(player.rotation.z, -dir.x * 0.32, 10.0 * delta)
	player.rotation.x = lerp(player.rotation.x, dir.y * 0.12, 10.0 * delta)
	flame.scale.z = 1.0 + 0.45 * sin(elapsed * 31.0) + dir.y * 0.4
	flame.position.y = sin(elapsed * 17.0) * 0.05

	# 无敌闪烁
	player_mesh.visible = invuln <= 0.0 or fmod(invuln, 0.24) < 0.12

	# 自动射击（双列）
	fire_cd -= delta
	if fire_cd <= 0.0:
		fire_cd = FIRE_INTERVAL
		for sx in [-0.75, 0.75]:
			pb.spawn(player.position + Vector3(sx, 0.2, -3.0), Vector3(0, 0, -BULLET_SPEED), COL_CYAN, 0.42, 1.4)

	if stress and eb.count < 300:
		for i in 6:
			var p := Vector3(randf_range(-16, 16), ENEMY_BULLET_Y, randf_range(-34, -14))
			_spawn_enemy_bullet(p, Vector3(randf_range(-4, 4), 0, randf_range(4, 9)), COL_PINK)


func hit_player() -> void:
	if invuln > 0.0 or dead:
		return
	armor -= 1
	invuln = 1.5
	shake = 0.35
	_burst(player.position, COL_CYAN, 8)
	if armor <= 0:
		dead = true
		_burst(player.position, COL_WHITE, 24)
		_burst(player.position, COL_PINK, 18)
		player.visible = false
		hud_center.text = "坠机！  R 重开 · Q 返回大厅"


func use_bomb() -> void:
	if dead or bombs <= 0:
		return
	bombs -= 1
	invuln = maxf(invuln, 1.6)
	shake = 0.4
	for i in range(eb.count):
		eb.kill(0)
	for e in enemies:
		_damage_enemy(e, 6)
	for i in 26:  # 冲击环
		var a := TAU * float(i) / 26.0
		fx.spawn(player.position + Vector3(0, 0.5, 0), Vector3(cos(a) * 22.0, 0.5, sin(a) * 22.0), COL_CYAN, 0.8, 0.55, 0.0, Vector3.ZERO, true)


func restart() -> void:
	get_tree().reload_current_scene()


# ================= 敌波 =================

func _update_waves(_delta: float) -> void:
	wave_t -= _delta
	if wave_t <= 0.0:
		wave_t = 3.4
		_spawn_wave(wave_idx % 6)
		wave_idx += 1


func _spawn_wave(idx: int) -> void:
	match idx:
		0:
			for i in 6:
				_spawn_air("E3", -14.0 + 5.6 * float(i), 3, randf_range(2.5, 4.0) * (1.0 if i % 2 == 0 else -1.0))
		1:
			_spawn_ground("E1", -8.0)
			_spawn_ground("E1", 8.0)
		2:
			for i in 3:
				_spawn_air("E5", -10.0 + 10.0 * float(i), 5)
		3:
			_spawn_ground("E2", 0.0)
			_spawn_ground("E1", 10.0)
			_spawn_ground("E1", -10.0)
		4:
			for i in 5:
				_spawn_air("E4", -8.0 + 4.0 * float(i), 4)
		5:
			for i in 4:
				_spawn_air("E3", -12.0 + 8.0 * float(i), 3, randf_range(-4.0, 4.0))
			_spawn_air("E5", 12.0, 5)


func _spawn_ground(type: String, x: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _meshes[type]
	n.material_override = VoxelModel.shaded_material()
	world.add_child(n)
	n.position = Vector3(x, 0.05, -58.0 - world.position.z)
	enemies.append({"n": n, "t": type, "hp": 4 if type == "E2" else 3, "ft": randf_range(0.8, 1.6), "age": 0.0, "ground": true})


func _spawn_air(type: String, x: float, hp: int, vx := 0.0) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _meshes[type]
	n.material_override = VoxelModel.shaded_material()
	add_child(n)
	var vz := SCROLL + (10.0 if type == "E3" else 5.0 if type == "E4" else 3.0)
	n.position = Vector3(x, 1.6, -46.0)
	enemies.append({"n": n, "t": type, "hp": hp, "ft": randf_range(0.6, 1.4), "age": 0.0, "ground": false, "vx": vx, "vz": vz, "x0": x})


func _update_enemies(delta: float) -> void:
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		e.age += delta
		var n: Node3D = e.n
		var gp := n.global_position
		if gp.z > 26.0 or gp.z < -70.0:  # 逃逸/异常回收
			n.queue_free()
			enemies.remove_at(i)
			continue
		match e.t:
			"E1":
				n.look_at(Vector3(player.position.x, n.global_position.y, player.position.z))
				e.ft -= delta
				if gp.z > -34.0 and gp.z < 6.0 and e.ft <= 0.0:
					e.ft = 2.2
					_fire_aimed(gp, 8.0, 3, 14.0)
			"E2":
				e.ft -= delta
				if gp.z > -34.0 and e.ft <= 0.0:
					e.ft = 2.7
					_fire_ring(gp, 14, 6.2, e.age)
					_fire_ring(gp, 14, 7.6, e.age + 0.22)
			"E3":
				n.position += Vector3(e.vx, 0, e.vz) * delta
				n.rotate_y(delta * 7.0)
			"E4":
				n.position += Vector3(e.vx * 0.2 + sin(e.age * 2.0) * 1.5, 0, e.vz) * delta
				e.ft -= delta
				if e.ft <= 0.0:
					e.ft = 2.6
					_fire_aimed(n.global_position, 7.0, 1, 0.0)
			"E5":
				n.position.x = e.x0 + sin(e.age * 1.35) * 7.0
				n.position.z += e.vz * delta
				e.ft -= delta
				if e.ft <= 0.0:
					e.ft = 1.9
					_fire_aimed(n.global_position, 7.5, 5, 42.0)
		i += 1


func _damage_enemy(e: Dictionary, dmg: int) -> void:
	e.hp -= dmg
	if e.hp <= 0:
		var n: Node3D = e.n
		var gp := n.global_position
		_burst(gp, COL_PINK, 12)
		_burst(gp, COL_WHITE, 6)
		var reward: int = {"E1": 5, "E2": 8, "E3": 3, "E4": 3, "E5": 10}.get(e.t, 5)
		var pts: int = {"E1": 50, "E2": 80, "E3": 30, "E4": 50, "E5": 100}.get(e.t, 50)
		score += pts
		for s in reward:
			var v := Vector3(randf_range(-6, 6), randf_range(3, 8), randf_range(-4, 4))
			pickups.spawn(gp + Vector3(0, 0.5, 0), v, COL_YELLOW, 0.85, STAR_LIFE, 16.0)
		n.queue_free()
		enemies.erase(e)


# ================= 弹型库 =================

func _spawn_enemy_bullet(p: Vector3, v: Vector3, col: Color) -> void:
	eb.spawn(p, v, col, 0.62, 8.0)
	eb.spawn(p, v, COL_WHITE, 0.3, 8.0)  # 白色内核提升可读性


func _fire_aimed(from: Vector3, speed: float, n: int, spread_deg: float) -> void:
	var to_p := player.position - from
	to_p.y = 0.0
	var base := atan2(to_p.x, -to_p.z)  # 屏面上朝向玩家的方位角
	for k in n:
		var off := 0.0 if n == 1 else spread_deg * PI / 180.0 * (float(k) / float(n - 1) - 0.5)
		var a := base + off
		_spawn_enemy_bullet(Vector3(from.x, ENEMY_BULLET_Y, from.z), Vector3(sin(a) * speed, 0, -cos(a) * speed), COL_PINK)


func _fire_ring(from: Vector3, n: int, speed: float, phase := 0.0) -> void:
	for k in n:
		var a := TAU * float(k) / float(n) + phase
		_spawn_enemy_bullet(Vector3(from.x, ENEMY_BULLET_Y, from.z), Vector3(sin(a) * speed, 0, cos(a) * speed), COL_PINK)


# ================= 子弹 / 星星 / 碎片 =================

func _update_bullets(_delta: float) -> void:
	pb.update(_delta)
	eb.update(_delta)

	# 自机弹 × 敌人
	var i := 0
	while i < pb.count:
		var hit := false
		for e in enemies:
			var gp: Vector3 = e.n.global_position
			var r := 1.7 if e.t == "E5" or e.t == "E2" else 1.3
			if absf(pb.pos[i].x - gp.x) < r and absf(pb.pos[i].z - gp.z) < r and absf(pb.pos[i].y - gp.y) < 2.5:
				_damage_enemy(e, 1)
				fx.spawn(pb.pos[i], Vector3(0, 2, 4), COL_WHITE, 0.3, 0.14, 0.0, Vector3.ZERO, true)
				hit = true
				break
		if hit:
			pb.kill(i)
		else:
			i += 1

	# 敌弹 × 玩家
	if not dead:
		i = 0
		while i < eb.count:
			var d: Vector3 = eb.pos[i] - player.position
			if absf(d.x) < 0.95 and absf(d.z) < 0.95 and absf(d.y) < 1.2:
				eb.kill(i)
				hit_player()
				if dead:
					break
			else:
				i += 1

	# 敌机撞击
	for e in enemies:
		if e.t == "E3":
			var gp: Vector3 = e.n.global_position
			if absf(gp.x - player.position.x) < 1.6 and absf(gp.z - player.position.z) < 1.6:
				hit_player()


func _update_pickups(delta: float) -> void:
	pickups.update(delta)
	var i := 0
	while i < pickups.count:
		# 落海弹跳 + 随地面滚动
		if pickups.pos[i].y < 0.45 and pickups.vel[i].y < 0.0:
			pickups.vel[i].y = absf(pickups.vel[i].y) * 0.35
			if pickups.vel[i].y < 1.0:
				pickups.vel[i].y = 0.0
				pickups.vel[i].z = SCROLL
		# 磁吸
		var d: Vector3 = player.position - pickups.pos[i]
		var dist: float = d.length()
		if dist < 7.5 and not dead:
			pickups.vel[i] = d.normalized() * clampf(26.0 - dist * 2.0, 8.0, 26.0)
			pickups.vel[i].y *= 0.4
		if dist < 1.7 and not dead:
			pickups.kill(i)
			star_cnt += 1
			score += 10
			continue
		if pickups.pos[i].z > 26.0:
			pickups.kill(i)
			continue
		i += 1


func _burst(at: Vector3, col: Color, n: int) -> void:
	for k in n:
		var v := Vector3(randf_range(-9, 9), randf_range(2, 11), randf_range(-9, 9))
		fx.spawn(at + Vector3(0, 0.4, 0), v, col, randf_range(0.35, 0.65), randf_range(0.4, 0.7), 24.0, Vector3(2, 3, 0), true)


# ================= 相机 / HUD / 输入 =================

func _update_camera(_delta: float) -> void:
	var target := Vector3(player.position.x * 0.62, 0, -3.0)
	var off: Vector3
	if cam_mode == 0:
		var pitch := deg_to_rad(68.0)
		off = Vector3(0, 30.0 * sin(pitch), 30.0 * cos(pitch))
	else:
		off = Vector3(0, 32.0, 0.01)
	cam.position = target + off
	if shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 1.6
	cam.look_at(target)


func _refresh_hud() -> void:
	hud_score.text = "SCORE %d    ★ %d    BOMB ×%d" % [score, star_cnt, bombs]
	hud_armor.text = "护甲 " + "■".repeat(maxi(armor, 0)) + "□".repeat(maxi(3 - armor, 0))
	hud_info.text = "FPS %d  敌弹 %d  F1/F2 相机[68°/90°]  F3 阴影[%s]  F4 压测[%s]  Esc 暂停" % [
		Engine.get_frames_per_second(), eb.count, "开" if sun.shadow_enabled else "关", "开" if stress else "关"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		match key:
			KEY_F1:
				cam_mode = 0
			KEY_F2:
				cam_mode = 1
			KEY_F3:
				sun.shadow_enabled = not sun.shadow_enabled
			KEY_F4:
				stress = not stress
			KEY_ESCAPE:
				if dead:
					get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
				else:
					paused = not paused
					hud_center.text = "已暂停  Esc 继续 · R 重开 · Q 返回大厅" if paused else ""
			KEY_R:
				if paused or dead:
					restart()
			KEY_Q:
				if paused or dead:
					get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			KEY_SPACE:
				if not paused:
					use_bomb()
