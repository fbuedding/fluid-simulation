extends Node2D

@export var grid_size: Vector2i = Vector2i(15, 10)
@export var grid_margin: Vector2 = Vector2(10, 10)

@export var density: float = 1.0
@export var iterations: int = 5

@export var arrow_color: Color
@export var sub_arrow_color: Color
@export var arrow_line_width: float = 1.0
@export var sub_arrow_line_width: float = 1.0
@export var arrows_visible := false

@export var interpolation_subdivision: int = 6

@export var brush_color: Color
@export var velocity_highlight_color: Color
@export var velocity_highlight_radius: float = 5

enum overlays { NONE, VELOCITY, PRESSURE, DIVERGENCE }
const highlight_solid_cell: bool = true

@export var mouse_position_label: Label
@export var pressure_label: Label
@export var velocity_label: Label
@export var divergence_label: Label

@onready var overlay_node: Sprite2D = $Overlay
@onready var grid_node: Grid = $Grid

var pressures: Double2DArray
var divergence: Double2DArray
var solid_cells: Packed2dBooleanArray
var packed_compute_data: PackedVector2Array
var velocities_x: Double2DArray
var velocities_y: Double2DArray

var velocities_x_1: Double2DArray
var velocities_y_1: Double2DArray

var window_size: Vector2
var cell_size: float
var cell_offset: float
var sub_cell_offset: float
var grid_offset: Vector2

var default_font: Font = ThemeDB.fallback_font

var solver_enabled := false

var brush_enabled := false
var brush_radius := 10

@export var brush_intensity := 1.0

var dragging := false
var dragging_start_position: Vector2

enum highlighted_velocity { X, Y, NONE }
var highlighted_velocity_state: highlighted_velocity = highlighted_velocity.NONE
var highlighted_velocity_index := Vector2i()
var highlighted_velocity_dragging_start_index := Vector2i(0, 0)
const DELTA: float = 1.0 / 60.0

var rd: RenderingDevice

var pressure_solver_shader_rid: RID
var packer_shader_rid: RID

var packed_data_shared_rid: RID
var velocities_x_shared_uniform_rid: RID
var velocities_y_shared_uniform_rid: RID
var solids_shared_uniform_rid: RID
var packer_params_uniform_rid: RID
var pressure_uniform_rid: RID
var solver_param_uniform_rid: RID

var packed_data_set: Array[RDUniform] = []
var velocity_set: Array[RDUniform] = []

var packed_data_uniform_set_packer: RID
var packed_data_uniform_set_solver: RID
var pressure_uniform_set: RID
var velocity_uniform_set_packer: RID
var packer_params_uniform_set: RID
var solver_params_uniform_set: RID

var solver_pipeline: RID
var packer_pipeline: RID


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		rd.free_rid(pressure_solver_shader_rid)
		rd.free_rid(packer_shader_rid)
		rd.free_rid(packed_data_shared_rid)
		rd.free_rid(velocities_x_shared_uniform_rid)
		rd.free_rid(velocities_y_shared_uniform_rid)
		rd.free_rid(solids_shared_uniform_rid)
		rd.free_rid(packer_params_uniform_rid)
		rd.free_rid(pressure_uniform_rid)
		rd.free_rid(solver_param_uniform_rid)
		rd.free_rid(packed_data_uniform_set_packer)
		rd.free_rid(pressure_uniform_set)
		rd.free_rid(velocity_uniform_set_packer)
		rd.free_rid(packer_params_uniform_set)
		rd.free_rid(solver_params_uniform_set)
		rd.free_rid(solver_pipeline)
		rd.free_rid(packer_pipeline)


func swap_velocities() -> void:
	var velocities_x_tmp := velocities_x
	velocities_x = velocities_x_1
	velocities_x_1 = velocities_x_tmp
	var velocities_y_tmp := velocities_y
	velocities_y = velocities_y_1
	velocities_y_1 = velocities_y_tmp


