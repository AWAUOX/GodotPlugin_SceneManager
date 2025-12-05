# Long Scene Manager Plugin

[中文文档](README_中文.md)

The Long Scene Manager is a Godot plugin designed to simplify and optimize the scene switching process, especially for complex scenes that require long loading times. It improves user experience by providing asynchronous scene loading, caching mechanisms, and customizable loading interfaces.

## Features

- **Asynchronous Scene Switching**: Non-blocking scene transitions using `await`
- **Customizable Loading Screens**: Support for both default and custom loading UI scenes
- **No-transition Mode**: Quick switching with `"no_transition"` option
- **Scene Preloading**: Load scenes into memory cache in advance
- **Cache Management**: Configurable maximum cache size, cache clearing, and cache status retrieval
- **LRU Cache Policy**: Implements Least Recently Used cache eviction strategy
- **Debug Support**: Internal state printing for diagnostics

## Installation

1. Copy the `addons/long_scene_manager` folder into your project's `addons` folder
2. Enable the plugin in Godot:
   - Go to `Project → Project Settings → Plugins`
   - Find "Long Scene Manager" and set its status to "Active"

## Usage

### 1. Switch Scenes with Default Loading Screen
```gdscript
await LongSceneManager.switch_scene("res://scenes/level2.tscn")
```

### 2. Switch Scenes with Custom Loading Screen
```gdscript
await LongSceneManager.switch_scene(
    "res://scenes/level2.tscn", 
    true,  # Use cache
    "res://ui/custom_load_screen.tscn"  # Custom loading screen
)
```

### 3. Switch Scenes Without Transition
```gdscript
await LongSceneManager.switch_scene(
    "res://scenes/level2.tscn", 
    true, 
    "no_transition"  # Special value indicating no transition
)
```

### 4. Preload a Scene
```gdscript
LongSceneManager.preload_scene("res://scenes/level3.tscn")
```

### 5. Get Cache Information
```gdscript
var cache_info = LongSceneManager.get_cache_info()
print("Cache Info: ", cache_info)
```

### 6. Dynamically Adjust Cache Size
```gdscript
LongSceneManager.set_max_cache_size(10)
```

### 7. Clear Cache
```gdscript
LongSceneManager.clear_cache()
```

### 8. Print Debug Information
```gdscript
LongSceneManager.print_debug_info()
```

## API Reference

### Scene Switching Methods

- `switch_scene(scene_path: String, use_cache: bool = true, load_screen_path: String = "")`
  Switch to a new scene with optional caching and custom loading screen
  
- `switch_scene_gd(scene_path: String, use_cache: bool = true, load_screen_path: String = "")`
  GDScript compatible wrapper for scene switching

### Preloading Methods

- `preload_scene(scene_path: String)`
  Preload a scene into the cache
  
- `preload_scene_gd(scene_path: String)`
  GDScript compatible wrapper for scene preloading

### Cache Management Methods

- `clear_cache()`
  Clear all cached scenes and preloaded resources
  
- `get_cache_info()`
  Get detailed information about the current cache status
  
- `is_scene_cached(scene_path: String)`
  Check if a scene is currently cached
  
- `set_max_cache_size(new_size: int)`
  Set the maximum number of scenes that can be cached
  
- `set_max_preload_resource_cache_size(new_size: int)`
  Set the maximum number of preloaded resources that can be cached

### Utility Methods

- `get_current_scene()`
  Get the current scene instance
  
- `get_previous_scene_path()`
  Get the path of the previous scene
  
- `get_loading_progress(scene_path: String)`
  Get the loading progress for a scene (0.0 to 1.0)
  
- `print_debug_info()`
  Print debug information to the console

## Signals

- `scene_preload_started(scene_path: String)`
  Emitted when scene preloading starts
  
- `scene_preload_completed(scene_path: String)`
  Emitted when scene preloading completes
  
- `scene_switch_started(from_scene: String, to_scene: String)`
  Emitted when a scene switch begins
  
- `scene_switch_completed(scene_path: String)`
  Emitted when a scene switch completes
  
- `scene_cached(scene_path: String)`
  Emitted when a scene is added to cache
  
- `scene_removed_from_cache(scene_path: String)`
  Emitted when a scene is removed from cache
  
- `load_screen_shown(load_screen_instance: Node)`
  Emitted when a loading screen is shown
  
- `load_screen_hidden(load_screen_instance: Node)`
  Emitted when a loading screen is hidden

## Configuration

The plugin exposes several configuration options that can be adjusted in the editor:

- `max_cache_size`: Maximum number of scenes to cache (default: 8, range: 1-20)
- `max_preload_resource_cache_size`: Maximum number of preloaded resources to cache (default: 20, range: 1-50)
- `use_async_loading`: Whether to use asynchronous loading (default: true)
- `always_use_default_load_screen`: Always use the default loading screen (default: false)

## Technical Details

### Architecture

The plugin is built around a singleton pattern using Godot's Autoload feature. The main class `LongSceneManager` manages all scene transitions and caching operations.

### Caching Strategy

The plugin implements an LRU (Least Recently Used) cache eviction policy for both instantiated scenes and preloaded resources. This ensures optimal memory usage while providing fast scene transitions.

### Cross-language Support

The plugin supports both GDScript and C# implementations. The C# version is located in `addons/long_scene_manager/autoload/LongSceneManagerCs.cs`.

## Troubleshooting

### Scene Preloading Issues

If you're having trouble with scene preloading after clearing the cache, make sure you're using the latest version of the plugin which properly resets the loading state when clearing the cache.

### Cache Not Working

Ensure that the `use_cache` parameter is set to `true` when switching scenes if you want to take advantage of the caching mechanism.

### Custom Loading Screens

When creating custom loading screens, make sure they inherit from a valid Godot node type and implement the expected methods (`fade_in`, `fade_out`, etc.) if you plan to use them.