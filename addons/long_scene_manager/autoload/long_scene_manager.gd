# long_scene_manager.gd
# Global Scene Manager Plugin
extends Node

# 全局场景管理器插件
# 支持自定义加载屏幕的场景切换、预加载和LRU缓存
# 场景树和缓存分离设计:场景实例要么在场景树中，要么在缓存中
#
# Global scene manager plugin
# Supports scene switching with custom loading screens, preloading, and LRU caching
# Scene tree and cache separation design: scene instances are either in the scene tree or in the cache

# ==================== 常量和枚举 ====================
# ==================== Constants and Enums ====================

const DEFAULT_LOAD_SCREEN_PATH = "res://addons/long_scene_manager/ui/loading_screen/GDscript/loading_black_screen.tscn"
# Default loading screen resource path

enum LoadState {
	NOT_LOADED,      # 未加载 # Not loaded
	LOADING,         # 正在加载中 # Loading in progress
	LOADED,          # 已加载（资源已加载但未实例化） # Loaded (resource loaded but not instantiated)
	INSTANTIATED     # 已实例化（场景对象已创建） # Instantiated (scene object created)
}

# ==================== 信号定义 ====================
# ==================== Signal Definitions ====================

# 预加载开始信号
# Preloading started signal
signal scene_preload_started(scene_path: String)

# 预加载完成信号
# Preloading completed signal
signal scene_preload_completed(scene_path: String)

# 场景切换开始信号
# Scene switching started signal
signal scene_switch_started(from_scene: String, to_scene: String)

# 场景切换完成信号
# Scene switching completed signal
signal scene_switch_completed(scene_path: String)

# 场景被缓存信号
# Scene cached signal
signal scene_cached(scene_path: String)

# 场景从缓存中移除信号
# Scene removed from cache signal
signal scene_removed_from_cache(scene_path: String)

# 加载屏幕显示信号
# Loading screen shown signal
signal load_screen_shown(load_screen_instance: Node)

# 加载屏幕隐藏信号
# Loading screen hidden signal
signal load_screen_hidden(load_screen_instance: Node)

# ==================== 导出变量 ====================
# ==================== Export Variables ====================

@export_category("Scene Manager Global Configuration")
# 场景管理器全局配置
@export_range(1, 20) var max_cache_size: int = 8
# 最大缓存场景数量，默认为8个
# Maximum number of cached scenes, default is 8

@export_range(1, 50) var max_preload_resource_cache_size: int = 20  # 预加载资源缓存最大容量
# Maximum preload resource cache capacity

@export var use_async_loading: bool = true
# 是否使用异步加载，默认开启
# Whether to use asynchronous loading, enabled by default

@export var always_use_default_load_screen: bool = false
# 总是使用默认加载屏幕
# Always use default loading screen

# ==================== 内部状态变量 ====================
# ==================== Internal State Variables ====================

var current_scene: Node = null
# 当前场景实例
# Current scene instance

var current_scene_path: String = ""
# 当前场景路径
# Current scene path

var previous_scene_path: String = ""
# 上一个场景路径
# Previous scene path

var default_load_screen: Node = null
# 默认加载屏幕实例
# Default loading screen instance

var active_load_screen: Node = null
# 当前激活的加载屏幕实例
# Currently active loading screen instance

var loading_scene_path: String = ""
# 正在加载的场景路径
# Path of the scene currently being loaded

var loading_state: LoadState = LoadState.NOT_LOADED
# 当前加载状态
# Current loading state

var loading_resource: PackedScene = null
# 正在加载的场景资源
# Scene resource currently being loaded

var scene_cache: Dictionary = {}  # 存储从场景树移除的节点实例
# Store node instances removed from the scene tree

var cache_access_order: Array = []  # LRU缓存访问顺序记录
# LRU cache access order record

# 新增:预加载资源缓存，存储预加载的PackedScene资源
# Added: Preload resource cache, stores preloaded PackedScene resources
var preload_resource_cache: Dictionary = {}

