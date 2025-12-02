extends Control


## 在你的游戏脚本中使用
## 1. 使用默认加载屏幕切换场景
#await LongSceneManager.switch_scene("res://scenes/level2.tscn")

## 2. 使用自定义加载屏幕切换场景
#await LongSceneManager.switch_scene(
	#"res://scenes/level2.tscn", 
	#true,  # 使用缓存
	#"res://ui/custom_load_screen.tscn"  # 自定义加载屏幕
#)
## 3. 无过渡效果切换场景
#await LongSceneManager.switch_scene(
	#"res://scenes/level2.tscn", 
	#true, 
	#"no_transition"  # 特殊值，表示无过渡
#)
## 4. 预加载场景
#LongSceneManager.preload_scene("res://scenes/level3.tscn")
## 5. 获取缓存信息
#var cache_info = LongSceneManager.get_cache_info()
#print("缓存信息: ", cache_info)
## 6. 动态调整缓存大小
#LongSceneManager.set_max_cache_size(10)
## 7. 清空缓存
#LongSceneManager.clear_cache()
## 8. 打印调试信息
#LongSceneManager.print_debug_info()


# 主场景脚本 - 用于测试场景切换

# 场景路径常量
const TEST_SCENE_1_PATH = "res://demo_test_scene_manager/test_scene_1.tscn"
const TEST_SCENE_2_PATH = "res://demo_test_scene_manager/test_scene_2.tscn"



@onready var button_scene_1: Button = $VBoxContainer/Button_Scene1
@onready var button_scene_2: Button = $VBoxContainer/Button_Scene2
@onready var button_preload_1: Button = $VBoxContainer/Button_Preload1
@onready var button_preload_2: Button = $VBoxContainer/Button_Preload2
@onready var button_clear_cache: Button = $VBoxContainer/Button_ClearCache
@onready var label_info: Label = $VBoxContainer/Label_Info



var is_first_enter:bool = true

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
	
	# 连接SceneManager信号
	LongSceneManager.scene_switch_started.connect(_on_scene_switch_started)
	LongSceneManager.scene_switch_completed.connect(_on_scene_switch_completed)
	LongSceneManager.scene_cached.connect(_on_scene_cached)
	
func _enter_tree() -> void:
	if not is_first_enter:
		_update_info_label()

func _update_info_label():
	#"""更新显示信息"""
	var cache_info:Dictionary = LongSceneManager.get_cache_info()
	
	label_info.text = """
    当前场景: Main Scene
    上一个场景: {previous}
    缓存场景数量: {cache_count}/{cache_max}
    缓存场景列表: {cache_list}
	
	""".format({
		"previous": LongSceneManager.get_previous_scene_path(),
		"cache_count": cache_info.size,
		"cache_max": cache_info.max_size,
		"cache_list": ",\n ".join(cache_info.access_order)
	})

func _on_scene1_pressed():
	#"""切换到场景1（使用默认加载屏幕）"""
	print("切换到场景1")
	await LongSceneManager.switch_scene(TEST_SCENE_1_PATH, true, "")

func _on_scene2_pressed():
	#"""切换到场景2（使用默认加载屏幕）"""
	print("切换到场景2")
	await LongSceneManager.switch_scene(TEST_SCENE_2_PATH, true, "")

func _on_preload1_pressed():
	#"""预加载场景1"""
	print("预加载场景1")
	LongSceneManager.preload_scene(TEST_SCENE_1_PATH)
	_update_info_label()

func _on_preload2_pressed():
	#"""预加载场景2"""
	print("预加载场景2")
	LongSceneManager.preload_scene(TEST_SCENE_2_PATH)
	_update_info_label()

func _on_clear_cache_pressed():
	#"""清空缓存"""
	print("清空缓存")
	LongSceneManager.clear_cache()
	_update_info_label()

func _on_scene_switch_started(from_scene: String, to_scene: String):
	print("场景切换开始: ", from_scene, " -> ", to_scene)

func _on_scene_switch_completed(scene_path: String):
	print("场景切换完成: ", scene_path)

func _on_scene_cached(scene_path: String):
	print("场景已缓存: ", scene_path)
	_update_info_label()
