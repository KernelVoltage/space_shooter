extends Control

var music_slider: HSlider
var sound_slider: HSlider
var home_btn: Control
var shop_btn: Control

var fade_layer: CanvasLayer
var fade_rect: ColorRect
var is_switching: bool = false

func _ready() -> void:
	# 1. Find Nodes
	music_slider = find_child("MusicSlider", true, false) as HSlider
	sound_slider = find_child("SoundSlider", true, false) as HSlider
	home_btn = find_child("HomeButton", true, false) as Control
	shop_btn = find_child("ShopButton", true, false) as Control

	# 2. Fade Transition Setup
	_setup_fade_overlay()
	_fade_in_from_black()

	# 3. Audio Sliders Setup (Music + Shoot & Explosion Sound)
	if music_slider and sound_slider:
		_setup_audio_sliders()

	# 4. Buttons Setup (Deferred to prevent layout freezing issues)
	call_deferred("_setup_all_buttons")

# --- AUDIO SLIDERS LOGIC (Shoot, Explosion & Music Control) ---
func _setup_audio_sliders() -> void:
	# 🎵 Load Music Slider Initial Value
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx != -1:
		var db = AudioServer.get_bus_volume_db(music_bus_idx)
		music_slider.value = db_to_linear(db) * 100.0
	else:
		music_slider.value = 80.0

	# 💥 Load Sound Effects Slider Initial Value (Shoot & Explosion)
	var sfx_bus_idx = _get_sfx_bus_index()
	if sfx_bus_idx != -1:
		var db = AudioServer.get_bus_volume_db(sfx_bus_idx)
		sound_slider.value = db_to_linear(db) * 100.0
	else:
		sound_slider.value = 80.0

	# Connect Signals
	music_slider.value_changed.connect(_on_music_volume_changed)
	sound_slider.value_changed.connect(_on_sound_volume_changed)

# Helper Function: Finds SFX / Sound Bus Index
func _get_sfx_bus_index() -> int:
	var idx = AudioServer.get_bus_index("SFX")
	if idx == -1:
		idx = AudioServer.get_bus_index("Sound")
	if idx == -1:
		idx = AudioServer.get_bus_index("Master")
	return idx

# Music Volume Change
func _on_music_volume_changed(value: float) -> void:
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx != -1:
		var db = linear_to_db(value / 100.0) if value > 0 else -80.0
		AudioServer.set_bus_volume_db(bus_idx, db)

# Sound Effects (Shoot + Explosion) Volume Change
func _on_sound_volume_changed(value: float) -> void:
	var sfx_bus_idx = _get_sfx_bus_index()
	if sfx_bus_idx != -1:
		var db = linear_to_db(value / 100.0) if value > 0 else -80.0
		AudioServer.set_bus_volume_db(sfx_bus_idx, db)

# --- BUTTONS SETUP & FADE TRANSITION ---
func _setup_all_buttons() -> void:
	await get_tree().process_frame
	
	if home_btn:
		_setup_button(home_btn, "res://scenes/main_menu.tscn")
	if shop_btn:
		_setup_button(shop_btn, "res://scenes/shop.tscn")

func _setup_fade_overlay() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 128
	add_child(fade_layer)
	
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)

func _fade_in_from_black() -> void:
	fade_layer.show()
	fade_rect.color.a = 1.0
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(fade_rect, "color:a", 0.0, 0.25)
	
	tween.finished.connect(func():
		fade_layer.hide()
	)

func _fade_out_to_black() -> void:
	fade_layer.show()
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.25)
	await fade_tween.finished

# --- PERFECT BUTTON HOVER & CLICK ANIMATION ---
func _setup_button(btn: Control, target_scene: String) -> void:
	var orig_pos: Vector2 = btn.position
	var orig_scale: Vector2 = btn.scale
	var orig_size: Vector2 = btn.size
	
	btn.mouse_entered.connect(func():
		if not is_switching:
			var zoom_scale = orig_scale * 1.08
			var zoom_pos = orig_pos - (orig_size * orig_scale * 0.08) / 2.0
			_animate_transform(btn, zoom_pos, zoom_scale, Color(1.2, 1.2, 1.2, 1.0), 0.1)
	)
	
	btn.mouse_exited.connect(func():
		if not is_switching:
			_animate_transform(btn, orig_pos, orig_scale, Color(1.0, 1.0, 1.0, 1.0), 0.1)
	)
	
	btn.pressed.connect(func():
		if is_switching:
			return
			
		is_switching = true
		
		var bounce_scale = orig_scale * 0.92
		var bounce_pos = orig_pos + (orig_size * orig_scale * 0.08) / 2.0
		_animate_transform(btn, bounce_pos, bounce_scale, Color(0.85, 0.85, 0.85, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout
		
		_animate_transform(btn, orig_pos, orig_scale, Color(1.0, 1.0, 1.0, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout
		
		await _fade_out_to_black()
		get_tree().change_scene_to_file(target_scene)
	)

func _animate_transform(btn: Control, target_pos: Vector2, target_scale: Vector2, target_color: Color, duration: float) -> void:
	if btn.has_meta("active_tween"):
		var old_tw = btn.get_meta("active_tween") as Tween
		if old_tw and old_tw.is_valid():
			old_tw.kill()
			
	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	btn.set_meta("active_tween", tw)
	
	tw.tween_property(btn, "position", target_pos, duration)
	tw.tween_property(btn, "scale", target_scale, duration)
	tw.tween_property(btn, "modulate", target_color, duration)
