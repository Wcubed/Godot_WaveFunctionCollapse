tool
extends EditorPlugin

const DOCK_NAME := "__RUNNING_WFC_DOCK"

var dock: WcfDock = null

# Root node we will search for ArrayMeshes to extract modules from.
var modules_source : Node = null
# Root node we will place found modules under.
var modules_target : Node = null

# Size of each grid cell, might be user editable later on.
var cell_size : Vector3 = Vector3(1, 1, 1)

# ---- Terminoligy ----
# Grid: the x by y by z space that everything happens on.
# Cell: one piece of the grid `cell_size` large.
# Module: A puzzle piece that occupies into one or multiple cells.
#         These are the pieces used to generate the final construction.
# Slot: A cell on the grid which can house a module.
#       This is where the modules are placed into during generation.
#       A module that occupies multiple cells will fill that many slots.

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
	
	for mesh_instance in list_top_level_mesh_instances(modules_source):
		# Dictionary of Vector3 (the cell position) -> Array[Vector3] (the cells faces)
		var cells : Dictionary = {}
		
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
					# Determine which cell this face is in.
					# TODO: be able to stretch multiple cells.
					var module_index := determine_grid_cell_indexes_of_face(face[ArrayMesh.ARRAY_VERTEX])
					
					# Normalize the vertex locations in the cell.
					for i in face[ArrayMesh.ARRAY_VERTEX].size():
						face[ArrayMesh.ARRAY_VERTEX][i] = face[ArrayMesh.ARRAY_VERTEX][i] - module_index
					
					# Add these vertices to the correct cell.
					if cells.has(module_index):
						# append the new face.
						for i in range(0, ArrayMesh.ARRAY_MAX):
							cells[module_index][i] += face[i]
					else:
						cells[module_index] = face
					
					# Get ready for the next triangle.
					# Don't use clear! as this will mess with the vertices that are now also in the cells.
					face = []
					for i in range(0, ArrayMesh.ARRAY_MAX):
						face.append([])
		
		# Create a new mesh instance for each module.
		# TODO: have modules stretch across multiple cells
		for module_index in cells.keys():
			# Turn the module array into something that the ArrayMesh will accept as input.
			var module : Array = array_mesh_input_from_generic_array(cells[module_index])
			
			# Create an ArrayMesh from the module.
			var arr_mesh := ArrayMesh.new()
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, module)
			
			# Create the MeshInstance.
			var result_mesh_instance := MeshInstance.new()
			result_mesh_instance.name = "Module"
			# Put it in the same relative location as the original module.
			result_mesh_instance.translation = module_index
			result_mesh_instance.mesh = arr_mesh
			
			# Add the mesh to the tree. `set_owner` needs to happen after `add_child`
			modules_target.add_child(result_mesh_instance)
			result_mesh_instance.set_owner(modules_target.owner)
		
		print("%d modules extracted from `%s`, into `%s`" % [cells.size(), mesh_instance.name, modules_target.name])
	
	# Extraction done, reset the ui.
	dock.reset_source_and_target()

# Takes a 3 vertex face and determines in which grid cell it is located.
# The face is an Array of 3 Vector3s, representing the 3 vertices of the face.
# TODO: If it stretches between two or three grid cells, it will return all of them.
# If it sits exactly on the border of two grid cells, it will return both.
# TODO: If a faces edge stretches accros more than 2 grid cells, the grid cells in-between will be ignored. So don't do this.
# TODO: If it can't decisively say which grid cells a face belongs to, it will return all of them.
# ! This can probably be done more efficient. But I have currently no clue how.
func determine_grid_cell_indexes_of_face(face_vertices: Array) -> Vector3:
	# First, we will find each grid cell that each vertex touches.
	var cells_per_vertex : Array = [[], [], []]
	for i in range(0, 3):
		# This is the cell that the vertex is in, if it isn't on the edge of a cell.
		var base_cell : Vector3 = (face_vertices[i] / cell_size).floor()
		var pos_in_cell : Vector3 = face_vertices[i] - base_cell
		
		cells_per_vertex[i].append(base_cell)
	
		# Check if the vertex is on a face, edge or corner.
		# Yes, each is a separate "if" statement, and not an "elif", because if we are in the corner, we need to actually add 7 possible modules.
		if pos_in_cell.x == 0.0:
			# On the x face.
			cells_per_vertex[i].append(Vector3(base_cell.x - 1, base_cell.y, base_cell.z))
		if pos_in_cell.y == 0.0:
			# On the y face.
			cells_per_vertex[i].append(Vector3(base_cell.x, base_cell.y - 1, base_cell.z))
		if pos_in_cell.z == 0.0:
			# On the z face.
			cells_per_vertex[i].append(Vector3(base_cell.x, base_cell.y, base_cell.z - 1))
		
		if pos_in_cell.x == 0.0 && pos_in_cell.y == 0.0:
			# On the xy edge.
			cells_per_vertex[i].append(Vector3(base_cell.x - 1, base_cell.y - 1, base_cell.z))
		if pos_in_cell.y == 0.0 && pos_in_cell.z == 0.0:
			# On the yz edge.
			cells_per_vertex[i].append(Vector3(base_cell.x, base_cell.y - 1, base_cell.z - 1))
		if pos_in_cell.z == 0.0 && pos_in_cell.x == 0.0:
			# On the zx edge.
			cells_per_vertex[i].append(Vector3(base_cell.x - 1, base_cell.y, base_cell.z - 1))
		
		if pos_in_cell == Vector3(0, 0, 0):
			# In the xyz corner.
			cells_per_vertex[i].append(Vector3(base_cell.x - 1, base_cell.y - 1, base_cell.z - 1))
	
	var result : Array = []
	# For now, we ignore the cases where the face can be in multiple modules at once.
	# TODO: implement those cases as well.
	for module in cells_per_vertex[0]:
		# See if this module is in both other vertices
		if cells_per_vertex[1].find(module) != -1 && cells_per_vertex[2].find(module) != -1:
			# Module is in all three vertices.
			result.append(module)
	
	if result.empty():
		# Ooh, there is no common module between all 3 vertices.
		# This means we are a module-spanning face.
		# TODO: find out exactly which modules.
		print("Can't find common modules in all 3 vertices. This is one for the TODO list.")
		return Vector3(0, 0, 0)
	
	# todo: support faces stretching accross modules.
	return result[0]

# Converts an [Array of generic Arras] of length ArrayMesh.ARRAY_MAX into something that will be accepted by the ArrayMesh.
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

