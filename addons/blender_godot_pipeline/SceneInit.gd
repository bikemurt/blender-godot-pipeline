# Michael Burt 2024
# www.michaeljared.ca
# Join the discord for support (you can get the Discord link from my website)

@tool
extends Node3D

## Remove the originally imported
## GLTF node from your scene. This should be done when the design of a 
## level is complete. Doing this disables "hot reload",
## so if you make further changes to your scene in Blender, you need to delete the
## _Imported node from the scene tree, re-import the GLTF file, and drag it 
## into the scene tree.
@export var disable_hot_reload := false:
	get: return disable_hot_reload
	set(value):
		if value and Engine.is_editor_hint():
			queue_free()

@export var global_data = {}
@export var gltf_path: String = ""

func check_global_flag(key: String) -> bool:
	return key in global_data and global_data[key] == 1

var addon_root := "res://addons/blender_godot_pipeline/"

var reparent_nodes = []
var delete_nodes = []
var multimesh_dict = {}

var duplicate_scene: Node

func debug_msg(msg: String, time := 1.0) -> void:
	await get_tree().create_timer(time).timeout
	print(msg)
	pass

func run_setup() -> void:
	if Engine.is_editor_hint():
		if get_meta("run"):
			
			DirAccess.make_dir_absolute(gltf_path.get_base_dir() + "/packed_scenes")
			print("Blender-Godot Pipeline: Running SceneInit - processing the scene.")
			
			#await get_tree().create_timer(2.0).timeout
			
			duplicate_all()
			
			#await get_tree().create_timer(2.0).timeout
			
			remove_skips(duplicate_scene)
			
			iterate_scene(duplicate_scene)
			
			process_multimeshes(duplicate_scene)
			
			reparent_pass()
			delete_pass()
			
			# SECOND PASS - process materials
			iterate_scene_pass2(duplicate_scene)
			
			# these timers feel so hacky, but not sure how else to remedy this
			await get_tree().create_timer(0.2).timeout
			
			# parse globals on top level only
			parse_globals(duplicate_scene)
			
			# ensure that SceneInit only runs once
			set_meta("run", false)
			
			hide()
			
			print("Blender-Godot Pipeline: Scene processing complete. ")
		
			EditorInterface.get_resource_filesystem().scan()

func _ready():
	run_setup()

func duplicate_all() -> void:
	duplicate_scene = duplicate()
	duplicate_scene.show()
	
	duplicate_scene.set_script(null)
	
	# check if duplicate already exists
	var new_name := name + "_Imported"
	var delete_node: Node = null
	for c in get_parent().get_children():
		if c.name == new_name:
			delete_node = c
	
	if delete_node:
		get_parent().remove_child(delete_node)
		delete_node.queue_free()
	
	# "Make Local" programmatically
	duplicate_scene.scene_file_path = ""
	duplicate_scene.name = new_name
	
	get_parent().add_child(duplicate_scene)
	duplicate_scene.owner = get_tree().edited_scene_root

###

func reparent_pass():
	for node in reparent_nodes:
		node[0].reparent(node[1], true)
		node[0].set_owner(get_tree().edited_scene_root)
		
		# this recursively finds all of the children of node[0]
		# and sets their scene_root
		set_children_scene_root(node[0])
		
func delete_pass():
	for node in delete_nodes:
		node.queue_free()

func set_children_scene_root(node):
	for child in node.get_children():
		set_children_scene_root(child)
		child.owner = get_tree().edited_scene_root

func set_children_to_parent(node, parent_to):
	for child in node.get_children():
		set_children_to_parent(node, parent_to)
		child.owner = parent_to

func _set_script_params(node:Node, script_filepath):
	var script_file = FileAccess.open(script_filepath, FileAccess.READ)

	while not script_file.eof_reached():
		var line = script_file.get_line()
		if line != "":
			_eval_params_line(node, line)

func _set_script_params_str(node:Node, string:String):
	var lines = string.split(";")
	for line in lines:
		_eval_params_line(node, line)

