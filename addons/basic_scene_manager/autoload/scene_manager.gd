# scene_manager.gd
extends Node
class_name SceneManager

"""
全局场景管理器插件
功能：支持自定义加载屏幕的场景切换、预加载和LRU缓存
支持任意节点类型的加载屏幕
"""

# ==================== 常量和枚举 ====================

# 插件内置的默认加载屏幕路径
const DEFAULT_LOAD_SCREEN_PATH = "res://addons/basic_scene_manager/ui/loading_screen/loading_black_screen.tscn"

# 加载状态枚举
enum LoadState {
	NOT_LOADED,      # 未加载
	LOADING,         # 加载中
	LOADED,          # 已加载（预加载完成）
	INSTANTIATED     # 已实例化（在场景树中）
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
@export var use_async_loading: bool = true
@export var always_use_default_load_screen: bool = false

# ==================== 内部状态变量 ====================

# 场景状态
var current_scene: Node = null
var current_scene_path: String = ""
var previous_scene_path: String = ""

# 加载屏幕管理 - 现在支持任意Node类型
var default_load_screen: Node = null  # 默认加载屏幕实例
var active_load_screen: Node = null   # 当前活动的加载屏幕

# 加载管理
var loading_scene_path: String = ""
var loading_state: LoadState = LoadState.NOT_LOADED
var loading_resource: PackedScene = null

# 缓存管理
var scene_cache: Dictionary = {}      # {scene_path: CachedScene}
var cache_access_order: Array = []    # LRU访问顺序

# 缓存场景类
class CachedScene:
	var scene_instance: Node
	var cached_time: float
	var access_count: int = 0
	
	func _init(scene: Node):
		scene_instance = scene
		cached_time = Time.get_unix_time_from_system()
	
	func access():
		access_count += 1

# ==================== 生命周期函数 ====================

func _ready():
	#"""场景管理器初始化"""
	print("[SceneManager] 场景管理器单例初始化")
	
	# 初始化默认加载屏幕
	_init_default_load_screen()
	
	# 设置当前场景
	current_scene = get_tree().current_scene
	if current_scene:
		current_scene_path = current_scene.scene_file_path
		print("[SceneManager] 当前场景: ", current_scene_path)
	
	print("[SceneManager] 初始化完成，最大缓存: ", max_cache_size)

# ==================== 初始化函数 ====================

func _init_default_load_screen():
	#"""初始化插件内置的默认加载屏幕"""
	print("[SceneManager] 初始化默认加载屏幕")
	
	if ResourceLoader.exists(DEFAULT_LOAD_SCREEN_PATH):
		var load_screen_scene = load(DEFAULT_LOAD_SCREEN_PATH)
		if load_screen_scene:
			default_load_screen = load_screen_scene.instantiate()
			add_child(default_load_screen)
			
			# 设置可见性 - 根据节点类型处理
			if default_load_screen is CanvasItem:
				default_load_screen.visible = false
			elif default_load_screen.has_method("set_visible"):
				default_load_screen.set_visible(false)
			
			print("[SceneManager] 默认加载屏幕加载成功")
			return
	
	# 如果默认文件不存在，动态创建一个简单的加载屏幕
	print("[SceneManager] 警告：默认加载屏幕文件不存在，创建简单版本")
	default_load_screen = _create_simple_load_screen()
	add_child(default_load_screen)
	
	if default_load_screen is CanvasItem:
		default_load_screen.visible = false
	elif default_load_screen.has_method("set_visible"):
		default_load_screen.set_visible(false)
	
	print("[SceneManager] 简单加载屏幕创建完成")

func _create_simple_load_screen() -> Node:
	#"""创建简单的加载屏幕作为后备"""
	# 创建一个简单的CanvasLayer作为默认加载屏幕
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SimpleLoadScreen"
	canvas_layer.layer = 1000  # 设置高层级
	
	# 创建一个黑色ColorRect覆盖全屏
	var color_rect = ColorRect.new()
	color_rect.color = Color(0, 0, 0, 1)
	color_rect.size = get_viewport().get_visible_rect().size
	color_rect.anchor_left = 0
	color_rect.anchor_top = 0
	color_rect.anchor_right = 1
	color_rect.anchor_bottom = 1
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 添加加载文字
	var label = Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	
	# 将节点添加到层次结构中
	canvas_layer.add_child(color_rect)
	color_rect.add_child(label)
	
