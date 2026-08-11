extends Area2D

# Signal for Main Manager when boss dies
signal boss_defeated

# Boss Configuration
@export var max_health: float = 1200.0
var current_health: float

var screen_size: Vector2
var entry_target_y: float = 180.0 # Upper Screen Hold Height
var is_entering: bool = true

# Movement & Oscillating AI
@export var move_speed: float = 160.0
var move_direction: float = 1.0
var time_passed: float = 0.0

var center_burst_timer: float = 0.0
@export var center_burst_cooldown: float = 3.0 # Every 3 seconds

# Firing System
var fire_cooldown: float = 0.0
@export var base_fire_rate: float = 0.55 # Base Firing Interval
var current_fire_rate: float = 0.55

var enemy_laser_scene = preload("res://scenes/laser.tscn")
var explosion_scene = preload("res://scenes/explosion.tscn")
var powerup_scene = preload("res://scenes/powerup.tscn")
var thruster_scene = preload("res://scenes/thruster.tscn")
var spawned_thrusters: Array[Node2D] = []

@onready var boss_sprite: Sprite2D = $BossMega
@onready var normal_thruster_marker: Marker2D = find_child("NormalThruster", true, false)
@onready var mega_thruster_1: Marker2D = find_child("BossMegaThruster", true, false)
@onready var mega_thruster_2: Marker2D = find_child("BossMegaThruster2", true, false)

# --- DYNAMIC LEVEL & LASER VARIABLES ---
var boss_level: int = 1
var current_laser_path: String = "res://asstes/Lasers/Lasers_1.png"
var current_laser_damage: float = 10.0

var use_markers: bool = false

# Memory Optimizations
var cached_scene_root: Node = null

# Dynamic Store
var gun_markers: Array[Marker2D] = []
var target_player: Node2D = null
var player_last_pos: Vector2 = Vector2.ZERO
var player_velocity: Vector2 = Vector2.ZERO

# UI HealthBar
var hp_bar: ProgressBar
var attack_pattern_counter: int = 0

func _ready() -> void:
	name = "MegaBoss"
	screen_size = get_viewport_rect().size
	cached_scene_root = get_tree().current_scene
	
	if not is_in_group("enemies"):
		add_to_group("enemies")
	
	# Top Entry Start Position
	global_position = Vector2(screen_size.x / 2.0, -200.0)
	
	# --- AUTO-SYNC WITH GAMEMANAGER ---
	var lvl = GameManager.current_level if GameManager else 1
	if GameManager and "boss_ship_textures" in GameManager and GameManager.boss_ship_textures.size() > 0:
		var texture_index = clamp(lvl - 1, 0, GameManager.boss_ship_textures.size() - 1)
		var chosen_path = GameManager.boss_ship_textures[texture_index]
		setup_boss_texture(chosen_path, lvl)
	else:
		setup_boss_texture("res://asstes/Enemies/Enemy_11.png", lvl)
	
	collect_all_markers(self)
	setup_boss_health_bar()
	_cache_player_reference()
	
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func collect_all_markers(parent_node: Node) -> void:
	for child in parent_node.get_children():
		if child is Marker2D:
			gun_markers.append(child)
		elif child.get_child_count() > 0:
			collect_all_markers(child)

func _cache_player_reference() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		target_player = players[0]
		player_last_pos = target_player.global_position

func setup_boss_health_bar() -> void:
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.queue_free()

	hp_bar = ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	hp_bar.show_percentage = false
	
	var sb_fill = StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.95, 0.05, 0.05) # Enraged Red
	sb_fill.corner_radius_top_left = 4
	sb_fill.corner_radius_top_right = 4
	sb_fill.corner_radius_bottom_left = 4
	sb_fill.corner_radius_bottom_right = 4
	
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	
	hp_bar.add_theme_stylebox_override("fill", sb_fill)
	hp_bar.add_theme_stylebox_override("background", sb_bg)
	
	hp_bar.custom_minimum_size = Vector2(280, 18)
	hp_bar.position = Vector2(-140, -180)
	hp_bar.rotation_degrees = 0.0
		
	add_child(hp_bar)

