tool
extends EditorPlugin

const DOCK_NAME := "__RUNNING_WFC_DOCK"

var dock: WcfDock = null

# Root node we will search for ArrayMeshes to extract modules from.
var modules_source : Node = null
# Root node we will place found modules under.
var modules_target : Node = null

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
	
	var extracted_modules_count := 0
	
	for mesh_instance in list_top_level_mesh_instances(modules_source):
		var array_mesh : ArrayMesh = mesh_instance.mesh
		
		# Keep track of when we have 3 vertexes, so we can start a new face.
		var vertex_face_count := 0
		for vertex in array_mesh.get_faces():
			# Is this a new face?
			if vertex_face_count == 0:
				print("New face")
			print(vertex)
			
			# 3 vertices per face.
			vertex_face_count += 1
			if vertex_face_count >= 3:
				vertex_face_count = 0
		
		# For now just create a triangle.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Make it not smooth.
		st.add_smooth_group(false)
		
		st.add_vertex(Vector3(1, 0, 0))
		st.add_vertex(Vector3(0, 1, 0))
		st.add_vertex(Vector3(0, 0, 1))
		
		# Generate indices (optional)
		st.index()
		# Calculate the normals automatically.
		st.generate_normals()
		
		var result_mesh := st.commit()
		
		var result_mesh_instance := MeshInstance.new()
		result_mesh_instance.name = "Module"
		result_mesh_instance.mesh = result_mesh
		
		# Add the mesh to the tree. `set_owner` needs to happen after `add_child`
		modules_target.add_child(result_mesh_instance)
		result_mesh_instance.set_owner(modules_target.owner)
		
		extracted_modules_count += 1
	
	print("%d modules extracted from `%s`, into `%s`" % [extracted_modules_count, modules_source.name, modules_target.name])
	# Extraction done, reset the ui.
	dock.reset_source_and_target()
