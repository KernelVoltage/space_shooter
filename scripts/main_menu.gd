extends Control

var play_btn: Control
var setting_btn: Control
var shop_btn: Control
var info_btn: Control

var fade_layer: CanvasLayer
var fade_rect: ColorRect
var is_switching: bool = false

func _ready() -> void:
	# 1. Auto-Find Nodes (VBoxContainer Tree Safety)
	play_btn = find_child("PlayButton", true, false) as Control
	setting_btn = find_child("SettingButton", true, false) as Control
	shop_btn = find_child("ShopButton", true, false) as Control
	info_btn = find_child("information", true, false) as Control # <--- 2. Found button here

	# 2. Black Fade Overlay Setup & Failsafe Fade In
	_setup_fade_overlay()
	_fade_in_from_black()

	# 3. Buttons Setup (Deferred so VBoxContainer layout gets fixed)
	call_deferred("_setup_all_buttons")

func _setup_all_buttons() -> void:
	await get_tree().process_frame # Let Godot finish the layout
	
	if play_btn:
		_setup_button(play_btn, "res://scenes/main.tscn")
		
	if setting_btn:
		var setting_path = "res://scenes/settings.tscn" if ResourceLoader.exists("res://scenes/settings.tscn") else "res://scenes/setting.tscn"
		_setup_button(setting_btn, setting_path)
		
	if shop_btn:
		_setup_button(shop_btn, "res://scenes/shop.tscn")
		
	if info_btn:
		# <--- 3. Set the link for the info button here
		_setup_url_button(info_btn, "https://github.com/KernelVoltage/space_shooter")

# --- SAFE FADE TRANSITION SYSTEM (Black Screen Bug Fixed) ---
func _setup_fade_overlay() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 128
	add_child(fade_layer)
	
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)

# Screen Open Fade-In
func _fade_in_from_black() -> void:
	fade_layer.show()
	fade_rect.color.a = 1.0
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(fade_rect, "color:a", 0.0, 0.25)
	
	# FIX: Hide the layer as soon as the animation completes
	tween.finished.connect(func():
		fade_layer.hide()
	)

func _fade_out_to_black() -> void:
	fade_layer.show()
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.25)
	await fade_tween.finished

# --- STANDARD BUTTON SETUP (For scene changes) ---
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

# --- URL BUTTON SETUP (New function for Information button) ---
func _setup_url_button(btn: Control, url: String) -> void:
	var orig_pos: Vector2 = btn.position
	var orig_scale: Vector2 = btn.scale
	var orig_size: Vector2 = btn.size
	
	btn.mouse_entered.connect(func():
		var zoom_scale = orig_scale * 1.08
		var zoom_pos = orig_pos - (orig_size * orig_scale * 0.08) / 2.0
		_animate_transform(btn, zoom_pos, zoom_scale, Color(1.2, 1.2, 1.2, 1.0), 0.1)
	)
	
	btn.mouse_exited.connect(func():
		_animate_transform(btn, orig_pos, orig_scale, Color(1.0, 1.0, 1.0, 1.0), 0.1)
	)
	
	btn.pressed.connect(func():
		var bounce_scale = orig_scale * 0.92
		var bounce_pos = orig_pos + (orig_size * orig_scale * 0.08) / 2.0
		_animate_transform(btn, bounce_pos, bounce_scale, Color(0.85, 0.85, 0.85, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout
		
		_animate_transform(btn, orig_pos, orig_scale, Color(1.0, 1.0, 1.0, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout
		
		# Open the specified URL in the default web browser
		OS.shell_open(url)
	)

# Transform Animation Helper
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