func _ready() -> void:
	calc_sizes_and_offsets()
	self.pressures = Double2DArray.new(grid_size.x, grid_size.y)
	self.divergence = Double2DArray.new(grid_size.x, grid_size.y)
	self.velocities_x = Double2DArray.new(grid_size.x + 1, grid_size.y)
	self.velocities_y = Double2DArray.new(grid_size.x, grid_size.y + 1)
	self.velocities_x_1 = Double2DArray.new(grid_size.x + 1, grid_size.y)
	self.velocities_y_1 = Double2DArray.new(grid_size.x, grid_size.y + 1)
	packed_compute_data = PackedVector2Array()
	packed_compute_data.resize(grid_size.x * grid_size.y)

	solid_cells = Packed2dBooleanArray.new(grid_size.x, grid_size.y)
	for y in grid_size.y:
		for x in grid_size.x:
			if x == 0 || y == 0 || x == grid_size.x - 1 || y == grid_size.y - 1:
				solid_cells.set_val(x, y, true)
			else:
				solid_cells.set_val(x, y, false)
	grid_node.set_params(grid_size, cell_size, solid_cells.to_2d_arr())
	grid_node.position = grid_offset
	calc_divergence()
	_init_compute_shaders()


func _init_compute_shaders() -> void:
	rd = RenderingServer.create_local_rendering_device()
	_init_shared_uniform_sets()
	_init_packer()
	_init_solver()


func _init_shared_uniform_sets() -> void:
	pass
	packed_data_shared_rid = _register_uniform(
		rd,
		0,
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
		packed_data_set,
		packed_compute_data.to_byte_array().size(),
	)
	var bytes := velocities_x.data.to_byte_array()
	velocities_x_shared_uniform_rid = _register_uniform(
		rd, 0, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, velocity_set, bytes.size(), bytes
	)
	bytes = velocities_y.data.to_byte_array()
	velocities_y_shared_uniform_rid = _register_uniform(
		rd, 1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, velocity_set, bytes.size(), bytes
	)
	solids_shared_uniform_rid = _register_uniform(
		rd,
		2,
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
		velocity_set,
		solid_cells.data.to_byte_array().size(),
		solid_cells.data.to_byte_array()
	)


func _init_solver() -> void:
	pressure_solver_shader_rid = _create_shader("res://solve_pressure.glsl")
	assert(pressure_solver_shader_rid.is_valid(), "Could not create shader")

	## Pressure
	var pressure_set: Array[RDUniform] = []
	## Params for pressure solver
	var params_solver_set: Array[RDUniform] = []
	pressure_uniform_rid = _register_uniform(
		rd,
		0,
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,
		pressure_set,
		pressures.data.to_byte_array().size(),
		pressures.data.to_byte_array()
	)

	var params := PackedInt32Array()
	params.resize(4)  # 8 padding bytes
	params[0] = grid_size.x
	params[1] = grid_size.y
	params[2] = 0
	params[3] = _ceiling_div(grid_size.x * grid_size.y, 2)
	solver_param_uniform_rid = _register_uniform(
		rd,
		0,
		RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,
		params_solver_set,
		params.to_byte_array().size(),
		params.to_byte_array()
	)

	packed_data_uniform_set_solver = rd.uniform_set_create(
		packed_data_set, pressure_solver_shader_rid, 0
	)
	pressure_uniform_set = rd.uniform_set_create(pressure_set, pressure_solver_shader_rid, 1)

	solver_params_uniform_set = rd.uniform_set_create(
		params_solver_set, pressure_solver_shader_rid, 2
	)

	solver_pipeline = rd.compute_pipeline_create(pressure_solver_shader_rid)


