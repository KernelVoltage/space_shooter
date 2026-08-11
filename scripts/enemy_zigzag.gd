extends Area2D

# ==========================================
# ⚙️ EXPORT VARIABLES
# ==========================================
@export var lerp_speed: float = 6.5
@export var dive_speed: float = 680.0
@export var base_speed: float = 240.0

# ==========================================
# 🐝 ENUM & SWARM ROLES
# ==========================================
enum EnemyRole { SWARM_SURROUND, STRIKER_DIVER, FLANKER }
var my_role: EnemyRole = EnemyRole.SWARM_SURROUND

var target_player: Node2D = null
var player_last_pos: Vector2 = Vector2.ZERO
var player_velocity: Vector2 = Vector2.ZERO
var screen_size: Vector2

var slot_offset: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var is_diving: bool = false
var dive_timer: float = 0.0

# ==========================================
# 📊 STATS & DYNAMIC SCALING
# ==========================================
var health: int = 6
var max_health: int = 6
var is_destroyed: bool = false
var ship_level: int = 1

# ==========================================
# 🔫 LASER & DAMAGE SYSTEM
# ==========================================
var fire_timer: float = 0.0
var fire_rate: float = 0.32
var current_laser_texture: String = "res://asstes/Lasers/Lasers_1.png"
var current_laser_damage: float = 15.0

# Performance & RAM Optimization
var cached_scene_root: Node = null
var viewport_height: float = 1280.0

# Preloaded Resources
var enemy_laser_scene: PackedScene = preload("res://scenes/laser.tscn")
var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")
var powerup_scene: PackedScene = preload("res://scenes/powerup.tscn")
var thruster_scene: PackedScene = preload("res://scenes/thruster.tscn")

# Separation & Tracking Timers
var separation_vector: Vector2 = Vector2.ZERO
var separation_timer: float = 0.0
var player_search_timer: float = 0.0

@onready var sprite: Sprite2D = $InterceptorGold
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	name = "EnemyZigZag"
	if not is_in_group("enemies"):
		add_to_group("enemies")

	screen_size = get_viewport_rect().size
	viewport_height = screen_size.y
	cached_scene_root = get_tree().current_scene
	
	fire_timer = randf_range(0.05, 0.2)
	_assign_dynamic_swarm_slot()

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	_cache_player_reference()
	call_deferred("setup_thrusters")

func _process(delta: float) -> void:
	if is_destroyed: return

	# --- 🧹 OFF-SCREEN CLEANUP ---
	if global_position.y > viewport_height + 150.0:
		if not is_destroyed and GameManager and GameManager.has_method("enemy_missed"):
			GameManager.enemy_missed()
		queue_free()
		return
	elif global_position.y < -250.0:
		queue_free()
		return

	# --- 🟢 SPEED MULTIPLIER & SLOW-MOTION INTEGRATION ---
	var time_mult = 1.0
	if GameManager and GameManager.has_method("get_effective_enemy_speed_multiplier"):
		time_mult = GameManager.get_effective_enemy_speed_multiplier()
	elif GameManager and "enemy_speed_multiplier" in GameManager:
		time_mult = GameManager.enemy_speed_multiplier

	var effective_delta = delta * time_mult

	# CPU Separation Optimization
	separation_timer -= effective_delta
	if separation_timer <= 0.0:
		_update_separation_force()
		separation_timer = 0.15

	_update_player_tracker(effective_delta)

	# --- 🛑 ABSENT / DEAD PLAYER MANEUVER ---
	if not is_instance_valid(target_player):
		global_position.y += base_speed * 1.8 * effective_delta
		return

	_update_organic_swarm_movement(effective_delta)
	_update_firing_system(effective_delta)

# ==========================================
# 🚀 THRUSTERS & VISUAL SETUP
# ==========================================
func setup_thrusters() -> void:
	if not thruster_scene: return
	var thruster_marker = get_node_or_null("ThrusterMarker")
	if not thruster_marker:
		for child in get_children():
			if child is Marker2D and child.name.to_lower().contains("thruster"):
				thruster_marker = child
				break
	if not thruster_marker: return

	for child in thruster_marker.get_children():
		child.queue_free()

	var thruster_instance = thruster_scene.instantiate()
	thruster_marker.add_child(thruster_instance)
	thruster_instance.position = Vector2.ZERO
	thruster_instance.rotation_degrees = 180.0
	thruster_instance.z_index = 1

	if thruster_instance is AnimatedSprite2D:
		thruster_instance.autoplay = "Thruster"
		thruster_instance.play("Thruster")
		thruster_instance.visible = true

func _cache_player_reference() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		target_player = players[0]
		player_last_pos = target_player.global_position
	else:
		target_player = null

