extends StaticBody2D

const TERRAIN_WIDTH = 2560
const TERRAIN_DEPTH = 200
const TERRAIN_RESOLUTION = 8  # pixels between height samples
const GRASS_DEPTH = 20.0

var heights: PackedFloat32Array  # Y offset of surface at each sample (0 = top, positive = lower)
var decorations: Array = []      # [{node: Node2D, x: float, width: float}]

func _ready():
	add_to_group("terrain")
	
	# Initialize height map with gentle rolling hills
	var num_points = int(TERRAIN_WIDTH / TERRAIN_RESOLUTION) + 1
	heights.resize(num_points)
	heights.fill(0.0)
	
	# Generate rolling terrain using layered sine waves
	# Launcher positions in local x: 400, 900, 1400, 1900 — flatten near those
	var launcher_xs = [400.0, 900.0, 1400.0, 1900.0]
	var flatten_radius = 80.0  # flat zone around each launcher
	
	# Random phase offsets for organic variety each game
	var phase1 = randf() * TAU
	var phase2 = randf() * TAU
	var phase3 = randf() * TAU
	
	for i in range(num_points):
		var x = float(i * TERRAIN_RESOLUTION)
		# Layered sine hills — different frequencies and amplitudes
		var h = 0.0
		h += sin(x * 0.004 + phase1) * 18.0      # broad rolling hills
		h += sin(x * 0.011 + phase2) * 8.0        # medium bumps
		h += sin(x * 0.025 + phase3) * 3.5        # small texture
		
		# Flatten near launcher positions so they sit level
		var flatten_factor = 1.0
		for lx in launcher_xs:
			var dist = abs(x - lx)
			if dist < flatten_radius:
				var t = dist / flatten_radius
				flatten_factor = min(flatten_factor, smoothstep(0.0, 1.0, t))
		
		# Shift hills to be mostly at or below surface (negative = mound up)
		heights[i] = h * flatten_factor - 5.0  # bias slightly up so hills are visible
		heights[i] = clampf(heights[i], -25.0, 20.0)
	
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
	_destroy_decorations_near(hit_x, radius * 1.5)

# ---------------------------------------------------------------------------
#  Decoration system — randomly placed buildings, bridges, soldiers
# ---------------------------------------------------------------------------

func spawn_decorations():
	# Clear any existing decorations
	for d in decorations:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	decorations.clear()

	# --- Background mountains (drawn behind everything) ---
	_add_background_mountains()

	# --- Scattered trees across full width (behind buildings) ---
	_scatter_trees()

	# Safe zones between launchers (launcher x: 400, 900, 1400, 1900 in local coords)
	var zones = [
		Vector2(50, 260),
		Vector2(540, 760),
		Vector2(1040, 1260),
		Vector2(1540, 1760),
		Vector2(2040, 2460),
	]

	# --- Place 1-2 bridges ---
	var bridge_zones = zones.duplicate()
	bridge_zones.shuffle()
	var num_bridges = randi_range(1, 2)
	for bi in range(mini(num_bridges, bridge_zones.size())):
		var bz = bridge_zones[bi]
		var bx = randf_range(bz.x + 20, bz.y - 100)
		_add_bridge(bx)

	# --- Fill zones with buildings, soldiers, and small trees/bushes ---
	for zone in zones:
		var items = randi_range(3, 5)
		var placed: Array = []  # x positions already used
		for _i in range(items):
			var x = randf_range(zone.x, zone.y)
			# Minimum spacing check
			var skip = false
			for px in placed:
				if abs(x - px) < 55:
					skip = true
					break
			if skip:
				continue
			placed.append(x)

			var roll = randf()
			if roll < 0.20:
				_add_civilian_building(x)
			elif roll < 0.35:
				_add_industry_building(x)
			elif roll < 0.50:
				_add_soldier_group(x)
			elif roll < 0.68:
				_add_deciduous_tree(x)
			elif roll < 0.82:
				_add_pine_tree(x)
			else:
				_add_bush_cluster(x)

func _register_decoration(node: Node2D, x: float, w: float):
	add_child(node)
	decorations.append({"node": node, "x": x, "width": w})

func _destroy_decorations_near(hit_x: float, blast_radius: float):
	var to_remove: Array = []
	for d in decorations:
		if not is_instance_valid(d["node"]):
			to_remove.append(d)
			continue
		var dx_min = d["x"]
		var dx_max = d["x"] + d["width"]
		var center = (dx_min + dx_max) * 0.5
		if abs(center - hit_x) < blast_radius + d["width"] * 0.5:
			_spawn_debris_burst(d["node"].position + Vector2(d["width"] * 0.5, -10))
			d["node"].queue_free()
			to_remove.append(d)
	for d in to_remove:
		decorations.erase(d)

