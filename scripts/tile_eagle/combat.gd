extends Node3D
## 瓦片雄鹰 M1 玩法最小集：自机弹 / 敌机 / 弹幕 / 击杀掉星 / 爆炸碎片 / 装甲与重开。
##
## 分工（design §8「M1 再拆 bullets/enemies」）：
## - 本文件只管"打"：弹池、敌机行为、XZ 判定、掉落、计分、死亡；
## - 场景与滚动在 game.gd；地貌与陆地查询在 tiles.gd / layout.gd；高度分层在 altitude.gd。
##
## ⚠️【高度是表现层】所有会打到玩家的弹都放在 AIR 层，与玩家同一平面——否则 68° 俯视下会
## 变成"弹从脚下掠过却把你打下来"。地面炮台的弹也升到 AIR，开火瞬间在炮口补一发枪焰把这段
## 高度差接上（altitude.gd 头注）。M2 要做分层弹道时，只改 `_enemy_bullet` 的 y 与判定。
##
## ⚠️【所有单位都挂在根节点下、自己走 z】瓦片走廊的滚动是"行回绕 + world.position.z 锯齿
## 补偿"（game.gd 文件头）：world 的子节点**拿不到**那份补偿，会被每 0.686 秒的锯齿拽回去
## 4.8 单位。所以单位一律挂根节点、按 `vz = 滚动速度 + 自身航速` 自行推进——
## 地面单位的 vz 就等于滚动速度，于是它们和脚下的岛严格同步、看不出接缝。
##
## ⚠️ 本节点必须是根场景的直接子节点、且根在原点：弹池坐标与 `global_position` 直接比对
## 依赖"根无偏移"。

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const VoxelPool = preload("res://scripts/voxel_eagle/pools.gd")
const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const Altitude = preload("res://scripts/tile_eagle/altitude.gd")
const Waves = preload("res://scripts/tile_eagle/waves.gd")
const SurvivorUnit = preload("res://scripts/voxel_eagle/survivor_unit.gd")
const RescueRing = preload("res://scripts/voxel_eagle/rescue_ring.gd")
const TileSave = preload("res://scripts/tile_eagle/tile_save.gd")

const BULLET_SPEED := 46.0          # 自机弹速（与方块雄鹰同值）
const ARMOR_MAX := 3
const INVULN := 1.5                 # 受击后无敌时长（与方块雄鹰同值）
const STAR_LIFE := 9.0
const MAGNET_R := 3.0               # 星星磁吸半径（方块雄鹰机库"磁铁"初始档）
const FIRE_INT := 0.115             # 自机主炮间隔（方块雄鹰 1 级主炮同值）
const AIR_SPAWN_Z := -46.0          # 空中单位出生 z（玩家在 z≈6，约 6 秒航程）
const RECYCLE_Z := 26.0             # 越过玩家身后这么多就回收
const COL_CYAN := Color("00f0ff")
const COL_PINK := Color("ff2a6d")
const COL_YELLOW := Color("ffe600")
const COL_WHITE := Color("f5f9ff")

## game.gd 注入
var host: Node3D                    # 场景根：读 player / scroll_spd / layout
var land_spot: Callable             # (float x_target) -> Vector3：岛上岸线落点（世界坐标）；INF = 没有陆地

var rope: MeshInstance3D            # 营救绳索（幸存者举手 → 玩家）
var ring: MeshInstance3D            # 机腹营救进度圈（RescueRing）
var _ring_flash := 0.0              # 救起后满圈保留的闪烁时间
var pb: VoxelPool                   # 自机弹
var eb: VoxelPool                   # 敌弹
var stars: VoxelPool                # 掉落星星
var fx: VoxelPool                   # 碎片 / 枪焰 / 命中闪光
var enemies: Array = []             # [{n, t, def, hp, ...}]（地面 + 空中）

var score := 0
var armor := ARMOR_MAX
var star_cnt := 0
var kills := 0
var land_miss := 0                  # 地面单位"等不到岛、兜底落海"的次数（观测指标）
var _pending: Array = []            # 等陆地落点的地面单位队列（见 _spawn 注释）
var invuln := 0.0
var dead := false
var gun_on := true                   # 自机主炮开关（出图取景用：摆拍时关掉，免得预热期把摆拍单位打爆）
var shake := 0.0                    # 受击镜头抖动残量（game.gd 读）
var script_t := 0.0                 # 关卡脚本时钟
var _wave_i := 0
var _fire_cd := 0.0
var _meshes := {}
var _mat: Material                  # 单位受光材质（全场共享一份）
var _rng := RandomNumberGenerator.new()

# ---- M3：幸存者救援 ----
var survivors: Array = []           # {n, ex, arm_l, arm_r, roping, prog, anchor_y}
var rescued := 0
var _surv_t := 8.0                  # 下一名幸存者的出现时刻（script_t 时钟）
## 幸存者出现节奏：比敌机组松得多——它是「飞过去顺手救」的目标，不是压力源。
const SURVIVOR_EVERY := 16.0
## 方舟悬停位（进场终点）。按 68° 正交投影量出来的：再远会顶进画面上缘的 HUD。
const BOSS_HOLD_Z := -9.0
# ---- M3：方舟 Boss ----
var boss_kills := 0
var _laser := {"st": 0, "t": 0.0, "org": Vector3.ZERO, "dir": Vector3.FORWARD, "len": 60.0}
var _laser_warn: MeshInstance3D
var _laser_beam: MeshInstance3D
var _boss_mat: StandardMaterial3D   # 阶段切换时泛红（毁伤外观）
# ---- M3：结算与存档 ----
var best := 0                       # 历史最高分（setup 时读档）
var new_best := false
var saved := false                  # 本局是否已落盘过（Boss 击破即存一次，死亡再补存）
var _banked_bk := 0                 # 已入账的方舟击破数（finalize 幂等：只补差额，避免重复计数）
var _banked_resc := 0               # 已入账的救援数（同上）
var _t := 0.0                       # 动画时钟（挥手 / 叹号浮动）


