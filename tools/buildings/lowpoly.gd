extends SceneTree
## First half of the skyline building baker (second half: tools/buildings/bake.py). The source models are ~100k
## triangles with their texture cut into thousands of tiny pieces, so no simplifier can reduce them while keeping
## that texture layout. Instead: merge vertices by position, simplify the shape (Godot's meshoptimizer), give the
## result a fresh UV layout (xatlas, via lightmap_unwrap), and write it out; bake.py then paints the new texture from
## the original model. usage: copy into godot/ as tools_lowpoly.gd, then
## godot --headless --path . --script res://tools_lowpoly.gd -- [triangles] [suffix]

const IDS := ["skyscraper", "spire", "ascent", "refinery", "foundry"]


func _init() -> void:
	var target := 12000
	var suffix := ""
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			target = int(a)
		else:
			suffix = a
	for id in IDS:
		var scene: PackedScene = load("res://assets/buildings/%s.glb" % id)
		var root := scene.instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var key := {}
		var WV := PackedVector3Array()
		var map := PackedInt32Array(); map.resize(V.size())
		for i in V.size():
			var k := (V[i] * 2000.0).round()
			if not key.has(k):
				key[k] = WV.size()
				WV.append(V[i])
			map[i] = key[k]
		var WI := PackedInt32Array()
		for t in I.size() / 3:
			var a := map[I[t * 3]]; var b := map[I[t * 3 + 1]]; var c := map[I[t * 3 + 2]]
			if a != b and b != c and a != c:
				WI.append(a); WI.append(b); WI.append(c)
		var w := []
		w.resize(Mesh.ARRAY_MAX)
		w[Mesh.ARRAY_VERTEX] = WV
		w[Mesh.ARRAY_INDEX] = WI
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, w)
		im.generate_lods(180.0, 0.0, [])
		var best := WI
		for l in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, l)
			if idx.size() / 3 >= target * 0.7:
				best = idx
		# flat-shaded copy (hard edges are right for buildings), then a fresh UV layout
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in best:
			st.add_vertex(WV[x])
		st.generate_normals()
		var am := st.commit()
		var size: float = am.get_aabb().size.length()
		var err := am.lightmap_unwrap(Transform3D.IDENTITY, size / 1400.0)
		var out: Array = am.surface_get_arrays(0)
		var OV: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
		var ON: PackedVector3Array = out[Mesh.ARRAY_NORMAL]
		var OU: PackedVector2Array = out[Mesh.ARRAY_TEX_UV2]
		var OI = out[Mesh.ARRAY_INDEX]
		if OI == null:
			OI = PackedInt32Array(range(OV.size()))
		var f := FileAccess.open("res://../tools/buildings/%s%s.bin" % [id, suffix], FileAccess.WRITE)
		f.store_32(OV.size())
		for i in OV.size():
			f.store_float(OV[i].x); f.store_float(OV[i].y); f.store_float(OV[i].z)
			f.store_float(ON[i].x); f.store_float(ON[i].y); f.store_float(ON[i].z)
			f.store_float(OU[i].x); f.store_float(OU[i].y)
		f.store_32(OI.size() / 3)
		for x in OI:
			f.store_32(x)
		f.close()
		print("%s: %d -> %d triangles, %d verts after unwrap (err %d)" % [id, I.size() / 3, OI.size() / 3, OV.size(), err])
		root.free()
	quit()
