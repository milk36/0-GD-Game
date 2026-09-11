extends Node3D
## 方块雄鹰 M3：体素纵版弹幕射击（Sky Force 类）。
## M0 基础 + M2 系统 + M3 内容：三关卡主题地形、选关面板（奖牌解锁）、
## E6 精英炮舰、炸弹补给掉落、程序化音效、按关结算与存档。
## 调试键：F1/F2 相机 68°/90°，F3 阴影，F4 弹幕压测；H 机库；S 选关；Esc 暂停。
## M3.12：玩家机移除金属材质层，统一使用普通受光材质。

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const VoxelPool = preload("res://scripts/voxel_eagle/pools.gd")
const SaveManager = preload("res://scripts/voxel_eagle/save_manager.gd")
const Stages = preload("res://scripts/voxel_eagle/stages.gd")
const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const SurvivorUnit = preload("res://scripts/voxel_eagle/survivor_unit.gd")
const RescueRing = preload("res://scripts/voxel_eagle/rescue_ring.gd")

# ---- MagicaVoxel 体素场景（.vox）接入 ----
# 把 assets/vox 下的 .vox 直接挂进战场：编辑器已导入则走导入产物（greedy mesh），
# 否则运行时用 VoxReader 解析。改 .vox 保存后重开游戏即生效，无需手工导出。
const VOX_DECOR_PATH := "res://assets/vox/island_scene.vox"
const VOX_DECOR_COUNT := 2        # 体素场景岛数量，0 = 关闭
const VOX_DECOR_SCALE := 0.1      # 仅运行时解析路径使用（1 体素 = 0.1 世界单位）
const VOX_DECOR_REPLACE := true   # true = 体素岛替换全部旧程序化草岛（已开启；暗礁/沉船仍为程序化，待 vox 化）

# ---- 数值 ----
const PLAYER_SPEED := 24.0
const ARENA_HALF_W := 15.0     # 玩家横移边界
const PLAYER_Z_MIN := -8.0
const PLAYER_Z_MAX := 10.0
const BULLET_SPEED := 46.0
const PLAYER_Y := 4.5          # 玩家飞行高度（高于岛屿/炮台/沉船顶部，避免穿模）
const ENEMY_BULLET_Y := 4.5    # 敌弹飞行高度（与玩家判定平面一致）
const STAR_LIFE := 9.0

# 阶段机
const PH_WAVES := 0
const PH_BOSSENTER := 1
const PH_BOSS := 2
const PH_VICTORY := 3
const PH_OVER := 4

const COL_CYAN := Color("00f0ff")
const COL_PINK := Color("ff2a6d")
const COL_YELLOW := Color("ffe600")
const COL_WHITE := Color("f5f9ff")

# 玩家机 / Boss / E1~E6 造型均已迁移至 MagicaVoxel 资产（assets/vox/units/*.vox），
# 经 tools/vox/gen_units.py 生成，可在 MagicaVoxel 中继续编辑后直接生效。
# 批量迭代流程：改 gen_units.py（或 MagicaVoxel 直接改 .vox）→ python gen_units.py
# → 切回编辑器等重导入 → 重开游戏。敌机已无字符画残留（旧 ART_* / PAL_ENEMY 已删）。
const ENEMY_VOX := {
	"E1": "res://assets/vox/units/E1.vox",     # 炮台底座（地面单位，贴地摆放）
	"E1H": "res://assets/vox/units/E1H.vox",   # 炮台炮头（含前伸炮管，look_at 指向玩家）
	"E2": "res://assets/vox/units/E2.vox",     # 环形机（中空方环 + 悬浮核心）
	"E3": "res://assets/vox/units/E3.vox",     # 无人机机身（四旋翼悬臂，朝向稳定不转）
	"E3R": "res://assets/vox/units/E3R.vox",   # 无人机旋翼层（挂机身顶部，单独绕 Y 旋转）
	"E4": "res://assets/vox/units/E4.vox",     # 战斗机（后掠翼，自机狙）
	"E5": "res://assets/vox/units/E5.vox",     # 巡航机（重型机身，五连发扇形）
	"E6": "res://assets/vox/units/E6.vox",     # 精英炮舰（双炮塔 + 舰桥 + 三联引擎）
	"E7": "res://assets/vox/units/E7.vox",     # 武装直升机机身（AI 体素管线 spec 产出，朝向稳定不自转）
	"E7R": "res://assets/vox/units/E7R.vox",   # 直升机主旋翼层（挂机身顶部，单独绕 Y 旋转）
	"E8": "res://assets/vox/units/E8.vox",     # 飞翼轰炸机（无尾三角飞翼，spec 批量产出）
	"E9": "res://assets/vox/units/E9.vox",     # 双体炮艇（双船身 + 中央桥炮塔，spec 批量产出）
	"E10": "res://assets/vox/units/E10.vox",   # 浮空盾堡（核心塔 + 能量环，spec 批量产出，ring op 首投产）
}
# 敌机 .vox 统一按 0.3 世界单位/体素 缩放（与玩家机同一精度；Boss 单独用 0.5）
const ENEMY_SCALE := 0.3
# 幸存者造型在 scripts/voxel_eagle/survivor_unit.gd（游戏与测试场景共用）
# 地貌（草岛 / 暗礁 / 沉船）仍是程序化方块，不属"单位造型"范畴

# 机库升级线定义（数值曲线见 save_manager.upgrade_cost）
const UPGRADES := [
	{"k": "main", "name": "主炮", "fx": "火力密度/弹列提升"},
	{"k": "wing", "name": "僚机导弹", "fx": "追踪弹 +1 枚（每 3s）"},
	{"k": "magnet", "name": "磁铁", "fx": "星星吸取半径 +2"},
	{"k": "shield", "name": "护盾", "fx": "出击护甲 +1（上限 +2）"},
	{"k": "bomb", "name": "炸弹", "fx": "携带上限 +1 / 威力提升"},
]

# ---- 场景节点 ----
var world: Node3D
var player: Node3D
var player_mesh: MeshInstance3D
var flame: MeshInstance3D
var cam: Camera3D
var sun: DirectionalLight3D
var pb: MultiMeshInstance3D   # 自机弹
var eb: MultiMeshInstance3D   # 敌弹
var pickups: MultiMeshInstance3D  # 星星
var supplies: MultiMeshInstance3D # 炸弹补给
var fx: MultiMeshInstance3D    # 碎片/闪光
var enemies: Array = []        # 敌人 dict 列表（含 Boss）
var waves: Array = []          # 波浪装饰 dict 列表（含相位）
var islands: Array = []        # 草岛 Node3D
var reefs: Array = []          # 暗礁岩石 Node3D
var wrecks: Array = []         # 燃烧沉船 Node3D
var fires: Array = []          # 火焰动画 dict 列表
var clouds: Array = []         # 云朵 dict 列表（视差）
var survivors: Array = []      # 幸存者 dict 列表（含 anchor_y 立足面高度）
var _island_cols := {}         # 体素岛滩涂列缓存 {Vector2i: 列顶高(体素)}，首次锚定懒加载
var _island_cols_mn := Vector2i.ZERO   # 列表 x/z 最小键（算网格中心用）
var _island_cols_mx := Vector2i.ZERO   # 列表 x/z 最大键
var missiles: Array = []       # 僚机追踪弹 dict 列表
var rope: MeshInstance3D       # 救援绳索（细长方块）
var laser_warn: MeshInstance3D
var laser_beam: MeshInstance3D
var boss_mat: StandardMaterial3D
var rescue_ring: MeshInstance3D   # 机上营救进度计时圈
var ring_flash_t := 0.0           # 救起后进度圈保留显示的剩余时间

# ---- HUD ----
var hud_score: Label
var hud_armor: Label
var hud_info: Label
var hud_center: Label
var hud_boss: Label

# ---- 覆盖层（选关 / 结算 / 机库） ----
var select_root: Control
var settle_root: Control
var settle_title: Label
var settle_lines: Label
var settle_medals: Label
var settle_unlock: Label
var hangar_root: Control
var hangar_balance: Label
var hangar_lv := {}    # key → Label（等级显示）
var hangar_buy := {}   # key → Button
var hangar_from := ""  # 打开来源："pause" / "settle"

# ---- 存档与局内状态 ----
var save: Dictionary
var stage_def: Dictionary
var stage_id := 1
var stage_name := ""
var phase := PH_WAVES
var score := 0
var star_cnt := 0          # 本局已拾取星星
var stars_spawned := 0     # 本局已产出星星（奖牌分母）
var armor := 3
var bombs := 2
var escaped := 0           # 逃逸敌机数（歼灭奖牌用）
var rescued := 0
var damage_taken := 0
var invuln := 0.0
var dead := false
var paused := false
var fire_cd := 0.0
var elapsed := 0.0
var stage_t := 0.0         # 关卡脚本时钟
var wave_i := 0
var surv_i := 0
var waves_done := false
var boss_delay := 0.0
var settle_t := 0.0
var victory := false
var shake := 0.0
var cam_mode := 0          # 0=68° 斜俯视 1=90° 纯俯视
var stress := false
var hud_cd := 0.0
var wing_t := 3.0
var laser := {"st": 0, "t": 0.0, "org": Vector3.ZERO, "dir": Vector3.FORWARD, "len": 60.0}

var rescue_hint_done := false
var hint_t := 0.0

# 关卡参数（来自 stage_def）
var scroll_spd := 7.0
var survivor_total := 3
var boss_pace := 1.0

# 升级快照（出击时从存档套用）
var fire_int := 0.11
var magnet_r := 3.0
var armor_max := 3
var bombs_max := 2
var boss := {}             # Boss dict（也在 enemies 中）
var _meshes := {}          # 敌型号 → 共享 ArrayMesh


