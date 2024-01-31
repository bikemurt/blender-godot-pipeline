@tool

extends Node

var reparent_nodes = []
var delete_nodes = []
var staticbody_cleanup_nodes = []
var rigidbody_cleanup_nodes = []

# Called when the node enters the scene tree for the first time.
func _ready():
	if Engine.is_editor_hint():
		if get_meta("run"):
			print("Running scene init")
			
			iterate_scene(self)
			
			reparent_pass()
			delete_pass()
			staticbody_cleanup()
			rigidbody_cleanup()
			
			#self.scene_file_path = ""
			#self.set_owner(get_tree().edited_scene_root)
			
			# ensure that SceneInit only runs once
			set_meta("run", false)

func reparent_pass():
	for node in reparent_nodes:
		node[0].reparent(node[1], true)
		node[0].set_owner(get_tree().edited_scene_root)
		
		set_children_scene_root(node[0])
		
func delete_pass():
	for node in delete_nodes:
		node.queue_free()

func staticbody_cleanup():
	for node in staticbody_cleanup_nodes:
		var staticbody : StaticBody3D
		for child in node.get_children():
			if child is StaticBody3D:
				staticbody = child
		
		var col_list = []
		for child in node.get_children():
			if child is CollisionShape3D:
				col_list.append(child)
		
		for col in col_list:
			col.reparent(staticbody)
			col.set_owner(get_tree().edited_scene_root)

func rigidbody_cleanup():
	for node in rigidbody_cleanup_nodes:
		# expect a child to be a meshInstance3D
		print(node.name)
		var col_list = []
		for child in node.get_children():
			if child is CollisionShape3D:
				col_list.append(child)
				
		for col in col_list:
			col.reparent(node.get_parent())
			col.set_owner(get_tree().edited_scene_root)	

func set_children_scene_root(node):
	for child in node.get_children():
		set_children_scene_root(child)
		child.set_owner(get_tree().edited_scene_root)

func set_body(node : Node3D, rigid_body=false):
	var body = StaticBody3D.new()
	body.name = node.name + "_StaticBody3D"

	if rigid_body:
		body = RigidBody3D.new()
		body.name = node.name + "_RigidBody3D"
		#body.transform = node.transform
		
		reparent_nodes.append([node, body])
		
		node.get_parent().add_child(body)
	else:
		node.add_child(body)

	body.set_owner(get_tree().edited_scene_root)
	
	return body

func set_generic_collision(node : Node3D, rigid_body=false, collision_only=false):
	var collision = CollisionShape3D.new()
	collision.name = node.name + "_CollisionShape3D"
	
	if collision_only:
		reparent_nodes.append([collision, node.get_parent()])
		delete_nodes.append(node)
		return [node, collision]
	
	else:
		var body = set_body(node, rigid_body)
		return [body, collision]	

func set_shape(col, shape):
	col[1].shape = shape
	
	col[0].add_child(col[1])
	col[1].set_owner(get_tree().edited_scene_root)

func set_script_params(node, script_filepath):
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

func iterate_scene(node):
	
	if node is MeshInstance3D:		
		var mesh_inst : MeshInstance3D = node
		
		var metas = node.get_meta_list()
		for meta in metas:
			
			var meta_val = node.get_meta(meta)
			if "material" in meta:
				var surface_split = meta.split("_")
				if len(surface_split) > 0:
					var surface = surface_split[1]
					var material = load(meta_val)
					
					var shader = load(node.get_meta("shader"))
					material.set_shader(shader)
					
					node.set_surface_override_material(int(surface), material)
			
			if "group" in meta:
				# TBD
				pass
			
			if "prop_file" in meta:
				# TBD
				pass
			
			if meta == "script":
				node.set_script(load(meta_val))
			
			if meta == "multimesh_target":
				
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
					set_script_params(mm_i, node.get_meta("prop_file"))
				
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
			
			if meta == "collision":
				var rigid_body = false
				var col_only = false
				
				if "-r" in meta_val:
					rigid_body = true
					meta_val = meta_val.replace("-r", "")
				
				if "-c" in meta_val:
					col_only = true
					meta_val = meta_val.replace("-c", "")
					
				if meta_val == "simple":
					mesh_inst.create_convex_collision()
					mesh_inst.set_owner(get_tree().edited_scene_root)
					
					if rigid_body:
						var body = RigidBody3D.new()
						body.name = node.name + "_RigidBody3D"
						#body.transform = node.transform
												
						var col = node.get_children()[0].get_children()[0]
						reparent_nodes.append([col, body])
						
						reparent_nodes.append([node, body])
						
						delete_nodes.append(node.get_children()[0])
						
						node.get_parent().add_child(body)
						body.set_owner(get_tree().edited_scene_root)
				
				if meta_val == "trimesh":
					mesh_inst.create_trimesh_collision()
				
				if meta_val == "cylinder":
					if "height" in metas and "radius" in metas:
						var col = set_generic_collision(node, rigid_body, col_only)
						
						var cyl = CylinderShape3D.new()
						
						var height = float(node.get_meta("height"))
						var radius = float(node.get_meta("radius"))
						
						cyl.height = height
						cyl.radius = radius
						
						set_shape(col, cyl)
				
				if meta_val == "box":
					if "size_x" in metas and "size_x" in metas \
					and "size_z" in metas:
						var col = set_generic_collision(node, rigid_body, col_only)
						
						var box = BoxShape3D.new()
						
						var size_x = float(node.get_meta("size_x"))
						var size_y = float(node.get_meta("size_y"))
						var size_z = float(node.get_meta("size_z"))
						
						box.size = Vector3(size_x, size_y, size_z)
						
						set_shape(col, box)
				
				if meta_val == "bodyonly":
					set_body(node, rigid_body)
					if rigid_body:
						rigidbody_cleanup_nodes.append(node)
					else:
						staticbody_cleanup_nodes.append(node)
				
			if meta == "state":
				if meta_val == "hide":
					node.hide()	
				
	for child in node.get_children():
		iterate_scene(child)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
