tool
extends EditorPlugin

# The name we give the plugin dock, so we can find it again.
const DOCK_NAME := "__RUNNING_WFC_DOCK"
# Epsilon used to compare floats.
const FLOAT_EPSILON = 0.00001

var dock: WcfDock = null

# Root node we will search for ArrayMeshes to extract modules from.
var modules_source : Node = null
# Root node we will place found modules under.
var modules_target : Node = null

# Size of each grid cell, might be user editable later on.
var cell_size : Vector3 = Vector3(1, 1, 1)

var module_scene : PackedScene = preload("./module.tscn")

# ---- Terminoligy ----
# Grid: the x by y by z space that everything happens on.
# Cell: one piece of the grid `cell_size` large.
# Module: A puzzle piece that occupies into one or multiple cells.
#         These are the pieces used to generate the final construction.
# Slot: A cell on the grid which can house a module.
#       This is where the modules are placed into during generation.
#       A module that occupies multiple cells will fill that many slots.

# TODO: do we want an "undo" functionality? See Godo's `UndoRedo` documentation.

func _enter_tree():
	print("Wave function collaps plugin loaded")
	
	# Add our custom dock to the right-hand panel.
	dock = preload("./ui/wfc_dock.tscn").instance()
	# Set the name to something that can't be mistaken for something else.
	# If we used the default name, we could confuse our active dock and
	# the scene open in the editor.
	dock.name = DOCK_NAME
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Get the TabContainer of this panel.
	var tab_container = dock.get_parent()
	
	# Find the docks tab number, set the title, and focus on it.
	for i in range(0, tab_container.get_child_count()):
		if tab_container.get_children()[i] == dock:
			tab_container.set_tab_title(i, "WFC")
			tab_container.current_tab = i
			break
	
	connect("scene_changed", self, "_on_scene_changed")
	
	# Reload the plugin when the button is pressed.
	dock.connect("reload_button_pressed", self, "_on_reload_button_pressed")
	
	# Connect the other dock events.
	dock.connect("select_modules_source_pressed", self, "_on_select_modules_source")
	dock.connect("select_modules_target_pressed", self, "_on_select_modules_target")
	dock.connect("extract_modules_pressed", self, "extract_modules")


func _exit_tree():
	# Clean up the dock.
	if dock == null:
		# We somehow lost our dock. Possibly due to a script update while we were running.
		# See if we can find it.
		var previous_dock = get_tree().get_root().find_node(DOCK_NAME + "*", true, false)
		if previous_dock != null:
			dock = previous_dock
		else:
			# Dock is not there. Nothing to do.
			return
	remove_control_from_docks(dock)
	dock.queue_free()


func _on_scene_changed(scene: SceneTree):
	# When the scene changes, the selected source and target nodes are no longer valid.
	modules_source = null
	modules_target = null
	
	dock.reset_source_and_target()

# Reloads this plugin.
func reload_plugin():
	var editor_interface := get_editor_interface()
	editor_interface.set_plugin_enabled("wave_function_collapse_plugin", false)
	editor_interface.set_plugin_enabled("wave_function_collapse_plugin", true)


func _on_reload_button_pressed():
	call_deferred("reload_plugin")


# Get's the current selected node, and sets it as the modules source root.
func _on_select_modules_source():
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	
	if selection.size() == 0:
		# Nothing selected.
		return
	
	# Use the first as the target.
	modules_source = selection[0]
	var mesh_count := list_top_level_mesh_instances(modules_source).size()
	
	# Update the interface.
	dock.set_modules_source_name(modules_source.get_name())
	var status := is_modules_source_ok(modules_source)
	dock.set_modules_source_status(status[1], status[0])


# Get's the current selected node, and sets it as the modules target.
func _on_select_modules_target():
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	if selection.size() == 0:
		# Nothing selected.
		return
	
	# Use the first as the target.
	modules_target = selection[0]
	
	# Update the interface.
	dock.set_modules_target_name(modules_target.get_name())
	var status := is_modules_target_ok(modules_target)
	dock.set_modules_target_status(status[1], status[0])

# ---- Wave function collapse related stuff ----