func _process(delta: float) -> void:
	var time_mult = 1.0
	if GameManager and GameManager.has_method("get_effective_enemy_speed_multiplier"):
		time_mult = GameManager.get_effective_enemy_speed_multiplier()
	else:
		time_mult = GameManager.enemy_speed_multiplier if GameManager else 1.0

	var effective_delta = delta * time_mult

	time_passed += effective_delta
	_update_player_tracker(effective_delta)

	if is_entering:
		global_position.y = lerp(global_position.y, entry_target_y, effective_delta * 2.0)
		if abs(global_position.y - entry_target_y) < 2.0:
			global_position.y = entry_target_y
			is_entering = false
	else:
		_process_boss_movement(effective_delta)

	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.value = current_health

	if not is_entering:
		# --- Regular Attack Cooldown ---
		fire_cooldown -= effective_delta
		if fire_cooldown <= 0.0:
			execute_boss_attack_routine()
			fire_cooldown = current_fire_rate

		# --- Center 3-Second Spread Burst Timer ---
		center_burst_timer += effective_delta
		if center_burst_timer >= center_burst_cooldown:
			center_burst_timer = 0.0
			spawn_center_spread_burst()

func _update_player_tracker(delta: float) -> void:
	if not is_instance_valid(target_player):
		_cache_player_reference()
		return

	if delta > 0.0:
		player_velocity = (target_player.global_position - player_last_pos) / delta
		player_last_pos = target_player.global_position

func _process_boss_movement(delta: float) -> void:
	# Enraged Speed Multiplier when health is under 40%
	var speed_multiplier = 1.6 if (current_health <= max_health * 0.4) else 1.0
	var organic_sine = sin(time_passed * 1.8) * 40.0
	
	global_position.x += move_direction * move_speed * speed_multiplier * delta
	global_position.y = entry_target_y + organic_sine

	# SAFE BOUNDS CLAMP
	var half_width = 160.0
	if global_position.x >= screen_size.x - half_width:
		global_position.x = screen_size.x - half_width
		move_direction = -1.0
	elif global_position.x <= half_width:
		global_position.x = half_width
		move_direction = 1.0

# BULLET-HELL ATTACK ROUTINE
func execute_boss_attack_routine() -> void:
	attack_pattern_counter += 1
	var is_enraged = (current_health <= max_health * 0.4)
	current_fire_rate = base_fire_rate * 0.55 if is_enraged else base_fire_rate

	if is_enraged and (attack_pattern_counter % 2 == 0):
		spawn_radial_bullet_hell(12)
	else:
		if attack_pattern_counter % 3 == 0:
			spawn_fan_spread_lasers()
		else:
			spawn_predictive_aim_lasers()

func spawn_predictive_aim_lasers() -> void:
	var predicted_pos = global_position + Vector2(0, 300)
	if is_instance_valid(target_player):
		predicted_pos = target_player.global_position + (player_velocity * 0.28)

	if use_markers and not gun_markers.is_empty():
		for marker in gun_markers:
			if is_instance_valid(marker):
				spawn_single_aimed_laser(marker.global_position, predicted_pos)
	else:
		spawn_single_aimed_laser(global_position + Vector2(-40, 60), predicted_pos)
		spawn_single_aimed_laser(global_position + Vector2(40, 60), predicted_pos)

func spawn_fan_spread_lasers() -> void:
	var base_origin = global_position + Vector2(0, 120)
	var angles = [-35.0, -18.0, 0.0, 18.0, 35.0]
	for deg in angles:
		var dir = Vector2.DOWN.rotated(deg_to_rad(deg))
		spawn_directional_laser(base_origin, dir)

func spawn_radial_bullet_hell(bullet_count: int) -> void:
	var origin = global_position + Vector2(0, 110)
	for i in range(bullet_count):
		var angle = (i * (360.0 / bullet_count))
		var dir = Vector2.DOWN.rotated(deg_to_rad(angle))
		spawn_directional_laser(origin, dir)

