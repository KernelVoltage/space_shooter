extends Control

# ==========================================
# ⚙️ CONSTANTS & CONFIGURATION
# ==========================================
const BASE_COST: int = 100
const MAX_LEVEL: int = 10

# Dynamic pricing base costs (minimum 100)
const LASER_BASE_COST: int = 150
const LASER_COST_STEP: int = 50

const SPEED_BASE_COST: int = 100
const SPEED_COST_STEP: int = 30

# ==========================================
# 🎮 UI REFERENCES
# ==========================================
var coin_label: Label
var laser_power_button: BaseButton
var speed_button: BaseButton
var home_button: BaseButton
var setting_button: BaseButton

var laser_progress: Range
var speed_progress: Range

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	set_process(false) # Disables process loop to prevent overriding button hover tweens
	_bind_ui_nodes_dynamically()
	_update_shop_ui()

	if GameManager and GameManager.has_signal("coins_updated"):
		if not GameManager.coins_updated.is_connected(_on_coins_updated_signal):
			GameManager.coins_updated.connect(_on_coins_updated_signal)

	# Deferred button setup so layout sizing completes before caching transform math
	call_deferred("_setup_all_animated_buttons")

func _on_coins_updated_signal(_new_coins: int = 0) -> void:
	_update_shop_ui()

# ==========================================
# 🔍 DYNAMIC UI BINDING
# ==========================================
func _bind_ui_nodes_dynamically() -> void:
	var all_children = _get_all_children(self)
	var progress_bars: Array[Range] = []
	var buttons: Array[BaseButton] = []

	for child in all_children:
		if not coin_label and child is Label and "coin" in child.name.to_lower():
			coin_label = child as Label
		elif child is TextureProgressBar or child is ProgressBar:
			progress_bars.append(child as Range)
		elif child is BaseButton:
			buttons.append(child as BaseButton)

	if not coin_label:
		coin_label = find_child("CoinLabel", true, false) as Label

	if progress_bars.size() >= 2:
		laser_progress = progress_bars[0]
		speed_progress = progress_bars[1]
	elif progress_bars.size() == 1:
		laser_progress = progress_bars[0]

	for btn in buttons:
		var btn_name = btn.name.to_lower()
		if "laser" in btn_name or "power" in btn_name:
			laser_power_button = btn
		elif "speed" in btn_name:
			speed_button = btn
		elif "home" in btn_name or "close" in btn_name:
			home_button = btn
		elif "setting" in btn_name:
			setting_button = btn

	if not laser_power_button and buttons.size() >= 1:
		laser_power_button = buttons[0]
	if not speed_button and buttons.size() >= 2:
		speed_button = buttons[1]

# ==========================================
# 🎨 PERFECT BUTTON HOVER, GLOW & CLICK ANIMATION
# ==========================================
func _setup_all_animated_buttons() -> void:
	await get_tree().process_frame

	_setup_button(home_button, _on_home_clicked)
	_setup_button(setting_button, _on_setting_clicked)
	_setup_button(laser_power_button, _on_laser_upgrade_clicked)
	_setup_button(speed_button, _on_speed_upgrade_clicked)