func _eval_params_line(node:Node, line:String):
	var components = line.split('=')
	if len(components) > 1:
		var param_name = components[0].strip_edges()
		var expression = components[1].strip_edges()

		var e = Expression.new()
		e.parse(expression, ['node'])
		var x = e.execute([node])
		if e.has_execute_failed():
			printerr("Execution Error on line '",line ,": ",e.get_error_text())
		node.set(param_name, x)
		
		# debug?
		#print(param_name,expression,e,x, node.get(param_name))
	else:
		var e = Expression.new()
		e.parse(line, ['node'])
		var x = e.execute([node])
		print(line,e,x, node)
		if e.has_execute_failed():
			printerr("Execution Error on line '",line ,": ",e.get_error_text())


func _material(node, metas, meta, meta_val):
	var surface_split = meta.split("_")
	if len(surface_split) > 0:
		var surface = surface_split[1]
		var material = load(meta_val)
		
		if "shader" in metas:
			var shader = load(node.get_meta("shader"))
			material.set_shader(shader)
		
		node.set_surface_override_material(int(surface), material)

# COLLLISIONS
func collision_script(body, node, metas) -> void:
	if "script" in metas:
		body.set_script(load(node.get_meta("script")))
	
	if "prop_file" in metas:
		# collision handled separately
		_set_script_params(body, node.get_meta("prop_file"))

	if "prop_string" in metas:
		_set_script_params_str(body, node.get_meta("prop_string"))
	
	if "physics_mat" in metas:
		if body is StaticBody3D or body is RigidBody3D:
			body.physics_material_override = load(node.get_meta("physics_mat"))

# updated collision logic oct 7, 2024
func _collisions(node, meta_val, metas):
	var t = node.transform
	var body = StaticBody3D.new()
	body.name = "StaticBody3D_" + node.name
	
	if "-r" in meta_val:
		body = RigidBody3D.new()
		body.name = "RigidBody3D_" + node.name
	
	if "-a" in meta_val:
		body = Area3D.new()
		body.name = "Area3D_" + node.name
	
	if "-m" in meta_val:
		body = AnimatableBody3D.new()
		body.name = "AnimatableBody3D_" + node.name
	
	if "-h" in meta_val:
		body = CharacterBody3D.new()
		body.name = "CharacterBody3D_" + node.name
	
	# --- NEW --- migrating simple/trimesh into primitive function
	
	var simple: bool = "simple" in meta_val
	var trimesh: bool = "trimesh" in meta_val
	
	# try to generate trimesh (concave) or simple (convex) collisions
	var trimesh_shape := ConcavePolygonShape3D.new()
	var simple_shape := ConvexPolygonShape3D.new()
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node
		if simple:
			var dummy_mesh := mesh_inst.duplicate()
			dummy_mesh.create_convex_collision()
			var col_shape_3d: CollisionShape3D = dummy_mesh.get_children()[0].get_children()[0]
			simple_shape = col_shape_3d.shape.duplicate()
		if trimesh:
			var dummy_mesh := mesh_inst.duplicate()
			dummy_mesh.create_trimesh_collision()
			var col_shape_3d: CollisionShape3D = dummy_mesh.get_children()[0].get_children()[0]
			trimesh_shape = col_shape_3d.shape.duplicate()
	
	# ---
	
	var col_only = "-c" in meta_val
	
	body.position = node.position
	
	var discard_mesh = "-d" in meta_val
	var nd: Node3D = node.duplicate()
	if not discard_mesh:
		# clear all children
		var children = []
		for child in nd.get_children():
			children.append(child)
		for child in children:
			nd.remove_child(child)
	
		nd.transform = Transform3D()
		nd.scale = node.scale
		nd.rotation = node.rotation
		
		body.add_child(nd)
	
	# only create a collision if not bodyonly
	var cs = CollisionShape3D.new()
	if "bodyonly" not in meta_val:
		cs.name = "CollisionShape3D_" + node.name
		
		if col_only:
			# here we capture position too because
			# these will be parented to a body
			# and we want to get the relative position
			cs.position = node.position
		
		cs.scale = node.scale
		cs.rotation = node.rotation
		
		if "box" in meta_val:
			if "size_x" in metas and "size_x" in metas \
			and "size_z" in metas:
				var bx = BoxShape3D.new()
				
				var size_x = float(node.get_meta("size_x"))
				var size_y = float(node.get_meta("size_y"))
				var size_z = float(node.get_meta("size_z"))
				
				bx.size = Vector3(size_x, size_y, size_z)
				
				cs.shape = bx
		
		if "cylinder" in meta_val:
			if "height" in metas and "radius" in metas:
				var cyl = CylinderShape3D.new()
				
				var height = float(node.get_meta("height"))
				var radius = float(node.get_meta("radius"))
				
				cyl.height = height
				cyl.radius = radius
				
				cs.shape = cyl
		
		if "sphere" in meta_val:
			if "radius" in metas:
				var sph = SphereShape3D.new()
				
				var radius = float(node.get_meta("radius"))
				
				sph.radius = radius
				
				cs.shape = sph
		
		if "capsule" in meta_val:
			if "height" in metas and "radius" in metas:
				var cap = CapsuleShape3D.new()
				
				var height = float(node.get_meta("height"))
				var radius = float(node.get_meta("radius"))
				
				cap.height = height
				cap.radius = radius
				
				cs.shape = cap
		
		if trimesh: cs.shape = trimesh_shape
		if simple: cs.shape = simple_shape
		
		if col_only:
			# collision gets added to the node parent mesh
			node.get_parent().add_child(cs)
			
		else:
			# otherwise add it to the body
			body.add_child(cs)
	
	if not col_only:
		node.get_parent().add_child(body)
		#body.owner = node
		body.owner = get_tree().edited_scene_root
		
		if not discard_mesh: nd.owner = get_tree().edited_scene_root
	
	cs.owner = get_tree().edited_scene_root
	
	# check for any collisions children, reparent to body
	for child in node.get_children():
		if not col_only:
			if child is CollisionShape3D:
				reparent_nodes.append([child, body])
	
	delete_nodes.append(node)
	
	collision_script(body, node, metas)

