extends MultiMeshInstance3D
## 通用体素实例池：一个 MultiMeshInstance3D 承载全部同类方块实例（子弹/星星/碎片）。
## 数据扁平数组 + swap-remove 紧凑活跃区，每帧只写活跃实例的 transform/color。
##
## 用法：
##   var VoxelPool = preload("res://scripts/voxel_eagle/pools.gd")
##   var pool := VoxelPool.new()
##   add_child(pool); pool.setup(512, mat)
##   pool.spawn(pos, vel, color, size, life, gravity, spin)
##   pool.update(delta)   # 每帧调用；碰撞检测由宿主读 pool.pos/vel 自理

var pos: PackedVector3Array
var vel: PackedVector3Array
var spin: PackedVector3Array
var life: PackedFloat32Array
var max_life: PackedFloat32Array
var size: PackedFloat32Array
var grav: PackedFloat32Array
var shrink: PackedByteArray
var count := 0          # 活跃实例数（紧凑区 [0, count)）
var _max := 0
var _rot := 0.0         # 全局自转相位（敌弹缓慢自转的廉价实现）


func setup(p_max: int, mat: Material) -> void:
	_max = p_max
	pos.resize(p_max)
	vel.resize(p_max)
	spin.resize(p_max)
	life.resize(p_max)
	max_life.resize(p_max)
	size.resize(p_max)
	grav.resize(p_max)
	shrink.resize(p_max)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = p_max
	multimesh = mm
	cast_shadow = 0  # GeometryInstance3D.SHADOW_CASTING_OFF：池实例不投影
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	multimesh.mesh = box
	# 未使用实例零缩放隐藏
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in p_max:
		multimesh.set_instance_transform(i, zero)
		multimesh.set_instance_color(i, Color.WHITE)


## 生成一个实例；池满时静默丢弃（调用方保证 max 足够大）
func spawn(p: Vector3, v: Vector3, col: Color, p_size := 1.0, p_life := 5.0, p_grav := 0.0, p_spin := Vector3.ZERO, p_shrink := false) -> int:
	if count >= _max:
		return -1
	var i := count
	count += 1
	pos[i] = p
	vel[i] = v
	spin[i] = p_spin
	life[i] = p_life
	max_life[i] = p_life
	size[i] = p_size
	grav[i] = p_grav
	shrink[i] = 1 if p_shrink else 0  # PackedByteArray 只存 int
	multimesh.set_instance_color(i, col)
	return i


## 杀死实例 i（swap-remove；死亡位 transform 置零防止残影）
func kill(i: int) -> void:
	if i < 0 or i >= count:
		return
	count -= 1
	if i < count:
		pos[i] = pos[count]
		vel[i] = vel[count]
		spin[i] = spin[count]
		life[i] = life[count]
		max_life[i] = max_life[count]
		size[i] = size[count]
		grav[i] = grav[count]
		shrink[i] = shrink[count]
		multimesh.set_instance_transform(i, _xf(i))
		multimesh.set_instance_color(i, multimesh.get_instance_color(count))
	multimesh.set_instance_transform(count, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


## 运动 + 寿命 + 写回实例。返回被寿命回收时最后一个被杀的下标（可循环继续检查），-1 无变化。
func update(delta: float) -> void:
	_rot += delta * 1.2
	var i := 0
	while i < count:
		life[i] -= delta
		if life[i] <= 0.0:
			kill(i)
			continue  # swap 后 i 位置是新数据，不递增
		vel[i].y -= grav[i] * delta
		pos[i] += vel[i] * delta
		multimesh.set_instance_transform(i, _xf(i))
		i += 1


func _xf(i: int) -> Transform3D:
	var s := size[i]
	if shrink[i]:
		s *= clampf(life[i] / max_life[i], 0.0, 1.0)
	var b := Basis.IDENTITY.rotated(Vector3.UP, _rot + float(i) * 0.7)
	if spin[i] != Vector3.ZERO:
		b = b.rotated(Vector3.RIGHT, _rot * spin[i].x).rotated(Vector3.FORWARD, _rot * spin[i].y)
	return Transform3D(b.scaled(Vector3(s, s, s)), pos[i])
