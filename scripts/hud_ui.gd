extends Control

# ==========================================
# 🎮 ONREADY NODE REFERENCES
# ==========================================
@onready var health_bar: ProgressBar = get_node_or_null("VBoxContainer/HealthContainer/HealthBar") as ProgressBar
@onready var coin_icon: TextureRect = get_node_or_null("VBoxContainer/CoinContainer/CoinIcon") as TextureRect
@onready var coin_label: Label = get_node_or_null("VBoxContainer/CoinContainer/CoinLabel") as Label
@onready var powerup_list: VBoxContainer = get_node_or_null("VBoxContainer/PowerupList") as VBoxContainer

# Dynamic Reference for Missed Enemies Display
var missed_label: Label = null

# ==========================================
# ⚙️ INTERNAL VARIABLES
# ==========================================
var health_stylebox: StyleBoxFlat
var active_powerups: Dictionary = {}
var total_coins: int = 0
var total_missed: int = 0
var health_tween: Tween = null

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	name = "HUD"
	if not is_in_group("hud"):
		add_to_group("hud")
	
	_setup_dynamic_health_bar()
	_setup_coin_container_ui()
	_setup_missed_label_ui()
	
	# Initial GameManager Signals and Sync
	if GameManager:
		if GameManager.has_signal("coins_updated") and not GameManager.coins_updated.is_connected(update_coins):
			GameManager.coins_updated.connect(update_coins)
			
		if GameManager.has_signal("missed_enemies_updated") and not GameManager.missed_enemies_updated.is_connected(update_missed_enemies):
			GameManager.missed_enemies_updated.connect(update_missed_enemies)
			
		# Sync HUD display with the active match run coin count
		if "current_coins" in GameManager:
			total_coins = GameManager.current_coins
		elif "coins" in GameManager:
			total_coins = GameManager.coins
			
		if "missed_enemies" in GameManager:
			total_missed = GameManager.missed_enemies
			
	update_coins(total_coins)
	update_missed_enemies(total_missed)

func _process(delta: float) -> void:
	var to_remove: Array[String] = []
	
	for powerup_id in active_powerups.keys():
		var data = active_powerups[powerup_id]
		data["time_left"] -= delta
		
		if is_instance_valid(data["bar"]) and data["total_time"] > 0.0:
			data["bar"].value = clamp((data["time_left"] / data["total_time"]) * 100.0, 0.0, 100.0)
			
		if data["time_left"] <= 0.0:
			to_remove.append(powerup_id)

	for powerup_id in to_remove:
		remove_powerup_item(powerup_id)

# ==========================================
# 🎨 UI SETUP & FORMATTING
# ==========================================
func _setup_coin_container_ui() -> void:
	if coin_icon:
		coin_icon.custom_minimum_size = Vector2(24, 24)
		coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
	if coin_label:
		coin_label.add_theme_font_size_override("font_size", 20)

func _setup_dynamic_health_bar() -> void:
	if health_bar:
		health_stylebox = StyleBoxFlat.new()
		health_bar.add_theme_stylebox_override("fill", health_stylebox)

func _setup_missed_label_ui() -> void:
	# Locate or dynamically construct the Missed Enemy counter inside the VBoxContainer
	missed_label = find_child("MissedLabel", true, false) as Label
	
	if not missed_label:
		var vbox = get_node_or_null("VBoxContainer")
		if vbox:
			missed_label = Label.new()
			missed_label.name = "MissedLabel"
			missed_label.add_theme_font_size_override("font_size", 18)
			# WHITE COLOR OVERRIDE
			missed_label.add_theme_color_override("font_color", Color.WHITE)
			vbox.add_child(missed_label)
	else:
		# Enforce white font color override if node already exists
		missed_label.add_theme_color_override("font_color", Color.WHITE)

# ==========================================
# 📊 HEALTH & STAT UPDATES
# ==========================================
func update_health(current_hp: float, max_hp: float) -> void:
	if not health_bar:
		return
		
	health_bar.max_value = max_hp
	
	if health_tween and health_tween.is_valid():
		health_tween.kill()
		
	health_tween = create_tween()
	health_tween.tween_property(health_bar, "value", current_hp, 0.25).set_trans(Tween.TRANS_SINE)
	
	var hp_ratio: float = clamp(current_hp / max_hp, 0.0, 1.0)
	var bar_color: Color
	
	if hp_ratio > 0.6:
		bar_color = Color.GREEN.lerp(Color.YELLOW, (1.0 - hp_ratio) / 0.4)
	elif hp_ratio > 0.3:
		bar_color = Color.YELLOW.lerp(Color.ORANGE, (0.6 - hp_ratio) / 0.3)
	else:
		bar_color = Color.ORANGE.lerp(Color.RED, (0.3 - hp_ratio) / 0.3)
		
	if health_stylebox:
		health_stylebox.bg_color = bar_color

func update_coins(amount: int) -> void:
	total_coins = amount
	if coin_label:
		coin_label.text = " " + str(total_coins)