# NAV MESH
func _nav_mesh(node, meta, meta_val) -> void:
	var mesh_inst: MeshInstance3D = node
	ResourceSaver.save(mesh_inst.mesh, meta_val)
	
	var n := NavigationMesh.new()
	
	mesh_inst.mesh.resource_name = mesh_inst.name + "_NavMesh"
	n.create_from_mesh(mesh_inst.mesh)
	
	var nr := NavigationRegion3D.new()
	nr.navigation_mesh = n
	nr.transform = mesh_inst.transform
	nr.name = mesh_inst.name + "_NavMesh"
	_set_script_params(nr, node.get_meta("prop_file"))
	
	mesh_inst.get_parent().add_child(nr)
	nr.owner = get_tree().edited_scene_root
	
	delete_nodes.append(mesh_inst)

# MULTIMESH
func _multimesh_new(node, meta, meta_val) -> void:
	if meta_val not in multimesh_dict:
		multimesh_dict[meta_val] = []
		var mi: MeshInstance3D = node
		var mi_mesh: Resource = mi.mesh
		
		mi_mesh.resource_name = node.name
		ResourceSaver.save(mi_mesh, meta_val)
		mi_mesh.take_over_path(meta_val)
		#mi.mesh.resource_name = node.name
		
	multimesh_dict[meta_val].push_back(node.transform)
	
	delete_nodes.push_back(node)

func process_multimeshes(parent: Node) -> void:
	for mm in multimesh_dict:
		
		var mm_i = MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		
		var size = len(multimesh_dict[mm])
		multimesh.instance_count = size
		
		var i := 0
		for loc in multimesh_dict[mm]:
			multimesh.set_instance_transform(i, loc)
			i += 1
		
		multimesh.mesh = ResourceLoader.load(mm)
		
		mm_i.multimesh = multimesh
		mm_i.name = multimesh.mesh.resource_name + "_Multimesh"
		
		parent.add_child(mm_i)
		mm_i.owner = get_tree().edited_scene_root

