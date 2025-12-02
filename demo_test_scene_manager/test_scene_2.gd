extends Node2D
# 测试场景2脚本

const MAIN_SCENE_PATH = "res://demo_test_scene_manager/main_scene.tscn"
const TEST_SCENE_1_PATH = "res://demo_test_scene_manager/test_scene_1.tscn"



@onready var button_main: Button = $VBoxContainer/Button_Main
@onready var button_scene1: Button = $VBoxContainer/Button_Scene1
@onready var button_preload_main: Button = $VBoxContainer/Button_PreloadMain
@onready var label_info: Label = $VBoxContainer/Label_Info
@onready var progress_bar: ProgressBar = $ProgressBar




func _ready():
	print("=== Test Scene 2 Loaded ===")
	
	# 连接按钮信号
	#button_main.pressed.connect(_on_main_pressed)
	#button_scene1.pressed.connect(_on_scene1_pressed)
	#button_preload_main.pressed.connect(_on_preload_main_pressed)
	
	# 更新信息
	_update_info()
	
	# 连接SceneManager信号
	LongSceneManager.scene_switch_started.connect(_on_scene_switch_started)
	LongSceneManager.scene_switch_completed.connect(_on_scene_switch_completed)

func _process(delta):
	#"""每帧更新预加载进度"""
	var progress = LongSceneManager.get_loading_progress(MAIN_SCENE_PATH)
	progress_bar.value = progress * 100
	
	if progress < 1.0 and progress > 0:
		label_info.text = "预加载主场景进度: " + str(round(progress * 100)) + "%"

func _update_info():
	#"""更新显示信息"""
	var cache_info = LongSceneManager.get_cache_info()
	
	label_info.text = """
    当前场景: Test Scene 2
    上一个场景: {previous}
    缓存数量: {cache_count}/{cache_max}
    主场景预加载: {preload_progress}%
	""".format({
		"previous": LongSceneManager.get_previous_scene_path(),
		"cache_count": cache_info.size,
		"cache_max": cache_info.max_size,
		"preload_progress": round(LongSceneManager.get_loading_progress(MAIN_SCENE_PATH) * 100)
	})

func _on_main_pressed():
	#"""切换回主场景"""
	print("切换回主场景")
	await LongSceneManager.switch_scene(MAIN_SCENE_PATH, true, "")

func _on_scene1_pressed():
	#"""切换到场景1"""
	print("切换到场景1")
	await LongSceneManager.switch_scene(TEST_SCENE_1_PATH, true, "")

func _on_preload_main_pressed():
	#"""预加载主场景"""
	print("预加载主场景")
	LongSceneManager.preload_scene(MAIN_SCENE_PATH)
	_update_info()

func _on_scene_switch_started(from_scene: String, to_scene: String):
	print("场景2 - 切换开始: ", from_scene, " -> ", to_scene)

func _on_scene_switch_completed(scene_path: String):
	print("场景2 - 切换完成: ", scene_path)
