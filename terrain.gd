extends StaticBody2D

const TERRAIN_WIDTH = 2560
const TERRAIN_DEPTH = 200
const TERRAIN_RESOLUTION = 8  # pixels between height samples
const GRASS_DEPTH = 20.0

var heights: PackedFloat32Array  # Y offset of surface at each sample (0 = top, positive = lower)

func _ready():
	add_to_group("terrain")
	
	# Initialize flat height map
	var num_points = int(TERRAIN_WIDTH / TERRAIN_RESOLUTION) + 1
	heights.resize(num_points)
	heights.fill(0.0)
	
	rebuild_mesh()

func rebuild_mesh():
	var num_points = heights.size()
	
	# Ground polygon: bottom-left → top edge left-to-right → bottom-right
	var ground_pts = PackedVector2Array()
	ground_pts.append(Vector2(0, TERRAIN_DEPTH))
	for i in range(num_points):
		ground_pts.append(Vector2(i * TERRAIN_RESOLUTION, heights[i]))
	ground_pts.append(Vector2(TERRAIN_WIDTH, TERRAIN_DEPTH))
	$Ground.polygon = ground_pts
	
	# Grass polygon: thin strip along surface, disappears in damaged areas
	var grass_pts = PackedVector2Array()
	# Top edge (terrain surface) left-to-right
	for i in range(num_points):
		var x = i * TERRAIN_RESOLUTION
		grass_pts.append(Vector2(x, heights[i]))
	# Bottom edge (grass depth below surface) right-to-left
	for i in range(num_points - 1, -1, -1):
		var x = i * TERRAIN_RESOLUTION
		# Suppress grass where surface is damaged (pushed down > 5px)
		var grass_bottom = heights[i] + GRASS_DEPTH if heights[i] < 5.0 else heights[i]
		grass_pts.append(Vector2(x, grass_bottom))
	$Grass.polygon = grass_pts
	
	# Collision matches ground shape
	$CollisionPolygon2D.polygon = ground_pts

func damage(world_hit_pos: Vector2, radius: float = 40.0, depth: float = 30.0):
	var local_pos = to_local(world_hit_pos)
	var hit_x = local_pos.x
	var num_points = heights.size()
	
	for i in range(num_points):
		var x = i * TERRAIN_RESOLUTION
		var dist = abs(x - hit_x)
		if dist < radius:
			# Circular crater profile with quadratic falloff
			var factor = 1.0 - (dist / radius)
			factor *= factor  # smoother, rounder crater
			heights[i] += depth * factor
			# Don't carve past the bottom of the terrain
			heights[i] = min(heights[i], TERRAIN_DEPTH - 10.0)
	
	rebuild_mesh()