# Checks if the given modules source is good to go.
# Returns an array: [ok?: bool, human_readable_result: String]
func is_modules_source_ok(root: Node) -> Array:
	if root == null:
		return [false, "Node not found"]
	
	# Can we find ArrayMeshes?
	var mesh_count := list_top_level_mesh_instances(modules_source).size()
	
	if mesh_count == 0:
		# Can't get modules if there are no meshes.
		return [false, "No top level MeshInstances with ArrayMeshes found"]
	elif mesh_count == 1:
		return [true, "1 MeshInstance found"]
	else:
		return [true, "%d MeshInstances found" % mesh_count]


# Checks if the given modules targetis good to go.
# Returns an array: [ok?: bool, human_readable_result: String]
func is_modules_target_ok(root: Node) -> Array:
	if root == null:
		return [false, "Node not found"]

	# Is target an Spatial node with 0 children?
	if modules_target.get_class() != "Spatial" || modules_target.get_children().size() != 0:
		return [false, "Target should be a Spatial node with 0 children"]
	else:
		return [true, "Target ok"]


# Takes a root node, returns all the MeshInstance nodes that are direct children.
# Only inclues MeshInstance nodes that use an ArrayMesh
func list_top_level_mesh_instances(root: Node) -> Array:
	var result := []
	
	for node in root.get_children():
		if node.get_class() == "MeshInstance":
			if node.mesh.get_class() == "ArrayMesh":
				result.append(node)
	
	return result


