extends Area2D

# ==========================================
# ⚙️ SIGNALS & EXPORTS
# ==========================================
signal player_died

@export var base_speed: float = 500.0
@export var base_max_health: float = 100.0

# ==========================================
# 📦 SCENE PRELOADS
# ==========================================
var laser_scene: PackedScene = preload("res://scenes/laser.tscn")
var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")
var thruster_scene: PackedScene = preload("res://scenes/thruster.tscn")

# ==========================================
# 🎮 ONREADY NODES
# ==========================================
@onready var sprite: Sprite2D = $AlphaPrime
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ==========================================
# 📊 GAME STATE VARIABLES
# ==========================================
var current_speed: float = 500.0
var max_health: float = 100.0
var current_health: float = 100.0
var laser_damage_multiplier: float = 1.0
var screen_size: Vector2

# Drag Controls
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Shooting System
var base_fire_rate: float = 0.18
var fire_rate: float = 0.18
var time_since_last_shot: float = 0.0

# Powerup States, Timers & Multiplier Levels
var is_shielded: bool = false
var shield_timer: float = 0.0
var shield_level: int = 1

var is_triple_shot: bool = false
var triple_shot_timer: float = 0.0
var triple_shot_level: int = 1

var is_rapid_fire: bool = false
var rapid_fire_timer: float = 0.0
var rapid_fire_level: int = 1

var is_purple_sequence: bool = false
var purple_timer: float = 0.0
var purple_level: int = 1

var is_slow_motion: bool = false
var slow_motion_timer: float = 0.0
var slow_motion_level: int = 1

var is_magnet_active: bool = false
var magnet_timer: float = 0.0
var magnet_level: int = 1

var is_invulnerable: bool = false
var active_lasers: Array[String] = []

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	name = "Player"
	screen_size = get_viewport_rect().size

	if not is_in_group("player"):
		add_to_group("player")

	apply_shop_upgrades()

	if GameManager and GameManager.has_signal("powerup_level_updated"):
		GameManager.powerup_level_updated.connect(_on_powerup_level_updated)

	setup_thrusters()
	update_ui_health()

	if sprite and sprite.texture:
		update_player_collision(sprite.texture)

	# Ensure signal connections for collisions
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func apply_shop_upgrades() -> void:
	if not GameManager:
		current_speed = base_speed
		max_health = base_max_health
		current_health = max_health
		laser_damage_multiplier = 1.0
		return

	var speed_lvl: int = 1
	if "level_speed_upgrade" in GameManager:
		speed_lvl = GameManager.level_speed_upgrade
	elif "speed_level" in GameManager:
		speed_lvl = GameManager.speed_level
	current_speed = base_speed + ((speed_lvl - 1) * 55.0)

	var hp_lvl: int = 1
	if "max_hp_level" in GameManager:
		hp_lvl = GameManager.max_hp_level
	max_health = base_max_health + ((hp_lvl - 1) * 25.0)
	current_health = max_health

	var dmg_lvl: int = 1
	if "laser_damage_level" in GameManager:
		dmg_lvl = GameManager.laser_damage_level
	elif "level_laser_damage" in GameManager:
		dmg_lvl = GameManager.level_laser_damage
	laser_damage_multiplier = 1.0 + ((dmg_lvl - 1) * 0.5)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	handle_movement(delta)
	handle_shooting(delta)
	handle_powerup_timers(delta)

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	handle_drag_input(event)

# ==========================================
# ⏳ POWERUP TIMERS MANAGEMENT
# ==========================================
func handle_powerup_timers(delta: float) -> void:
	if is_shielded:
		shield_timer -= delta
		if shield_timer <= 0.0:
			stop_shield()

	if is_triple_shot:
		triple_shot_timer -= delta
		if triple_shot_timer <= 0.0:
			stop_triple_shot()

	if is_rapid_fire:
		rapid_fire_timer -= delta
		if rapid_fire_timer <= 0.0:
			stop_rapid_fire()

	if is_purple_sequence:
		purple_timer -= delta
		if purple_timer <= 0.0:
			stop_purple_overcharge()

	if is_slow_motion:
		slow_motion_timer -= delta
		if slow_motion_timer <= 0.0:
			stop_slow_motion()

	if is_magnet_active:
		magnet_timer -= delta
		if magnet_timer <= 0.0:
			stop_magnet()

