extends SceneTree
## 体素资产量化审计：① 绕序（面是否朝外）② 法线硬边/平滑 ③ 光照溢出（配色是否过曝）
## 用法：godot --headless --path <项目> -s res://tools/vox/asset_audit.gd
##
## 朝外判定用的是严格方法：面中心沿法线内推 0.25 格应落在实心体素内、
## 外推 0.25 格应落在空格里。对轴对齐体素面这是充分判据。

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")


func _initialize() -> void:
	_winding_proof()
	_normal_style()
	await _light_budget()
	quit(0)


# ---------------------------------------------------------------- ① 绕序
func _winding_proof() -> void:
	var cases := {
		"单块": {Vector3i(0, 0, 0): Color.WHITE},
		"2×2×2实心": _box(Vector3i.ZERO, Vector3i(1, 1, 1)),
		"L形(凹面)": _l_shape(),
	}
	print("=== ① 绕序 / 面朝向（严格占据格判据）===")
	for name in cases:
		var blocks: Dictionary = cases[name]
		var mesh: ArrayMesh = VoxelModel.build_blocks(blocks)
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var total := vs.size() / 3
		var ctr := _mean_key(blocks)
		var geo_a := 0      # 几何法线 (v1-v0)x(v2-v0) 朝外
		var geo_b := 0      # 几何法线 (v0-v1)x(v0-v2) 朝外
		var normal_out := 0 # 存储法线朝外
		var normal_tracks_geo := 0
		for t in total:
			var v0 := vs[t * 3]
			var v1 := vs[t * 3 + 1]
			var v2 := vs[t * 3 + 2]
			var na := (v1 - v0).cross(v2 - v0).normalized()
			var c := (v0 + v1 + v2) / 3.0
			var n := ns[t * 3]
			if _is_outward(blocks, ctr, c, na):
				geo_a += 1
			if _is_outward(blocks, ctr, c, -na):
				geo_b += 1
			if _is_outward(blocks, ctr, c, n):
				normal_out += 1
			if absf(n.dot(na)) > 0.9 or absf(n.dot(-na)) > 0.9:
				normal_tracks_geo += 1
		print("  %-11s 三角面=%4d 几何朝向 (v1-v0)x(v2-v0) 朝外=%.0f%% / 反向朝外=%.0f%% | 存储法线朝外=%.0f%% | 法线与几何同轴=%.0f%%"
			% [name, total, 100.0 * geo_a / total, 100.0 * geo_b / total,
			   100.0 * normal_out / total, 100.0 * normal_tracks_geo / total])


## 面中心内推 0.25 格应落在某个实心体素内、外推 0.25 格应落在空处 → 该法线朝外。
## 用「最近体素键」判定而非四舍五入，避免网格居中偏移造成的假阴性。
func _mean_key(blocks: Dictionary) -> Vector3:
	var s := Vector3.ZERO
	for k in blocks:
		s += Vector3(k)
	return s / float(blocks.size())


func _inside(blocks: Dictionary, ctr: Vector3, p: Vector3) -> bool:
	for k in blocks:
		var v: Vector3 = Vector3(k) + Vector3(0.5, 0.5, 0.5) - ctr
		if absf(p.x - v.x) <= 0.51 and absf(p.y - v.y) <= 0.51 and absf(p.z - v.z) <= 0.51:
			return true
	return false


func _is_outward(blocks: Dictionary, ctr: Vector3, c: Vector3, n: Vector3) -> bool:
	return _inside(blocks, ctr, c - n * 0.25) and not _inside(blocks, ctr, c + n * 0.25)


func _box(a: Vector3i, b: Vector3i) -> Dictionary:
	var d := {}
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				d[Vector3i(x, y, z)] = Color.WHITE
	return d


func _l_shape() -> Dictionary:
	var d := _box(Vector3i.ZERO, Vector3i(1, 1, 1))
	d.erase(Vector3i(1, 1, 1))   # 挖掉一角 → 产生凹面，检验内面剔除与朝向
	return d


# ---------------------------------------------------------------- ② 法线风格
func _normal_style() -> void:
	print("\n=== ② 法线风格：硬边 or 平滑 ===")
	var blocks := {Vector3i(0, 0, 0): Color.WHITE}
	var mesh: ArrayMesh = VoxelModel.build_blocks(blocks)
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var flat_faces := 0
	var smooth_faces := 0
	var diag := 0
	for t in vs.size() / 3:
		var n0 := ns[t * 3]
		var same := n0.is_equal_approx(ns[t * 3 + 1]) and n0.is_equal_approx(ns[t * 3 + 2])
		if same:
			flat_faces += 1
		else:
			smooth_faces += 1
		if absf(n0.x) > 0.2 and absf(n0.y) > 0.2 and absf(n0.z) > 0.2:
			diag += 1
	print("  单块 6 面 = 12 三角面：整面法线一致(硬边)=%d  面内法线不一致(平滑)=%d  斜向法线顶点所在面=%d"
		% [flat_faces, smooth_faces, diag])
	var sample := ""
	for t in mini(3, vs.size() / 3):
		sample += "    面%d 三顶点法线: %s | %s | %s\n" % [t, str(ns[t * 3]), str(ns[t * 3 + 1]), str(ns[t * 3 + 2])]
	print(sample)