	# 居中标签
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.position = Vector2(-50, -16)
	label.size = Vector2(100, 32)
	
	return canvas_layer

# ==================== 公开API - 场景切换 ====================

func switch_scene(new_scene_path: String, use_cache: bool = true, load_screen_path: String = "") -> void:
	#"""
	#切换到新场景，支持自定义加载屏幕
	#
	#参数:
	#- new_scene_path: 目标场景路径
	#- use_cache: 是否使用缓存（默认true）
	#- load_screen_path: 自定义加载屏幕路径（空字符串则使用默认）
	#"""
	print("[SceneManager] 开始切换场景到: ", new_scene_path)
	
	# 如果全局配置强制使用默认加载屏幕
	if always_use_default_load_screen:
		load_screen_path = ""
		print("[SceneManager] 强制使用默认加载屏幕")
	
	# 检查路径有效性
	if not ResourceLoader.exists(new_scene_path):
		push_error("[SceneManager] 错误：目标场景路径不存在: ", new_scene_path)
		return
	
	scene_switch_started.emit(current_scene_path, new_scene_path)
	
	# 如果目标场景就是当前场景，直接返回
	if current_scene_path == new_scene_path:
		print("[SceneManager] 场景已加载: ", new_scene_path)
		scene_switch_completed.emit(new_scene_path)
		return
	
	# 确定使用哪个加载屏幕
	var load_screen_to_use = _get_load_screen_instance(load_screen_path)
	if load_screen_path != "no_transition" and not load_screen_to_use:
		push_error("[SceneManager] 错误：无法获取加载屏幕，切换中止")
		return
	
	# 检查是否正在预加载这个场景
	if loading_scene_path == new_scene_path and loading_state == LoadState.LOADING:
		print("[SceneManager] 场景正在预加载中，等待完成...")
		await _handle_preloading_scene(new_scene_path, load_screen_to_use, use_cache)
		return
	
	# 检查缓存
	if use_cache and scene_cache.has(new_scene_path):
		print("[SceneManager] 从缓存加载场景: ", new_scene_path)
		await _handle_cached_scene(new_scene_path, load_screen_to_use)
		return
	
	# 直接加载场景
	print("[SceneManager] 直接加载场景: ", new_scene_path)
	await _handle_direct_load(new_scene_path, load_screen_to_use, use_cache)

# ==================== 公开API - 预加载 ====================

func preload_scene(scene_path: String) -> void:
	#"""
	#预加载场景到内存（不实例化）
	#
	#参数:
	#- scene_path: 要预加载的场景路径
	#"""
	# 检查路径有效性
	if not ResourceLoader.exists(scene_path):
		push_error("[SceneManager] 错误：预加载场景路径不存在: ", scene_path)
		return
	
	# 如果已经在加载中、已加载或在缓存中，直接返回
	if (loading_scene_path == scene_path and loading_state == LoadState.LOADING) or \
	   (loading_scene_path == scene_path and loading_state == LoadState.LOADED) or \
	   scene_cache.has(scene_path):
		print("[SceneManager] 场景已加载或正在加载: ", scene_path)
		return
	
	print("[SceneManager] 开始预加载场景: ", scene_path)
	scene_preload_started.emit(scene_path)
	
	# 设置加载状态
	loading_scene_path = scene_path
	loading_state = LoadState.LOADING
	
	# 异步或同步加载场景
	if use_async_loading:
		await _async_preload_scene(scene_path)
	else:
		_sync_preload_scene(scene_path)
	
	# 加载完成处理
	if loading_resource:
		loading_state = LoadState.LOADED
		scene_preload_completed.emit(scene_path)
		print("[SceneManager] 预加载完成: ", scene_path)
	else:
		loading_state = LoadState.NOT_LOADED
		loading_scene_path = ""
		print("[SceneManager] 预加载失败: ", scene_path)

# ==================== 公开API - 缓存管理 ====================

func clear_cache() -> void:
	#"""清空所有缓存场景"""
	print("[SceneManager] 清空缓存...")
	
