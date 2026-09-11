extends SceneTree
## 瓦片雄鹰验收工具：跑真实场景，打印布局/渲染诊断，并按三机位各拍一张 1280×720 PNG。
##
## 用法（必须带 GPU，不能加 --headless —— dummy 渲染器出不了内容，见 tools/vox/README §8）：
##     "…Godot…_console.exe" --path <项目> -s res://tools/tile_eagle/shot.gd
##
## 产出（res://tools/tile_eagle/）：
##     tile_cam68.png / tile_cam90.png / tile_camiso.png   三机位
##     tile_cam68_nocloud.png                              云层对照（C 键的 off 状态）
##     tile_cam68_noshadow.png                             阴影对照（F3 的 off 状态）
##     tile_cam68_nowave.png                               水面动感对照（V 键的 off 状态）
##     tile_combat.png                                     第 1 波炮台交火（固定步长空跑）
##     tile_elite.png                                      精英机取景（debug_spawn 定点摆拍）
## 打完自动退出；日志里的「布局校验和」用于验收「同种子逐位复现」。

const SCENE := "res://scenes/tile_eagle.tscn"
const OUT_DIR := "res://tools/tile_eagle"
const SETTLE := 12                     # 冻结后等几帧让渲染管线出完图
# M1 起场景里有战斗：出图前先**确定性地**空跑一段模拟（固定步长直接驱动 _process），
# 让第 1 波地面炮台走到玩家附近再冻结。这样截图里有敌机/弹幕，且每次出图完全一致。
const PREROLL_SEC := 13.5
const PREROLL_DT := 1.0 / 60.0
# 构图锚点：跳到第 21 绝对行时，4×4 主岛（记录行 15）正好落在屏幕中央。
# 公式：布局行 k 的屏幕行 j = k − abs_row + (VIS_ROWS−1)，行 z = (NEAR_ROWS − j)·4.8；
# 想让岛心（行 13.5）落在相机观察点 z=−3 → j≈5.6 → abs_row≈21。
const SEEK_ROW := 21
const SHOTS := [
	{"mode": 0, "name": "tile_cam68.png", "clouds": true},
	{"mode": 1, "name": "tile_cam90.png", "clouds": true},
	{"mode": 2, "name": "tile_camiso.png", "clouds": true},
	{"mode": 0, "name": "tile_cam68_nocloud.png", "clouds": false},
	{"mode": 0, "name": "tile_cam68_noshadow.png", "clouds": false, "shadow": false},
	# 水面顶点动感的唯一变量对照（V 键的 off 状态）：材质/网格/衰减全不动，只把 wave_amp 置 0
	{"mode": 0, "name": "tile_cam68_nowave.png", "clouds": false, "wave": false},
	# M2 要塞走廊（layout.gd 的手工精摆段，rows 34~47）：seek=45 让 4×4 要塞正好居中
	# （要塞远行 39 → 屏幕行 j = 39−45+13 = 7 → z = −9.6；近行 36 → z = +4.8，跨相机观察点）。
	# 14 行的精摆段塞不进一个 68° 视野（可见带只有 ~8 行），这张取「码头+要塞+翼塔」主组。
	{"mode": 0, "name": "tile_fort.png", "clouds": true, "seek": 45},
	# 战斗图放最后：它不跳行（跳行会把已生成的敌机和地貌错开），改为先确定性空跑一段，
	# 让第 1 波地面炮台走到玩家附近再冻结。
	{"mode": 0, "name": "tile_combat.png", "clouds": false, "combat": true, "seek": 0},
	# 精英取景图（M1 §16.2）：波次里的精英最早在 t=112s 才出场，靠空跑控制不住它们落在
	# 屏幕哪里 → 换成 debug_spawn 定点摆拍（生成路径与波次完全相同，只覆盖 z），
	# 再固定步长推 2.8 秒让它们开火、弹幕进画面。
	# 摆位两条经验：① x 要避开玩家主炮的火线（自机弹沿 x=0 直射 -z，摆在火线上会在预热
	# 期间被打爆，画面上直接少一架）；② 落点 z 用"出生 z + 2.8s × 实际航速"倒推。
	{"mode": 0, "name": "tile_elite.png", "clouds": false, "elite": true, "spawn": [
		["E6", -3.0, -32.0], ["E10", 5.0, -28.0], ["E5", -10.0, -24.0], ["E7", 10.0, -20.0],
	]},
	# 方舟战舰（M3）：debug_spawn 摆在中距，预热 2.8s 让它进完场（z→-14）并开一轮扇形。
	# 血条在 HUD 右上角（boss_info 非空即显示）。
	{"mode": 0, "name": "tile_boss.png", "clouds": false, "elite": true, "spawn": [
		["BOSS", 0.0, -30.0],
	]},
]

## 精英取景图的固定步长预热（秒）：只够它们开火 1~2 轮、且 < 第一波 t=6 → 画面里只有摆拍单位
const ELITE_SEC := 2.8

