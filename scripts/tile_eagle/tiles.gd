extends RefCounted
## 瓦片注册表：assets/vox/tiles/*.vox → 底面中心锚点修正 → mesh/lift 共享缓存。
##
## 瓦片三规格（tools/vox/README.md §3.8 / llmdoc/tile-eagle-design.html §2）：
## - 边长 16 体素 = 4.8 世界单位（体素缩放 0.3 不变）
## - 底面中心锚点：公共管线 voxel_model.gd 的 AABB 居中【不改】，
##   本类用 mesh.get_aabb() 反推 lift 把底面抬到 y=0（README §6 的键-中心半格差在此一并消化）
## - 北向 vox +Y = 游戏 -Z；rot ∈ {0,90,180,270} 只旋转不镜像

const VoxReader = preload("res://scripts/voxel_eagle/vox_reader.gd")
const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
const Altitude = preload("res://scripts/tile_eagle/altitude.gd")

const TILE := 4.8            # 瓦片边长（世界单位）
const VOXEL := 0.3           # 体素缩放（与方块雄鹰一致）
const DIR := "res://assets/vox/tiles/"
## 可落位列的高度上限（世界单位）：岸线沙面 0.60 到要塞甲板/城墙顶。塔尖/旗杆不收
## （tiles.gd::_fill_columns 头注）。
const WALK_MAX := 3.0

const ALL_IDS: Array[String] = [
	"sea_a", "sea_b", "sea_c", "sea_d", "sea_e", "sea_f",
	"sea_crest", "shoal", "reef_s", "island_4x4", "island_2x2", "sandbar_2x2",
	# ---- M2：pirate 4×4 接入 + terrain spec 批量产的结构瓦（tools/vox/terraintile.py）----
	"fort_4x4", "fort_wall", "fort_tower", "fort_gate", "dock_2x2",
]
const HIGH_IDS: Array[String] = [
	"reef_s", "island_4x4", "island_2x2", "sandbar_2x2",
	"fort_4x4", "fort_wall", "fort_tower", "fort_gate", "dock_2x2",
]
## 多格跨度的「超级瓦」：一张资产占 N×N 格。尺寸档 =
## 要塞/主岛 19.2 / 小岛·沙洲·码头 9.6（世界单位）。
## 有机轮廓只能靠单张整体资产实现——多瓦拼岛一定是方块形（`gen_tiles.build_island` 头注）。
## span 上限受 VIS_ROWS 约束：span ≤ VIS_ROWS-1，且跨度越大越要保证释放发生在屏幕之外
## （见 game.gd `_spawn_row` 的 z 落位注释）。
const SPAN := {"island_4x4": 4, "island_2x2": 2, "sandbar_2x2": 2,
	"fort_4x4": 4, "dock_2x2": 2}
const TOP_ONLY: Array = [Vector3i(0, 1, 0)]

static var _cache := {}


static func span_of(id: String) -> int:
	return int(SPAN.get(id, 1))


