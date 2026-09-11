extends Node3D
## 瓦片雄鹰 M1：瓦片滚动走廊 + 玩家机飞行的对照实验小场景（M1 起逐步接入玩法）。
##
## 架构（llmdoc/tile-eagle-design.html §3）：瓦片本体 assets/vox/tiles/*.vox →
## 排布层 layout.gd（节奏表 + 图章 + 种子）→ 渲染层本文件（按种类分组 MultiMesh + 行回绕）。
## 环境参数照抄方块雄鹰关 1（碧海突袭），保证两作并排对比时同相机同色板同光照。
##
## M1 第一步（design §14）：① 岛/沙洲做大做稀（layout 节奏表 + island_4x4/sandbar_2x2）；
## ② 空域与云层整体拉高（altitude.gd）。两者都是**表现层**改动，判定仍在 XZ 平面。

const Tiles = preload("res://scripts/tile_eagle/tiles.gd")
const Layout = preload("res://scripts/tile_eagle/layout.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const PlayerSc = preload("res://scripts/tile_eagle/player.gd")
const Altitude = preload("res://scripts/tile_eagle/altitude.gd")
const Combat = preload("res://scripts/tile_eagle/combat.gd")
const WaterShader = preload("res://scripts/tile_eagle/water.gdshader")

const SCROLL := 7.0                    # 与方块雄鹰关 1 相同

# 可见窗口几何（design §14.2 重新标定）。两条约束决定这两个数：
# ① **释放**：行 0（最近端）的瓦必须在屏幕下缘（地面 z = +16）之外消失
#    → NEAR_ROWS·TILE − TILE/2 > 16，NEAR_ROWS ≥ 4（取 5，留 5.6 单位余量）；
# ② **生成**：跨度 span 的超级瓦在远端生成时整块必须在屏幕上缘（z = −22）之外，
#    因为超级瓦的块中心挂在"记录行 + (span−1)/2"，记录行越远越安全：
#    (NEAR_ROWS − VIS_ROWS + span)·TILE ≤ −22  →  VIS_ROWS ≥ NEAR_ROWS + span + 4.59
#    （span=4 的主岛 → 需 14；M0 的 span=2 配 12 行其实差 0.6 行，2×2 岛在屏幕最上缘
#     会露出一条边，本轮一并修掉）
const VIS_ROWS := 14                   # 在场行数（含屏幕外的预生成行）
const NEAR_ROWS := 5.0                 # 行 0 的 z = +5T：释放也发生在屏幕下缘之外

# 云层（altitude.gd 的 CLOUD_LO/HI 定高度；本处只管漂移与回收带）
const CLOUD_N := 3
const CLOUD_PARALLAX := 0.3            # 云相对地面的视差系数（慢于地面 → 远景感）
# 回收带必须**贴着可见带**：正交 68° 下高度 h 的可见 z 区间是 [0.5h−22, 0.5h+16]，
# 云在 22~30 高时即 [−9, +30]。M0 把云从 +30 直接扔回 −240，导致云九成时间在屏幕外
# 空飞（M0 截图里几乎看不到云，就是这个原因）——现在回收带收缩到 42 单位。
# 注意：68° 正交下天空层**必然横穿整个画面**（高度 h 等价于把地面物体平移 +0.5h），
# 做不到"只出现在天边"；所以云只能靠低透明度与小块数当轻微的空气层，不能当主视觉。
const CLOUD_Z_START := -14.0           # 首帧云带起点（让至少一团落在屏幕内）
const CLOUD_Z_NEAR := 28.0             # 越过此 z 即回收（此时云已滑出屏幕下缘）
const CLOUD_Z_SPAN := 42.0             # 回收后的行程长度 → 云新位置 z = 越过点 − 42
## 云的 x 用固定展开 + 小抖动（而不是各自随机撒）：随机撒样会把两三团叠到同一列，
## 叠出来的灰板比单团大得多、也更容易被当成"贴图错误"。
const CLOUD_X_SPREAD: Array[float] = [-16.0, 3.0, 20.0]

## 水面动感幅度（water.gdshader 的两个 uniform）。**主力是 sheen（亮度行波）不是 wave_amp**：
## 正交俯视下垂直位移几乎不可见（它位移的是一片没有纹理的连续水面，颜色图案是钉在几何上的）
## —— wave_amp 只负责"水面相对静止的岛在动"，看得见的流动感全靠 sheen。
## 对照按 V 键（两个一起归零，才是干净的 A/B）。
const WAVE_AMP := 0.055
const WAVE_SHEEN := 0.30

# 关 1「碧海突袭」主题色板（stages.gd）
const COL_SKY := Color("050810")
const COL_FOG := Color("0a2540")
const COL_AMBIENT := Color("223050")
const COL_SUN := Color("fff2e0")
const COL_CYAN := Color("00f0ff")
const COL_PINK := Color("ff2a6d")

var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var player: Node3D
var layout: RefCounted
var hud: Label
var combat: Node3D                     # M1 玩法最小集（弹幕/敌机/计分/死亡）

var cam_mode := 0                      # 0=68° 斜俯视 1=90° 纯俯视 2=等距
var paused := false
var wire := false
var clouds_on := true
var hud_center: Label
var water_mat: ShaderMaterial            # 水面材质（water.gdshader，所有水瓦共用一份）
var wave_on := true                      # V 键开关（出图对照用）
## 滚动速度（世界单位/秒）。战斗层要拿它给地面单位定 vz（与地貌严格同步），故做成变量。
var scroll_spd := SCROLL

# 渲染层状态
var mmis := {}                         # kind -> MultiMeshInstance3D
var free_slots := {}                   # kind -> Array[int] 自由槽栈
var row_slots: Array = []              # row_slots[j] = 第 j 行（z=(NEAR-j)*TILE）的 [{kind, slot}]
var world_z := 0.0
var abs_row := VIS_ROWS - 1            # 远端刚生成那一行的绝对行号（内容取 rows[abs_row % ROWS]）
var wire_mesh: MeshInstance3D
var clouds: Array = []
var _cloud_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_env()
	_build_tiles()
	_build_clouds()
	_build_player()
	_build_combat()
	_build_hud()


# ================= 场景构建 =================

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = COL_AMBIENT
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = 1                      # DEPTH
	env.fog_light_color = COL_FOG
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 170.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = COL_SUN
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 0       # ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	# 影子不透明度 0.62：**这是拉高空域的连带修正**。方向上影子与物体的屏幕错位是 0.40·h，
	# M0 的空域只有 4.5（错位 1.8 单位）看不出问题；拉高到 AIR 7.5 / HIGH 11.5 之后，
	# 精英单位的影子被推到 4.6 单位外，而阴影区只剩环境光（0x223050 × 深海色 ≈ RGB(1,7,20)）
	# → 在水面上读成一个纯黑的"洞"（出图一看就废）。降 opacity 让影子变成柔和的暗块：
	# 层次感（"看得见飞得高"）靠的是影子的**错位量**，不是它的深浅。
	sun.shadow_opacity = 0.62
	add_child(sun)

	cam = Camera3D.new()
	cam.projection = 1                    # ORTHOGONAL
	cam.size = 34.0                       # 与方块雄鹰一致
	cam.near = 0.5
	cam.far = 300.0
	add_child(cam)
	cam.position = Vector3(0, 30, 12)
	cam.look_at(Vector3.ZERO)

	world = Node3D.new()
	world.name = "World"
	add_child(world)


func _build_tiles() -> void:
	layout = Layout.new()
	layout.build()
	row_slots.resize(VIS_ROWS)
	for j in VIS_ROWS:
		row_slots[j] = []
	var zero_t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	# 每类实例容量按布局实际峰值分配（不足则补 1，避免空 MultiMesh）
	var need := {}
	for r in Layout.ROWS:
		for cell in layout.rows[r]:
			need[cell.tile] = int(need.get(cell.tile, 0)) + 1
	# 整条走廊的包围盒：MultiMesh 逐实例散布上百单位，不设 custom_aabb 会被视锥误剔除
	# （M0 踩坑 ①）。范围按「最近端 + 最远端」算，别按行数硬写，否则上缘会缺一截。
	var half_x := float(Layout.COLS) * Tiles.TILE * 0.5 + 4.0
	var z_far := -(NEAR_ROWS + float(VIS_ROWS) + 6.0) * Tiles.TILE
	var z_near := (NEAR_ROWS + 6.0) * Tiles.TILE
	var aabb := AABB(Vector3(-half_x, -1.0, z_far),
			Vector3(half_x * 2.0, 14.0, z_near - z_far))
	# 瓦片材质：**全部瓦片共用这一份** ShaderMaterial（water.gdshader）。水面/陆地的区分
	# 在 shader 里按「朝上的面 × 世界 y < 水位线」完成 —— 岛/礁/沙洲的 z=0 层就是水面板，
	# 于是岛周围那圈水也跟着整片海一起起伏，不会留下一块"海在动、这块不动"的方斑。
	water_mat = ShaderMaterial.new()
	water_mat.shader = WaterShader
	water_mat.set_shader_parameter("sea_y", Altitude.SEA)
	water_mat.set_shader_parameter("wave_amp", WAVE_AMP)
	water_mat.set_shader_parameter("sheen", WAVE_SHEEN)
	for id in Tiles.ALL_IDS:
		var td: Dictionary = Tiles.get_tile(id)
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true                   # 逐实例亮度抖动，打破同瓦图案重复感
		mm.mesh = td.mesh
		mm.instance_count = maxi(int(need.get(id, 0)), 1)
		for i in mm.instance_count:
			mm.set_instance_transform(i, zero_t)
			mm.set_instance_color(i, Color.WHITE)
		mmi.multimesh = mm
		# 全场共用一份材质（见上）：陆地面片在 shader 里 mask=0，观感与原来的受光顶点色材质一致
		mmi.material_override = water_mat
		# 瓦片层不投影：海面瓦与岛瓦的**水面板彼此共面**（都停在 y=0.3），
		# 在阴影贴图里深度相同 → 边界处会互相自阴影，沿整块瓦的轮廓渗出 2~3px 的暗线
		# （4×4 岛放大 4 倍后尤其明显）。瓦片是纯接收方：单位的影子照样落在水面上，
		# 陆地的明暗由方向光本身给出，不需要靠自阴影。
		mmi.cast_shadow = 0                    # SHADOW_CASTING_OFF
		mmi.custom_aabb = aabb
		world.add_child(mmi)
		mmis[id] = mmi
		var slots := []
		for i in mm.instance_count:
			slots.append(i)
		free_slots[id] = slots
	# 初始把可见窗口铺满：行 j 的内容 = 绝对行 abs_row-(VIS_ROWS-1-j)
	for j in VIS_ROWS:
		_spawn_row(j, layout.rows[posmod(abs_row - (VIS_ROWS - 1 - j), Layout.ROWS)])


## 格位 → 瓦片实例变换。**这是行/列/跨度和世界坐标之间唯一的换算入口**：
## `_spawn_row`（画瓦片）与 `_land_spot`（在岛上落位地面单位）都走这里，
## 保证"反算出来的落点"和"画出来的瓦片"永远是同一个位置。
##
## 跨格瓦以「块中心」落位：N 格块中心在 列 col+(N−1)/2、行 j+(N−1)/2
## （行号越大 z 越负，故中心比宿主行更靠近相机 → z 加半格；写成减号会让岛被画到
##  掩码保留位置之外一格，露出一个 2×1 的空洞 —— M0 踩坑 ⑧）。
## 行 0 停在 +5T（屏幕下缘之外），行 13 在 −38.4T：释放/生成都发生在可见窗口之外。
func _cell_xf(col: int, j: int, span: int, off: Vector3, rot: int) -> Transform3D:
	var half_cols := float(Layout.COLS - 1) * 0.5
	var basis := Basis(Vector3.UP, float(rot) * PI * 0.5) \
			* Basis.IDENTITY.scaled(Vector3.ONE * Tiles.VOXEL)
	var x := (float(col) + (float(span) - 1.0) * 0.5 - half_cols) * Tiles.TILE
	var z := (NEAR_ROWS - float(j) + (float(span) - 1.0) * 0.5) * Tiles.TILE
	# off 为体素坐标偏移：乘上 basis（含 0.3 缩放）后把瓦片几何范围对齐到格位
	return Transform3D(basis, Vector3(x, 0.0, z) + basis * off)


func _spawn_row(j: int, cells: Array) -> void:
	for cell in cells:
		var kind: String = cell.tile
		var td: Dictionary = Tiles.get_tile(kind)
		if td.mesh == null:
			continue
		var slot: int = free_slots[kind].pop_back()
		var t := _cell_xf(int(cell.col), j, int(td.span), td.off, int(cell.rot))
		mmis[kind].multimesh.set_instance_transform(slot, t)
		# 槽位哈希决定亮度抖动：海面细碎图案需要它打破重复，陆地/浅滩大色块上
		# 抖动会读成"补丁"，故只给海面系小幅抖动
		var amp := 0.02 if (Tiles.is_high(kind) or kind == "shoal") else 0.12
		var v := (1.0 - amp * 0.5) + amp * fposmod(float(slot) * 0.618034, 1.0)
		mmis[kind].multimesh.set_instance_color(slot, Color(v, v, v))
		row_slots[j].append({"kind": kind, "slot": slot})


func _release_row(j: int) -> void:
	var zero_t := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	for rec: Dictionary in row_slots[j]:
		mmis[rec.kind].multimesh.set_instance_transform(rec.slot, zero_t)
		free_slots[rec.kind].append(rec.slot)
	row_slots[j].clear()


## 行回绕：world.z 后退一格的同时，保留实例 local z 前挪同一格补偿（世界位置不变），
## 近端行释放、远端补一行新内容。漏掉补偿会让走廊每格瞬间向 -Z 跳动（锯齿倒滚）。
func _advance_row() -> void:
	_release_row(0)
	for j in range(1, VIS_ROWS):
		for rec: Dictionary in row_slots[j]:
			var mm: MultiMesh = mmis[rec.kind].multimesh
			var t := mm.get_instance_transform(rec.slot)
			t.origin.z += Tiles.TILE
			mm.set_instance_transform(rec.slot, t)
		row_slots[j - 1] = row_slots[j]
	row_slots[VIS_ROWS - 1] = []
	abs_row += 1
	_spawn_row(VIS_ROWS - 1, layout.rows[abs_row % Layout.ROWS])


func _build_clouds() -> void:
	# 高空淡云（照抄 M3.7 手法）：每团十几个小盒随机散布，俯视下读作不规则碎块而非白板。
	# M1 起高度取 altitude.gd 的 CLOUD_LO/HI（22~30，M0 是 16~20）——与主空域（7.5）
	# 之间空出 14 个单位，M1 的高空内容/穿云玩法有地方放。
	# 透明度压到 0.14：68° 正交下天空层必然横穿画面，云只能当"空气层"，alpha 一大就抢戏。
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# alpha 压到 0.16、尺寸收到 0.9~1.3 倍：68°/90° 正交下天空层**必然横穿画面**
	# （高度 h 等价于把地面物体平移 +0.5h），做不到"只出现在天边"；云只能当空气层，
	# 一放大或一提亮就变成挡视线的灰板。要更明显就调这两个数 + C 键对照。
	cmat.albedo_color = Color(0.80, 0.90, 1.0, 0.10)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _cloud_mesh(_cloud_rng)
	for i in CLOUD_N:
		var c := MeshInstance3D.new()
		c.mesh = mesh
		c.cast_shadow = 0                  # SHADOW_CASTING_OFF（数值：枚举在此不可直接引用）
		c.material_override = cmat
		add_child(c)
		clouds.append(c)
	_place_clouds()


## 云带复位（首帧与 debug_seek 共用）：同种子 → 同位置，保证截图可复现。
func _place_clouds() -> void:
	_cloud_rng.seed = 20260911
	var z := CLOUD_Z_START
	for i in clouds.size():
		# 注意单位：云网格走 build_blocks 的「1 体素 = 1 世界单位」烘焙（不是瓦片的 0.3），
		# 所以 16×12 的斑块是本底 16×12 世界单位 —— 缩放 0.45~0.65 才是 7~10 单位宽的云，
		# 而 M0 的 1.3~1.9 其实是 21~30 单位的巨物（半个屏幕，也是"云像贴图错误"的原因）。
		clouds[i].scale = Vector3.ONE * _cloud_rng.randf_range(0.45, 0.65)
		clouds[i].position = Vector3(
				CLOUD_X_SPREAD[i % CLOUD_X_SPREAD.size()] + _cloud_rng.randf_range(-4.0, 4.0),
				_cloud_rng.randf_range(Altitude.CLOUD_LO, Altitude.CLOUD_HI),
				z)
		clouds[i].visible = clouds_on
		z += CLOUD_Z_SPAN / float(clouds.size())


## 体素白云（Minecraft 式）：平面随机斑块挤出一层，俯视下就是一朵云。
## 俯角 68° + 高空平放的长方盒会读成"灰色平板"，故不用盒状云。
## 填充率刻意压低（0.34）：斑块连成一片会读成"灰板"，稀疏碎块才像云。
func _cloud_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var blocks := {}
	for y in 12:
		for x in 16:
			if rng.randf() > 0.34:
				continue
			blocks[Vector3i(x, 0, y)] = Color.WHITE
	return VoxelModel.build_blocks(blocks)


func _build_player() -> void:
	player = PlayerSc.new()
	player.name = "Player"
	add_child(player)


func _build_combat() -> void:
	combat = Combat.new()
	add_child(combat)
	combat.host = self
	combat.land_spot = _land_spot
	combat.setup()


## 布局行 → 屏幕行号（0 = 最近端、VIS_ROWS−1 = 最远端）；窗口外会回绕成窗口内的值，
## 因此调用方必须自己判断 j 是否落在窗口里。与 _spawn_row 的映射同源。
func _screen_row(row_layout: int) -> int:
	return posmod(row_layout - abs_row + (VIS_ROWS - 1), Layout.ROWS)


## 在"还在屏幕外 1~8 行"的超级瓦里挑一个**可落位**列，作为地面单位落点（世界坐标）。
## `x_target` 是要落位的单位原本的列位——取最接近它的可落位列，让一组（如左右 -8/+8）
## 落在陆上后仍然左右分开。返回 Vector3.INF 表示当前没有合适陆地（调用方兜底落海面）。
##
## 为什么必须走瓦片实例变换反算：地面单位的 y 要贴地面、x/z 要落在轮廓内，
## 这两件事只有瓦片自己的网格与变换知道（tiles.gd 的列高表 + 本文件的 `_cell_xf`）。
## 为什么只取"屏幕外"：落点若已进屏，地面炮台会在玩家眼前凭空出现。
## 窗口宽度是"陆地命中率"的旋钮：每张超级瓦在 48 行里只被 11 行窗口命中一次。
## M2 起可落位列 = 岸线沙面 + 要塞甲板/城墙顶（tiles.gd `_fill_columns` 的 landing），
## 所以炮台能真正摆上要塞——否则要塞走廊就退化成纯背景板。
func _land_spot(x_target: float) -> Vector3:
	var best := Vector3.INF
	var best_d := 1e9
	for f in layout.features:
		var span: int = int(f.span)
		var j := _screen_row(int(f.row0) + span - 1)      # 记录行 = 跨度里最远那行
		if j < VIS_ROWS or j > VIS_ROWS + 10:
			continue                                     # 只认"还没进屏、11 行之内会进"的瓦
		var td: Dictionary = Tiles.get_tile(f.tile)
		var landing: Array = td.get("landing", [])
		if landing.is_empty():
			continue
		var xf := _cell_xf(int(f.col0), j, span, td.off, 0)
		for sp in landing:
			var w: Vector3 = xf * sp
			var d := absf(w.x - x_target)
			if d < best_d:
				best_d = d
				best = w
	return best


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 10)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_color", COL_CYAN)
	layer.add_child(hud)
	# 屏幕中央的告示（目前只有"被击落"）
	hud_center = Label.new()
	hud_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_center.add_theme_font_size_override("font_size", 34)
	hud_center.add_theme_color_override("font_color", COL_PINK)
	hud_center.visible = false
	layer.add_child(hud_center)


