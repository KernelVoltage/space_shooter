extends Area2D

# ==========================================
# ⚙️ EXPORT VARIABLES
# ==========================================
@export var min_speed: float = 180.0
@export var max_speed: float = 280.0

# ==========================================
# 📊 MOVEMENT & STATS
# ==========================================
var current_speed: float
var target_player: Node2D = null
var health: int = 1
var max_health: int = 1
var is_destroyed: bool = false
var ship_level: int = 1

# Performance & Screen Boundary Caching
var cached_scene_root: Node = null
var viewport_height: float = 1280.0

# ==========================================
# 💣 WEAPONS & PRELOADED SCENES
# ==========================================
var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")
var powerup_scene: PackedScene = preload("res://scenes/powerup.tscn")
var thruster_scene: PackedScene = preload("res://scenes/thruster.tscn")
var enemy_laser_scene: PackedScene = preload("res://scenes/laser.tscn")

var fire_timer: float = 0.0
var fire_rate: float = 0.90
var current_laser_texture: String = "res://asstes/Lasers/Lasers_1.png"
var current_laser_damage: float = 12.0

@onready var sprite: Sprite2D = $FighterRed
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	name = "EnemyNormal"
	
	if not is_in_group("enemies"):
		add_to_group("enemies")
		
	var diff_mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
	current_speed = randf_range(min_speed, max_speed) * diff_mult
	fire_timer = randf_range(0.4, 0.8)
	
	cached_scene_root = get_tree().current_scene
	viewport_height = get_viewport_rect().size.y
	
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	_cache_player_reference()
	call_deferred("setup_thrusters")

func _process(delta: float) -> void:
	if is_destroyed:
		return

	# --- 🧹 OFF-SCREEN CLEANUP & MISSED ENEMY TRACKING ---
	if global_position.y > viewport_height + 100.0:
		if not is_destroyed and GameManager and GameManager.has_method("enemy_missed"):
			GameManager.enemy_missed()
		queue_free()
		return
	elif global_position.y < -250.0:
		queue_free()
		return

	# --- 🟢 SLOW-MOTION & SPEED MULTIPLIER INTEGRATION ---
	var speed_multiplier = 1.0
	if GameManager and GameManager.has_method("get_effective_enemy_speed_multiplier"):
		speed_multiplier = GameManager.get_effective_enemy_speed_multiplier()
	elif GameManager and "enemy_speed_multiplier" in GameManager:
		speed_multiplier = GameManager.enemy_speed_multiplier

	global_position.y += current_speed * speed_multiplier * delta

	# --- 🛑 FIRING SYSTEM CONDITIONS ---
	var game_lvl = GameManager.current_level if (GameManager and "current_level" in GameManager) else 1
	
	if ship_level > 2 and game_lvl > 2 and global_position.y >= 0.0:
		fire_timer -= delta
		if fire_timer <= 0.0:
			prepare_and_fire()
			var mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
			fire_timer = max(0.35, fire_rate - (mult * 0.05))

# ==========================================
# 🚀 THRUSTERS & VISUAL SETUP
# ==========================================
func setup_thrusters() -> void:
	if not thruster_scene:
		return

	var thruster_marker = get_node_or_null("ThrusterMarker")
	
	if not thruster_marker:
		for child in get_children():
			if child is Marker2D and child.name.to_lower().contains("thruster"):
				thruster_marker = child
				break

	if not thruster_marker:
		return

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
	else:
		var anim = thruster_instance.get_node_or_null("AnimatedSprite2D")
		if anim and anim is AnimatedSprite2D:
			anim.autoplay = "Thruster"
			anim.play("Thruster")
			anim.visible = true

func _cache_player_reference() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		target_player = players[0]
	else:
		target_player = null

# ==========================================
# 🎨 SHIP LEVEL & STAT SCALING
# ==========================================
func set_enemy_texture(texture_path: String) -> void:
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	var texture = load(texture_path) as Texture2D
	if texture and sprite:
		sprite.texture = texture
		sprite.centered = true
		
		var digits = texture_path.get_file().get_basename().replace("Fighter_", "").replace("fighter_", "").replace("Enemy_", "").replace("enemy_", "")
		var lvl = digits.to_int()
		ship_level = clamp(lvl if lvl > 0 else 1, 1, 11)
		current_laser_texture = "res://asstes/Lasers/Lasers_" + str(ship_level) + ".png"

		var diff_mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
		var hp_mult = GameManager.enemy_hp_multiplier if GameManager and "enemy_hp_multiplier" in GameManager else 1.0

		if ship_level <= 2:
			max_health = int(2 * hp_mult)
			current_speed *= 1.45 * diff_mult
		elif ship_level <= 5:
			max_health = int(4 * hp_mult)
			current_speed *= 1.25 * diff_mult
			fire_rate = 0.70
			current_laser_damage = 18.0
		elif ship_level <= 8:
			max_health = int(8 * hp_mult)
			current_speed *= 1.10 * diff_mult
			fire_rate = 0.55
			current_laser_damage = 25.0
		else:
			max_health = int(16 * hp_mult)
			current_speed *= 0.95 * diff_mult
			fire_rate = 0.40
			current_laser_damage = 35.0

		health = max_health

		# Shape Duplication & Fit Optimization
		if collision_shape and collision_shape.shape:
			var img_size = texture.get_size()
			if collision_shape.shape is CapsuleShape2D:
				var new_shape = collision_shape.shape.duplicate() as CapsuleShape2D
				new_shape.radius = (img_size.x / 2.0) * 0.80
				new_shape.height = img_size.y * 0.90
				collision_shape.shape = new_shape
			elif collision_shape.shape is RectangleShape2D:
				var new_shape = collision_shape.shape.duplicate() as RectangleShape2D
				new_shape.size = img_size * 0.85
				collision_shape.shape = new_shape
				
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
			
	call_deferred("setup_thrusters")

