@tool
class_name RoomAtlasValidator
extends RefCounted

## 编辑期静态校验。
##
## 只校验"几何与资源是否自洽"，不校验连通性、可达性、缝隙或门 ——
## 房间之间怎么来往是游戏层的事，插件不做判断。

static func validate(config: RoomAtlasConfig) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if config == null:
		errors.append("配置为空")
		return { "errors": errors, "warnings": warnings }

	if config.schema_version != RoomAtlasConfig.SCHEMA_VERSION:
		warnings.append("schema_version=%d，当前实现为 %d，请确认是否需要迁移" % [
			config.schema_version, RoomAtlasConfig.SCHEMA_VERSION
		])
	if config.cell_size.x <= 0.0 or config.cell_size.y <= 0.0:
		errors.append("cell_size 必须为正数")

	var s := config.streaming
	if s == null:
		errors.append("缺少 streaming 设置")
	else:
		if s.mount_distance <= 0.0:
			errors.append("mount_distance 必须大于 0")
		if not (s.mount_distance < s.sleep_distance and s.sleep_distance < s.unload_distance):
			errors.append("需满足 mount_distance < sleep_distance < unload_distance")
		# bucket_size <= 0 表示自动推导；NaN / INF 才是非法（NaN < INF 恒为 false）。
		if not (s.bucket_size < INF):
			errors.append("bucket_size 不能是 NaN / INF（<= 0 表示自动推导）")
		elif s.bucket_size > 0.0 \
				and s.mount_distance > RoomAtlasLayout.max_query_radius(s.bucket_size):
			warnings.append("mount_distance 超出单次邻域查询的桶预算，运行时会截断半径")
		# max_mounted <= 0 是「自动派生」的合法取值，只有负数才是错误。
		if s.max_mounted < 0:
			errors.append("max_mounted 不能为负数（<= 0 表示自动派生）")
		if s.tick <= 0.0:
			errors.append("tick 必须大于 0")
		if s.max_mounted > 0 and s.max_mounted < 3:
			warnings.append("max_mounted 偏小，可能与 mount_distance 冲突导致反复休眠/唤醒")

	if config.rooms.is_empty():
		errors.append("rooms 为空")

	var seen: Dictionary = {}
	var rects: Array = []
	for i in range(config.rooms.size()):
		var r = config.rooms[i]
		if not (r is RoomAtlasPlacement):
			errors.append("rooms[%d] 不是 RoomAtlasPlacement" % i)
			continue
		var p: RoomAtlasPlacement = r
		var tag := "rooms[%d]" % i
		if p.id == &"":
			errors.append("%s 缺少 id" % tag)
		elif seen.has(p.id):
			errors.append("id 重复：%s" % p.id)
		else:
			seen[p.id] = true
		if p.scene == null:
			errors.append("%s (%s) 未指定 scene" % [tag, p.id])
		if p.cells.size.x <= 0 or p.cells.size.y <= 0:
			errors.append("%s (%s) 的 cells.size 必须为正" % [tag, p.id])
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
				errors.append("房间格区间重叠：%s 与 %s" % [ra, rb])

	return { "errors": errors, "warnings": warnings }


static func format(result: Dictionary) -> String:
	var lines: Array[String] = []
	for e in result.get("errors", []):
		lines.append("ERROR  " + e)
	for w in result.get("warnings", []):
		lines.append("WARN   " + w)
	if lines.is_empty():
		lines.append("OK     配置有效")
	return "\n".join(PackedStringArray(lines))
