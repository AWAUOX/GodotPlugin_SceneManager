# long_scene_manager.gd
extends Node

# 全局场景管理器插件
# 支持自定义加载屏幕的场景切换、预加载和LRU缓存
# 场景树和缓存分离设计:场景实例要么在场景树中，要么在缓存中

# ==================== 常量和枚举 ====================

const DEFAULT_LOAD_SCREEN_PATH = "res://addons/long_scene_manager/ui/loading_screen/GDscript/loading_black_screen.tscn"

enum LoadState {
	NOT_LOADED,
	LOADING,
	LOADED,
	INSTANTIATED
}

# ==================== 信号定义 ====================

signal scene_preload_started(scene_path: String)
signal scene_preload_completed(scene_path: String)
signal scene_switch_started(from_scene: String, to_scene: String)
signal scene_switch_completed(scene_path: String)
signal scene_cached(scene_path: String)
signal scene_removed_from_cache(scene_path: String)
signal load_screen_shown(load_screen_instance: Node)
signal load_screen_hidden(load_screen_instance: Node)

# ==================== 导出变量 ====================

@export_category("场景管理器全局配置")
@export_range(1, 20) var max_cache_size: int = 8
@export_range(1, 50) var max_preload_resource_cache_size: int = 20  # 预加载资源缓存最大容量
@export var use_async_loading: bool = true
@export var always_use_default_load_screen: bool = false

# ==================== 内部状态变量 ====================

var current_scene: Node = null
var current_scene_path: String = ""
var previous_scene_path: String = ""

var default_load_screen: Node = null
var active_load_screen: Node = null

var loading_scene_path: String = ""
var loading_state: LoadState = LoadState.NOT_LOADED
var loading_resource: PackedScene = null

var scene_cache: Dictionary = {}  # 存储从场景树移除的节点实例
var cache_access_order: Array = []  # LRU缓存访问顺序记录

# 新增:预加载资源缓存，存储预加载的PackedScene资源
var preload_resource_cache: Dictionary = {}
var preload_resource_cache_access_order: Array = []  # 预加载资源缓存LRU访问顺序记录

class CachedScene:
	var scene_instance: Node  # 缓存的节点实例
	var cached_time: float    # 缓存时间戳
	var access_count: int = 0  # 访问次数统计
	
	func _init(scene: Node):
		scene_instance = scene
		cached_time = Time.get_unix_time_from_system()
	
	func access():
		access_count += 1

# ==================== 生命周期函数 ====================

func _ready():
	print("[SceneManager] 场景管理器单例初始化")
	
	_init_default_load_screen()
	
	current_scene = get_tree().current_scene
	if current_scene:
		current_scene_path = current_scene.scene_file_path
		print("[SceneManager] 当前场景: ", current_scene_path)
	
	print("[SceneManager] 初始化完成，最大缓存: ", max_cache_size)

# ==================== 初始化函数 ====================

func _init_default_load_screen():
	print("[SceneManager] 初始化默认加载屏幕")
	
	if ResourceLoader.exists(DEFAULT_LOAD_SCREEN_PATH):
		var load_screen_scene = load(DEFAULT_LOAD_SCREEN_PATH)
		if load_screen_scene:
			default_load_screen = load_screen_scene.instantiate()
			add_child(default_load_screen)
			
			if default_load_screen is CanvasItem:
				default_load_screen.visible = false
			elif default_load_screen.has_method("set_visible"):
				default_load_screen.set_visible(false)
			
			print("[SceneManager] 默认加载屏幕加载成功")
			return
	
	print("[SceneManager] 警告:默认加载屏幕文件不存在，创建简单版本")
	default_load_screen = _create_simple_load_screen()
	add_child(default_load_screen)
	
	if default_load_screen is CanvasItem:
		default_load_screen.visible = false
	elif default_load_screen.has_method("set_visible"):
		default_load_screen.set_visible(false)
	
	print("[SceneManager] 简单加载屏幕创建完成")