var preload_resource_cache_access_order: Array = []  # 预加载资源缓存LRU访问顺序记录
# Preload resource cache LRU access order record

class CachedScene:
	var scene_instance: Node  # 缓存的节点实例 # Cached node instance
	var cached_time: float    # 缓存时间戳 # Cache timestamp
	var access_count: int = 0  # 访问次数统计 # Access count statistics
	
	func _init(scene: Node):
		scene_instance = scene
		cached_time = Time.get_unix_time_from_system()
	
	func access():
		access_count += 1

# ==================== 生命周期函数 ====================
# ==================== Lifecycle Functions ====================

func _ready():
	print("[SceneManager] Scene manager singleton initialized")
	# 场景管理器单例初始化
	
	_init_default_load_screen()
	
	current_scene = get_tree().current_scene
	if current_scene:
		current_scene_path = current_scene.scene_file_path
		print("[SceneManager] Current scene: ", current_scene_path)
		# 当前场景:
	
	print("[SceneManager] Initialization complete, max cache: ", max_cache_size)
	# 初始化完成，最大缓存:

# ==================== 初始化函数 ====================
# ==================== Initialization Functions ====================

func _init_default_load_screen():
	print("[SceneManager] Initializing default loading screen")
	# 初始化默认加载屏幕
	
	if ResourceLoader.exists(DEFAULT_LOAD_SCREEN_PATH):
		var load_screen_scene = load(DEFAULT_LOAD_SCREEN_PATH)
		if load_screen_scene:
			default_load_screen = load_screen_scene.instantiate()
			add_child(default_load_screen)
			
			if default_load_screen is CanvasItem:
				default_load_screen.visible = false
			elif default_load_screen.has_method("set_visible"):
				default_load_screen.set_visible(false)
			
			print("[SceneManager] Default loading screen loaded successfully")
			# 默认加载屏幕加载成功
			return
	
	print("[SceneManager] Warning: Default loading screen file does not exist, creating simple version")
	# 警告:默认加载屏幕文件不存在，创建简单版本
	default_load_screen = _create_simple_load_screen()
	add_child(default_load_screen)
	
	if default_load_screen is CanvasItem:
		default_load_screen.visible = false
	#elif default_load_screen.has_method("set_visible"):
	#	default_load_screen.set_visible(false)
	
	print("[SceneManager] Simple loading screen creation completed")
	# 简单加载屏幕创建完成

func _create_simple_load_screen() -> Node:
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SimpleLoadScreen"
	canvas_layer.layer = 1000  # 设置层级为1000，确保显示在最前面
	                       # Set layer to 1000 to ensure it displays in front
	
	var color_rect = ColorRect.new()
	color_rect.color = Color(0, 0, 0, 1)  # 纯黑色不透明
	                                  # Pure black opaque
	color_rect.size = get_viewport().get_visible_rect().size  # 设置为视口大小
	                                                      # Set to viewport size
	color_rect.anchor_left = 0
	color_rect.anchor_top = 0
	color_rect.anchor_right = 1
	color_rect.anchor_bottom = 1
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # 阻止鼠标事件穿透
	                                                # Prevent mouse events from passing through
	
	var label = Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # 水平居中
	                                                     # Horizontal center
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER      # 垂直居中
	                                                     # Vertical center
	label.add_theme_font_size_override("font_size", 32)         # 字体大小32
	                                                        # Font size 32
	label.add_theme_color_override("font_color", Color.WHITE) # 白色字体
	                                                     # White font
	
	canvas_layer.add_child(color_rect)
	color_rect.add_child(label)
	
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.position = Vector2(-50, -16)  # 微调位置
	                               # Fine-tune position
	label.size = Vector2(100, 32)
	
	return canvas_layer

# ==================== 公开API - 场景切换 ====================
# ==================== Public API - Scene Switching ====================