func _add_laser_to_scene(laser: Node) -> void:
	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(laser)
	else:
		get_tree().current_scene.add_child(laser)

func _configure_enemy_laser(laser: Node) -> void:
	if "is_enemy_laser" in laser:
		laser.is_enemy_laser = true
	laser.add_to_group("enemy_laser")
	if laser.is_in_group("player_laser"):
		laser.remove_from_group("player_laser")
	if "damage" in laser:
		laser.damage = current_laser_damage
	if laser.has_method("set_damage"):
		laser.set_damage(current_laser_damage)

func spawn_single_aimed_laser(spawn_pos: Vector2, target_pos: Vector2) -> void:
	var safe_offset = Vector2(0, 45)
	var final_pos = spawn_pos + safe_offset
	
	var laser = enemy_laser_scene.instantiate()
	_add_laser_to_scene(laser)
	laser.global_position = final_pos
	
	_configure_enemy_laser(laser)
		
	if laser.has_method("setup_laser_custom"):
		laser.setup_laser_custom(current_laser_path, 650.0, current_laser_damage, true)
	elif laser.has_method("setup_custom_laser"):
		laser.setup_custom_laser(current_laser_path)

	if laser.has_method("set_aim_target"):
		laser.set_aim_target(target_pos)

func spawn_directional_laser(spawn_pos: Vector2, direction_vec: Vector2) -> void:
	var laser = enemy_laser_scene.instantiate()
	_add_laser_to_scene(laser)
	laser.global_position = spawn_pos

	_configure_enemy_laser(laser)

	if laser.has_method("setup_laser_custom"):
		laser.setup_laser_custom(current_laser_path, 650.0, current_laser_damage, false)
	elif laser.has_method("setup_custom_laser"):
		laser.setup_custom_laser(current_laser_path)
		
	if "move_direction" in laser:
		laser.move_direction = direction_vec.normalized()

func spawn_center_spread_burst() -> void:
	if not enemy_laser_scene:
		return
		
	var center_origin = global_position + Vector2(0, 90)
	var total_bullets = 16
	
	for i in range(total_bullets):
		var angle_deg = i * (360.0 / total_bullets)
		
		var laser = enemy_laser_scene.instantiate()
		_add_laser_to_scene(laser)
		laser.global_position = center_origin
		
		_configure_enemy_laser(laser)
			
		var final_dir = Vector2.DOWN.rotated(deg_to_rad(angle_deg))
		
		if laser.has_method("setup_directional_custom_laser"):
			laser.setup_directional_custom_laser(current_laser_path, 500.0, current_laser_damage, final_dir)
		elif laser.has_method("setup_laser_custom"):
			laser.setup_laser_custom(current_laser_path, 500.0, current_laser_damage, false)
			if "move_direction" in laser:
				laser.move_direction = final_dir

func trigger_mega_boss_star_spread() -> void:
	spawn_center_spread_burst()

func take_damage(amount: float) -> void:
	current_health -= amount
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.value = current_health
		
	if current_health <= 0.0:
		spawn_explosion()
		spawn_massive_loot_shower()
		boss_defeated.emit()
		queue_free()

func spawn_explosion() -> void:
	if not explosion_scene:
		return
		
	var exp_node = explosion_scene.instantiate() as Node2D
	exp_node.global_position = global_position
	exp_node.scale = Vector2(3.5, 3.5)
	exp_node.z_index = 10
	
	if exp_node.has_node("Sprite2D"):
		var exp_sprite = exp_node.get_node("Sprite2D") as Sprite2D
		if exp_sprite:
			exp_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	_add_laser_to_scene(exp_node)