func extract_modules():
	# First check if source and target nodes are still alright.
	var source_status := is_modules_source_ok(modules_source)
	var target_status := is_modules_target_ok(modules_target)
	dock.set_modules_source_status(source_status[1], source_status[0])
	dock.set_modules_target_status(target_status[1], target_status[0])
	
	# Are both still ok?
	if !source_status[0] || !target_status[1]:
		return
	
	# Go through all the mesh instances we can find.
	for mesh_instance in list_top_level_mesh_instances(modules_source):
		# Dictionary mapping cell_coordinate (Vector3) to ArrayMesh data.
		# Dictionary(key: Vector3, Value: Array["length of ArrayMesh arrays (ArrayMesh.ARRAY_MAX)"])
		# Each face is only in one of the cells here. They have to be assembled into modules using the `connected_cells` dictionary.
		var cells : Dictionary = {}
		# When a face overlaps two cells those cells connect to form a larger module.
		# This maps cell coordinates (Vector3) to the coordinates of all the cells they overlap with (Vector3).
		# If a cell has no overlapping faces with other cells, it won't be in here.
		var connected_cells : Dictionary = {}
		
		var array_mesh : ArrayMesh = mesh_instance.mesh
		
		# Keep track of the 3 vertexes that make up each face.
		# We need to fit all the different parameters in this array, not only the vertex coordinates.
		var face : Array = []
		for i in range(0, ArrayMesh.ARRAY_MAX):
			face.append([])
		
		# Go through all the surfaces.
		# Sort all the vertexes into faces.
		# Then sort every face into the module it belongs into.
		# This algorithm assumes the ArrayMesh is using an ARRAY_INDEX array.
		for surface_idx in range(0, array_mesh.get_surface_count()):
			# Get the arrays of this surface.
			var surface_arrays := array_mesh.surface_get_arrays(surface_idx)
			
			# Go through all the vertices in the order indicated by the index array.
			for vertex_idx in surface_arrays[ArrayMesh.ARRAY_INDEX]:
				# Get all the different parameters for this vertex. Except the vertex_index.
				# The index is the last array in the list of arrays. Hence, the `size()-1`.
				for i in range(0, face.size()-1):
					# Some of the parameters might not be there, ignore those.
					if surface_arrays[i]:
						if not surface_arrays[i].empty():
							if i == ArrayMesh.ARRAY_TANGENT || i == ArrayMesh.ARRAY_BONES || i == ArrayMesh.ARRAY_WEIGHTS:
								# These parameters have 4 items per vertex.
								for j in range(0, 4):
									face[i].append(surface_arrays[i][(vertex_idx * 4) + j])
							else:
								# The rest of the parameters have 1 item per vertex.
								face[i].append(surface_arrays[i][vertex_idx])
				
				# Check if we have enough vertices for a triangle.
				if face[ArrayMesh.ARRAY_VERTEX].size() == 3:
					# We have a triangle.
					# Determine which cells this face is in.
					var face_cells : Array = determine_grid_cell_indexes_of_face(face[ArrayMesh.ARRAY_VERTEX])
					
					# If there are no cells listed, the face is exactly on the edge of cells and we ignore it.
					if !face_cells.empty():
						# We only want to add the vertices to one cell, so it is easier to assemble the modules later.
						var primary_cell_index : Vector3 = face_cells[0]
						
						# Normalize the vertex locations in the cell.
						for i in face[ArrayMesh.ARRAY_VERTEX].size():
							face[ArrayMesh.ARRAY_VERTEX][i] = face[ArrayMesh.ARRAY_VERTEX][i] - primary_cell_index
						
						# Add these vertices to the correct cell.
						if cells.has(primary_cell_index):
							# append the new face.
							for i in range(0, ArrayMesh.ARRAY_MAX):
								cells[primary_cell_index][i] += face[i]
						else:
							cells[primary_cell_index] = face
						
						# Is this cell connected to other cells?
						if face_cells.size() > 1:
							# We link the connection both ways.
							# so cell -> Other_cell and other_cell -> cell
							for i in range(0, face_cells.size()):
								var cell : Vector3 = face_cells[i]
								for j in range(i + 1, face_cells.size()):
									var other_cell : Vector3 = face_cells[j]
									
									# Add the connection cell -> other_cell.
									if connected_cells.has(cell):
										# Only add the connection once.
										if connected_cells[cell].find(other_cell) == -1:
											connected_cells[cell].append(other_cell)
									else:
										connected_cells[cell] = [other_cell]
									
									# Add the connection other_cell -> cell
									if connected_cells.has(other_cell):
										# Only add the connection once.
										if connected_cells[other_cell].find(cell) == -1:
											connected_cells[other_cell].append(cell)
									else:
										connected_cells[other_cell] = [cell]
							
					# Get ready for the next triangle.
					# Don't use clear! as this will mess with the vertices that are now also in the cells.
					face = []
					for i in range(0, ArrayMesh.ARRAY_MAX):
						face.append([])
		
		# We now know in which cell each surface is, and which surfaces are connected.
		# Now we need to assemble each set of connected cells into a coherent module.
		
		# Dictionary of cell indexes to ArrayMesh arrays.
		# The cell index in here is the main cell index of that module.
		# Which cells this module is also in can be found in `connected_modules`.
		var modules : Dictionary = {}
		for cell_index in cells.keys():
			if connected_cells.has(cell_index):
				# This is a connected cell.
				# Check if one of the connections is already in the module dictionary.
				var added_to_other := false
				for other_index in connected_cells[cell_index]:
					if modules.has(other_index):
						added_to_other = true
						# One of our connections is already in the list. We append all our arrays to that.
						for i in range(0, ArrayMesh.ARRAY_MAX):
							var array : Array = cells[cell_index][i]
							
							if i == ArrayMesh.ARRAY_VERTEX:
								# If we are adding vertices, we need to re-base the vertex location.
								# Because currently, it has (0, 0, 0) as the start of it's own cell, but now (0, 0, 0) will be the start of the other cell.
								for j in range(0, array.size()):
									var diff : Vector3 = other_index - cell_index
									array[j] = array[j] - diff
							
							modules[other_index][i] += array
						break
				
				if !added_to_other:
					# There was no other cell we could add this one to.
					# So add it by itself.
					modules[cell_index] = cells[cell_index]
			else:
				# This cell is not connected to any other cell.
				# So it is it's own module.
				modules[cell_index] = cells[cell_index]
		
		# Create a new module instance for each module.
		for module_index in modules.keys():
			# Turn the module array into something that the ArrayMesh will accept as input.
			var module : Array = array_mesh_input_from_generic_array(modules[module_index])
			
			# Create an ArrayMesh from the module.
			var arr_mesh := ArrayMesh.new()
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, module)
			
			# Create the Module scene.
			var module_node := module_scene.instance()
			module_node.name = "Module"
			# Put it in the same relative location as the original module.
			module_node.translation = module_index
			
			var module_cells := [module_index]
			# Are there connected cells?
			if connected_cells.has(module_index):
				module_cells += connected_cells[module_index]
			
			# Add the Module to the tree. `set_owner` needs to happen after `add_child`
			modules_target.add_child(module_node)
			module_node.set_owner(modules_target.owner)
			
			# Initialize the Module with the required data.
			module_node.init(cell_size, module_cells, arr_mesh)
		
		print("%d modules extracted from `%s`, into `%s`" % [modules.size(), mesh_instance.name, modules_target.name])
	
	# Extraction done, reset the ui.
	dock.reset_source_and_target()