# ==========================================
# 🔫 FIRING SYSTEM WITH TARGETING
# ==========================================
func prepare_and_fire() -> void:
	if is_destroyed or global_position.y < 0.0:
		return
		
	if is_instance_valid(sprite) and ship_level >= 7:
		var original_mod = sprite.modulate
		sprite.modulate = Color(2.0, 1.2, 0.6) # Flash glow pre-shot
		
		get_tree().create_timer(0.06).timeout.connect(func():
			if is_instance_valid(sprite) and not is_destroyed:
				sprite.modulate = original_mod
				execute_class_firing_pattern()
		)
	else:
		execute_class_firing_pattern()

func execute_class_firing_pattern() -> void:
	if not enemy_laser_scene or is_destroyed or global_position.y < 0.0:
		return

	# Calculate dynamic trajectory tilt towards player
	var aim_angle_offset: float = 0.0
	if is_instance_valid(target_player):
		var dx = target_player.global_position.x - global_position.x
		aim_angle_offset = clamp(dx * 0.05, -15.0, 15.0)

	if ship_level <= 5:
		spawn_single_laser(Vector2(0, get_nose_offset()), 180.0 + aim_angle_offset)
	elif ship_level <= 8:
		spawn_single_laser(Vector2(-16, get_nose_offset()), 170.0 + aim_angle_offset)
		spawn_single_laser(Vector2(16, get_nose_offset()), 190.0 + aim_angle_offset)
	else:
		spawn_single_laser(Vector2(0, get_nose_offset()), 180.0 + aim_angle_offset)
		spawn_single_laser(Vector2(-22, get_nose_offset()), 155.0 + aim_angle_offset)
		spawn_single_laser(Vector2(22, get_nose_offset()), 205.0 + aim_angle_offset)

func get_nose_offset() -> float:
	if sprite and sprite.texture:
		return (sprite.texture.get_size().y * sprite.scale.y * 0.5) + 4.0
	return 30.0

func spawn_single_laser(offset: Vector2, rot_deg: float) -> void:
	var laser = enemy_laser_scene.instantiate() as Area2D
	laser.global_position = global_position + offset
	laser.rotation_degrees = rot_deg
	
	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(laser)
	else:
		get_parent().add_child(laser)
	
	if laser.has_method("setup_laser"):
		laser.setup_laser("ENEMY")
	if laser.has_method("setup_custom_laser"):
		laser.setup_custom_laser(current_laser_texture)
	if laser.has_method("set_damage"):
		laser.set_damage(current_laser_damage)
	elif "damage" in laser:
		laser.damage = current_laser_damage

# ==========================================
# 💥 DAMAGE, RECOIL & DESTRUCTION
# ==========================================
func take_damage(amount: float) -> void:
	if is_destroyed or global_position.y < 0.0:
		return

	health -= int(max(1.0, amount))

	# Recoil animation & Red flash on hit
	if is_instance_valid(sprite):
		sprite.modulate = Color(3.0, 0.3, 0.3)
		var orig_y = sprite.position.y
		sprite.position.y -= 3.0 # Nudge back on hit
		
		get_tree().create_timer(0.06).timeout.connect(func():
			if is_instance_valid(sprite):
				sprite.modulate = Color(1.0, 1.0, 1.0)
				sprite.position.y = orig_y
		)

	if health <= 0:
		destroy()

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	if GameManager:
		if GameManager.has_method("register_kill"):
			GameManager.register_kill()
		if GameManager.has_method("add_score"):
			GameManager.add_score(50 * ship_level)
		
	check_drop_powerup()
	spawn_explosion()
	queue_free()

func spawn_explosion() -> void:
	if not explosion_scene:
		return
		
	var exp_instance = explosion_scene.instantiate() as Node2D
	exp_instance.global_position = global_position
	
	var exp_scale: float = 0.30
	if sprite and sprite.texture:
		var sprite_width = sprite.texture.get_size().x
		exp_scale = clamp(sprite_width / 260.0, 0.25, 0.40)
		
	exp_instance.scale = Vector2(exp_scale, exp_scale)
	
	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(exp_instance)
	else:
		get_parent().add_child(exp_instance)

func check_drop_powerup() -> void:
	if randf() <= 0.30 and powerup_scene:
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
# 🎯 COLLISION HANDLING
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if is_destroyed or global_position.y < 0.0:
		return

	if area.is_in_group("enemies") or area.is_in_group("enemy_laser") or area.is_in_group("powerup"):
		return

	if area.is_in_group("player_laser") or area.name.contains("Laser"):
		if not area.name.contains("EnemyLaser"):
			var dmg = 1.0
			if area.has_method("get_damage"):
				dmg = area.get_damage()
			elif "damage" in area:
				dmg = area.damage
			area.queue_free()
			take_damage(dmg)
				
	elif area.is_in_group("player") or area.name == "Player":
		if area.has_method("destroy_player"):
			area.destroy_player()
		elif area.has_method("take_damage"):
			area.take_damage(100.0)
			
		destroy()