# ---------------------------------------------------------------- ③ 光照预算
func _light_budget() -> void:
	print("\n=== ③ 光照预算：各朝向面的合成光强（判定配色是否过曝）===")
	var game: Node = load("res://scenes/voxel_eagle.tscn").instantiate()
	get_root().add_child(game)
	game.visible = false
	await process_frame
	await process_frame
	# 覆盖三关配置
	var stage_file = load("res://scripts/voxel_eagle/stages.gd")
	var stages: Array = stage_file.STAGES
	var dirs := {
		"+Y顶面": Vector3.UP, "-Y底面": Vector3.DOWN,
		"+X右侧": Vector3.RIGHT, "-X左侧": Vector3.LEFT,
		"+Z正面": Vector3.BACK, "-Z背面": Vector3.FORWARD,
	}
	var pal := {
		"W 近白": Color("dfe6f5"), "C 浅粉": Color("ffb0c8"), "R/M 洋红": Color("ff2a6d"),
		"H 浅灰": Color("8a94aa"), "G 灰蓝": Color("6a7488"), "T 深板岩": Color("3a4254"),
		"S 沙黄": Color("8a7a52"), "D 暗红": Color("b03050"), "COL_WHITE": Color("f5f9ff"),
	}
	for s in stages:
		var e := float(s["sun_energy"])
		# Godot：albedo_color 与 light_color 都是 sRGB，引擎转线性后相乘，线性空间 >1 才截断
		var amb := Color(s["ambient"]).srgb_to_linear() * 1.0
		var sunc := Color(s["sun"]).srgb_to_linear() * e
		var L: Vector3 = game.sun.global_transform.basis.z  # 平行光沿 -Z 照射，+Z 指向光源
		print("--- 第%d关 %s：日光能量 %.2f   L=%s（线性空间计算）" % [s["id"], s["name"], e, str(L.snappedf(0.01))])
		var head := "      %-9s %-8s" % ["朝向", "N·L"]
		for k in pal:
			head += "%-10s" % k
		print(head)
		for dn in dirs:
			var ndotl: float = maxf(0.0, (dirs[dn] as Vector3).dot(L))
			var row := "      %-9s %-8s" % [dn, "%.2f" % ndotl]
			for k in pal:
				var alb: Color = pal[k]
				var lit := alb.srgb_to_linear() * (amb + sunc * ndotl)
				var mx: float = maxf(lit.r, maxf(lit.g, lit.b))
				row += "%-10s" % ("%.2f%s" % [mx, "*" if mx > 1.0 else ""])
			print(row)
		print("      （数值=线性空间最亮通道；* = 线性 >1 被截断）")
		break   # 三关数值接近，先看第一关
	_sun_candidates()
	_asset_stats(game)


## 日光方位候选：找出四个竖面都被照到的角度（当前 -28° 方位让 +X/-Z 面只剩环境光 → 死黑）
func _sun_candidates() -> void:
	print("\n=== ⑤ 日光方位候选（竖面 N·L，0 表示只吃环境光 → 近乎死黑）===")
	var cands := [Vector3(-52, -28, 0), Vector3(-50, -45, 0), Vector3(-55, -60, 0), Vector3(-45, -35, 0), Vector3(-60, -50, 0)]
	print("      %-18s %-7s %-7s %-7s %-7s %-7s %-7s" % ["旋转(俯仰,方位)", "+Y", "-Y", "+X", "-X", "+Z", "-Z"])
	for c in cands:
		var b := Basis.from_euler(Vector3(deg_to_rad(c.x), deg_to_rad(c.y), 0.0))
		var L := b.z
		var vals := []
		var ndotl := {}
		for k in ["+Y", "-Y", "+X", "-X", "+Z", "-Z"]:
			ndotl[k] = maxf(0.0, (dirs_map[k] as Vector3).dot(L))
		for k in ["+X", "-X", "+Z", "-Z"]:
			vals.append(ndotl[k])
		var mn: float = vals.min()
		print("      %-18s %-7.2f %-7.2f %-7.2f %-7.2f %-7.2f %-7.2f %.2f%s"
			% [str(c.snappedf(1.0)), ndotl["+Y"], ndotl["-Y"], ndotl["+X"], ndotl["-X"], ndotl["+Z"], ndotl["-Z"],
			   mn, "  ← 当前" if c.x == -52 and c.y == -28 else ""])
	print("      注意：单一平行光最多照亮相邻 2 个竖面，另 2 个竖面 N·L 必为 0 ——")
	print("      所以「死黑侧面」不能靠转方位解决，只能靠抬环境光（见下表）")
	_ambient_candidates()


