tool
extends EditorPlugin

const DOCK_NAME := "__RUNNING_WFC_DOCK"

var dock: WcfDock = null

# Root node we will search for ArrayMeshes to extract modules from.
var modules_source : Node = null
# Root node we will place found modules under.
var modules_target : Node = null

# Size of each module, might be user editable later on.
var module_size : Vector3 = Vector3(1, 1, 1)

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
	
	# Dictionary of Vector3 (the module position) -> Array[Vector3] (the modules faces)
	var modules : Dictionary = {}
	
	for mesh_instance in list_top_level_mesh_instances(modules_source):
		var array_mesh : ArrayMesh = mesh_instance.mesh
		
		# Keep track of the 3 vertexes that make up each face.
		var face : Array = []
		
		for vertex in array_mesh.get_faces():
			face.append(vertex)
			if face.size() == 3:
				# We have a triangle.
				# Determine which module this face is in.
				# TODO: be able to stretch multiple modules.
				var module_index := determine_module_indexes_of_face(face)
				if modules.has(module_index):
					# append the new face.
					modules[module_index] += face
				else:
					modules[module_index] = face
				
				# Get ready for the next triangle.
				face.clear()
		
		# TODO: Add the sorted faces to surface tools for each module.
		print(modules)
		
		# Create a new mesh instance for each module.
		for module_index in modules.keys():
			var module : Array = modules[module_index]
			
			# Create an ArrayMesh from the module.
			var arr_mesh := ArrayMesh.new()
			var arrays := []
			arrays.resize(ArrayMesh.ARRAY_MAX)
			arrays[ArrayMesh.ARRAY_VERTEX] = module
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			
			var result_mesh_instance := MeshInstance.new()
			result_mesh_instance.name = "Module"
			result_mesh_instance.mesh = arr_mesh
			
			# Add the mesh to the tree. `set_owner` needs to happen after `add_child`
			modules_target.add_child(result_mesh_instance)
			result_mesh_instance.set_owner(modules_target.owner)
	
	print("%d modules extracted from `%s`, into `%s`" % [modules.size(), modules_source.name, modules_target.name])
	# Extraction done, reset the ui.
	dock.reset_source_and_target()


# Implementation of: v1 % v2
func vector3_modulo(v1: Vector3, v2: Vector3) -> Vector3:
	return Vector3(fmod(v1.x, v2.x), fmod(v1.y, v2.y), fmod(v1.z, v2.z))

# Takes a face and determines in which modules it is located.
# TODO: If it stretches between two or three modules, it will return all of them.
# If it sits exactly on the border of two modules, it will return both.
# TODO: If a faces edge stretches accros more than 2 modules, the modules in-between will be ignored. So don't do this.
# TODO: It also doesn't like a face with 1 vertex between multiple modules, and the other 2 vertices in neither of those modules. So don't do that.
# ! This can probably be done more efficient. But I have currently no clue how.
func determine_module_indexes_of_face(face: Array) -> Vector3:
	# First, get each module that a vertex can be in.
	var modules_per_vertex : Array = [[], [], []]
	for i in range(0, 3):
		# This is the module that the vertex is in, if it isn't on the edge of a module.
		var base_module : Vector3 = (face[i] / module_size).floor()
		var pos_in_module : Vector3 = vector3_modulo(face[i], module_size)
		
		modules_per_vertex[i].append(base_module)
		
		# Check if the vertex is on a face, edge or corner.
		# Yes, each is a separate case, because if we are in the corner, we need to actually add 7 possible modules.
		if pos_in_module.x == 0.0:
			# On the x face.
			modules_per_vertex[i].append(Vector3(base_module.x - 1, base_module.y, base_module.z))
		if pos_in_module.y == 0.0:
			# On the y face.
			modules_per_vertex[i].append(Vector3(base_module.x, base_module.y - 1, base_module.z))
		if pos_in_module.z == 0.0:
			# On the z face.
			modules_per_vertex[i].append(Vector3(base_module.x, base_module.y, base_module.z - 1))
		
		if pos_in_module.x == 0.0 && pos_in_module.y == 0.0:
			# On the xy edge.
			modules_per_vertex[i].append(Vector3(base_module.x - 1, base_module.y - 1, base_module.z))
		if pos_in_module.y == 0.0 && pos_in_module.z == 0.0:
			# On the yz edge.
			modules_per_vertex[i].append(Vector3(base_module.x, base_module.y - 1, base_module.z - 1))
		if pos_in_module.z == 0.0 && pos_in_module.x == 0.0:
			# On the zx edge.
			modules_per_vertex[i].append(Vector3(base_module.x - 1, base_module.y, base_module.z - 1))
		
		if pos_in_module == Vector3(0, 0, 0):
			# In the xyz corner.
			modules_per_vertex[i].append(Vector3(base_module.x - 1, base_module.y - 1, base_module.z - 1))
	
	var result : Array = []
	# For now, we ignore the cases where the face can be in multiple modules at once.
	# TODO: implement those cases as well.
	for module in modules_per_vertex[0]:
		# See if this module is in both other vertices
		if modules_per_vertex[1].find(module) != -1 && modules_per_vertex[2].find(module) != -1:
			# Module is in all three vertices.
			result.append(module)
	
	# todo: support faces stretching accross modules.
	return result[0]
