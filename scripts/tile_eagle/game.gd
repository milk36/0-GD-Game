extends Node3D
## 瓦片雄鹰 M0：瓦片滚动走廊 + 玩家机飞行的对照实验小场景（无战斗）。
##
## 架构（llmdoc/tile-eagle-design.html §3）：瓦片本体 assets/vox/tiles/*.vox →
## 排布层 layout.gd（段落 + 图章 + 种子）→ 渲染层本文件（按种类分组 MultiMesh + 行回绕）。
## 环境参数照抄方块雄鹰关 1（碧海突袭），保证两作并排对比时同相机同色板同光照。

const Tiles = preload("res://scripts/tile_eagle/tiles.gd")
const Layout = preload("res://scripts/tile_eagle/layout.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const PlayerSc = preload("res://scripts/tile_eagle/player.gd")

const SCROLL := 7.0                    # 与方块雄鹰关 1 相同
const VIS_ROWS := 12                   # 在场行数：只实例化视距内的行（可见 z 约 [-21,+15]）
const NEAR_ROWS := 6.0                 # 行 0 的 z = +6T：保证释放/生成都发生在屏幕下缘之外

# 关 1「碧海突袭」主题色板（stages.gd）
const COL_SKY := Color("050810")
const COL_FOG := Color("0a2540")
const COL_AMBIENT := Color("223050")
const COL_SUN := Color("fff2e0")
const COL_CYAN := Color("00f0ff")

var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var player: Node3D
var layout: RefCounted
var hud: Label

var cam_mode := 0                      # 0=68° 斜俯视 1=90° 纯俯视 2=等距
var paused := false
var wire := false

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
	# 整条走廊的包围盒：MultiMesh 逐实例散布 230 单位，不设 custom_aabb 会被视锥误剔除
	var half_x := float(Layout.COLS) * Tiles.TILE * 0.5 + 4.0
	var aabb := AABB(
		Vector3(-half_x, -1.0, -(float(Layout.ROWS) + 2.0) * Tiles.TILE),
		Vector3(half_x * 2.0, 10.0, (float(Layout.ROWS) + 4.0) * Tiles.TILE))
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
		mmi.material_override = VoxelModel.shaded_material()
		mmi.custom_aabb = aabb
		world.add_child(mmi)
		mmis[id] = mmi
		var slots := []
		for i in mm.instance_count:
			slots.append(i)
		free_slots[id] = slots
	# 初始把可见窗口铺满：行 j 的内容 = 绝对行 abs_row-(VIS_ROWS-1-j)
	for j in VIS_ROWS:
		_spawn_row(j, layout.rows[(abs_row - (VIS_ROWS - 1 - j) + Layout.ROWS * 2) % Layout.ROWS])


func _spawn_row(j: int, cells: Array) -> void:
	var half_cols := float(Layout.COLS - 1) * 0.5
	for cell in cells:
		var kind: String = cell.tile
		var td: Dictionary = Tiles.get_tile(kind)
		if td.mesh == null:
			continue
		var slot: int = free_slots[kind].pop_back()
		var span: float = float(td.span)
		# 跨格瓦以「块中心」落位：N 格块中心在 列 col+(N-1)/2、行 j+(N-1)/2
		# （行号越大 z 越负，故中心比宿主行更靠近相机 → z 加半格；写成减号会让
		#  岛被画到掩码保留位置之外一格，露出一个 2×1 的空洞）
		var x := (float(cell.col) + (span - 1.0) * 0.5 - half_cols) * Tiles.TILE
		var basis := Basis(Vector3.UP, float(cell.rot) * PI * 0.5) \
				* Basis.IDENTITY.scaled(Vector3.ONE * Tiles.VOXEL)
		# 行 0 停在 +6T（屏幕下缘 z≈+15 之外），行 11 在 -24T：
		# 释放/生成都发生在可见窗口之外，不会有可见的弹出或消失
		var z := (NEAR_ROWS - float(j) + (span - 1.0) * 0.5) * Tiles.TILE
		# off 为体素坐标偏移：乘上 basis（含 0.3 缩放）后把瓦片几何范围对齐到格位
		var t := Transform3D(basis, Vector3(x, 0.0, z) + basis * td.off)
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
	# 高空淡云（照抄 M3.7 手法）：每团 7 个小盒随机散布，俯视下读作不规则碎块而非白板；
	# alpha 压低（0.20）避免与海面争夺注意力，主要起远景层次作用
	_cloud_rng.seed = 20260911
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1, 1, 1, 0.45)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _cloud_mesh(_cloud_rng)
	for i in 3:
		var c := MeshInstance3D.new()
		c.mesh = mesh
		c.scale = Vector3.ONE * _cloud_rng.randf_range(1.3, 1.9)
		c.cast_shadow = 0                  # SHADOW_CASTING_OFF（数值：枚举在此不可直接引用）
		c.material_override = cmat
		c.position = Vector3(_cloud_rng.randf_range(-26, 26),
				_cloud_rng.randf_range(16.0, 20.0), -30.0 - i * 55.0)
		add_child(c)
		clouds.append(c)


