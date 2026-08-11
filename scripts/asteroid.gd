extends Area2D

# ==========================================
# ⚙️ EXPORT VARIABLES
# ==========================================
@export var min_speed: float = 200.0
@export var max_speed: float = 350.0

# ==========================================
# 📊 MOVEMENT & STATS
# ==========================================
var current_speed: float
var rotation_speed: float
var overlap_avoidance_direction: float = 0.0

# Cache Scene Tree and Screen Boundary (Performance & Memory Optimization)
var cached_scene_root: Node = null
var viewport_height: float = 1280.0

# Preloaded Scenes
var powerup_scene: PackedScene = preload("res://scenes/powerup.tscn")
var explosion_scene: PackedScene = preload("res://scenes/explosion.tscn")

# Health & State Flags
var health: int = 1
var max_health: int = 1
var is_destroyed: bool = false

# Node References
@onready var sprite: Sprite2D = $Asteroid1
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ==========================================
# 🎬 GODOT LIFECYCLE
# ==========================================
func _ready() -> void:
	name = "Asteroid"
	
	if not is_in_group("enemies"):
		add_to_group("enemies")
		
	var diff_mult = GameManager.difficulty_multiplier if GameManager and "difficulty_multiplier" in GameManager else 1.0
	current_speed = randf_range(min_speed, max_speed) * diff_mult
	rotation_speed = randf_range(-1.5, 1.5)
	overlap_avoidance_direction = randf_range(-50.0, 50.0)
	
	cached_scene_root = get_tree().current_scene
	viewport_height = get_viewport_rect().size.y

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if is_destroyed:
		return

	# --- 🧹 OFF-SCREEN CLEANUP & MISSED ENEMY COUNTER ---
	if global_position.y > viewport_height + 120.0:
		if GameManager and GameManager.has_method("enemy_missed"):
			GameManager.enemy_missed() # Register missed asteroid when escaping bottom screen
		queue_free()
		return
	elif global_position.y < -250.0:
		queue_free()
		return

	var speed_multiplier = 1.0
	if GameManager and GameManager.has_method("get_effective_enemy_speed_multiplier"):
		speed_multiplier = GameManager.get_effective_enemy_speed_multiplier()
	elif GameManager and "enemy_speed_multiplier" in GameManager:
		speed_multiplier = GameManager.enemy_speed_multiplier

	global_position.y += current_speed * speed_multiplier * delta
	global_position.x += overlap_avoidance_direction * speed_multiplier * delta
	
	if sprite:
		sprite.rotation += rotation_speed * delta

# ==========================================
# 🎨 TEXTURE & HEALTH SETUP
# ==========================================
func set_asteroid_texture(texture_path: String) -> void:
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	var texture = load(texture_path) as Texture2D
	if texture and sprite:
		sprite.texture = texture
		sprite.centered = true
		
		# Health Mapping based on Asteroid Size
		var base_hp: int = 1
		var file_name = texture_path.get_file()
		if "Asteroid_5" in file_name or "5" in file_name:
			base_hp = 5
		elif "Asteroid_4" in file_name or "4" in file_name:
			base_hp = 4
		elif "Asteroid_3" in file_name or "3" in file_name:
			base_hp = 3
		elif "Asteroid_2" in file_name or "2" in file_name:
			base_hp = 2
		else:
			base_hp = 1
			
		var hp_mult = GameManager.enemy_hp_multiplier if GameManager and "enemy_hp_multiplier" in GameManager else 1.0
		max_health = max(3, int(base_hp * hp_mult * 2))
		health = max_health
		
		# Dynamic Collision Shape Fitting
		if collision_shape and collision_shape.shape:
			var img_size = texture.get_size()
			if collision_shape.shape is CircleShape2D:
				var new_shape = collision_shape.shape.duplicate() as CircleShape2D
				new_shape.radius = (img_size.x / 2.0) * 0.95
				collision_shape.shape = new_shape
				
		if collision_shape:
			collision_shape.set_deferred("disabled", false)

# ==========================================
# 🎁 POWERUP DROP SYSTEM
# ==========================================
func check_drop_powerup() -> void:
	if randf() <= 0.20 and powerup_scene:
		var p_item = powerup_scene.instantiate() as Area2D
		p_item.global_position = global_position
		
		# Weighted selection: 45% Coin vs 55% Special Powerups
		var chosen_type: int = 8 if randf() <= 0.45 else (randi() % 8)
			
		if is_instance_valid(cached_scene_root):
			cached_scene_root.call_deferred("add_child", p_item)
		else:
			get_parent().call_deferred("add_child", p_item)
		
		if p_item.has_method("setup_type"):
			p_item.call_deferred("setup_type", chosen_type)
		elif p_item.has_method("setup_random_type"):
			p_item.call_deferred("setup_random_type")

# ==========================================
# 💥 EXPLOSION & DAMAGE LOGIC
# ==========================================
func spawn_proportional_explosion() -> void:
	if not explosion_scene:
		return
		
	var exp_instance = explosion_scene.instantiate() as Node2D
	exp_instance.global_position = global_position
	
	var exp_scale: float = 0.35 + (max_health * 0.2)
	exp_instance.scale = Vector2(exp_scale, exp_scale)
	
	if is_instance_valid(cached_scene_root):
		cached_scene_root.add_child(exp_instance)
	else:
		get_parent().add_child(exp_instance)

func take_damage(amount: float) -> void:
	if is_destroyed or global_position.y < 0.0:
		return

	health -= 1

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
			GameManager.add_score(25 * max_health)

	spawn_proportional_explosion()
	check_drop_powerup()
	queue_free()

# ==========================================
# 🎯 COLLISION HANDLING
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if is_destroyed or global_position.y < 0.0:
		return

	if area.is_in_group("powerup") or area.name.contains("Powerup") or area.is_in_group("enemies"):
		return

	if area.is_in_group("player_laser") or area.name.contains("Laser"):
		if not area.name.contains("EnemyLaser"):
			area.queue_free()
			take_damage(1.0)
				
	elif area.is_in_group("player") or area.name == "Player":
		if area.has_method("take_damage"):
			var damage_amount = (max_health * 8.0) + 7.0
			area.take_damage(damage_amount)
		destroy()