func setup() -> void:
	name = "Combat"
	_rng.seed = host.layout.seed_val
	_mat = VoxelModel.shaded_material()
	_boss_mat = VoxelModel.shaded_material()
	# 弹/星/碎片用无光照顶点色（高饱和即霓虹感，不依赖 Bloom）
	var un := VoxelModel.unshaded_material()
	pb = _mk_pool(96, un)
	eb = _mk_pool(512, un)
	stars = _mk_pool(256, un)
	fx = _mk_pool(320, un)
	for k in ["E1", "E1H", "E2", "E3", "E3R", "E4",
			"E5", "E6", "E7", "E7R", "E8", "E9", "E10", "boss"]:
		_meshes[k] = VoxReader.read_mesh("res://assets/vox/units/%s.vox" % k)
	# 营救件：绳索（细长盒，按目标距离缩放 z）+ 机腹营救进度圈（挂在玩家机上）
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = SurvivorUnit.ROPE_COLOR
	rope = MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(0.12, 0.12, 1.0)
	rbox.material = rm
	rope.mesh = rbox
	rope.visible = false
	rope.cast_shadow = 0
	add_child(rope)
	ring = RescueRing.build()
	ring.visible = false
	host.player.add_child(ring)
	best = int(TileSave.load_data().get("best", 0))


func _mk_pool(n: int, mat: Material) -> VoxelPool:
	var p := VoxelPool.new()
	add_child(p)
	p.setup(n, mat)
	return p


## 场上敌机数（HUD 用）
func enemy_count() -> int:
	return enemies.size()


## 重开：清场 + 复位计分（走廊本身不用重置）
func reset() -> void:
	for e in enemies:
		(e["n"] as Node).queue_free()
	enemies.clear()
	for s in survivors:
		(s["n"] as Node).queue_free()
	survivors.clear()
	pb.clear()
	eb.clear()
	stars.clear()
	fx.clear()
	score = 0
	armor = ARMOR_MAX
	star_cnt = 0
	kills = 0
	land_miss = 0
	_pending.clear()
	invuln = 0.0
	dead = false
	shake = 0.0
	script_t = 0.0
	_wave_i = 0
	_fire_cd = 0.0
	gun_on = true
	# M3：救援 / Boss 计数归零（best 保留——历史最高分跨局有效）
	rescued = 0
	boss_kills = 0
	new_best = false
	saved = false
	_banked_bk = 0
	_banked_resc = 0
	_surv_t = SURVIVOR_EVERY
	rope.visible = false
	ring.visible = false
	_ring_flash = 0.0
	_laser["st"] = 0
	if _laser_warn != null:
		_laser_warn.visible = false
		_laser_beam.visible = false


# ================= 主循环 =================

func update(delta: float) -> void:
	_t += delta
	if dead:
		_update_bullets(delta)          # 死亡后让残弹飞完，画面不会瞬间定格
		_update_stars(delta)
		_update_laser(delta)            # 激光同理：否则预警线/光束最多冻结 0.8s 在结算画面下
		return
	invuln = maxf(invuln - delta, 0.0)
	shake = maxf(shake - delta * 2.0, 0.0)
	_update_script(delta)
	_update_pending(delta)
	_update_player_gun(delta)
	_update_enemies(delta)
	_update_bullets(delta)
	_update_stars(delta)
	_update_survivors(delta)
	_spawn_survivors_tick(delta)
	_update_laser(delta)


## 波次脚本：到点整组刷出；表跑完往回退一个周期并从头循环（走廊无尽 → 波次也无尽）
func _update_script(delta: float) -> void:
	script_t += delta
	while _wave_i < Waves.WAVES.size() and script_t >= float(Waves.WAVES[_wave_i]["t"]):
		for ent in Waves.WAVES[_wave_i]["spawn"]:
			_spawn(ent)
		_wave_i += 1
	if _wave_i >= Waves.WAVES.size():
		script_t = 0.0
		_wave_i = 0


## 刷一个单位。地面单位要落在岛上，而「前方有岛」只在每个 48 行周期里的一段时间成立
## （4 张超级瓦 × 11 行窗口 → 约七成时间有岛）。直接落海会让岛变成纯背景板，
## 所以这里先**排队等岛**：每 0.25 秒问一次，最多等 LAND_WAIT_MAX 秒；
## 等不到才按方块雄鹰的原行为兜底落海面（并计入 land_miss 观测指标）。
const LAND_RETRY := 0.25
const LAND_WAIT_MAX := 6.0

func _spawn(ent: Dictionary) -> void:
	var t: String = ent["t"]
	var x: float = clampf(float(ent["x"]), -13.0, 13.0)
	if t == "SURVIVOR":                       # M3：幸存者也走「排队等陆」这条链
		var sp := _ask_land(x)
		if sp == Vector3.INF:
			_pending.append({"t": t, "x": x, "wait": 0.0, "try": LAND_RETRY, "surv": true})
			return
		_spawn_survivor(sp)
		return
	if String(Waves.get_enemy(t)["layer"]) == "GROUND":
		var lp := _ask_land(x)
		if lp == Vector3.INF:
			_pending.append({"t": t, "x": x, "wait": 0.0, "try": LAND_RETRY})
			return
		_spawn_ground(t, lp)
	else:
		_spawn_air(t, x, float(ent.get("vx", 0.0)))


