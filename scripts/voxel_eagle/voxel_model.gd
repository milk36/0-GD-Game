extends Object
## 体素建模工具：字符画 → 方块表 → 合并 ArrayMesh（顶点色 + 内面剔除）。
## 零外部资源：所有模型由代码生成，改字符画即改造型。
##
## 用法：
##   const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")
##   var mesh := VoxelModel.build(ART, PALETTE, 3)  # 挤出 3 层
##   var mesh2 := VoxelModel.build_multi([{art = "", pal = {}, y = 0, layers = 1}, ...])  # 分层组装
##   # MeshInstance3D.material_override 传 VertexColorMaterial

const FACE_VERTS := {
	Vector3i(1, 0, 0): [Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5)],
	Vector3i(-1, 0, 0): [Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5)],
	Vector3i(0, 1, 0): [Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5)],
	Vector3i(0, -1, 0): [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	Vector3i(0, 0, 1): [Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)],
	Vector3i(0, 0, -1): [Vector3(0.5, -0.5, -0.5), Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5)],
}

const DIRS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## 多部件组装建模：parts = [{art, pal, y, layers}]，自下而上叠出立体模型。
## 用于需要分层细节的机型（机翼/机身/座舱各占一层）。
static func build_multi(parts: Array) -> ArrayMesh:
	var blocks := {}
	for p in parts:
		_art_to_blocks(p["art"], p["pal"], int(p.get("y", 0)), int(p.get("layers", 1)), blocks)
	return _build_mesh(blocks)


## 单张俯视字符画沿 Y 轴挤出 layers 层。字符画第一行 = -Z（机头方向）。
## palette: { 字符: Color }，未登记的字符（如空格/·）跳过。
static func build(art: String, palette: Dictionary, layers: int = 1) -> ArrayMesh:
	return build_multi([{"art": art, "pal": palette, "y": 0, "layers": layers}])


static func _art_to_blocks(art: String, palette: Dictionary, y0: int, layers: int, blocks: Dictionary) -> void:
	var rows: Array = art.split("\n")
	rows = rows.filter(func(r: String) -> bool: return not r.strip_edges().is_empty())
	for zi in rows.size():
		var row: String = rows[zi]
		for xi in row.length():
			var ch := row[xi]
			if palette.has(ch):
				for yi in layers:
					blocks[Vector3i(xi, y0 + yi, zi)] = palette[ch]


## 直接给方块表 {Vector3i: Color} 建模（供程序化地形等使用）。
## face_filter：可选，只生成法线在列表内的面。瓦片走廊用它「只出顶面」——
## 同层相邻瓦各自独立成 mesh 时，边缘侧面无法被邻居剔除，会在瓦界留下可见接缝线。
## 默认 [] = 六面全出，既有行为完全不变。
static func build_blocks(blocks: Dictionary, face_filter: Array = []) -> ArrayMesh:
	return _build_mesh(blocks, face_filter)


static func _build_mesh(blocks: Dictionary, face_filter: Array = []) -> ArrayMesh:
	if blocks.is_empty():
		push_error("VoxelModel: 空方块表")
		return ArrayMesh.new()
	# 以 AABB 中心为模型原点，模型摆放无需手动对中
	var center := Vector3.ZERO
	for pos in blocks:
		center += Vector3(pos)
	center /= float(blocks.size())

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pos in blocks:
		var col: Color = blocks[pos]
		var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5) - center
		for d in DIRS:
			if not face_filter.is_empty() and not face_filter.has(d):
				continue
			if blocks.has(pos + d):
				continue  # 内面剔除：被邻居贴住的面不生成
			var verts: Array = FACE_VERTS[d]
			# 绕序：Godot 正面为顺时针，按 0-2-1 / 0-3-2 排列才使正面朝外
			# （顺序反了会导致顶面被背面剔除、看到内部底面 → 观感"上下颠倒"）
			var n := Vector3(d)
			# 法线：直接写死面朝向（硬边）。不用 generate_normals()——它是按位置平滑平均的，
			# 会把相邻面法线混在一起（1 层厚的模型侧面因此几乎全变成斜向法线，块面结构糊掉）。
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(c + verts[0])
			st.set_normal(n)
			st.add_vertex(c + verts[2])
			st.set_normal(n)
			st.add_vertex(c + verts[1])
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(c + verts[0])
			st.set_normal(n)
			st.add_vertex(c + verts[3])
			st.set_normal(n)
			st.add_vertex(c + verts[2])
	var mesh := st.commit()
	return mesh


## 受光顶点色材质（机体/敌人/地形/玩家机共用，配 material_override）
static func shaded_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m


## 无光照顶点色材质（子弹/星星/特效：高饱和即霓虹感，不依赖 Bloom）
static func unshaded_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m