func _spawn_debris_burst(local_pos: Vector2):
	var debris_root = Node2D.new()
	debris_root.position = local_pos
	add_child(debris_root)

	for _i in range(randi_range(4, 8)):
		var chip = Polygon2D.new()
		var s = randf_range(2, 5)
		chip.polygon = PackedVector2Array([
			Vector2(-s, -s), Vector2(s * 0.5, -s * 0.7),
			Vector2(s, s * 0.3), Vector2(-s * 0.4, s)
		])
		chip.color = [
			Color(0.45, 0.35, 0.25), Color(0.55, 0.45, 0.3),
			Color(0.35, 0.3, 0.25), Color(0.5, 0.4, 0.35)
		].pick_random()
		chip.position = Vector2(randf_range(-8, 8), randf_range(-8, 8))
		chip.rotation = randf() * TAU
		debris_root.add_child(chip)

	# Animate debris flying outward then fade
	var tw = create_tween().set_parallel(true)
	for chip in debris_root.get_children():
		var dir = Vector2(randf_range(-60, 60), randf_range(-80, -20))
		tw.tween_property(chip, "position", chip.position + dir, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(chip, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.chain().tween_callback(debris_root.queue_free)

# ---------------------------------------------------------------------------
#  Background mountains — parallax-style layered silhouettes behind terrain
# ---------------------------------------------------------------------------
func _add_background_mountains():
	var bg = Node2D.new()
	bg.name = "BackgroundMountains"
	bg.z_index = -10  # behind everything

	# Layer 1: far distant mountains (very dark, tall, smooth)
	var far_color = Color(0.15, 0.18, 0.22, 0.7)
	_draw_mountain_layer(bg, far_color, -280, 160, 5, 0.6)

	# Layer 2: mid-distance mountains (slightly lighter, more jagged)
	var mid_color = Color(0.18, 0.22, 0.26, 0.75)
	_draw_mountain_layer(bg, mid_color, -180, 120, 7, 0.8)

	# Layer 3: nearby hills (most detail, color closest to terrain)
	var near_color = Color(0.22, 0.28, 0.22, 0.65)
	_draw_mountain_layer(bg, near_color, -100, 80, 10, 1.0)

	# Snow caps on far mountains
	_draw_snow_caps(bg, -280, 160, 5)

	add_child(bg)

func _draw_mountain_layer(parent: Node2D, color: Color, base_y: float, max_height: float, num_peaks: int, jaggedness: float):
	var pts = PackedVector2Array()
	# Start at bottom-left
	pts.append(Vector2(0, 0))

	# Generate mountain ridge points
	var segment_width = TERRAIN_WIDTH / num_peaks
	var phase = randf() * TAU

	# Build smooth mountain outline with sub-peaks
	var ridge_points = []
	var steps = num_peaks * 6  # smooth resolution
	for i in range(steps + 1):
		var t = float(i) / steps
		var x = t * TERRAIN_WIDTH
		# Layered noise for natural look
		var h = 0.0
		h += sin(t * PI * num_peaks + phase) * max_height * 0.5
		h += sin(t * PI * num_peaks * 2.3 + phase * 1.7) * max_height * 0.25 * jaggedness
		h += sin(t * PI * num_peaks * 5.1 + phase * 3.2) * max_height * 0.08 * jaggedness
		h = max(h, 8.0)  # minimum hill height
		ridge_points.append(Vector2(x, base_y - h))

	for p in ridge_points:
		pts.append(p)

	# Close at bottom-right
	pts.append(Vector2(TERRAIN_WIDTH, 0))

	var mountain = Polygon2D.new()
	mountain.polygon = pts
	mountain.color = color
	parent.add_child(mountain)

func _draw_snow_caps(parent: Node2D, base_y: float, max_height: float, num_peaks: int):
	var phase = randf() * TAU
	var steps = num_peaks * 6
	var snow_color = Color(0.85, 0.88, 0.92, 0.5)

	for i in range(steps):
		var t = float(i) / steps
		var x = t * TERRAIN_WIDTH
		var h = 0.0
		h += sin(t * PI * num_peaks + phase) * max_height * 0.5
		h += sin(t * PI * num_peaks * 2.3 + phase * 1.7) * max_height * 0.25 * 0.6
		h += sin(t * PI * num_peaks * 5.1 + phase * 3.2) * max_height * 0.08 * 0.6

		# Only put snow on peaks above threshold
		if h > max_height * 0.6:
			var snow_h = (h - max_height * 0.6) * 0.4
			var peak_y = base_y - h
			var sw = randf_range(15, 30)
			var snow = Polygon2D.new()
			snow.polygon = PackedVector2Array([
				Vector2(x - sw * 0.5, peak_y + snow_h * 0.5),
				Vector2(x, peak_y - snow_h),
				Vector2(x + sw * 0.5, peak_y + snow_h * 0.5)
			])
			snow.color = snow_color
			parent.add_child(snow)

# ---------------------------------------------------------------------------
#  Scatter trees across terrain — fills open areas with natural vegetation
# ---------------------------------------------------------------------------
func _scatter_trees():
	var launcher_xs = [400.0, 900.0, 1400.0, 1900.0]
	var tree_clear = 70.0  # clearance around launchers

	var num_trees = randi_range(18, 30)
	for _ti in range(num_trees):
		var tx = randf_range(30, TERRAIN_WIDTH - 30)

		# Skip if too close to a launcher
		var near_launcher = false
		for lx in launcher_xs:
			if abs(tx - lx) < tree_clear:
				near_launcher = true
				break
		if near_launcher:
			continue

		# Get terrain height at this x
		var sample_i = clampi(int(tx / TERRAIN_RESOLUTION), 0, heights.size() - 1)
		var terrain_y = heights[sample_i]

		var roll = randf()
		if roll < 0.40:
			_add_pine_tree(tx, terrain_y)
		elif roll < 0.75:
			_add_deciduous_tree(tx, terrain_y)
		else:
			_add_bush_cluster(tx, terrain_y)

# ---------------------------------------------------------------------------
#  Deciduous tree — round/organic canopy with trunk, branches, shadow
# ---------------------------------------------------------------------------
func _add_deciduous_tree(x: float, y_offset: float = 0.0):
	var node = Node2D.new()
	node.position = Vector2(x, y_offset)

	var trunk_h = randf_range(22, 38)
	var trunk_w = randf_range(4, 7)
	var canopy_r = randf_range(16, 28)

	var trunk_colors = [
		Color(0.35, 0.25, 0.16), Color(0.38, 0.28, 0.18),
		Color(0.32, 0.22, 0.14), Color(0.40, 0.30, 0.20),
	]
	var trunk_color: Color = trunk_colors.pick_random()

	var canopy_greens = [
		Color(0.22, 0.42, 0.18), Color(0.25, 0.45, 0.20),
		Color(0.20, 0.38, 0.16), Color(0.28, 0.48, 0.22),
		Color(0.18, 0.40, 0.15), Color(0.24, 0.44, 0.20),
	]
	var canopy_color: Color = canopy_greens.pick_random()

	# Ground shadow (ellipse)
	var shadow = Polygon2D.new()
	var shadow_pts = PackedVector2Array()
	var shadow_rx = canopy_r * 0.8
	var shadow_ry = 4.0
	for si in range(12):
		var angle = TAU * si / 12
		shadow_pts.append(Vector2(cos(angle) * shadow_rx, sin(angle) * shadow_ry + 2))
	shadow.polygon = shadow_pts
	shadow.color = Color(0.08, 0.10, 0.05, 0.35)
	node.add_child(shadow)

	# Trunk
	var trunk = Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(-trunk_w * 0.5, 0), Vector2(trunk_w * 0.5, 0),
		Vector2(trunk_w * 0.35, -trunk_h), Vector2(-trunk_w * 0.35, -trunk_h)
	])
	trunk.color = trunk_color
	node.add_child(trunk)

	# Trunk bark texture (darker strip)
	var bark = Polygon2D.new()
	bark.polygon = PackedVector2Array([
		Vector2(-trunk_w * 0.15, -2), Vector2(trunk_w * 0.15, -2),
		Vector2(trunk_w * 0.1, -trunk_h + 3), Vector2(-trunk_w * 0.1, -trunk_h + 3)
	])
	bark.color = trunk_color.darkened(0.2)
	node.add_child(bark)

	# Branches (2-3 visible ones poking out)
	var num_branches = randi_range(2, 3)
	for bi in range(num_branches):
		var by = -trunk_h * randf_range(0.5, 0.85)
		var bdir = 1.0 if bi % 2 == 0 else -1.0
		var blen = randf_range(8, 15)
		var branch = Polygon2D.new()
		branch.polygon = PackedVector2Array([
			Vector2(0, by), Vector2(bdir * blen, by - randf_range(4, 10)),
			Vector2(bdir * blen, by - randf_range(4, 10) - 1.5), Vector2(0, by - 1.5)
		])
		branch.color = trunk_color.darkened(0.08)
		node.add_child(branch)

	# Canopy — multiple overlapping circles for organic shape
	var canopy_center_y = -trunk_h - canopy_r * 0.4
	var num_blobs = randi_range(4, 6)
	for ci in range(num_blobs):
		var blob = Polygon2D.new()
		var blob_pts = PackedVector2Array()
		var br = canopy_r * randf_range(0.55, 0.85)
		var bx = randf_range(-canopy_r * 0.4, canopy_r * 0.4)
		var by = canopy_center_y + randf_range(-canopy_r * 0.3, canopy_r * 0.3)
		var segments = 10
		for si in range(segments):
			var angle = TAU * si / segments
			# Organic wobble
			var wobble = 1.0 + sin(angle * 3 + ci) * 0.15
			blob_pts.append(Vector2(
				bx + cos(angle) * br * wobble,
				by + sin(angle) * br * wobble * 0.85
			))
		blob.polygon = blob_pts
		blob.color = canopy_color.lightened(randf_range(-0.06, 0.06))
		node.add_child(blob)

	# Canopy highlight (top-left light source)
	var highlight = Polygon2D.new()
	var hl_pts = PackedVector2Array()
	var hl_r = canopy_r * 0.5
	for si in range(8):
		var angle = TAU * si / 8
		hl_pts.append(Vector2(
			-canopy_r * 0.2 + cos(angle) * hl_r,
			canopy_center_y - canopy_r * 0.15 + sin(angle) * hl_r * 0.7
		))
	highlight.polygon = hl_pts
	highlight.color = canopy_color.lightened(0.15)
	highlight.modulate.a = 0.4
	node.add_child(highlight)

	_register_decoration(node, x, canopy_r * 2)