var vp: SubViewport


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
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
	_report(inst)
	var combat = inst.get("combat")
	if combat != null:
		(combat as Node).set("armor", 999)          # 出图期间别被打死（冻结帧才好看）

	for shot in SHOTS:
		inst.set("cam_mode", int(shot.mode))
		inst.set("clouds_on", bool(shot.clouds))
		(inst.get("sun") as DirectionalLight3D).shadow_enabled = bool(shot.get("shadow", true))
		inst.call("set_wave", bool(shot.get("wave", true)))
		if bool(shot.get("elite", false)):
			# 摆拍：先跳行复位，再定点投放精英单位，最后固定步长推 ELITE_SEC 秒。
			# 必须先 reset()：上一张图（战斗图）已经空跑过 13.5 秒，波次时钟还停在半路，
			# 不清场的话推 2.8 秒会正好撞上 t=16 的无人机波，画面里混进一堆非摆拍单位。
			inst.call("debug_seek", int(shot.get("seek", SEEK_ROW)))
			(combat as Node).call("reset")
			(combat as Node).set("armor", 999)
			(combat as Node).set("gun_on", false)   # 关主炮：否则持续弹束会在预热期把摆拍单位打爆
			inst.set("paused", false)
			inst.set_process(false)
			for sp in shot["spawn"]:
				(combat as Node).call("debug_spawn", String(sp[0]), float(sp[1]), float(sp[2]))
			for i in int(ELITE_SEC / PREROLL_DT):
				inst.call("_process", PREROLL_DT)
			inst.set_process(true)
			var al: Array = []
			for e in (combat as Node).get("enemies"):
				al.append("%s@(%.1f, %.1f, %.1f)" % [String(e["t"]),
						(e["n"] as Node3D).position.x, (e["n"] as Node3D).position.y,
						(e["n"] as Node3D).position.z])
			print("精英取景：敌机 %d（%s）  敌弹 %d  击落 %d"
					% [(combat as Node).call("enemy_count"), ", ".join(al),
						int(((combat as Node).get("eb") as MultiMeshInstance3D).get("count")),
						(combat as Node).get("kills")])
		elif bool(shot.get("combat", false)):
			# 先跳行把世界复位到确定状态（此时还没有敌机，不存在错位），再固定步长空跑。
			# 少了这一步，预热起点会随"引擎实时跑了多少帧"变化，出图就不逐像素可复现了。
			# 战斗图的跳行锚点单独给（"seek"）：要让第 1 波炮台落在 4×4 主岛上。
			inst.call("debug_seek", int(shot.get("seek", SEEK_ROW)))
			inst.set("paused", false)
			inst.set_process(false)                 # 关掉引擎驱动，按固定步长推进 → 完全确定
			for i in int(PREROLL_SEC / PREROLL_DT):
				inst.call("_process", PREROLL_DT)
			inst.set_process(true)
			print("预热 %.1fs：敌机 %d  敌弹 %d  击落 %d"
					% [PREROLL_SEC, (combat as Node).call("enemy_count"),
						int(((combat as Node).get("eb") as MultiMeshInstance3D).get("count")),
						(combat as Node).get("kills")])
		else:
			inst.call("debug_seek", int(shot.get("seek", SEEK_ROW)))   # 固定构图 + 复位玩家与云带
		inst.set("paused", true)                    # 冻结滚动，同机位截图逐像素可复现
		for i in SETTLE:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null:
			print("NULL IMAGE（缺 GPU？）")
		else:
			img.save_png(ProjectSettings.globalize_path(OUT_DIR) + "/" + str(shot.name))
			print("saved ", shot.name, " ", img.get_size())
	quit(0)


func _report(inst: Node) -> void:
	var layout = inst.get("layout")
	var sum := 0
	var per_kind := {}
	var row_cells := 0
	for r in range(layout.rows.size()):
		for cell in layout.rows[r]:
			row_cells += 1
			sum = (sum * 31 + hash(cell.tile + ":" + str(cell.col) + ":" + str(cell.rot))) & 0x7fffffff
			per_kind[cell.tile] = int(per_kind.get(cell.tile, 0)) + 1
	print("布局校验和 = ", sum, "   排布格数 = ", row_cells, "   种子 = ", layout.seed_val)
	var kinds := per_kind.keys()
	kinds.sort()
	for k in kinds:
		print("  %-13s × %d" % [k, per_kind[k]])
	var inst_count := 0
	for rs in (inst.get("row_slots") as Array):
		inst_count += (rs as Array).size()
	print("在场瓦片实例 = ", inst_count)
	print("玩家机 y = ", (inst.get("player") as Node3D).position.y,
			"   云层 y = ", (inst.get("clouds")[0] as Node3D).position.y)
	var cam := inst.get("cam") as Camera3D
	print("相机 size = ", cam.size, "  投影正交 = ", cam.projection == Camera3D.PROJECTION_ORTHOGONAL)
	print("HUD: ", (inst.get("hud") as Label).text.replace("\n", " | "))
