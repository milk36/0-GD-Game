extends SceneTree
## 临时探针（不属于交付物）：把**浪光 sheen** 放大到 5 倍出图，判定相位到底锚在哪里。
##
## 为什么测 sheen 而不是 wave_amp：几何起伏在正交俯视下几乎不可见（它位移的是一片没有纹理的
## 连续水面，颜色图案是钉在几何上的），把 wave_amp 放大 12 倍也看不出瓦界台阶 —— 那是个
## "看不见所以通过"的假验证。sheen 才是看得见的那一层，用它测才有效。
##
## 判据：相位若为 f(world.xz)（即 MODEL_MATRIX 含 MultiMesh 实例变换），亮度栅格跨瓦连续、
## 不认瓦格；若退化成 f(local)（MODEL_MATRIX 不含实例变换，所有海瓦图案逐位相同），
## 那么 p2 分量（周期 2.976 ≠ 4.8）会在每 4.8 单位的瓦格线上露出明显的错位缝。

const SCENE := "res://scenes/tile_eagle.tscn"
const OUT := "res://tools/tile_eagle/_probe_wave_big.png"

var vp: SubViewport


func _initialize() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)
	var packed: PackedScene = load(SCENE)
	var inst: Node = packed.instantiate()
	vp.add_child(inst)
	await process_frame
	await process_frame
	inst.call("debug_seek", 21)
	inst.call("set_wave", false)
	var wm: ShaderMaterial = inst.get("water_mat")
	wm.set_shader_parameter("sheen", 1.6)     # 5.3× 诊断幅度：把亮度栅格逼出来看接不接得上
	inst.set("paused", true)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(OUT))
		print("saved ", OUT, " ", img.get_size())
	else:
		print("NULL IMAGE")
	quit(0)

