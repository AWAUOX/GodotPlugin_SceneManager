extends Node2D
# 测试场景1脚本

const MAIN_SCENE_PATH = "res://demo_test_scene_manager/main_scene.tscn"
const TEST_SCENE_2_PATH = "res://demo_test_scene_manager/test_scene_2.tscn"

var is_first_enter:bool = true

@onready var button_main: Button = $VBoxContainer/Button_Main
@onready var button_scene2: Button = $VBoxContainer/Button_Scene2
@onready var button_back: Button = $VBoxContainer/Button_Back
@onready var label_info: Label = $VBoxContainer/Label_Info


func _ready():
	print("=== Test Scene 1 Loaded ===")
	
	# 连接按钮信号
	#button_main.pressed.connect(_on_main_pressed)
	#button_scene2.pressed.connect(_on_scene2_pressed)
	#button_back.pressed.connect(_on_back_pressed)
	
	# 更新信息标签
	_update_info_label()
	is_first_enter = false
	
	# 连接SceneManager信号
	LongSceneManager.scene_switch_started.connect(_on_scene_switch_started)
	LongSceneManager.scene_switch_completed.connect(_on_scene_switch_completed)
	
	
func _enter_tree() -> void:
	if not is_first_enter:
		_update_info_label()
		
func _process(delta: float) -> void:
	_update_info_label()

func _update_info_label():
	#LongSceneManager.print_debug_info()
	#"""更新显示信息"""
	var cache_info = LongSceneManager.get_cache_info()
	
	label_info.text = """
    上一个场景: {previous}
    缓存实例场景数: {cache_count}/{cache_max}
	缓存最大数值: {cache_max}
    缓存实例场景列表: {cache_list}
	预加载资源缓存数量: {preload_cache_size}
	预加载缓存最大数值: {preload_cache_max}
	""".format({
		"previous": LongSceneManager.get_previous_scene_path(),
		"cache_count": cache_info.instance_cache_size,
		"cache_max": cache_info.max_size,
		"cache_list": ",\n ".join(cache_info.access_order),
		"preload_cache_size": LongSceneManager.preload_resource_cache.size(),
		"preload_cache_max": LongSceneManager.max_preload_resource_cache_size
	})
	

func _on_main_pressed():
	#"""切换回主场景"""
	print("切换回主场景")
	await LongSceneManager.switch_scene(MAIN_SCENE_PATH, true, "")

func _on_scene2_pressed():
	#"""切换到场景2"""
	print("切换到场景2")
	await LongSceneManager.switch_scene(TEST_SCENE_2_PATH, true, "")

func _on_back_pressed():
	#"""返回按钮（特殊测试：无过渡效果）"""
	print("返回主场景（无过渡效果）")
	await LongSceneManager.switch_scene(MAIN_SCENE_PATH, true, "no_transition")

func _on_scene_switch_started(from_scene: String, to_scene: String):
	print("场景1 - 切换开始: ", from_scene, " -> ", to_scene)

func _on_scene_switch_completed(scene_path: String):
	print("场景1 - 切换完成: ", scene_path)
