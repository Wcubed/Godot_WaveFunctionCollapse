tool
extends Spatial

# Size of each of the grid's cells.
# Should be the same for each module.
# TODO: how are we going to check that?
var _cell_size := Vector3(0, 0, 0)   setget set_cell_size, get_cell_size

# Array of Vector3 of all the cell indexes that this module spans.
# One of them will be (0, 0, 0) and the others are normalized to that.
var _module_cells : Array = []   setget set_module_cells, get_module_cells

# This modules mesh. A module should currently have only one mesh instance as child.
onready var _mesh_instance : MeshInstance = get_node("MeshInstance")   setget set_mesh_instance, get_mesh_instance

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Call after adding the node to the scene.
# module_cells should be an array of cell_indexes (Vector3)
func init(cell_size: Vector3, module_cells: Array, array_mesh: ArrayMesh):
	_cell_size = cell_size
	_module_cells = module_cells
	_mesh_instance.mesh = array_mesh
	
	# The first cell mentioned in module_cells will be our (0, 0, 0) cell. The rest will be set relative to that.
	var diff : Vector3 = _module_cells[0]
	for i in range(0, _module_cells.size()):
		_module_cells[i] -= diff

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func set_cell_size(ignored):
	assert("_cell_size should not be changed from outside the module.")

func get_cell_size():
	return _cell_size

func set_module_cells(ignored):
	assert("_module_cells should not be changed from outside the module.")

func get_module_cells():
	return _module_cells

func set_mesh_instance(ignored):
	assert("_mesh_insance should not be changed from outside the module.")

func get_mesh_instance():
	return _mesh_instance