# ---------------------------------------------------------------------------
#  Pine / conifer tree — triangular layered canopy
# ---------------------------------------------------------------------------
func _add_pine_tree(x: float, y_offset: float = 0.0):
	var node = Node2D.new()
	node.position = Vector2(x, y_offset)

	var trunk_h = randf_range(18, 30)
	var trunk_w = randf_range(3.5, 5.5)
	var tree_h = randf_range(40, 65)  # total height including canopy
	var base_width = randf_range(18, 28)

	var trunk_color = Color(0.32, 0.22, 0.14)
	var pine_greens = [
		Color(0.12, 0.30, 0.14), Color(0.14, 0.32, 0.16),
		Color(0.10, 0.28, 0.12), Color(0.16, 0.34, 0.15),
		Color(0.11, 0.26, 0.13),
	]
	var pine_color: Color = pine_greens.pick_random()

	# Ground shadow
	var shadow = Polygon2D.new()
	var shadow_pts = PackedVector2Array()
	for si in range(10):
		var angle = TAU * si / 10
		shadow_pts.append(Vector2(cos(angle) * base_width * 0.6, sin(angle) * 3.5 + 2))
	shadow.polygon = shadow_pts
	shadow.color = Color(0.06, 0.08, 0.04, 0.3)
	node.add_child(shadow)

	# Trunk
	var trunk = Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(-trunk_w * 0.5, 0), Vector2(trunk_w * 0.5, 0),
		Vector2(trunk_w * 0.3, -trunk_h), Vector2(-trunk_w * 0.3, -trunk_h)
	])
	trunk.color = trunk_color
	node.add_child(trunk)

	# Layered triangular canopy (3-5 tiers)
	var num_tiers = randi_range(3, 5)
	var canopy_start = -trunk_h * 0.6  # canopy overlaps trunk
	var tier_h = (tree_h - trunk_h * 0.4) / num_tiers

	for ti in range(num_tiers):
		var ty = canopy_start - ti * tier_h * 0.75  # tiers overlap
		var tw = base_width * (1.0 - ti * 0.15)  # narrower toward top
		var th = tier_h * 1.1  # slight overlap

		# Main tier triangle
		var tier = Polygon2D.new()
		tier.polygon = PackedVector2Array([
			Vector2(-tw * 0.5, ty), Vector2(tw * 0.5, ty), Vector2(0, ty - th)
		])
		tier.color = pine_color.lightened(ti * 0.03)
		node.add_child(tier)

		# Shadow on right side of tier
		var tier_shadow = Polygon2D.new()
		tier_shadow.polygon = PackedVector2Array([
			Vector2(0, ty), Vector2(tw * 0.5, ty), Vector2(0, ty - th)
		])
		tier_shadow.color = pine_color.darkened(0.12)
		node.add_child(tier_shadow)

		# Snow dusting on top tier edges (subtle)
		if ti >= num_tiers - 2 and randf() < 0.3:
			var snow = Polygon2D.new()
			var snow_w = tw * 0.3
			snow.polygon = PackedVector2Array([
				Vector2(-snow_w * 0.5, ty - th + 2),
				Vector2(snow_w * 0.5, ty - th + 2),
				Vector2(0, ty - th - 1)
			])
			snow.color = Color(0.90, 0.92, 0.95, 0.35)
			node.add_child(snow)

	_register_decoration(node, x, base_width)

# ---------------------------------------------------------------------------
#  Bush cluster — low rounded shrubs grouped together
# ---------------------------------------------------------------------------
func _add_bush_cluster(x: float, y_offset: float = 0.0):
	var node = Node2D.new()
	node.position = Vector2(x, y_offset)

	var num_bushes = randi_range(2, 4)
	var spread = num_bushes * randf_range(8, 12)

	var bush_greens = [
		Color(0.20, 0.36, 0.16), Color(0.24, 0.40, 0.18),
		Color(0.18, 0.34, 0.14), Color(0.26, 0.38, 0.20),
		Color(0.22, 0.42, 0.17),
	]

	for bi in range(num_bushes):
		var bx = randf_range(-spread * 0.5, spread * 0.5)
		var bush_w = randf_range(10, 18)
		var bush_h = randf_range(8, 14)
		var bush_color: Color = bush_greens.pick_random()

		# Bush shadow
		var shadow = Polygon2D.new()
		var shadow_pts = PackedVector2Array()
		for si in range(8):
			var angle = TAU * si / 8
			shadow_pts.append(Vector2(
				bx + cos(angle) * bush_w * 0.5,
				sin(angle) * 2.5 + 2
			))
		shadow.polygon = shadow_pts
		shadow.color = Color(0.06, 0.08, 0.04, 0.25)
		node.add_child(shadow)

		# Bush body — rounded blob
		var bush = Polygon2D.new()
		var bush_pts = PackedVector2Array()
		var segments = 10
		for si in range(segments):
			var angle = TAU * si / segments
			var wobble = 1.0 + sin(angle * 2.5 + bi) * 0.2
			var rx = bush_w * 0.5 * wobble
			var ry = bush_h * 0.5 * wobble
			# Flatten bottom
			var py = sin(angle) * ry
			if py > 0:
				py *= 0.3  # squash bottom
			bush_pts.append(Vector2(
				bx + cos(angle) * rx,
				-bush_h * 0.3 + py
			))
		bush.polygon = bush_pts
		bush.color = bush_color
		node.add_child(bush)

		# Bush highlight blob (top-left)
		var hl = Polygon2D.new()
		var hl_pts = PackedVector2Array()
		var hl_r = bush_w * 0.25
		for si in range(7):
			var angle = TAU * si / 7
			hl_pts.append(Vector2(
				bx - bush_w * 0.12 + cos(angle) * hl_r,
				-bush_h * 0.45 + sin(angle) * hl_r * 0.6
			))
		hl.polygon = hl_pts
		hl.color = bush_color.lightened(0.12)
		hl.modulate.a = 0.45
		node.add_child(hl)

		# Occasional berry/flower dots
		if randf() < 0.3:
			var berry_colors = [
				Color(0.75, 0.15, 0.15), Color(0.85, 0.75, 0.20),
				Color(0.80, 0.40, 0.60), Color(0.90, 0.55, 0.15),
			]
			var bc = berry_colors.pick_random()
			for _di in range(randi_range(2, 5)):
				var dot = Polygon2D.new()
				var dx = bx + randf_range(-bush_w * 0.35, bush_w * 0.35)
				var dy = -bush_h * randf_range(0.2, 0.6)
				dot.polygon = PackedVector2Array([
					Vector2(dx - 1.5, dy - 1.5), Vector2(dx + 1.5, dy - 1.5),
					Vector2(dx + 1.5, dy + 1.5), Vector2(dx - 1.5, dy + 1.5)
				])
				dot.color = bc
				node.add_child(dot)

	_register_decoration(node, x, spread)