func _init_packer() -> void:
	packer_shader_rid = _create_shader("res://packer.glsl")
	assert(packer_shader_rid.is_valid(), "Could not create shader")
	## Params for pressure solve packer
	var param_packer_set: Array[RDUniform] = []
	var params := PackedInt32Array()
	params.resize(4)  # 8 padding bytes
	params[0] = grid_size.x
	params[1] = grid_size.y
	params[2] = 0
	params[3] = 0
	packer_params_uniform_rid = _register_uniform(
		rd,
		0,
		RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,
		param_packer_set,
		params.to_byte_array().size(),
		params.to_byte_array()
	)
	packed_data_uniform_set_packer = rd.uniform_set_create(packed_data_set, packer_shader_rid, 0)
	velocity_uniform_set_packer = rd.uniform_set_create(velocity_set, packer_shader_rid, 1)
	packer_params_uniform_set = rd.uniform_set_create(param_packer_set, packer_shader_rid, 2)

	packer_pipeline = rd.compute_pipeline_create(packer_shader_rid)


func _init_velocity_advecter() -> void:
	pass


func _run_pressure_solver() -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, solver_pipeline)
	rd.compute_list_bind_uniform_set(list, packed_data_uniform_set_solver, 0)
	rd.compute_list_bind_uniform_set(list, pressure_uniform_set, 1)
	rd.compute_list_bind_uniform_set(list, solver_params_uniform_set, 2)
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(list, grid_size.x * grid_size.y / 16 + 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.buffer_update(solver_param_uniform_rid, 4 * 2, 4, PackedInt32Array([1]).to_byte_array())
	list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, solver_pipeline)
	rd.compute_list_bind_uniform_set(list, packed_data_uniform_set_solver, 0)
	rd.compute_list_bind_uniform_set(list, pressure_uniform_set, 1)
	rd.compute_list_bind_uniform_set(list, solver_params_uniform_set, 2)
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(list, grid_size.x * grid_size.y / 16 + 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.buffer_update(solver_param_uniform_rid, 4 * 2, 4, PackedInt32Array([0]).to_byte_array())
	pass


func _run_packer(delta: float) -> void:
	var K := delta / (density * cell_size)
	rd.buffer_update(packer_params_uniform_rid, 4 * 2, 4, PackedFloat32Array([K]).to_byte_array())
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, packer_pipeline)
	rd.compute_list_bind_uniform_set(list, packed_data_uniform_set_packer, 0)
	rd.compute_list_bind_uniform_set(list, velocity_uniform_set_packer, 1)
	rd.compute_list_bind_uniform_set(list, packer_params_uniform_set, 2)
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(list, grid_size.x * grid_size.y / 16 + 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()


func _get_pressure() -> void:
	var output_bytes := rd.buffer_get_data(pressure_uniform_rid)
	pressures.data = output_bytes.to_float64_array()


func _update_velocity_buffers() -> void:
	var bytes := velocities_x.data.to_byte_array()
	rd.buffer_update(velocities_x_shared_uniform_rid, 0, bytes.size(), bytes)
	bytes = velocities_y.data.to_byte_array()
	rd.buffer_update(velocities_y_shared_uniform_rid, 0, bytes.size(), bytes)
	pass


func _create_shader(path: String) -> RID:
	var shader_fie: RDShaderFile = load(path)
	var shader_spirv: RDShaderSPIRV = shader_fie.get_spirv()
	if shader_spirv.compile_error_compute != "":
		push_error(shader_spirv.compile_error_compute)
		return RID()
	var shader_rid := rd.shader_create_from_spirv(shader_spirv)
	if not shader_rid.is_valid():
		push_error("Invalid Shader")
		return RID()
	return shader_rid


func _register_uniform(
	rendering_device: RenderingDevice,
	binding: int,
	type: RenderingDevice.UniformType,
	uniform_list: Array[RDUniform],
	size: int,
	bytes: PackedByteArray = PackedByteArray()
) -> RID:
	var buffer_rid: RID
	if type == RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER:
		buffer_rid = rendering_device.storage_buffer_create(size, bytes)
	else:
		buffer_rid = rendering_device.uniform_buffer_create(size, bytes)
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	uniform.add_id(buffer_rid)
	uniform_list.append(uniform)
	return buffer_rid


func _process(_delta: float) -> void:
	calc_sizes_and_offsets()
	update_overlay()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# calc_divergence()
	if solver_enabled:
		step_solver(_delta)


func step_solver(_delta: float) -> void:
	advect_velocity(_delta)
	swap_velocities()
	_update_velocity_buffers()
	_run_packer(_delta)
	for _i in iterations:
		_run_pressure_solver()
		_get_pressure()
		pass
	update_velocities(_delta)


func _draw() -> void:
	if arrows_visible:
		for y in velocities_x.height:
			var pos_y := y * cell_size + cell_offset
			for x in velocities_x.width:
				var pos_x := x * cell_size
				draw_arrow_x(
					Vector2(pos_x, pos_y) + grid_offset,
					velocities_x.get_val(x, y),
					arrow_color,
					arrow_line_width
				)

		for y in velocities_y.height:
			var pos_y := y * cell_size
			for x in velocities_y.width:
				var pos_x := x * cell_size + cell_offset
				draw_arrow_y(
					Vector2(pos_x, pos_y) + grid_offset,
					velocities_y.get_val(x, y),
					arrow_color,
					arrow_line_width
				)
		pass
	if brush_enabled:
		draw_circle(get_local_mouse_position(), brush_radius, brush_color)
	if highlighted_velocity_state == highlighted_velocity.X:
		var pos := Vector2(highlighted_velocity_index) * cell_size
		pos.y += cell_offset
		pos += grid_offset
		draw_circle(pos, velocity_highlight_radius, velocity_highlight_color)
		pass

	if highlighted_velocity_state == highlighted_velocity.Y:
		var pos := Vector2(highlighted_velocity_index) * cell_size
		pos.x += cell_offset
		pos += grid_offset
		draw_circle(pos, velocity_highlight_radius, velocity_highlight_color)
		pass


func calc_sizes_and_offsets() -> void:
	window_size = Vector2(DisplayServer.window_get_size()) - grid_margin * 2
	var cell_scale := window_size / Vector2(grid_size)
	cell_size = min(cell_scale.x, cell_scale.y)
	cell_offset = cell_size / 2
	grid_offset = Vector2(0, 0)
	if cell_scale.x > cell_scale.y:
		grid_offset.x = (window_size.x - grid_size.x * cell_size) / 2
	else:
		grid_offset.y = (window_size.y - grid_size.y * cell_size) / 2
	grid_offset += grid_margin
	sub_cell_offset = cell_size / interpolation_subdivision


func update_overlay() -> void:
	var data := PackedVector4Array()
	data.resize(grid_size.x * grid_size.y)
	for y in grid_size.y:
		for x in grid_size.x:
			var vel := sample_velocity_at_grid_position(Vector2(x + 0.5, y + 0.5))
			data[y * grid_size.x + x] = Vector4(
				vel.x, vel.y, pressures.get_val(x, y), divergence.get_val(x, y)
			)

	overlay_node.position = grid_offset
	overlay_node.scale = grid_size * cell_size / overlay_node.texture.get_size()
	overlay_node.material.set(
		"shader_parameter/data", packed_vector4_array_to_texture(data, grid_size.x, grid_size.y)
	)


func packed_vector4_array_to_texture(
	packed_vec4_array: PackedVector4Array, width: int, height: int
) -> ImageTexture:
	var img := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBAF, packed_vec4_array.to_byte_array()
	)
	var tex := ImageTexture.create_from_image(img)
	return tex


