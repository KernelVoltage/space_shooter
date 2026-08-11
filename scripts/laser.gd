extends Area2D

# --- EXPORT & CONFIGS ---
@export var speed: float = 850.0
var damage: float = 1.0
var is_enemy_laser: bool = false
var move_direction: Vector2 = Vector2.UP

# Sprite2D & CollisionShape2D references
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var collision_shape: CollisionShape2D = $CollisionShape2D if has_node("CollisionShape2D") else null

func _ready() -> void:
	if not is_in_group("player_laser") and not is_enemy_laser:
		add_to_group("player_laser")
	elif is_enemy_laser and not is_in_group("enemy_laser"):
		add_to_group("enemy_laser")

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
		
	_adjust_laser_transform_and_collision()

	# Rotation alignment
	if rotation != 0.0 and move_direction == Vector2.UP:
		move_direction = move_direction.rotated(rotation)

# Basic setup for Player vs Enemy
func setup_laser(type: String) -> void:
	if type == "PLAYER":
		damage = 1.0
		is_enemy_laser = false
		add_to_group("player_laser")
		if is_in_group("enemy_laser"):
			remove_from_group("enemy_laser")
		move_direction = Vector2.UP.rotated(rotation)
	elif type == "ENEMY":
		damage = 1.0
		is_enemy_laser = true
		add_to_group("enemy_laser")
		if is_in_group("player_laser"):
			remove_from_group("player_laser")
		move_direction = Vector2.DOWN.rotated(rotation)

# Direct Damage Setter
func set_damage(dmg: float) -> void:
	damage = dmg

# Single argument texture setup
func setup_custom_laser(texture_path: String) -> void:
	if texture_path == "":
		return
		
	var tex = load(texture_path) as Texture2D
	if not sprite and has_node("Sprite2D"):
		sprite = $Sprite2D
		
	if tex and sprite:
		sprite.texture = tex
		_adjust_laser_transform_and_collision()
		
		# Dynamic damage mapping
		if texture_path.contains("Lasers_1.png"): damage = 2.0
		elif texture_path.contains("Lasers_2.png"): damage = 3.0
		elif texture_path.contains("Lasers_3.png"): damage = 4.0
		elif texture_path.contains("Lasers_4.png"): damage = 5.0
		elif texture_path.contains("Lasers_5.png"): damage = 6.0
		elif texture_path.contains("Lasers_6.png"): damage = 7.0
		elif texture_path.contains("Lasers_8.png"): damage = 10.0
		elif texture_path.contains("Lasers_10.png"): damage = 15.0

# Full Parameter Setup (Called by Boss / Special Enemies)
func setup_laser_custom(texture_path: String, custom_speed: float, custom_damage: float, is_aimed: bool = false) -> void:
	setup_custom_laser(texture_path)
	speed = custom_speed
	damage = custom_damage
	is_enemy_laser = true
	add_to_group("enemy_laser")
	if is_in_group("player_laser"):
		remove_from_group("player_laser")

	if not is_aimed:
		move_direction = Vector2.DOWN.rotated(rotation)

# Directional Custom Setup (For Fan Spread / Radial Bursts)
func setup_directional_custom_laser(texture_path: String, custom_speed: float, custom_damage: float, direction: Vector2) -> void:
	setup_custom_laser(texture_path)
	speed = custom_speed
	damage = custom_damage
	is_enemy_laser = true
	add_to_group("enemy_laser")
	if is_in_group("player_laser"):
		remove_from_group("player_laser")

	move_direction = direction.normalized()
	rotation = move_direction.angle() - (PI / 2.0)

# Predictive Target Aiming
func set_aim_target(target_pos: Vector2) -> void:
	var dir = (target_pos - global_position).normalized()
	if dir != Vector2.ZERO:
		move_direction = dir
		rotation = move_direction.angle() - (PI / 2.0)

# PERFECT SIZE & VERTICAL ORIENTATION
func _adjust_laser_transform_and_collision() -> void:
	if not sprite and has_node("Sprite2D"):
		sprite = $Sprite2D

	if not sprite or not sprite.texture:
		return

	sprite.scale = Vector2(1, 1)

	# Dynamic Vertical Check
	var raw_size = sprite.texture.get_size()
	if raw_size.x > raw_size.y:
		sprite.rotation_degrees = 90.0
	else:
		sprite.rotation_degrees = 0.0

	# Collision Box Scaling according to size
	if collision_shape and collision_shape.shape:
		var visual_width = raw_size.y * sprite.scale.x if sprite.rotation_degrees == 90.0 else raw_size.x * sprite.scale.x
		var visual_height = raw_size.x * sprite.scale.y if sprite.rotation_degrees == 90.0 else raw_size.y * sprite.scale.y

		# Safe Duplicate shape per instance
		collision_shape.shape = collision_shape.shape.duplicate()

		if collision_shape.shape is RectangleShape2D:
			collision_shape.shape.size = Vector2(visual_width * 0.85, visual_height * 0.95)
		elif collision_shape.shape is CapsuleShape2D:
			collision_shape.shape.radius = visual_width * 0.45
			collision_shape.shape.height = visual_height * 0.9

func _process(delta: float) -> void:
	var effective_delta = delta

	# Green Crystal Slow-Motion Effect for Enemy Lasers
	if is_enemy_laser and GameManager:
		var mult = 1.0
		if GameManager.has_method("get_effective_enemy_speed_multiplier"):
			mult = GameManager.get_effective_enemy_speed_multiplier()
		elif "enemy_speed_multiplier" in GameManager:
			mult = GameManager.enemy_speed_multiplier
		effective_delta *= mult

	global_position += move_direction * speed * effective_delta

	# Screen Off Cleanup
	if global_position.y < -200 or global_position.y > 1500 or global_position.x < -200 or global_position.x > 1000:
		queue_free()

# UNIVERSAL DAMAGE SYSTEM
func _on_area_entered(area: Area2D) -> void:
	if is_enemy_laser:
		if area.is_in_group("enemies") or area.is_in_group("enemy_laser") or area.is_in_group("powerup"):
			return
	else:
		if area.is_in_group("player") or area.is_in_group("player_laser") or area.is_in_group("powerup"):
			return

	var targets_to_try: Array[Node] = [area]
	if area.get_parent(): targets_to_try.append(area.get_parent())
	if area.owner: targets_to_try.append(area.owner)

	var damage_dealt = false

	for target in targets_to_try:
		if is_instance_valid(target):
			if target.has_method("take_damage"):
				target.take_damage(damage)
				damage_dealt = true
				break
			elif target.has_method("destroy"):
				target.destroy()
				damage_dealt = true
				break
			elif "health" in target:
				target.health -= damage
				damage_dealt = true
				break

	if damage_dealt or area.is_in_group("enemies") or area.is_in_group("player"):
		queue_free()
