extends SceneTree
## 诊断：瓦片网格在瓦边缘有没有残留的侧立面（M0 踩坑 ④ 的专项检查）。
## 用法："…Godot…_console.exe" --headless --path <项目> -s res://tools/tile_eagle/_mesh_probe.gd

const Tiles = preload("res://scripts/tile_eagle/tiles.gd")
const TILE_HALF := 8.0   # 单格 16 体素的半宽


func _initialize() -> void:
	for id in ["sea_a", "sea_crest", "island_4x4", "island_2x2", "sandbar_2x2", "reef_s"]:
		_probe(id)
	quit(0)


func _probe(id: String) -> void:
	var td: Dictionary = Tiles.get_tile(id)
	var m: ArrayMesh = td.mesh
	if m == null:
		print(id, " 加载失败")
		return
	var half := float(int(td.span)) * TILE_HALF   # 瓦半宽（体素）
	var off: Vector3 = td.off
	# 水面层的顶面在**网格局部坐标**里的 y：水面层由 build_blocks(plate, TOP_ONLY) 单独烘焙，
	# 它的 center 是「只含水面层」的键均值（y=0）→ 顶面固定在 1.0。上层（沙/草）是另一次
	# build_blocks，center 是「只含上层」的键均值 → 两次烘焙的坐标系不同，合并后各组件的
	# 实际高度 = (局部 y + 该组 center 的修正)。这里只报 off，用于核对最终世界高度。
	print("=== %s  span=%d  off=%s  aabb=%s  面数=%d"
			% [id, int(td.span), str(off), str(m.get_aabb()), m.get_surface_count()])
	var all_min := Vector3(1e9, 1e9, 1e9)
	var all_max := Vector3(-1e9, -1e9, -1e9)
	var edge_side := 0
	var tris := 0
	var samples := []
	for s in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		tris += verts.size() / 3
		for i in verts.size():
			var v: Vector3 = verts[i]
			all_min = all_min.min(v)
			all_max = all_max.max(v)
			if absf(norms[i].y) < 0.5:           # 竖直面 = 侧立面
				# 网格以「键均值」为中心，瓦几何范围约 ±half
				if absf(v.x) > half - 1.5 or absf(v.z) > half - 1.5:
					edge_side += 1
					if samples.size() < 6:
						samples.append("%s n=%s" % [str(v), str(norms[i])])
	# 水面层顶面落在哪个世界高度：水面层是网格的最低面，AABB.min.y 就是它，
	# 世界高度 = (AABB.min.y + off.y) × 0.3。**全体瓦片必须都等于 0.30**
	# （= altitude.gd 的 SEA）——不等就说明锚点/分层烘焙又错位了，瓦界会露出台阶。
	print("    水面层顶面世界 y = %.4f（期望 0.3000）   三角面 %d   贴瓦边的侧立面顶点 = %d"
			% [(m.get_aabb().position.y + off.y) * 0.3, tris, edge_side])
	print("    顶点范围 %s .. %s" % [str(all_min), str(all_max)])
	if not samples.is_empty():
		print("    样例：", ", ".join(samples))