func calc_divergence() -> void:
	for y in divergence.height:
		for x in divergence.width:
			divergence.set_val(
				x,
				y,
				(
					(velocities_x.get_val(x + 1, y) - velocities_x.get_val(x, y)) / cell_size
					+ (velocities_y.get_val(x, y) - velocities_y.get_val(x, y + 1)) / cell_size
				)
			)


func position_is_solidv(pos: Vector2) -> bool:
	var grid_pos := position_to_gridi(pos)
	if grid_pos.x < 0 || grid_pos.y < 0 || grid_pos.x >= grid_size.x || grid_pos.y >= grid_size.y:
		return false
	return solid_cells.get_val(grid_pos.x, grid_pos.y)


func is_solidv(pos: Vector2i) -> bool:
	if pos.x < 0 || pos.y < 0 || pos.x >= grid_size.x || pos.y >= grid_size.y:
		return false
	return solid_cells.get_val(pos.x, pos.y)


func is_solid_cell(x: int, y: int) -> bool:
	if x < 0 || y < 0 || x >= grid_size.x || y >= grid_size.y:
		return false
	return solid_cells.get_val(x, y)


func _pack_compute_data(delta: float) -> void:
	var K := delta / (density * cell_size)
	for y in grid_size.y:
		for x in grid_size.x:
			var is_solid: int = is_solid_cell(x, y)
			var flow_top := 1 - (is_solid | (is_solid_cell(x, y - 1) as int))
			var flow_right := 1 - (is_solid | (is_solid_cell(x + 1, y) as int))
			var flow_bottom := 1 - (is_solid | (is_solid_cell(x, y + 1) as int))
			var flow_left := 1 - (is_solid | (is_solid_cell(x - 1, y) as int))
			# 4 bit bitmask TRBL
			var packed_edge_flow: int = (
				flow_top << 0 | flow_right << 1 | flow_bottom << 2 | flow_left << 3
			)

			var velocity_top := velocities_y.get_val(x, y)  #* top
			var velocity_right := velocities_x.get_val(x + 1, y)  #* right
			var velocity_bottom := velocities_y.get_val(x, y + 1)  #* bottom
			var velocity_left := velocities_x.get_val(x, y)  #* left

			var velocity_term := 0.0
			var flow_count := flow_top + flow_right + flow_bottom + flow_left
			var delta_velocity := velocity_right - velocity_left + velocity_bottom - velocity_top
			if flow_count > 0:
				velocity_term = delta_velocity / (flow_count * K)
			packed_compute_data[y * grid_size.x + x] = Vector2(velocity_term, packed_edge_flow)

	pass


