@tool
class_name SeamlessRoomValidator
extends RefCounted

## 编辑期静态校验。
##
## 只校验"几何与资源是否自洽"，不校验连通性、可达性、缝隙或门 ——
## 房间之间怎么来往是游戏层的事，插件不做判断。
## 接缝过渡配置同理：只校验关系 / 参数是否自洽，不判断美术效果。

static func validate(config: SeamlessRoomConfig) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if config == null:
		errors.append(SeamlessRoomI18n.t("Config is empty"))
		return { "errors": errors, "warnings": warnings }

	if config.schema_version != SeamlessRoomConfig.SCHEMA_VERSION:
		warnings.append(SeamlessRoomI18n.tf(
			"schema_version=%d, this build is %d; verify whether migration is required",
			[config.schema_version, SeamlessRoomConfig.SCHEMA_VERSION]))
	if config.cell_size.x <= 0.0 or config.cell_size.y <= 0.0:
		errors.append(SeamlessRoomI18n.t("cell_size must be positive"))

	var s := config.streaming
	if s == null:
		errors.append(SeamlessRoomI18n.t("streaming settings are missing"))
	else:
		if s.mount_distance <= 0.0:
			errors.append(SeamlessRoomI18n.t("mount_distance must be greater than 0"))
		if not (s.mount_distance < s.sleep_distance and s.sleep_distance < s.unload_distance):
			errors.append(SeamlessRoomI18n.t(
				"Requires mount_distance < sleep_distance < unload_distance"))
		# bucket_size <= 0 表示自动推导；NaN / INF 才是非法（NaN < INF 恒为 false）。
		if not (s.bucket_size < INF):
			errors.append(SeamlessRoomI18n.t(
				"bucket_size must not be NaN / INF (<= 0 means auto)"))
		elif s.bucket_size > 0.0 \
				and s.mount_distance > SeamlessRoomLayout.max_query_radius(s.bucket_size):
			warnings.append(SeamlessRoomI18n.t(
				"mount_distance exceeds the bucket budget for a single neighborhood query; the radius will be clamped at runtime"))
		# max_mounted <= 0 是「自动派生」的合法取值，只有负数才是错误。
		if s.max_mounted < 0:
			errors.append(SeamlessRoomI18n.t(
				"max_mounted must not be negative (<= 0 means auto)"))
		if s.tick <= 0.0:
			errors.append(SeamlessRoomI18n.t("tick must be greater than 0"))
		if s.max_mounted > 0 and s.max_mounted < 3:
			warnings.append(SeamlessRoomI18n.t(
				"max_mounted is small and may conflict with mount_distance, causing repeated sleep/wake cycles"))

	if config.rooms.is_empty():
		errors.append(SeamlessRoomI18n.t("rooms is empty"))

	var seen: Dictionary = {}
	var rects: Array = []
	for i in range(config.rooms.size()):
		var r = config.rooms[i]
		if not (r is SeamlessRoomPlacement):
			errors.append(SeamlessRoomI18n.tf(
				"rooms[%d] is not a SeamlessRoomPlacement", [i]))
			continue
		var p: SeamlessRoomPlacement = r
		var tag := "rooms[%d]" % i
		if p.id == &"":
			errors.append(SeamlessRoomI18n.tf("%s is missing id", [tag]))
		elif seen.has(p.id):
			errors.append(SeamlessRoomI18n.tf("Duplicate id: %s", [p.id]))
		else:
			seen[p.id] = true
		if p.scene == null:
			errors.append(SeamlessRoomI18n.tf("%s (%s) has no scene", [tag, p.id]))
		if p.cells.size.x <= 0 or p.cells.size.y <= 0:
			errors.append(SeamlessRoomI18n.tf(
				"%s (%s) cells.size must be positive", [tag, p.id]))
		rects.append(p.cells)

	# 格区间两两不重叠。按 x 排序后扫描：后一个的左边界一旦越过当前右边界，
	# 后面都不可能相交，可提前 break（正常地图退化成接近 O(N log N)）。
	var sorted_rects := rects.duplicate()
	sorted_rects.sort_custom(func(a, b): return a.position.x < b.position.x)
	for a in range(sorted_rects.size()):
		var ra: Rect2i = sorted_rects[a]
		for b in range(a + 1, sorted_rects.size()):
			var rb: Rect2i = sorted_rects[b]
			if rb.position.x >= ra.end.x:
				break
			if ra.intersects(rb):
				errors.append(SeamlessRoomI18n.tf(
					"Room cells overlap: %s and %s", [ra, rb]))

	_validate_seams(config, errors, warnings)

	return { "errors": errors, "warnings": warnings }


