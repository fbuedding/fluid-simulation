class_name Grid
extends Node2D

@onready var grid_size: Vector2

@onready var cell_size: float
@onready var cell_offset: float
@export var cell_marker_radius: float = 0.0
@export var cell_marker_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var solid_cell_color: Color

@onready var solid_cells: Array[Array]

@export var line_width: float = 1.0
@export var line_color: Color = Color(0.3, 0.3, 0.3, 1.0)

@warning_ignore("SHADOWED_VARIABLE")


func set_params(grid_size: Vector2, cell_size: float, solid_cells: Array[Array]) -> void:
	self.grid_size = grid_size
	self.cell_size = cell_size
	self.solid_cells = solid_cells
	cell_offset = cell_size / 2
	pass


func _draw() -> void:
	var line_offset := line_width / 2
	_draw_solid_cells()
	for y in grid_size.y:
		var pos_y: float = y * cell_size + cell_offset
		for x in grid_size.x:
			var pos_x: float = x * cell_size + cell_offset
			draw_circle(Vector2(pos_x, pos_y), cell_marker_radius, cell_marker_color)
	for x in grid_size.x - 1:
		var pos_x := cell_size * x + line_offset + cell_size
		draw_line(
			Vector2(pos_x, 0), Vector2(pos_x, grid_size.y * cell_size), line_color, line_width
		)
	for y in grid_size.y - 1:
		var pos_y := cell_size * y + line_offset + cell_size
		draw_line(
			Vector2(0, pos_y), Vector2(grid_size.x * cell_size, pos_y), line_color, line_width
		)


func _draw_solid_cells() -> void:
	for y in grid_size.y:
		for x in grid_size.x:
			if not solid_cells[y][x]:
				continue
			var pos := cell_size * Vector2(x, y)
			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), solid_cell_color)