# ==========================================
# 🐝 SWARM & AI ROLE LOGIC
# ==========================================
func _assign_dynamic_swarm_slot() -> void:
	var my_id = get_instance_id()
	var angle_step = (my_id % 16) * (PI / 8.0)
	var radius_x = randf_range(120.0, 240.0)
	var radius_y = randf_range(90.0, 180.0)

	slot_offset = Vector2(cos(angle_step) * radius_x, -abs(sin(angle_step) * radius_y) - 60.0)

	if (my_id % 3) == 0:
		my_role = EnemyRole.STRIKER_DIVER
	elif (my_id % 2) == 0:
		my_role = EnemyRole.FLANKER
	else:
		my_role = EnemyRole.SWARM_SURROUND

func _update_player_tracker(delta: float) -> void:
	if not is_instance_valid(target_player):
		player_search_timer -= delta
		if player_search_timer <= 0.0:
			_cache_player_reference()
			player_search_timer = 0.8
		return

	if delta > 0.0:
		player_velocity = (target_player.global_position - player_last_pos) / delta
		player_last_pos = target_player.global_position

func _update_organic_swarm_movement(delta: float) -> void:
	var player_pos = target_player.global_position

	# Continuous movement downwards if enemy is lower than player
	if global_position.y > player_pos.y + 20.0:
		global_position.y += base_speed * 1.8 * delta
		return

	var diff_mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
	var is_player_stopped = player_velocity.length_squared() < 100.0
	var continuous_downward_flow = (base_speed * (0.85 if is_player_stopped else 0.5)) * diff_mult * delta

	# Smart Dive & Flank Maneuvers
	if is_player_stopped or is_diving:
		var strike_target = Vector2(player_pos.x + sin(Time.get_ticks_msec() * 0.006) * 70.0, player_pos.y + 100.0)
		global_position = global_position.move_toward(strike_target + separation_vector, dive_speed * diff_mult * delta)
	else:
		dive_timer += delta
		if dive_timer > 1.2 and my_role == EnemyRole.STRIKER_DIVER:
			is_diving = true

		if my_role == EnemyRole.FLANKER:
			var side = 1.0 if (get_instance_id() % 2 == 0) else -1.0
			var wave_y = cos(Time.get_ticks_msec() * 0.003 + get_instance_id()) * 50.0
			target_position = Vector2((screen_size.x * 0.5) + (side * 220.0), player_pos.y - 140.0 + wave_y)
			global_position = global_position.lerp(target_position + separation_vector, lerp_speed * delta)
			global_position.y += continuous_downward_flow
		else:
			var wave_x = sin(Time.get_ticks_msec() * 0.005 + get_instance_id()) * 110.0
			target_position = Vector2(player_pos.x + slot_offset.x + wave_x, player_pos.y + slot_offset.y)
			global_position = global_position.lerp(target_position + separation_vector, lerp_speed * delta)
			global_position.y += continuous_downward_flow

	global_position.x = clamp(global_position.x, 30.0, screen_size.x - 30.0)

func _update_separation_force() -> void:
	var push = Vector2.ZERO
	var neighbors = get_tree().get_nodes_in_group("enemies")
	var my_pos = global_position

	for enemy in neighbors:
		if enemy != self and is_instance_valid(enemy):
			var diff = my_pos - enemy.global_position
			var dist_sq = diff.length_squared()
			if dist_sq < 6400.0 and dist_sq > 0.0:
				var dist = sqrt(dist_sq)
				push += (diff / dist) * (80.0 - dist)

	separation_vector = push

# ==========================================
# 🔫 FIRING SYSTEM WITH ANGLED SPREADS
# ==========================================
func _update_firing_system(delta: float) -> void:
	if global_position.y < 0.0: return
	if is_instance_valid(target_player) and global_position.y > target_player.global_position.y: return

	fire_timer -= delta
	if fire_timer <= 0.0:
		execute_firing_pattern()
		var mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
		fire_timer = max(0.15, fire_rate - (mult * 0.02))

func execute_firing_pattern() -> void:
	if not enemy_laser_scene or is_destroyed or global_position.y < 0.0: return

	var nose_y = get_nose_offset()

	if ship_level <= 2:
		spawn_single_laser(Vector2(0, nose_y), 0.0)
	elif ship_level <= 5:
		spawn_single_laser(Vector2(-12, nose_y), -5.0)
		spawn_single_laser(Vector2(12, nose_y), 5.0)
	elif ship_level <= 8:
		spawn_single_laser(Vector2(0, nose_y), 0.0)
		spawn_single_laser(Vector2(-18, nose_y), -10.0)
		spawn_single_laser(Vector2(18, nose_y), 10.0)
	else:
		spawn_single_laser(Vector2(-8, nose_y), -5.0)
		spawn_single_laser(Vector2(8, nose_y), 5.0)
		spawn_single_laser(Vector2(-22, nose_y), -15.0)
		spawn_single_laser(Vector2(22, nose_y), 15.0)

func get_nose_offset() -> float:
	if sprite and sprite.texture:
		return (sprite.texture.get_size().y * sprite.scale.y * 0.5) + 8.0
	return 32.0

