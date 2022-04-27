extends KinematicBody

enum move_state {
	walking,
	crouching,
	sliding,
	sprinting,
}

export var mouse_sensitivity = 0.05
export var max_look_angles = Vector2(-90, 90)

export var gravity_scale = 20
export var jump_speed = 10

export var walk_speed = 20
export var sprint_speed = 40
export var crouch_speed = 12
export var slide_input_speed = 5
export var slide_speed = 25

export var ground_acceleration = 5
export var air_acceration = 2

export var stand_height : float = 2
export var crouch_height : float = 1
export var height_adjust_speed : float = 5

var snap_vector : Vector3 = Vector3()
var movement_vector : Vector3 = Vector3()
var gravity_vector : Vector3 = Vector3()
var slide_vector : Vector3 = Vector3()
onready var current_height : float = stand_height
var target_height : float = stand_height
var current_state = move_state.walking

onready var camera_arm = $Camera_Arm
onready var player_collision = $Collision

func _process(delta):
	var input_vector = Vector2()
	input_vector.x = (Input.get_action_strength("move_left") - Input.get_action_strength("move_right"))
	input_vector.y = (Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	input_vector = input_vector.normalized()
	if is_on_floor():
		ground_move(delta, input_vector)
	else:
		if current_state == move_state.crouching:
			toggle_crouch(delta)
		air_move(delta, input_vector)
	
	if Input.is_action_just_pressed("jump") and can_jump():
		snap_vector = Vector3.ZERO
		gravity_vector = Vector3.UP * jump_speed
	
	if Input.is_action_just_pressed("crouch") and is_on_floor() and (current_state == move_state.walking or current_state == move_state.crouching):
		toggle_crouch(delta)
	
	if Input.is_action_just_pressed("sprint") and can_sprint():
		current_state = move_state.sprinting
	
	if Input.is_action_just_pressed("crouch") and current_state == move_state.sprinting:
		begin_slide(delta)
	
	adjust_height(delta)
	resolve_current_state(delta)

func _physics_process(delta):
	apply_motion(delta)

func apply_motion(delta):
	slide_vector = slide_vector.linear_interpolate(Vector3.ZERO, delta)
	var final_movement_vector = movement_vector + gravity_vector + slide_vector
	move_and_slide_with_snap(final_movement_vector, snap_vector, Vector3.UP)

func resolve_current_state(delta):
	if slide_vector.length() <= crouch_speed:
		slide_vector = Vector3.ZERO
		if current_state == move_state.sliding:
			slide_vector = Vector3.ZERO
			current_state = move_state.crouching
	elif current_state == move_state.sliding and !is_on_floor():
		slide_vector /= 2
		current_state = move_state.walking
	
	if (current_state == move_state.walking or current_state == move_state.sprinting):
		target_height = stand_height
	elif (current_state == move_state.crouching or current_state == move_state.sliding):
		target_height = crouch_height

#If player is on the ground, grabs the horizontal movement and changes the movement vector.
func ground_move(delta, inputs : Vector2):
	var speed = get_speed()
	var accel = get_acceleration()
	var direction = get_direction_vector(inputs)
	
	var horiz_move = Vector3(movement_vector.x, 0, movement_vector.z)
	horiz_move = horiz_move.linear_interpolate(speed * direction, accel * delta)
	movement_vector = Vector3(horiz_move.x, 0, horiz_move.z)
	gravity_vector = Vector3.ZERO
	snap_vector = -get_floor_normal()

#If the player is in the air, will apply Y-direction movement with applied gravity scale in case you want low gravity.
func air_move(delta, inputs : Vector2, applied_gravity : float = 1.0):
	var speed = get_speed()
	var accel = get_acceleration()
	var direction = get_direction_vector(inputs)
	
	var horiz_move = Vector3(movement_vector.x, 0, movement_vector.z)
	horiz_move = horiz_move.linear_interpolate(speed * direction, accel * delta)
	movement_vector = Vector3(horiz_move.x, 0, horiz_move.z)
	gravity_vector += Vector3.DOWN * gravity_scale * applied_gravity * delta
	snap_vector = Vector3.DOWN

#Adjusts the player's height and camera arm height if player is not at target height
func adjust_height(delta):
	current_height = player_collision.shape.height
	if current_height != target_height:
		current_height = current_height + (target_height - current_height) * height_adjust_speed * delta
		player_collision.shape.height = current_height
		player_collision.translation.y = current_height
		camera_arm.translation.y = current_height * 2 - 0.4

func begin_slide(delta):
	slide_vector = movement_vector.normalized() * slide_speed
	target_height = crouch_height
	current_state = move_state.sliding

#Toggles the player's crouch state and sets target height
func toggle_crouch(delta):
	if current_state == move_state.walking:
		target_height = crouch_height
		current_state = move_state.crouching
	elif current_state == move_state.crouching:
		if can_stand():
			target_height = stand_height
			current_state = move_state.walking

#Checks if the player can sprint (is on the floor and walking)
func can_sprint():
	if current_state == move_state.walking and is_on_floor():
		return true
	else:
		return false

#Checks if the player is walking and not standing still
func can_slide():
	if current_state == move_state.walking and movement_vector.length() > 0:
		return true
	else:
		return false

#Checks if the player is in a movement state that's capable of jumping and on the floor
func can_jump():
	if is_on_floor() and (current_state == move_state.walking or current_state == move_state.sprinting):
		return true
	else:
		return false

#Checks if the player can stand by shooting a raycast upwards, if already standing/sprinting just returns true
func can_stand():
	if current_state != move_state.crouching or current_state != move_state.sliding:
		return true
	else:
		var space_state = get_world().direct_space_state
		var collision = space_state.intersect_ray(global_transform.origin, global_transform.origin + Vector3.UP * (stand_height / 2), [self])
		return collision.size <= 0

#Checks if player is on ground, returns acceleration.  Takes 1 override, if player wants to ignore acceleration.
func get_acceleration(ignore : bool = false):
	if ignore:
		return 0
	elif is_on_floor():
		return ground_acceleration
	else:
		return air_acceration

#Returns speed based on the player's move state
func get_speed():
	match current_state:
		move_state.walking:
			return walk_speed
		move_state.crouching:
			return crouch_speed
		move_state.sprinting:
			return sprint_speed
		move_state.sliding:
			#get vector going down slope if on slope
			return slide_input_speed
		_:
			print("ERROR: Could not match movement state!")
			return walk_speed

#Takes input vector and returns vector relative to player's direction (unless sliding down hill then will return vector facing down slope)
func get_direction_vector(input_vector):
	return (self.global_transform.basis.x * input_vector.x) + (self.global_transform.basis.z * input_vector.y)


func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		self.rotate_y(deg2rad(-event.relative.x * mouse_sensitivity))
		camera_arm.rotate_x(deg2rad(event.relative.y * mouse_sensitivity))
		camera_arm.rotation.x = clamp(camera_arm.rotation.x, deg2rad(max_look_angles.x), deg2rad(max_look_angles.y))

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