# ================= 主循环 =================

func _process(delta: float) -> void:
	if not paused:
		# 死亡即冻结走廊：残弹继续飞（combat 自己处理死亡态），但地貌停住，方便看清撞在哪
		if not combat.dead:
			world_z += scroll_spd * delta
			if world_z >= Tiles.TILE:
				world_z -= Tiles.TILE
				_advance_row()
			world.position = Vector3(0, 0, world_z)
			for c in clouds:
				c.position.z += scroll_spd * CLOUD_PARALLAX * delta
				if c.position.z > CLOUD_Z_NEAR:
					# 回收带贴着可见带走（见文件头 CLOUD_Z_* 注释）：云始终待在能被看到的位置
					c.position.x = _cloud_rng.randf_range(-24, 24)
					c.position.y = _cloud_rng.randf_range(Altitude.CLOUD_LO, Altitude.CLOUD_HI)
					c.position.z -= CLOUD_Z_SPAN
		combat.update(delta)
		# 无敌期间机身上下闪烁（与方块雄鹰同一手法）
		player.set_blink(combat.invuln > 0.0 and fmod(combat.invuln, 0.24) < 0.12)
	_update_camera()
	_refresh_hud()


func _update_camera() -> void:
	var target := Vector3(player.position.x * 0.62, 0, -3.0)
	var off: Vector3
	match cam_mode:
		0:
			var pitch := deg_to_rad(68.0)
			off = Vector3(0, 40.0 * sin(pitch), 40.0 * cos(pitch))
		1:
			off = Vector3(0, 42.0, 0.01)
		2:
			off = Vector3(28.0, 28.0, 28.0)
	# 受击抖动：抖相机位置而不是 look_at 目标（正交机位下前者只平移画面，不产生歪斜）
	var sh: float = combat.shake if combat != null else 0.0
	if sh > 0.0:
		off += Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), randf_range(-1.0, 1.0)) * sh * 2.2
	cam.position = target + off
	cam.look_at(target)


