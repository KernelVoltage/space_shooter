extends Area2D

enum PowerupType {
	HEART,
	MEDICAL_PLUS,
	SHIELD,
	ENERGY,
	STAR,
	GREEN_CRYSTAL,
	PURPLE_CRYSTAL,
	MAGNET,
	COIN
}

@export var type: PowerupType = PowerupType.COIN
@export var fall_speed: float = 180.0
@export var magnet_pull_speed: float = 650.0

@onready var sprite: Sprite2D = $Sprite2D
var coin_value: int = 50
var is_being_magnetized: bool = false
var value_label: Label = null
var target_player: Node2D = null

const ICON_PATHS = {
	PowerupType.HEART: "res://asstes/Icons/Heart.png",
	PowerupType.MEDICAL_PLUS: "res://asstes/Icons/Medical_Plus.png",
	PowerupType.SHIELD: "res://asstes/Icons/Shield.png",
	PowerupType.ENERGY: "res://asstes/Icons/Energy.png",
	PowerupType.STAR: "res://asstes/Icons/Star.png",
	PowerupType.GREEN_CRYSTAL: "res://asstes/Icons/Green_Crystal.png",
	PowerupType.PURPLE_CRYSTAL: "res://asstes/Icons/Purple_Crystal.png",
	PowerupType.MAGNET: "res://asstes/Icons/Energy.png",
	PowerupType.COIN: "res://asstes/Icons/Coin.png"
}

func _ready() -> void:
	if not is_in_group("powerup"):
		add_to_group("powerup")
		
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
		
	setup_type(type)

func setup_random_type() -> void:
	# 45% Chance for COIN, 55% for all other Powerups combined
	var rand_val = randf() * 100.0
	
	if rand_val <= 45.0:
		setup_type(PowerupType.COIN)
	else:
		var other_types = [
			PowerupType.HEART,
			PowerupType.MEDICAL_PLUS,
			PowerupType.SHIELD,
			PowerupType.ENERGY,
			PowerupType.STAR,
			PowerupType.GREEN_CRYSTAL,
			PowerupType.PURPLE_CRYSTAL,
			PowerupType.MAGNET
		]
		var chosen_type = other_types[randi() % other_types.size()]
		setup_type(chosen_type)

func setup_type(p_type: int) -> void:
	type = p_type as PowerupType
	if not is_node_ready():
		await ready

	var path: String = ICON_PATHS.get(type, "res://asstes/Icons/Coin.png")

	var tex: Texture2D = null
	if GameManager and GameManager.has_method("get_cached_texture"):
		tex = GameManager.get_cached_texture(path)
	elif ResourceLoader.exists(path):
		tex = load(path) as Texture2D

	if tex and sprite:
		sprite.texture = tex
		sprite.scale = Vector2(1.2, 1.2)

	# COIN TOP-RIGHT AMOUNT TEXT SETUP
	if type == PowerupType.COIN:
		var amounts = [10, 20, 50, 100, 200]
		coin_value = amounts[randi() % amounts.size()]
		_create_top_right_label("+" + str(coin_value))

func _create_top_right_label(txt: String) -> void:
	if value_label:
		value_label.text = txt
		return
		
	value_label = Label.new()
	value_label.text = txt
	value_label.position = Vector2(10, -20)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	add_child(value_label)

func _process(delta: float) -> void:
	if is_being_magnetized:
		if not is_instance_valid(target_player):
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				target_player = players[0]
				
		if is_instance_valid(target_player):
			global_position = global_position.move_toward(target_player.global_position, magnet_pull_speed * delta)
		else:
			global_position.y += fall_speed * delta
	else:
		global_position.y += fall_speed * delta

	if global_position.y > 1350:
		queue_free()

func trigger_magnet_pull(player_node: Node2D = null) -> void:
	is_being_magnetized = true
	if player_node:
		target_player = player_node

func _on_area_entered(area: Area2D) -> void:
	_handle_collision(area)

func _on_body_entered(body: Node2D) -> void:
	_handle_collision(body)

