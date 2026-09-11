extends SceneTree
## 按游戏真实相机参数渲染，核对「实际观感 / 物体比例 / 认物」。
## 相机照抄 _build_env：正交 size 34，位置 (0,30,12)，看向原点。
##
## 用法：godot --path <项目> -s res://tools/vox/ingame_view.gd
## 输出：%TEMP%/vox_review/ingame_*.png

const OUT_DIR := "C:/Users/milk_36/AppData/Local/Temp/vox_review"

var vp: SubViewport
var cam: Camera3D
var game: Node


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/voxel_eagle.tscn").instantiate()
	get_root().add_child(game)
	game.visible = false
	await process_frame
	await process_frame
	_setup()
	await _shot_wide()
	await _shot_closeup()
	await _shot_enemies()
	print("DONE")
	quit(0)


func _setup() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)          # 先分配好尺寸，避免首次 resize 丢首帧
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(game.stage_def["sky"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(game.stage_def["ambient"])
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(game.stage_def["sun"])
	sun.light_energy = float(game.stage_def["sun_energy"])
	sun.rotation_degrees = Vector3(-52, -28, 0)
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.5
	cam.far = 300.0
	cam.size = 34.0
	vp.add_child(cam)                      # 必须先入树，look_at 依赖全局变换
	cam.position = Vector3(0, 30, 12)
	cam.look_at(Vector3.ZERO)
	cam.current = true


## 全景：把地貌与幸存者按游戏内真实比例摆开（1280×720 与游戏窗口一致）
func _shot_wide() -> void:
	var stage := Node3D.new()
	vp.add_child(stage)
	var items := [
		{"fn": "T_VOX", "pos": Vector3(-16, 0, 0)},
		{"fn": "T_ISLAND", "pos": Vector3(-6, 0, 0)},
		{"fn": "T_REEF", "pos": Vector3(2, 0.02, 0)},
		{"fn": "T_WRECK", "pos": Vector3(9, 0.08, 0)},
		{"fn": "SURV", "pos": Vector3(16, 0.5, 0)},
	]
	for it in items:
		var n: Node3D = _take(it["fn"])
		if n != null:
			n.position = it["pos"]
			stage.add_child(n)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save("ingame_wide.png")
	stage.queue_free()


## 特写：同一体素尺度下，沉船 vs 幸存者 并排（用于认物）
func _shot_closeup() -> void:
	var stage := Node3D.new()
	vp.add_child(stage)
	var wreck: Node3D = _take("T_WRECK")
	if wreck != null:
		(wreck as Node3D).position = Vector3(-4.5, 0.08, 0)
		stage.add_child(wreck)
	var surv: Node3D = _take("SURV")
	if surv != null:
		(surv as Node3D).position = Vector3(4.0, 0.5, 0)
		stage.add_child(surv)
	vp.size = Vector2i(900, 560)
	cam.size = 14.0
	cam.position = Vector3(0, 9, 11)
	cam.look_at(Vector3(0, 0.5, 0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save("ingame_closeup.png")
	stage.queue_free()


func _save(name: String) -> void:
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + name)
		print("saved ", name)
	else:
		print("NULL IMAGE ", name)


## 敌机在游戏尺度下的实际观感：与玩家机并排，核对体积 / 朝向 / 辨识度
func _shot_enemies() -> void:
	var stage := Node3D.new()
	vp.add_child(stage)
	vp.size = Vector2i(1280, 720)             # 回到与游戏窗口一致的尺度
	cam.size = 34.0
	cam.position = Vector3(0, 30, 12)
	cam.look_at(Vector3.ZERO)
	var ids := ["E1", "E2", "E3", "E4", "E5", "E6", "PLAYER"]
	var step := 7.5
	for i in ids.size():
		var n: Node3D = _take(ids[i])
		if n == null:
			continue
		var y := 4.3
		if ids[i] == "E1" or ids[i] == "E2":          # 地面单位：按 AABB 贴海面（节点已带 0.3 缩放）
			y = -n.mesh.get_aabb().position.y * game.ENEMY_SCALE - 0.15 if n is MeshInstance3D else 0.0
			if ids[i] == "E1":                         # 炮管转向玩家侧（游戏内由 look_at 完成）
				for c in n.get_children():
					if c is MeshInstance3D:
						(c as Node3D).rotation.y = PI
		elif ids[i] == "PLAYER":
			y = 4.5
		n.position = Vector3((i - (ids.size() - 1) * 0.5) * step, y, 0.0)
		stage.add_child(n)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save("ingame_enemies.png")
	stage.queue_free()


func _take(id: String) -> Node3D:
	var n: Node3D = null
	match id:
		"E1":
			n = _grab_enemy("E1", true)
		"E2", "E3", "E4", "E5", "E6":
			n = _grab_enemy(id, false)
		"T_ISLAND":
			n = game._make_island()
		"T_REEF":
			n = game._make_reef()
		"T_WRECK":
			n = game._make_wreck()
		"T_VOX":
			n = game._spawn_vox_decor()
		"SURV":
			game._spawn_survivor(0.0)
			var s: Dictionary = game.survivors[game.survivors.size() - 1]
			(s["ex"] as Node3D).visible = false   # 无叹号的常态；带叹号另见 asset_review
			n = s["n"]
		"PLAYER":
			n = game.player_mesh
	if n == null:
		return null
	var p := n.get_parent()
	if p != null:
		p.remove_child(n)
	n.rotation = Vector3.ZERO
	if id == "T_WRECK":
		var fl := 0.0
		for c in n.get_children():      # 火焰是子节点，保持其相对位置
			fl = 1.0
		n.position = Vector3.ZERO
	return n


## 借用游戏自身的生成函数取真实敌机节点（含 E1 炮头子树）
func _grab_enemy(type: String, ground: bool) -> Node3D:
	if ground:
		game._spawn_ground(type, 0.0)
	else:
		game._spawn_air(type, 0.0, 3, 0.0)
	return game.enemies[game.enemies.size() - 1]["n"]