func _ready() -> void:
	save = SaveManager.load_data()
	_load_stage_def()
	_apply_upgrades()
	_build_env()
	_build_ground()
	_build_player()
	_build_pools()
	_build_hud()
	_build_overlays()
	_meshes = {
		"SURV": SurvivorUnit.mesh(),
	}
	# E1~E6：MagicaVoxel .vox 运行时解析（与玩家机 / Boss 同一条加载路径）
	for k in ENEMY_VOX:
		_meshes[k] = _load_vox_mesh(ENEMY_VOX[k])
	if Stages.selected == 0:
		select_root.visible = true  # 从大厅进入：先选关
	_start_bgm()


## 背景音乐：程序化四小节循环，按关变调；随场景退出自动停止
func _start_bgm() -> void:
	var bstream := SFX.stream_for("eagle_bgm")
	if bstream == null:
		return
	bstream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bstream.loop_begin = 0
	bstream.loop_end = bstream.data.size() / 4  # 16bit 立体声帧数
	var bgm := AudioStreamPlayer.new()
	bgm.stream = bstream
	bgm.volume_db = -16.0
	bgm.pitch_scale = [1.0, 1.05, 1.1][stage_id - 1]
	add_child(bgm)
	bgm.play()


func _load_stage_def() -> void:
	stage_id = 1 if int(Stages.selected) == 0 else int(Stages.selected)
	for s in Stages.STAGES:
		if int(s["id"]) == stage_id:
			stage_def = s
			break
	stage_name = stage_def["name"]
	scroll_spd = float(stage_def["scroll"])
	survivor_total = int(stage_def["survivors"])
	boss_pace = float(stage_def["boss_pace"])


func _apply_upgrades() -> void:
	var up: Dictionary = save["upgrades"]
	var main_lv: int = up.get("main", 1)
	var mag_lv: int = up.get("magnet", 0)
	var sh_lv: int = up.get("shield", 0)
	var bo_lv: int = up.get("bomb", 0)
	fire_int = maxf(0.12 - 0.004 * float(main_lv), 0.085)
	magnet_r = 3.0 + 2.0 * float(mag_lv)
	armor_max = 3 + mini(sh_lv, 2)
	armor = armor_max
	bombs_max = mini(2 + bo_lv, 5)
	bombs = bombs_max


## 运行时解析单位 .vox 网格（与玩家机 / Boss 一致）；失败时退化为占位方块，保证流程可跑
func _load_vox_mesh(path: String) -> Mesh:
	var m := VoxReader.read_mesh(path)
	if m != null and m.get_surface_count() > 0:
		return m
	push_warning("单位 .vox 加载失败，使用占位方块：%s" % path)
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.0, 3.0)
	return bm


# ================= 场景构建 =================

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(stage_def["sky"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(stage_def["ambient"])
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = 1  # DEPTH
	env.fog_light_color = Color(stage_def["fog"])
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 170.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(stage_def["sun"])
	sun.light_energy = float(stage_def["sun_energy"])
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 0  # ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	cam = Camera3D.new()
	cam.projection = 1  # ORTHOGONAL
	cam.size = 34.0     # M3.5 拉高视野：26 → 34，展示更多场景
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	cam.position = Vector3(0, 30, 12)
	cam.look_at(Vector3.ZERO)


func _build_ground() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	# 海面：纯色大平面（无纹理，运动感由波浪块/岛提供）
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(stage_def["sea"])
	sea_mat.roughness = 1.0
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(72, 300)
	pm.material = sea_mat
	sea.mesh = pm
	sea.position = Vector3(0, 0, -110)
	add_child(sea)

	# 波浪装饰（两层）：细长浪痕条带 + 小块亮浪尖，颜色由本关海色向白色分带插值
	# （无光照材质保证色带精确，不随光照漂白）；挂 World 随滚动流动 + 轻微呼吸，
	# 滚出下缘后回绕（见 _process 波浪回绕段）。
	var sea_c := Color(stage_def["sea"])
	var band: Array = []
	for f in [0.22, 0.38, 0.55, 0.82]:
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = sea_c.lerp(Color.WHITE, f)
		band.append(bm)
	for i in 64:  # 浪痕：细长条带，模拟涌浪破碎纹（三档暗→亮）
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(randf_range(1.0, 3.4), 0.05, randf_range(0.5, 1.1))
		wm.material = band[randi() % 3]
		w.mesh = wm
		w.position = Vector3(randf_range(-26, 26), 0.07, randf_range(-200, 24))
		world.add_child(w)
		waves.append({"n": w, "ph": randf() * TAU})
	for i in 16:  # 浪尖：小而亮的碎浪块，点缀在浪痕之间
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(randf_range(0.55, 0.95), 0.07, randf_range(0.55, 0.95))
		cm.material = band[3]
		c.mesh = cm
		c.position = Vector3(randf_range(-26, 26), 0.07, randf_range(-200, 24))
		world.add_child(c)
		waves.append({"n": c, "ph": randf() * TAU})

	# 地貌：草岛 / 暗礁岩石 / 燃烧沉船（按关卡数量，元素差异参照需求截图）
	if not VOX_DECOR_REPLACE:
		for i in int(stage_def["islands"]):
			islands.append(_make_island())
	# MagicaVoxel 体素场景：直接挂 .vox，与草岛共用回绕/避让逻辑
	for i in VOX_DECOR_COUNT:
		_spawn_vox_decor()
	for i in int(stage_def["reefs"]):
		reefs.append(_make_reef())
	for i in int(stage_def["wrecks"]):
		wrecks.append(_make_wreck())

	# 天空云朵：4~6 块相互重叠拼成蓬松云团，高空慢速飘过战场（半透明、不投影）
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.albedo_color = Color(1, 1, 1, 0.34)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 5:
		var cloud := Node3D.new()
		for k in randi_range(4, 6):
			var cm := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(randf_range(2.6, 5.5), randf_range(0.7, 1.2), randf_range(2.0, 3.6))
			box.material = cloud_mat
			cm.mesh = box
			cm.position = Vector3(randf_range(-1.5, 1.5), randf_range(-0.35, 0.35), randf_range(-1.0, 1.0))
			cm.cast_shadow = 0  # 云不投影
			cloud.add_child(cm)
		cloud.position = Vector3(randf_range(-26, 26), randf_range(13.0, 19.0), randf_range(-200, 24))
		add_child(cloud)
		clouds.append({"n": cloud, "spd": randf_range(0.22, 0.42)})


func _make_island() -> Node3D:
	var blocks := {}
	var half := randi_range(1, 2)
	for x in range(-half - 1, half + 2):
		for z in range(-half - 1, half + 2):
			var edge := absi(x) > half or absi(z) > half
			blocks[Vector3i(x, 0, z)] = Color("8a7a52") if edge else Color("1f6f3f")
	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			if (x + z) % 2 == 0:
				blocks[Vector3i(x, 1, z)] = Color("2a8a4f")
	# 要塞关：岛上加灰色军事建筑块
	if bool(stage_def["buildings"]) and randf() < 0.55:
		for h in 2:
			blocks[Vector3i(0, 2 + h, 0)] = Color("5a6478")
			blocks[Vector3i(1, 2 + h, 0)] = Color("49526a")
	var n := MeshInstance3D.new()
	n.mesh = VoxelModel.build_blocks(blocks)
	n.material_override = VoxelModel.shaded_material()
	n.position = _decor_spot(22.0, 0.0)
	world.add_child(n)
	return n


## MagicaVoxel 体素场景接入：优先用编辑器导入产物（已按 Scale=0.1 烘焙），
## 缺失时回退到 VoxReader 运行时解析（仍按 1 体素 0.1 单位缩放），并归入 islands
## 复用既有的回绕（z 越界回卷）与波浪穿模剔除逻辑。
func _spawn_vox_decor() -> Node3D:
	var mesh := load(VOX_DECOR_PATH) as Mesh
	var s := 1.0
	if mesh == null:  # 编辑器尚未导入 / 导出后无导入产物 → 运行时解析
		mesh = VoxReader.read_mesh(VOX_DECOR_PATH)
		s = VOX_DECOR_SCALE
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("体素场景加载失败，已跳过：%s" % VOX_DECOR_PATH)
		return null
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.scale = Vector3(s, s, s)
	n.material_override = VoxelModel.shaded_material()
	n.rotate_y(randf() * TAU)  # 随机朝向，避免重复感
	var p := _decor_spot(20.0, 0.0)
	p.y = -mesh.get_aabb().position.y * s - 0.1  # 底面对齐海面并略微下沉
	n.position = p
	n.set_meta("vox_island", true)  # 幸存者锚定：可从 .vox 采样滩涂列
	world.add_child(n)
	islands.append(n)
	return n


## 暗礁岩石：浅灰色不规则石堆，随机缺角与凸起
func _make_reef() -> Node3D:
	var blocks := {}
	var rx := randi_range(1, 2)
	var rz := randi_range(1, 2)
	for x in range(-rx - 1, rx + 2):
		for z in range(-rz - 1, rz + 2):
			if randf() < 0.18:
				continue  # 不规则边缘
			blocks[Vector3i(x, 0, z)] = Color("7d7d88") if randf() < 0.5 else Color("93939e")
	for k in randi_range(1, 3):
		blocks[Vector3i(randi_range(-rx, rx), 1, randi_range(-rz, rz))] = Color("a8a8b4")
	var n := MeshInstance3D.new()
	n.mesh = VoxelModel.build_blocks(blocks)
	n.material_override = VoxelModel.shaded_material()
	n.position = _decor_spot(22.0, 0.02)
	world.add_child(n)
	return n


## 燃烧沉船：深色断成两截的船体 + 两团闪烁火焰（参照需求截图中的燃烧舰船）
func _make_wreck() -> Node3D:
	var blocks := {}
	for z in 6:
		if z == 3:
			continue  # 中段断裂缺口
		for x in 2:
			blocks[Vector3i(x, 0, z)] = Color("3a3230") if (x + z) % 2 == 0 else Color("463c38")
	blocks[Vector3i(0, 1, 1)] = Color("2a2422")  # 舰桥残骸
	blocks[Vector3i(1, 1, 1)] = Color("2a2422")
	var n := MeshInstance3D.new()
	n.mesh = VoxelModel.build_blocks(blocks)
	n.material_override = VoxelModel.shaded_material()
	n.rotation.y = randf_range(-0.4, 0.4)
	# 火焰：橙黄双团，无光照闪烁
	for k in 2:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.55, 0.55, 0.55)
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = COL_YELLOW if k == 0 else Color("ff9020")
		fm.material = fmat
		f.mesh = fm
		f.position = Vector3(randf_range(0.2, 0.8), 0.8, float(k) * 1.6)
		n.add_child(f)
		fires.append({"n": f, "y0": 0.8, "ph": randf() * TAU})
	n.position = _decor_spot(20.0, 0.08)
	world.add_child(n)
	return n


## 地貌摆放：避开已有岛屿/礁石/沉船（最小间距 7），防止物件相互穿模
func _decor_spot(xr: float, y: float) -> Vector3:
	var p := Vector3(randf_range(-xr, xr), y, randf_range(-200.0, 24.0))
	for attempt in 8:
		p = Vector3(randf_range(-xr, xr), y, randf_range(-200.0, 24.0))
		var ok := true
		for arr in [islands, reefs, wrecks]:
			for d in arr:
				if Vector2(d.position.x - p.x, d.position.z - p.z).length() < 7.0:
					ok = false
					break
			if not ok:
				break
		if ok:
			break
	return p


func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	player_mesh = MeshInstance3D.new()
	# MagicaVoxel 体素机（.vox 运行时解析，顶点色与材质体系一致）
	player_mesh.mesh = VoxReader.read_mesh("res://assets/vox/units/player.vox")
	player_mesh.scale = Vector3.ONE * 0.3  # 15×19×6 体素 × 0.3 ≈ 4.5×5.7×1.8
	player_mesh.material_override = VoxelModel.shaded_material()  # 普通受光材质（同敌人/地貌）
	player.add_child(player_mesh)
	player.position = Vector3(0, PLAYER_Y, 6)

	flame = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.5, 0.5, 1.4)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = COL_YELLOW
	fm.material = fmat
	flame.mesh = fm
	flame.position = Vector3(0, 0, 3.2)
	player.add_child(flame)

	# 救援绳索（细长白方块，救援时显示）
	rope = MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.16, 0.16, 1.0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = COL_WHITE
	rm.material = rmat
	rope.mesh = rm
	rope.visible = false
	add_child(rope)

	# 营救进度计时圈（挂在机上，营救时显示，半径=触发距离）
	rescue_ring = RescueRing.build()
	player.add_child(rescue_ring)

	# Boss 激光：预警细线 + 光束粗梁
	laser_warn = MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.14, 0.14, 1.0)
	wm.material = rmat
	laser_warn.mesh = wm
	laser_warn.visible = false
	add_child(laser_warn)
	laser_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.6, 1.0)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = COL_PINK
	bm.material = bmat
	laser_beam.mesh = bm
	laser_beam.visible = false
	add_child(laser_beam)

	boss_mat = VoxelModel.shaded_material()


