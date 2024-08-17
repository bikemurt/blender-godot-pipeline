@tool
extends EditorScenePostImport

var node_extras_dict = {}

func _post_import(scene):
	print("Blender-Godot Pipeline: Starting the post import process.")
	
	var source := get_source_file()
	
	if ".blend" in source:
		var use_hidden: bool = ProjectSettings.get_setting("application/config/use_hidden_project_data_directory")
		
		var data_folder := "godot"
		if use_hidden: data_folder = ".godot"
		
		var imported_file := "res://"+data_folder+"/imported/" + source.get_file().replace(".blend", "") + "-" + source.md5_text() + ".gltf"
		source = imported_file

	var file = FileAccess.open(source, FileAccess.READ)
	var content = file.get_as_text()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error == OK:
		parseGLTF(json.data)
		iterateScene(scene)
	
	scene.set_script(load("res://addons/blender_godot_pipeline/SceneInit.gd"))
	scene.set_meta("run", true)
	
	print("Blender-Godot Pipeline: Post import complete.")
	
	return scene # Remember to return the imported scene


func parseGLTF(json):
	# go through each node and find ones which references meshes
	if "nodes" in json:
		for node in json["nodes"]:
			if "mesh" in node:
				var mesh_index = node["mesh"]
				var mesh = json["meshes"][mesh_index]
				if "extras" in mesh:
					addExtrasToDict(node["name"], mesh["extras"])
				
			if "extras" in node:
				addExtrasToDict(node["name"], node["extras"])

func addExtrasToDict(nodeName, extras):
	var gNodeName = nodeName.replace(".", "_")
	if gNodeName not in node_extras_dict:
		node_extras_dict[gNodeName] = {}
	for extra in extras:
		node_extras_dict[gNodeName][extra] = str(extras[extra])

func iterateScene(node):
	if node != null:
		
		if (node.name in node_extras_dict) and (node is Node3D):
			var extras = node_extras_dict[node.name]
			#print("Set extras for: " + node.name)
			for key in extras:
				#print(key + "=" + extras[key])
				node.set_meta(key, extras[key])
		
	for child in node.get_children():
		iterateScene(child)
