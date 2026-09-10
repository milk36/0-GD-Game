extends SceneTree
## 冒烟测试：实例化方块雄鹰场景，检查 MagicaVoxel 体素岛是否成功挂载
## 运行：godot --headless --path <项目> -s res://tools/vox/_smoke.gd


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/voxel_eagle.tscn")
	var inst: Node = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var world: Node = inst.get_node_or_null("World")
	if world == null:
		print("FAIL: 找不到 World 节点")
		quit(1)
		return
	var big := []
	for c in world.get_children():
		if c is MeshInstance3D:
			var a: AABB = (c as MeshInstance3D).mesh.get_aabb()
			if a.size.x > 5.0:
				big.append({"pos": c.position, "scale": c.scale, "aabb": a.size})
	print("World children=", world.get_children().size())
	print("体素大岛数量=", big.size())
	for b in big:
		print("  pos=", b["pos"], " scale=", b["scale"], " aabb_size=", b["aabb"])
	var used_import := ResourceLoader.exists("res://assets/vox/island_scene.vox")
	print("导入产物可用=", used_import)
	quit(0 if big.size() > 0 else 1)
