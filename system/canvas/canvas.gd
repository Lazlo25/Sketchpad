class_name Canvas
extends Node2D

signal canvas_input(event: InputEventMouse)

@export var camera_movable: bool = false
@export var camera: Camera2D

var _project: Project
var _time_machine_pictures: Array[Image] = []
var _time_machine_frames: Array[int] = []
var _time_machine_layers: Array[int] = []

@onready var control_node: Control = $Control
@onready var layers_node: Node2D = $Control/Layers
@onready var onion_skin_renderer: OnionSkinRenderer = $Control/OnionSkin
@onready var dynamic_node: Node2D = $Control/Dynamic

@onready var bake_viewport: Viewport = $BakeViewport
@onready var bake_node: Node2D = $BakeViewport/Bake


func _ready() -> void:
	camera.movable = camera_movable


func attach_project(project: Project) -> void:
	if _project and _project.new_current_page.is_connected(render_page):
		_project.new_current_page.disconnect(render_page)
	_project = project

	_time_machine_pictures.clear()
	_time_machine_frames.clear()
	_time_machine_layers.clear()
	if _project:
		_project.new_current_page.connect(render_page)
		onion_skin_renderer.attach_project(project)


func go_back_one_step() -> void:
	if _project == null:
		return

	if _time_machine_pictures.size() == 0:
		return

	var picture = _time_machine_pictures.pop_back()
	var frame_number = _time_machine_frames.pop_back()
	var layer_number = _time_machine_layers.pop_back()

	if frame_number < 0:
		return

	if frame_number >= _project.frames.size():
		return

	var page = _project.frames[frame_number]

	if layer_number < 0:
		return

	if layer_number >= page.layers.size():
		return

	page.set_layer(layer_number, picture)
	_project.set_layer(layer_number)
	_project.set_frame(frame_number)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed:
			if not event.echo:
				if event.keycode == KEY_Z:
					if event.ctrl_pressed or event.meta_pressed:
						go_back_one_step()
						get_viewport().set_input_as_handled()


func _put_current_picture_in_time_machine() -> void:
	if _project == null:
		return

	var page = _project.get_current_page()

	if page == null:
		return

	var layer_number = _project.current_layer

	if layer_number < 0:
		return

	if layer_number >= page.layers.size():
		return

	_time_machine_pictures.append(page.layers[layer_number].duplicate())
	_time_machine_frames.append(_project.current_frame)
	_time_machine_layers.append(layer_number)

	while _time_machine_pictures.size() > 20:
		_time_machine_pictures.remove_at(0)
		_time_machine_frames.remove_at(0)
		_time_machine_layers.remove_at(0)


## Refreshes canvas sprites to current page. [br]
## [param page] - Page to render.
func render_page(page: Page) -> void:

	control_node.size = Vector2(_project.width, _project.height)
	control_node.position = -(control_node.size / 2.0)

	for node in layers_node.get_children():
		layers_node.remove_child(node)
		node.queue_free()

	var textures = page.get_content()
	for texture in textures:
		var sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layers_node.add_child(sprite)
		if sprite is Sprite2D:
			sprite.texture = texture

	onion_skin_renderer.render()


func toggle_onion_skin() -> void:
	onion_skin_renderer.toggle()


## Sets the number of ghost frames to display backwards.
func set_onion_skin_depth(new_depth: int) -> void:
	onion_skin_renderer.set_depth(new_depth)


## Bakes [code]dynamic_node[/code] contents to the current page.
func bake_page() -> void:
	# Getting items from our project.
	var current_page = _project.frames[_project.current_frame]
	var current_layer = _project.current_layer
	_put_current_picture_in_time_machine()

	bake_viewport.size = Vector2(_project.width, _project.height)
	bake_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	bake_viewport.transparent_bg = true

	# Preventing the odd flicker between render and baking.
	for node in dynamic_node.get_children():
		var new_node = node.duplicate()
		bake_node.add_child(new_node)

	# Taking the snapshot of our dynamic node.
	bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	# Baking ontop of the existing layer.
	var texture_to_bake = bake_viewport.get_texture()
	var image_to_bake = texture_to_bake.get_image()

	# Convert premultiply RGB to normal RGB
	for y in image_to_bake.get_height():
		for x in image_to_bake.get_width():
			var c = image_to_bake.get_pixel(x, y)
			if c.a > 0.0:
				c.r /= c.a
				c.g /= c.a
				c.b /= c.a
			image_to_bake.set_pixel(x, y, c)

	var layer_image = current_page.layers[current_layer]
	layer_image.blend_rect(
		image_to_bake, Rect2(Vector2.ZERO, image_to_bake.get_size()), Vector2.ZERO
	)

	current_page.set_layer(current_layer, layer_image)

	# Clearing dynamic and viewport now that it is baked.
	for node in bake_node.get_children():
		bake_node.remove_child(node)
		node.queue_free()

	for node in dynamic_node.get_children():
		dynamic_node.remove_child(node)
		node.queue_free()

	_project.get_current_page()


func _on_gui_input(event: InputEvent) -> void:
	canvas_input.emit(event)