func spawn_single_laser(offset: Vector2, angle_offset_deg: float = 0.0) -> void:
	var laser = enemy_laser_scene.instantiate() as Area2D
	laser.global_position = global_position + offset
	laser.rotation_degrees = angle_offset_deg

	if laser.has_method("setup_laser"):
		laser.setup_laser("ENEMY")
	if laser.has_method("setup_custom_laser"):
		laser.setup_custom_laser(current_laser_texture)
	if laser.has_method("set_damage"):
		laser.set_damage(current_laser_damage)
	elif "damage" in laser:
		laser.damage = current_laser_damage

	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(laser)
	else:
		get_parent().add_child(laser)

# ==========================================
# 🎨 TEXTURE & STATS SETUP
# ==========================================
func set_enemy_texture(texture_path: String) -> void:
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	var texture = load(texture_path) as Texture2D
	if texture and sprite:
		sprite.texture = texture

		var digits = texture_path.get_file().get_basename().replace("Enemy_", "").replace("enemy_", "")
		var lvl = digits.to_int()
		ship_level = clamp(lvl if lvl > 0 else 1, 1, 11)
		
		current_laser_texture = "res://asstes/Lasers/Lasers_" + str(ship_level) + ".png"

		current_laser_damage = 10.0 + (ship_level * 4.0)
		fire_rate = max(0.15, 0.45 - (ship_level * 0.025))

		var hp_mult = GameManager.enemy_hp_multiplier if GameManager and "enemy_hp_multiplier" in GameManager else 1.0
		health = int((5 + (ship_level * 2)) * hp_mult)
		max_health = health

		if collision_shape and collision_shape.shape:
			var img_size = texture.get_size()
			if collision_shape.shape is CapsuleShape2D:
				var new_shape = collision_shape.shape.duplicate() as CapsuleShape2D
				new_shape.radius = (img_size.x / 2.0) * 0.75
				new_shape.height = img_size.y * 0.85
				collision_shape.shape = new_shape

		if collision_shape:
			collision_shape.set_deferred("disabled", false)

	call_deferred("setup_thrusters")

# ==========================================
# 💥 DAMAGE, RECOIL & DESTRUCTION
# ==========================================
func take_damage(amount: float) -> void:
	if is_destroyed or global_position.y < 0.0: return
	health -= int(max(1.0, amount))

	if is_instance_valid(sprite):
		sprite.modulate = Color(3.0, 0.4, 0.4)
		var orig_y = sprite.position.y
		sprite.position.y -= 2.0
		
		get_tree().create_timer(0.06).timeout.connect(func():
			if is_instance_valid(sprite):
				sprite.modulate = Color(1.0, 1.0, 1.0)
				sprite.position.y = orig_y
		)

	if health <= 0: destroy()

func destroy() -> void:
	if is_destroyed: return
	is_destroyed = true

	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	if GameManager:
		if GameManager.has_method("register_kill"):
			GameManager.register_kill()
		if GameManager.has_method("add_score"):
			GameManager.add_score(100 * ship_level)

	check_drop_powerup()
	spawn_explosion()
	queue_free()

func spawn_explosion() -> void:
	if not explosion_scene: return
	var exp_instance = explosion_scene.instantiate() as Node2D
	exp_instance.global_position = global_position
	exp_instance.scale = Vector2(0.45, 0.45)
	
	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(exp_instance)
	else:
		get_parent().add_child(exp_instance)

func check_drop_powerup() -> void:
	if randf() <= 0.25 and powerup_scene:
		var p_item = powerup_scene.instantiate() as Area2D
		p_item.global_position = global_position
		var chosen_type: int = 8 if randf() <= 0.45 else (randi() % 8)
		
		if is_instance_valid(cached_scene_root):
			cached_scene_root.call_deferred("add_child", p_item)
		else:
			get_parent().call_deferred("add_child", p_item)
		
		if p_item.has_method("setup_type"):
			p_item.call_deferred("setup_type", chosen_type)

# ==========================================
# 🎯 COLLISION & DAMAGE HANDLING
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if is_destroyed or global_position.y < 0.0: return

	if area.is_in_group("enemies") or area.is_in_group("enemy_laser") or area.is_in_group("powerup"):
		return

	# Player Laser Hit
	if area.is_in_group("player_laser") or area.name.contains("Laser"):
		if not area.name.contains("EnemyLaser"):
			var dmg: float = 1.0
			if area.has_method("get_damage"):
				dmg = area.get_damage()
			elif "damage" in area:
				dmg = area.damage
			elif "laser_damage" in area:
				dmg = area.laser_damage
			
			area.queue_free()
			take_damage(dmg)

	# Direct Collision with Player
	elif area.is_in_group("player") or area.name == "Player":
		var ramming_damage: float = 30.0 + (ship_level * 5.0)
		if area.has_method("take_damage"):
			area.take_damage(ramming_damage)
		elif area.has_method("apply_damage"):
			area.apply_damage(ramming_damage)
		
		destroy()