func switch_scene(new_scene_path: String, use_cache: bool = true, load_screen_path: String = "") -> void:
	print("[SceneManager] Start switching scene to: ", new_scene_path)
	# 开始切换场景到:
	
	# 添加场景树验证，确保状态清晰
	# Add scene tree validation to ensure clear state
	_debug_validate_scene_tree()
	
	if always_use_default_load_screen:
		load_screen_path = ""
		print("[SceneManager] Force using default loading screen")
		# 强制使用默认加载屏幕
	
	if not ResourceLoader.exists(new_scene_path):
		push_error("[SceneManager] Error: Target scene path does not exist: ", new_scene_path)
		# 错误:目标场景路径不存在:
		return
	
	scene_switch_started.emit(current_scene_path, new_scene_path)
	
	if current_scene_path == new_scene_path:
		print("[SceneManager] Scene already loaded: ", new_scene_path)
		# 场景已加载:
		scene_switch_completed.emit(new_scene_path)
		return
	
	var load_screen_to_use = _get_load_screen_instance(load_screen_path)
	if load_screen_path != "no_transition" and not load_screen_to_use:
		push_error("[SceneManager] Error: Unable to get loading screen, switching aborted")
		# 错误:无法获取加载屏幕，切换中止
		return
	
	# 检查预加载资源缓存
	# Check preload resource cache
	if preload_resource_cache.has(new_scene_path):
		print("[SceneManager] Using preload resource cache: ", new_scene_path)
		# 使用预加载资源缓存:
		await _handle_preloaded_resource(new_scene_path, load_screen_to_use, use_cache)
		return
	
	if loading_scene_path == new_scene_path and loading_state == LoadState.LOADING:
		print("[SceneManager] Scene is preloading, waiting for completion...")
		# 场景正在预加载中，等待完成...
		await _handle_preloading_scene(new_scene_path, load_screen_to_use, use_cache)
		return
	
	if use_cache and scene_cache.has(new_scene_path):
		print("[SceneManager] Loading scene from instance cache: ", new_scene_path)
		# 从实例缓存加载场景:
		await _handle_cached_scene(new_scene_path, load_screen_to_use)
		return
	
	print("[SceneManager] Directly loading scene: ", new_scene_path)
	# 直接加载场景:
	await _handle_direct_load(new_scene_path, load_screen_to_use, use_cache)

# ==================== 公开API - 预加载 ====================
# ==================== Public API - Preloading ====================

func preload_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("[SceneManager] Error: Preload scene path does not exist: ", scene_path)
		# 错误:预加载场景路径不存在:
		return
	
	# 检查是否已预加载或已缓存
	# Check if already preloaded or cached
	if preload_resource_cache.has(scene_path):
		print("[SceneManager] Scene already preloaded: ", scene_path)
		# 场景已预加载:
		# 更新LRU访问顺序
		# Update LRU access order
		_update_preload_resource_cache_access(scene_path)
		return
	
	if (loading_scene_path == scene_path and loading_state == LoadState.LOADING) or \
	   (loading_scene_path == scene_path and loading_state == LoadState.LOADED) or \
	   scene_cache.has(scene_path):
		print("[SceneManager] Scene already loaded or loading: ", scene_path)
		# 场景已加载或正在加载:
		return
	
	print("[SceneManager] Start preloading scene: ", scene_path)
	# 开始预加载场景:
	scene_preload_started.emit(scene_path)
	
	loading_scene_path = scene_path
	loading_state = LoadState.LOADING
	
	if use_async_loading:
		await _async_preload_scene(scene_path)
	else:
		_sync_preload_scene(scene_path)
	
	if loading_resource:
		# 预加载完成后，将资源存入预加载资源缓存
		# After preloading is complete, store the resource in the preload resource cache
		preload_resource_cache[scene_path] = loading_resource
		preload_resource_cache_access_order.append(scene_path)
		loading_state = LoadState.LOADED
		scene_preload_completed.emit(scene_path)
		print("[SceneManager] Preloading complete, resource cached: ", scene_path)
		# 预加载完成，资源已缓存:
		
		# 如果预加载资源缓存数量超过最大限制，则移除最旧的缓存项
		# If the number of preload resource cache items exceeds the maximum limit, remove the oldest cache item
		if preload_resource_cache_access_order.size() > max_preload_resource_cache_size:
			_remove_oldest_preload_resource()
	else:
		loading_state = LoadState.NOT_LOADED
		loading_scene_path = ""
		print("[SceneManager] Preloading failed: ", scene_path)
		# Preloading failed:

# ==================== 公开API - 缓存管理 ====================
# ==================== Public API - Cache Management ====================

func clear_cache() -> void:
	print("[SceneManager] Clearing cache...")
	# 清空缓存...
	
	# 清理预加载资源缓存
	# Clean up preload resource cache
	preload_resource_cache.clear()
	preload_resource_cache_access_order.clear()
	print("[SceneManager] Preload resource cache cleared")
	# 预加载资源缓存已清空
	
	# 清理实例缓存
	# Clean up instance cache
	var to_remove = []
	for scene_path in scene_cache:
		var cached = scene_cache[scene_path]
		if is_instance_valid(cached.scene_instance):
			_cleanup_orphaned_nodes(cached.scene_instance)  # 清理孤立节点
			                                            # Clean up orphaned nodes
			cached.scene_instance.queue_free()
		to_remove.append(scene_path)
		scene_removed_from_cache.emit(scene_path)
	
	for scene_path in to_remove:
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
	
	# 重置加载状态，确保可以重新预加载场景
	# Reset loading state to ensure scenes can be preloaded again
	loading_scene_path = ""
	loading_state = LoadState.NOT_LOADED
	loading_resource = null
	
	print("[SceneManager] Cache cleared")
	# 缓存已清空

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
# ==================== Public API - Utility Functions ====================

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
		push_error("[SceneManager] Error: Cache size must be greater than 0")
		# 错误:缓存大小必须大于0
		return
	
	max_cache_size = new_size
	print("[SceneManager] Setting maximum cache size: ", max_cache_size)
	# 设置最大缓存大小:
	
	while cache_access_order.size() > max_cache_size:
		_remove_oldest_cached_scene()

# 添加设置预加载资源缓存最大容量的方法
# Add method to set maximum preload resource cache capacity
func set_max_preload_resource_cache_size(new_size: int) -> void:
	if new_size < 1:
		push_error("[SceneManager] Error: Preload resource cache size must be greater than 0")
		# 错误:预加载资源缓存大小必须大于0
		return
	
	max_preload_resource_cache_size = new_size
	print("[SceneManager] Setting maximum preload resource cache size: ", max_preload_resource_cache_size)
	# 设置预加载资源缓存最大大小:
	
	while preload_resource_cache_access_order.size() > max_preload_resource_cache_size:
		_remove_oldest_preload_resource()

# ==================== 加载屏幕管理 ====================
# ==================== Loading Screen Management ====================

func _get_load_screen_instance(load_screen_path: String) -> Node:
	if load_screen_path == "":
		if default_load_screen:
			print("[SceneManager] Using default loading screen")
			# 使用默认加载屏幕
			return default_load_screen
		else:
			push_error("[SceneManager] Error: Default loading screen not initialized")
			# 错误:默认加载屏幕未初始化
			return null
	elif load_screen_path == "no_transition":
		print("[SceneManager] Using no transition mode")
		# 使用无过渡模式
		return null
	else:
		if ResourceLoader.exists(load_screen_path):
			var custom_scene = load(load_screen_path)
			if custom_scene:
				var instance = custom_scene.instantiate()
				add_child(instance)
				print("[SceneManager] Using custom loading screen: ", load_screen_path)
				# 使用自定义加载屏幕:
				return instance
			else:
				print("[SceneManager] Warning: Custom loading screen failed to load, using default")
				# 警告:自定义加载屏幕加载失败，使用默认
				return default_load_screen
		else:
			print("[SceneManager] Warning: Custom loading screen path does not exist, using default")
			# 警告:自定义加载屏幕路径不存在，使用默认
			return default_load_screen

