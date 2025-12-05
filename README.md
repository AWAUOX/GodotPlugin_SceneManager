Long Scene Manager Plugin


## 在你的游戏脚本中使用
## 1. 使用默认加载屏幕切换场景
await LongSceneManager.switch_scene("res://scenes/level2.tscn")

## 2. 使用自定义加载屏幕切换场景
await LongSceneManager.switch_scene(
	"res://scenes/level2.tscn", 
	true,  # 使用缓存
	"res://ui/custom_load_screen.tscn"  # 自定义加载屏幕
)
## 3. 无过渡效果切换场景
await LongSceneManager.switch_scene(
	"res://scenes/level2.tscn", 
	true, 
	"no_transition"  # 特殊值，表示无过渡
)
## 4. 预加载场景
LongSceneManager.preload_scene("res://scenes/level3.tscn")
## 5. 获取缓存信息
var cache_info = LongSceneManager.get_cache_info()
print("缓存信息: ", cache_info)
## 6. 动态调整缓存大小
LongSceneManager.set_max_cache_size(10)
## 7. 清空缓存
LongSceneManager.clear_cache()
## 8. 打印调试信息
LongSceneManager.print_debug_info()