## 体素白云（Minecraft 式）：平面随机斑块挤出一层，俯视下就是一朵云。
## 俯角 68° + 高空平放的长方盒会读成"灰色平板"，故不用盒状云。
func _cloud_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var blocks := {}
	for y in 8:
		for x in 11:
			if rng.randf() > 0.45:
				continue
			blocks[Vector3i(x, 0, y)] = Color.WHITE
	return VoxelModel.build_blocks(blocks)


func _build_player() -> void:
	player = PlayerSc.new()
	player.name = "Player"
	add_child(player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 10)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_color", COL_CYAN)
	layer.add_child(hud)


# ================= 主循环 =================

func _process(delta: float) -> void:
	if not paused:
		world_z += SCROLL * delta
		if world_z >= Tiles.TILE:
			world_z -= Tiles.TILE
			_advance_row()
		world.position = Vector3(0, 0, world_z)
		for c in clouds:
			c.position.z += SCROLL * 0.3 * delta
			if c.position.z > 30.0:
				c.position.x = randf_range(-20, 20)
				c.position.y = randf_range(13.0, 19.0)
				c.position.z = -240.0
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
	cam.position = target + off
	cam.look_at(target)


func _refresh_hud() -> void:
	var inst := 0
	for j in VIS_ROWS:
		inst += row_slots[j].size()
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	hud.text = "瓦片雄鹰 M0   FPS %d   瓦片实例 %d   绘制 %d   种子 %d%s\n瓦片走廊 13×48 · 行深 4.8 · 滚速 7.0      F1/F2/F5 相机[68°/90°/等距]  F3 阴影  P 暂停  R 重摇  G 网格  Q 返回" % [
		Engine.get_frames_per_second(), inst, dc, layout.seed_val,
		"  [暂停]" if paused else "",
	]


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
			KEY_P:
				paused = not paused
			KEY_R:
				_reshuffle()
			KEY_G:
				_toggle_wire()
			KEY_Q, KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## R 键：换种子重摇布局（同种子重进场景则逐位复现——可复现性验收项）
func _reshuffle() -> void:
	layout.seed_val = randi()
	layout.build()
	abs_row = VIS_ROWS - 1
	for j in VIS_ROWS:
		_release_row(j)
		row_slots[j] = []
	# 初始把可见窗口铺满：行 j 的内容 = 绝对行 abs_row-(VIS_ROWS-1-j)
	for j in VIS_ROWS:
		_spawn_row(j, layout.rows[(abs_row - (VIS_ROWS - 1 - j) + Layout.ROWS * 2) % Layout.ROWS])


func _toggle_wire() -> void:
	wire = not wire
	if wire and wire_mesh == null:
		wire_mesh = MeshInstance3D.new()
		var im := ImmediateMesh.new()
		var w := float(Layout.COLS) * Tiles.TILE
		var x0 := -w * 0.5
		var z0 := 0.02
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