func _show_load_screen(load_screen_instance: Node) -> void:
	if not load_screen_instance:
		print("[SceneManager] No loading screen, switching directly")
		# 无加载屏幕，直接切换
		return
	
	active_load_screen = load_screen_instance
	
	if load_screen_instance is CanvasItem:
		load_screen_instance.visible = true
	elif load_screen_instance.has_method("set_visible"):
		load_screen_instance.set_visible(true)
	elif load_screen_instance.has_method("show"):
		load_screen_instance.show()
	
	if load_screen_instance.has_method("fade_in"):
		print("[SceneManager] Calling loading screen fade-in effect")
		# 调用加载屏幕淡入效果
		await load_screen_instance.fade_in()
	elif load_screen_instance.has_method("show_loading"):
		await load_screen_instance.show_loading()
	
	load_screen_shown.emit(load_screen_instance)
	print("[SceneManager] Loading screen display completed")
	# 加载屏幕显示完成

func _hide_load_screen(load_screen_instance: Node) -> void:
	if not load_screen_instance:
		return
	
	if load_screen_instance.has_method("fade_out"):
		print("[SceneManager] Calling loading screen fade-out effect")
		# 调用加载屏幕淡出效果
		await load_screen_instance.fade_out()
	elif load_screen_instance.has_method("hide_loading"):
		await load_screen_instance.hide_loading()
	elif load_screen_instance.has_method("hide"):
		load_screen_instance.hide()
	
	if load_screen_instance != default_load_screen:
		load_screen_instance.queue_free()
		print("[SceneManager] Cleaning up custom loading screen")
		# 清理自定义加载屏幕
	else:
		if load_screen_instance is CanvasItem:
			load_screen_instance.visible = false
		elif load_screen_instance.has_method("set_visible"):
			load_screen_instance.set_visible(false)
	
	active_load_screen = null
	load_screen_hidden.emit(load_screen_instance)
	print("[SceneManager] Loading screen hiding completed")
	# 加载屏幕隐藏完成

# ==================== 场景切换处理函数 ====================
# ==================== Scene Switching Handler Functions ====================

func _handle_preloaded_resource(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	# 处理预加载资源缓存的场景
	# Handle scenes with preloaded resource cache
	await _show_load_screen(load_screen_instance)
	
	# 从预加载资源缓存获取并移除
	# Get and remove from preload resource cache
	var packed_scene = preload_resource_cache.get(scene_path)
	preload_resource_cache.erase(scene_path)
	
	# 从预加载资源缓存访问顺序中移除
	# Remove from preload resource cache access order
	var index = preload_resource_cache_access_order.find(scene_path)
	if index != -1:
		preload_resource_cache_access_order.remove_at(index)
	
	if not packed_scene:
		push_error("[SceneManager] Preload resource cache error: ", scene_path)
		# Preload resource cache error:
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] Instantiate preloaded resources: ", scene_path)
	# 实例化预加载资源:
	var new_scene = packed_scene.instantiate()
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)

func _handle_preloading_scene(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	await _show_load_screen(load_screen_instance)
	await _wait_for_preload(scene_path)
	
	# 预加载完成后，将资源存入预加载资源缓存
	# After preloading is complete, store the resource in the preload resource cache
	if loading_resource:
		preload_resource_cache[scene_path] = loading_resource
		preload_resource_cache_access_order.append(scene_path)
		print("[SceneManager] Preload resource cached: ", scene_path)
		# Preload resource cached:
		
		# 如果预加载资源缓存数量超过最大限制，则移除最旧的缓存项
		# If the number of preload resource cache items exceeds the maximum limit, remove the oldest cache item
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
# ==================== Loading and Switching Core Functions ====================

func _wait_for_preload(scene_path: String) -> void:
	print("[SceneManager] Waiting for preload to complete: ", scene_path)
	# 等待预加载完成:
	
	var wait_start_time = Time.get_ticks_msec()
	while loading_scene_path == scene_path and loading_state == LoadState.LOADING:
		if Time.get_ticks_msec() - wait_start_time > 500:
			var progress = get_loading_progress(scene_path)
			print("[SceneManager] Preload progress: ", progress * 100, "%")
			# 预加载进度:
			wait_start_time = Time.get_ticks_msec()
		
		await get_tree().process_frame
	
	print("[SceneManager] Preload waiting completed")
	# 预加载等待完成

func _instantiate_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	if not loading_resource or loading_scene_path != scene_path:
		push_error("[SceneManager] Preloaded resource does not exist or path mismatch")
		# 预加载资源不存在或路径不匹配
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] Instantiating preloaded scene: ", scene_path)
	# 实例化预加载场景:
	
	var new_scene = loading_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] Scene instantiation failed")
		# 场景实例化失败
		await _hide_load_screen(load_screen_instance)
		return
	
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)
	
	loading_scene_path = ""
	loading_state = LoadState.NOT_LOADED
	loading_resource = null