## 接缝过渡配置校验：只校验关系与参数是否自洽，不判断美术是否合适。
## 失效的共享边只报 WARN —— 地图编辑时房间会短暂不对齐，不应阻断运行。
static func _validate_seams(config: SeamlessRoomConfig,
		errors: Array[String], warnings: Array[String]) -> void:
	var seams: Array = []
	if config.get("seams") is Array:
		seams = config.seams
	if seams.is_empty():
		return
	var layout := SeamlessRoomLayout.new(config)
	var by_key := {}
	for e in layout.seams():
		by_key[e["key"]] = e
	var seen := {}
	for i in range(seams.size()):
		var raw = seams[i]
		var tag := "seams[%d]" % i
		if not (raw is SeamlessRoomSeam):
			errors.append(SeamlessRoomI18n.tf(
					"seams[%d] is not a SeamlessRoomSeam", [i]))
			continue
		var s: SeamlessRoomSeam = raw
		if s.left == &"" or s.right == &"" or s.left == s.right:
			errors.append(SeamlessRoomI18n.tf(
					"%s has missing or identical room ids", [tag]))
		if s.axis != SeamlessRoomSeam.AXIS_X and s.axis != SeamlessRoomSeam.AXIS_Y:
			errors.append(SeamlessRoomI18n.tf("%s has an invalid axis", [tag]))
		if s.width_ratio <= 0.0 or s.core < 0.0 \
				or s.feather_min <= 0.0 or s.feather_max <= 0.0:
			errors.append(SeamlessRoomI18n.tf(
					"%s has invalid width/core/feather parameters", [tag]))
		var key := s.key()
		if seen.has(key):
			errors.append(SeamlessRoomI18n.tf("Duplicate seam key: %s", [key]))
		else:
			seen[key] = true
		if s.material_override != null:
			if s.material_override.shader == null:
				warnings.append(SeamlessRoomI18n.tf(
						"%s material_override has no shader; default shader will be used", [tag]))
			elif s.material_override.shader.code.find("blend_premul_alpha") == -1:
				warnings.append(SeamlessRoomI18n.tf(
						"%s material_override does not use blend_premul_alpha; corner blending will differ", [tag]))
		if not s.enabled:
			continue
		if not layout.has_room(s.left) or not layout.has_room(s.right):
			warnings.append(SeamlessRoomI18n.tf(
					"%s references a room that is not on the map", [tag]))
		elif not by_key.has(key):
			warnings.append(SeamlessRoomI18n.tf(
					"%s no longer matches a shared edge (rooms moved or resized)", [tag]))
		elif by_key[key]["span"] <= 0.0:
			warnings.append(SeamlessRoomI18n.tf(
					"%s shared edge has zero span", [tag]))


static func format(result: Dictionary) -> String:
	var lines: Array[String] = []
	for e in result.get("errors", []):
		lines.append("ERROR  " + e)
	for w in result.get("warnings", []):
		lines.append("WARN   " + w)
	if lines.is_empty():
		lines.append("OK     " + SeamlessRoomI18n.t("Config is valid"))
	return "\n".join(PackedStringArray(lines))
