extends SceneTree
## 体素资产视觉验收：调用游戏自身的生成函数取到「真实资产」，逐个离屏渲染成 PNG。
## 用于绕序/法线/材质/配色改动后的整体外观回归，比读代码推断可靠。
##
## 用法：
##   godot --path <项目> -s res://tools/vox/asset_review.gd
## 输出：C:/Users/milk_36/AppData/Local/Temp/vox_review/*.png（放在项目外，避免编辑器导入噪声）
##
## 两个机位：
##   play = 与游戏相机 (0,30,12) 同向，即玩家实际看到的样子（含右侧死黑面）
##   iso  = 3/4 斜俯视，从受光侧打光，看块面与层次

const OUT_DIR := "C:/Users/milk_36/AppData/Local/Temp/vox_review"
const VIEWS := {
	"play": Vector3(0.0, 0.93, 0.37),
	"iso": Vector3(-0.75, 0.62, 1.0),
}
const ASSETS := ["E1", "E2", "E3", "E4", "E5", "E6", "BOSS", "SURV", "PLAYER",
	"T_ISLAND", "T_REEF", "T_WRECK", "T_VOX", "ROW"]

var vp: SubViewport
var cam: Camera3D
var game: Node
var _acc := AABB()
var _has := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/voxel_eagle.tscn").instantiate()
	get_root().add_child(game)
	game.visible = false          # 游戏本体不渲染，只借用它的资产与环境配色
	await process_frame
	await process_frame
	_setup_viewport()

	for id in ASSETS:
		var node: Node3D = _take(id)
		if node == null:
			print("SKIP (生成失败): ", id)
			continue
		for vname in VIEWS:
			await _shoot(node, VIEWS[vname], "%s_%s.png" % [id, vname])
		node.queue_free()
	print("DONE")
	quit(0)


func _setup_viewport() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(560, 420)
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
	cam.near = 0.05
	cam.far = 600.0
	vp.add_child(cam)
	cam.current = true


## 取真实资产：直接调用游戏的生成函数，保证与运行时完全一致
func _take(id: String) -> Node3D:
	match id:
		"E1":
			return _detach(_grab_enemy("E1", true))
		"E2", "E3", "E4", "E5", "E6":
			return _detach(_grab_enemy(id, false))
		"BOSS":
			game._spawn_boss()
			return _detach(game.boss["n"])
		"SURV":
			game._spawn_survivor(0.0)
			var s: Dictionary = game.survivors[game.survivors.size() - 1]
			(s["ex"] as Node3D).visible = true   # 叹号默认隐藏，验收时打开看整体
			return _detach(s["n"])
		"PLAYER":
			return _detach(game.player_mesh)
		"T_ISLAND":
			return _detach(game._make_island())
		"T_REEF":
			return _detach(game._make_reef())
		"T_WRECK":
			return _detach(game._make_wreck())
		"T_VOX":
			return _detach(game._spawn_vox_decor())
		"ROW":
			return _enemy_row()
	return null


## 全家福：五类敌人 + Boss 一字排开，便于对比体积与轮廓
func _enemy_row() -> Node3D:
	var holder := Node3D.new()
	var ids := ["E1", "E2", "E3", "E4", "E5", "E6", "BOSS"]
	var step := 14.0
	for i in ids.size():
		var n: Node3D = null
		if ids[i] == "E1":
			n = _detach(_grab_enemy("E1", true))
		elif ids[i] == "BOSS":
			game._spawn_boss()
			n = _detach(game.boss["n"])
		else:
			n = _detach(_grab_enemy(ids[i], false))
		if n != null:
			n.position = Vector3((i - (ids.size() - 1) * 0.5) * step, 0.0, 0.0)
			holder.add_child(n)
	return holder


func _grab_enemy(type: String, ground: bool) -> Node3D:
	if ground:
		game._spawn_ground(type, 0.0)
	else:
		game._spawn_air(type, 0.0, 3, 0.0)
	var e: Dictionary = game.enemies[game.enemies.size() - 1]
	return e["n"]


func _detach(n: Node3D) -> Node3D:
	if n == null:
		return null
	var p := n.get_parent()
	if p != null:
		p.remove_child(n)
	n.position = Vector3.ZERO
	n.rotation = Vector3.ZERO
	return n


func _shoot(node: Node3D, view_dir: Vector3, out_name: String) -> void:
	_acc = AABB()
	_has = false
	_walk(node, Transform3D.IDENTITY)
	if not _has:
		push_warning("空资产：" + out_name)
		return
	var aabb := _acc
	node.position -= aabb.get_center()   # 资产居中到原点（节点 rotation 已归零）
	vp.add_child(node)

	var aspect := float(vp.size.x) / float(vp.size.y)
	var need_v: float = aabb.size.y * 1.5
	var need_h: float = maxf(aabb.size.x, aabb.size.z) * 1.5 / aspect
	cam.size = maxf(1.0, maxf(need_v, need_h))
	cam.position = view_dir.normalized() * (aabb.size.length() * 4.0 + 14.0)
	cam.look_at(Vector3.ZERO)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + out_name)
		print("saved %-18s aabb=%s" % [out_name, str(aabb.size)])
	else:
		print("NULL IMAGE ", out_name)
	vp.remove_child(node)


## 递归累加 AABB（含子节点，如炮台炮头、幸存者双臂）
func _walk(n: Node, xf: Transform3D) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var a: AABB = cur * mi.mesh.get_aabb()
			if _has:
				_acc = _acc.merge(a)
			else:
				_acc = a
				_has = true
	for c in n.get_children():
		_walk(c, cur)