func _setup_button(btn: BaseButton, click_action: Callable) -> void:
	if not btn:
		return

	# Maintain original scene position and scale without code relocation
	var orig_scale: Vector2 = btn.scale

	btn.mouse_entered.connect(func():
		if btn.disabled:
			return
		_animate_scale_and_color(btn, orig_scale * 1.08, Color(1.3, 1.3, 1.45, 1.0), 0.1)
	)

	btn.mouse_exited.connect(func():
		var target_color = Color(0.4, 0.4, 0.4, 0.6) if btn.disabled else Color(1.0, 1.0, 1.0, 1.0)
		_animate_scale_and_color(btn, orig_scale, target_color, 0.1)
	)

	btn.pressed.connect(func():
		if btn.disabled:
			return

		_animate_scale_and_color(btn, orig_scale * 0.92, Color(0.85, 0.85, 0.85, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout

		_animate_scale_and_color(btn, orig_scale, Color(1.0, 1.0, 1.0, 1.0), 0.05)
		await get_tree().create_timer(0.05).timeout

		click_action.call()
	)

func _animate_scale_and_color(btn: Control, target_scale: Vector2, target_color: Color, duration: float) -> void:
	if not is_instance_valid(btn):
		return

	if btn.has_meta("active_tween"):
		var old_tw = btn.get_meta("active_tween") as Tween
		if old_tw and old_tw.is_valid():
			old_tw.kill()

	var tw = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	btn.set_meta("active_tween", tw)

	# Only animates scale & modulate to keep manual scene positions intact
	tw.tween_property(btn, "scale", target_scale, duration)
	tw.tween_property(btn, "modulate", target_color, duration)

# ==========================================
# 🛒 SHOP LOGIC & UI UPDATES
# ==========================================
func _get_total_shop_coins() -> int:
	if not GameManager:
		return 0
	if "total_coins" in GameManager:
		return GameManager.total_coins
	elif "coins" in GameManager:
		return GameManager.coins
	return 0

func _update_shop_ui() -> void:
	if not GameManager:
		return

	if coin_label:
		coin_label.text = str(_get_total_shop_coins())

	var laser_lvl = _get_laser_level()
	var speed_lvl = _get_speed_level()

	if laser_progress:
		laser_progress.min_value = 0
		laser_progress.max_value = MAX_LEVEL
		laser_progress.value = laser_lvl

	if speed_progress:
		speed_progress.min_value = 0
		speed_progress.max_value = MAX_LEVEL
		speed_progress.value = speed_lvl

	_update_button_states()

func _update_button_states() -> void:
	if not GameManager:
		return

	var player_coins: int = _get_total_shop_coins()
	var laser_cost: int = _get_laser_upgrade_cost(_get_laser_level())
	var speed_cost: int = _get_speed_upgrade_cost(_get_speed_level())

	if laser_power_button:
		var disable_laser = (player_coins < laser_cost) or (_get_laser_level() >= MAX_LEVEL)
		laser_power_button.disabled = disable_laser
		laser_power_button.modulate = Color(0.4, 0.4, 0.4, 0.6) if disable_laser else Color(1, 1, 1, 1.0)

	if speed_button:
		var disable_speed = (player_coins < speed_cost) or (_get_speed_level() >= MAX_LEVEL)
		speed_button.disabled = disable_speed
		speed_button.modulate = Color(0.4, 0.4, 0.4, 0.6) if disable_speed else Color(1, 1, 1, 1.0)

# ==========================================
# 💰 UPGRADE BUTTON CLICK HANDLERS
# ==========================================
func _on_laser_upgrade_clicked() -> void:
	if not GameManager:
		return

	var current_lvl = _get_laser_level()
	var cost = _get_laser_upgrade_cost(current_lvl)

	if current_lvl < MAX_LEVEL and _get_total_shop_coins() >= cost:
		if _deduct_coins(cost):
			_set_laser_level(current_lvl + 1)
			_save_and_refresh()

func _on_speed_upgrade_clicked() -> void:
	if not GameManager:
		return

	var current_lvl = _get_speed_level()
	var cost = _get_speed_upgrade_cost(current_lvl)

	if current_lvl < MAX_LEVEL and _get_total_shop_coins() >= cost:
		if _deduct_coins(cost):
			_set_speed_level(current_lvl + 1)
			_save_and_refresh()

# ==========================================
# 🛠️ HELPER FUNCTIONS
# ==========================================
func _deduct_coins(amount: int) -> bool:
	if GameManager.has_method("spend_coins"):
		var success = GameManager.spend_coins(amount)
		if success:
			return true

	var current_total = _get_total_shop_coins()
	if current_total >= amount:
		if "total_coins" in GameManager:
			GameManager.total_coins -= amount
		elif "coins" in GameManager:
			GameManager.coins -= amount

		if GameManager.has_signal("coins_updated"):
			GameManager.coins_updated.emit(_get_total_shop_coins())
		return true

	return false

func _get_upgrade_cost(level: int) -> int:
	return _get_laser_upgrade_cost(level)

func _get_laser_upgrade_cost(level: int) -> int:
	return LASER_BASE_COST + ((level - 1) * LASER_COST_STEP)

func _get_speed_upgrade_cost(level: int) -> int:
	return SPEED_BASE_COST + ((level - 1) * SPEED_COST_STEP)

func _get_laser_level() -> int:
	if "laser_damage_level" in GameManager:
		return GameManager.laser_damage_level
	elif "level_laser_damage" in GameManager:
		return GameManager.level_laser_damage
	return 1

func _set_laser_level(new_lvl: int) -> void:
	if "laser_damage_level" in GameManager:
		GameManager.laser_damage_level = new_lvl
	if "level_laser_damage" in GameManager:
		GameManager.level_laser_damage = new_lvl

func _get_speed_level() -> int:
	if "level_speed_upgrade" in GameManager:
		return GameManager.level_speed_upgrade
	elif "speed_level" in GameManager:
		return GameManager.speed_level
	return 1

func _set_speed_level(new_lvl: int) -> void:
	if "level_speed_upgrade" in GameManager:
		GameManager.level_speed_upgrade = new_lvl
	if "speed_level" in GameManager:
		GameManager.speed_level = new_lvl

func _save_and_refresh() -> void:
	if GameManager.has_method("save_game_data"):
		GameManager.save_game_data()
	_update_shop_ui()

func _on_home_clicked() -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	else:
		queue_free()

func _on_setting_clicked() -> void:
	if ResourceLoader.exists("res://scenes/settings.tscn"):
		get_tree().change_scene_to_file("res://scenes/settings.tscn")

func _get_all_children(node: Node) -> Array[Node]:
	var list: Array[Node] = []
	for child in node.get_children():
		list.append(child)
		list.append_array(_get_all_children(child))
	return list
