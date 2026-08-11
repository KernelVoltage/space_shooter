extends Control

# ==========================================
# 🎮 ONREADY NODE REFERENCES
# ==========================================
@onready var game_over_panel: Control = get_node_or_null("GameOverPanel")
@onready var title_label: Label = get_node_or_null("GameOverPanel/Title")
@onready var retry_btn: Control = get_node_or_null("GameOverPanel/RetryButton")
@onready var setting_btn: Control = get_node_or_null("GameOverPanel/SettingButton")
@onready var shop_btn: Control = get_node_or_null("GameOverPanel/ShopButton")
@onready var close_btn: Control = get_node_or_null("GameOverPanel/Close")
@onready var coin_label: Label = get_node_or_null("GameOverPanel/CoinLabel")
@onready var coin_icon: Control = get_node_or_null("GameOverPanel/Coin")
@onready var missed_label: Label = get_node_or_null("GameOverPanel/MissedLabel")
@onready var missed_value: Label = get_node_or_null("GameOverPanel/MissedValue")

# Optional Stat Display Labels (Auto-detected if present)
var reason_label: Label = null
var score_label: Label = null
var kills_label: Label = null

# ==========================================
# 📡 SIGNALS
# ==========================================
signal restart_pressed
signal setting_pressed
signal shop_pressed
signal resume_pressed

var background_overlay: ColorRect

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	_find_optional_stat_nodes()
	_setup_background_overlay()
	_setup_ui_elements()
	
	_init_button(retry_btn, func(): emit_signal("restart_pressed"))
	_init_button(setting_btn, func(): emit_signal("setting_pressed"))
	_init_button(shop_btn, func(): emit_signal("shop_pressed"))
	_init_button(close_btn, func(): emit_signal("resume_pressed"))

func _find_optional_stat_nodes() -> void:
	if game_over_panel:
		reason_label = game_over_panel.find_child("ReasonLabel", true, false) as Label
		score_label = game_over_panel.find_child("ScoreLabel", true, false) as Label
		kills_label = game_over_panel.find_child("KillsLabel", true, false) as Label

func _setup_background_overlay() -> void:
	background_overlay = ColorRect.new()
	background_overlay.color = Color(0, 0, 0, 0.65)
	background_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_overlay.show_behind_parent = true
	add_child(background_overlay)

func _setup_ui_elements() -> void:
	if coin_icon:
		coin_icon.custom_minimum_size = Vector2(40, 40)
		coin_icon.size = Vector2(40, 40)
		if coin_icon is TextureRect:
			coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	# Increased font size for coin label so it's larger and clearer
	if coin_label:
		coin_label.add_theme_font_size_override("font_size", 34)
		coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		coin_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	# Increased font size for missed labels and adjusted vertical positions downwards
	if missed_label:
		missed_label.add_theme_font_size_override("font_size", 32)
		missed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		missed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		missed_label.position.y += 15
		
	if missed_value:
		missed_value.add_theme_font_size_override("font_size", 32)
		missed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		missed_value.autowrap_mode = TextServer.AUTOWRAP_OFF
		missed_value.position.y += 15

func _init_button(btn: Control, callback: Callable) -> void:
	if not btn: 
		return
	
	btn.pivot_offset = btn.size / 2.0
	if not btn.resized.is_connected(_on_button_resized.bind(btn)):
		btn.resized.connect(_on_button_resized.bind(btn))
	
	if btn is BaseButton:
		if not btn.pressed.is_connected(callback):
			btn.pressed.connect(callback)
	else:
		if not btn.is_connected("gui_input", callback):
			btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					callback.call()
			)
	
	var orig_scale = btn.scale
	
	btn.mouse_entered.connect(func():
		var tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(btn, "scale", orig_scale * 1.08, 0.1)
		tween.tween_property(btn, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.1)
	)
	
	btn.mouse_exited.connect(func():
		var tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(btn, "scale", orig_scale, 0.1)
		tween.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	)

func _on_button_resized(btn: Control) -> void:
	if btn:
		btn.pivot_offset = btn.size / 2.0

# ==========================================
# 📊 PANEL SETUP & DISPLAY
# ==========================================
func setup_panel(is_paused: bool, current_coins: int = 0, custom_reason: String = "") -> void:
	visible = true
	
	# Fetch Coins
	var display_coins = current_coins
	if display_coins == 0 and GameManager:
		if "coins" in GameManager:
			display_coins = GameManager.coins
		elif "score" in GameManager:
			display_coins = GameManager.score
			
	if coin_label:
		coin_label.text = str(display_coins)

	# Fetch Game Statistics
	var missed_cnt: int = 0
	if GameManager:
		if "missed_enemies" in GameManager:
			missed_cnt = GameManager.missed_enemies
		if score_label and "score" in GameManager:
			score_label.text = "SCORE: " + str(GameManager.score)
		if kills_label and "kills" in GameManager:
			kills_label.text = "KILLS: " + str(GameManager.kills)

	# Update Missed Values for separate labels or combined
	if missed_value:
		missed_value.text = str(missed_cnt)
	elif missed_label:
		missed_label.text = "MISSED: " + str(missed_cnt) + " / 3"
		
	# Setup Panel Mode (Paused vs Game Over)
	if is_paused:
		if title_label: 
			title_label.text = "GAME PAUSED"
		if reason_label: 
			reason_label.text = ""
		if close_btn: 
			close_btn.visible = true
	else:
		if title_label: 
			if custom_reason != "":
				title_label.text = custom_reason
			elif missed_cnt >= 3 or "ESCAPED" in custom_reason.to_upper():
				title_label.text = "3+ ENEMIES ESCAPED!"
			else:
				title_label.text = "GAME OVER!"
				
		if reason_label: 
			if custom_reason != "":
				reason_label.text = custom_reason
			elif missed_cnt >= 3:
				reason_label.text = "3 ENEMIES ESCAPED"
			else:
				reason_label.text = "SHIP DESTROYED"
				
		if close_btn: 
			close_btn.visible = false

	# Wait a frame for bounding box computations
	await get_tree().process_frame
	_update_dynamic_layouts()

	if game_over_panel:
		game_over_panel.modulate.a = 0.0
		var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.2)

# ==========================================
# 📐 LAYOUT ALIGNMENT
# ==========================================
func _update_dynamic_layouts() -> void:
	# Coin alignment if dynamic positioning is needed
	if coin_icon and coin_label and not coin_label.is_set_as_top_level():
		var icon_w = coin_icon.size.x * coin_icon.scale.x
		var icon_h = coin_icon.size.y * coin_icon.scale.y
		if icon_w <= 0.0: icon_w = 40.0
		if icon_h <= 0.0: icon_h = 40.0
		
		# Optional safeguard if absolute alignment is overridden
		pass
