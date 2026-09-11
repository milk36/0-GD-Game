extends SceneTree
## 临时校验：E1~E5 迁移后，敌人生成 + 更新循环（含 E1 炮头 look_at）无报错。
## 运行：godot --headless --path <项目> -s res://tools/vox/_check_enemies.gd


func _initialize() -> void:
	var inst: Node = load("res://scenes/voxel_eagle.tscn").instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	print("--- _meshes 加载情况 ---")
	for k in ["E1", "E1H", "E2", "E3", "E3R", "E4", "E5", "E6"]:
		var m: Mesh = inst._meshes[k]
		var a: AABB = m.get_aabb()
		print("  %-4s surfaces=%d aabb=%s" % [k, m.get_surface_count(), str(a.size)])

	print("--- 生成 + 更新循环 ---")
	inst._spawn_ground("E1", -8.0)
	inst._spawn_ground("E2", 8.0)
	inst._spawn_air("E3", -4.0, 3, 0.0)
	inst._spawn_air("E4", 0.0, 4, 0.0)
	inst._spawn_air("E5", 4.0, 5, 0.0)
	inst._spawn_air("E6", 8.0, 40, 0.0)
	for i in 30:
		inst._update_enemies(1.0 / 60.0)
		await process_frame
	print("  敌人数量=", inst.enemies.size())
	for e in inst.enemies:
		var n: Node3D = e["n"]
		print("  %-4s pos=%s" % [e["t"], str(n.position.snappedf(0.01))])
	var e1: Dictionary = inst.enemies[0]
	print("  E1 炮头旋转=", str((e1["head"] as Node3D).rotation.snappedf(0.01)))
	var e3: Dictionary = inst.enemies[2]
	var rotor: Node3D = e3.get("rotor")
	print("  E3 旋翼子节点=", rotor != null, " 旋转=", str(rotor.rotation.snappedf(0.01)) if rotor else "-",
		" 机身旋转=", str((e3["n"] as Node3D).rotation.snappedf(0.01)))
	print("OK")
	quit(0)