func _switch_to_cached_scene(scene_path: String, load_screen_instance: Node) -> void:
	if not scene_cache.has(scene_path):
		push_error("[SceneManager] Scene not found in cache: ", scene_path)
		# 缓存中找不到场景:
		await _hide_load_screen(load_screen_instance)
		return
	
	var cached = scene_cache[scene_path]
	if not is_instance_valid(cached.scene_instance):
		push_error("[SceneManager] Cached scene instance is invalid")
		# 缓存场景实例无效
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] Using cached scene: ", scene_path)
	# 使用缓存场景:
	
	var scene_instance = cached.scene_instance
	
	# 从缓存中移除
	# Remove from cache
	scene_cache.erase(scene_path)
	var index = cache_access_order.find(scene_path)
	if index != -1:
		cache_access_order.remove_at(index)
	
	cached.access()
	
	# 确保缓存节点不在任何父节点下
	# Ensure cached node is not under any parent node
	if scene_instance.is_inside_tree():
		scene_instance.get_parent().remove_child(scene_instance)
	
	await _perform_scene_switch(scene_instance, scene_path, load_screen_instance, true)

func _load_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	print("[SceneManager] Loading scene: ", scene_path)
	# 加载场景:
	
	var new_scene_resource = load(scene_path)
	if not new_scene_resource:
		push_error("[SceneManager] Scene loading failed: ", scene_path)
		# 场景加载失败:
		await _hide_load_screen(load_screen_instance)
		return
	
	var new_scene = new_scene_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] Scene instantiation failed: ", scene_path)
		# 场景实例化失败:
		await _hide_load_screen(load_screen_instance)
		return
	
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)