func recalculate_fire_rate() -> void:
	if is_purple_sequence:
		fire_rate = max(0.02, 0.10 - (purple_level * 0.015))
	elif is_rapid_fire:
		fire_rate = max(0.03, 0.12 - (rapid_fire_level * 0.025))
	else:
		fire_rate = base_fire_rate

# ==========================================
# 🕹️ MOVEMENT & DRAG CONTROLS
# ==========================================
func handle_movement(delta: float) -> void:
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		global_position += input_dir * current_speed * delta

	global_position.x = clamp(global_position.x, 40.0, screen_size.x - 40.0)
	global_position.y = clamp(global_position.y, 40.0, screen_size.y - 40.0)

func handle_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.is_pressed():
			var click_pos = to_local(event.position)
			if sprite and sprite.get_rect().has_point(click_pos):
				is_dragging = true
				drag_offset = global_position - event.position
		else:
			is_dragging = false

	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if is_dragging:
			global_position = event.position + drag_offset

# ==========================================
# 🔫 SHOOTING SYSTEM
# ==========================================
func handle_shooting(delta: float) -> void:
	time_since_last_shot += delta
	if time_since_last_shot >= fire_rate:
		shoot_laser()
		time_since_last_shot = 0.0

func shoot_laser() -> void:
	if not laser_scene:
		return

	var spawn_y: float = -35.0
	if sprite and sprite.texture:
		spawn_y = -(sprite.texture.get_size().y * sprite.scale.y * 0.5) - 5.0

	# Purple Crystal Shooting
	if is_purple_sequence and purple_timer > 0.0:
		spawn_single_laser(Vector2(0.0, spawn_y), 0.0, active_lasers[0] if active_lasers.size() > 0 else "")
		var max_pairs = min(purple_level * 2, 8)
		for i in range(1, max_pairs + 1):
			var x_offset = i * 12.0
			var angle = i * 8.0
			var tex_path = active_lasers[i % active_lasers.size()] if active_lasers.size() > 0 else ""
			spawn_single_laser(Vector2(-x_offset, spawn_y + (i * 2.0)), -angle, tex_path)
			spawn_single_laser(Vector2(x_offset, spawn_y + (i * 2.0)), angle, tex_path)

	# Triple Shot
	elif is_triple_shot and triple_shot_timer > 0.0:
		spawn_single_laser(Vector2(0.0, spawn_y), 0.0, "")
		var max_pairs = min(triple_shot_level, 5)
		for i in range(1, max_pairs + 1):
			var x_offset = i * 16.0
			var angle = i * 12.0
			spawn_single_laser(Vector2(-x_offset, spawn_y + (i * 2.0)), -angle, "")
			spawn_single_laser(Vector2(x_offset, spawn_y + (i * 2.0)), angle, "")

	# Default Single Shot
	else:
		spawn_single_laser(Vector2(0.0, spawn_y), 0.0, "")

func spawn_single_laser(offset: Vector2, angle_deg: float, custom_tex_path: String) -> void:
	if has_node("Shoot"):
		$Shoot.play()
	var laser = laser_scene.instantiate() as Area2D
	laser.global_position = global_position + offset
	laser.rotation_degrees = angle_deg
	
	var base_dmg = 1.0 * laser_damage_multiplier

	if GameManager and custom_tex_path == "" and "selected_laser_texture" in GameManager and GameManager.selected_laser_texture != "":
		custom_tex_path = GameManager.selected_laser_texture

	if laser.has_method("set_damage"):
		laser.set_damage(base_dmg)
	elif "damage" in laser:
		laser.damage = base_dmg

	get_parent().add_child(laser)

	if laser.has_method("setup_laser"):
		laser.setup_laser("PLAYER")

	if custom_tex_path != "" and laser.has_method("setup_custom_laser"):
		laser.setup_custom_laser(custom_tex_path)

# ==========================================
# 💥 HEALTH & COLLISION SYSTEM
# ==========================================
func take_damage(amount: float) -> void:
	if is_shielded or is_invulnerable:
		return

	current_health = clamp(current_health - amount, 0.0, max_health)
	update_ui_health()

	is_invulnerable = true
	get_tree().create_timer(0.2).timeout.connect(func(): is_invulnerable = false)

	if is_instance_valid(sprite):
		sprite.modulate = Color(1.0, 0.3, 0.3)
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_instance_valid(sprite):
				sprite.modulate = Color(0.3, 0.7, 1.0) if is_shielded else Color(1.0, 1.0, 1.0)
		)

	if current_health <= 0.0:
		destroy_player()

