# Michael Burt 2024
# www.michaeljared.ca
# Join the discord for support (you can get the Discord link from my website)

@tool
extends EditorScenePostImport

# we map the extras to a dictionary (both mesh and object customs get mapped)
var node_extras_dict = {}
func _post_import(scene):
	print("Blender-Godot Pipeline: Starting the post import process.")
	
	var source := get_source_file()
	
	# capture the GLTF file that gets generated using .blend file importing
	if ".blend" in source:
		var use_hidden: bool = ProjectSettings.get_setting("application/config/use_hidden_project_data_directory")
		
		var data_folder := "godot"
		if use_hidden: data_folder = ".godot"
		
		var imported_file := "res://"+data_folder+"/imported/" + source.get_file().replace(".blend", "") + "-" + source.md5_text() + ".gltf"
		source = imported_file

	# do a direct read of the GLTF file to parse some extra stuff
	var file = FileAccess.open(source, FileAccess.READ)
	var content = file.get_as_text()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error == OK:
		parse_GLTF(json.data)
		iterate_scene(scene)
	
	scene.set_script(load("res://addons/blender_godot_pipeline/SceneInit.gd"))
	scene.set_meta("run", true)
	
	# parse scene data from the GLTF file (global properties)
	if "scenes" in json.data:
		var scenes = json.data["scenes"]
		if len(scenes) > 0 and "extras" in scenes[0]:
			var extras = scenes[0]["extras"]
			if "GodotPipelineProps" in extras:
				var gpp = extras["GodotPipelineProps"]
				scene.set("global_data", gpp)
				print("Blender-Godot Pipeline: Global data found and attached.")
	
	scene.set("gltf_path", source)
	
	print("Blender-Godot Pipeline: Post import complete.")
	
	return scene

func parse_GLTF(json):
	# go through each node and find ones which references meshes
	if "nodes" in json:
		for node in json["nodes"]:
			if "mesh" in node:
				var mesh_index = node["mesh"]
				var mesh = json["meshes"][mesh_index]
				if "extras" in mesh:
					add_extras_to_dict(node["name"], mesh["extras"])
				
			if "extras" in node:
				add_extras_to_dict(node["name"], node["extras"])

func add_extras_to_dict(node_name, extras):
	var g_node_name = node_name.replace(".", "_")
	if g_node_name not in node_extras_dict:
		node_extras_dict[g_node_name] = {}
	for extra in extras:
		node_extras_dict[g_node_name][extra] = str(extras[extra])

func iterate_scene(node):
	if node != null:
		
		if (node.name in node_extras_dict) and (node is Node3D):
			var extras = node_extras_dict[node.name]
			# ONLY FOR DEBUG
			#print("Set extras for: " + node.name)
			for key in extras:
				#print(key + "=" + extras[key])
				node.set_meta(key, extras[key])
		
	for child in node.get_children():
		iterate_scene(child)