func _set_script(node, metas, meta, meta_val) -> void:
	if "collision" not in metas:
		node.set_script(load(meta_val))

func remove_skips(node):
	var n: Node3D
	for child in node.get_children():
		if "state" in child.get_meta_list():
			if child.get_meta("state") == "skip":
				child.queue_free()
			else:
				remove_skips(child)

func iterate_scene(node):
	for child in node.get_children():
		iterate_scene(child)

	# after this point, all children have been parsed (or don't exist)
	# update - we should be able to parse all Node3Ds.. right?
	node.owner = get_tree().edited_scene_root
	if node is Node:
		
		var metas = node.get_meta_list()
		for meta in metas:
			
			var meta_val = node.get_meta(meta)
			
			if meta == "state":
				if meta_val == "hide":
					node.hide()
					
			# PARSE NAME OVERRIDE FIRST
			if "name_override" in metas:
				if node.get_meta("name_override") != "":
					node.name = node.get_meta("name_override")
			
			# 2024-05-09 I don't even know what this was for anymore
			if "group" in meta:
				# TBD
				pass
			
			if meta == "script":
				_set_script(node, metas, meta, meta_val)
			
			if meta == "prop_file":
				# collision handled separately. good reasons for this
				if "collision" not in metas and "nav_mesh" not in metas:
					_set_script_params(node, meta_val)

			if meta == "prop_string":
				if "collision" not in metas and "nav_mesh" not in metas:
					_set_script_params_str(node, meta_val)
			
			# collision logic updated again oct 7, 2024
			if meta == "collision":
				_collisions(node, meta_val, metas)
			
			if meta == "nav_mesh":
				_nav_mesh(node, meta, meta_val)
				
			if meta == "multimesh":
				_multimesh_new(node, meta, meta_val)
			
			if meta == "packed_scene":
				await get_tree().create_timer(0.1).timeout
				var packed_scene = load(meta_val).instantiate()
				packed_scene.name = "PackedScene_" + node.name
				node.get_parent().add_child(packed_scene)
				packed_scene.global_transform = node.global_transform
				packed_scene.owner = get_tree().edited_scene_root
				delete_nodes.push_back(node)

func iterate_scene_pass2(node):
	for child in node.get_children():
		iterate_scene_pass2(child)

	var metas = node.get_meta_list()
	for meta in metas:
		var meta_val = node.get_meta(meta)
		if "material" in meta:
			_material(node, metas, meta, meta_val)

func set_child_ownership(node):
	for c in node.get_children():
		c.owner = node
		set_child_ownership(c)

func parse_globals(node):
	for child in node.get_children():
		if child is Node3D:
			var n := child as Node3D
			var preserve_position := n.global_position
				
			# reset origin
			if check_global_flag("individual_origins"):
				n.global_position = Vector3(0,0,0)
			
			# pack all into scenes
			if check_global_flag("packed_resources"):
				var ps := PackedScene.new()
				
				# before packing, we need to reset the owner of all children
				# to be this node
				set_child_ownership(child)
				var res := ps.pack(child)
				
				if res == OK:

					#var scene_path: String = addon_root + "packed_scenes/" + child.name + ".tscn"
					var scene_path: String = gltf_path.get_base_dir() + "/packed_scenes/" + child.name + ".tscn"
					var error = ResourceSaver.save(ps, scene_path)
					if error:
						print("Blender-Godot Pipeline: Error saving scene (" + scene_path + ") to disk.")
					else:
						# save was good, we can now unlink the node
						var packed_scene = load(scene_path).instantiate()
						packed_scene.name = "PackedScene_" + child.name
						node.add_child(packed_scene)
						if check_global_flag("individual_origins"):
							(packed_scene as Node3D).global_position = preserve_position
						packed_scene.owner = get_tree().edited_scene_root
						
						child.queue_free()
	