func _on_area_entered(area: Area2D) -> void:
	# Ignore powerups and player's own lasers
	if area.is_in_group("powerup") or area.name.contains("Powerup") or area.is_in_group("player_laser"):
		return

	# Handle Enemy Laser Hits
	if area.is_in_group("enemy_laser") or area.name.contains("EnemyLaser") or area.name.contains("Laser"):
		area.queue_free()
		take_damage(15.0)
		return

	# Handle Zigzag Enemy Collision (Instant Mutual Destruction)
	if area.is_in_group("zigzag") or area.name.to_lower().contains("zigzag"):
		if area.has_method("destroy"):
			area.destroy()
		else:
			area.queue_free()

		if not is_shielded:
			destroy_player()
		return

	# Handle General Enemies, Bosses & Asteroids Collision
	if area.is_in_group("enemies") or area.name.contains("Enemy") or area.name.contains("Asteroid") or area.name.contains("Boss"):
		if area.has_method("take_damage"):
			area.take_damage(50.0)
		elif area.has_method("destroy"):
			area.destroy()

		if not is_shielded:
			destroy_player()

func heal(amount: float) -> void:
	current_health = clamp(current_health + amount, 0.0, max_health)
	update_ui_health()

func upgrade_max_health(extra_amount: float) -> void:
	max_health += extra_amount
	current_health = max_health
	update_ui_health()

func destroy_player() -> void:
	if is_shielded:
		return

	Engine.time_scale = 1.0

	if explosion_scene:
		var exp_instance = explosion_scene.instantiate() as Node2D
		exp_instance.global_position = global_position
		get_parent().add_child(exp_instance)

	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if hud.has_method("clear_powerup_bars"):
			hud.clear_powerup_bars()
		if hud.has_method("reset_hud"):
			hud.reset_hud()
		if hud.has_method("update_health"):
			hud.update_health(0.0, max_health)

	player_died.emit()
	queue_free()

# ==========================================
# 🌟 POWERUPS & HUD INTEGRATION
# ==========================================
func setup_thrusters() -> void:
	if not thruster_scene:
		return

	for child in get_children():
		if child is Marker2D and child.name.contains("Thruster"):
			var thruster_instance = thruster_scene.instantiate()
			child.add_child(thruster_instance)
			thruster_instance.position = Vector2.ZERO
			thruster_instance.z_index = 1

			var anim = thruster_instance.get_node_or_null("AnimatedSprite2D")
			if anim:
				anim.play("Thruster")
			elif thruster_instance is AnimatedSprite2D:
				thruster_instance.play("Thruster")

func update_ui_health() -> void:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("update_health"):
		hud.update_health(current_health, max_health)

func show_powerup_progress_bar(powerup_id: String, icon_path: String, duration: float, level: int = 1) -> void:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if hud.has_method("add_or_update_powerup"):
			hud.add_or_update_powerup(powerup_id, icon_path, duration, level)
		
		var p_node = hud.find_child(powerup_id, true, false)
		if p_node:
			_update_level_labels_in_node(p_node, level)

func _update_level_labels_in_node(node: Node, level: int) -> void:
	for child in node.get_children():
		if child is Label:
			child.text = "1x" + str(level)
			child.visible = true
		_update_level_labels_in_node(child, level)

func remove_powerup_progress_bar(powerup_id: String) -> void:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if hud.has_method("remove_powerup_bar"):
			hud.remove_powerup_bar(powerup_id)
		elif hud.has_method("remove_powerup"):
			hud.remove_powerup(powerup_id)

func _on_powerup_level_updated(powerup_name: String, level: int) -> void:
	print("Player received level update for: ", powerup_name, " -> Level: ", level)

# ----------------------------
# POWERUP ACTIVATORS & STACKERS
# ----------------------------

func activate_purple_overcharge(duration: float = 6.0) -> void:
	stop_triple_shot()

	if is_purple_sequence:
		purple_level = min(purple_level + 1, 5)
	else:
		is_purple_sequence = true
		purple_level = 1

	purple_timer = duration
	recalculate_fire_rate()

	active_lasers.clear()
	for i in range(purple_level + 2):
		active_lasers.append("res://asstes/Lasers/Lasers_" + str((randi() % 11) + 1) + ".png")

	show_powerup_progress_bar("Purple Crystal", "res://asstes/Icons/Purple_Crystal.png", duration, purple_level)