func _refresh_hud() -> void:
	var inst := 0
	for j in VIS_ROWS:
		inst += row_slots[j].size()
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var armor_txt := ""
	for i in Combat.ARMOR_MAX:
		armor_txt += "◆" if i < combat.armor else "◇"
	hud.text = "分数 %d   装甲 %s   星 %d   击落 %d   敌机 %d%s\n瓦片雄鹰 M1   FPS %d   实例 %d   绘制 %d   种子 %d · 空域 %.1f · 云 %.0f~%.0f · 水波 %s%s      F1/F2/F5 相机  F3 阴影  C 云  V 水波  P 暂停  R 重摇  G 网格  Q 返回" % [
		combat.score, armor_txt, combat.star_cnt, combat.kills, combat.enemy_count(),
		"  [暂停]" if paused else "",
		Engine.get_frames_per_second(), inst, dc, layout.seed_val,
		Altitude.AIR, Altitude.CLOUD_LO, Altitude.CLOUD_HI,
		"开" if wave_on else "关",
		"" if clouds_on else "  [无云]",
	]
	hud_center.visible = combat.dead
	if combat.dead:
		hud_center.text = "被 击 落\n\n按 回车 重开"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				cam_mode = 0
			KEY_F2:
				cam_mode = 1
			KEY_F5:
				cam_mode = 2
			KEY_F3:
				sun.shadow_enabled = not sun.shadow_enabled
			KEY_C:
				clouds_on = not clouds_on
				for c in clouds:
					c.visible = clouds_on
			KEY_V:
				set_wave(not wave_on)
			KEY_P:
				paused = not paused
			KEY_R:
				_reshuffle()
			KEY_G:
				_toggle_wire()
			KEY_ENTER, KEY_KP_ENTER:
				if combat.dead:
					combat.reset()
					player.position = Vector3(0.0, Altitude.AIR, 6.0)
			KEY_Q, KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## V 键 / 出图脚本：开关水面动感（关 = wave_amp 与 sheen 一起置 0 → 与"根本没有 shader"等价，
