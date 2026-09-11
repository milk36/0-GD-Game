extends Object
## 营救进度计时圈：飞机身上的一圈进度环（屏幕对齐、正对相机），0 → 1 顺时针填充。
## 半径 = 营救触发距离，所以这圈同时也是"营救判定范围"的可视化。
##
## 用法：
##   const RescueRing = preload("res://scripts/voxel_eagle/rescue_ring.gd")
##   var ring := RescueRing.build()      # 挂到玩家节点下
##   RescueRing.aim(ring, cam, player.global_position)
##   RescueRing.set_progress(ring, prog) # 0~1；>=1 显示为完成色
##   ring.visible = false                # 不营救时隐藏

const SurvivorUnit = preload("res://scripts/voxel_eagle/survivor_unit.gd")

const RADIUS := SurvivorUnit.RESCUE_TRIGGER   # 与判定范围一致（改一处两边同步）
const WIDTH := 0.34
const SEGMENTS := 64
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.15)     # 底圈
const FILL_COLOR := Color("00f0ff")                 # 填充中（青）
const DONE_COLOR := Color("ffe600")                 # 填满一瞬（黄）
const FLASH_TIME := 0.30                            # 完成后保留显示时长


static func build() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "RescueRing"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true                 # 不被机身/海面遮住，始终可读
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## 重建圆弧（每帧调用；顶点量很小）
static func set_progress(mi: MeshInstance3D, p: float) -> void:
	var im := mi.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	_arc(im, 0.0, TAU, TRACK_COLOR)
	if p > 0.001:
		# 屏幕坐标：环的局部 +X = 屏幕右、+Y = 屏幕上、角度增大 = 逆时针（从相机侧看）
		# 所以从 12 点（+90°）开始、角度递减 = 顺时针填充
		var a0 := PI * 0.5
		var col := DONE_COLOR if p >= 1.0 else FILL_COLOR
		_arc(im, a0, a0 - TAU * clampf(p, 0.0, 1.0), col)


static func _arc(im: ImmediateMesh, a0: float, a1: float, col: Color) -> void:
	var steps: int = maxi(2, int(SEGMENTS * absf(a1 - a0) / TAU) + 2)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / float(steps))
		var dir := Vector2(cos(a), sin(a))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(dir.x * (RADIUS - WIDTH * 0.5), dir.y * (RADIUS - WIDTH * 0.5), 0.0))
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(dir.x * (RADIUS + WIDTH * 0.5), dir.y * (RADIUS + WIDTH * 0.5), 0.0))
	im.surface_end()


## 让圆环正对相机（屏幕空间呈正圆）。环的局部 XY 平面 = 相机的右/上方向。
static func aim(mi: MeshInstance3D, cam: Camera3D, at: Vector3) -> void:
	if cam == null:
		return
	mi.global_transform = Transform3D(cam.global_transform.basis.orthonormalized(), at)