func _create_simple_load_screen() -> Node:
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SimpleLoadScreen"
	canvas_layer.layer = 1000
	
	var color_rect = ColorRect.new()
	color_rect.color = Color(0, 0, 0, 1)
	color_rect.size = get_viewport().get_visible_rect().size
	color_rect.anchor_left = 0
	color_rect.anchor_top = 0
	color_rect.anchor_right = 1
	color_rect.anchor_bottom = 1
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var label = Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	
	canvas_layer.add_child(color_rect)
	color_rect.add_child(label)
	
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.position = Vector2(-50, -16)
	label.size = Vector2(100, 32)
	
	return canvas_layer

# ==================== 公开API - 场景切换 ====================

func switch_scene(new_scene_path: String, use_cache: bool = true, load_screen_path: String = "") -> void:
	print("[SceneManager] 开始切换场景到: ", new_scene_path)
	
	# 添加场景树验证，确保状态清晰
	_debug_validate_scene_tree()
	
	if always_use_default_load_screen:
		load_screen_path = ""
		print("[SceneManager] 强制使用默认加载屏幕")
	
	if not ResourceLoader.exists(new_scene_path):
		push_error("[SceneManager] 错误:目标场景路径不存在: ", new_scene_path)
		return
	
	scene_switch_started.emit(current_scene_path, new_scene_path)
	
	if current_scene_path == new_scene_path:
		print("[SceneManager] 场景已加载: ", new_scene_path)
		scene_switch_completed.emit(new_scene_path)
		return
	
	var load_screen_to_use = _get_load_screen_instance(load_screen_path)
	if load_screen_path != "no_transition" and not load_screen_to_use:
		push_error("[SceneManager] 错误:无法获取加载屏幕，切换中止")
		return
	
	# 检查预加载资源缓存
	if preload_resource_cache.has(new_scene_path):
		print("[SceneManager] 使用预加载资源缓存: ", new_scene_path)
		await _handle_preloaded_resource(new_scene_path, load_screen_to_use, use_cache)
		return
	
	if loading_scene_path == new_scene_path and loading_state == LoadState.LOADING:
		print("[SceneManager] 场景正在预加载中，等待完成...")
		await _handle_preloading_scene(new_scene_path, load_screen_to_use, use_cache)
		return
	
	if use_cache and scene_cache.has(new_scene_path):
		print("[SceneManager] 从实例缓存加载场景: ", new_scene_path)
		await _handle_cached_scene(new_scene_path, load_screen_to_use)
		return
	
	print("[SceneManager] 直接加载场景: ", new_scene_path)
	await _handle_direct_load(new_scene_path, load_screen_to_use, use_cache)

# ==================== 公开API - 预加载 ====================

func preload_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("[SceneManager] 错误:预加载场景路径不存在: ", scene_path)
		return
	
	# 检查是否已预加载或已缓存
	if preload_resource_cache.has(scene_path):
		print("[SceneManager] 场景已预加载: ", scene_path)
		# 更新LRU访问顺序
		_update_preload_resource_cache_access(scene_path)
		return
	
	if (loading_scene_path == scene_path and loading_state == LoadState.LOADING) or \
	   (loading_scene_path == scene_path and loading_state == LoadState.LOADED) or \
	   scene_cache.has(scene_path):
		print("[SceneManager] 场景已加载或正在加载: ", scene_path)
		return
	
	print("[SceneManager] 开始预加载场景: ", scene_path)
	scene_preload_started.emit(scene_path)
	
	loading_scene_path = scene_path
	loading_state = LoadState.LOADING
	
	if use_async_loading:
		await _async_preload_scene(scene_path)
	else:
		_sync_preload_scene(scene_path)
	
	if loading_resource:
		# 预加载完成后，将资源存入预加载资源缓存
		preload_resource_cache[scene_path] = loading_resource
		preload_resource_cache_access_order.append(scene_path)
		loading_state = LoadState.LOADED
		scene_preload_completed.emit(scene_path)
		print("[SceneManager] 预加载完成，资源已缓存: ", scene_path)
		
		# 如果预加载资源缓存数量超过最大限制，则移除最旧的缓存项
		if preload_resource_cache_access_order.size() > max_preload_resource_cache_size:
			_remove_oldest_preload_resource()
	else:
		loading_state = LoadState.NOT_LOADED
		loading_scene_path = ""
		print("[SceneManager] 预加载失败: ", scene_path)