func spawn_massive_loot_shower() -> void:
	if not powerup_scene:
		return

	var total_drop_count = randi_range(16, 22)
	
	for i in range(total_drop_count):
		var p_item = powerup_scene.instantiate() as Area2D
		var angle = randf() * TAU
		var radius = randf_range(30.0, 180.0)
		var random_spread = Vector2(cos(angle), sin(angle)) * radius
		
		p_item.global_position = global_position + random_spread
		var chosen_type: int = 8 if (randf() * 100.0 <= 65.0) else (randi() % 8)
			
		if is_instance_valid(cached_scene_root):
			cached_scene_root.call_deferred("add_child", p_item)
		else:
			get_tree().current_scene.call_deferred("add_child", p_item)

		if p_item.has_method("setup_type"):
			p_item.call_deferred("setup_type", chosen_type)

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemies") or area.is_in_group("enemy_laser") or area.is_in_group("enemy_lasers") or area.name.contains("Enemy"):
		return
		
	# Player Laser Hit (Calculates dynamic projectile damage)
	if area.is_in_group("player_laser") or area.is_in_group("player_lasers") or area.name.contains("Laser"):
		var incoming_dmg: float = 20.0
		if area.has_method("get_damage"):
			incoming_dmg = area.get_damage()
		elif "damage" in area:
			incoming_dmg = area.damage
		elif "laser_damage" in area:
			incoming_dmg = area.laser_damage
			
		take_damage(incoming_dmg)
		area.queue_free()
			
	# Direct Collision with Player
	elif area.name == "Player" or area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(50.0)
		elif area.has_method("apply_damage"):
			area.apply_damage(50.0)

func setup_boss_texture(texture_path: String, lvl: int) -> void:
	boss_level = lvl
	
	# Level-wise Laser & Damage Setup
	var laser_index = clamp(lvl, 1, 11)
	current_laser_path = "res://asstes/Lasers/Lasers_" + str(laser_index) + ".png"
	current_laser_damage = 8.0 + (laser_index * 3.5)
	
	if boss_sprite and ResourceLoader.exists(texture_path):
		boss_sprite.texture = load(texture_path)
	
	if boss_sprite and boss_sprite.texture:
		var tex_size = boss_sprite.texture.get_size()
		var target_width = 130.0
		var auto_scale = target_width / tex_size.x
		
		var is_mega = ("boss_mega" in texture_path.to_lower() or lvl >= 11)
		var hp_mult = GameManager.boss_hp_multiplier if GameManager else 1.0

		if is_mega:
			scale = Vector2(auto_scale * 1.2, auto_scale * 1.2)
			use_markers = true
			max_health = 1500.0 * hp_mult
		else:
			scale = Vector2(auto_scale * 1.4, auto_scale * 1.4)
			use_markers = false
			max_health = (400.0 + (lvl * 100.0)) * hp_mult
			
		setup_boss_thrusters_from_markers(is_mega)
			
	current_health = max_health
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.max_value = max_health
		hp_bar.value = current_health

func setup_boss_thrusters_from_markers(is_mega: bool) -> void:
	for t in spawned_thrusters:
		if is_instance_valid(t):
			t.queue_free()
	spawned_thrusters.clear()
	
	if is_mega:
		var mega_markers = [normal_thruster_marker, mega_thruster_1, mega_thruster_2]
		for marker in mega_markers:
			if marker:
				spawn_thruster_at_marker(marker, Vector2(0.45, 0.45))
	else:
		if normal_thruster_marker:
			spawn_thruster_at_marker(normal_thruster_marker, Vector2(0.4, 0.4))

func spawn_thruster_at_marker(marker_node: Marker2D, thruster_scale: Vector2) -> void:
	if not thruster_scene or not marker_node:
		return
		
	var thruster = thruster_scene.instantiate()
	add_child(thruster)
	
	thruster.global_position = marker_node.global_position
	thruster.scale = thruster_scale
	thruster.show_behind_parent = true
	
	if thruster is AnimatedSprite2D:
		thruster.play()
	elif thruster.has_node("AnimatedSprite2D"):
		var anim = thruster.get_node("AnimatedSprite2D") as AnimatedSprite2D
		if anim:
			anim.play()
			
	spawned_thrusters.append(thruster)
