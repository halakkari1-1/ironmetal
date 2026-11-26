extends SceneTree
## Makes the lighter meshes of the lobby yard for the medium and low tiers: assets/lobby/lo/<name>.res.
## Each model is read as glTF, Godot's own simplifier (the one behind its automatic levels of detail) builds
## its levels, and the level closest to the target triangle count is kept, with the coarser levels after it as
## the mesh's own levels of detail. The vertices and their texture coordinates are the original ones, so the
## same maps fit.
## usage (from godot/):  godot --headless --path . --script res://tools/models/lobby_lods.gd

const TARGETS := {"cliffs": 150000, "foundry": 80000, "bridge": 60000, "outpost": 80000,
	"beacon1": 30000, "beacon2": 30000, "beacon3": 30000, "beacon4": 30000}


func _init() -> void:
	for id in TARGETS:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file("res://assets/lobby/%s.glb" % id, state) != OK:
			push_error("cannot read " + id)
			continue
		var im: ImporterMesh = state.get_meshes()[0].mesh
		im.generate_lods(25.0, 60.0, [])
		var arr := im.get_surface_arrays(0)
		var full: int = arr[Mesh.ARRAY_INDEX].size() / 3
		var pick := -1
		var levels := []
		for l in im.get_surface_lod_count(0):
			var n: int = im.get_surface_lod_indices(0, l).size() / 3
			levels.append(n)
			if pick < 0 and n <= TARGETS[id]:
				pick = l
		if pick < 0:
			pick = im.get_surface_lod_count(0) - 1
		var base: PackedInt32Array = im.get_surface_lod_indices(0, pick)
		# keep only the vertices this level uses
		var used := {}
		var order := PackedInt32Array()
		for i in base:
			if not used.has(i):
				used[i] = order.size()
				order.append(i)
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TANGENT]:
			var src = arr[k]
			if src == null:
				continue
			if k == Mesh.ARRAY_TANGENT:
				var t := PackedFloat32Array()
				for i in order:
					for c in 4:
						t.append(src[i * 4 + c])
				out[k] = t
			elif k == Mesh.ARRAY_TEX_UV:
				var u := PackedVector2Array()
				for i in order:
					u.append(src[i])
				out[k] = u
			else:
				var v := PackedVector3Array()
				for i in order:
					v.append(src[i])
				out[k] = v
		var remap := func(ix: PackedInt32Array) -> PackedInt32Array:
			var r := PackedInt32Array()
			for i in ix:
				r.append(used.get(i, 0))
			return r
		out[Mesh.ARRAY_INDEX] = remap.call(base)
		var lods := {}
		for l in range(pick + 1, im.get_surface_lod_count(0)):
			var ix := im.get_surface_lod_indices(0, l)
			var ok := true
			for i in ix:
				if not used.has(i):
					ok = false
					break
			if ok:
				lods[im.get_surface_lod_size(0, l)] = remap.call(ix)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], lods)
		ResourceSaver.save(mesh, "res://assets/lobby/lo/%s.res" % id, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d -> %d triangles (levels %s), %d lower levels kept" % [id, full, base.size() / 3, levels, lods.size()])
	quit()
