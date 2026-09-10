extends RefCounted
class_name VoxReader
## MagicaVoxel .vox 导入器：解析 RIFF 块 → {Vector3i: Color} 方块表 → ArrayMesh。
## 让 MagicaVoxel 里编辑的场景直接进游戏，无需手工导出 obj。
##
## 用法：
##   var blocks := VoxReader.read_blocks("res://assets/vox/xxx.vox")  # 方块表
##   var mesh   := VoxReader.read_mesh("res://assets/vox/xxx.vox")    # 直接出网格
##   var mi := MeshInstance3D.new(); mi.mesh = mesh
##   mi.material_override = VoxelModel.shaded_material()
##
## 支持块：SIZE / XYZI / RGBA / nTRN / nGRP / nSHP（场景图平移 + 旋转）。
## 坐标：MagicaVoxel 是 Z-up，转换 vox(x,y,z) → godot(x, z, y)，网格以 AABB 中心为原点。

const VoxelModel = preload("res://scripts/voxel_eagle/voxel_model.gd")


## 读 .vox 为方块表 {Vector3i: Color}（Y-up，绝对坐标）
static func read_blocks(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("VoxReader: 打不开 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return {}
	var b := f.get_buffer(f.get_length())
	f.close()
	if b.size() < 20 or b.slice(0, 4).get_string_from_ascii() != "VOX ":
		push_error("VoxReader: 不是合法 .vox 文件: %s" % path)
		return {}

	var main := _chunk(b, 8)
	var models: Array = []            # [{size: Vector3i, data: PackedByteArray(4B/voxel)}]
	var palette := PackedByteArray()  # 256*4，第 k 项对应颜色索引 k+1
	var trn := {}                     # id -> 节点
	var grp := {}
	var shp := {}
	var cur_size := Vector3i.ZERO

	var p: int = main["children"]
	var end_p: int = main["children"] + main["children_size"]
	while p + 12 <= end_p:
		var h := _chunk(b, p)
		match h["id"]:
			"SIZE":
				cur_size = Vector3i(_u32(b, h["content"]), _u32(b, h["content"] + 4), _u32(b, h["content"] + 8))
			"XYZI":
				var n := _u32(b, h["content"])
				models.append({"size": cur_size, "data": b.slice(h["content"] + 4, h["content"] + 4 + n * 4)})
			"RGBA":
				palette = b.slice(h["content"], h["content"] + 1024)
			"nTRN":
				var t := _parse_trn(b, h["content"])
				trn[t["id"]] = t
			"nGRP":
				var g := _parse_grp(b, h["content"])
				grp[g["id"]] = g["children"]
			"nSHP":
				var s := _parse_shp(b, h["content"])
				shp[s["id"]] = s["models"]
		p = h["next"]

	if models.is_empty():
		push_error("VoxReader: 文件内无模型 %s" % path)
		return {}

	# 场景图 → 模型实例（平移 + 旋转）
	var instances: Array = []  # [{basis: Basis, t: Vector3}]
	if trn.has(0) or grp.has(0) or shp.has(0):
		_walk(0, Basis.IDENTITY, Vector3i.ZERO, trn, grp, shp, instances)
	else:
		for i in models.size():
			instances.append({"model": i, "basis": Basis.IDENTITY, "t": Vector3i.ZERO})

	# 展平为方块表，Z-up → Y-up
	var blocks := {}
	for inst in instances:
		var mid: int = inst["model"]
		if mid < 0 or mid >= models.size():
			continue
		var basis: Basis = inst["basis"]
		var t: Vector3i = inst["t"]
		var data: PackedByteArray = models[mid]["data"]
		for i in data.size() >> 2:
			var ci := data[i * 4 + 3]
			if ci == 0:
				continue
			var w: Vector3 = basis * Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]) + Vector3(t)
			blocks[Vector3i(roundi(w.x), roundi(w.z), roundi(w.y))] = _palette_color(palette, ci)
	return blocks


## 读 .vox 并生成合并网格（顶点色 + 内面剔除，复用 VoxelModel 管线）
static func read_mesh(path: String) -> ArrayMesh:
	var blocks := read_blocks(path)
	if blocks.is_empty():
		return ArrayMesh.new()
	return VoxelModel.build_blocks(blocks)


# ---------------------------------------------------------------- 内部

static func _u32(b: PackedByteArray, p: int) -> int:
	return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)


static func _i32(b: PackedByteArray, p: int) -> int:
	var v := _u32(b, p)
	return v if v < 0x80000000 else v - 0x100000000