# ==================== 公开API - 缓存管理 ====================

func clear_cache() -> void:
	print("[SceneManager] 清空缓存...")
	
	# 清理预加载资源缓存
	preload_resource_cache.clear()
	preload_resource_cache_access_order.clear()
	print("[SceneManager] 预加载资源缓存已清空")
	
	# 清理实例缓存
	var to_remove = []
	for scene_path in scene_cache:
		var cached = scene_cache[scene_path]
		if is_instance_valid(cached.scene_instance):
			_cleanup_orphaned_nodes(cached.scene_instance)  # 清理孤立节点
			cached.scene_instance.queue_free()
		to_remove.append(scene_path)
		scene_removed_from_cache.emit(scene_path)
	
	for scene_path in to_remove:
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
	
	# 重置加载状态，确保可以重新预加载场景
	loading_scene_path = ""
	loading_state = LoadState.NOT_LOADED
	loading_resource = null
	
	print("[SceneManager] 缓存已清空")

func get_cache_info() -> Dictionary:
	var cached_scenes = []
	for path in scene_cache:
		var cached = scene_cache[path]
		cached_scenes.append({
			"path": path,
			"access_count": cached.access_count,
			"cached_time": cached.cached_time,
			"instance_valid": is_instance_valid(cached.scene_instance)
		})
	
	var preloaded_scenes = []
	for path in preload_resource_cache:
		preloaded_scenes.append(path)
	
	return {
		"instance_cache_size": scene_cache.size(),
		"max_size": max_cache_size,
		"access_order": cache_access_order.duplicate(),
		"cached_scenes": cached_scenes,
		"preload_resource_cache": preloaded_scenes,
		"preload_cache_size": preload_resource_cache.size(),
		"max_preload_resource_cache_size": max_preload_resource_cache_size,
		"preload_resource_access_order": preload_resource_cache_access_order.duplicate()
	}

func is_scene_cached(scene_path: String) -> bool:
	return scene_cache.has(scene_path) or preload_resource_cache.has(scene_path)

# ==================== 公开API - 实用函数 ====================

func get_current_scene() -> Node:
	return current_scene

func get_previous_scene_path() -> String:
	return previous_scene_path

func get_loading_progress(scene_path: String) -> float:
	if loading_scene_path != scene_path or loading_state != LoadState.LOADING:
		return 1.0 if (scene_cache.has(scene_path) or preload_resource_cache.has(scene_path)) else 0.0
	
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and progress.size() > 0:
		return progress[0]
	
	return 0.0

func set_max_cache_size(new_size: int) -> void:
	if new_size < 1:
		push_error("[SceneManager] 错误:缓存大小必须大于0")
		return
	
	max_cache_size = new_size
	print("[SceneManager] 设置最大缓存大小: ", max_cache_size)
	
	while cache_access_order.size() > max_cache_size:
		_remove_oldest_cached_scene()

# 添加设置预加载资源缓存最大容量的方法
func set_max_preload_resource_cache_size(new_size: int) -> void:
	if new_size < 1:
		push_error("[SceneManager] 错误:预加载资源缓存大小必须大于0")
		return
	
	max_preload_resource_cache_size = new_size
	print("[SceneManager] 设置预加载资源缓存最大大小: ", max_preload_resource_cache_size)
	
	while preload_resource_cache_access_order.size() > max_preload_resource_cache_size:
		_remove_oldest_preload_resource()

