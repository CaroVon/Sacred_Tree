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
	&"event": "res://scenes/event/event.tscn",
}

const SETTINGS_PATH := "user://settings.cfg"
const SFX := [&"place", &"prune", &"pulse", &"tip", &"click", &"win", &"lose",
	&"slam", &"boom", &"pattern", &"chord", &"overkill", &"goal", &"flow", &"draw", &"reward", &"banner", &"season", &"shatter"]
## 音乐与环境音：按季节 / 天灾 / 场景选曲（文件在 assets/music、assets/ambience，由 tools/audio/synth_audio.py 合成）。
const SEASON_MUSIC := {1: &"spring", 2: &"summer", 3: &"autumn", 4: &"winter", 5: &"calamity"}
const SEASON_AMB := {1: &"birds", 2: &"crickets", 3: &"wind", 4: &"winter_wind", 5: &"wind"}
const CALAMITY_AMB := {&"flood": &"rain", &"lightning": &"rain", &"wildfire": &"fire", &"gale": &"wind",
	&"drought": &"wind", &"pests": &"crickets", &"eclipse": &"winter_wind"}

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
## 音乐、环境音音量（0..1）；volume 是音效音量。
var music_volume: float = 0.55
var ambience_volume: float = 0.5
var _music: Array[AudioStreamPlayer] = []
var _amb: Array[AudioStreamPlayer] = []
var _music_id: StringName = &""
var _amb_id: StringName = &""
var _streams: Dictionary = {}

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
	_setup_buses()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		add_child(m)
		_music.append(m)
		var a := AudioStreamPlayer.new()
		a.bus = &"Ambience"
		add_child(a)
		_amb.append(a)
	apply_volumes()
	_add_paper_overlay()


## 三条总线：音乐、环境音、音效，都送进 Master。
func _setup_buses() -> void:
	for nm in [&"Music", &"Ambience", &"SFX"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, &"Master")


func apply_volumes() -> void:
	for pair in [[&"Music", music_volume], [&"Ambience", ambience_volume], [&"SFX", volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, pair[1])))
			AudioServer.set_bus_mute(i, pair[1] <= 0.0)


func _loop_stream(dir: String, id: StringName) -> AudioStream:
	var key := dir + String(id)
	if _streams.has(key):
		return _streams[key]
	var path := "res://assets/%s/%s.wav" % [dir, id]
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_streams[key] = st
	return st


## 交叉淡入一首循环（音乐或环境音）。id 为空时淡出。
func _crossfade(players: Array[AudioStreamPlayer], st: AudioStream, fade: float) -> void:
	var cur := players[0]
	var nxt := players[1]
	players.reverse()
	if cur.playing:
		var t1 := cur.create_tween()
		t1.tween_property(cur, "volume_db", -60.0, fade)
		t1.tween_callback(cur.stop)
	if st == null:
		return
	nxt.stream = st
	nxt.volume_db = -60.0
	nxt.play(randf() * st.get_length() * 0.5)
	var t2 := nxt.create_tween()
	t2.tween_property(nxt, "volume_db", 0.0, fade)


func play_music(id: StringName, fade: float = 1.6) -> void:
	if id == _music_id:
		return
	_music_id = id
	_crossfade(_music, _loop_stream("music", id) if id != &"" else null, fade)


func play_ambience(id: StringName, fade: float = 2.0) -> void:
	if id == _amb_id:
		return
	_amb_id = id
	_crossfade(_amb, _loop_stream("ambience", id) if id != &"" else null, fade)


## 场景氛围：季节曲 + 季节 / 天灾环境音；scene 为 menu / codex 时放主题曲，market / map / event 放集市曲。
func scene_audio(scene: StringName, season: int = 1, calamity: StringName = &"") -> void:
	match scene:
		&"menu", &"codex":
			play_music(&"theme")
			play_ambience(&"wind")
		&"market", &"map", &"event":
			play_music(&"market")
			play_ambience(SEASON_AMB.get(mini(season, 4), &"wind"))
		_:
			play_music(SEASON_MUSIC.get(season, &"spring"))
			var amb: StringName = SEASON_AMB.get(season, &"wind")
			if season == 5 and CALAMITY_AMB.has(calamity):
				amb = CALAMITY_AMB[calamity]
			play_ambience(amb)


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


func sfx(id: StringName, pitch: float = 1.0, gain_db: float = 0.0) -> void:
	if volume <= 0.0 or not _sfx.has(id):
		return
	# 先找空闲的播放器；都在响时抢播放得最久的那个（不再直接丢掉新音效）
	var pick: AudioStreamPlayer = null
	var oldest := -1.0
	for p in _players:
		if not p.playing:
			pick = p
			break
		var pos := p.get_playback_position()
		if pos > oldest:
			oldest = pos
			pick = p
	pick.stream = _sfx[id]
	pick.pitch_scale = pitch
	pick.volume_db = gain_db
	pick.play()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
		volume = float(cfg.get_value("audio", "volume", 0.75))
		music_volume = float(cfg.get_value("audio", "music", 0.55))
		ambience_volume = float(cfg.get_value("audio", "ambience", 0.5))
		tutorial_done = bool(cfg.get_value("ui", "tutorial_done", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
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
		push_warning("启程者 %s 不存在或未解锁，改用园丁" % starter)
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
			RunState.Phase.EVENT:
				goto(&"event")
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
