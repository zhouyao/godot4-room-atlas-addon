@tool
class_name SeamlessRoomValidator
extends RefCounted

## 编辑期静态校验。
##
## 只校验"几何与资源是否自洽"，不校验连通性、可达性、缝隙或门 ——
## 房间之间怎么来往是游戏层的事，插件不做判断。

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

	return { "errors": errors, "warnings": warnings }


static func format(result: Dictionary) -> String:
	var lines: Array[String] = []
	for e in result.get("errors", []):
		lines.append("ERROR  " + e)
	for w in result.get("warnings", []):
		lines.append("WARN   " + w)
	if lines.is_empty():
		lines.append("OK     " + SeamlessRoomI18n.t("Config is valid"))
	return "\n".join(PackedStringArray(lines))