	for scene_path in scene_cache:
		var cached = scene_cache[scene_path]
		if is_instance_valid(cached.scene_instance):
			cached.scene_instance.queue_free()
		scene_removed_from_cache.emit(scene_path)
	
	scene_cache.clear()
	cache_access_order.clear()
	print("[SceneManager] 缓存已清空")

func get_cache_info() -> Dictionary:
	#"""获取缓存信息"""
	var cached_scenes = []
	for path in scene_cache:
		var cached = scene_cache[path]
		cached_scenes.append({
			"path": path,
			"access_count": cached.access_count,
			"cached_time": cached.cached_time,
			"instance_valid": is_instance_valid(cached.scene_instance)
		})
	
	return {
		"size": scene_cache.size(),
		"max_size": max_cache_size,
		"access_order": cache_access_order.duplicate(),
		"cached_scenes": cached_scenes
	}

func is_scene_cached(scene_path: String) -> bool:
	#"""检查场景是否在缓存中"""
	return scene_cache.has(scene_path)

# ==================== 公开API - 实用函数 ====================

func get_current_scene() -> Node:
	#"""获取当前场景实例"""
	return current_scene

func get_previous_scene_path() -> String:
	#"""获取上一个场景路径"""
	return previous_scene_path

func get_loading_progress(scene_path: String) -> float:
	#"""获取场景加载进度（0.0-1.0）"""
	if loading_scene_path != scene_path or loading_state != LoadState.LOADING:
		return 1.0 if scene_cache.has(scene_path) else 0.0
	
	# 异步加载进度检查
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and progress.size() > 0:
		return progress[0]
	
	return 0.0

func set_max_cache_size(new_size: int) -> void:
	#"""动态设置最大缓存大小"""
	if new_size < 1:
		push_error("[SceneManager] 错误：缓存大小必须大于0")
		return
	
	max_cache_size = new_size
	print("[SceneManager] 设置最大缓存大小: ", max_cache_size)
	
	# 如果新大小小于当前缓存数量，需要清理
	while cache_access_order.size() > max_cache_size:
		_remove_oldest_cached_scene()

# ==================== 加载屏幕管理 ====================

func _get_load_screen_instance(load_screen_path: String) -> Node:
	#"""
	#获取加载屏幕实例
	#参数为空时返回默认，否则加载指定场景
	#"""
	if load_screen_path == "":
		# 使用默认加载屏幕
		if default_load_screen:
			print("[SceneManager] 使用默认加载屏幕")
			return default_load_screen
		else:
			push_error("[SceneManager] 错误：默认加载屏幕未初始化")
			return null
	elif load_screen_path == "no_transition":
		# 特殊值，表示无过渡
		print("[SceneManager] 使用无过渡模式")
		return null
	else:
		# 加载自定义加载屏幕
		if ResourceLoader.exists(load_screen_path):
			var custom_scene = load(load_screen_path)
			if custom_scene:
				var instance = custom_scene.instantiate()
				
				add_child(instance)
				print("[SceneManager] 使用自定义加载屏幕: ", load_screen_path)
				return instance
			else:
				print("[SceneManager] 警告：自定义加载屏幕加载失败，使用默认")
				return default_load_screen
		else:
			print("[SceneManager] 警告：自定义加载屏幕路径不存在，使用默认")
			return default_load_screen

func _show_load_screen(load_screen_instance: Node) -> void:
	#"""显示指定的加载屏幕实例"""
	if not load_screen_instance:
		print("[SceneManager] 无加载屏幕，直接切换")
		return
	
	active_load_screen = load_screen_instance
	
	# 设置可见性 - 根据节点类型处理
	if load_screen_instance is CanvasItem:
		load_screen_instance.visible = true
	elif load_screen_instance.has_method("set_visible"):
		load_screen_instance.set_visible(true)
	
	# 如果有淡入方法则调用
	if load_screen_instance.has_method("fade_in"):
		print("[SceneManager] 调用加载屏幕淡入效果")
		await load_screen_instance.fade_in()
	elif load_screen_instance.has_method("show_loading"):
		# 兼容其他可能的接口
		await load_screen_instance.show_loading()
	elif load_screen_instance.has_method("show"):
		# 通用show方法
		load_screen_instance.show()
	