# ---------------------------------------------------------------------------
#  Civilian building  — house with depth shading, chimney, shutters, porch
# ---------------------------------------------------------------------------
func _add_civilian_building(x: float):
	var node = Node2D.new()
	node.position = Vector2(x, 0)

	var w = randf_range(40, 58)
	var h = randf_range(32, 46)
	var roof_h = randf_range(14, 20)

	var wall_colors = [
		Color(0.72, 0.65, 0.55), Color(0.68, 0.58, 0.48),
		Color(0.76, 0.70, 0.60), Color(0.82, 0.78, 0.68),
		Color(0.70, 0.62, 0.55), Color(0.85, 0.80, 0.72),
	]
	var wall_color: Color = wall_colors.pick_random()
	var wall_shadow = wall_color.darkened(0.18)
	var roof_colors = [
		Color(0.55, 0.22, 0.18), Color(0.50, 0.28, 0.20),
		Color(0.42, 0.25, 0.18), Color(0.35, 0.18, 0.14),
	]
	var roof_color: Color = roof_colors.pick_random()

	# Foundation
	var foundation = Polygon2D.new()
	foundation.polygon = PackedVector2Array([
		Vector2(-2, 0), Vector2(w + 2, 0), Vector2(w + 2, -4), Vector2(-2, -4)
	])
	foundation.color = Color(0.42, 0.40, 0.38)
	node.add_child(foundation)

	# Wall body
	var wall = Polygon2D.new()
	wall.polygon = PackedVector2Array([
		Vector2(0, -3), Vector2(w, -3), Vector2(w, -h), Vector2(0, -h)
	])
	wall.color = wall_color
	node.add_child(wall)

	# Side shadow (right wall darker for depth)
	var shadow_w = w * 0.2
	var shadow = Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(w - shadow_w, -3), Vector2(w, -3), Vector2(w, -h), Vector2(w - shadow_w, -h)
	])
	shadow.color = wall_shadow
	node.add_child(shadow)

	# Horizontal siding lines
	var siding_color = wall_color.darkened(0.08)
	var num_lines = int(h / 7)
	for li in range(num_lines):
		var ly = -4 - li * (h - 4) / max(num_lines, 1)
		var line = Polygon2D.new()
		line.polygon = PackedVector2Array([
			Vector2(1, ly), Vector2(w - 1, ly), Vector2(w - 1, ly - 1), Vector2(1, ly - 1)
		])
		line.color = siding_color
		node.add_child(line)

	# Roof (triangle) with ridge line
	var overhang = 6.0
	var roof = Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-overhang, -h), Vector2(w + overhang, -h), Vector2(w * 0.5, -h - roof_h)
	])
	roof.color = roof_color
	node.add_child(roof)

	# Roof shadow (left half slightly darker)
	var roof_shadow = Polygon2D.new()
	roof_shadow.polygon = PackedVector2Array([
		Vector2(w + overhang, -h), Vector2(w * 0.5, -h), Vector2(w * 0.5, -h - roof_h)
	])
	roof_shadow.color = roof_color.darkened(0.15)
	node.add_child(roof_shadow)

	# Roof ridge cap
	var ridge = Polygon2D.new()
	var rx = w * 0.5
	ridge.polygon = PackedVector2Array([
		Vector2(rx - 3, -h - roof_h + 1), Vector2(rx + 3, -h - roof_h + 1),
		Vector2(rx + 1, -h - roof_h - 2), Vector2(rx - 1, -h - roof_h - 2)
	])
	ridge.color = roof_color.darkened(0.25)
	node.add_child(ridge)

	# Chimney (50% chance)
	if randf() > 0.5:
		var chim_x = w * randf_range(0.65, 0.8)
		var chim_w = randf_range(6, 9)
		var chim_h = randf_range(12, 18)
		var chimney = Polygon2D.new()
		chimney.polygon = PackedVector2Array([
			Vector2(chim_x, -h - 4), Vector2(chim_x + chim_w, -h - 4),
			Vector2(chim_x + chim_w, -h - 4 - chim_h), Vector2(chim_x, -h - 4 - chim_h)
		])
		chimney.color = Color(0.48, 0.30, 0.25)
		node.add_child(chimney)
		# Chimney cap
		var cap = Polygon2D.new()
		cap.polygon = PackedVector2Array([
			Vector2(chim_x - 1.5, -h - 4 - chim_h), Vector2(chim_x + chim_w + 1.5, -h - 4 - chim_h),
			Vector2(chim_x + chim_w + 1.5, -h - 4 - chim_h - 2.5), Vector2(chim_x - 1.5, -h - 4 - chim_h - 2.5)
		])
		cap.color = Color(0.35, 0.22, 0.18)
		node.add_child(cap)

	# Door with frame and step
	var door_w = w * 0.20
	var door_h = h * 0.42
	var door_x = w * 0.5 - door_w * 0.5
	# Door step
	var step = Polygon2D.new()
	step.polygon = PackedVector2Array([
		Vector2(door_x - 3, -2), Vector2(door_x + door_w + 3, -2),
		Vector2(door_x + door_w + 3, -5), Vector2(door_x - 3, -5)
	])
	step.color = Color(0.50, 0.48, 0.44)
	node.add_child(step)
	# Door frame
	var frame = Polygon2D.new()
	frame.polygon = PackedVector2Array([
		Vector2(door_x - 2, -3), Vector2(door_x + door_w + 2, -3),
		Vector2(door_x + door_w + 2, -3 - door_h - 3), Vector2(door_x - 2, -3 - door_h - 3)
	])
	frame.color = Color(0.35, 0.28, 0.22)
	node.add_child(frame)
	# Door
	var door = Polygon2D.new()
	door.polygon = PackedVector2Array([
		Vector2(door_x, -3), Vector2(door_x + door_w, -3),
		Vector2(door_x + door_w, -3 - door_h), Vector2(door_x, -3 - door_h)
	])
	door.color = Color(0.30, 0.22, 0.16)
	node.add_child(door)
	# Doorknob
	var knob = Polygon2D.new()
	var kx = door_x + door_w * 0.75
	var ky = -3 - door_h * 0.5
	knob.polygon = PackedVector2Array([
		Vector2(kx - 1, ky - 1), Vector2(kx + 1, ky - 1),
		Vector2(kx + 1, ky + 1), Vector2(kx - 1, ky + 1)
	])
	knob.color = Color(0.75, 0.65, 0.30)
	node.add_child(knob)

	# Awning above door
	var awning = Polygon2D.new()
	awning.polygon = PackedVector2Array([
		Vector2(door_x - 4, -3 - door_h - 2),
		Vector2(door_x + door_w + 4, -3 - door_h - 2),
		Vector2(door_x + door_w + 6, -3 - door_h - 6),
		Vector2(door_x - 6, -3 - door_h - 6),
	])
	awning.color = roof_color.lightened(0.1)
	node.add_child(awning)

	# Windows with shutters and mullions
	var num_windows = 2 if w > 44 else 1
	var win_w = 8.0
	var win_h = 9.0
	var win_y = -h * 0.58
	var window_glow = Color(0.92, 0.85, 0.45, 0.9)
	var shutter_color = wall_color.darkened(0.30)
	var win_positions = [0.22, 0.72] if num_windows == 2 else [0.25]
	for wi_frac in win_positions:
		var wx = w * wi_frac - win_w * 0.5
		# Window frame
		var wf = Polygon2D.new()
		wf.polygon = PackedVector2Array([
			Vector2(wx - 1.5, win_y - 1.5), Vector2(wx + win_w + 1.5, win_y - 1.5),
			Vector2(wx + win_w + 1.5, win_y + win_h + 1.5), Vector2(wx - 1.5, win_y + win_h + 1.5)
		])
		wf.color = Color(0.35, 0.30, 0.25)
		node.add_child(wf)
		# Glass pane
		var win = Polygon2D.new()
		win.polygon = PackedVector2Array([
			Vector2(wx, win_y), Vector2(wx + win_w, win_y),
			Vector2(wx + win_w, win_y + win_h), Vector2(wx, win_y + win_h)
		])
		win.color = window_glow
		node.add_child(win)
		# Mullion cross (vertical)
		var mv = Polygon2D.new()
		mv.polygon = PackedVector2Array([
			Vector2(wx + win_w * 0.5 - 0.5, win_y), Vector2(wx + win_w * 0.5 + 0.5, win_y),
			Vector2(wx + win_w * 0.5 + 0.5, win_y + win_h), Vector2(wx + win_w * 0.5 - 0.5, win_y + win_h)
		])
		mv.color = Color(0.30, 0.25, 0.20)
		node.add_child(mv)
		# Mullion cross (horizontal)
		var mh = Polygon2D.new()
		mh.polygon = PackedVector2Array([
			Vector2(wx, win_y + win_h * 0.5 - 0.5), Vector2(wx + win_w, win_y + win_h * 0.5 - 0.5),
			Vector2(wx + win_w, win_y + win_h * 0.5 + 0.5), Vector2(wx, win_y + win_h * 0.5 + 0.5)
		])
		mh.color = Color(0.30, 0.25, 0.20)
		node.add_child(mh)
		# Left shutter
		var ls = Polygon2D.new()
		ls.polygon = PackedVector2Array([
			Vector2(wx - 5, win_y - 1), Vector2(wx - 1, win_y - 1),
			Vector2(wx - 1, win_y + win_h + 1), Vector2(wx - 5, win_y + win_h + 1)
		])
		ls.color = shutter_color
		node.add_child(ls)
		# Right shutter
		var rs = Polygon2D.new()
		rs.polygon = PackedVector2Array([
			Vector2(wx + win_w + 1, win_y - 1), Vector2(wx + win_w + 5, win_y - 1),
			Vector2(wx + win_w + 5, win_y + win_h + 1), Vector2(wx + win_w + 1, win_y + win_h + 1)
		])
		rs.color = shutter_color
		node.add_child(rs)
		# Window sill
		var sill = Polygon2D.new()
		sill.polygon = PackedVector2Array([
			Vector2(wx - 2, win_y + win_h + 1), Vector2(wx + win_w + 2, win_y + win_h + 1),
			Vector2(wx + win_w + 2, win_y + win_h + 3.5), Vector2(wx - 2, win_y + win_h + 3.5)
		])
		sill.color = Color(0.60, 0.58, 0.54)
		node.add_child(sill)

	_register_decoration(node, x, w)