## 取瓦片数据 {mesh: Mesh, off: Vector3, span: int}；失败时 mesh 为 null（该瓦片实例不可见）。
##
## off 是**体素坐标系**下的对齐偏移，实例须以 basis = R * scale(VOXEL)、
## origin = 瓦片块中心 + basis * off 摆放。三个关键点：
## 1) build_blocks 以「方块键质心」为原点，质心 ≠ 几何中心（README §6 的已知坑）——
##    不同瓦的抬升体素分布不同 → 质心偏移不同 → 直接摆会裂出细缝。故 x/z 一律按 AABB
##    （真实几何范围）反推，把 AABB 中心对到瓦片块中心。
## 2) **y 不能用 AABB 反推**：为消掉瓦界细缝，水面层只出顶面（`_build_tile_mesh`），
##    于是「只有 z=0 一层」的瓦（海面/浅滩）网格里根本没有底面，AABB 的 min.y 就是那个
##    顶面 → `-aabb.position.y` 会把水面钉到 y=0，而带上层几何的瓦（礁/岛/浪尖）的
##    AABB 含底面、水面落在 y=0.3 → 两者在瓦界差 0.3，正交下就是一条 6px 的暗色台阶
##    （M1 把岛放大到 4×4 后被放大到整块瓦的轮廓，才定位到这里）。
##    正解：按**方块键的 y 均值**反推——z=0 层底面在网格局部坐标里 = −mean_key_y，
##    把它抬到世界 y=0，全体瓦片的水面就统一在 SEA=0.3（altitude.gd）。
## 3) 多格超级瓦的 span 由 SPAN 表给出，摆位公式见 game.gd `_spawn_row`。
static func get_tile(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var blocks := VoxReader.read_blocks(DIR + id + ".vox")
	var mesh: ArrayMesh = null
	var off := Vector3.ZERO
	var span := span_of(id)
	var mid := Vector3.ZERO
	if not blocks.is_empty():
		mesh = _build_tile_mesh(blocks)
	if mesh != null and mesh.get_surface_count() > 0 and not blocks.is_empty():
		var aabb := mesh.get_aabb()
		mid = _mean_key(blocks)
		off = Vector3(
			-(aabb.position.x + aabb.size.x * 0.5),
			mid.y,
			-(aabb.position.z + aabb.size.z * 0.5))
	else:
		push_warning("瓦片加载失败：%s（该瓦片将不可见）" % id)
		mesh = null
	var d := {"mesh": mesh, "off": off, "span": span}
	_fill_columns(d, blocks)          # 逐列高度表（供地面单位落位，见 _fill_columns 头注）
	_cache[id] = d
	return d


## 逐列高度表 + 可落位列（M1 地面单位落位 / M2 要塞落位用）。
##
## 网格局部坐标系（与 `_build_tile_mesh` 的重基准一致）：`local = key + 0.5 − mean_key`，
## 于是任一列的**顶面**局部 y = `top_key_y + 1 − mean_key.y`，而世界 y = `(局部 y + off.y) × 0.3`
## = `(top_key_y + 1) × 0.3`（因为 off.y 恒等于 mean_key.y）——即「世界高度只由列顶体素数决定」：
## 水面 0.30 / 沙滩 0.60 / 草丘 0.90~1.50 / 要塞甲板与城墙顶 0.90~3.0。这条恒等式是地面单位贴地的依据。
##
## 产出：
## - `heights`  PackedFloat32Array，下标 `(z−mn.z)·sx + (x−mn.x)`，值 = 该列顶面的世界 y
## - `landing`  可落位列（岸线沙面 + 可站立的平台面），元素是**网格局部坐标**的列顶中心
##              （世界位置 = 瓦片实例变换 × 该向量，见 game.gd::cell_xf）
##
## 【为什么是「可落位」而不是只收沙滩】M2 的要塞是石头结构，甲板/城墙顶在 0.9~3.0，
## 若只认沙滩，炮台永远上不了要塞——「要塞走廊」就退化成纯背景。上限 WALK_MAX 之外
## （塔尖/旗杆）不收：把炮台摆在塔尖上既读不出来也没法打。
static func _fill_columns(d: Dictionary, blocks: Dictionary) -> void:
	var top := {}
	var mn := Vector2i(1 << 30, 1 << 30)
	var mx := Vector2i(-(1 << 30), -(1 << 30))
	for p in blocks:
		var key := Vector2i(p.x, p.z)
		if not top.has(key) or int(top[key]) < p.y:
			top[key] = p.y
		mn = Vector2i(mini(mn.x, key.x), mini(mn.y, key.y))
		mx = Vector2i(maxi(mx.x, key.x), maxi(mx.y, key.y))
	if top.is_empty():
		d["heights"] = PackedFloat32Array()
		d["landing"] = []
		return
	var sx := mx.x - mn.x + 1
	var heights := PackedFloat32Array()
	heights.resize(sx * (mx.y - mn.y + 1))
	var landing: Array = []
	var mid: Vector3 = _mean_key(blocks)
	var off_y: float = mid.y                      # off.y ≡ mean_key.y
	for key in top:
		var world_y := (float(int(top[key])) + 1.0) * VOXEL
		heights[(key.y - mn.y) * sx + (key.x - mn.x)] = world_y
		var walkable := world_y > Altitude.SEA + 0.15 and world_y <= WALK_MAX
		if walkable:
			landing.append(Vector3(
				float(key.x) + 0.5 - mid.x,
				float(int(top[key])) + 1.0 - off_y,
				float(key.y) + 0.5 - mid.z))
	d["heights"] = heights
	d["landing"] = landing


## 瓦片网格 = 水面层（z=0，只出顶面 → 无缝无接缝线）+ 上层实体（z≥1，六面全出，有立体感）。
## 水面层中被上层压住的顶面直接剔除。
##
## ⚠️ 两次 build_blocks 各按**自己的方块键均值**定原点，合并前必须把两块拉回同一次烘焙的
## 坐标系，否则水面层与陆地的相对高度会差 (mean_upper − mean_all) 个体素 —— 岛越大错得越
## 离谱：4×4 岛的水面被抬到世界 y=0.60、沙滩沉到 0.27（水下），瓦界露出一道 0.30 高的
## 暗台阶（正交 68° 下约 2.4px 的深色轮廓线，M1 放大岛屿后才定位到）。修法：按
## (自己的键均值 − 全局键均值) 平移后再合并，等价于「一次烘焙全量、只是按层过滤了面」。
static func _build_tile_mesh(blocks: Dictionary) -> ArrayMesh:
	var plate := {}
	var upper := {}
	for pos in blocks:
		if int(pos.y) == 0:
			if not blocks.has(pos + Vector3i(0, 1, 0)):
				plate[pos] = blocks[pos]
		else:
			upper[pos] = blocks[pos]
	if plate.is_empty():
		return VoxelModel.build_blocks(blocks)
	var mid := _mean_key(blocks)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(VoxelModel.build_blocks(plate, TOP_ONLY), 0,
			Transform3D(Basis.IDENTITY, _mean_key(plate) - mid))
	if not upper.is_empty():
		var up := VoxelModel.build_blocks(upper)
		for s in up.get_surface_count():
			st.append_from(up, s, Transform3D(Basis.IDENTITY, _mean_key(upper) - mid))
	return st.commit()


static func _mean_key(blocks: Dictionary) -> Vector3:
	var m := Vector3.ZERO
	for p in blocks:
		m += Vector3(p)
	return m / float(blocks.size())


static func is_high(id: String) -> bool:
	return HIGH_IDS.has(id)