	load_screen_shown.emit(load_screen_instance)
	print("[SceneManager] 加载屏幕显示完成")

func _hide_load_screen(load_screen_instance: Node) -> void:
	#"""隐藏指定的加载屏幕实例"""
	if not load_screen_instance:
		return
	
	# 如果有淡出方法则调用
	if load_screen_instance.has_method("fade_out"):
		print("[SceneManager] 调用加载屏幕淡出效果")
		await load_screen_instance.fade_out()
	elif load_screen_instance.has_method("hide_loading"):
		# 兼容其他可能的接口
		await load_screen_instance.hide_loading()
	elif load_screen_instance.has_method("hide"):
		# 通用hide方法
		load_screen_instance.hide()
	
	# 如果不是默认加载屏幕，使用后需要清理
	if load_screen_instance != default_load_screen:
		load_screen_instance.queue_free()
		print("[SceneManager] 清理自定义加载屏幕")
	else:
		# 设置可见性 - 根据节点类型处理
		if load_screen_instance is CanvasItem:
			load_screen_instance.visible = false
		elif load_screen_instance.has_method("set_visible"):
			load_screen_instance.set_visible(false)
	
	active_load_screen = null
	load_screen_hidden.emit(load_screen_instance)
	print("[SceneManager] 加载屏幕隐藏完成")

# ==================== 场景切换处理函数 ====================

func _handle_preloading_scene(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	#"""处理正在预加载的场景"""
	# 显示加载屏幕
	await _show_load_screen(load_screen_instance)
	
	# 等待预加载完成
	await _wait_for_preload(scene_path)
	
	# 实例化并切换到场景
	await _instantiate_and_switch(scene_path, load_screen_instance, use_cache)

func _handle_cached_scene(scene_path: String, load_screen_instance: Node) -> void:
	#"""处理从缓存加载的场景"""
	# 显示加载屏幕
	await _show_load_screen(load_screen_instance)
	
	# 切换到缓存场景
	await _switch_to_cached_scene(scene_path, load_screen_instance)

func _handle_direct_load(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	#"""处理直接加载的场景"""
	# 显示加载屏幕
	await _show_load_screen(load_screen_instance)
	
	# 将当前场景加入缓存
	if current_scene and use_cache:
		_cache_current_scene()
	
	# 加载并切换新场景
	await _load_and_switch(scene_path, load_screen_instance, use_cache)

# ==================== 加载和切换核心函数 ====================

func _wait_for_preload(scene_path: String) -> void:
	#"""等待预加载完成"""
	print("[SceneManager] 等待预加载完成: ", scene_path)
	
	var wait_start_time = Time.get_ticks_msec()
	while loading_scene_path == scene_path and loading_state == LoadState.LOADING:
		# 每500ms打印一次进度
		if Time.get_ticks_msec() - wait_start_time > 500:
			var progress = get_loading_progress(scene_path)
			print("[SceneManager] 预加载进度: ", progress * 100, "%")
			wait_start_time = Time.get_ticks_msec()
		
		await get_tree().process_frame
	
	print("[SceneManager] 预加载等待完成")

func _instantiate_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	#"""实例化预加载的场景并切换"""
	if not loading_resource or loading_scene_path != scene_path:
		push_error("[SceneManager] 预加载资源不存在或路径不匹配")
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] 实例化预加载场景: ", scene_path)
	
	# 创建场景实例
	var new_scene = loading_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] 实例化场景失败")
		await _hide_load_screen(load_screen_instance)
		return
	
	# 执行场景切换
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)
	
	# 重置加载状态
	loading_scene_path = ""
	loading_state = LoadState.NOT_LOADED
	loading_resource = null