func advect_velocity(delta: float) -> void:
	var pos := Vector2()
	var pos_mid := Vector2()
	for y in velocities_x.height:
		for x in velocities_x.width:
			pos.x = x
			pos.y = y + 0.5
			pos_mid = pos - 0.5 * delta * sample_velocity_at_grid_position(pos)
			pos = pos - delta * sample_velocity_at_grid_position(pos_mid)
			velocities_x_1.set_val(x, y, sample_velocity_at_grid_position(pos).x)

	for y in velocities_y.height:
		for x in velocities_y.width:
			pos.x = x + 0.5
			pos.y = y
			pos_mid = pos - 0.5 * delta * sample_velocity_at_grid_position(pos)
			pos = pos - delta * sample_velocity_at_grid_position(pos_mid)
			velocities_y_1.set_val(x, y, sample_velocity_at_grid_position(pos).y)


func solve_pressure(_delta: float) -> void:
	for y in grid_size.y:
		for x in grid_size.x:
			# var top := 0 if is_solid_cell(x, y - 1) else 1
			# var right := 0 if is_solid_cell(x + 1, y) else 1
			# var bottom := 0 if is_solid_cell(x, y + 1) else 1
			# var left := 0 if is_solid_cell(x - 1, y) else 1
			# var fluid_count := top + right + bottom + left
			var edge_flow := int(packed_compute_data[y * grid_size.x + x].y)
			var top := (edge_flow >> 0) & 1
			var right := (edge_flow >> 1) & 1
			var bottom := (edge_flow >> 2) & 1
			var left := (edge_flow >> 3) & 1
			var fluid_count := top + right + bottom + left

			if fluid_count == 0:
				pressures.set_val(x, y, 0)
				continue
			var pressure_top := pressures.get_val(x, y - 1) * top
			var pressure_right := pressures.get_val(x + 1, y) * right
			var pressure_bottom := pressures.get_val(x, y + 1) * bottom
			var pressure_left := pressures.get_val(x - 1, y) * left

			# var velocity_top := velocities_y.get_val(x, y)  #* top
			# var velocity_right := velocities_x.get_val(x + 1, y)  #* right
			# var velocity_bottom := velocities_y.get_val(x, y + 1)  #* bottom
			# var velocity_left := velocities_x.get_val(x, y)  #* left
			#
			var pressure_sum := pressure_top + pressure_right + pressure_bottom + pressure_left
			# var delta_velocity := velocity_right - velocity_left + velocity_bottom - velocity_top
			# var pressure_new := pressure_sum / fluid_count - delta_velocity / (fluid_count * K)
			var pressure_new := (
				pressure_sum / fluid_count - packed_compute_data[y * grid_size.x + x].x
			)
			var pressure_old := pressures.get_val(x, y)
			pressures.set_val(x, y, pressure_old + (pressure_new - pressure_old) * 1.7)