# ==================== 加载屏幕管理 ====================

func _get_load_screen_instance(load_screen_path: String) -> Node:
	if load_screen_path == "":
		if default_load_screen:
			print("[SceneManager] 使用默认加载屏幕")
			return default_load_screen
		else:
			push_error("[SceneManager] 错误:默认加载屏幕未初始化")
			return null
	elif load_screen_path == "no_transition":
		print("[SceneManager] 使用无过渡模式")
		return null
	else:
		if ResourceLoader.exists(load_screen_path):
			var custom_scene = load(load_screen_path)
			if custom_scene:
				var instance = custom_scene.instantiate()
				add_child(instance)
				print("[SceneManager] 使用自定义加载屏幕: ", load_screen_path)
				return instance
			else:
				print("[SceneManager] 警告:自定义加载屏幕加载失败，使用默认")
				return default_load_screen
		else:
			print("[SceneManager] 警告:自定义加载屏幕路径不存在，使用默认")
			return default_load_screen

func _show_load_screen(load_screen_instance: Node) -> void:
	if not load_screen_instance:
		print("[SceneManager] 无加载屏幕，直接切换")
		return
	
	active_load_screen = load_screen_instance
	
	if load_screen_instance is CanvasItem:
		load_screen_instance.visible = true
	elif load_screen_instance.has_method("set_visible"):
		load_screen_instance.set_visible(true)
	elif load_screen_instance.has_method("show"):
		load_screen_instance.show()
	
	if load_screen_instance.has_method("fade_in"):
		print("[SceneManager] 调用加载屏幕淡入效果")
		await load_screen_instance.fade_in()
	elif load_screen_instance.has_method("show_loading"):
		await load_screen_instance.show_loading()
	
	load_screen_shown.emit(load_screen_instance)
	print("[SceneManager] 加载屏幕显示完成")

func _hide_load_screen(load_screen_instance: Node) -> void:
	if not load_screen_instance:
		return
	
	if load_screen_instance.has_method("fade_out"):
		print("[SceneManager] 调用加载屏幕淡出效果")
		await load_screen_instance.fade_out()
	elif load_screen_instance.has_method("hide_loading"):
		await load_screen_instance.hide_loading()
	elif load_screen_instance.has_method("hide"):
		load_screen_instance.hide()
	
	if load_screen_instance != default_load_screen:
		load_screen_instance.queue_free()
		print("[SceneManager] 清理自定义加载屏幕")
	else:
		if load_screen_instance is CanvasItem:
			load_screen_instance.visible = false
		elif load_screen_instance.has_method("set_visible"):
			load_screen_instance.set_visible(false)
	
	active_load_screen = null
	load_screen_hidden.emit(load_screen_instance)
	print("[SceneManager] 加载屏幕隐藏完成")

# ==================== 场景切换处理函数 ====================

func _handle_preloaded_resource(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	# 处理预加载资源缓存的场景
	await _show_load_screen(load_screen_instance)
	
	# 从预加载资源缓存获取并移除
	var packed_scene = preload_resource_cache.get(scene_path)
	preload_resource_cache.erase(scene_path)
	
	# 从预加载资源缓存访问顺序中移除
	var index = preload_resource_cache_access_order.find(scene_path)
	if index != -1:
		preload_resource_cache_access_order.remove_at(index)
	
	if not packed_scene:
		push_error("[SceneManager] 预加载资源缓存错误: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] 实例化预加载资源: ", scene_path)
	var new_scene = packed_scene.instantiate()
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)