func _build_pools() -> void:
	var unshaded := VoxelModel.unshaded_material()
	pb = VoxelPool.new()
	add_child(pb)
	pb.setup(96, unshaded)
	eb = VoxelPool.new()
	add_child(eb)
	eb.setup(512, unshaded)
	pickups = VoxelPool.new()
	add_child(pickups)
	pickups.setup(256, unshaded)
	supplies = VoxelPool.new()
	add_child(supplies)
	supplies.setup(16, unshaded)
	fx = VoxelPool.new()
	add_child(fx)
	fx.setup(320, unshaded)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_score = _mk_label(layer, Vector2(24, 16), 22, COL_CYAN)
	hud_armor = _mk_label(layer, Vector2(24, 52), 18, COL_PINK)
	hud_info = _mk_label(layer, Vector2(24, 690), 14, Color("8a93b8"))
	hud_center = _mk_label(layer, Vector2(360, 300), 30, COL_YELLOW)
	hud_boss = _mk_label(layer, Vector2(820, 16), 20, COL_PINK)
	hud_boss.visible = false


func _mk_label(parent: Node, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


# ================= 覆盖层（选关 / 结算 / 机库） =================

func _make_overlay() -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(15)  # FULL_RECT
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.86)
	dim.set_anchors_preset(15)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(15)
	root.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	cc.add_child(box)
	root.visible = false
	return [root, box]


