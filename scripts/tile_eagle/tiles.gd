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

const TILE := 4.8            # 瓦片边长（世界单位）
const VOXEL := 0.3           # 体素缩放（与方块雄鹰一致）
const DIR := "res://assets/vox/tiles/"

const ALL_IDS: Array[String] = [
	"sea_a", "sea_b", "sea_c", "sea_d", "sea_e", "sea_f",
	"sea_crest", "shoal", "reef_s", "isle_sand", "isle_grass", "island_2x2",
]
const HIGH_IDS: Array[String] = ["reef_s", "isle_sand", "isle_grass", "island_2x2"]
## 多格跨度的「超级瓦」：一张资产占 N×N 格（岛=2 → 32 体素 = 9.6 世界单位）。
## 有机轮廓只能靠单张整体资产实现——多瓦拼岛一定是方块形（`gen_tiles.build_island` 头注）。
const SPAN := {"island_2x2": 2}
const TOP_ONLY: Array = [Vector3i(0, 1, 0)]

static var _cache := {}


static func span_of(id: String) -> int:
	return int(SPAN.get(id, 1))


## 取瓦片数据 {mesh: Mesh, off: Vector3, span: int}；失败时 mesh 为 null（该瓦片实例不可见）。
##
## off 是**体素坐标系**下的对齐偏移，实例须以 basis = R * scale(VOXEL)、
## origin = 瓦片块中心 + basis * off 摆放。两个关键点：
## 1) build_blocks 以「方块键质心」为原点，质心 ≠ 几何中心（README §6 的已知坑）——
##    不同瓦的抬升体素分布不同 → 质心偏移不同 → 直接摆会裂出细缝。故一律按 AABB
##    （真实几何范围）反推：x/z 把 AABB 中心对到瓦片块中心，y 把底面抬到 0。
## 2) 水面层只出顶面、上层（z≥1）全出面（见 _build_tile_mesh）：各瓦独立成 mesh 时
##    边缘侧面无法被邻居剔除，会在瓦界留下可见接缝线。
static func get_tile(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var blocks := VoxReader.read_blocks(DIR + id + ".vox")
	var mesh: ArrayMesh = null
	var off := Vector3.ZERO
	if not blocks.is_empty():
		mesh = _build_tile_mesh(blocks)
	if mesh != null and mesh.get_surface_count() > 0:
		var aabb := mesh.get_aabb()
		off = Vector3(
			-(aabb.position.x + aabb.size.x * 0.5),
			-aabb.position.y,
			-(aabb.position.z + aabb.size.z * 0.5))
	else:
		push_warning("瓦片加载失败：%s（该瓦片将不可见）" % id)
		mesh = null
	var d := {"mesh": mesh, "off": off, "span": span_of(id)}
	_cache[id] = d
	return d


## 瓦片网格 = 水面层（z=0，只出顶面 → 无缝无接缝线）+ 上层实体（z≥1，六面全出，有立体感）。
## 水面层中被上层压住的顶面直接剔除。
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
	var mesh := VoxelModel.build_blocks(plate, TOP_ONLY)
	if upper.is_empty():
		return mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(mesh, 0, Transform3D.IDENTITY)
	var up := VoxelModel.build_blocks(upper)
	for s in up.get_surface_count():
		st.append_from(up, s, Transform3D.IDENTITY)
	return st.commit()


static func is_high(id: String) -> bool:
	return HIGH_IDS.has(id)
