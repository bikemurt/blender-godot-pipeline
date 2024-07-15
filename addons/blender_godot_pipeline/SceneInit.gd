# Michael Burt 2024
# www.michaeljared.ca
# Reach out on Twitter for support @_michaeljared

@tool

extends Node3D

## Remove the originally imported
## GLTF node from your scene. This should be done when the design of a 
## level is complete. Doing this effectively disables "hot reload",
## so if you make further changes to your scene in Blender, you need to delete the
## _Imported node from the scene tree, re-import the GLTF file, and drag it 
## into the scene tree.
@export var remove_original_node := false:
	get: return remove_original_node
	set(value):
		if value and Engine.is_editor_hint():
			queue_free()

var reparent_nodes = []
var delete_nodes = []
var multimesh_dict = {}

var duplicate_scene: Node
func run_setup() -> void:
	if Engine.is_editor_hint():
		if get_meta("run"):
			
			print("Blender-Godot Pipeline: Running SceneInit - processing the scene.")
			
			duplicate_all()
			
			remove_skips(duplicate_scene)
			
			iterate_scene(duplicate_scene)
			
			process_multimeshes(duplicate_scene)
			
			reparent_pass()
			delete_pass()
			
			# SECOND PASS - process materials
			iterate_scene_pass2(duplicate_scene)
			
			# ensure that SceneInit only runs once
			set_meta("run", false)
			
			hide()
			
			print("Blender-Godot Pipeline: Scene processing complete. ")

func _ready():
	run_setup()

func duplicate_all() -> void:
	
	duplicate_scene = duplicate()
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
	
	duplicate_scene.scene_file_path = ""
	duplicate_scene.name = new_name
	
	get_parent().add_child(duplicate_scene)
	duplicate_scene.owner = get_tree().edited_scene_root

###

func reparent_pass():
	for node in reparent_nodes:
		node[0].reparent(node[1], true)
		node[0].set_owner(get_tree().edited_scene_root)
		
		set_children_scene_root(node[0])
		
func delete_pass():
	for node in delete_nodes:
		node.queue_free()

func set_children_scene_root(node):
	for child in node.get_children():
		set_children_scene_root(child)
		child.set_owner(get_tree().edited_scene_root)

func _set_script_params(node, script_filepath):
	var script_file = FileAccess.open(script_filepath, FileAccess.READ)
	
	while not script_file.eof_reached():
		var line = script_file.get_line()
		var components = line.split('=')
		if len(components) > 1:
			var param_name = components[0]
			var expression = components[1]
			
			var e = Expression.new()
			e.parse(expression)
			node.set(param_name, e.execute())

func _material(node, metas, meta, meta_val):
	var surface_split = meta.split("_")
	if len(surface_split) > 0:
		var surface = surface_split[1]
		var material = load(meta_val)
		
		if "shader" in metas:
			var shader = load(node.get_meta("shader"))
			material.set_shader(shader)
		
		node.set_surface_override_material(int(surface), material)
			
# 2024-05-09 LEGACY... eventually remove
func _multimesh(node, metas, meta, meta_val):
	var mm_i = MultiMeshInstance3D.new()
	node.get_parent().add_child(mm_i)
	
	var scatter_size = Vector3(10,10,10)
	if "size_x" in metas:
		scatter_size.x = float(node.get_meta("size_x"))
		scatter_size.y = float(node.get_meta("size_y"))
		scatter_size.z = float(node.get_meta("size_z"))
	
	mm_i.set("scatter_size", scatter_size)
	
	mm_i.transform = node.transform
	
	var target : MeshInstance3D = get_node(meta_val)
	mm_i.name = target.name + "_Multimesh"
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = target.mesh
	mm_i.multimesh = mm
	
	mm_i.set_owner(get_tree().edited_scene_root)
	
	##
	
	if "script" in metas:
		mm_i.set_script(load(node.get_meta("script")))
	
	##
	
	if "prop_file" in metas:
		_set_script_params(mm_i, node.get_meta("prop_file"))
	
	# occlusion culling flickers... more investigation needed
	if "occlusion_culling" in metas:
		var occlusion = OccluderInstance3D.new()
		node.get_parent().add_child(occlusion)
		
		occlusion.name = "OccluderInstance3D"
		occlusion.transform = node.transform
		
		var box_occluder = BoxOccluder3D.new()
		box_occluder.size = scatter_size
		occlusion.occluder = box_occluder
		
		occlusion.set_owner(get_tree().edited_scene_root)
	##
	
	if "camera_node" in metas:
		var dyn_node = Node.new()
		node.get_parent().add_child(dyn_node)
		
		dyn_node.name = "DynamicInstancingNode"
		dyn_node.set_script(load(node.get_meta("dynamic_script")))
		
		dyn_node.set("target_path", node.get_meta("camera_node"))
		dyn_node.set("multimesh_path", "../" + mm_i.name)
		
		var plane_size = Vector2(scatter_size.x, scatter_size.z).length()
		
		dyn_node.set("distance_fade_start", plane_size)
		dyn_node.set("distance_fade_end", plane_size * 2)
		
		dyn_node.set_owner(get_tree().edited_scene_root)
	##
	
	# THIS DOES NOT WORK APPARENTLY
	if "group" in metas:
		mm_i.add_to_group(node.get_meta("group"), true)
	
	##
	
	target.hide()
	delete_nodes.append(node)

