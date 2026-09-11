extends SceneTree
## M1 玩法最小集 headless 冒烟：把整张波次表跑完，检查生成 / 落岛 / 弹幕 / 击杀 / 受伤死亡。
## 用固定步长直接驱动 `_process`（不用等真实时间），因此结果确定、可复现。
##
## 用法："…Godot…_console.exe" --headless --path <项目> -s res://tools/tile_eagle/_play_smoke.gd
## 期望：波次全部刷出、地面单位落在陆地上（y ≈ 0.6）、有弹幕与击杀、无脚本报错；
##       最后单独走一遍"连中三弹 → 死亡 → 重开"，验证能死能重开。

const SCENE := "res://scenes/tile_eagle.tscn"
const DT := 1.0 / 60.0
const Layout = preload("res://scripts/tile_eagle/layout.gd")
## 必须 ≥ 波次表最后一组的时间（waves.gd 的精英段末组 t=232）——否则精英段根本没被跑到。
## 240 秒 × 60 帧 = 14400 步，headless 下十几秒即可跑完。
const SECONDS := 240.0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FAIL: 载入失败 ", SCENE)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	print("场景已就绪，开始推进…")
	inst.set_process(false)                     # 关掉引擎驱动，改由本脚本按固定步长推进

	var combat = inst.get("combat")
	if combat == null:
		print("FAIL: 没有 combat 节点")
		quit(1)
		return
	combat.set("armor", 999)                    # 先测"波次跑得完"，把死亡单独放到后面测
	var steps := int(SECONDS / DT)
	var peak_eb := 0
	var peak_enemies := 0
	var ground_y_min := 1e9
	var ground_y_max := -1e9
	var ground_x_min := 1e9
	var ground_x_max := -1e9
	var seen := {}                              # 型号 -> 出现过的次数采样（验证精英段真的刷了）
	var seen_layer := {}                        # 层名 -> 该层的单位被采样到的次数
	for i in steps:
		inst.call("_process", DT)
		if i % 600 == 0:
			print("  … %.0fs  敌机 %d  弹 %d  击落 %d"
					% [float(i) * DT, combat.call("enemy_count"),
						int((combat.get("eb") as MultiMeshInstance3D).get("count")), combat.get("kills")])
		peak_eb = maxi(peak_eb, int((combat.get("eb") as MultiMeshInstance3D).get("count")))
		peak_enemies = maxi(peak_enemies, combat.call("enemy_count"))
		for e in combat.get("enemies"):
			var d: Dictionary = e["def"]
			seen[String(e["t"])] = int(seen.get(String(e["t"]), 0)) + 1
			var ln := String(d["layer"])
			seen_layer[ln] = int(seen_layer.get(ln, 0)) + 1
			if ln == "GROUND":
				var n: MeshInstance3D = e["n"]
				# 量"脚底"而不是节点原点：体素网格以块键均值居中，原点 y 随资产不同而不同，
				# 只有 AABB 底面才代表它站在哪 —— 沙滩面 0.55（=0.60 减 0.05 微沉）才是"落在陆地上"
				var feet: float = n.position.y + n.mesh.get_aabb().position.y * 0.3
				ground_y_min = minf(ground_y_min, feet)
				ground_y_max = maxf(ground_y_max, feet)
				var x: float = n.position.x
				ground_x_min = minf(ground_x_min, x)
				ground_x_max = maxf(ground_x_max, x)

	print("=== 跑完 %.0f 秒（%d 帧）===" % [SECONDS, steps])
	print("  敌机峰值 = %d   敌弹峰值 = %d" % [peak_enemies, peak_eb])
	print("  击落 = %d   得分 = %d   拾星 = %d" % [combat.get("kills"), combat.get("score"), combat.get("star_cnt")])
	print("  地面单位脚底 y ∈ [%.2f, %.2f]（0.55 = 岛上沙滩面；0.85 = 要塞甲板/码头面；0.25 = 兜底落海面）"
			% [ground_y_min, ground_y_max])
	print("  地面单位落位 x ∈ [%.1f, %.1f]（期望在走廊 ±31 内）" % [ground_x_min, ground_x_max])
	print("  没赶上岛、兜底落海面的次数 = %d（期望远小于总生成数）" % combat.get("land_miss"))
	print("  场上星数 = %d" % int((combat.get("stars") as MultiMeshInstance3D).get("count")))
	var ks := seen.keys()
	ks.sort()
	var line := ""
	for k in ks:
		line += "%s=%d " % [k, seen[k]]
	print("  采样到的型号（帧计数，非生成数）：", line)
	var ls := seen_layer.keys()
	ls.sort()
	line = ""
	for k in ls:
		line += "%s=%d " % [k, seen_layer[k]]
	print("  分层采样：", line, "（LOW/HIGH 非 0 即说明精英段的分层落位生效）")

	# 受伤 → 死亡 → 重开
	combat.set("armor", 3)
	combat.set("invuln", 0.0)
	for k in 3:
		combat.call("hit_player")
		combat.set("invuln", 0.0)               # 跳过无敌期，连续受击
	print("  连中三弹后：装甲 = %d   dead = %s" % [combat.get("armor"), str(combat.get("dead"))])
	inst.call("_process", DT)
	combat.call("reset")
	print("  重开后：装甲 = %d   dead = %s   分数 = %d"
			% [combat.get("armor"), str(combat.get("dead")), combat.get("score")])

	# M2 验收项：精摆段（要塞走廊）必须与种子无关 —— 换种子重建布局后逐位一致。
	# 这是「设计师摆的走廊」的成立前提：R 键重摇只影响程序段，精摆段一动不动。
	var n_hand: int = Layout.HAND_SECTION.size()
	var before: Array = []
	var lay = inst.get("layout")
	for r in range(Layout.ROWS - n_hand, Layout.ROWS):
		before.append(str(lay.rows[r]))
	lay.set("seed_val", 987654321)
	lay.build()
	var same := true
	for i in n_hand:
		if str(lay.rows[Layout.ROWS - n_hand + i]) != before[i]:
			same = false
	print("  精摆段与种子无关：%s（%d 行逐位比对）"
			% ["一致 ✓" if same else "不一致 ✗（精摆段被种子改动了）", n_hand])
	quit(0)