func update_velocities(_delta: float) -> void:
	var K := _delta / (density * cell_size)
	for y in velocities_x.height:
		for x in velocities_x.width:
			if is_solid_cell(x - 1, y) || is_solid_cell(x, y):
				velocities_x.set_val(x, y, 0)
				continue
			velocities_x.sub_val(x, y, K * (pressures.get_val(x, y) - pressures.get_val(x - 1, y)))
	for y in velocities_y.height:
		for x in velocities_y.width:
			if is_solid_cell(x, y - 1) || is_solid_cell(x, y):
				velocities_y.set_val(x, y, 0)
				continue
			velocities_y.sub_val(x, y, K * (pressures.get_val(x, y) - pressures.get_val(x, y - 1)))


func draw_values(data: Double2DArray) -> void:
	for y in data.height:
		for x in data.width:
			var value := data.get_scaled_val(x, y)
			if is_zero_approx(value):
				continue
			var pos := cell_size * Vector2(x, y) + grid_offset
			var color := Color(maxf(0.0, value), 0, absf(minf(0.0, value)))
			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), color)
			# draw_string(
			# 	default_font,
			# 	pos + Vector2(cell_offset, cell_offset),
			# 	"%0.2f" % data.get_val(x, y),
			# 	HORIZONTAL_ALIGNMENT_CENTER,
			#
			# )


func sample_velocity_at_grid_position(pos: Vector2) -> Vector2:
	if is_solidv(pos.floor()):
		return Vector2()
	var pos_x := pos
	var pos_y := pos
	pos_x.y -= 0.5
	pos_y.x -= 0.5

	var frac_x := pos_x - pos_x.floor()
	var frac_y := pos_y - pos_y.floor()
	pos_x = pos_x.floor()
	pos_y = pos_y.floor()
	return Vector2(
		sample_bilinear(velocities_x, pos_x, frac_x), sample_bilinear(velocities_y, pos_y, frac_y)
	)


func sample_velocity_at_position(pos: Vector2) -> Vector2:
	if position_is_solidv(pos):
		return Vector2()
	pos -= grid_offset
	var pos_x := pos
	var pos_y := pos
	pos_x.y -= cell_offset
	pos_y.x -= cell_offset
	pos_x /= cell_size
	pos_y /= cell_size

	var frac_x := pos_x - pos_x.floor()
	var frac_y := pos_y - pos_y.floor()
	pos_x = pos_x.floor()
	pos_y = pos_y.floor()
	return Vector2(
		sample_bilinear(velocities_x, pos_x, frac_x), sample_bilinear(velocities_y, pos_y, frac_y)
	)


func sample_bilinear(data: Double2DArray, pos: Vector2i, frac: Vector2) -> float:
	var x := pos.x
	var y := pos.y
	var top_left := data.get_val(x, y)
	var top_right := data.get_val(x + 1, y)
	var bottom_left := data.get_val(x, y + 1)
	var bottom_right := data.get_val(x + 1, y + 1)

	var top := lerpf(top_left, top_right, frac.x)
	var bottom := lerpf(bottom_left, bottom_right, frac.x)

	return lerpf(top, bottom, frac.y)


func draw_arrow(pos: Vector2, dir: Vector2, color: Color, line_width: float) -> void:
	draw_line(pos, pos + dir, color, line_width)
	pass