# ---------------------------------------------------------------------------
#  Industry building  — factory with corrugated walls, sawtooth roof, pipes
# ---------------------------------------------------------------------------
func _add_industry_building(x: float):
	var node = Node2D.new()
	node.position = Vector2(x, 0)

	var w = randf_range(65, 105)
	var h = randf_range(42, 60)

	var body_colors = [
		Color(0.38, 0.40, 0.44), Color(0.42, 0.42, 0.46),
		Color(0.35, 0.37, 0.42), Color(0.40, 0.38, 0.36),
	]
	var body_color: Color = body_colors.pick_random()

	# Concrete foundation
	var foundation = Polygon2D.new()
	foundation.polygon = PackedVector2Array([
		Vector2(-3, 0), Vector2(w + 3, 0), Vector2(w + 3, -5), Vector2(-3, -5)
	])
	foundation.color = Color(0.45, 0.43, 0.40)
	node.add_child(foundation)

	# Main body
	var body = Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(0, -4), Vector2(w, -4), Vector2(w, -h), Vector2(0, -h)
	])
	body.color = body_color
	node.add_child(body)

	# Side shadow for depth
	var side_shadow = Polygon2D.new()
	var sw = w * 0.18
	side_shadow.polygon = PackedVector2Array([
		Vector2(w - sw, -4), Vector2(w, -4), Vector2(w, -h), Vector2(w - sw, -h)
	])
	side_shadow.color = body_color.darkened(0.15)
	node.add_child(side_shadow)

	# Corrugated wall texture (vertical stripes)
	var stripe_color_light = body_color.lightened(0.06)
	var stripe_color_dark = body_color.darkened(0.06)
	var stripe_w = 6.0
	var num_stripes = int(w / stripe_w)
	for si in range(num_stripes):
		var sx = si * stripe_w
		if si % 2 == 0:
			var stripe = Polygon2D.new()
			stripe.polygon = PackedVector2Array([
				Vector2(sx, -5), Vector2(sx + stripe_w * 0.5, -5),
				Vector2(sx + stripe_w * 0.5, -h + 1), Vector2(sx, -h + 1)
			])
			stripe.color = stripe_color_light
			node.add_child(stripe)

	# Sawtooth roof sections
	var num_teeth = randi_range(2, 4)
	var tooth_w = w / num_teeth
	var tooth_h = randf_range(8, 14)
	var roof_base_color = Color(0.32, 0.32, 0.34)
	var roof_glass_color = Color(0.55, 0.70, 0.80, 0.6)
	for ti in range(num_teeth):
		var tx = ti * tooth_w
		# Flat slope
		var tooth = Polygon2D.new()
		tooth.polygon = PackedVector2Array([
			Vector2(tx, -h), Vector2(tx + tooth_w, -h),
			Vector2(tx + tooth_w, -h - tooth_h), Vector2(tx, -h - 2)
		])
		tooth.color = roof_base_color
		node.add_child(tooth)
		# Glass panel (vertical face of sawtooth)
		var glass = Polygon2D.new()
		glass.polygon = PackedVector2Array([
			Vector2(tx + tooth_w - 0.5, -h),
			Vector2(tx + tooth_w + 0.5, -h),
			Vector2(tx + tooth_w + 0.5, -h - tooth_h),
			Vector2(tx + tooth_w - 0.5, -h - tooth_h)
		])
		glass.color = roof_glass_color
		node.add_child(glass)

	# Smokestack(s)
	var num_stacks = randi_range(1, 2)
	for si in range(num_stacks):
		var stack_w = randf_range(7, 11)
		var stack_h = randf_range(24, 40)
		var stack_x = w * (0.2 + si * 0.55) - stack_w * 0.5
		# Stack body
		var stack = Polygon2D.new()
		stack.polygon = PackedVector2Array([
			Vector2(stack_x, -h), Vector2(stack_x + stack_w, -h),
			Vector2(stack_x + stack_w, -h - stack_h), Vector2(stack_x, -h - stack_h)
		])
		stack.color = Color(0.32, 0.30, 0.28)
		node.add_child(stack)
		# Stack shadow strip
		var ss = Polygon2D.new()
		ss.polygon = PackedVector2Array([
			Vector2(stack_x + stack_w * 0.6, -h),
			Vector2(stack_x + stack_w, -h),
			Vector2(stack_x + stack_w, -h - stack_h),
			Vector2(stack_x + stack_w * 0.6, -h - stack_h)
		])
		ss.color = Color(0.26, 0.24, 0.22)
		node.add_child(ss)
		# Stack band (ring detail)
		for band_i in range(2):
			var by = -h - stack_h * (0.3 + band_i * 0.4)
			var band = Polygon2D.new()
			band.polygon = PackedVector2Array([
				Vector2(stack_x - 1, by), Vector2(stack_x + stack_w + 1, by),
				Vector2(stack_x + stack_w + 1, by - 2.5), Vector2(stack_x - 1, by - 2.5)
			])
			band.color = Color(0.38, 0.36, 0.34)
			node.add_child(band)
		# Red warning light on top
		var light = Polygon2D.new()
		var lx = stack_x + stack_w * 0.5
		var ly = -h - stack_h
		light.polygon = PackedVector2Array([
			Vector2(lx - 2.5, ly - 1), Vector2(lx + 2.5, ly - 1),
			Vector2(lx + 2.5, ly - 4), Vector2(lx - 2.5, ly - 4)
		])
		light.color = Color(1.0, 0.15, 0.1, 0.95)
		node.add_child(light)
		# Light glow
		var glow = Polygon2D.new()
		glow.polygon = PackedVector2Array([
			Vector2(lx - 5, ly - 0), Vector2(lx + 5, ly - 0),
			Vector2(lx + 5, ly - 6), Vector2(lx - 5, ly - 6)
		])
		glow.color = Color(1.0, 0.2, 0.1, 0.15)
		node.add_child(glow)

	# Pipes running along the side
	var num_pipes = randi_range(1, 3)
	for pi in range(num_pipes):
		var py = -h * (0.25 + pi * 0.22)
		var pipe = Polygon2D.new()
		pipe.polygon = PackedVector2Array([
			Vector2(-4, py), Vector2(w * 0.4, py),
			Vector2(w * 0.4, py - 3), Vector2(-4, py - 3)
		])
		pipe.color = Color(0.50, 0.48, 0.42)
		node.add_child(pipe)
		# Pipe shadow
		var ps = Polygon2D.new()
		ps.polygon = PackedVector2Array([
			Vector2(-4, py + 1.5), Vector2(w * 0.4, py + 1.5),
			Vector2(w * 0.4, py), Vector2(-4, py)
		])
		ps.color = Color(0.28, 0.27, 0.25, 0.4)
		node.add_child(ps)

	# Industrial windows — row with frames
	var num_wins = int(w / 18)
	var win_w = 9.0
	var win_h = 12.0
	var win_y = -h * 0.52
	for wi in range(num_wins):
		var wx = 12 + wi * (w - 24) / max(num_wins - 1, 1) - win_w * 0.5
		# Frame
		var wf = Polygon2D.new()
		wf.polygon = PackedVector2Array([
			Vector2(wx - 1.5, win_y - 1.5), Vector2(wx + win_w + 1.5, win_y - 1.5),
			Vector2(wx + win_w + 1.5, win_y + win_h + 1.5), Vector2(wx - 1.5, win_y + win_h + 1.5)
		])
		wf.color = Color(0.28, 0.28, 0.30)
		node.add_child(wf)
		# Glass
		var win = Polygon2D.new()
		win.polygon = PackedVector2Array([
			Vector2(wx, win_y), Vector2(wx + win_w, win_y),
			Vector2(wx + win_w, win_y + win_h), Vector2(wx, win_y + win_h)
		])
		win.color = Color(0.55, 0.65, 0.75, 0.7)
		node.add_child(win)
		# Horizontal divider
		var hd = Polygon2D.new()
		hd.polygon = PackedVector2Array([
			Vector2(wx, win_y + win_h * 0.5 - 0.5), Vector2(wx + win_w, win_y + win_h * 0.5 - 0.5),
			Vector2(wx + win_w, win_y + win_h * 0.5 + 0.5), Vector2(wx, win_y + win_h * 0.5 + 0.5)
		])
		hd.color = Color(0.28, 0.28, 0.30)
		node.add_child(hd)

	# Loading dock with hazard stripes
	var dock_w = w * 0.3
	var dock_h = h * 0.32
	var dock_x = w * 0.62
	var dock = Polygon2D.new()
	dock.polygon = PackedVector2Array([
		Vector2(dock_x, -4), Vector2(dock_x + dock_w, -4),
		Vector2(dock_x + dock_w, -4 - dock_h), Vector2(dock_x, -4 - dock_h)
	])
	dock.color = Color(0.18, 0.18, 0.20)
	node.add_child(dock)
	# Hazard stripe bar above dock
	var hazard_y = -4 - dock_h
	var num_hz = int(dock_w / 8)
	for hi in range(num_hz):
		if hi % 2 == 0:
			var hx = dock_x + hi * (dock_w / num_hz)
			var stripe_len = dock_w / num_hz
			var hz = Polygon2D.new()
			hz.polygon = PackedVector2Array([
				Vector2(hx, hazard_y), Vector2(hx + stripe_len, hazard_y),
				Vector2(hx + stripe_len, hazard_y - 3), Vector2(hx, hazard_y - 3)
			])
			hz.color = Color(0.85, 0.70, 0.10, 0.9)
			node.add_child(hz)

	_register_decoration(node, x, w)

