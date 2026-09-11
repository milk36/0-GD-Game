extends SceneTree
## 把任意场景按 1280×720 离屏渲染成 PNG，并打印节点统计（用于验收测试场景）。
## 注意：渲染必须带 GPU（不能加 --headless），会短暂开窗。
##
## 用法：godot --path <项目> -s res://tools/vox/scene_shot.gd
## 改 SCENE 即可拍别的场景。

const SCENE := "res://scenes/survivor_test.tscn"
const OUT_DIR := "C:/Users/milk_36/AppData/Local/Temp/vox_review"
const OUT_NAME := "survivor_test.png"
const CLOSEUP := false         # true = 用场景的"特写"机位（需场景实现 _apply_cam_mode）
const NO_SHADOW := false       # true = 关掉平行光阴影（排查黑影来源）
const DEMO_PROG := -1.0        # >=0 时调用场景 demo_rescue(prog) 并定格（如 0.55 = 起吊中途）

var vp: SubViewport


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)

	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FAIL: 载入失败 ", SCENE)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	vp.add_child(inst)
	await process_frame
	await process_frame

	if DEMO_PROG >= 0.0 and inst.has_method("demo_rescue"):
		inst.call("demo_rescue", DEMO_PROG)
	if NO_SHADOW and inst.get("sun") != null:
		(inst.get("sun") as DirectionalLight3D).shadow_enabled = false
		(inst.get("hud") as Label).text += "\n[无阴影]"
	if CLOSEUP and inst.has_method("_apply_cam"):
		inst.call("_apply_cam", true)
	await process_frame
	if DEMO_PROG >= 0.0:
		var s6 := inst.get_node_or_null("Survivor06")
		if s6 != null:
			print("Survivor06 pos=%s scale=%s visible=%s" % [str(s6.position), str(s6.scale), str(s6.visible)])
		var rp := inst.get_node_or_null("Player")
		if rp != null:
			print("Player pos=%s" % str(rp.position))
	_report(inst)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var suffix := "_close" if CLOSEUP else ("_rescue" if DEMO_PROG >= 0.0 else "")
	var out_name: String = OUT_NAME.replace(".png", suffix + ".png")
	if img != null:
		img.save_png(OUT_DIR + "/" + out_name)
		print("saved ", out_name, " ", img.get_size())
	else:
		print("NULL IMAGE（缺 GPU？）")
	quit(0)


func _report(root: Node) -> void:
	var survs := []
	_collect(root, survs)
	print("幸存者节点数 = ", survs.size())
	for n in survs:
		print("  %s pos=%s scale=%s 子节点=%d" % [n.name, str(n.position), str(n.scale), n.get_child_count()])
	var cam := _find_camera(root)
	if cam != null:
		print("相机：正交=%s size=%.1f pos=%s" % [cam.projection == Camera3D.PROJECTION_ORTHOGONAL, cam.size, str(cam.position)])


func _collect(n: Node, out: Array) -> void:
	# 用「带 Mark 子节点的 MeshInstance3D」当幸存者指纹（Godot 会给重名节点自动改名）
	if n is MeshInstance3D and n.get_node_or_null("Mark") != null:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _find_camera(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var r := _find_camera(c)
		if r != null:
			return r
	return null