func draw_arrow_x(pos: Vector2, length: float, color: Color, line_width: float) -> void:
	draw_line(pos, pos + Vector2(length, 0), color, line_width)
	pass


func draw_arrow_y(pos: Vector2, length: float, color: Color, line_width: float) -> void:
	draw_line(pos, pos + Vector2(0, length), color, line_width)


func position_to_cell(pos: Vector2) -> Vector2:
	pos -= grid_offset
	pos /= cell_size
	return pos - pos.floor()


func position_set_highlited_velocity(pos: Vector2) -> void:
	var pos_grid := position_to_gridi(pos)
	if !is_index_in_grid(pos_grid):
		highlighted_velocity_state = highlighted_velocity.NONE
		return
	var pos_cell := position_to_cell(pos)
	var vel_t_b_l_r := [pos_cell.y, 1 - pos_cell.y, pos_cell.x, 1 - pos_cell.x]
	var index := vel_t_b_l_r.find(vel_t_b_l_r.min())
	# top velocity of cell
	if index == 0:
		highlighted_velocity_state = highlighted_velocity.Y
	elif index == 1:
		highlighted_velocity_state = highlighted_velocity.Y
		pos_grid.y += 1
	elif index == 3:
		highlighted_velocity_state = highlighted_velocity.X
		pos_grid.x += 1
	else:
		highlighted_velocity_state = highlighted_velocity.X
	highlighted_velocity_index = pos_grid


func is_index_in_grid(pos: Vector2i) -> bool:
	return pos.x >= 0 && pos.x < grid_size.x && pos.y >= 0 && pos.y < grid_size.y


func position_to_gridi(pos: Vector2) -> Vector2i:
	pos -= grid_offset
	pos /= cell_size
	return pos.floor()


func position_to_grid(pos: Vector2) -> Vector2:
	pos -= grid_offset
	pos /= cell_size
	return pos


func add_to_velocities_in_radius(pos: Vector2, radius: float, vel: Vector2) -> void:
	vel = vel.normalized() * brush_intensity
	for y in velocities_y.height:
		for x in velocities_x.width:
			var vel_pos := Vector2(x, y) * cell_size + grid_offset
			if y < velocities_x.height:
				var vel_pos_x := vel_pos
				var distance := pos.distance_to(vel_pos_x)
				vel_pos_x.y += cell_offset
				if distance < radius:
					velocities_x.add_val(x, y, vel.x * radius / distance)
			if x < velocities_y.width:
				var vel_pos_y := vel_pos
				var distance := pos.distance_to(vel_pos_y)
				vel_pos_y.x += cell_offset
				if pos.distance_to(vel_pos_y) < radius:
					velocities_y.add_val(x, y, vel.y * radius / distance)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fluid_randomize"):
		self.pressures.rand(5, -5)
		self.velocities_x.rand(10, -10)
		self.velocities_y.rand(10, -10)
	if event.is_action_pressed("velocity_swap"):
		swap_velocities()
	if event.is_action_pressed("velocity_dragging"):
		dragging = true
		highlighted_velocity_dragging_start_index = highlighted_velocity_index
		var mb_event := event as InputEventMouseButton
		dragging_start_position = mb_event.position
	if event.is_action_released("velocity_dragging"):
		dragging = false

	if event.is_action_pressed("brush_toggle"):
		brush_enabled = !brush_enabled
		highlighted_velocity_state = highlighted_velocity.NONE
	if event.is_action_pressed("brush_increase"):
		brush_radius += 10
	if event.is_action_pressed("brush_decrease"):
		brush_radius -= 10
	if event.is_action_pressed("solver_step"):
		step_solver(DELTA)
	elif event.is_action_pressed("solver_toggle"):
		solver_enabled = !solver_enabled
	if event is InputEventMouseMotion:
		var mm_event := event as InputEventMouseMotion

		if dragging && !brush_enabled:
			var drag_vector := mm_event.position - dragging_start_position
			if highlighted_velocity_state == highlighted_velocity.X:
				velocities_x.set_val(
					highlighted_velocity_dragging_start_index.x,
					highlighted_velocity_dragging_start_index.y,
					drag_vector.x
				)
			if highlighted_velocity_state == highlighted_velocity.Y:
				velocities_y.set_val(
					highlighted_velocity_dragging_start_index.x,
					highlighted_velocity_dragging_start_index.y,
					drag_vector.y
				)
		if dragging && brush_enabled:
			add_to_velocities_in_radius(mm_event.position, brush_radius, mm_event.velocity)
		if mouse_position_label:
			mouse_position_label.text = ("%s" % position_to_gridi(mm_event.position))
		if divergence_label:
			var pos := position_to_gridi(mm_event.position)
			divergence_label.text = "Divergence: %1.10f" % divergence.get_val(pos.x, pos.y)
		if pressure_label:
			var pos := position_to_gridi(mm_event.position)
			pressure_label.text = "Pressure: %1.3f" % pressures.get_val(pos.x, pos.y)
		if !brush_enabled && !dragging:
			position_set_highlited_velocity(mm_event.position)
			velocity_label.text = ("Velocity %s" % sample_velocity_at_position(mm_event.position))