# ---------------------------------------------------------------------------
#  Bridge — suspension-style with cables, road markings, massive pillars
# ---------------------------------------------------------------------------
func _add_bridge(x: float):
	var node = Node2D.new()
	node.position = Vector2(x, 0)

	var span = randf_range(80, 120)
	var deck_h = 5.0
	var deck_y = -20.0
	var pillar_w = 10.0
	var tower_h = 50.0

	var bridge_color = Color(0.48, 0.45, 0.40)
	var pillar_color = Color(0.40, 0.38, 0.35)
	var pillar_shadow = Color(0.32, 0.30, 0.28)
	var railing_color = Color(0.55, 0.52, 0.48)
	var cable_color = Color(0.42, 0.40, 0.38, 0.8)
	var road_color = Color(0.28, 0.28, 0.27)
	var marking_color = Color(0.85, 0.82, 0.70, 0.7)

	# Road approach ramps
	var ramp_len = 25.0
	var left_ramp = Polygon2D.new()
	left_ramp.polygon = PackedVector2Array([
		Vector2(-ramp_len, 0), Vector2(0, 0),
		Vector2(0, deck_y), Vector2(-ramp_len, -3)
	])
	left_ramp.color = road_color
	node.add_child(left_ramp)
	var right_ramp = Polygon2D.new()
	right_ramp.polygon = PackedVector2Array([
		Vector2(span, 0), Vector2(span + ramp_len, 0),
		Vector2(span + ramp_len, -3), Vector2(span, deck_y)
	])
	right_ramp.color = road_color
	node.add_child(right_ramp)

	# Left tower
	var lt = Polygon2D.new()
	lt.polygon = PackedVector2Array([
		Vector2(pillar_w, 0), Vector2(pillar_w * 2, 0),
		Vector2(pillar_w * 2, -tower_h), Vector2(pillar_w, -tower_h)
	])
	lt.color = pillar_color
	node.add_child(lt)
	# Left tower shadow
	var lts = Polygon2D.new()
	lts.polygon = PackedVector2Array([
		Vector2(pillar_w * 1.5, 0), Vector2(pillar_w * 2, 0),
		Vector2(pillar_w * 2, -tower_h), Vector2(pillar_w * 1.5, -tower_h)
	])
	lts.color = pillar_shadow
	node.add_child(lts)
	# Left tower cap
	var ltc = Polygon2D.new()
	ltc.polygon = PackedVector2Array([
		Vector2(pillar_w - 2, -tower_h), Vector2(pillar_w * 2 + 2, -tower_h),
		Vector2(pillar_w * 2 + 2, -tower_h - 4), Vector2(pillar_w - 2, -tower_h - 4)
	])
	ltc.color = pillar_shadow
	node.add_child(ltc)

	# Right tower
	var rt_x = span - pillar_w * 2
	var rt = Polygon2D.new()
	rt.polygon = PackedVector2Array([
		Vector2(rt_x, 0), Vector2(rt_x + pillar_w, 0),
		Vector2(rt_x + pillar_w, -tower_h), Vector2(rt_x, -tower_h)
	])
	rt.color = pillar_color
	node.add_child(rt)
	var rts = Polygon2D.new()
	rts.polygon = PackedVector2Array([
		Vector2(rt_x + pillar_w * 0.5, 0), Vector2(rt_x + pillar_w, 0),
		Vector2(rt_x + pillar_w, -tower_h), Vector2(rt_x + pillar_w * 0.5, -tower_h)
	])
	rts.color = pillar_shadow
	node.add_child(rts)
	var rtc = Polygon2D.new()
	rtc.polygon = PackedVector2Array([
		Vector2(rt_x - 2, -tower_h), Vector2(rt_x + pillar_w + 2, -tower_h),
		Vector2(rt_x + pillar_w + 2, -tower_h - 4), Vector2(rt_x - 2, -tower_h - 4)
	])
	rtc.color = pillar_shadow
	node.add_child(rtc)

	# Deck
	var deck = Polygon2D.new()
	deck.polygon = PackedVector2Array([
		Vector2(0, deck_y), Vector2(span, deck_y),
		Vector2(span, deck_y - deck_h), Vector2(0, deck_y - deck_h)
	])
	deck.color = bridge_color
	node.add_child(deck)

	# Deck underside shadow
	var underside = Polygon2D.new()
	underside.polygon = PackedVector2Array([
		Vector2(2, deck_y), Vector2(span - 2, deck_y),
		Vector2(span - 2, deck_y + 3), Vector2(2, deck_y + 3)
	])
	underside.color = Color(0.22, 0.20, 0.18, 0.5)
	node.add_child(underside)

	# Road surface on deck
	var road = Polygon2D.new()
	road.polygon = PackedVector2Array([
		Vector2(2, deck_y - deck_h), Vector2(span - 2, deck_y - deck_h),
		Vector2(span - 2, deck_y - deck_h - 2), Vector2(2, deck_y - deck_h - 2)
	])
	road.color = road_color
	node.add_child(road)

	# Center road marking (dashed)
	var dash_len = 8.0
	var gap_len = 6.0
	var mark_y = deck_y - deck_h - 0.5
	var cx = 5.0
	while cx < span - 5:
		var dash = Polygon2D.new()
		dash.polygon = PackedVector2Array([
			Vector2(cx, mark_y), Vector2(cx + dash_len, mark_y),
			Vector2(cx + dash_len, mark_y - 1.5), Vector2(cx, mark_y - 1.5)
		])
		dash.color = marking_color
		node.add_child(dash)
		cx += dash_len + gap_len

	# Edge markings (solid lines)
	for edge_x_offset in [3.0, span - 4.5]:
		var edge = Polygon2D.new()
		edge.polygon = PackedVector2Array([
			Vector2(edge_x_offset, deck_y - deck_h), Vector2(edge_x_offset + 1.5, deck_y - deck_h),
			Vector2(edge_x_offset + 1.5, deck_y - deck_h - 2), Vector2(edge_x_offset, deck_y - deck_h - 2)
		])
		edge.color = marking_color
		node.add_child(edge)

	# Suspension cables from towers to deck
	var left_tower_top = Vector2(pillar_w * 1.5, -tower_h - 3)
	var right_tower_top = Vector2(rt_x + pillar_w * 0.5, -tower_h - 3)
	var cable_segments = 10
	# Left main cable (catenary curve from left tower to right tower)
	for ci in range(cable_segments):
		var t0 = float(ci) / cable_segments
		var t1 = float(ci + 1) / cable_segments
		var x0 = lerp(left_tower_top.x, right_tower_top.x, t0)
		var x1 = lerp(left_tower_top.x, right_tower_top.x, t1)
		# Parabolic sag
		var sag0 = 4.0 * (tower_h - 25) * t0 * (1.0 - t0)
		var sag1 = 4.0 * (tower_h - 25) * t1 * (1.0 - t1)
		var y0 = left_tower_top.y + sag0
		var y1 = left_tower_top.y + sag1
		var cable_seg = Polygon2D.new()
		cable_seg.polygon = PackedVector2Array([
			Vector2(x0, y0), Vector2(x1, y1),
			Vector2(x1, y1 - 1.5), Vector2(x0, y0 - 1.5)
		])
		cable_seg.color = cable_color
		node.add_child(cable_seg)

	# Vertical suspender cables from main cable to deck
	var num_suspenders = int(span / 12)
	for si in range(1, num_suspenders):
		var t = float(si) / num_suspenders
		var sx = lerp(left_tower_top.x, right_tower_top.x, t)
		var sag = 4.0 * (tower_h - 25) * t * (1.0 - t)
		var sy_top = left_tower_top.y + sag
		var sy_bottom = deck_y - deck_h
		if sy_top < sy_bottom:
			var susp = Polygon2D.new()
			susp.polygon = PackedVector2Array([
				Vector2(sx - 0.5, sy_top), Vector2(sx + 0.5, sy_top),
				Vector2(sx + 0.5, sy_bottom), Vector2(sx - 0.5, sy_bottom)
			])
			susp.color = cable_color
			node.add_child(susp)

	# Railings — vertical posts with top bar
	var num_posts = int(span / 12)
	var post_h = 10.0
	for pi in range(num_posts + 1):
		var px = pi * span / max(num_posts, 1)
		var post = Polygon2D.new()
		post.polygon = PackedVector2Array([
			Vector2(px - 1, deck_y - deck_h - 2),
			Vector2(px + 1, deck_y - deck_h - 2),
			Vector2(px + 1, deck_y - deck_h - 2 - post_h),
			Vector2(px - 1, deck_y - deck_h - 2 - post_h)
		])
		post.color = railing_color
		node.add_child(post)

	# Top rail bars (both sides)
	var rail_y = deck_y - deck_h - 2 - post_h
	var rail = Polygon2D.new()
	rail.polygon = PackedVector2Array([
		Vector2(0, rail_y), Vector2(span, rail_y),
		Vector2(span, rail_y - 2), Vector2(0, rail_y - 2)
	])
	rail.color = railing_color
	node.add_child(rail)

	# Arch under deck (multiple arches)
	var num_arches = 2
	for ai in range(num_arches):
		var arch = Polygon2D.new()
		var arch_pts = PackedVector2Array()
		var arch_cx = span * (0.33 + ai * 0.34)
		var arch_rx = span * 0.2
		var arch_steps = 14
		for asi in range(arch_steps + 1):
			var angle = PI * asi / arch_steps
			arch_pts.append(Vector2(
				arch_cx + cos(angle) * arch_rx,
				-sin(angle) * 16.0
			))
		arch_pts.append(Vector2(arch_cx + arch_rx, 0))
		arch_pts.append(Vector2(arch_cx - arch_rx, 0))
		arch.polygon = arch_pts
		arch.color = Color(0.22, 0.20, 0.18, 0.4)
		node.add_child(arch)

	_register_decoration(node, x, span + ramp_len * 2)