## 环境光候选：让吃不到直射光的竖面从"死黑"回到可读
func _ambient_candidates() -> void:
	print("\n=== ⑥ 环境光强度候选：死黑竖面上各色显示值（sRGB）===")
	var amb := Color("223050").srgb_to_linear()      # 第 1 关环境色
	var sunc := Color("fff2e0").srgb_to_linear() * 1.3
	var L := Basis.from_euler(Vector3(deg_to_rad(-52), deg_to_rad(-28), 0)).z
	var pal := {"W 近白": Color("dfe6f5"), "H 浅灰": Color("8a94aa"), "G 灰蓝": Color("6a7488"), "R 洋红": Color("ff2a6d")}
	var top_ndotl: float = maxf(0.0, Vector3.UP.dot(L))
	print("      能量  每格=「竖面底色 / 顶面底色」")
	for k: float in [1.0, 1.8, 2.5, 3.5]:
		var row := "      %.1f   " % k
		var gray_lum := 0.0
		for name in pal:
			var alb: Color = (pal[name] as Color).srgb_to_linear()
			var dead := (alb * (amb * k)).linear_to_srgb()
			var top := (alb * (amb * k + sunc * top_ndotl)).linear_to_srgb()
			row += "%-9s %-18s" % [name, "#%s / #%s" % [dead.to_html(false), top.to_html(false)]]
			if name.begins_with("G"):
				gray_lum = dead.get_luminance()
		print(row + "  灰蓝竖面明度=%.2f" % gray_lum)


const dirs_map := {
	"+Y": Vector3.UP, "-Y": Vector3.DOWN,
	"+X": Vector3.RIGHT, "-X": Vector3.LEFT,
	"+Z": Vector3.BACK, "-Z": Vector3.FORWARD,
}


## 逐资产：三角面数、朝向面积分布（顶面占比决定过曝影响面）
func _asset_stats(game: Node) -> void:
	print("\n=== ④ 逐资产三角面与朝向分布 ===")
	var meshes := {}
	for k in game._meshes:
		meshes[k] = game._meshes[k]
	meshes["BOSS"] = load("res://scripts/voxel_eagle/vox_reader.gd").read_mesh("res://assets/vox/units/boss.vox")
	meshes["PLAYER"] = load("res://scripts/voxel_eagle/vox_reader.gd").read_mesh("res://assets/vox/units/player.vox")
	var VoxelModel = load("res://scripts/voxel_eagle/voxel_model.gd")
	var ind = game._make_island()
	meshes["岛屿"] = (ind as MeshInstance3D).mesh
	game.world.remove_child(ind)
	var rf = game._make_reef()
	meshes["暗礁"] = (rf as MeshInstance3D).mesh
	game.world.remove_child(rf)
	var wk = game._make_wreck()
	meshes["沉船"] = (wk as MeshInstance3D).mesh
	game.world.remove_child(wk)
	meshes["波浪块"] = (VoxelModel.build("WW", {"W": Color.WHITE}, 1))
	for k in meshes:
		var mesh: ArrayMesh = meshes[k]
		if mesh == null or mesh.get_surface_count() == 0:
			print("  %-8s <空>" % k)
			continue
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cnt := {"+Y": 0, "-Y": 0, "±X": 0, "±Z": 0, "斜向": 0}
		var smooth_faces := 0
		for t in vs.size() / 3:
			var n := ns[t * 3]
			if not (n.is_equal_approx(ns[t * 3 + 1]) and n.is_equal_approx(ns[t * 3 + 2])):
				smooth_faces += 1
			if absf(n.y) > 0.99:
				cnt["+Y" if n.y > 0 else "-Y"] += 1
			elif absf(n.x) > 0.99 or absf(n.z) > 0.99:
				cnt["±X" if absf(n.x) > 0.99 else "±Z"] += 1
			else:
				cnt["斜向"] += 1
		var tot := vs.size() / 3
		print("  %-8s 三角面=%5d  顶面=%.0f%% 底面=%.0f%% 侧面=%.0f%%  非轴法线(平滑)=%.0f%%"
			% [k, tot, 100.0 * cnt["+Y"] / tot, 100.0 * cnt["-Y"] / tot,
			   100.0 * (cnt["±X"] + cnt["±Z"]) / tot, 100.0 * smooth_faces / tot])


func _sort_directions() -> Array:
	return [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