## 材质与网格都不变）。**两个都要关**：只关 wave_amp 的话亮度行波还在跑，A/B 就不成立了。
func set_wave(on: bool) -> void:
	wave_on = on
	if water_mat != null:
		water_mat.set_shader_parameter("wave_amp", WAVE_AMP if on else 0.0)
		water_mat.set_shader_parameter("sheen", WAVE_SHEEN if on else 0.0)


## R 键：换种子重摇布局（同种子重进场景则逐位复现——可复现性验收项）
## 同时清空战斗：地貌换了位置，留在旧岛上的地面单位会悬在海上
func _reshuffle() -> void:
	layout.seed_val = randi()
	layout.build()
	combat.reset()
	debug_seek(VIS_ROWS - 1)


## 验收 / 出图用：把渲染窗口**直接跳**到指定绝对行（而不是滚动过去），并把玩家与云带复位。
## tools/tile_eagle/shot.gd 用它固定构图 —— 同机位同布局的截图才可复现（M0 验收项 ⑤ 需要）。
func debug_seek(row_abs: int) -> void:
	abs_row = row_abs
	world_z = 0.0
	world.position = Vector3.ZERO
	for j in VIS_ROWS:
		_release_row(j)
		row_slots[j] = []
	for j in VIS_ROWS:
		_spawn_row(j, layout.rows[posmod(abs_row - (VIS_ROWS - 1 - j), Layout.ROWS)])
	player.position = Vector3(0.0, Altitude.AIR, 6.0)
	_place_clouds()
	_update_camera()


func _toggle_wire() -> void:
	wire = not wire
	if wire and wire_mesh == null:
		wire_mesh = MeshInstance3D.new()
		var im := ImmediateMesh.new()
		var w := float(Layout.COLS) * Tiles.TILE
		var x0 := -w * 0.5
		var z0 := Altitude.SEA + 0.05          # 网格线浮在水面之上（水面顶 = Altitude.SEA）
		for c in Layout.COLS + 1:
			var x := x0 + float(c) * Tiles.TILE
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(x, z0, 0.0))
			im.surface_add_vertex(Vector3(x, z0, (NEAR_ROWS - float(VIS_ROWS)) * Tiles.TILE))
			im.surface_end()
		for j in VIS_ROWS + 1:
			var z := (NEAR_ROWS - float(j)) * Tiles.TILE
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			im.surface_add_vertex(Vector3(x0, z0, z))
			im.surface_add_vertex(Vector3(x0 + w, z0, z))
			im.surface_end()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(COL_CYAN, 0.35)
		wire_mesh.mesh = im
		wire_mesh.material_override = m
		world.add_child(wire_mesh)
	wire_mesh.visible = wire
