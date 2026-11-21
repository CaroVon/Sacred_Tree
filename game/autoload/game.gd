extends Node
## 持有当前 RunState，负责场景切换与存档。场景之间不直接互相引用。

const SAVE_PATH := "user://save.json"
## 多局之间的收藏与解锁。
const PROFILE_PATH := "user://profile.json"
const SCENES := {
	&"menu": "res://scenes/menu/menu.tscn",
	&"season": "res://scenes/season/season.tscn",
	&"map": "res://scenes/map/year_map.tscn",
	&"market": "res://scenes/market/market.tscn",
	&"codex": "res://scenes/codex/codex.tscn",
}

const SETTINGS_PATH := "user://settings.cfg"
const SFX := [&"place", &"prune", &"pulse", &"tip", &"click", &"win", &"lose"]

var run: RunState
## 收藏与解锁（流派、启程者、图鉴统计、联动谱）。
var profile: Profile
## 待显示的解锁 / 联动消息（下一个场景取走后清空）。
var notices: Array[String] = []
## 设置：减少动效、音量（0..1）。
var reduce_motion: bool = false
## 新手指导进行中（不存档）；以及是否完成过。
var tutorial: Tutorial
var tutorial_done: bool = false
var volume: float = 0.75

var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
## 正在做转场 wipe，避免连点时叠加。
var _wiping: bool = false


func _ready() -> void:
	get_tree().root.theme = Palette.make_theme()
	RenderingServer.set_default_clear_color(Palette.PAPER)
	load_settings()
	profile = Profile.load_from(PROFILE_PATH)
	for id in SFX:
		var path := "res://assets/sfx/%s.wav" % id
		if ResourceLoader.exists(path):
			_sfx[id] = load(path)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_add_paper_overlay()


## 全屏纸纹（正片叠底），盖在所有界面之上、不拦截鼠标。
func _add_paper_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/paper.gdshader")
	rect.material = mat
	layer.add_child(rect)


func sfx(id: StringName, pitch: float = 1.0) -> void:
	if volume <= 0.0 or not _sfx.has(id):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sfx[id]
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(volume)
			p.play()
			return


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
		volume = float(cfg.get_value("audio", "volume", 0.75))
		tutorial_done = bool(cfg.get_value("ui", "tutorial_done", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("ui", "tutorial_done", tutorial_done)
	cfg.save(SETTINGS_PATH)


## 图鉴关闭后回到哪个场景。
var codex_return: StringName = &"menu"


func open_codex(from: StringName) -> void:
	codex_return = from
	goto(&"codex")


func goto(scene: StringName) -> void:
	var path: String = SCENES[scene]
	if reduce_motion:
		get_tree().change_scene_to_file.call_deferred(path)
		return
	_wipe(func(): get_tree().change_scene_to_file.call_deferred(path))


## 换场景时纸色从画面中心像墨一样晕开（带一圈墨边），盖满后换场景，再晕散回去。
func _wipe(cb: Callable) -> void:
	if _wiping:
		cb.call()
		return
	_wiping = true
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/transition.gdshader")
	var vs := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("aspect", Vector2(vs.x / maxf(1.0, vs.y), 1.0))
	mat.set_shader_parameter("paper", Palette.SHEET)
	mat.set_shader_parameter("ink", Palette.INK)
	mat.set_shader_parameter("seed", randf() * 50.0)
	mat.set_shader_parameter("progress", 0.0)
	rect.material = mat
	layer.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	cb.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := rect.create_tween()
	tw2.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 1.0, 0.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw2.finished
	layer.queue_free()
	_wiping = false


func start_tutorial() -> void:
	tutorial = Tutorial.new()
	run = Tutorial.make_run()
	goto(&"season")


func finish_tutorial() -> void:
	tutorial = null
	tutorial_done = true
	save_settings()
	run = load_save()


func new_run(run_seed: int = -1, starter: StringName = &"gardener") -> void:
	tutorial = null
	if not profile.has_starter(starter):
		starter = &"gardener"
	run = RunState.create(run_seed, starter, profile.families())
	profile.record_run_start()
	save()
	goto(&"map")


func continue_run() -> void:
	var r := load_save()
	if r:
		tutorial = null
		run = r
		match r.phase:
			RunState.Phase.MARKET:
				goto(&"market")
			RunState.Phase.PLAY:
				goto(&"map" if r.turn == 1 and r.score == 0 else &"season")
			_:
				goto(&"season")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and load_save() != null


## 局内状态写入存档；已经结束的局删除存档。
func save() -> void:
	if run == null or tutorial != null:
		return
	if run.phase == RunState.Phase.LOST or run.phase == RunState.Phase.WON:
		clear_save()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(run.to_dict()))


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func load_save() -> RunState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (d is Dictionary) or int(d.get("version", 0)) != RunState.SAVE_VERSION:
		return null
	return RunState.from_dict(d)