func stop_purple_overcharge() -> void:
	is_purple_sequence = false
	purple_timer = 0.0
	purple_level = 1
	active_lasers.clear()
	recalculate_fire_rate()
	remove_powerup_progress_bar("Purple Crystal")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("PURPLE")

func activate_triple_shot(duration: float = 6.0) -> void:
	stop_purple_overcharge()

	if is_triple_shot:
		triple_shot_level = min(triple_shot_level + 1, 5)
	else:
		is_triple_shot = true
		triple_shot_level = 1

	triple_shot_timer = duration
	recalculate_fire_rate()

	show_powerup_progress_bar("Triple Shot", "res://asstes/Icons/Star.png", duration, triple_shot_level)

func stop_triple_shot() -> void:
	is_triple_shot = false
	triple_shot_timer = 0.0
	triple_shot_level = 1
	recalculate_fire_rate()
	remove_powerup_progress_bar("Triple Shot")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("Triple Shot")

func activate_shield(duration: float = 6.0) -> void:
	if is_shielded:
		shield_level = min(shield_level + 1, 5)
	else:
		is_shielded = true
		shield_level = 1

	shield_timer = duration
	heal(15.0 * shield_level)
	show_powerup_progress_bar("Shield", "res://asstes/Icons/Shield.png", duration, shield_level)

	if is_instance_valid(sprite):
		sprite.modulate = Color(0.3, 0.7, 1.0)

func stop_shield() -> void:
	is_shielded = false
	shield_timer = 0.0
	shield_level = 1
	if is_instance_valid(sprite):
		sprite.modulate = Color(1.0, 1.0, 1.0)
	remove_powerup_progress_bar("Shield")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("Shield")

func boost_fire_rate(duration: float = 5.0) -> void:
	if is_rapid_fire:
		rapid_fire_level = min(rapid_fire_level + 1, 5)
	else:
		is_rapid_fire = true
		rapid_fire_level = 1

	rapid_fire_timer = duration
	recalculate_fire_rate()
	show_powerup_progress_bar("Rapid Fire", "res://asstes/Icons/Energy.png", duration, rapid_fire_level)

func stop_rapid_fire() -> void:
	is_rapid_fire = false
	rapid_fire_timer = 0.0
	rapid_fire_level = 1
	recalculate_fire_rate()
	remove_powerup_progress_bar("Rapid Fire")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("Rapid Fire")

func activate_slow_motion(duration: float = 6.0) -> void:
	if is_slow_motion:
		slow_motion_level = min(slow_motion_level + 1, 5)
	else:
		is_slow_motion = true
		slow_motion_level = 1

	slow_motion_timer = duration
	Engine.time_scale = max(0.2, 0.5 - (slow_motion_level * 0.05))
	show_powerup_progress_bar("Slow Motion", "res://asstes/Icons/Clock.png", duration, slow_motion_level)

func stop_slow_motion() -> void:
	is_slow_motion = false
	slow_motion_timer = 0.0
	slow_motion_level = 1
	Engine.time_scale = 1.0
	remove_powerup_progress_bar("Slow Motion")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("SLOW_MOTION")

func activate_magnet(duration: float = 8.0) -> void:
	if is_magnet_active:
		magnet_level = min(magnet_level + 1, 5)
	else:
		is_magnet_active = true
		magnet_level = 1

	magnet_timer = duration
	show_powerup_progress_bar("Magnet", "res://asstes/Icons/Magnet.png", duration, magnet_level)

	var coins = get_tree().get_nodes_in_group("coins")
	for coin in coins:
		if coin.has_method("enable_magnet"):
			coin.enable_magnet(self, duration)

func stop_magnet() -> void:
	is_magnet_active = false
	magnet_timer = 0.0
	magnet_level = 1
	remove_powerup_progress_bar("Magnet")
	if GameManager and GameManager.has_method("reset_powerup_level"):
		GameManager.reset_powerup_level("MAGNET")

func update_player_collision(texture: Texture2D) -> void:
	if not collision_shape or not collision_shape.shape:
		return

	var img_size = texture.get_size()
	if collision_shape.shape is CapsuleShape2D:
		collision_shape.shape.radius = (img_size.x / 2.0) * 0.75
		collision_shape.shape.height = img_size.y * 0.85
	elif collision_shape.shape is RectangleShape2D:
		collision_shape.shape.size = img_size * 0.8