# ---------------------------------------------------------------------------
#  Soldier group — detailed pixel soldiers with weapons, gear, sandbags
# ---------------------------------------------------------------------------
func _add_soldier_group(x: float):
	var node = Node2D.new()
	node.position = Vector2(x, 0)

	var count = randi_range(2, 5)
	var spread = count * 14.0

	var uniform_colors = [
		Color(0.25, 0.32, 0.20), Color(0.28, 0.30, 0.22),
		Color(0.22, 0.28, 0.20), Color(0.30, 0.33, 0.24),
	]
	var skin_tones = [
		Color(0.72, 0.58, 0.45), Color(0.68, 0.52, 0.38),
		Color(0.78, 0.62, 0.48), Color(0.60, 0.45, 0.32),
	]
	var helmet_color = Color(0.22, 0.26, 0.18)
	var boot_color = Color(0.18, 0.15, 0.12)
	var weapon_color = Color(0.25, 0.22, 0.18)
	var gear_color = Color(0.30, 0.28, 0.22)

	# Maybe add sandbag emplacement (40% chance)
	var has_sandbags = randf() < 0.4
	if has_sandbags:
		var sb_x = spread * 0.3
		# Sandbag stack (3 rows)
		for row in range(3):
			var bags_in_row = 3 - row
			for bi in range(bags_in_row):
				var bx = sb_x + bi * 10 - bags_in_row * 5 + row * 3
				var by = -row * 5
				var bag = Polygon2D.new()
				bag.polygon = PackedVector2Array([
					Vector2(bx, by), Vector2(bx + 9, by),
					Vector2(bx + 8, by - 4.5), Vector2(bx + 1, by - 4.5)
				])
				bag.color = Color(0.52, 0.46, 0.32).darkened(row * 0.05)
				node.add_child(bag)
				# Bag tie/seam
				var seam = Polygon2D.new()
				seam.polygon = PackedVector2Array([
					Vector2(bx + 4, by - 1), Vector2(bx + 5, by - 1),
					Vector2(bx + 5, by - 3.5), Vector2(bx + 4, by - 3.5)
				])
				seam.color = Color(0.42, 0.38, 0.26)
				node.add_child(seam)

	# Maybe add a flag (30% chance)
	if randf() < 0.3:
		var flag_x = spread * randf_range(0.6, 0.9)
		# Pole
		var pole = Polygon2D.new()
		pole.polygon = PackedVector2Array([
			Vector2(flag_x - 0.8, 0), Vector2(flag_x + 0.8, 0),
			Vector2(flag_x + 0.8, -35), Vector2(flag_x - 0.8, -35)
		])
		pole.color = Color(0.45, 0.42, 0.38)
		node.add_child(pole)
		# Flag (small pennant)
		var flag = Polygon2D.new()
		var flag_colors = [
			Color(0.15, 0.35, 0.55), Color(0.55, 0.15, 0.15),
			Color(0.20, 0.40, 0.20),
		]
		flag.polygon = PackedVector2Array([
			Vector2(flag_x + 1, -35), Vector2(flag_x + 16, -32),
			Vector2(flag_x + 1, -28)
		])
		flag.color = flag_colors.pick_random()
		node.add_child(flag)

	for si in range(count):
		var sx = si * randf_range(10, 16) + (15 if has_sandbags else 0)
		var skin_color: Color = skin_tones.pick_random()
		var uni_color: Color = uniform_colors.pick_random()

		var soldier = Node2D.new()
		soldier.position = Vector2(sx, 0)

		# Boots (angled slightly)
		var left_boot = Polygon2D.new()
		left_boot.polygon = PackedVector2Array([
			Vector2(-3, 0), Vector2(-0.5, 0), Vector2(-0.5, -4), Vector2(-3, -3.5)
		])
		left_boot.color = boot_color
		soldier.add_child(left_boot)
		var right_boot = Polygon2D.new()
		right_boot.polygon = PackedVector2Array([
			Vector2(0.5, 0), Vector2(3, 0), Vector2(3, -3.5), Vector2(0.5, -4)
		])
		right_boot.color = boot_color
		soldier.add_child(right_boot)

		# Legs (pants)
		var left_leg = Polygon2D.new()
		left_leg.polygon = PackedVector2Array([
			Vector2(-2.5, -3.5), Vector2(-0.5, -4), Vector2(-0.5, -7), Vector2(-2.5, -7)
		])
		left_leg.color = uni_color.darkened(0.12)
		soldier.add_child(left_leg)
		var right_leg = Polygon2D.new()
		right_leg.polygon = PackedVector2Array([
			Vector2(0.5, -4), Vector2(2.5, -3.5), Vector2(2.5, -7), Vector2(0.5, -7)
		])
		right_leg.color = uni_color.darkened(0.12)
		soldier.add_child(right_leg)

		# Torso
		var body_h = randf_range(7, 9)
		var torso = Polygon2D.new()
		torso.polygon = PackedVector2Array([
			Vector2(-3, -7), Vector2(3, -7), Vector2(2.5, -7 - body_h), Vector2(-2.5, -7 - body_h)
		])
		torso.color = uni_color
		soldier.add_child(torso)

		# Belt
		var belt = Polygon2D.new()
		belt.polygon = PackedVector2Array([
			Vector2(-3.2, -7.5), Vector2(3.2, -7.5), Vector2(3.2, -9), Vector2(-3.2, -9)
		])
		belt.color = Color(0.22, 0.20, 0.16)
		soldier.add_child(belt)

		# Arms (holding weapon)
		var arm_y = -7 - body_h * 0.4
		var left_arm = Polygon2D.new()
		left_arm.polygon = PackedVector2Array([
			Vector2(-3, arm_y + 2), Vector2(-5.5, arm_y),
			Vector2(-5, arm_y - 1.5), Vector2(-2.5, arm_y + 0.5)
		])
		left_arm.color = uni_color.darkened(0.08)
		soldier.add_child(left_arm)
		var right_arm = Polygon2D.new()
		right_arm.polygon = PackedVector2Array([
			Vector2(3, arm_y + 2), Vector2(5.5, arm_y),
			Vector2(5, arm_y - 1.5), Vector2(2.5, arm_y + 0.5)
		])
		right_arm.color = uni_color.darkened(0.08)
		soldier.add_child(right_arm)

		# Weapon (rifle)
		var weap = Polygon2D.new()
		var wy = arm_y - 0.5
		weap.polygon = PackedVector2Array([
			Vector2(4.5, wy + 1), Vector2(12, wy - 2),
			Vector2(12, wy - 3.5), Vector2(4.5, wy - 0.5)
		])
		weap.color = weapon_color
		soldier.add_child(weap)

		# Backpack (on some soldiers)
		if randf() < 0.5:
			var pack = Polygon2D.new()
			var pack_y = -7 - body_h * 0.3
			pack.polygon = PackedVector2Array([
				Vector2(-5, pack_y + 3), Vector2(-3, pack_y + 3),
				Vector2(-3, pack_y - 3), Vector2(-5, pack_y - 3)
			])
			pack.color = gear_color
			soldier.add_child(pack)

		# Neck
		var neck_y = -7 - body_h
		var neck = Polygon2D.new()
		neck.polygon = PackedVector2Array([
			Vector2(-1.2, neck_y), Vector2(1.2, neck_y),
			Vector2(1.2, neck_y - 2), Vector2(-1.2, neck_y - 2)
		])
		neck.color = skin_color
		soldier.add_child(neck)

		# Head
		var head_y = neck_y - 2
		var head = Polygon2D.new()
		head.polygon = PackedVector2Array([
			Vector2(-2.5, head_y), Vector2(2.5, head_y),
			Vector2(2.5, head_y - 4), Vector2(-2.5, head_y - 4)
		])
		head.color = skin_color
		soldier.add_child(head)

		# Helmet (with brim)
		var hy = head_y - 3.5
		var helmet = Polygon2D.new()
		helmet.polygon = PackedVector2Array([
			Vector2(-3.5, hy + 1), Vector2(3.5, hy + 1),
			Vector2(3, hy - 2.5), Vector2(-3, hy - 2.5)
		])
		helmet.color = helmet_color
		soldier.add_child(helmet)
		# Helmet band
		var hband = Polygon2D.new()
		hband.polygon = PackedVector2Array([
			Vector2(-3.3, hy + 1), Vector2(3.3, hy + 1),
			Vector2(3.3, hy - 0.2), Vector2(-3.3, hy - 0.2)
		])
		hband.color = Color(0.35, 0.32, 0.26)
		soldier.add_child(hband)

		node.add_child(soldier)

	_register_decoration(node, x, spread + (15 if has_sandbags else 0))
