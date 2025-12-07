# Long Scene Manager Plugin

[English Documentation](README.md)

Long Scene Manager 是一个 Godot 插件，旨在简化和优化场景切换过程，特别是对于需要长时间加载的复杂场景。它通过提供异步场景加载、缓存机制和可定制的加载界面来改善用户体验。

**注意：** 本文档仍在更新中。中文注解已经完整实现，但英文注解基本完善，案例项目除外。

## 图标

插件在 `image_icon` 文件夹中包含以下图标：
- ![主场景图标](addons/long_scene_manager/image_icon/main_scene.png) 主场景
- ![场景1图标](addons/long_scene_manager/image_icon/scene1.png) 场景1
- ![场景2图标](addons/long_scene_manager/image_icon/scene2.png) 场景2

## 功能特性

- **异步场景切换**：使用 `await` 实现非阻塞式场景切换
- **可定制的加载屏幕**：支持默认和自定义加载 UI 场景
- **无过渡模式**：通过 `"no_transition"` 选项实现快速切换
- **场景预加载**：提前将场景加载到内存缓存中
- **缓存管理**：可配置的最大缓存大小、缓存清除和缓存状态检索
- **LRU 缓存策略**：实现最近最少使用缓存淘汰策略
- **调试支持**：内部状态打印用于诊断

## 安装方法

1. 将 `addons/long_scene_manager` 文件夹复制到项目的 `addons` 文件夹中
2. 在 Godot 中启用插件：
   - 转到 `Project → Project Settings → Plugins`
   - 找到 "Long Scene Manager" 并将其状态设置为 "Active"

## 插件配置

该插件实现为全局自动加载单例。根据您想要使用 GDScript 还是 C# 实现，您需要在 `plugin.cfg` 文件中更改脚本，并在自动加载设置中核对路径：

1. 打开 `addons/long_scene_manager/plugin.cfg`
2. 修改 `script` 条目以指向 GDScript 或 C# 实现：
   - 对于 GDScript：`script="res://addons/long_scene_manager/autoload/long_scene_manager.gd"`
   - 对于 C#：`script="res://addons/long_scene_manager/autoload/LongSceneManagerCs.cs"`
3. 在项目设置 → 自动加载中，确认为 `LongSceneManager` 单例注册了正确的路径

## 缓存机制

插件实现了双层缓存系统：

1. **实例缓存**：存储完全实例化的场景节点，这些节点当前未处于活动状态但在内存中保留以便快速切换
2. **预加载资源缓存**：存储已加载的 PackedScene 资源，以便更快地实例化

两种缓存都实现了 LRU（最近最少使用）淘汰策略，具有可配置的最大大小：
- 实例缓存：由 `max_cache_size` 控制（默认：8）
- 预加载资源缓存：由 `max_preload_resource_cache_size` 控制（默认：20）

当缓存达到最大容量时，最近最少使用的项目会被自动移除以为新项目腾出空间。

## 使用方法

### 1. 使用默认加载屏幕切换场景
```gdscript
await LongSceneManager.switch_scene("res://scenes/level2.tscn")
```

### 2. 使用自定义加载屏幕切换场景
```gdscript
await LongSceneManager.switch_scene(
    "res://scenes/level2.tscn", 
    true,  # 使用缓存
    "res://ui/custom_load_screen.tscn"  # 自定义加载屏幕
)
```

### 3. 无过渡效果切换场景
```gdscript
await LongSceneManager.switch_scene(
    "res://scenes/level2.tscn", 
    true, 
    "no_transition"  # 特殊值，表示无过渡
)
```

### 4. 预加载场景
```gdscript
LongSceneManager.preload_scene("res://scenes/level3.tscn")
```

### 5. 获取缓存信息
```gdscript
var cache_info = LongSceneManager.get_cache_info()
print("缓存信息: ", cache_info)
```

### 6. 动态调整缓存大小
```gdscript
LongSceneManager.set_max_cache_size(10)
```

### 7. 清空缓存
```gdscript
LongSceneManager.clear_cache()
```

### 8. 打印调试信息
```gdscript
LongSceneManager.print_debug_info()
```

## API 参考

### 场景切换方法

- `switch_scene(scene_path: String, use_cache: bool = true, load_screen_path: String = "")`
  切换到新场景，可选择使用缓存和自定义加载屏幕
  
- `switch_scene_gd(scene_path: String, use_cache: bool = true, load_screen_path: String = "")`
  GDScript 兼容的场景切换包装器

### 预加载方法

- `preload_scene(scene_path: String)`
  将场景预加载到缓存中
  
- `preload_scene_gd(scene_path: String)`
  GDScript 兼容的场景预加载包装器

### 缓存管理方法

- `clear_cache()`
  清除所有缓存的场景和预加载资源
  
- `get_cache_info()`
  获取当前缓存状态的详细信息
  
- `is_scene_cached(scene_path: String)`
  检查场景当前是否已缓存
  
- `set_max_cache_size(new_size: int)`
  设置可缓存场景的最大数量
  
- `set_max_preload_resource_cache_size(new_size: int)`
  设置可缓存的预加载资源的最大数量

### 实用方法

- `get_current_scene()`
  获取当前场景实例
  
- `get_previous_scene_path()`
  获取上一个场景的路径
  
- `get_loading_progress(scene_path: String)`
  获取场景的加载进度 (0.0 到 1.0)
  
- `print_debug_info()`
  将调试信息打印到控制台

## 信号

- `scene_preload_started(scene_path: String)`
  场景预加载开始时发出
  
- `scene_preload_completed(scene_path: String)`
  场景预加载完成时发出
  
- `scene_switch_started(from_scene: String, to_scene: String)`
  场景切换开始时发出
  
- `scene_switch_completed(scene_path: String)`
  场景切换完成时发出
  
- `scene_cached(scene_path: String)`
  场景添加到缓存时发出
  
- `scene_removed_from_cache(scene_path: String)`
  场景从缓存中移除时发出
  
- `load_screen_shown(load_screen_instance: Node)`
  加载屏幕显示时发出
  
- `load_screen_hidden(load_screen_instance: Node)`
  加载屏幕隐藏时发出

## 配置选项

插件暴露了几个可在编辑器中调整的配置选项：

- `max_cache_size`：要缓存的最大场景数（默认：8，范围：1-20）
- `max_preload_resource_cache_size`：要缓存的最大预加载资源数（默认：20，范围：1-50）
- `use_async_loading`：是否使用异步加载（默认：true）
- `always_use_default_load_screen`：始终使用默认加载屏幕（默认：false）

## 技术细节

### 架构

该插件使用 Godot 的 Autoload 功能围绕单例模式构建。主类 `LongSceneManager` 管理所有场景转换和缓存操作。

### 缓存策略

该插件为实例化场景和预加载资源实现了 LRU（最近最少使用）缓存淘汰策略。这确保了最佳的内存使用效率，同时提供快速的场景转换。

### 跨语言支持

该插件支持 GDScript 和 C# 实现。C# 版本位于 `addons/long_scene_manager/autoload/LongSceneManagerCs.cs`。

## 故障排除

### 场景预加载问题

如果您在清除缓存后遇到场景预加载问题，请确保您使用的是最新版本的插件，该版本在清除缓存时会正确重置加载状态。

### 缓存不工作

如果想利用缓存机制，请确保在切换场景时将 `use_cache` 参数设置为 `true`。

### 自定义加载屏幕

创建自定义加载屏幕时，请确保它们继承自有效的 Godot 节点类型，并在计划使用时实现预期的方法（如 `fade_in`、`fade_out` 等）。