# Takes a 3 vertex face and determines in which grid cell it is located.
# The face is an Array of 3 Vector3s, representing the 3 vertices of the face.
# It returns an Array of 1 or more Vector3s, representing which grid cells this face is in.
# The only two cases it does not like:
# 1. A face is completely on a face, edge or corner of a cell, in that case it returns an empty array.
# 2. A face is so large that there are cells in the middle that the edges do not go through:
#    In that case the middle cells are not returned.
func determine_grid_cell_indexes_of_face(face_vertices: Array) -> Array:
	var cells := []
	# Take steps of a fraction of a cells diagonal length.
	var step_size := cell_size.length() * 0.1
	
	# Analyze all 3 lines.
	for i in range(0, face_vertices.size()):
		var line_begin : Vector3 = face_vertices[i]
		var line_end : Vector3 = face_vertices[(i + 1) % face_vertices.size()]
		
		# ALways step along the line from small to large.
		# If that would not be the case, swap the points so it is.
		if line_begin > line_end:
			var temp = line_begin
			line_begin = line_end
			line_end = temp
		
		var direction := line_begin.direction_to(line_end)
		var step := direction * step_size
		
		var current_pos := line_begin
		
		# Step along the line, and find each cell it goes through.
		while current_pos <= line_end:
			var cell := (current_pos / cell_size).floor()
			var pos_in_cell = current_pos - cell
			
			# Are we between two or more cells?
			if f_equals(pos_in_cell.x, 0) || f_equals(pos_in_cell.y, 0) || f_equals(pos_in_cell.z, 0) || f_equals(pos_in_cell.x, cell_size.x) || f_equals(pos_in_cell.y, cell_size.y) || f_equals(pos_in_cell.z, cell_size.z):
				# We don't know which of the cells to pick, so continue.
				pass
			else:
				# We are in a single cell, add it.
				# Only add cells once.
				if cells.find(cell) == -1:
					cells.append(cell)
			
			# Next step along the line.
			current_pos += step
	
	return cells


# Converts an [Array of generic Arrays] of length ArrayMesh.ARRAY_MAX into something that will be accepted by the ArrayMesh.
func array_mesh_input_from_generic_array(array: Array) -> Array:
	if array.size() < ArrayMesh.ARRAY_MAX:
		# Not enough info, can't do anything logical here.
		return []
	
	var result : Array = []
	result.resize(ArrayMesh.ARRAY_MAX)
	
	# Only fill the index if there is data. Otherwise we need to leave it null.
	for i in range(0, ArrayMesh.ARRAY_MAX):
		if !array[i].empty():
			# there are different types of data in each slot.
			# See the ArrayMesh documentation on why the array looks like this.
			if i == ArrayMesh.ARRAY_VERTEX || i == ArrayMesh.ARRAY_NORMAL:
				result[i] = PoolVector3Array(array[i])
			elif i == ArrayMesh.ARRAY_TANGENT || i == ArrayMesh.ARRAY_BONES || i == ArrayMesh.ARRAY_WEIGHTS:
				result[i] = PoolRealArray(array[i])
			elif i == ArrayMesh.ARRAY_COLOR:
				result[i] = PoolColorArray(array[i])
			elif i == ArrayMesh.ARRAY_TEX_UV || i == ArrayMesh.ARRAY_TEX_UV2:
				result[i] = PoolVector2Array(array[i])
			elif i == ArrayMesh.ARRAY_INDEx:
				result[i] = PoolIntArray(array[i])
	return result

# Compares two floats for approximate equality.
static func f_equals(a, b, epsilon = FLOAT_EPSILON):
	return abs(a - b) <= epsilon