func _mk_olabel(box: VBoxContainer, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = 1  # 居中
	box.add_child(l)
	return l


func _mk_obutton(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _build_overlays() -> void:
	_build_select()
	var sr := _make_overlay()
	settle_root = sr[0]
	var sbox: VBoxContainer = sr[1]
	settle_title = _mk_olabel(sbox, 34, COL_YELLOW)
	settle_lines = _mk_olabel(sbox, 20, COL_WHITE)
	settle_medals = _mk_olabel(sbox, 20, COL_CYAN)
	settle_unlock = _mk_olabel(sbox, 16, Color("8a93b8"))
	_mk_olabel(sbox, 14, Color("8a93b8")).text = " "
	_mk_obutton(sbox, "H 机库", _open_hangar_from_settle)
	_mk_obutton(sbox, "R 重打", restart)
	_mk_obutton(sbox, "S 选关", _back_to_select)
	_mk_obutton(sbox, "Q 返回大厅", _go_menu)

	var hr := _make_overlay()
	hangar_root = hr[0]
	var hbox: VBoxContainer = hr[1]
	hangar_balance = _mk_olabel(hbox, 30, COL_YELLOW)
	_mk_olabel(hbox, 16, Color("8a93b8")).text = "机库 · 星星升级（下次出击生效）"
	for u in UPGRADES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		hbox.add_child(row)
		var name_l := Label.new()
		name_l.text = u["name"]
		name_l.custom_minimum_size = Vector2(120, 0)
		name_l.add_theme_font_size_override("font_size", 19)
		name_l.add_theme_color_override("font_color", COL_CYAN)
		row.add_child(name_l)
		var lv_l := Label.new()
		lv_l.text = "Lv 1/8"
		lv_l.custom_minimum_size = Vector2(90, 0)
		lv_l.add_theme_font_size_override("font_size", 19)
		row.add_child(lv_l)
		hangar_lv[u["k"]] = lv_l
		var fx_l := Label.new()
		fx_l.text = u["fx"]
		fx_l.custom_minimum_size = Vector2(230, 0)
		fx_l.add_theme_font_size_override("font_size", 15)
		fx_l.add_theme_color_override("font_color", Color("8a93b8"))
		row.add_child(fx_l)
		var btn := Button.new()
		btn.text = "★0 升级"
		btn.custom_minimum_size = Vector2(130, 40)
		btn.pressed.connect(_buy.bind(u["k"]))
		row.add_child(btn)
		hangar_buy[u["k"]] = btn
	_mk_olabel(hbox, 14, Color("8a93b8")).text = " "
	_mk_obutton(hbox, "Esc/H 关闭", _close_hangar)
	_refresh_hangar()


func _build_select() -> void:
	var sr := _make_overlay()
	select_root = sr[0]
	var box: VBoxContainer = sr[1]
	_mk_olabel(box, 32, COL_CYAN).text = "选择作战区域"
	_mk_olabel(box, 15, Color("8a93b8")).text = "奖牌解锁：关 2 需关 1 奖牌 ≥2 · 关 3 需累计 ≥4（歼灭 / 救援 / 星光 / 完璧）"
	_mk_olabel(box, 12, Color("8a93b8")).text = " "
	for s in Stages.STAGES:
		var id: int = int(s["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		box.add_child(row)
		var name_l := Label.new()
		name_l.text = "%d · %s" % [id, s["name"]]
		name_l.custom_minimum_size = Vector2(220, 0)
		name_l.add_theme_font_size_override("font_size", 21)
		name_l.add_theme_color_override("font_color", COL_WHITE)
		row.add_child(name_l)
		var got: Array = save["medals"].get(str(id), [])
		var medal_s := ""
		for m in Stages.MEDAL_ORDER:
			medal_s += "■" if got.has(m) else "□"
		var medal_l := Label.new()
		medal_l.text = medal_s
		medal_l.custom_minimum_size = Vector2(120, 0)
		medal_l.add_theme_font_size_override("font_size", 21)
		medal_l.add_theme_color_override("font_color", COL_YELLOW)
		row.add_child(medal_l)
		var best_l := Label.new()
		best_l.text = "最高 %d" % int(save["best"].get(str(id), 0))
		best_l.custom_minimum_size = Vector2(160, 0)
		best_l.add_theme_font_size_override("font_size", 16)
		best_l.add_theme_color_override("font_color", Color("8a93b8"))
		row.add_child(best_l)
		var btn := Button.new()
		var unlocked := Stages.is_unlocked(save, id)
		btn.text = "出 击" if unlocked else "已锁定"
		btn.disabled = not unlocked
		btn.custom_minimum_size = Vector2(130, 44)
		btn.pressed.connect(_launch_stage.bind(id))
		row.add_child(btn)
	_mk_olabel(box, 12, Color("8a93b8")).text = " "
	_mk_obutton(box, "返回大厅", _go_menu)


func _launch_stage(id: int) -> void:
	Stages.selected = id
	restart()


func _back_to_select() -> void:
	Stages.selected = 0
	restart()


func _refresh_hangar() -> void:
	hangar_balance.text = "★ %d" % int(save["stars"])
	for u in UPGRADES:
		var k: String = u["k"]
		var lv: int = save["upgrades"].get(k, 0)
		if k == "main":
			lv = maxi(lv, 1)
		var lv_l: Label = hangar_lv[k]
		lv_l.text = "Lv %d/8" % lv
		var btn: Button = hangar_buy[k]
		if lv >= 8:
			btn.text = "已满级"
			btn.disabled = true
		else:
			var cost := SaveManager.upgrade_cost(lv + 1)
			btn.text = "★%d 升级" % cost
			btn.disabled = int(save["stars"]) < cost


func _buy(k: String) -> void:
	var lv: int = save["upgrades"].get(k, 0)
	if k == "main":
		lv = maxi(lv, 1)
	if lv >= 8:
		return
	var cost := SaveManager.upgrade_cost(lv + 1)
	if int(save["stars"]) < cost:
		return
	save["stars"] = int(save["stars"]) - cost
	save["upgrades"][k] = lv + 1
	SaveManager.save_data(save)
	_refresh_hangar()


func _open_hangar_from_settle() -> void:
	hangar_from = "settle"
	settle_root.visible = false
	_refresh_hangar()
	hangar_root.visible = true


func _close_hangar() -> void:
	hangar_root.visible = false
	if hangar_from == "settle":
		settle_root.visible = true


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ================= 主循环 =================

func _process(delta: float) -> void:
	if select_root.visible or paused or hangar_root.visible or phase == PH_OVER:
		return
	elapsed += delta
	shake = maxf(0.0, shake - delta)
	invuln = maxf(0.0, invuln - delta)

	# 世界滚动 + 地貌回绕与动画
	world.position.z += scroll_spd * delta
	var decor: Array = islands + reefs + wrecks
	for wd in waves:
		var wn: Node3D = wd["n"]
		wn.position.y = 0.07 + 0.045 * sin(elapsed * 2.2 + float(wd["ph"]))
		if world.position.z + wn.position.z > 26.0:
			wn.position.z -= 224.0
			wn.position.x = randf_range(-26, 26)
		# 波浪穿模剔除：靠近岛屿/礁石/沉船时隐藏
		var wgp := wn.global_position
		var blocked := false
		for d in decor:
			var dp: Vector3 = d.position
			if absf(dp.x - wgp.x) < 5.0 and absf(world.position.z + dp.z - wgp.z) < 5.0:
				blocked = true
				break
		wn.visible = not blocked
	for isl in islands:
		if world.position.z + isl.position.z > 30.0:
			isl.position.z -= 230.0
			isl.position.x = randf_range(-22, 22)
	for rf in reefs:
		if world.position.z + rf.position.z > 30.0:
			rf.position.z -= 230.0
			rf.position.x = randf_range(-22, 22)
	for wk in wrecks:
		if world.position.z + wk.position.z > 30.0:
			wk.position.z -= 230.0
			wk.position.x = randf_range(-20, 20)
	for fr in fires:  # 火焰闪烁
		var fl := 1.0 + 0.35 * sin(elapsed * 13.0 + float(fr["ph"]))
		fr["n"].scale = Vector3(fl, fl, fl)
		fr["n"].position.y = float(fr["y0"]) + 0.12 * sin(elapsed * 9.0 + float(fr["ph"]))
	for cl in clouds:  # 云朵慢速视差
		var cn: Node3D = cl["n"]
		cn.position.z += scroll_spd * float(cl["spd"]) * delta
		if cn.position.z > 28.0:
			cn.position.z -= 230.0
			cn.position.x = randf_range(-26, 26)
			cn.position.y = randf_range(13.0, 19.0)

	if dead:
		settle_t -= delta
		if settle_t <= 0.0:
			_show_settlement(false)
	else:
		_update_player(delta)
		match phase:
			PH_WAVES:
				_update_stage_script(delta)
			PH_VICTORY:
				settle_t -= delta
				if settle_t <= 0.0:
					_show_settlement(true)
			_:
				pass
		_update_survivors(delta)
		_update_enemies(delta)
		_update_missiles(delta)
		_update_laser(delta)
	_update_bullets(delta)
	_update_pickups(delta)
	_update_supplies(delta)
	fx.update(delta)
	_update_camera(delta)

	hud_cd -= delta
	if hud_cd <= 0.0:
		hud_cd = 0.15
		_refresh_hud()

	if hint_t > 0.0:  # 救援提示到期清除（不覆盖坠机/暂停文案）
		hint_t -= delta
		if hint_t <= 0.0 and hud_center.text.begins_with("飞到"):
			hud_center.text = ""


## 关卡脚本：按 stage_t 触发波次与幸存者，全部触发后延时进 Boss
func _update_stage_script(delta: float) -> void:
	stage_t += delta
	var wave_list: Array = stage_def["waves"]
	var spot_list: Array = stage_def["spots"]
	while wave_i < wave_list.size() and stage_t >= float(wave_list[wave_i]["t"]):
		_spawn_group(wave_list[wave_i]["spawn"])
		wave_i += 1
	while surv_i < spot_list.size() and stage_t >= float(spot_list[surv_i]["t"]):
		_spawn_survivor(float(spot_list[surv_i]["x"]))
		surv_i += 1
	if wave_i >= wave_list.size():
		if not waves_done:
			waves_done = true
			boss_delay = 6.0
		boss_delay -= delta
		if boss_delay <= 0.0:
			phase = PH_BOSSENTER
			_spawn_boss()


# ================= 玩家 =================

func _update_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	dir = dir.normalized()
	player.position.x = clampf(player.position.x + dir.x * PLAYER_SPEED * delta, -ARENA_HALF_W, ARENA_HALF_W)
	player.position.z = clampf(player.position.z + dir.y * PLAYER_SPEED * delta, PLAYER_Z_MIN, PLAYER_Z_MAX)

	# 机身倾斜 + 尾焰脉动（尾焰随视觉缩放 0.6）
	player.rotation.z = lerp(player.rotation.z, -dir.x * 0.32, 10.0 * delta)
	player.rotation.x = lerp(player.rotation.x, dir.y * 0.12, 10.0 * delta)
	var fs := 0.6 * (1.0 + 0.45 * sin(elapsed * 31.0) + dir.y * 0.4)
	flame.scale = Vector3(0.6, 0.6, maxf(fs, 0.1))
	flame.position.y = sin(elapsed * 17.0) * 0.05

	# 无敌闪烁
	player_mesh.visible = invuln <= 0.0 or fmod(invuln, 0.24) < 0.12

	# 主炮：弹列数与射速由机库「主炮」等级决定
	var main_lv: int = maxi(int(save["upgrades"].get("main", 1)), 1)
	fire_cd -= delta
	if fire_cd <= 0.0:
		fire_cd = fire_int
		var cols: Array = []
		if main_lv == 1:
			cols = [0.0]
		elif main_lv <= 3:
			cols = [-0.75, 0.75]
		elif main_lv <= 5:
			cols = [-0.9, 0.0, 0.9]
		elif main_lv <= 7:
			cols = [-1.2, -0.4, 0.4, 1.2]
		else:
			cols = [-1.6, -0.8, 0.0, 0.8, 1.6]
		for off in cols:
			pb.spawn(player.position + Vector3(float(off), 0.2, -3.0), Vector3(0, 0, -BULLET_SPEED), COL_CYAN, 0.42, 1.4)
		if main_lv >= 5:  # 两翼斜射
			for s in [-1.0, 1.0]:
				var v := Vector3(0, 0, -BULLET_SPEED).rotated(Vector3.UP, s * 0.18)
				pb.spawn(player.position + Vector3(s * 1.1, 0.2, -2.4), v, COL_CYAN, 0.38, 1.4)
		SFX.play("eagle_shot", -6.0)

	# 僚机追踪弹
	var wing_lv: int = int(save["upgrades"].get("wing", 0))
	if wing_lv > 0:
		wing_t -= delta
		if wing_t <= 0.0:
			wing_t = 3.0
			for i in mini(wing_lv, 4):
				_spawn_missile(Vector3(player.position.x - 1.6 + 3.2 * float(i), player.position.y, player.position.z))

	if stress and eb.count < 300:
		for i in 6:
			var p := Vector3(randf_range(-16, 16), ENEMY_BULLET_Y, randf_range(-34, -14))
			_spawn_enemy_bullet(p, Vector3(randf_range(-4, 4), 0, randf_range(4, 9)), COL_PINK)


func _spawn_missile(at: Vector3) -> void:
	if missiles.size() >= 6:
		return
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.5, 0.5, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL_YELLOW
	m.material = mat
	n.mesh = m
	add_child(n)
	n.position = at
	missiles.append({"n": n, "vel": Vector3(randf_range(-3, 3), 4.0, -10.0), "life": 4.0})


func _update_missiles(delta: float) -> void:
	var i := 0
	while i < missiles.size():
		var ms: Dictionary = missiles[i]
		ms["life"] = float(ms["life"]) - delta
		var n: Node3D = ms["n"]
		if float(ms["life"]) <= 0.0:
			n.queue_free()
			missiles.remove_at(i)
			continue
		# 追踪最近敌人
		var tgt := Vector3.ZERO
		var best := 1e9
		for e in enemies:
			var gp: Vector3 = e["n"].global_position
			var d := gp.distance_to(n.global_position)
			if d < best:
				best = d
				tgt = gp
		var vel: Vector3 = ms["vel"]
		if best < 1e8:
			var desired := (tgt - n.global_position).normalized() * 26.0
			vel = (vel + (desired - vel) * minf(8.0 * delta, 1.0)).normalized() * 26.0
		ms["vel"] = vel
		n.position += vel * delta
		n.look_at(n.position + vel)
		# 命中检测
		var hit := false
		for e in enemies:
			var gp: Vector3 = e["n"].global_position
			var r := _hit_radius(e["t"])
			if absf(n.position.x - gp.x) < r.x + 0.6 and absf(n.position.z - gp.z) < r.y + 0.6 and absf(n.position.y - gp.y) < 6.0:
				_damage_enemy(e, 3)
				_burst(n.position, COL_YELLOW, 5)
				hit = true
				break
		if hit:
			n.queue_free()
			missiles.remove_at(i)
			continue
		i += 1


func hit_player() -> void:
	if invuln > 0.0 or dead:
		return
	armor -= 1
	damage_taken += 1
	invuln = 1.5
	shake = 0.35
	SFX.play("eagle_hurt")
	_burst(player.position, COL_CYAN, 8)
	if armor <= 0:
		dead = true
		settle_t = 1.3
		_burst(player.position, COL_WHITE, 24)
		_burst(player.position, COL_PINK, 18)
		player.visible = false
		rope.visible = false
		hud_center.text = "坠机！"


func use_bomb() -> void:
	if dead or bombs <= 0:
		return
	bombs -= 1
	invuln = maxf(invuln, 1.6)
	shake = 0.4
	SFX.play("eagle_bomb")
	for i in range(eb.count):
		eb.kill(0)
	var bomb_dmg := 6 + int(save["upgrades"].get("bomb", 0))
	for e in enemies.duplicate():
		_damage_enemy(e, bomb_dmg)
	for i in 26:  # 冲击环
		var a := TAU * float(i) / 26.0
		fx.spawn(player.position + Vector3(0, 0.5, 0), Vector3(cos(a) * 22.0, 0.5, sin(a) * 22.0), COL_CYAN, 0.8, 0.55, 0.0, Vector3.ZERO, true)


func restart() -> void:
	get_tree().reload_current_scene()


# ================= 波次生成 =================

func _spawn_group(list: Array) -> void:
	for ent in list:
		var t: String = ent["t"]
		var x: float = float(ent["x"])
		if t == "E1" or t == "E2":
			_spawn_ground(t, x)
		else:
			var hp: int = {"E3": 3, "E4": 4, "E5": 5, "E6": 40, "E7": 5,
					"E8": 10, "E9": 4, "E10": 24}.get(t, 3)
			_spawn_air(t, x, int(hp), float(ent.get("vx", 0.0)))


func _spawn_ground(type: String, x: float) -> void:
	var n := MeshInstance3D.new()
	n.mesh = _meshes[type]
	n.scale = Vector3.ONE * ENEMY_SCALE
	n.material_override = VoxelModel.shaded_material()
	world.add_child(n)
	# 体素网格以块整数键均值居中（键与几何中心差半格），按 AABB 底面对齐海面后略微下沉
	n.position = Vector3(x, -n.mesh.get_aabb().position.y * ENEMY_SCALE - 0.15,
			-58.0 - world.position.z)
	var e := {"n": n, "t": type, "hp": 4 if type == "E2" else 3, "ft": randf_range(0.8, 1.6), "age": 0.0}
	if type == "E1":  # 炮台：底座 + 可旋转炮头（含炮管，指向玩家）
		var head := MeshInstance3D.new()
		head.mesh = _meshes["E1H"]
		head.material_override = VoxelModel.shaded_material()
		# 炮头底面正好落在底座顶面：按两者 AABB 反推，改模型高度不必再改这里
		# （head 是 n 的子节点，会继承 n 的 0.3 缩放，故这里的局部值不用乘缩放）
		head.position = Vector3(0, n.mesh.get_aabb().end.y - head.mesh.get_aabb().position.y, 0)
		n.add_child(head)
		e["head"] = head
	enemies.append(e)


func _spawn_air(type: String, x: float, hp: int, vx := 0.0) -> Dictionary:
	var n := MeshInstance3D.new()
	n.mesh = _meshes[type]
	n.scale = Vector3.ONE * ENEMY_SCALE
	n.material_override = VoxelModel.shaded_material()
	add_child(n)
	var vz: float = scroll_spd + ({"E3": 10.0, "E4": 5.0, "E6": 1.5, "E7": 2.5, "E8": 2.0,
			"E9": 8.0, "E10": 1.5}.get(type, 3.0))
	n.position = Vector3(x, 4.3, -46.0)  # 空中单位与玩家同一飞行高度层
	var e := {"n": n, "t": type, "hp": hp, "ft": randf_range(0.6, 1.4), "age": 0.0, "vx": vx, "vz": vz, "x0": x, "mode": 0}
	if type in ["E3", "E7"]:  # 旋翼机：旋翼独立成层（E3R/E7R）挂机身顶部，运行时只旋转这一层
		var rotor := MeshInstance3D.new()
		rotor.mesh = _meshes[type + "R"]
		rotor.material_override = VoxelModel.shaded_material()
		# 旋翼层底面落在机身顶面：按两者 AABB 反推（子节点继承 0.3 缩放，局部值不乘）
		rotor.position = Vector3(0, n.mesh.get_aabb().end.y - rotor.mesh.get_aabb().position.y, 0)
		n.add_child(rotor)
		e["rotor"] = rotor
	enemies.append(e)
	return e


func _spawn_survivor(x: float) -> void:
	# 造型统一由 SurvivorUnit 提供（与测试场景共用同一份定义）
	var parts := SurvivorUnit.build()
	var n: Node3D = parts["n"]
	var spot := _survivor_anchor(x)
	world.add_child(n)
	n.position = spot["pos"]
	survivors.append({
		"n": n, "ex": parts["ex"], "arm_l": parts["arm_l"], "arm_r": parts["arm_r"],
		"roping": false, "prog": 0.0, "anchor_y": float(spot["pos"].y),
	})
	rescue_hint_done = true
	hint_t = 3.5
	hud_center.text = "飞到幸存者上方悬停即可施救"


## 幸存者落点：优先锚到前方漂过的地貌顶面（体素岛滩涂 → 暗礁 → 沉船），
## 站在实体上比空海面合理且显眼；没有合适地貌才落空海面（旧行为兜底）。
## 锚定后随世界滚动同步移动；营救起吊以 anchor_y 为立足面（见 _update_survivors）。
func _survivor_anchor(fallback_x: float) -> Dictionary:
	for win in [Vector2(-95.0, -38.0), Vector2(-150.0, -30.0)]:  # 先近后远
		var cands: Array = []
		for isl in islands:
			if isl.has_meta("vox_island") and isl.position.z >= win.x and isl.position.z <= win.y:
				var p := _island_coast_spot(isl)
				if p != Vector3.INF:
					cands.append(p)
		for rf in reefs:
			if rf.position.z >= win.x and rf.position.z <= win.y:
				cands.append(Vector3(rf.position.x, rf.position.y + rf.mesh.get_aabb().end.y, rf.position.z))
		for wk in wrecks:
			if wk.position.z >= win.x and wk.position.z <= win.y:
				cands.append(Vector3(wk.position.x, wk.position.y + wk.mesh.get_aabb().end.y, wk.position.z))
		if not cands.is_empty():
			var pos: Vector3 = cands[randi() % cands.size()]
			return {"pos": pos}
	return {"pos": Vector3(fallback_x, SurvivorUnit.BASE_Y, -50.0)}


## 体素岛滩涂取点：从 .vox 列高表缓存里挑一列低矮岸带（顶面 ≤4 体素），
## 换算到网格局部坐标再经岛屿变换（含随机旋转/缩放）映射到世界；失败返回 INF。
func _island_coast_spot(isl: Node3D) -> Vector3:
	if _island_cols.is_empty():
		var blocks := VoxReader.read_blocks(VOX_DECOR_PATH)
		if blocks.is_empty():
			return Vector3.INF
		for k in blocks:
			var key := Vector2i(k.x, k.z)
			if not _island_cols.has(key) or k.y > int(_island_cols[key]):
				_island_cols[key] = k.y
		var mn := Vector2i(1 << 30, 1 << 30)
		var mx := Vector2i(-(1 << 30), -(1 << 30))
		for key in _island_cols:
			mn = Vector2i(mini(mn.x, key.x), mini(mn.y, key.y))
			mx = Vector2i(maxi(mx.x, key.x), maxi(mx.y, key.y))
		_island_cols_mn = mn
		_island_cols_mx = mx
	var coast: Array = []
	for key in _island_cols:
		if int(_island_cols[key]) <= 3:  # 滩涂带：低矮沿海列（不含山峰）
			coast.append(key)
	if coast.is_empty():
		return Vector3.INF
	var k: Vector2i = coast[randi() % coast.size()]
	var cx := (_island_cols_mn.x + _island_cols_mx.x + 1) * 0.5
	var cz := (_island_cols_mn.y + _island_cols_mx.y + 1) * 0.5
	var maxh := 0
	for key2 in _island_cols:
		maxh = maxi(maxh, int(_island_cols[key2]))
	# 网格以块 AABB 中心为原点：局部单位坐标 = 键 + 0.5 - 中心（y 用整岛列高范围）
	# 世界偏移手动换算（体素×0.1 + 随机朝向旋转），不经过节点 transform——
	# 编辑器导入路径节点 scale=1（已烘焙）、运行时路径 scale=0.1，走 to_global 两条路不一致
	var local := Vector3(k.x + 0.5 - cx, float(int(_island_cols[k]) + 1) - float(maxh + 1) * 0.5,
			k.y + 0.5 - cz)
	var off := (local * VOX_DECOR_SCALE).rotated(Vector3.UP, isl.rotation.y)
	return isl.position + off + Vector3(0, 0.02, 0)


func _spawn_boss() -> void:
	var n := MeshInstance3D.new()
	# MagicaVoxel 体素舰（.vox 运行时解析）；缺失时退化为占位方块保持流程可跑
	var vox_mesh := VoxReader.read_mesh("res://assets/vox/units/boss.vox")
	if vox_mesh != null and vox_mesh.get_surface_count() > 0:
		n.mesh = vox_mesh
		n.scale = Vector3.ONE * 0.5  # 17×24×6 体素 × 0.5 ≈ 8.5×12×3
	else:
		push_warning("Boss .vox 加载失败，使用占位方块")
		var fm := BoxMesh.new()
		fm.size = Vector3(8.5, 3.0, 12.0)
		n.mesh = fm
	boss_mat = VoxelModel.shaded_material()
	n.material_override = boss_mat
	add_child(n)
	n.position = Vector3(0, 0.12, -46.0)
	var hp_max := int(stage_def["boss_hp"])
	boss = {"n": n, "t": "BOSS", "hp": hp_max, "hp_max": hp_max, "age": 0.0, "phase": 1, "entering": true, "mode": 0, "act_t": 2.5, "burst_left": 0, "burst_t": 0.0, "sp_t": 0.0, "spiral_a": 0.0, "ring_t": 2.0, "add_t": 5.0, "laser_t": 4.0}
	enemies.append(boss)


# ================= 敌人更新 =================

func _update_enemies(delta: float) -> void:
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		e["age"] = float(e["age"]) + delta
		var n: Node3D = e["n"]
		var gp := n.global_position
		if float(e["age"]) > 2.0 and (gp.z > 26.0 or gp.z < -70.0):  # 逃逸/异常回收
			if not bool(e.get("add", false)):
				escaped += 1  # 计入歼灭奖牌（Boss 战增援除外）
			n.queue_free()
			enemies.remove_at(i)
			continue
		match e["t"]:
			"E1":
				var head: Node3D = e["head"]
				head.look_at(Vector3(player.position.x, head.global_position.y, player.position.z))
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -34.0 and gp.z < 6.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 2.2
					_fire_aimed(head.global_position + Vector3(0, 1.0, 0), 8.0, 3, 14.0)
			"E2":
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -34.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 2.7
					_fire_ring(gp, 14, 6.2, float(e["age"]))
					_fire_ring(gp, 14, 7.6, float(e["age"]) + 0.22)
			"E3":
				n.position += Vector3(float(e["vx"]), 0, float(e["vz"])) * delta
				var rotor: Node3D = e.get("rotor")
				if rotor != null:
					rotor.rotate_y(delta * 14.0)  # 只转旋翼层：机身朝向稳定，旋翼转得快也读得出机型
			"E7":
				# 武装直升机：缓慢下压 + 正弦侧移，双管机炮对玩家短点射
				n.position.x = clampf(float(e["x0"]) + sin(float(e["age"]) * 1.1) * 5.0, -13.0, 13.0)
				n.position.z += float(e["vz"]) * delta
				var heli_rotor: Node3D = e.get("rotor")
				if heli_rotor != null:
					heli_rotor.rotate_y(delta * 12.0)  # 主旋翼比无人机略慢一档
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -44.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 2.4
					_fire_aimed(n.global_position, 7.5, 2, 20.0)
			"E8":
				# 飞翼轰炸机：缓慢直压，定期向四周散布慢速炸弹（投弹）
				n.position.z += float(e["vz"]) * delta
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -40.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 3.2
					_fire_ring(gp, 8, 4.5, float(e["age"]))
			"E9":
				# 双体炮艇：快速冲撞 + 前向点射压制
				n.position += Vector3(float(e["vx"]) * 0.6, 0, float(e["vz"])) * delta
				e["ft"] = float(e["ft"]) - delta
				if float(e["ft"]) <= 0.0:
					e["ft"] = 1.8
					_fire_aimed(n.global_position, 6.5, 1, 0.0)
			"E10":
				# 浮空盾堡：极缓推进 + 微幅横移，环形弹幕与自机狙交替（小 boss 级）
				n.position.z += float(e["vz"]) * delta
				n.position.x = float(e["x0"]) + sin(float(e["age"]) * 0.5) * 2.0
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -40.0 and gp.z < 8.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 2.0
					e["mode"] = 1 - int(e["mode"])
					if int(e["mode"]) == 1:
						_fire_ring(gp, 12, 6.0, float(e["age"]))
					else:
						_fire_aimed(gp, 7.0, 3, 16.0)
			"E4":
				n.position += Vector3(float(e["vx"]) * 0.2 + sin(float(e["age"]) * 2.0) * 1.5, 0, float(e["vz"])) * delta
				e["ft"] = float(e["ft"]) - delta
				if float(e["ft"]) <= 0.0:
					e["ft"] = 2.6
					_fire_aimed(n.global_position, 7.0, 1, 0.0)
			"E5":
				n.position.x = float(e["x0"]) + sin(float(e["age"]) * 1.35) * 7.0
				n.position.z += float(e["vz"]) * delta
				e["ft"] = float(e["ft"]) - delta
				if float(e["ft"]) <= 0.0:
					e["ft"] = 1.9
					_fire_aimed(n.global_position, 7.5, 5, 42.0)
			"E6":
				# 精英炮舰：缓慢推进，濒死（hp<40%）加速逃逸；自机狙/环形交替
				var boost := 6.0 if int(e["hp"]) < 16 else 0.0
				n.position.z += (float(e["vz"]) + boost) * delta
				n.position.x = float(e["x0"]) + sin(float(e["age"]) * 0.7) * 3.0
				e["ft"] = float(e["ft"]) - delta
				if gp.z > -34.0 and gp.z < 6.0 and float(e["ft"]) <= 0.0:
					e["ft"] = 2.2
					e["mode"] = 1 - int(e["mode"])
					if int(e["mode"]) == 1:
						_fire_aimed(gp, 8.0, 3, 14.0)
					else:
						_fire_ring(gp, 10, 6.5, float(e["age"]))
			"BOSS":
				_update_boss(e, n, delta)
		i += 1


func _update_boss(e: Dictionary, n: Node3D, delta: float) -> void:
	if bool(e["entering"]):
		n.position.z = move_toward(n.position.z, -14.0, 12.0 * delta)
		if n.position.z >= -14.0:
			e["entering"] = false
			hud_boss.visible = true
		return
	e["age"] = float(e["age"]) + delta
	n.position.x = sin(float(e["age"]) * 0.5) * 6.0
	var frac := float(e["hp"]) / float(e["hp_max"])
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
		1:  # 5 向扇形 ×3 波 ↔ 自机狙 3 连，交替
			e["act_t"] = float(e["act_t"]) - delta
			if float(e["act_t"]) <= 0.0 and int(e["burst_left"]) <= 0:
				e["act_t"] = 4.0 / boss_pace
				e["burst_left"] = 3
				e["burst_t"] = 0.0
			if int(e["burst_left"]) > 0:
				e["burst_t"] = float(e["burst_t"]) - delta
				if float(e["burst_t"]) <= 0.0:
					e["burst_t"] = 0.38
					e["burst_left"] = int(e["burst_left"]) - 1
					if int(e["mode"]) == 0:
						_fire_aimed(bp, 7.5, 5, 46.0)
					else:
						_fire_aimed(bp, 8.0, 3, 14.0)
		2:  # 无人机增援 + 横扫激光 + 轻自机狙
			e["add_t"] = float(e["add_t"]) - delta
			if float(e["add_t"]) <= 0.0:
				e["add_t"] = 6.0 / boss_pace
				for s in [-1.0, 1.0]:
					var add := _spawn_air("E3", bp.x + s * 4.0, 3, s * randf_range(2.0, 4.0))
					add["add"] = true
			e["laser_t"] = float(e["laser_t"]) - delta
			if float(e["laser_t"]) <= 0.0 and int(laser["st"]) == 0:
				e["laser_t"] = 5.0 / boss_pace
				_fire_laser(bp)
			e["act_t"] = float(e["act_t"]) - delta
			if float(e["act_t"]) <= 0.0:
				e["act_t"] = 2.4 / boss_pace
				_fire_aimed(bp, 8.0, 1, 0.0)
		3:  # 双螺旋 + 环形
			e["sp_t"] = float(e["sp_t"]) - delta
			if float(e["sp_t"]) <= 0.0:
				e["sp_t"] = 0.12 / boss_pace
				var a0 := float(e["spiral_a"])
				for arm in 2:
					var a := a0 + PI * float(arm)
					_spawn_enemy_bullet(Vector3(bp.x, ENEMY_BULLET_Y, bp.z), Vector3(sin(a) * 6.5, 0, cos(a) * 6.5), COL_PINK)
				e["spiral_a"] = a0 + 0.38
			e["ring_t"] = float(e["ring_t"]) - delta
			if float(e["ring_t"]) <= 0.0:
				e["ring_t"] = 3.0 / boss_pace
				_fire_ring(bp, 16, 7.5, float(e["age"]))


func _boss_phase_change(e: Dictionary, ph: int) -> void:
	e["phase"] = ph
	e["act_t"] = 1.6
	e["burst_left"] = 0
	for i in range(eb.count):  # 阶段切换清屏
		eb.kill(0)
	SFX.play("eagle_boss_phase")
	_burst(e["n"].global_position, COL_WHITE, 16)
	_burst(e["n"].global_position, COL_PINK, 12)
	shake = 0.4
	# 毁伤外观：材质逐渐泛红
	var tint := 1.0 - 0.22 * float(ph - 1)
	boss_mat.albedo_color = Color(1.0, tint, tint * 0.95)


func _fire_laser(from: Vector3) -> void:
	var org := from + Vector3(0, 0.5, 0)
	var dir := (player.position + Vector3(0, -0.4, 0) - org).normalized()
	laser["org"] = org
	laser["dir"] = dir
	laser["st"] = 1
	laser["t"] = 0.7
	SFX.play("eagle_laser")
	var ln: float = laser["len"]
	laser_warn.visible = true
	_laser_pose(laser_warn, org, dir, ln)
	laser_beam.visible = false


func _laser_pose(node: MeshInstance3D, org: Vector3, dir: Vector3, ln: float) -> void:
	node.position = org + dir * (ln * 0.5)
	node.look_at(org + dir * ln)


func _update_laser(delta: float) -> void:
	var st := int(laser["st"])
	if st == 0:
		return
	laser["t"] = float(laser["t"]) - delta
	if st == 1:
		if float(laser["t"]) <= 0.0:
			laser["st"] = 2
			laser["t"] = 0.8
			laser_warn.visible = false
			laser_beam.visible = true
			_laser_pose(laser_beam, laser["org"], laser["dir"], laser["len"])
	elif st == 2:
		if not dead and invuln <= 0.0:
			var p_rel: Vector3 = player.position - laser["org"]
			var dir: Vector3 = laser["dir"]
			var tt: float = clampf(p_rel.dot(dir), 0.0, laser["len"])
			var closest: Vector3 = laser["org"] + dir * tt
			if player.position.distance_to(closest) < 1.2:
				hit_player()
		if float(laser["t"]) <= 0.0:
			laser["st"] = 0
			laser_beam.visible = false


func _hit_radius(t: String) -> Vector2:
	if t == "BOSS":
		return Vector2(7.0, 3.4)
	if t == "E6":
		return Vector2(2.6, 2.0)
	if t == "E5" or t == "E2":
		return Vector2(1.7, 1.7)
	return Vector2(1.3, 1.3)


func _damage_enemy(e: Dictionary, dmg: int) -> void:
	if e["t"] == "BOSS":
		if bool(e["entering"]) or phase == PH_VICTORY:
			return
		e["hp"] = int(e["hp"]) - dmg
		if int(e["hp"]) <= 0:
			_boss_die(e)
		return
	e["hp"] = int(e["hp"]) - dmg
	if e["hp"] <= 0:
		var n: Node3D = e["n"]
		var gp := n.global_position
		_burst(gp, COL_PINK, 12)
		_burst(gp, COL_WHITE, 6)
		SFX.play("eagle_boom")
		var reward: int = {"E1": 5, "E2": 8, "E3": 3, "E4": 3, "E5": 10, "E6": 40}.get(e["t"], 5)
		var pts: int = {"E1": 50, "E2": 80, "E3": 30, "E4": 50, "E5": 100, "E6": 500}.get(e["t"], 50)
		score += pts
		for s in reward:
			var v := Vector3(randf_range(-6, 6), randf_range(3, 8), randf_range(-4, 4))
			pickups.spawn(gp + Vector3(0, 0.5, 0), v, COL_YELLOW, 0.85, STAR_LIFE, 16.0)
		stars_spawned += reward
		if e["t"] == "E6":  # 精英炮舰必掉炸弹补给
			supplies.spawn(gp + Vector3(0, 0.8, 0), Vector3(randf_range(-3, 3), randf_range(4, 7), randf_range(-2, 2)), COL_CYAN, 1.15, 12.0, 14.0)
		n.queue_free()
		enemies.erase(e)


func _boss_die(e: Dictionary) -> void:
	var gp: Vector3 = e["n"].global_position
	_burst(gp, COL_WHITE, 26)
	_burst(gp, COL_PINK, 22)
	_burst(gp, COL_YELLOW, 18)
	SFX.play("eagle_boom", 3.0)
	score += 2000
	for s in 100:  # 星星喷泉
		var v := Vector3(randf_range(-10, 10), randf_range(6, 14), randf_range(-8, 8))
		pickups.spawn(gp + Vector3(0, 1.0, 0), v, COL_YELLOW, 0.85, STAR_LIFE, 16.0)
	stars_spawned += 100
	e["n"].queue_free()
	enemies.erase(e)
	boss = {}
	hud_boss.visible = false
	laser_beam.visible = false
	laser_warn.visible = false
	laser["st"] = 0
	shake = 0.5
	phase = PH_VICTORY
	settle_t = 1.8


# ================= 幸存者救援 =================

func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _update_survivors(delta: float) -> void:
	var i := 0
	var ring_prog := -1.0            # <0 = 本帧无营救，需隐藏进度圈
	while i < survivors.size():
		var s: Dictionary = survivors[i]
		var n: Node3D = s["n"]
		var gp := n.global_position
		if gp.z > 24.0:  # 滚出屏幕 = 错过
			n.queue_free()
			survivors.remove_at(i)
			continue
		var d := _xz_dist(gp, player.position)
		var ex: MeshInstance3D = s["ex"]
		ex.visible = d < 8.0 and not bool(s["roping"])
		SurvivorUnit.mark_bob(ex, elapsed)
		# 双手高举挥动呼叫（攀爬时停止挥手改为抱绳姿态）
		SurvivorUnit.pose(s["arm_l"], s["arm_r"], elapsed, bool(s["roping"]))
		if bool(s["roping"]):
			if d > SurvivorUnit.RESCUE_LEAVE or dead:  # 离开范围 → 绳索收回（不惩罚）
				s["roping"] = false
				s["prog"] = 0.0
				SurvivorUnit.reset_rescue(n, float(s["anchor_y"]))
				rope.visible = false
			else:
				# 幸存者停止随地面滚动，原地等玩家悬停拉起
				n.position.z -= scroll_spd * delta
				s["prog"] = float(s["prog"]) + delta / SurvivorUnit.RESCUE_TIME
				var prog := float(s["prog"])
				if SurvivorUnit.apply_rescue_progress(n, prog, float(s["anchor_y"])):
					rescued += 1
					score += 1000
					SFX.play("eagle_rescue")   # 救起音效：C5-E5-G5-C6 上行琶音
					_burst(gp, COL_WHITE, 10)
					rope.visible = false
					ring_prog = 1.0            # 进度圈填满（保留 0.3s 闪一下）
					ring_flash_t = RescueRing.FLASH_TIME
					n.queue_free()
					survivors.remove_at(i)
					continue
				ring_prog = prog
				_rope_pose(gp)
		else:
			if d < SurvivorUnit.RESCUE_TRIGGER and not dead:
				s["roping"] = true
				s["prog"] = 0.0
				ring_prog = 0.0
		i += 1
	_update_rescue_ring(ring_prog, delta)


## 进度圈刷新：营救中实时填充；救起后保留 FLASH_TIME 显示满圈；其余时间隐藏
func _update_rescue_ring(prog: float, delta: float) -> void:
	if rescue_ring == null:
		return
	if prog >= 0.0:
		ring_flash_t = 0.0 if prog < 1.0 else ring_flash_t
		rescue_ring.visible = true
	elif ring_flash_t > 0.0:
		ring_flash_t -= delta
		prog = 1.0
		if ring_flash_t <= 0.0:
			rescue_ring.visible = false
			return
	else:
		rescue_ring.visible = false
		return
	RescueRing.aim(rescue_ring, cam, player.global_position)
	RescueRing.set_progress(rescue_ring, clampf(prog, 0.0, 1.0))


func _rope_pose(sur_gp: Vector3) -> void:
	var rp := SurvivorUnit.rope_pose(sur_gp, player.position)
	rope.global_transform = rp["xf"]
	rope.scale = Vector3(1, 1, rp["len"])


# ================= 弹型库 =================

func _spawn_enemy_bullet(p: Vector3, v: Vector3, col: Color) -> void:
	eb.spawn(p, v, col, 0.62, 8.0)
	eb.spawn(p, v, COL_WHITE, 0.3, 8.0)  # 白色内核提升可读性


func _fire_aimed(from: Vector3, speed: float, n: int, spread_deg: float) -> void:
	var to_p := player.position - from
	to_p.y = 0.0
	var base := atan2(to_p.x, -to_p.z)  # 屏面上朝向玩家的方位角
	for k in n:
		var off := 0.0 if n == 1 else spread_deg * PI / 180.0 * (float(k) / float(n - 1) - 0.5)
		var a := base + off
		_spawn_enemy_bullet(Vector3(from.x, ENEMY_BULLET_Y, from.z), Vector3(sin(a) * speed, 0, -cos(a) * speed), COL_PINK)


func _fire_ring(from: Vector3, n: int, speed: float, phase_off := 0.0) -> void:
	for k in n:
		var a := TAU * float(k) / float(n) + phase_off
		_spawn_enemy_bullet(Vector3(from.x, ENEMY_BULLET_Y, from.z), Vector3(sin(a) * speed, 0, cos(a) * speed), COL_PINK)


# ================= 子弹 / 星星 / 补给 / 碎片 =================

func _update_bullets(_delta: float) -> void:
	pb.update(_delta)
	eb.update(_delta)

	# 自机弹 × 敌人
	var i := 0
	while i < pb.count:
		var hit := false
		for e in enemies:
			var gp: Vector3 = e["n"].global_position
			var r := _hit_radius(e["t"])
			if absf(pb.pos[i].x - gp.x) < r.x and absf(pb.pos[i].z - gp.z) < r.y:
				_damage_enemy(e, 1)
				fx.spawn(pb.pos[i], Vector3(0, 2, 4), COL_WHITE, 0.3, 0.14, 0.0, Vector3.ZERO, true)
				hit = true
				break
		if hit:
			pb.kill(i)
		else:
			i += 1

	# 敌弹 × 玩家
	if not dead:
		i = 0
		while i < eb.count:
			var d: Vector3 = eb.pos[i] - player.position
			if absf(d.x) < 0.95 and absf(d.z) < 0.95 and absf(d.y) < 1.2:
				eb.kill(i)
				hit_player()
				if dead:
					break
			else:
				i += 1

	# 敌机撞击
	if not dead:
		for e in enemies:
			if e["t"] == "E3":
				var gp3: Vector3 = e["n"].global_position
				if absf(gp3.x - player.position.x) < 1.6 and absf(gp3.z - player.position.z) < 1.6:
					hit_player()


func _update_pickups(delta: float) -> void:
	pickups.update(delta)
	var i := 0
	while i < pickups.count:
		# 落海弹跳 + 随地面滚动
		if pickups.pos[i].y < 0.45 and pickups.vel[i].y < 0.0:
			pickups.vel[i].y = absf(pickups.vel[i].y) * 0.35
			if pickups.vel[i].y < 1.0:
				pickups.vel[i].y = 0.0
				pickups.vel[i].z = scroll_spd
		# 磁吸（半径由机库「磁铁」等级决定；按 XZ 平面距离，星星会飞升到飞行高度）
		var d: Vector3 = player.position - pickups.pos[i]
		var dist_xz: float = Vector2(d.x, d.z).length()
		if dist_xz < magnet_r and not dead:
			pickups.vel[i] = d.normalized() * clampf(26.0 - dist_xz * 2.0, 8.0, 26.0)
			pickups.vel[i].y *= 0.4
		if dist_xz < 1.7 and not dead:
			pickups.kill(i)
			star_cnt += 1
			score += 10
			SFX.play("eagle_star", -4.0)
			continue
		if pickups.pos[i].z > 26.0:
			pickups.kill(i)
			continue
		i += 1


func _update_supplies(delta: float) -> void:
	supplies.update(delta)
	var i := 0
	while i < supplies.count:
		if supplies.pos[i].y < 0.8 and supplies.vel[i].y < 0.0:
			supplies.vel[i].y = absf(supplies.vel[i].y) * 0.3
			if supplies.vel[i].y < 1.0:
				supplies.vel[i].y = 0.0
				supplies.vel[i].z = scroll_spd
		var d: Vector3 = player.position - supplies.pos[i]
		var dist_xz: float = Vector2(d.x, d.z).length()
		if dist_xz < magnet_r + 2.0 and not dead:
			supplies.vel[i] = d.normalized() * clampf(24.0 - dist_xz, 8.0, 24.0)
		if dist_xz < 2.0 and not dead:
			supplies.kill(i)
			if bombs < bombs_max:
				bombs += 1
			else:
				score += 200  # 满弹拾取折算分数
			SFX.play("item_get")
			continue
		if supplies.pos[i].z > 26.0:
			supplies.kill(i)
			continue
		i += 1


func _burst(at: Vector3, col: Color, n: int) -> void:
	for k in n:
		var v := Vector3(randf_range(-9, 9), randf_range(2, 11), randf_range(-9, 9))
		fx.spawn(at + Vector3(0, 0.4, 0), v, col, randf_range(0.35, 0.65), randf_range(0.4, 0.7), 24.0, Vector3(2, 3, 0), true)


# ================= 结算 =================

func _show_settlement(p_victory: bool) -> void:
	phase = PH_OVER
	victory = p_victory
	hud_center.text = ""
	SFX.play("eagle_win" if p_victory else "eagle_lose")
	# 星星入账：场上剩余星星一并回收，通关全额入账，坠机折半
	star_cnt += pickups.count
	var banked := int(star_cnt * 0.5) if not p_victory else star_cnt
	save["stars"] = int(save["stars"]) + banked
	var key := str(stage_id)
	var medals: Array = []
	if p_victory:
		if escaped == 0:
			medals.append("kill")
		if rescued >= survivor_total:
			medals.append("rescue")
		if stars_spawned > 0 and float(star_cnt) >= float(stars_spawned) * 0.95:
			medals.append("star")
		if damage_taken == 0:
			medals.append("perfect")
		var got: Array = save["medals"].get(key, [])
		for m in medals:
			if not got.has(m):
				got.append(m)
		save["medals"][key] = got
	var prev_best: int = save["best"].get(key, 0)
	if score > prev_best:
		save["best"][key] = score
		prev_best = score
	SaveManager.save_data(save)

	settle_title.text = "%s · 任务完成！" % stage_name if p_victory else "%s · 任务失败" % stage_name
	var ratio := 100.0 if stars_spawned == 0 else float(star_cnt) / float(stars_spawned) * 100.0
	settle_lines.text = "得分 %d    最高 %d\n星星收益 +%d ★（%s）\n逃逸敌机 %d    幸存者 %d/%d    星星 %.0f%%" % [
		score, prev_best, banked, "通关全额" if p_victory else "坠机折半", escaped, rescued, survivor_total, ratio]
	settle_medals.text = "[歼灭者] %s    [救援英雄] %s\n[星光收集者] %s    [完璧] %s" % [
		"达成" if medals.has("kill") else "未达成",
		"达成" if medals.has("rescue") else "未达成",
		"达成" if medals.has("star") else "未达成",
		"达成" if medals.has("perfect") else "未达成"]
	settle_unlock.text = ""
	if p_victory and stage_id < 3 and not Stages.is_unlocked(save, stage_id + 1):
		settle_unlock.text = "下一关需更多奖牌：回本关继续刷（歼灭 / 救援 / 星光 / 完璧）"
	settle_root.visible = true
	_refresh_hangar()


# ================= 相机 / HUD / 输入 =================

func _update_camera(_delta: float) -> void:
	var target := Vector3(player.position.x * 0.62, 0, -3.0)
	var off: Vector3
	match cam_mode:
		0:
			var pitch := deg_to_rad(68.0)
			off = Vector3(0, 40.0 * sin(pitch), 40.0 * cos(pitch))
		1:
			off = Vector3(0, 42.0, 0.01)
		2:
			# 等距机位：标准 isometric（偏移 1:1:1，俯角 35.26°），与 unit_review 审查姿态一致
			off = Vector3(28.0, 28.0, 28.0)
	cam.position = target + off
	if shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 1.6
	cam.look_at(target)


func _refresh_hud() -> void:
	hud_score.text = "【%s】SCORE %d    ★ %d（+%d）    BOMB %d/%d" % [stage_name, score, int(save["stars"]), star_cnt, bombs, bombs_max]
	hud_armor.text = "护甲 " + "■".repeat(maxi(armor, 0)) + "□".repeat(maxi(armor_max - armor, 0)) + "    救援 %d/%d    歼灭 %d" % [rescued, survivor_total, escaped]
	hud_info.text = "FPS %d  敌弹 %d  F1/F2/F5 相机[68°/90°/等距]  F3 阴影[%s]  F4 压测[%s]  Esc 暂停  H 机库" % [
		Engine.get_frames_per_second(), eb.count, "开" if sun.shadow_enabled else "关", "开" if stress else "关"]
	if boss.is_empty() or bool(boss.get("entering", true)):
		hud_boss.visible = false
	else:
		hud_boss.visible = true
		var frac := float(boss["hp"]) / float(boss["hp_max"])
		var bars := int(ceil(frac * 12.0))
		hud_boss.text = "方舟战舰 " + "■".repeat(bars) + "□".repeat(12 - bars) + " %d%%" % int(frac * 100.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		var settle_open := settle_root.visible
		var hangar_open := hangar_root.visible
		if select_root.visible:
			if key == KEY_ESCAPE:
				_go_menu()
			return  # 选关界面只响应 Esc 和鼠标
		match key:
			KEY_F1:
				cam_mode = 0
			KEY_F2:
				cam_mode = 1
			KEY_F5:
				cam_mode = 2
			KEY_F3:
				sun.shadow_enabled = not sun.shadow_enabled
			KEY_F4:
				stress = not stress
			KEY_H:
				if hangar_open:
					_close_hangar()
				else:
					hangar_from = "settle" if settle_open else "pause"
					if settle_open:
						settle_root.visible = false
					paused = true
					_refresh_hangar()
					hangar_root.visible = true
			KEY_S:
				if settle_open or paused:
					_back_to_select()
			KEY_ESCAPE:
				if hangar_open:
					_close_hangar()
				elif settle_open:
					pass  # 结算层 Esc 不响应（用 Q/R/S/H）
				elif dead or phase == PH_OVER:
					_go_menu()
				else:
					paused = not paused
					hud_center.text = "已暂停  Esc 继续 · R 重开 · S 选关 · H 机库 · Q 大厅" if paused else ""
			KEY_R:
				if settle_open or paused:
					restart()
			KEY_Q:
				if settle_open or paused:
					_go_menu()
			KEY_SPACE:
				if not paused and not hangar_open and not settle_open:
					use_bomb()