func _handle_preloading_scene(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	await _show_load_screen(load_screen_instance)
	await _wait_for_preload(scene_path)
	
	# 预加载完成后，将资源存入预加载资源缓存
	if loading_resource:
		preload_resource_cache[scene_path] = loading_resource
		preload_resource_cache_access_order.append(scene_path)
		print("[SceneManager] 预加载资源已缓存: ", scene_path)
		
		# 如果预加载资源缓存数量超过最大限制，则移除最旧的缓存项
		if preload_resource_cache_access_order.size() > max_preload_resource_cache_size:
			_remove_oldest_preload_resource()
	
	await _instantiate_and_switch(scene_path, load_screen_instance, use_cache)

func _handle_cached_scene(scene_path: String, load_screen_instance: Node) -> void:
	await _show_load_screen(load_screen_instance)
	await _switch_to_cached_scene(scene_path, load_screen_instance)

func _handle_direct_load(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	await _show_load_screen(load_screen_instance)
	await _load_and_switch(scene_path, load_screen_instance, use_cache)

# ==================== 加载和切换核心函数 ====================

func _wait_for_preload(scene_path: String) -> void:
	print("[SceneManager] 等待预加载完成: ", scene_path)
	
	var wait_start_time = Time.get_ticks_msec()
	while loading_scene_path == scene_path and loading_state == LoadState.LOADING:
		if Time.get_ticks_msec() - wait_start_time > 500:
			var progress = get_loading_progress(scene_path)
			print("[SceneManager] 预加载进度: ", progress * 100, "%")
			wait_start_time = Time.get_ticks_msec()
		
		await get_tree().process_frame
	
	print("[SceneManager] 预加载等待完成")

func _instantiate_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	if not loading_resource or loading_scene_path != scene_path:
		push_error("[SceneManager] 预加载资源不存在或路径不匹配")
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] 实例化预加载场景: ", scene_path)
	
	var new_scene = loading_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] 实例化场景失败")
		await _hide_load_screen(load_screen_instance)
		return
	
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)
	
	loading_scene_path = ""
	loading_state = LoadState.NOT_LOADED
	loading_resource = null

func _switch_to_cached_scene(scene_path: String, load_screen_instance: Node) -> void:
	if not scene_cache.has(scene_path):
		push_error("[SceneManager] 缓存中找不到场景: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	var cached = scene_cache[scene_path]
	if not is_instance_valid(cached.scene_instance):
		push_error("[SceneManager] 缓存场景实例无效")
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] 使用缓存场景: ", scene_path)
	
	var scene_instance = cached.scene_instance
	
	# 从缓存中移除
	scene_cache.erase(scene_path)
	var index = cache_access_order.find(scene_path)
	if index != -1:
		cache_access_order.remove_at(index)
	
	cached.access()
	
	# 确保缓存节点不在任何父节点下
	if scene_instance.is_inside_tree():
		scene_instance.get_parent().remove_child(scene_instance)
	
	await _perform_scene_switch(scene_instance, scene_path, load_screen_instance, true)