func _switch_to_cached_scene(scene_path: String, load_screen_instance: Node) -> void:
	#"""切换到缓存中的场景"""
	if not scene_cache.has(scene_path):
		push_error("[SceneManager] 缓存中找不到场景: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	var cached = scene_cache[scene_path]
	if not is_instance_valid(cached.scene_instance):
		push_error("[SceneManager] 缓存场景实例无效")
		scene_cache.erase(scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	print("[SceneManager] 使用缓存场景: ", scene_path)
	
	# 更新缓存访问顺序和统计
	_update_cache_access(scene_path)
	cached.access()
	
	# 执行场景切换
	await _perform_scene_switch(cached.scene_instance, scene_path, load_screen_instance, true)

func _load_and_switch(scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	#"""直接加载并切换场景"""
	print("[SceneManager] 加载场景: ", scene_path)
	
	# 加载场景资源
	var new_scene_resource = load(scene_path)
	if not new_scene_resource:
		push_error("[SceneManager] 场景加载失败: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	# 实例化场景
	var new_scene = new_scene_resource.instantiate()
	if not new_scene:
		push_error("[SceneManager] 场景实例化失败: ", scene_path)
		await _hide_load_screen(load_screen_instance)
		return
	
	# 执行场景切换
	await _perform_scene_switch(new_scene, scene_path, load_screen_instance, use_cache)

func _perform_scene_switch(new_scene: Node, new_scene_path: String, load_screen_instance: Node, use_cache: bool) -> void:
	#"""执行实际场景切换的核心逻辑"""
	print("[SceneManager] 执行场景切换到: ", new_scene_path)
	
	# 1. 更新场景引用
	previous_scene_path = current_scene_path
	current_scene_path = new_scene_path
	
	# 2. 移除当前场景（不立即释放，可能加入缓存）
	var old_scene = current_scene
	if old_scene and old_scene != new_scene:
		print("[SceneManager] 移除当前场景: ", old_scene.name)
		
		# 从场景树中移除
		if old_scene.is_inside_tree():
			old_scene.get_parent().remove_child(old_scene)
		
		# 如果使用缓存且不是同一个场景，尝试缓存旧场景
		if use_cache and old_scene.scene_file_path != "" and old_scene.scene_file_path != new_scene_path:
			_cache_scene(old_scene)
		else:
			# 否则释放
			old_scene.queue_free()
	
	# 3. 添加新场景到场景树
	print("[SceneManager] 添加新场景: ", new_scene.name)
	get_tree().root.add_child(new_scene)
	
	# 4. 设置当前场景
	get_tree().current_scene = new_scene
	current_scene = new_scene
	
	# 5. 等待场景准备就绪
	if not new_scene.is_node_ready():
		print("[SceneManager] 等待新场景准备就绪...")
		await new_scene.ready
	
	# 6. 隐藏加载屏幕
	await _hide_load_screen(load_screen_instance)
	
	# 7. 发出完成信号
	scene_switch_completed.emit(new_scene_path)
	print("[SceneManager] 场景切换完成: ", new_scene_path)

# ==================== 缓存管理内部函数 ====================

func _cache_current_scene() -> void:
	#"""将当前场景加入缓存"""
	if not current_scene:
		return
	
	_cache_scene(current_scene)

func _cache_scene(scene: Node) -> void:
	#"""将指定场景加入缓存"""
	var scene_path = scene.scene_file_path
	if scene_path == "":
		print("[SceneManager] 警告：场景没有文件路径，无法缓存")
		return
	
	# 检查是否已在缓存中
	if scene_cache.has(scene_path):
		print("[SceneManager] 场景已在缓存中: ", scene_path)
		_update_cache_access(scene_path)
		return
	
	print("[SceneManager] 缓存场景: ", scene_path)
	
	# 确保场景不在场景树中
	if scene.is_inside_tree():
		scene.get_parent().remove_child(scene)
	
	# 创建缓存项
	var cached = CachedScene.new(scene)
	scene_cache[scene_path] = cached
	cache_access_order.append(scene_path)
	scene_cached.emit(scene_path)
	
	# 检查缓存是否已满
	if cache_access_order.size() > max_cache_size:
		_remove_oldest_cached_scene()

func _update_cache_access(scene_path: String) -> void:
	#"""更新缓存的访问顺序（LRU算法）"""
	var index = cache_access_order.find(scene_path)
	if index != -1:
		cache_access_order.remove_at(index)
	cache_access_order.append(scene_path)
	
	# 更新最后访问时间
	if scene_cache.has(scene_path):
		var cached = scene_cache[scene_path]
		cached.cached_time = Time.get_unix_time_from_system()

func _remove_oldest_cached_scene() -> void:
	#"""移除最旧的缓存场景"""
	if cache_access_order.size() == 0:
		return
	
	var oldest_path = cache_access_order[0]
	cache_access_order.remove_at(0)
	
	if scene_cache.has(oldest_path):
		var cached = scene_cache[oldest_path]
		if is_instance_valid(cached.scene_instance):
			cached.scene_instance.queue_free()
		scene_cache.erase(oldest_path)
		scene_removed_from_cache.emit(oldest_path)
		print("[SceneManager] 移除旧缓存: ", oldest_path)

# ==================== 预加载内部函数 ====================

func _async_preload_scene(scene_path: String) -> void:
	#"""异步预加载场景"""
	print("[SceneManager] 异步预加载: ", scene_path)
	
	# 使用ResourceLoader异步加载
	var load_start_time = Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(scene_path)
	
	# 等待加载完成
	while true:
		var status = ResourceLoader.load_threaded_get_status(scene_path)
		
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				# 每500ms打印一次进度
				if Time.get_ticks_msec() - load_start_time > 500:
					var progress = []
					ResourceLoader.load_threaded_get_status(scene_path, progress)
					if progress.size() > 0:
						print("[SceneManager] 异步加载进度: ", progress[0] * 100, "%")
					load_start_time = Time.get_ticks_msec()
				
				await get_tree().process_frame
			
			ResourceLoader.THREAD_LOAD_LOADED:
				# 加载成功
				loading_resource = ResourceLoader.load_threaded_get(scene_path)
				print("[SceneManager] 异步预加载完成: ", scene_path)
				return
			
			ResourceLoader.THREAD_LOAD_FAILED:
				# 加载失败
				push_error("[SceneManager] 异步加载失败: ", scene_path)
				loading_resource = null
				return
			
			_:
				push_error("[SceneManager] 未知加载状态: ", status)
				loading_resource = null
				return

func _sync_preload_scene(scene_path: String) -> void:
	#"""同步预加载场景"""
	print("[SceneManager] 同步预加载: ", scene_path)
	loading_resource = load(scene_path)

# ==================== 错误处理 ====================

func _handle_scene_switch_error(error: String, load_screen_instance: Node) -> void:
	#"""处理场景切换错误"""
	push_error("[SceneManager] 场景切换错误: ", error)
	
	# 隐藏加载屏幕
	if load_screen_instance:
		_hide_load_screen(load_screen_instance)
	
	# 发出错误信号
	scene_switch_completed.emit("")  # 空路径表示错误

# ==================== 调试和工具函数 ====================

func print_debug_info() -> void:
	#"""打印调试信息"""
	print("\n=== SceneManager 调试信息 ===")
	print("当前场景: ", current_scene_path if current_scene else "None")
	print("上一个场景: ", previous_scene_path)
	print("缓存数量: ", scene_cache.size(), "/", max_cache_size)
	print("缓存访问顺序: ", cache_access_order)
	print("正在加载的场景: ", loading_scene_path if loading_scene_path != "" else "None")
	print("加载状态: ", LoadState.keys()[loading_state])
	print("默认加载屏幕: ", "已加载" if default_load_screen else "未加载")
	print("活动加载屏幕: ", "有" if active_load_screen else "无")
	print("使用异步加载: ", use_async_loading)
	print("始终使用默认加载屏幕: ", always_use_default_load_screen)
	print("===============================\n")

# ==================== 信号连接辅助 ====================

func connect_all_signals(target: Object) -> void:
	#"""连接所有信号到目标对象"""
	if not target:
		return
	
	# 获取所有信号
	var signals_list = get_signal_list()
	for signal_info in signals_list:
		var signal_name = signal_info["name"]
		
		# 检查目标是否有对应的处理函数
		var method_name = "_on_scene_manager_" + signal_name
		if target.has_method(method_name):
			connect(signal_name, Callable(target, method_name))
			print("[SceneManager] 连接信号: ", signal_name, " -> ", method_name)