func _perform_scene_switch(new_scene: Node, new_scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	print("[SceneManager] Performing scene switch to: ", new_scene_path)
	# 执行场景切换到:
	
	var old_scene = current_scene
	var old_scene_path = current_scene_path
	
	previous_scene_path = current_scene_path
	current_scene = new_scene
	current_scene_path = new_scene_path
	
	# 处理旧场景
	# Handle old scene
	if old_scene and old_scene != new_scene:
		print("[SceneManager] Removing current scene: ", old_scene.name)
		# 移除当前场景:
		
		if old_scene.is_inside_tree():
			old_scene.get_parent().remove_child(old_scene)
		
		if use_cache and old_scene_path != "" and old_scene_path != new_scene_path:
			_add_to_cache(old_scene_path, old_scene)
		else:
			_cleanup_orphaned_nodes(old_scene)
			old_scene.queue_free()
	
	print("[SceneManager] Adding new scene: ", new_scene.name)
	# 添加新场景:
	
	# 确保新场景不在任何父节点下（防止重复父节点）
	# Ensure new scene is not under any parent node (prevent duplicate parent nodes)
	if new_scene.is_inside_tree():
		new_scene.get_parent().remove_child(new_scene)
	
	# 添加到场景树
	# Add to scene tree
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	
	# 等待场景就绪
	# Wait for scene to be ready
	if not new_scene.is_node_ready():
		print("[SceneManager] Waiting for new scene to be ready...")
		# 等待新场景准备就绪...
		await new_scene.ready
	
	await _hide_load_screen(load_screen_instance)
	
	# 验证场景树状态
	# Validate scene tree state
	_debug_validate_scene_tree()
	
	scene_switch_completed.emit(new_scene_path)
	print("[SceneManager] Scene switching completed: ", new_scene_path)
	# 场景切换完成:

# ==================== 缓存管理内部函数 ====================
# ==================== Cache Management Internal Functions ====================

func _add_to_cache(scene_path: String, scene_instance: Node) -> void:
	if scene_path == "" or not scene_instance:
		print("[SceneManager] Warning: Cannot cache empty scene or path")
		# 警告:无法缓存空场景或路径
		return
	
	if scene_cache.has(scene_path):
		print("[SceneManager] Scene already in instance cache: ", scene_path)
		# 场景已在实例缓存中:
		var old_cached = scene_cache[scene_path]
		if is_instance_valid(old_cached.scene_instance):
			_cleanup_orphaned_nodes(old_cached.scene_instance)
			old_cached.scene_instance.queue_free()
		scene_cache.erase(scene_path)
		var index = cache_access_order.find(scene_path)
		if index != -1:
			cache_access_order.remove_at(index)
	
	# 清理孤立节点确保节点不在场景树中
	# Clean up orphaned nodes to ensure node is not in scene tree
	_cleanup_orphaned_nodes(scene_instance)
	
	# 如果节点仍在场景树中，这是错误状态
	# 如果节点仍在场景树中，这是错误状态
	if scene_instance.is_inside_tree():
		push_error("[SceneManager] Error: Attempting to cache node still in scene tree")
		# 错误:尝试缓存仍在场景树中的节点
		scene_instance.get_parent().remove_child(scene_instance)
	
	print("[SceneManager] Adding to instance cache: ", scene_path)
	# 添加到实例缓存:
	
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
# Update preload resource cache access record
func _update_preload_resource_cache_access(scene_path: String) -> void:
	# 从访问顺序列表中移除该场景
	# Remove this scene from the access order list
	var index = preload_resource_cache_access_order.find(scene_path)
	if index != -1:
		preload_resource_cache_access_order.remove_at(index)
	# 将该场景添加到访问顺序列表末尾（表示最近访问）
	# Add this scene to the end of the access order list (indicating recent access)
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
		print("[SceneManager] Removing old cache: ", oldest_path)
		# 移除旧缓存:

# 移除最旧的预加载资源
# Remove the oldest preload resource
func _remove_oldest_preload_resource() -> void:
	# 检查预加载资源缓存是否为空
	# Check if preload resource cache is empty
	if preload_resource_cache_access_order.size() == 0:
		return
	
	# 获取最早访问的场景路径
	# Get the earliest accessed scene path
	var oldest_path = preload_resource_cache_access_order[0]
	preload_resource_cache_access_order.remove_at(0)
	
	# 从预加载资源缓存中移除该资源
	# Remove this resource from the preload resource cache
	if preload_resource_cache.has(oldest_path):
		preload_resource_cache.erase(oldest_path)
		print("[SceneManager] Removing old preload resource: ", oldest_path)
		# 移除旧预加载资源:

# ==================== 预加载内部函数 ====================
# ==================== Preload Internal Functions ====================

func _async_preload_scene(scene_path: String) -> void:
	print("[SceneManager] Asynchronous preload: ", scene_path)
	# 异步预加载:
	
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
						print("[SceneManager] Asynchronous loading progress: ", progress[0] * 100, "%")
						# 异步加载进度:
					load_start_time = Time.get_ticks_msec()
				
				await get_tree().process_frame
			
			ResourceLoader.THREAD_LOAD_LOADED:
				loading_resource = ResourceLoader.load_threaded_get(scene_path)
				print("[SceneManager] Asynchronous preload completed: ", scene_path)
				# 异步预加载完成:
				return
			
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("[SceneManager] Asynchronous loading failed: ", scene_path)
				# 异步加载失败:
				loading_resource = null
				return
			
			_:
				push_error("[SceneManager] Unknown loading status: ", status)
				# 未知加载状态:
				loading_resource = null
				return

func _sync_preload_scene(scene_path: String) -> void:
	print("[SceneManager] Synchronous preload: ", scene_path)
	# 同步预加载:
	loading_resource = load(scene_path)

# ==================== 孤立节点清理函数 ====================
# ==================== Orphaned Node Cleanup Functions ====================

func _cleanup_orphaned_nodes(root_node: Node) -> void:
	# 递归清理可能成为孤立节点的子节点
	# Recursively clean up child nodes that may become orphaned
	if not root_node or not is_instance_valid(root_node):
		return
	
	# 如果节点仍在场景树中，强制移除
	# If node is still in scene tree, force removal
	if root_node.is_inside_tree():
		var parent = root_node.get_parent()
		if parent:
			parent.remove_child(root_node)
	
	# 递归清理所有子节点
	# Recursively clean up all child nodes
	for child in root_node.get_children():
		_cleanup_orphaned_nodes(child)

func _debug_validate_scene_tree() -> void:
	# 调试用:验证场景树状态
	var root = get_tree().root
	var current = get_tree().current_scene
	
	print("[SceneManager] Scene tree validation - Root node child count: ", root.get_child_count())
	# 场景树验证 - 根节点子节点数:
	print("[SceneManager] Current scene: ", current.name if current else "None")
	# 当前场景:
	
	# 检查缓存节点是否意外在场景树中
	# Check if cached nodes are unexpectedly in the scene tree
	for scene_path in scene_cache:
		var cached = scene_cache[scene_path]
		if is_instance_valid(cached.scene_instance) and cached.scene_instance.is_inside_tree():
			push_error("[SceneManager] Error: Cached node still in scene tree: ", scene_path)
			# 错误:缓存节点仍在场景树中:

# ==================== 信号连接辅助 ====================
# ==================== Signal Connection Helper ====================

func connect_all_signals(target: Object) -> void:
	if not target:
		return
	
	var signals_list = get_signal_list()
	for signal_info in signals_list:
		var signal_name = signal_info["name"]
		
		var method_name = "_on_scene_manager_" + signal_name
		if target.has_method(method_name):
			connect(signal_name, Callable(target, method_name))
			print("[SceneManager] Connecting signal: ", signal_name, " -> ", method_name)
			# 连接信号:

# ==================== 调试和工具函数 ====================
# ==================== Debug and Utility Functions ====================

func print_debug_info() -> void:
	print("\n=== SceneManager Debug Info ===")
	# SceneManager Debug Info
	# 场景管理器调试信息
	print("Current scene: ", current_scene_path if current_scene else "None")
	# Current scene:
	# 当前场景:
	print("Previous scene: ", previous_scene_path)
	# Previous scene:
	# 上一个场景:
	print("Instance cache count: ", scene_cache.size(), "/", max_cache_size)
	# Instance cache count:
	# 实例缓存数量:
	print("Preload resource cache count: ", preload_resource_cache.size(), "/", max_preload_resource_cache_size)
	# Preload resource cache count:
	# 预加载资源缓存数量:
	print("Cache access order: ", cache_access_order)
	# Cache access order:
	# 缓存访问顺序:
	print("Preload resource cache access order: ", preload_resource_cache_access_order)
	# Preload resource cache access order:
	# 预加载资源缓存访问顺序:
	print("Scene currently loading: ", loading_scene_path if loading_scene_path != "" else "None")
	# Scene currently loading:
	# 正在加载的场景:
	print("Loading state: ", LoadState.keys()[loading_state])
	# Loading state:
	# 加载状态:
	print("Default loading screen: ", "Loaded" if default_load_screen else "Not loaded")
	# Default loading screen: "Loaded" or "Not loaded"
	# 默认加载屏幕:
	print("Active loading screen: ", "Yes" if active_load_screen else "No")
	# Active loading screen: "Yes" or "No"
	# 活动加载屏幕:
	print("Using asynchronous loading: ", use_async_loading)
	# Using asynchronous loading:
	# 使用异步加载:
	print("Always use default loading screen: ", always_use_default_load_screen)
	# Always use default loading screen:
	# 总是使用默认加载屏幕:
	print("===============================\n")