func update_missed_enemies(count: int) -> void:
	total_missed = count
	if missed_label:
		missed_label.text = "MISSED: " + str(total_missed) + " / 3"

func add_coins_to_total(amount: int) -> void:
	total_coins += amount
	if GameManager:
		if "current_coins" in GameManager:
			GameManager.current_coins = total_coins
		elif "coins" in GameManager:
			GameManager.coins = total_coins
	update_coins(total_coins)

# ==========================================
# 🛡️ POWERUP LIST MANAGEMENT
# ==========================================
func _normalize_powerup_id(raw_id: String) -> String:
	var upper = raw_id.to_upper().strip_edges()
	if "SHIELD" in upper: return "SHIELD"
	if "ENERGY" in upper or "FIRE" in upper: return "ENERGY"
	if "STAR" in upper or "TRIPLE" in upper: return "STAR"
	if "PURPLE" in upper or "OVERCHARGE" in upper or "BEAM" in upper: return "PURPLE"
	if "SLOW" in upper or "GREEN" in upper: return "GREEN_CRYSTAL"
	if "MAGNET" in upper: return "MAGNET"
	return upper

func add_or_update_powerup(powerup_id: String, icon_path: String, duration: float, current_level: int = 1) -> void:
	if not powerup_list:
		return
		
	var id_key: String = _normalize_powerup_id(powerup_id)
	var badge_text: String = "MAX" if current_level >= 3 else "Lx" + str(current_level)
		
	# Refresh existing card
	if active_powerups.has(id_key):
		var data = active_powerups[id_key]
		data["time_left"] = duration
		data["total_time"] = max(duration, 0.01)
		
		if is_instance_valid(data["bar"]):
			data["bar"].value = 100.0
			
		if is_instance_valid(data["container"]):
			data["container"].modulate.a = 1.0
			
		if data.has("level_label") and is_instance_valid(data["level_label"]):
			data["level_label"].text = badge_text
		return

	# Create new card
	var card = HBoxContainer.new()
	card.name = "Powerup_" + id_key
	card.custom_minimum_size = Vector2(180, 28)
	
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var tex: Texture2D = null
	if GameManager and GameManager.has_method("get_cached_texture"):
		tex = GameManager.get_cached_texture(icon_path)
	elif ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
		
	if tex:
		icon.texture = tex
	card.add_child(icon)
	
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.value = 100.0
	
	var style_fill = StyleBoxFlat.new()
	var path_upper = icon_path.to_upper()
	
	if "SHIELD" in path_upper or "SHIELD" in id_key:
		style_fill.bg_color = Color(0.1, 0.6, 1.0)
	elif "ENERGY" in path_upper or "ENERGY" in id_key:
		style_fill.bg_color = Color(1.0, 0.8, 0.0)
	elif "PURPLE" in path_upper or "PURPLE" in id_key:
		style_fill.bg_color = Color(0.6, 0.1, 0.9)
	elif "STAR" in path_upper or "STAR" in id_key:
		style_fill.bg_color = Color(0.8, 0.2, 1.0)
	else:
		style_fill.bg_color = Color(0.2, 0.9, 0.3)
		
	style_fill.corner_radius_top_left = 4
	style_fill.corner_radius_bottom_left = 4
	style_fill.corner_radius_top_right = 4
	style_fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", style_fill)
	card.add_child(bar)
	
	var lvl_label = Label.new()
	lvl_label.text = badge_text
	lvl_label.add_theme_font_size_override("font_size", 12)
	lvl_label.add_theme_color_override("font_color", Color.GOLD)
	card.add_child(lvl_label)
	
	powerup_list.add_child(card)
	
	active_powerups[id_key] = {
		"container": card,
		"bar": bar,
		"level_label": lvl_label,
		"time_left": duration,
		"total_time": max(duration, 0.01)
	}

func remove_powerup_item(powerup_id: String) -> void:
	var id_key: String = _normalize_powerup_id(powerup_id)
	if active_powerups.has(id_key):
		var card = active_powerups[id_key]["container"]
		active_powerups.erase(id_key)
		
		if is_instance_valid(card):
			var tween = create_tween()
			tween.tween_property(card, "modulate:a", 0.0, 0.2)
			tween.chain().tween_callback(card.queue_free)

# ==========================================
# 💬 FLOATING TEXT EFFECTS
# ==========================================
func spawn_floating_text(pos: Vector2, text_val: String) -> void:
	var float_label = Label.new()
	float_label.text = text_val
	
	var screen_pos: Vector2 = get_canvas_transform() * pos
	float_label.global_position = screen_pos
	
	float_label.add_theme_color_override("font_color", Color.GOLD)
	float_label.add_theme_font_size_override("font_size", 22)
	add_child(float_label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(float_label, "global_position:y", screen_pos.y - 50.0, 0.8)
	tween.tween_property(float_label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(float_label.queue_free)