func _handle_collision(node: Node) -> void:
	var target = node
	if not target.is_in_group("player") and target.get_parent() and target.get_parent().is_in_group("player"):
		target = target.get_parent()

	if target.is_in_group("player") or target.name == "Player" or target.name == "player":
		apply_powerup_effect(target)
		queue_free()

func apply_powerup_effect(player: Node) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		hud = get_tree().root.find_child("HUD", true, false)
	
	match type:
		PowerupType.HEART:
			_call_player_method(player, ["heal", "add_health", "restore_health"], [30.0])
			if hud and hud.has_method("spawn_floating_text"):
				hud.spawn_floating_text(global_position, "+30 HP")

		PowerupType.MEDICAL_PLUS:
			_call_player_method(player, ["upgrade_max_health", "add_max_health", "increase_max_hp"], [25.0])
			if hud and hud.has_method("spawn_floating_text"):
				hud.spawn_floating_text(global_position, "MAX HP UP!")

		PowerupType.SHIELD:
			_call_player_method(player, ["activate_shield", "enable_shield", "add_shield"], [6.0])
			var lvl: int = _get_player_stat(player, ["shield_level", "shield_lvl"], 1)
			if hud and hud.has_method("add_or_update_powerup"):
				hud.add_or_update_powerup("SHIELD", ICON_PATHS[PowerupType.SHIELD], 6.0, lvl)

		PowerupType.ENERGY:
			_call_player_method(player, ["boost_fire_rate", "upgrade_fire_rate", "activate_energy"], [5.0])
			var lvl: int = _get_player_stat(player, ["energy_level", "fire_rate_level"], 1)
			if hud and hud.has_method("add_or_update_powerup"):
				hud.add_or_update_powerup("ENERGY", ICON_PATHS[PowerupType.ENERGY], 5.0, lvl)

		PowerupType.STAR:
			_call_player_method(player, ["activate_triple_shot", "enable_triple_shot", "upgrade_weapons"], [8.0])
			var lvl: int = _get_player_stat(player, ["star_level", "triple_shot_level"], 1)
			if hud and hud.has_method("add_or_update_powerup"):
				hud.add_or_update_powerup("STAR", ICON_PATHS[PowerupType.STAR], 8.0, lvl)

		PowerupType.GREEN_CRYSTAL:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if "speed" in enemy: enemy.speed *= 0.5
				if "current_speed" in enemy: enemy.current_speed *= 0.5
			if hud and hud.has_method("spawn_floating_text"):
				hud.spawn_floating_text(global_position, "SLOW MOTION!")

		PowerupType.PURPLE_CRYSTAL:
			_call_player_method(player, ["activate_purple_overcharge", "activate_overcharge"], [7.0])
			var lvl: int = _get_player_stat(player, ["purple_level", "overcharge_level"], 1)
			if hud and hud.has_method("add_or_update_powerup"):
				hud.add_or_update_powerup("PURPLE", ICON_PATHS[PowerupType.PURPLE_CRYSTAL], 7.0, lvl)

		PowerupType.MAGNET:
			var p_node = player as Node2D
			for p in get_tree().get_nodes_in_group("powerup"):
				if p.has_method("trigger_magnet_pull"):
					p.trigger_magnet_pull(p_node)

		PowerupType.COIN:
			if GameManager:
				GameManager.add_coins(coin_value)
				
			if hud:
				if hud.has_method("add_coins_to_total"):
					hud.add_coins_to_total(coin_value)
				if hud.has_method("spawn_floating_text"):
					hud.spawn_floating_text(global_position, "+" + str(coin_value))

# --- HELPER FUNCTIONS FOR SAFE METHOD CALLING ---
func _call_player_method(player: Node, method_names: Array, args: Array) -> void:
	for m_name in method_names:
		if player.has_method(m_name):
			player.callv(m_name, args)
			return

func _get_player_stat(player: Node, var_names: Array, default_val: int) -> int:
	for v_name in var_names:
		if v_name in player:
			var val = player.get(v_name)
			if val != null and typeof(val) == TYPE_INT:
				return val
	return default_val