func _load_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	print("[SceneManager] 加载场景: ", scene_path)
	
	var new_scene_resource = load(scene_path)
	if not new_scene_resource:
		push_error("[SceneManager] 场景加载失败: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	var new_scene = new_scene_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] 场景实例化失败: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)

func _perform_scene_switch(new_scene: Node, new_scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	print("[SceneManager] 执行场景切换到: ", new_scene_path)
	
	var old_scene = current_scene
	var old_scene_path = current_scene_path
	
	previous_scene_path = current_scene_path
	current_scene = new_scene
	current_scene_path = new_scene_path
	
	# 处理旧场景
	if old_scene and old_scene != new_scene:
		print("[SceneManager] 移除当前场景: ", old_scene.name)
		
		if old_scene.is_inside_tree():
			old_scene.get_parent().remove_child(old_scene)
		
		if use_cache and old_scene_path != "" and old_scene_path != new_scene_path:
			_add_to_cache(old_scene_path, old_scene)
		else:
			_cleanup_orphaned_nodes(old_scene)
			old_scene.queue_free()
	
	print("[SceneManager] 添加新场景: ", new_scene.name)
	
	# 确保新场景不在任何父节点下（防止重复父节点）
	if new_scene.is_inside_tree():
		new_scene.get_parent().remove_child(new_scene)
	
	# 添加到场景树
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	
	# 等待场景就绪
	if not new_scene.is_node_ready():
		print("[SceneManager] 等待新场景准备就绪...")
		await new_scene.ready
	
	await _hide_load_screen(load_screen_instance)
	
	# 验证场景树状态
	_debug_validate_scene_tree()
	
	scene_switch_completed.emit(new_scene_path)
	print("[SceneManager] 场景切换完成: ", new_scene_path)

# ==================== 缓存管理内部函数 ====================

func _add_to_cache(scene_path: String, scene_instance: Node) -> void:
	if scene_path == "" or not scene_instance:
		print("[SceneManager] 警告:无法缓存空场景或路径")
		return
	
	if scene_cache.has(scene_path):
		print("[SceneManager] 场景已在实例缓存中: ", scene_path)
		var old_cached = scene_cache[scene_path]
		if is_instance_valid(old_cached.scene_instance):
			_cleanup_orphaned_nodes(old_cached.scene_instance)
			old_cached.scene_instance.queue_free()
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
	
	# 清理孤立节点确保节点不在场景树中
	_cleanup_orphaned_nodes(scene_instance)
	
	# 如果节点仍在场景树中，这是错误状态
	if scene_instance.is_inside_tree():
		push_error("[SceneManager] 错误:尝试缓存仍在场景树中的节点")
		scene_instance.get_parent().remove_child(scene_instance)
	
	print("[SceneManager] 添加到实例缓存: ", scene_path)
	
	var cached = CachedScene.new(scene_instance)
	scene_cache[scene_path] = cached
	cache_access_order.append(scene_path)
	scene_cached.emit(scene_path)
	
	if cache_access_order.size() > max_cache_size:
		_remove_oldest_cached_scene()

func _update_cache_access(scene_path: String) -> void:
	var index = cache_access_order.find(scene_path)
	if index != -1:
		cache_access_order.remove_at(index)
	cache_access_order.append(scene_path)
	
	if scene_cache.has(scene_path):
		var cached = scene_cache[scene_path]
		cached.cached_time = Time.get_unix_time_from_system()

# 更新预加载资源缓存访问记录
func _update_preload_resource_cache_access(scene_path: String) -> void:
	# 从访问顺序列表中移除该场景
	var index = preload_resource_cache_access_order.find(scene_path)
	if index != -1:
		preload_resource_cache_access_order.remove_at(index)
	# 将该场景添加到访问顺序列表末尾（表示最近访问）
	preload_resource_cache_access_order.append(scene_path)

func _remove_oldest_cached_scene() -> void:
	if cache_access_order.size() == 0:
		return
	
	var oldest_path = cache_access_order[0]
	cache_access_order.remove_at(0)
	
	if scene_cache.has(oldest_path):
		var cached = scene_cache[oldest_path]
		if is_instance_valid(cached.scene_instance):
			_cleanup_orphaned_nodes(cached.scene_instance)
			cached.scene_instance.queue_free()
		scene_cache.erase(oldest_path)
		scene_removed_from_cache.emit(oldest_path)
		print("[SceneManager] 移除旧缓存: ", oldest_path)

# 移除最旧的预加载资源
func _remove_oldest_preload_resource() -> void:
	# 检查预加载资源缓存是否为空
	if preload_resource_cache_access_order.size() == 0:
		return
	
	# 获取最早访问的场景路径
	var oldest_path = preload_resource_cache_access_order[0]
	preload_resource_cache_access_order.remove_at(0)
	
	# 从预加载资源缓存中移除该资源
	if preload_resource_cache.has(oldest_path):
		preload_resource_cache.erase(oldest_path)
		print("[SceneManager] 移除旧预加载资源: ", oldest_path)

# ==================== 预加载内部函数 ====================

func _async_preload_scene(scene_path: String) -> void:
	print("[SceneManager] 异步预加载: ", scene_path)
	
	var load_start_time = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(scene_path)
	
	while true:
		var status = ResourceLoader.load_threaded_get_status(scene_path)
		
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if Time.get_ticks_msec() - load_start_time > 500:
					var progress = []
					ResourceLoader.load_threaded_get_status(scene_path, progress)
					if progress.size() > 0:
						print("[SceneManager] 异步加载进度: ", progress[0] * 100, "%")
					load_start_time = Time.get_ticks_msec()
				
				await get_tree().process_frame
			
			ResourceLoader.THREAD_LOAD_LOADED:
				loading_resource = ResourceLoader.load_threaded_get(scene_path)
				print("[SceneManager] 异步预加载完成: ", scene_path)
				return
			
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("[SceneManager] 异步加载失败: ", scene_path)
				loading_resource = null
				return
			
			_:
				push_error("[SceneManager] 未知加载状态: ", status)
				loading_resource = null
				return

func _sync_preload_scene(scene_path: String) -> void:
	print("[SceneManager] 同步预加载: ", scene_path)
	loading_resource = load(scene_path)

# ==================== 孤立节点清理函数 ====================

func _cleanup_orphaned_nodes(root_node: Node) -> void:
	# 递归清理可能成为孤立节点的子节点
	if not root_node or not is_instance_valid(root_node):
		return
	
	# 如果节点仍在场景树中，强制移除
	if root_node.is_inside_tree():
		var parent = root_node.get_parent()
		if parent:
			parent.remove_child(root_node)
	
	# 递归清理所有子节点
	for child in root_node.get_children():
		_cleanup_orphaned_nodes(child)

func _debug_validate_scene_tree() -> void:
	# 调试用:验证场景树状态
	var root = get_tree().root
	var current = get_tree().current_scene
	
	print("[SceneManager] 场景树验证 - 根节点子节点数: ", root.get_child_count())
	print("[SceneManager] 当前场景: ", current.name if current else "None")
	
	# 检查缓存节点是否意外在场景树中
	for scene_path in scene_cache:
		var cached = scene_cache[scene_path]
		if is_instance_valid(cached.scene_instance) and cached.scene_instance.is_inside_tree():
			push_error("[SceneManager] 错误:缓存节点仍在场景树中: ", scene_path)

# ==================== 信号连接辅助 ====================

func connect_all_signals(target: Object) -> void:
	if not target:
		return
	
	var signals_list = get_signal_list()
	for signal_info in signals_list:
		var signal_name = signal_info["name"]
		
		var method_name = "_on_scene_manager_" + signal_name
		if target.has_method(method_name):
			connect(signal_name, Callable(target, method_name))
			print("[SceneManager] 连接信号: ", signal_name, " -> ", method_name)

# ==================== 调试和工具函数 ====================

func print_debug_info() -> void:
	print("\n=== SceneManager 调试信息 ===")
	print("当前场景: ", current_scene_path if current_scene else "None")
	print("上一个场景: ", previous_scene_path)
	print("实例缓存数量: ", scene_cache.size(), "/", max_cache_size)
	print("预加载资源缓存数量: ", preload_resource_cache.size(), "/", max_preload_resource_cache_size)
	print("缓存访问顺序: ", cache_access_order)
	print("预加载资源缓存访问顺序: ", preload_resource_cache_access_order)
	print("正在加载的场景: ", loading_scene_path if loading_scene_path != "" else "None")
	print("加载状态: ", LoadState.keys()[loading_state])
	print("默认加载屏幕: ", "已加载" if default_load_screen else "未加载")
	print("活动加载屏幕: ", "有" if active_load_screen else "无")
	print("使用异步加载: ", use_async_loading)
	print("始终使用默认加载屏幕: ", always_use_default_load_screen)
	print("===============================\n")
