# # 主场景脚本 - 用于测试场景切换

# extends Control

# # 场景路径常量
# const TEST_SCENE_1_PATH = "res://demo_test_scene_manager/test_scene_1.tscn"
# const TEST_SCENE_2_PATH = "res://demo_test_scene_manager/test_scene_2.tscn"

# @onready var button_scene_1: Button = $VBoxContainer/Button_Scene1
# @onready var button_scene_2: Button = $VBoxContainer/Button_Scene2
# @onready var button_preload_1: Button = $VBoxContainer/Button_Preload1
# @onready var button_preload_2: Button = $VBoxContainer/Button_Preload2
# @onready var button_clear_cache: Button = $VBoxContainer/Button_ClearCache
# @onready var label_info: Label = $VBoxContainer/Label_Info


# var is_first_enter:bool = true

# func _ready():
# 	print("=== Main Scene Loaded ===")
	
# 	# 连接按钮信号
# 	button_scene_1.pressed.connect(_on_scene1_pressed)
# 	button_scene_2.pressed.connect(_on_scene2_pressed)
# 	button_preload_1.pressed.connect(_on_preload1_pressed)
# 	button_preload_2.pressed.connect(_on_preload2_pressed)
# 	button_clear_cache.pressed.connect(_on_clear_cache_pressed)
	
# 	# 更新信息标签
# 	_update_info_label()
# 	is_first_enter = false
	
# 	# 连接SceneManager信号
# 	LongSceneManager.scene_switch_started.connect(_on_scene_switch_started)
# 	LongSceneManager.scene_switch_completed.connect(_on_scene_switch_completed)
# 	LongSceneManager.scene_cached.connect(_on_scene_cached)
	
# func _enter_tree() -> void:
# 	if not is_first_enter:
# 		_update_info_label()
		
# func _process(delta: float) -> void:
# 	_update_info_label()
		


# func _update_info_label():
# 	#LongSceneManager.print_debug_info()
# 	##"更新显示信息"""
# 	var cache_info:Dictionary = LongSceneManager.get_cache_info()
	
# 	label_info.text = """
# 	当前场景: Main Scene
# 	上一个场景: {previous}
# 	缓存实例场景数: {cache_count}/{cache_max}
# 	缓存最大数值: {cache_max}
# 	缓存实例场景列表: {cache_list}
# 	预加载资源缓存数量: {preload_cache_size}
# 	预加载缓存最大数值: {preload_cache_max}
# 	""".format({
# 		"previous": LongSceneManager.get_previous_scene_path(),
# 		"cache_count": cache_info.instance_cache_size,
# 		"cache_max": cache_info.max_size,
# 		"cache_list": ",\n ".join(cache_info.access_order),
# 		"preload_cache_size": LongSceneManager.preload_resource_cache.size(),
# 		"preload_cache_max": LongSceneManager.max_preload_resource_cache_size
# 	})

# func _on_scene1_pressed():
# 	##"切换到场景1（使用默认加载屏幕）"""
# 	print("切换到场景1")
# 	await LongSceneManager.switch_scene(TEST_SCENE_1_PATH, true, "")

# func _on_scene2_pressed():
# 	##"切换到场景2（使用默认加载屏幕）"""
# 	print("切换到场景2")
# 	await LongSceneManager.switch_scene(TEST_SCENE_2_PATH, true, "")

# func _on_preload1_pressed():
# 	##"预加载场景1"""
# 	print("预加载场景1")
# 	LongSceneManager.preload_scene(TEST_SCENE_1_PATH)
# 	#LongSceneManager.print_debug_info()
# 	_update_info_label()

# func _on_preload2_pressed():
# 	##"预加载场景2"""
# 	print("预加载场景2")
# 	LongSceneManager.preload_scene(TEST_SCENE_2_PATH)
# 	#LongSceneManager.print_debug_info()
# 	_update_info_label()

# func _on_clear_cache_pressed():
# 	##"清空缓存"""
# 	print("清空缓存")
# 	LongSceneManager.clear_cache()
# 	#LongSceneManager.print_debug_info()
# 	_update_info_label()

# func _on_scene_switch_started(from_scene: String, to_scene: String):
# 	print("场景切换开始: ", from_scene, " -> ", to_scene)

# func _on_scene_switch_completed(scene_path: String):
# 	print("场景切换完成: ", scene_path)

# func _on_scene_cached(scene_path: String):
# 	print("场景已缓存: ", scene_path)
# 	_update_info_label()



# ******************************************************************************
# 以下是使用C#版本SceneManagerCs的代码
# ******************************************************************************


extends Control

# 场景路径常量
const TEST_SCENE_1_PATH = "res://demo_test_scene_manager/test_scene_1.tscn"
const TEST_SCENE_2_PATH = "res://demo_test_scene_manager/test_scene_2.tscn"

@onready var button_scene_1: Button = $VBoxContainer/Button_Scene1
@onready var button_scene_2: Button = $VBoxContainer/Button_Scene2
@onready var button_preload_1: Button = $VBoxContainer/Button_Preload1
@onready var button_preload_2: Button = $VBoxContainer/Button_Preload2
@onready var button_clear_cache: Button = $VBoxContainer/Button_ClearCache
@onready var label_info: Label = $VBoxContainer/Label_Info

var is_first_enter: bool = true

func _ready():
	print("=== Main Scene Loaded ===")
	
	# 连接按钮信号
	button_scene_1.pressed.connect(_on_scene1_pressed)
	button_scene_2.pressed.connect(_on_scene2_pressed)
	button_preload_1.pressed.connect(_on_preload1_pressed)
	button_preload_2.pressed.connect(_on_preload2_pressed)
	button_clear_cache.pressed.connect(_on_clear_cache_pressed)
	
	# 更新信息标签
	_update_info_label()
	is_first_enter = false
	
	# 连接SceneManagerCs信号 - 使用get_node方式
	_connect_to_scene_manager_signals()