func overlay_selected(index: overlays) -> void:
	overlay_node.material.set("shader_parameter/overlay_type", index)
	pass


func _ceiling_div(x: int, y: int) -> int:
	@warning_ignore("integer_division")
	return (x + y - 1) / y


class Packed2dBooleanArray:
	extends RefCounted
	var width: int
	var height: int
	var data: PackedInt32Array
	const DATA_TYPE_SIZE = 32

	func _init(w: int, h: int) -> void:
		width = w
		height = h
		data = PackedInt32Array()
		data.resize(self._ceiling_div(w * h, DATA_TYPE_SIZE))

	func set_val(x: int, y: int, value: bool) -> void:
		var i := y * width + x
		var n := i % DATA_TYPE_SIZE
		i /= DATA_TYPE_SIZE
		var old_value := data[i]
		var val := value as int
		data[i] = old_value & ~(1 << n) | (val << n)

	func get_val(x: int, y: int) -> bool:
		var i := y * width + x
		var n := i % DATA_TYPE_SIZE
		i /= DATA_TYPE_SIZE
		return data[i] >> n & 1

	func to_2d_arr() -> Array[Array]:
		var arr: Array[Array]
		arr.resize(height)
		for j in height:
			arr[j].resize(width)
			for i in width:
				arr[j][i] = get_val(i, j)
		return arr

	func _ceiling_div(x: int, y: int) -> int:
		@warning_ignore("integer_division")
		return (x + y - 1) / y


class Double2DArray:
	extends RefCounted
	var width: int
	var height: int
	var data: PackedFloat64Array

	func _init(w: int, h: int) -> void:
		width = w
		height = h
		data = PackedFloat64Array()
		data.resize(w * h)

	func _find_min() -> float:
		var _min := INF
		for val in data:
			if val < _min:
				_min = val
		return _min

	func _find_max() -> float:
		var _max := -INF
		for val in data:
			if val > _max:
				_max = val
		return _max

	func get_val(x: int, y: int) -> float:
		if x < 0 || y < 0 || x >= width || y >= height:
			return 0
		return data[y * width + x]

	func get_scaled_val(x: int, y: int) -> float:
		if x < 0 || y < 0 || x >= width || y >= height:
			return 0
		var value := data[y * width + x]
		return value

	func set_val(x: int, y: int, value: float) -> void:
		data[y * width + x] = value

	func sub_val(x: int, y: int, value: float) -> void:
		data[y * width + x] = data[y * width + x] - value
		value = data[y * width + x]

	func add_val(x: int, y: int, value: float) -> void:
		data[y * width + x] += value
		value = data[y * width + x]

	func rand(max_val: float = 1.0, min_val: float = 0.0) -> void:
		for i in len(data):
			data[i] = randf() * (max_val - min_val) + min_val