# COLLLISIONS
func collision_script(body, node, metas) -> void:
	if "script" in metas:
		body.set_script(load(node.get_meta("script")))
	
	if "prop_file" in metas:
		# collision handled separately
		_set_script_params(body, node.get_meta("prop_file"))
	
	if "physics_mat" in metas:
		if body is StaticBody3D or body is RigidBody3D:
			body.physics_material_override = load(node.get_meta("physics_mat"))

# LEGACY 06/24/24
func _complex_col(node, rigid_body, area_3d, simple, trimesh, meta_val, metas):
	var mesh_inst : MeshInstance3D = node

	if simple: mesh_inst.create_convex_collision()
	if trimesh: mesh_inst.create_trimesh_collision()
	mesh_inst.set_owner(get_tree().edited_scene_root)
	
	#if rigid_body or area_3d:
	var body = StaticBody3D.new()
	body.name = node.name + "_StaticBody3D"
	
	if rigid_body:
		body = RigidBody3D.new()
		body.name = node.name + "_RigidBody3D"
	
	if area_3d:
		body = Area3D.new()
		body.name = node.name + "_Area3D"
	
	var col = node.get_children()[0].get_children()[0]
	reparent_nodes.append([col, body])
	
	reparent_nodes.append([node, body])
	
	delete_nodes.append(node.get_children()[0])
	
	var discard_mesh = "-d" in meta_val
	if discard_mesh: delete_nodes.append(node)
	
	node.get_parent().add_child(body)
	body.set_owner(get_tree().edited_scene_root)
	
	collision_script(body, node, metas)


# NEW COLLISION - CAPTURES ALL TYPES NOW 06/24/24
func _primitive_col(node, rigid_body, area_3d, meta_val, metas):
	var t = node.transform
	var body = StaticBody3D.new()
	body.name = "StaticBody3D_" + node.name
	
	if rigid_body:
		body = RigidBody3D.new()
		body.name = "RigidBody3D_" + node.name
	
	if area_3d:
		body = Area3D.new()
		body.name = "Area3D_" + node.name
	
	# --- NEW --- migrating simple/trimesh into primitive function
	
	var simple: bool = "simple" in meta_val
	var trimesh: bool = "trimesh" in meta_val
	var mesh_inst: MeshInstance3D = node
	var trimesh_shape := ConcavePolygonShape3D.new()
	var simple_shape := ConvexPolygonShape3D.new()
	if simple:
		mesh_inst.create_convex_collision()
		body = node.get_children()[0].duplicate()
		var col_shape_3d: CollisionShape3D = body.get_children()[0]
		simple_shape = col_shape_3d.shape.duplicate()
	if trimesh:
		mesh_inst.create_trimesh_collision()
		body = node.get_children()[0].duplicate()
		var col_shape_3d: CollisionShape3D = body.get_children()[0]
		trimesh_shape = col_shape_3d.shape.duplicate()
	
	# ---
	
	var col_only = "-c" in meta_val
	
	body.position = node.position
	
	var discard_mesh = "-d" in meta_val
	var nd : Node3D = node.duplicate()
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

# NEW COLLISION - CAPTURES ALL TYPES NOW 06/24/24
func _collision(node, metas, meta, meta_val):
	var mesh_inst : MeshInstance3D = node
	
	var rigid_body = false
	if "-r" in meta_val: rigid_body = true
	
	var area_3d = false
	if "-a" in meta_val: area_3d = true
	
	var simple = "simple" in meta_val
	var trimesh = "trimesh" in meta_val
	
	if simple or trimesh:	
		_primitive_col(node, rigid_body, area_3d, meta_val, metas)
		#_complex_col(node, rigid_body, area_3d, simple, trimesh, meta_val, metas)
	else:
		_primitive_col(node, rigid_body, area_3d, meta_val, metas)

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

# MULTTIMESH
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
	# we only ever parse mesh instance 3Ds from Blender (e.g. BLENDER OBJECTS)
	node.owner = get_tree().edited_scene_root
	if node is MeshInstance3D:
		var mesh_inst : MeshInstance3D = node
		
		var metas = node.get_meta_list()
		for meta in metas:
			
			var meta_val = node.get_meta(meta)
			
			if meta == "state":
				if meta_val == "hide":
					node.hide()
					
			# PARSE NAME OVERRIDE FIRST
			if "name_override" in metas:
				if node.get_meta("name_override") != "":
					mesh_inst.name = node.get_meta("name_override")
			
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
			
			# LEGACY MULTIMESH
			if meta == "multimesh_target":
				_multimesh(node, metas, meta, meta_val)
			
			# new collision logic as of v1.3 2024/02/01
			if meta == "collision":
				_collision(node, metas, meta, meta_val)
			
			if meta == "nav_mesh":
				_nav_mesh(node, meta, meta_val)
				
			if meta == "multimesh":
				_multimesh_new(node, meta, meta_val)

func iterate_scene_pass2(node):
	for child in node.get_children():
		iterate_scene_pass2(child)

	# not explicitly checking if node is MeshInstance3D here..
	# maybe this is a good idea?
	var metas = node.get_meta_list()
	for meta in metas:
		var meta_val = node.get_meta(meta)
		if "material" in meta:
			_material(node, metas, meta, meta_val)