func _connect_to_scene_manager_signals():
	# 尝试几种可能的访问方式
	var sceneManagers = [
		get_node_or_null("/root/LongSceneManagerCs"),
		get_node_or_null("/root/SceneManager"),
		get_node_or_null("/root/LongSceneManagerCs")
	]
	
	var sceneManager = null
	for mgr in sceneManagers:
		if mgr != null:
			sceneManager = mgr
			print("找到场景管理器: ", mgr.get_class())
			break
	
	if sceneManager != null:
		if sceneManager.has_signal("scene_switch_started"):
			sceneManager.connect("scene_switch_started", _on_scene_switch_started)
		if sceneManager.has_signal("scene_switch_completed"):
			sceneManager.connect("scene_switch_completed", _on_scene_switch_completed)
		if sceneManager.has_signal("scene_cached"):
			sceneManager.connect("scene_cached", _on_scene_cached)
	else:
		printerr("未找到任何场景管理器单例!")

func _enter_tree() -> void:
	if not is_first_enter:
		_update_info_label()
		
func _process(delta: float) -> void:
	_update_info_label()

func _get_scene_manager():
	# 尝试几种可能的访问方式
	var managers = [
		get_node_or_null("/root/SceneManagerCs"),
		get_node_or_null("/root/SceneManager"),
		get_node_or_null("/root/LongSceneManager")
	]
	
	for mgr in managers:
		if mgr != null:
			return mgr
	
	printerr("未找到场景管理器单例!")
	return null

func _update_info_label():
	# 获取缓存信息 - 使用改进的方式访问C#单例
	var sceneManager = _get_scene_manager()
	if sceneManager == null:
		label_info.text = "错误: 未找到场景管理器单例!"
		return
		
	# 检查是否有get_cache_info方法
	if not sceneManager.has_method("get_cache_info"):
		label_info.text = "错误: 场景管理器缺少get_cache_info方法!"
		return
	
	var cache_info: Dictionary = sceneManager.get_cache_info()
	
	# 安全地访问字典值
	var previous_scene = ""
	var instance_cache_size = 0
	var max_size = 0
	var access_order_text = ""
	var preload_cache_size = 0
	var max_preload_resource_cache_size = 0
	
	if cache_info.has("instance_cache_size"):
		instance_cache_size = cache_info["instance_cache_size"]
	
	if cache_info.has("max_size"):
		max_size = cache_info["max_size"]
	
	if cache_info.has("access_order"):
		if cache_info["access_order"] is Array and cache_info["access_order"].size() > 0:
			access_order_text = ",\n ".join(cache_info["access_order"])
	
	if cache_info.has("preload_cache_size"):
		preload_cache_size = cache_info["preload_cache_size"]
	
	if cache_info.has("max_preload_resource_cache_size"):
		max_preload_resource_cache_size = cache_info["max_preload_resource_cache_size"]
	
	# 获取上一个场景路径
	if sceneManager.has_method("get_previous_scene_path"):
		previous_scene = sceneManager.get_previous_scene_path()
	
	label_info.text = """
    当前场景: Main Scene
    上一个场景: %s
    缓存实例场景数: %d/%d
	缓存最大数值: %d
    缓存实例场景列表: %s
	预加载资源缓存数量: %d
	预加载缓存最大数值: %d
	""" % [
		previous_scene,
		instance_cache_size,
		max_size,
		max_size,
		access_order_text,
		preload_cache_size,
		max_preload_resource_cache_size
	]

func _on_scene1_pressed():
	"""切换到场景1（使用默认加载屏幕）"""
	print("切换到场景1")
	var sceneManager = _get_scene_manager()
	if sceneManager != null and sceneManager.has_method("switch_scene"):
		await sceneManager.switch_scene(TEST_SCENE_1_PATH, true, "")

func _on_scene2_pressed():
	"""切换到场景2（使用默认加载屏幕）"""
	print("切换到场景2")
	var sceneManager = _get_scene_manager()
	if sceneManager != null and sceneManager.has_method("switch_scene"):
		await sceneManager.switch_scene(TEST_SCENE_2_PATH, true, "")

func _on_preload1_pressed():
	"""预加载场景1"""
	print("预加载场景1")
	var sceneManager = _get_scene_manager()
	if sceneManager != null and sceneManager.has_method("preload_scene"):
		sceneManager.preload_scene(TEST_SCENE_1_PATH)
	_update_info_label()

func _on_preload2_pressed():
	"""预加载场景2"""
	print("预加载场景2")
	var sceneManager = _get_scene_manager()
	if sceneManager != null and sceneManager.has_method("preload_scene"):
		sceneManager.preload_scene(TEST_SCENE_2_PATH)
	_update_info_label()

func _on_clear_cache_pressed():
	"""清空缓存"""
	print("清空缓存")
	var sceneManager = _get_scene_manager()
	if sceneManager != null and sceneManager.has_method("clear_cache"):
		sceneManager.clear_cache()
	_update_info_label()

func _on_scene_switch_started(from_scene: String, to_scene: String):
	print("场景切换开始: ", from_scene, " -> ", to_scene)

func _on_scene_switch_completed(scene_path: String):
	print("场景切换完成: ", scene_path)

func _on_scene_cached(scene_path: String):
	print("场景已缓存: ", scene_path)
	_update_info_label()
