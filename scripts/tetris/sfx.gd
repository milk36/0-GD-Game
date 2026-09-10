extends Node
## 音效管理器（autoload: SFX）—— 懒合成 + 缓存 + 声道池轮询。
##
## 用法：SFX.play("wind_cast")
## 首次播放某个 id 时才合成 PCM（几十毫秒，一次性），之后走缓存。
## 8 个 AudioStreamPlayer 轮询：连发道具 / 多格碎片同时熄灭时不会互相打断。

const Synth := preload("res://scripts/tetris/sfx_synth.gd")

const POOL_SIZE := 8
const BASE_VOLUME_DB := -8.0

## 各音效的相对音量微调(dB)，统一入口便于整体混音平衡。
const MIX := {
	"shard_spawn": 0.0,
	"shard_tick0": -6.0,
	"shard_tick1": -4.0,
	"shard_tick2": -2.0,
	"shard_expire": -1.0,
	"item_get": 1.0,
	"wind_cast": 0.0,
	"rain_cast": -1.0,
	"bolt_cast": 0.0,
	"item_fizzle": -3.0,
	"item_clear": -5.0,
	"eagle_star": -8.0,
	"eagle_boom": -2.0,
	"eagle_hurt": 0.0,
	"eagle_bomb": 1.0,
	"eagle_rescue": 1.0,
	"eagle_laser": -3.0,
	"eagle_boss_phase": 0.0,
	"eagle_win": 1.0,
	"eagle_lose": 0.0,
	"eagle_shot": -8.0,
}

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next := 0
var _muted := false
var _warm_queue: Array[String] = []


func _ready() -> void:
	# 暂停 / 结算界面下音效仍可正常播放（不受场景 pause 影响）
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "SFX"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Ch%d" % i
		p.volume_db = BASE_VOLUME_DB
		add_child(p)
		_players.append(p)


## 播放指定音效。vol_db 为临时音量偏移。
func play(id: String, vol_db: float = 0.0) -> void:
	if _muted:
		return
	var s := stream_for(id)
	if s == null:
		push_warning("SFX: 未知音效 id '%s'" % id)
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = BASE_VOLUME_DB + float(MIX.get(id, 0.0)) + vol_db
	p.play()


## 取(并按需合成)音效流。
func stream_for(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var s := Synth.build(id)
	if s != null:
		_cache[id] = s
	return s


## 同步预热：一次性合成全部音效（约几百毫秒，只适合在主菜单空闲时调用）。
func prewarm(ids: Array[String] = []) -> void:
	for i in _all_ids(ids):
		stream_for(i)


## 异步预热：每帧合成一个，摊平开销。主菜单 _ready() 调用它最合适。
func prewarm_async(ids: Array[String] = []) -> void:
	_warm_queue = _all_ids(ids)


## 剩余待预热数量（调试用）。
func warm_remaining() -> int:
	return _warm_queue.size()


func _process(_delta: float) -> void:
	if _warm_queue.is_empty():
		return
	stream_for(_warm_queue.pop_front())


func _all_ids(ids: Array[String]) -> Array[String]:
	if not ids.is_empty():
		return ids
	return [
		"shard_spawn", "shard_tick0", "shard_tick1", "shard_tick2",
		"shard_expire", "item_get", "wind_cast", "rain_cast",
		"bolt_cast", "item_fizzle", "item_clear",
		"eagle_star", "eagle_boom", "eagle_hurt", "eagle_bomb",
		"eagle_rescue", "eagle_laser", "eagle_boss_phase",
		"eagle_win", "eagle_lose", "eagle_shot", "eagle_bgm",
	]


func set_muted(v: bool) -> void:
	_muted = v


func is_muted() -> bool:
	return _muted
