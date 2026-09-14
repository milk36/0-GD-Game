extends SceneTree
## 瓦片雄鹰：新敌人（E14 红零式 / E15 金零式 / E16 野牛气垫登陆艇）游戏内合影。
## 用法（必须带 GPU，不能加 --headless）：
##     "...Godot..._console.exe" --path <项目> -s res://tools/tile_eagle/shot_trio.gd
## 产出：res://tools/tile_eagle/tile_new_enemies.png

const SCENE := "res://scenes/tile_eagle.tscn"
const OUT_DIR := "res://tools/tile_eagle"
const SETTLE := 12
const ELITE_SEC := 2.8
const SEEK_ROW := 21

const SHOTS := [
	{
		"mode": 0, "name": "tile_new_enemies.png", "clouds": false, "elite": true,
		"hide_player": true, "preroll": 0.05, "seek": SEEK_ROW,
		# 红零式 -7、金零式 0 并排；野牛体型大、贴海面，放右侧并略靠近镜头
		"spawn": [["E14", -7.0, 8.0], ["E15", 0.0, 8.0], ["E16", 8.0, 5.0]],
	},
]

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
	var combat = inst.get("combat")
	if combat != null:
		(combat as Node).set("armor", 999)

	for shot in SHOTS:
		inst.set("cam_mode", int(shot.mode))
		inst.set("clouds_on", bool(shot.clouds))
		(inst.get("sun") as DirectionalLight3D).shadow_enabled = bool(shot.get("shadow", true))
		inst.call("set_wave", bool(shot.get("wave", true)))
		if bool(shot.get("elite", false)):
			inst.call("debug_seek", int(shot.get("seek", SEEK_ROW)))
			(combat as Node).call("reset")
			(combat as Node).set("armor", 999)
			(combat as Node).set("gun_on", false)
			inst.set("paused", false)
			inst.set_process(false)
			for sp in shot.get("spawn", []):
				(combat as Node).call("debug_spawn", String(sp[0]), float(sp[1]), float(sp[2]))
			if shot.has("turret_scale"):
				var k: float = float(shot["turret_scale"])
				for e in (combat as Node).get("enemies"):
					if String(e["t"]) != "E11":
						continue
					var ship: Node3D = e["n"]
					var ha: AABB = ship.mesh.get_aabb()
					var deck_y: float = ha.position.y + ha.size.y * 0.5
					for tk in ["t_f", "t_a"]:
						var ttn: Node3D = e[tk]
						var tb: AABB = ttn.mesh.get_aabb()
						ttn.scale = Vector3.ONE * k
						ttn.position.y = deck_y - tb.position.y * k - 0.3
			var sec: float = float(shot.get("preroll", ELITE_SEC))
			(inst.get("cam") as Camera3D).size = float(shot.get("cam_size", 34.0))
			if bool(shot.get("hide_player", false)):
				(inst.get("player") as Node3D).visible = false
			for i in int(sec / (1.0 / 60.0)):
				inst.call("_process", 1.0 / 60.0)
			var al: Array = []
			for e in (combat as Node).get("enemies"):
				al.append("%s@(%.1f, %.1f, %.1f)" % [String(e["t"]),
						(e["n"] as Node3D).position.x, (e["n"] as Node3D).position.y,
						(e["n"] as Node3D).position.z])
			print("新敌人取景：%s" % ", ".join(al))
		else:
			inst.call("debug_seek", int(shot.get("seek", SEEK_ROW)))
		inst.set("paused", true)
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