static func _chunk(b: PackedByteArray, p: int) -> Dictionary:
	var cs := _u32(b, p + 4)
	return {
		"id": b.slice(p, p + 4).get_string_from_ascii(),
		"content": p + 12,
		"children": p + 12 + cs,
		"children_size": _u32(b, p + 8),
		"next": p + 12 + cs + _u32(b, p + 8),
	}


## DICT：int32 数量 + (int32 键长, 键, int32 值长, 值字节)…
static func _dict_at(b: PackedByteArray, p: int) -> Dictionary:
	var n := _i32(b, p)
	p += 4
	var d := {}
	for i in n:
		var kl := _i32(b, p)
		p += 4
		var k := b.slice(p, p + kl).get_string_from_ascii()
		p += kl
		var vl := _i32(b, p)
		p += 4
		d[k] = b.slice(p, p + vl)
		p += vl
	return {"d": d, "next": p}


static func _parse_trn(b: PackedByteArray, p: int) -> Dictionary:
	var id := _i32(b, p)
	var q: int = _dict_at(b, p + 4)["next"]
	var child := _i32(b, q)
	q += 12  # child + reserved(-1) + layer_id
	var frames := _i32(b, q)
	q += 4
	var t := Vector3i.ZERO
	var r := -1
	if frames > 0:
		var fr: Dictionary = _dict_at(b, q)["d"]
		if fr.has("_t"):
			var parts: PackedStringArray = (fr["_t"] as PackedByteArray).get_string_from_ascii().split(" ")
			if parts.size() == 3:
				t = Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		if fr.has("_r") and (fr["_r"] as PackedByteArray).size() > 0:
			r = fr["_r"][0]
	return {"id": id, "child": child, "t": t, "r": r}


static func _parse_grp(b: PackedByteArray, p: int) -> Dictionary:
	var id := _i32(b, p)
	var q: int = _dict_at(b, p + 4)["next"]
	var n := _i32(b, q)
	q += 4
	var kids := PackedInt32Array()
	for i in n:
		kids.append(_i32(b, q + i * 4))
	return {"id": id, "children": kids}


static func _parse_shp(b: PackedByteArray, p: int) -> Dictionary:
	var id := _i32(b, p)
	var q: int = _dict_at(b, p + 4)["next"]
	var n := _i32(b, q)
	q += 4
	var models := PackedInt32Array()
	for i in n:
		models.append(_i32(b, q + i * 4))
	return {"id": id, "models": models}


## _r 字节 → 旋转基（规范：bit0-1/2-3 为一二行非零元列号，bit4/5 为符号，第三行叉积）
static func _rot_basis(r: int) -> Basis:
	var i1: int = r & 3
	var i2: int = (r >> 2) & 3
	var s1 := -1.0 if (r & 16) else 1.0
	var s2 := -1.0 if (r & 32) else 1.0
	var row0 := Vector3.ZERO
	var row1 := Vector3.ZERO
	row0[i1] = s1
	row1[i2] = s2
	var row2 := row0.cross(row1)
	# Basis 构造按列：列 j = (row0[j], row1[j], row2[j])
	return Basis(
		Vector3(row0.x, row1.x, row2.x),
		Vector3(row0.y, row1.y, row2.y),
		Vector3(row0.z, row1.z, row2.z))


static func _walk(id: int, acc_basis: Basis, acc_t: Vector3i, trn: Dictionary, grp: Dictionary, shp: Dictionary, out: Array) -> void:
	if trn.has(id):
		var n: Dictionary = trn[id]
		var rb: Basis = _rot_basis(n["r"]) if int(n["r"]) >= 0 else Basis.IDENTITY
		var t: Vector3i = n["t"]
		# 先子后父合成：world = t_acc + R_acc * (t + R * v)
		_walk(n["child"], acc_basis * rb, acc_t + Vector3i(Vector3(acc_basis * Vector3(t))), trn, grp, shp, out)
	elif grp.has(id):
		for kid in grp[id]:
			_walk(kid, acc_basis, acc_t, trn, grp, shp, out)
	elif shp.has(id):
		for mid in shp[id]:
			out.append({"model": mid, "basis": acc_basis, "t": acc_t})


static func _palette_color(pal: PackedByteArray, ci: int) -> Color:
	var o := (ci - 1) * 4
	if pal.size() < o + 4:
		return Color(1, 0, 1)  # 缺调色板时用品红占位，便于发现
	return Color8(pal[o], pal[o + 1], pal[o + 2])