func _ask_land(x: float) -> Vector3:
	if not land_spot.is_valid():
		return Vector3.INF
	return land_spot.call(x)


## 落位队列：等到岛就补刷；超时兜底落海
func _update_pending(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		var q: Dictionary = _pending[i]
		q["wait"] = float(q["wait"]) + delta
		q["try"] = float(q["try"]) - delta
		if float(q["try"]) <= 0.0:
			q["try"] = LAND_RETRY
			var lp := _ask_land(float(q["x"]))
			if lp != Vector3.INF:
				if bool(q.get("surv", false)):
					_spawn_survivor(lp)
				else:
					_spawn_ground(String(q["t"]), lp)
				_pending.remove_at(i)
				continue
		if float(q["wait"]) > LAND_WAIT_MAX:
			if bool(q.get("surv", false)):
				pass                        # 幸存者没有「兜底落海」——等不到就静默放弃这一名
			else:
				land_miss += 1
				_spawn_ground(String(q["t"]), Vector3(float(q["x"]), Altitude.GROUND, AIR_SPAWN_Z))
			_pending.remove_at(i)
			continue
		i += 1


## 幸存者投放节拍：到点往陆上放一名；放不下（前方暂时没有岛/要塞）就排队等。
## 幸存者没有兜底落海——空海面上一个挥手的幸存者读不出「遇难」，宁可这一轮不出。
func _spawn_survivors_tick(delta: float) -> void:
	_surv_t -= delta
	if _surv_t > 0.0:
		return
	_surv_t = SURVIVOR_EVERY
	_spawn({"t": "SURVIVOR", "x": _rng.randf_range(-10.0, 10.0)})


func _spawn_survivor(p: Vector3) -> void:
	var parts := SurvivorUnit.build()
	var n: Node3D = parts["n"]
	add_child(n)
	# 与地面单位同一条贴地规则：AABB 底面坐到落点上（mesh 以键均值居中，原点在半高）
	var aabb: AABB = n.mesh.get_aabb()
	n.position = Vector3(p.x, p.y - aabb.position.y * SurvivorUnit.SCALE, p.z)
	survivors.append({
		"n": n, "ex": parts["ex"], "arm_l": parts["arm_l"], "arm_r": parts["arm_r"],
		"roping": false, "prog": 0.0, "anchor_y": n.position.y,
	})
	host.hint("飞到幸存者上方悬停即可施救", 3.5)


## 幸存者：随地貌滚动；玩家悬停在 XZ 半径内开始起吊，离开范围绳索收回（不惩罚）。
## 交互模型与方块雄鹰逐参数一致（SurvivorUnit 的常量两边共用同一份定义）。
func _update_survivors(delta: float) -> void:
	var ring_prog := -1.0                 # <0 = 本帧无营救，需隐藏进度圈
	var i := 0
	while i < survivors.size():
		var s: Dictionary = survivors[i]
		var n: Node3D = s["n"]
		n.position.z += host.scroll_spd * delta       # 与脚下的岛严格同步（combat.gd 文件头注）
		var gp := n.global_position
		if gp.z > RECYCLE_Z:                          # 滚出屏幕 = 错过
			n.queue_free()
			survivors.remove_at(i)
			continue
		var pp: Vector3 = host.player.position
		var d := Vector2(gp.x - pp.x, gp.z - pp.z).length()
		var ex: MeshInstance3D = s["ex"]
		ex.visible = d < 8.0 and not bool(s["roping"])
		SurvivorUnit.mark_bob(ex, _t)
		SurvivorUnit.pose(s["arm_l"], s["arm_r"], _t, bool(s["roping"]))
		if bool(s["roping"]):
			if d > SurvivorUnit.RESCUE_LEAVE or dead:
				s["roping"] = false
				s["prog"] = 0.0
				SurvivorUnit.reset_rescue(n, float(s["anchor_y"]))
				rope.visible = false
			else:
				# 停止随地面滚动，原地等玩家悬停拉起（否则 0.6 秒内就被拽出半径）
				n.position.z -= host.scroll_spd * delta
				s["prog"] = float(s["prog"]) + delta / SurvivorUnit.RESCUE_TIME
				if SurvivorUnit.apply_rescue_progress(n, float(s["prog"]), float(s["anchor_y"])):
					rescued += 1
					score += 1000
					SFX.play("eagle_rescue")
					_burst(gp, COL_WHITE, 10)
					rope.visible = false
					ring_prog = 1.0
					_ring_flash = RescueRing.FLASH_TIME
					n.queue_free()
					survivors.remove_at(i)
					continue
				ring_prog = float(s["prog"])
				_rope_pose(gp)
		else:
			if d < SurvivorUnit.RESCUE_TRIGGER and not dead:
				s["roping"] = true
				s["prog"] = 0.0
				ring_prog = 0.0
		i += 1
	_update_ring(ring_prog, delta)


func _rope_pose(sur_gp: Vector3) -> void:
	var rp := SurvivorUnit.rope_pose(sur_gp, host.player.position)
	rope.global_transform = rp["xf"]
	rope.scale = Vector3(1, 1, float(rp["len"]))


## 进度圈刷新：营救中实时填充；救起后保留 FLASH_TIME 显示满圈；其余时间隐藏
func _update_ring(prog: float, delta: float) -> void:
	if ring == null:
		return
	if prog >= 0.0:
		ring.visible = true
	elif _ring_flash > 0.0:
		_ring_flash -= delta
		prog = 1.0
		if _ring_flash <= 0.0:
			ring.visible = false
			return
	else:
		ring.visible = false
		return
	RescueRing.aim(ring, host.cam, host.player.global_position)
	RescueRing.set_progress(ring, clampf(prog, 0.0, 1.0))


## 自机主炮：与方块雄鹰 1 级主炮同参数（单列 / 间隔 0.115s）；M1 不带升级线
func _update_player_gun(delta: float) -> void:
	if not gun_on:
		return
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	_fire_cd = FIRE_INT
	var p: Vector3 = host.player.position
	pb.spawn(p + Vector3(0, 0.2, -3.0), Vector3(0, 0, -BULLET_SPEED), COL_CYAN, 0.42, 1.4)
	SFX.play("eagle_shot", -8.0)


# ================= 单位生成 =================

func _new_unit_node(vox: String, def: Dictionary = {}) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = _meshes[vox]
	# Boss 用 0.5（waves.gd 的 "scale" 字段），其余全表 0.3 —— 与方块雄鹰同值
	n.scale = Vector3.ONE * float(def.get("scale", Waves.SCALE))
	# Boss 用独立材质：阶段切换时整体泛红做「毁伤外观」（共享材质会染红全场）
	n.material_override = _boss_mat if vox == "boss" else _mat
	return n


func _spawn_ground(type: String, p: Vector3) -> void:
	var def := Waves.get_enemy(type)
	var n := _new_unit_node(def["vox"])
	add_child(n)
	# 体素网格以块整数键均值居中（键与几何中心差半格）→ 按 AABB 底面贴地，再微沉 0.05 防浮空缝
	n.position = Vector3(p.x, p.y - n.mesh.get_aabb().position.y * Waves.SCALE - 0.05, p.z)
	var e := {
		"n": n, "t": type, "def": def, "hp": int(def["hp"]),
		"ft": _rng.randf_range(0.9, 1.8), "age": 0.0,
		"vz": host.scroll_spd, "x0": p.x,
	}
	if def.has("head"):   # 炮台炮头：按两者 AABB 反推，使炮头底面正好落在底座顶面（改模型高度不必改代码）
		var head := _new_unit_node(def["head"])
		head.position = Vector3(0, n.mesh.get_aabb().end.y - head.mesh.get_aabb().position.y, 0)
		n.add_child(head)
		e["head"] = head
	enemies.append(e)


func _spawn_air(type: String, x: float, vx: float) -> void:
	var def := Waves.get_enemy(type)
	var n := _new_unit_node(def["vox"], def)
	add_child(n)
	# 高度只认 def.layer（altitude.gd::of）——M1 的 LOW / HIGH 层就是靠这一行生效的
	n.position = Vector3(x, Altitude.of(String(def["layer"])), AIR_SPAWN_Z)
	# hold=true（Boss）：vz 归零 → 与玩家相对静止。Boss 战是定点的，跟着走廊滚就打不成了
	var vz: float = host.scroll_spd + float(def.get("vz", 3.0))
	if bool(def.get("hold", false)):
		vz = 0.0
	var e := {
		"n": n, "t": type, "def": def, "hp": int(def["hp"]),
		"ft": _rng.randf_range(0.7, 1.5), "age": 0.0, "mode": 0,
		"vx": vx, "vz": vz, "x0": x,
		# Boss 专属状态（其它单位读不到这些键）
		"entering": type == "BOSS", "phase": 1, "act_t": 1.6, "burst_left": 0, "burst_t": 0.0,
		"add_t": 4.0, "laser_t": 3.0, "sp_t": 0.0, "spiral_a": 0.0,
	}
	if def.has("rotor"):   # 旋翼层只转自己：机身朝向稳定，旋翼转得快也读得出机型
		var rotor := _new_unit_node(def["rotor"])
		rotor.position = Vector3(0, n.mesh.get_aabb().end.y - rotor.mesh.get_aabb().position.y, 0)
		n.add_child(rotor)
		e["rotor"] = rotor
	enemies.append(e)


## 出图用（tools/tile_eagle/shot.gd）：在指定 (x, z) 直接摆一个单位，走**与波次完全相同的
## 生成路径**（同一套 def / 挂件 / 高度层），只覆盖 z。存在的理由是构图：精英单位最早在
## t=112s 才出场，靠"空跑 112 秒"根本控制不住它在屏幕上的落点（世界在这段时间里滚了 800 多
## 单位），取景图只能摆拍。行为验证交给 `_play_smoke.gd`（跑真波次）。
## 地面单位不吃 z（它的 z 由滚动速度决定、且必须落在岛的岸线上）→ 直接退化成按波次刷。
func debug_spawn(t: String, x: float, z: float) -> void:
	var def := Waves.get_enemy(t)
	if String(def["layer"]) == "GROUND":
		_spawn({"t": t, "x": x})
		return
	_spawn_air(t, x, 0.0)
	if enemies.is_empty():
		return
	var e: Dictionary = enemies[enemies.size() - 1]
	if String(e["t"]) == t:
		(e["n"] as Node3D).position.z = z


# ================= 敌机行为 =================

func _update_enemies(delta: float) -> void:
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		e["age"] = float(e["age"]) + delta
		var n: Node3D = e["n"]
		# 统一的前进：vz 已含滚动速度，地面单位的 vz 就等于滚动速度（见文件头注）
		n.position.z += float(e["vz"]) * delta
		var gp := n.global_position
		if float(e["age"]) > 2.0 and (gp.z > RECYCLE_Z or gp.z < -110.0):
			n.queue_free()
			enemies.remove_at(i)
			continue
		_tick_unit(e, n, gp, delta)
		i += 1


func _tick_unit(e: Dictionary, n: Node3D, gp: Vector3, delta: float) -> void:
	var def: Dictionary = e["def"]
	match String(def["beh"]):
		"turret":
			# 炮台：炮头锁玩家，进入射程后定点点射
			var head: Node3D = e["head"]
			head.look_at(Vector3(host.player.position.x, head.global_position.y, host.player.position.z))
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				var from: Vector3 = head.global_position + Vector3(0, 1.0, 0)
				_bridge(def, from)
				_fire_aimed(from, def)
		"ring":
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_bridge(def, gp + Vector3(0, 1.0, 0))
				_fire_ring(gp, def, float(e["age"]))
		"drift":
			n.position.x += float(e["vx"]) * delta
			var rotor: Node3D = e.get("rotor")
			if rotor != null:
				rotor.rotate_y(delta * 14.0)
		"weave":
			n.position.x = float(e["x0"]) + sin(float(e["age"]) * 2.0) * 1.5
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_fire_aimed(gp, def)
		# ---- 精英段（M1 §16.2）。横向位移一律 clamp 到走廊 ±13：飞出走廊就再也打不到，
		#      玩家只能干看着（原作 E7/E5 的同类分支也是这么夹的）。
		"strafe":
			# 巡洋机：大幅横移扫场，5 发扇形压制
			n.position.x = clampf(float(e["x0"]) + sin(float(e["age"]) * 1.35) * 7.0, -13.0, 13.0)
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_fire_aimed(n.global_position, def)
		"heli":
			# 武装直升机：正弦侧移 + 主旋翼独立旋转，双管短点射
			n.position.x = clampf(float(e["x0"]) + sin(float(e["age"]) * 1.1) * 5.0, -13.0, 13.0)
			var hr: Node3D = e.get("rotor")
			if hr != null:
				hr.rotate_y(delta * 12.0)
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_bridge(def, n.global_position)
				_fire_aimed(n.global_position, def)
		"bomber":
			# 飞翼轰炸机：直压 + 定期向四周撒慢速炸弹（环形，弹速刻意慢）
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_bridge(def, n.global_position)
				_fire_ring(n.global_position, def, float(e["age"]))
		"raider":
			# 双体炮艇：LOW 层掠海冲撞，前向点射
			n.position.x += float(e["vx"]) * delta
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				_bridge(def, n.global_position)
				_fire_aimed(n.global_position, def)
		"elite":
			# 精英炮舰：缓推 + 微幅横移；hp 掉到 40% 以下加速逃逸（与原作同手法）
			var boost := float(def.get("flee", 6.0)) if int(e["hp"]) * 5 < int(def["hp"]) * 2 else 0.0
			n.position.z += boost * delta
			n.position.x = clampf(float(e["x0"]) + sin(float(e["age"]) * 0.7) * 3.0, -13.0, 13.0)
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				e["mode"] = 1 - int(e["mode"])
				_bridge(def, n.global_position)
				if int(e["mode"]) == 1:
					_fire_ring(n.global_position, def, float(e["age"]),
							int(def.get("ring_n", 12)), float(def.get("ring_spd", 6.0)))
				else:
					_fire_aimed(n.global_position, def)
		"fortress":
			# 浮空盾堡：小 boss 级 —— 极缓推进 + 微幅横移，环形 / 自机狙交替
			n.position.x = clampf(float(e["x0"]) + sin(float(e["age"]) * 0.5) * 2.0, -13.0, 13.0)
			if _in_range(gp, def) and _cd_tick(e, def, delta):
				e["mode"] = 1 - int(e["mode"])
				_bridge(def, n.global_position)
				if int(e["mode"]) == 1:
					_fire_ring(n.global_position, def, float(e["age"]),
							int(def.get("ring_n", 12)), float(def.get("ring_spd", 6.0)))
				else:
					_fire_aimed(n.global_position, def)
		"boss":
			_update_boss(e, n, delta)


## 开火节拍：按 def.cd 倒计时，到点返回 true 并重置
func _cd_tick(e: Dictionary, def: Dictionary, delta: float) -> bool:
	e["ft"] = float(e["ft"]) - delta
	if float(e["ft"]) > 0.0:
		return false
	e["ft"] = float(def["cd"])
	return true


## 是否进入开火的前后区间（range_z 缺省 = 全程；口径与方块雄鹰一致）
func _in_range(gp: Vector3, def: Dictionary) -> bool:
	if not def.has("range_z"):
		return true
	var r: Vector2 = def["range_z"]
	return gp.z > r.x and gp.z < r.y


# ================= 弹幕 =================

## 敌弹：统一放在 AIR 层（见文件头注）。白芯 + 粉壳提升正交俯视下的可读性。
func _enemy_bullet(p: Vector3, v: Vector3, col: Color) -> void:
	var q := Vector3(p.x, Altitude.AIR, p.z)
	eb.spawn(q, v, col, 0.62, 8.0)
	eb.spawn(q, v, COL_WHITE, 0.3, 8.0)


## 自机狙：以玩家方位角为基准，n 发在 spread 度内均匀散布（n=1 即单发直射）
## n/spread/spd 传 -1 = 按 def 表取值（精英单位的"混合弹幕"才需要显式覆盖）
func _fire_aimed(from: Vector3, def: Dictionary,
		n: int = -1, spread: float = -1.0, spd: float = -1.0) -> void:
	var to_p: Vector3 = host.player.position - from
	to_p.y = 0.0
	var base := atan2(to_p.x, -to_p.z)
	if n < 0:
		n = int(def.get("n", 1))
	if spread < 0.0:
		spread = float(def.get("spread", 0.0))
	if spd < 0.0:
		spd = float(def.get("bspeed", 7.0))
	for k in n:
		var off := 0.0 if n == 1 else deg_to_rad(spread) * (float(k) / float(n - 1) - 0.5)
		var a := base + off
		_enemy_bullet(from, Vector3(sin(a) * spd, 0.0, -cos(a) * spd), COL_PINK)


## 环形弹幕：n 发均分一圈，相位随存活时间缓慢旋转
func _fire_ring(from: Vector3, def: Dictionary, phase: float,
		n: int = -1, spd: float = -1.0) -> void:
	if n < 0:
		n = int(def.get("n", 12))
	if spd < 0.0:
		spd = float(def.get("bspeed", 6.0))
	for k in n:
		var a := TAU * float(k) / float(n) + phase
		_enemy_bullet(from, Vector3(sin(a) * spd, 0.0, cos(a) * spd), COL_PINK)


# ================= 方舟 Boss（M3） =================

func boss_info() -> Dictionary:
	"""HUD 血条用：{} = 场上没有（或还没进完场）。"""
	for e in enemies:
		if String(e["t"]) == "BOSS":
			return {"hp": int(e["hp"]), "hp_max": int(e["def"]["hp"]),
					"entering": bool(e["entering"])}
	return {}


## 三阶段（与方块雄鹰同构，弹幕量级按本作波次表折算）：
##   P1 hp>66%  5 向扇形 ×3 波 ↔ 自机狙 3 连交替
##   P2 hp>33%  无人机增援 + 横扫激光 + 轻自机狙
##   P3 其余     双螺旋 + 环形
func _update_boss(e: Dictionary, n: Node3D, delta: float) -> void:
	if bool(e["entering"]):
		# 进场：从出生点压到悬停位。z 取 -9 是按正交 68° 的投影量出来的——Boss 的 8.5×12
		# 体量要完整落在画面上半、又不贴着上缘（-14 会顶进 HUD），到位才开打。
		n.position.z = move_toward(n.position.z, BOSS_HOLD_Z, 12.0 * delta)
		if n.position.z >= BOSS_HOLD_Z:
			e["entering"] = false
		return
	e["age"] = float(e["age"]) + delta
	n.position.x = clampf(sin(float(e["age"]) * 0.5) * 6.0, -13.0, 13.0)
	var frac := float(e["hp"]) / float(e["def"]["hp"])
	var ph := 1
	if frac <= 0.33:
		ph = 3
	elif frac <= 0.66:
		ph = 2
	if ph != int(e["phase"]):
		_boss_phase_change(e, ph)
		return
	var bp := n.global_position
	match ph:
		1:
			e["act_t"] = float(e["act_t"]) - delta
			if float(e["act_t"]) <= 0.0 and int(e["burst_left"]) <= 0:
				e["act_t"] = 4.0
				e["burst_left"] = 3
				e["burst_t"] = 0.0
			if int(e["burst_left"]) > 0:
				e["burst_t"] = float(e["burst_t"]) - delta
				if float(e["burst_t"]) <= 0.0:
					e["burst_t"] = 0.38
					e["burst_left"] = int(e["burst_left"]) - 1
					e["mode"] = 1 - int(e["mode"])
					if int(e["mode"]) == 0:
						_fire_aimed(bp, e["def"], 5, 46.0, 7.5)
					else:
						_fire_aimed(bp, e["def"], 3, 14.0, 8.0)
		2:
			e["add_t"] = float(e["add_t"]) - delta
			if float(e["add_t"]) <= 0.0:
				e["add_t"] = 6.0
				for s in [-1.0, 1.0]:
					_spawn_air("E3", clampf(bp.x + s * 4.0, -13.0, 13.0), s * 3.0)
			e["laser_t"] = float(e["laser_t"]) - delta
			if float(e["laser_t"]) <= 0.0 and int(_laser["st"]) == 0:
				e["laser_t"] = 5.0
				_fire_laser(bp)
			e["act_t"] = float(e["act_t"]) - delta
			if float(e["act_t"]) <= 0.0:
				e["act_t"] = 2.4
				_fire_aimed(bp, e["def"], 1, 0.0, 8.0)
		3:
			e["sp_t"] = float(e["sp_t"]) - delta
			if float(e["sp_t"]) <= 0.0:
				e["sp_t"] = 0.12
				var a0 := float(e["spiral_a"])
				for arm in 2:
					var a := a0 + PI * float(arm)
					_enemy_bullet(bp, Vector3(sin(a) * 6.5, 0.0, cos(a) * 6.5), COL_PINK)
				e["spiral_a"] = a0 + 0.38
			e["ring_t"] = float(e.get("ring_t", 3.0)) - delta
			if float(e["ring_t"]) <= 0.0:
				e["ring_t"] = 3.0
				_fire_ring(bp, e["def"], float(e["age"]), 16, 7.5)


func _boss_phase_change(e: Dictionary, ph: int) -> void:
	e["phase"] = ph
	e["act_t"] = 1.6
	e["burst_left"] = 0
	for i in eb.count:      # 阶段切换清屏：换招的呼吸口，也是玩家的一次喘息
		eb.kill(0)
	SFX.play("eagle_boss_phase")
	_burst((e["n"] as Node3D).global_position, COL_WHITE, 16)
	_burst((e["n"] as Node3D).global_position, COL_PINK, 12)
	shake = 0.4
	# 毁伤外观：材质逐渐泛红
	var tint := 1.0 - 0.22 * float(ph - 1)
	_boss_mat.albedo_color = Color(1.0, tint, tint * 0.95)


## 横扫激光：预警线（0.7s，半透明）→ 光束（0.8s），按「玩家到线段的最近距离」判定。
## 与方块雄鹰同参数；这里必须自带判定——本作的玩家在 AIR 层，光束原点也在 AIR，同一平面。
func _fire_laser(from: Vector3) -> void:
	if _laser_warn == null:
		_build_laser()
	var org := from + Vector3(0, 0.5, 0)
	var dir: Vector3 = (host.player.position - org).normalized()
	_laser["org"] = org
	_laser["dir"] = dir
	_laser["st"] = 1
	_laser["t"] = 0.7
	SFX.play("eagle_laser")
	_laser_warn.visible = true
	_laser_pose(_laser_warn, org, dir, float(_laser["len"]))
	_laser_beam.visible = false


func _build_laser() -> void:
	_laser_warn = _mk_beam(Color(1.0, 0.16, 0.43, 0.35))
	_laser_beam = _mk_beam(Color(1, 1, 1, 0.9))


func _mk_beam(col: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 1.0)
	box.material = m
	mi.mesh = box
	mi.visible = false
	mi.cast_shadow = 0
	add_child(mi)
	return mi


func _laser_pose(node: MeshInstance3D, org: Vector3, dir: Vector3, ln: float) -> void:
	node.position = org + dir * (ln * 0.5)
	node.look_at(org + dir * ln)
	node.scale = Vector3(1, 1, ln)


func _update_laser(delta: float) -> void:
	var st := int(_laser["st"])
	if st == 0:
		return
	_laser["t"] = float(_laser["t"]) - delta
	if st == 1:
		if float(_laser["t"]) <= 0.0:
			_laser["st"] = 2
			_laser["t"] = 0.8
			_laser_warn.visible = false
			_laser_beam.visible = true
			_laser_pose(_laser_beam, _laser["org"], _laser["dir"], float(_laser["len"]))
	elif st == 2:
		if not dead and invuln <= 0.0:
			var p_rel: Vector3 = host.player.position - _laser["org"]
			var dir: Vector3 = _laser["dir"]
			var tt: float = clampf(p_rel.dot(dir), 0.0, float(_laser["len"]))
			var closest: Vector3 = _laser["org"] + dir * tt
			if host.player.position.distance_to(closest) < 1.2:
				hit_player()
		if float(_laser["t"]) <= 0.0:
			_laser["st"] = 0
			_laser_beam.visible = false


## 方舟击破：星星喷泉 + 计入存档（boss_kills），走廊继续（无尽模式没有「通关」，有「击破」）
func _boss_die(e: Dictionary) -> void:
	var gp: Vector3 = (e["n"] as Node3D).global_position
	_burst(gp, COL_WHITE, 26)
	_burst(gp, COL_PINK, 22)
	_burst(gp, COL_YELLOW, 18)
	SFX.play("eagle_boom", 3.0)
	SFX.play("eagle_win")
	score += 2000
	boss_kills += 1
	for s in 40:      # 星星喷泉（本作星池 256，40 颗不挤占）
		var v := Vector3(_rng.randf_range(-10, 10), _rng.randf_range(6, 14), _rng.randf_range(-8, 8))
		stars.spawn(gp + Vector3(0, 1.0, 0), v, COL_YELLOW, 0.85, STAR_LIFE, 16.0)
	e["n"].queue_free()
	enemies.erase(e)
	shake = 0.5
	_laser["st"] = 0
	if _laser_warn != null:
		_laser_warn.visible = false
		_laser_beam.visible = false
	host.hint("方 舟 击 破  +2000", 3.0)
	finalize()


## 结算落盘：死亡时与方舟击破时各写一次（幂等；连续写两次只是覆盖同一份字段）
func finalize() -> void:
	## 幂等：Boss 击破会先存一次、死亡再补存一次——计数只补「自上次落盘以来的差额」，
	## 否则同一局的 boss_kills / rescued_total 会被加两遍；new_best 只置位不清除
	##（第二次落盘时磁盘上的 best 已含本局分数，直接比较会把标志错误地翻回 false）。
	var d := TileSave.load_data()
	var prev: int = int(d.get("best", 0))
	new_best = new_best or score > prev
	if score > prev:
		d["best"] = score
	d["boss_kills"] = int(d.get("boss_kills", 0)) + (boss_kills - _banked_bk)
	d["rescued_total"] = int(d.get("rescued_total", 0)) + (rescued - _banked_resc)
	_banked_bk = boss_kills
	_banked_resc = rescued
	TileSave.save_data(d)
	best = maxi(best, score)
	saved = true


## 枪焰桥接：弹幕**统一在 AIR 层**（文件头注），而开火单位可能在下方的 GROUND/LOW、
## 或在最上方的 HIGH。两层之间的高度差在 68° 正交下就是一段屏幕位移（不遮挡），
## 不补枪焰的观感就是"弹从脚下 / 头顶凭空冒出来"。
## AIR 层单位本身与弹同层，不需要桥接（省一次池写入）。
func _bridge(def: Dictionary, at: Vector3) -> void:
	var layer := String(def["layer"])
	if layer == "AIR":
		return
	# HIGH 单位在弹的上方 → 枪焰打在自己身上（读作"它的炮口在开火"）；
	# GROUND / LOW 单位在弹的下方 → 枪焰打在弹层，把这段高度差接起来。
	var y: float = Altitude.of(layer) if layer == "HIGH" else Altitude.AIR
	fx.spawn(Vector3(at.x, y, at.z), Vector3(0, 3, 6), COL_YELLOW, 0.34, 0.12, 0.0, Vector3.ZERO, true)


func _burst(at: Vector3, col: Color, n: int) -> void:
	for k in n:
		var v := Vector3(_rng.randf_range(-9, 9), _rng.randf_range(2, 11), _rng.randf_range(-9, 9))
		fx.spawn(at + Vector3(0, 0.4, 0), v, col, _rng.randf_range(0.35, 0.65),
				_rng.randf_range(0.4, 0.7), 24.0, Vector3(2, 3, 0), true)


func _update_bullets(delta: float) -> void:
	pb.update(delta)
	eb.update(delta)
	# 自机弹 × 敌机（XZ 判定，高度不参与）
	var i := 0
	while i < pb.count:
		var hit := false
		for e in enemies:
			var gp: Vector3 = (e["n"] as Node3D).global_position
			var r: Vector2 = e["def"]["hit"]
			if absf(pb.pos[i].x - gp.x) < r.x and absf(pb.pos[i].z - gp.z) < r.y:
				_damage(e, 1)
				fx.spawn(pb.pos[i], Vector3(0, 2, 4), COL_WHITE, 0.3, 0.14, 0.0, Vector3.ZERO, true)
				hit = true
				break
		if hit:
			pb.kill(i)
		else:
			i += 1
	if dead:
		return
	# 敌弹 × 玩家
	i = 0
	while i < eb.count:
		var d: Vector3 = eb.pos[i] - host.player.position
		if absf(d.x) < 0.95 and absf(d.z) < 0.95 and absf(d.y) < 1.2:
			eb.kill(i)
			hit_player()
			if dead:
				return
		else:
			i += 1
	# 撞击伤害（无人机）
	for e in enemies:
		if bool(e["def"].get("ram", false)):
			var gp2: Vector3 = (e["n"] as Node3D).global_position
			if absf(gp2.x - host.player.position.x) < 1.6 and absf(gp2.z - host.player.position.z) < 1.6:
				hit_player()
				if dead:
					return


func _update_stars(delta: float) -> void:
	stars.update(delta)
	var i := 0
	while i < stars.count:
		# 落海弹跳 + 落到海面后随地貌滚动（与方块雄鹰同手法）
		if stars.pos[i].y < Altitude.SEA + 0.15 and stars.vel[i].y < 0.0:
			stars.vel[i].y = absf(stars.vel[i].y) * 0.35
			if stars.vel[i].y < 1.0:
				stars.vel[i].y = 0.0
				stars.vel[i].z = host.scroll_spd
		var d: Vector3 = host.player.position - stars.pos[i]
		var dxz: float = Vector2(d.x, d.z).length()
		if dxz < MAGNET_R and not dead:
			stars.vel[i] = d.normalized() * clampf(26.0 - dxz * 2.0, 8.0, 26.0)
			stars.vel[i].y *= 0.4
		if dxz < 1.7 and not dead:
			stars.kill(i)
			star_cnt += 1
			score += 10
			SFX.play("eagle_star", -8.0)
			continue
		if stars.pos[i].z > RECYCLE_Z:
			stars.kill(i)
			continue
		i += 1


# ================= 受击 =================

func _damage(e: Dictionary, dmg: int) -> void:
	e["hp"] = int(e["hp"]) - dmg
	if String(e["t"]) == "BOSS":
		if bool(e["entering"]):
			e["hp"] = int(e["hp"]) + dmg      # 进场中无敌（还没就位，打了也不算）
			return
		if int(e["hp"]) <= 0:
			_boss_die(e)
		return
	if int(e["hp"]) > 0:
		return
	var def: Dictionary = e["def"]
	var n: Node3D = e["n"]
	var gp := n.global_position
	_burst(gp, COL_PINK, 12)
	_burst(gp, COL_WHITE, 6)
	SFX.play("eagle_boom")
	score += int(def.get("score", 30))
	kills += 1
	for s in int(def.get("stars", 1)):
		stars.spawn(gp + Vector3(0, 0.5, 0),
				Vector3(_rng.randf_range(-6, 6), _rng.randf_range(3, 8), _rng.randf_range(-4, 4)),
				COL_YELLOW, 0.85, STAR_LIFE, 16.0)
	n.queue_free()
	enemies.erase(e)


func hit_player() -> void:
	if invuln > 0.0 or dead:
		return
	armor -= 1
	invuln = INVULN
	shake = 0.35
	SFX.play("eagle_hurt")
	var p: Vector3 = host.player.position
	_burst(p, COL_PINK, 10)
	if armor <= 0:
		dead = true
		_burst(p, COL_YELLOW, 18)
		_burst(p, COL_WHITE, 10)
		finalize()
		SFX.play("eagle_lose")
