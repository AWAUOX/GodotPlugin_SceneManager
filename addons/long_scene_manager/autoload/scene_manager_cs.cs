using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Godot;
using Godot.Collections;

namespace LongSceneManager
{
	/// <summary>
	/// 全局场景管理器插件
	/// 支持自定义加载屏幕的场景切换、预加载和LRU缓存
	/// 场景树和缓存分离设计：场景实例要么在场景树中，要么在缓存中
	/// </summary>
	public partial class SceneManager : Node
	{
		#region 常量和枚举
		
		public const string DefaultLoadScreenPath = "res://addons/long_scene_manager/ui/loading_screen/loading_black_screen.tscn";
		
		public enum LoadState
		{
			NotLoaded,
			Loading,
			Loaded,
			Instantiated
		}
		
		#endregion
		
		#region 信号定义
		
		[Signal] public delegate void ScenePreloadStartedEventHandler(string scenePath);
		[Signal] public delegate void ScenePreloadCompletedEventHandler(string scenePath);
		[Signal] public delegate void SceneSwitchStartedEventHandler(string fromScene, string toScene);
		[Signal] public delegate void SceneSwitchCompletedEventHandler(string scenePath);
		[Signal] public delegate void SceneCachedEventHandler(string scenePath);
		[Signal] public delegate void SceneRemovedFromCacheEventHandler(string scenePath);
		[Signal] public delegate void LoadScreenShownEventHandler(Node loadScreenInstance);
		[Signal] public delegate void LoadScreenHiddenEventHandler(Node loadScreenInstance);
		
		#endregion
		
		#region 导出变量
		
		[ExportCategory("场景管理器全局配置")]
		[Export(PropertyHint.Range, "1,20")] 
		private int _maxCacheSize = 8;
		
		[Export] 
		private bool _useAsyncLoading = true;
		
		[Export] 
		private bool _alwaysUseDefaultLoadScreen = false;
		
		#endregion
		
		#region 内部状态变量
		
		private Node _currentScene;
		private string _currentScenePath = "";
		private string _previousScenePath = "";
		
		private Node _defaultLoadScreen;
		private Node _activeLoadScreen;
		
		private string _loadingScenePath = "";
		private LoadState _loadingState = LoadState.NotLoaded;
		private PackedScene _loadingResource;
		
		// 存储从场景树移除的节点实例
		private readonly System.Collections.Generic.Dictionary<string, CachedScene> _sceneCache = new();
		
		// LRU缓存访问顺序记录
		private readonly List<string> _cacheAccessOrder = new();
		
		// 预加载资源缓存，存储预加载的PackedScene资源
		private readonly System.Collections.Generic.Dictionary<string, PackedScene> _preloadResourceCache = new();
		
		#endregion
		
		#region 生命周期函数
		
		public override void _Ready()
		{
			GD.Print("[SceneManager] 场景管理器单例初始化");
			
			InitDefaultLoadScreen();
			
			_currentScene = GetTree().CurrentScene;
			if (_currentScene != null)
			{
				_currentScenePath = _currentScene.SceneFilePath;
				GD.Print($"[SceneManager] 当前场景: {_currentScenePath}");
			}
			
			GD.Print($"[SceneManager] 初始化完成，最大缓存: {_maxCacheSize}");
		}
		
		#endregion
		
		#region 初始化函数
		
		private void InitDefaultLoadScreen()
		{
			GD.Print("[SceneManager] 初始化默认加载屏幕");
			
			if (ResourceLoader.Exists(DefaultLoadScreenPath))
			{
				var loadScreenScene = ResourceLoader.Load<PackedScene>(DefaultLoadScreenPath);
				if (loadScreenScene != null)
				{
					_defaultLoadScreen = loadScreenScene.Instantiate();
					AddChild(_defaultLoadScreen);
					
					if (_defaultLoadScreen is CanvasItem canvasItem)
					{
						canvasItem.Visible = false;
					}
					else if (_defaultLoadScreen.HasMethod("set_visible"))
					{
						_defaultLoadScreen.Call("set_visible", false);
					}
					
					GD.Print("[SceneManager] 默认加载屏幕加载成功");
					return;
				}
			}
			
			GD.Print("[SceneManager] 警告：默认加载屏幕文件不存在，创建简单版本");
			_defaultLoadScreen = CreateSimpleLoadScreen();
			AddChild(_defaultLoadScreen);
			
			if (_defaultLoadScreen is CanvasItem defaultCanvasItem)
			{
				defaultCanvasItem.Visible = false;
			}
			else if (_defaultLoadScreen.HasMethod("set_visible"))
			{
				_defaultLoadScreen.Call("set_visible", false);
			}
			
			GD.Print("[SceneManager] 简单加载屏幕创建完成");
		}
		
		private Node CreateSimpleLoadScreen()
		{
			var canvasLayer = new CanvasLayer();
			canvasLayer.Name = "SimpleLoadScreen";
			canvasLayer.Layer = 1000;
			
			var colorRect = new ColorRect();
			colorRect.Color = new Color(0, 0, 0, 1);
			colorRect.Size = GetViewport().GetVisibleRect().Size;
			colorRect.AnchorLeft = 0;
			colorRect.AnchorTop = 0;
			colorRect.AnchorRight = 1;
			colorRect.AnchorBottom = 1;
			colorRect.MouseFilter = Control.MouseFilterEnum.Stop;
			
			var label = new Label();
			label.Text = "Loading...";
			label.HorizontalAlignment = HorizontalAlignment.Center;
			label.VerticalAlignment = VerticalAlignment.Center;
			label.AddThemeFontSizeOverride("font_size", 32);
			label.AddThemeColorOverride("font_color", Colors.White);
			
			canvasLayer.AddChild(colorRect);
			colorRect.AddChild(label);
			
			label.AnchorLeft = 0.5f;
			label.AnchorTop = 0.5f;
			label.AnchorRight = 0.5f;
			label.AnchorBottom = 0.5f;
			label.Position = new Vector2(-50, -16);
			label.Size = new Vector2(100, 32);
			
			return canvasLayer;
		}
		
		#endregion
		
		#region 公开API - 场景切换
		
		public async Task SwitchScene(string newScenePath, bool useCache = true, string loadScreenPath = "")
		{
			GD.Print($"[SceneManager] 开始切换场景到: {newScenePath}");
			
			// 添加场景树验证，确保状态清晰
			DebugValidateSceneTree();
			
			if (_alwaysUseDefaultLoadScreen)
			{
				loadScreenPath = "";
				GD.Print("[SceneManager] 强制使用默认加载屏幕");
			}
			
			if (!ResourceLoader.Exists(newScenePath))
			{
				GD.PrintErr($"[SceneManager] 错误：目标场景路径不存在: {newScenePath}");
				return;
			}
			
			EmitSignal(SignalName.SceneSwitchStarted, _currentScenePath, newScenePath);
			
			if (_currentScenePath == newScenePath)
			{
				GD.Print($"[SceneManager] 场景已加载: {newScenePath}");
				EmitSignal(SignalName.SceneSwitchCompleted, newScenePath);
				return;
			}
			
			var loadScreenToUse = GetLoadScreenInstance(loadScreenPath);
			if (loadScreenPath != "no_transition" && loadScreenToUse == null)
			{
				GD.PrintErr("[SceneManager] 错误：无法获取加载屏幕，切换中止");
				return;
			}
			
			// 检查预加载资源缓存
			if (_preloadResourceCache.ContainsKey(newScenePath))
			{
				GD.Print($"[SceneManager] 使用预加载资源缓存: {newScenePath}");
				await HandlePreloadedResource(newScenePath, loadScreenToUse, useCache);
				return;
			}
			
			if (_loadingScenePath == newScenePath && _loadingState == LoadState.Loading)
			{
				GD.Print("[SceneManager] 场景正在预加载中，等待完成...");
				await HandlePreloadingScene(newScenePath, loadScreenToUse, useCache);
				return;
			}
			
			if (useCache && _sceneCache.ContainsKey(newScenePath))
			{
				GD.Print($"[SceneManager] 从实例缓存加载场景: {newScenePath}");
				await HandleCachedScene(newScenePath, loadScreenToUse);
				return;
			}
			
			GD.Print($"[SceneManager] 直接加载场景: {newScenePath}");
			await HandleDirectLoad(newScenePath, loadScreenToUse, useCache);
		}
		
		#endregion
		
		#region 公开API - 预加载
		
		public async Task PreloadScene(string scenePath)
		{
			if (!ResourceLoader.Exists(scenePath))
			{
				GD.PrintErr($"[SceneManager] 错误：预加载场景路径不存在: {scenePath}");
				return;
			}
			
			// 检查是否已预加载或已缓存
			if (_preloadResourceCache.ContainsKey(scenePath))
			{
				GD.Print($"[SceneManager] 场景已预加载: {scenePath}");
				return;
			}
			
			if ((_loadingScenePath == scenePath && _loadingState == LoadState.Loading) ||
				(_loadingScenePath == scenePath && _loadingState == LoadState.Loaded) ||
				_sceneCache.ContainsKey(scenePath))
			{
				GD.Print($"[SceneManager] 场景已加载或正在加载: {scenePath}");
				return;
			}
			
			GD.Print($"[SceneManager] 开始预加载场景: {scenePath}");
			EmitSignal(SignalName.ScenePreloadStarted, scenePath);
			
			_loadingScenePath = scenePath;
			_loadingState = LoadState.Loading;
			
			if (_useAsyncLoading)
			{
				await AsyncPreloadScene(scenePath);
			}
			else
			{
				SyncPreloadScene(scenePath);
			}
			
			if (_loadingResource != null)
			{
				// 预加载完成后，将资源存入预加载资源缓存
				_preloadResourceCache[scenePath] = _loadingResource;
				_loadingState = LoadState.Loaded;
				EmitSignal(SignalName.ScenePreloadCompleted, scenePath);
				GD.Print($"[SceneManager] 预加载完成，资源已缓存: {scenePath}");
			}
			else
			{
				_loadingState = LoadState.NotLoaded;
				_loadingScenePath = "";
				GD.Print($"[SceneManager] 预加载失败: {scenePath}");
			}
		}
		
		#endregion
		
		#region 公开API - 缓存管理
		
		public void ClearCache()
		{
			GD.Print("[SceneManager] 清空缓存...");
			
			// 清理预加载资源缓存
			_preloadResourceCache.Clear();
			GD.Print("[SceneManager] 预加载资源缓存已清空");
			
			// 清理实例缓存
			var toRemove = new List<string>();
			foreach (var kvp in _sceneCache)
			{
				var scenePath = kvp.Key;
				var cached = kvp.Value;
				if (IsInstanceValid(cached.SceneInstance))
				{
					CleanupOrphanedNodes(cached.SceneInstance);  // 清理孤立节点
					cached.SceneInstance.QueueFree();
				}
				toRemove.Add(scenePath);
				EmitSignal(SignalName.SceneRemovedFromCache, scenePath);
			}
			
			foreach (var scenePath in toRemove)
			{
				_sceneCache.Remove(scenePath);
				var index = _cacheAccessOrder.IndexOf(scenePath);
				if (index != -1)
				{
					_cacheAccessOrder.RemoveAt(index);
				}
			}
			
			GD.Print("[SceneManager] 缓存已清空");
		}
		
		public Godot.Collections.Dictionary<string, Variant> GetCacheInfo()
		{
			var cachedScenes = new Array<Godot.Collections.Dictionary<string, Variant>>();
			foreach (var kvp in _sceneCache)
			{
				var path = kvp.Key;
				var cached = kvp.Value;
				var dict = new Godot.Collections.Dictionary<string, Variant>();
				dict.Add("path", path);
				dict.Add("access_count", cached.AccessCount);
				dict.Add("cached_time", cached.CachedTime);
				dict.Add("instance_valid", IsInstanceValid(cached.SceneInstance));
				cachedScenes.Add(dict);
			}
			
			var preloadedScenes = new Array<string>();
			foreach (var path in _preloadResourceCache.Keys)
			{
				preloadedScenes.Add(path);
			}
			
			var result = new Godot.Collections.Dictionary<string, Variant>();
			result.Add("instance_cache_size", _sceneCache.Count);
			result.Add("max_size", _maxCacheSize);
			result.Add("access_order", new Variant(_cacheAccessOrder.ToArray()));
			result.Add("cached_scenes", new Variant(cachedScenes));
			result.Add("preload_resource_cache", new Variant(preloadedScenes));
			result.Add("preload_cache_size", _preloadResourceCache.Count);
			
			return result;
		}
		
		public bool IsSceneCached(string scenePath)
		{
			return _sceneCache.ContainsKey(scenePath) || _preloadResourceCache.ContainsKey(scenePath);
		}
		
		#endregion
		
		#region 公开API - 实用函数
		
		public Node GetCurrentScene() => _currentScene;
		
		public string GetPreviousScenePath() => _previousScenePath;
		
		public float GetLoadingProgress(string scenePath)
		{
			if (_loadingScenePath != scenePath || _loadingState != LoadState.Loading)
			{
				return (_sceneCache.ContainsKey(scenePath) || _preloadResourceCache.ContainsKey(scenePath)) ? 1.0f : 0.0f;
			}
			
			Array progressArray = new();
			var status = ResourceLoader.LoadThreadedGetStatus(scenePath, progressArray);
			if (status == ResourceLoader.ThreadLoadStatus.InProgress && progressArray.Count > 0)
			{
				return (float)progressArray[0];
			}
			
			return 0.0f;
		}
		
		public void SetMaxCacheSize(int newSize)
		{
			if (newSize < 1)
			{
				GD.PrintErr("[SceneManager] 错误：缓存大小必须大于0");
				return;
			}
			
			_maxCacheSize = newSize;
			GD.Print($"[SceneManager] 设置最大缓存大小: {_maxCacheSize}");
			
			while (_cacheAccessOrder.Count > _maxCacheSize)
			{
				RemoveOldestCachedScene();
			}
		}
		
		#endregion
		
		#region 加载屏幕管理
		
		private Node GetLoadScreenInstance(string loadScreenPath)
		{
			if (string.IsNullOrEmpty(loadScreenPath))
			{
				if (_defaultLoadScreen != null)
				{
					GD.Print("[SceneManager] 使用默认加载屏幕");
					return _defaultLoadScreen;
				}
				else
				{
					GD.PrintErr("[SceneManager] 错误：默认加载屏幕未初始化");
					return null;
				}
			}
			else if (loadScreenPath == "no_transition")
			{
				GD.Print("[SceneManager] 使用无过渡模式");
				return null;
			}
			else
			{
				if (ResourceLoader.Exists(loadScreenPath))
				{
					var customScene = ResourceLoader.Load<PackedScene>(loadScreenPath);
					if (customScene != null)
					{
						var instance = customScene.Instantiate();
						AddChild(instance);
						GD.Print($"[SceneManager] 使用自定义加载屏幕: {loadScreenPath}");
						return instance;
					}
					else
					{
						GD.Print("[SceneManager] 警告：自定义加载屏幕加载失败，使用默认");
						return _defaultLoadScreen;
					}
				}
				else
				{
					GD.Print("[SceneManager] 警告：自定义加载屏幕路径不存在，使用默认");
					return _defaultLoadScreen;
				}
			}
		}
		
		private async Task ShowLoadScreen(Node loadScreenInstance)
		{
			if (loadScreenInstance == null)
			{
				GD.Print("[SceneManager] 无加载屏幕，直接切换");
				return;
			}
			
			_activeLoadScreen = loadScreenInstance;
			
			if (loadScreenInstance is CanvasItem canvasItem)
			{
				canvasItem.Visible = true;
			}
			else if (loadScreenInstance.HasMethod("set_visible"))
			{
				loadScreenInstance.Call("set_visible", true);
			}
			else if (loadScreenInstance.HasMethod("show"))
			{
				loadScreenInstance.Call("show");
			}
			
			if (loadScreenInstance.HasMethod("fade_in"))
			{
				GD.Print("[SceneManager] 调用加载屏幕淡入效果");
				var result = loadScreenInstance.Call("fade_in");
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			else if (loadScreenInstance.HasMethod("show_loading"))
			{
				var result = loadScreenInstance.Call("show_loading");
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			
			EmitSignal(SignalName.LoadScreenShown, loadScreenInstance);
			GD.Print("[SceneManager] 加载屏幕显示完成");
		}
		
		private async Task HideLoadScreen(Node loadScreenInstance)
		{
			if (loadScreenInstance == null)
			{
				return;
			}
			
			if (loadScreenInstance.HasMethod("fade_out"))
			{
				GD.Print("[SceneManager] 调用加载屏幕淡出效果");
				var result = loadScreenInstance.Call("fade_out");
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			else if (loadScreenInstance.HasMethod("hide_loading"))
			{
				var result = loadScreenInstance.Call("hide_loading");
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			else if (loadScreenInstance.HasMethod("hide"))
			{
				loadScreenInstance.Call("hide");
			}
			
			if (loadScreenInstance != _defaultLoadScreen)
			{
				loadScreenInstance.QueueFree();
				GD.Print("[SceneManager] 清理自定义加载屏幕");
			}
			else
			{
				if (loadScreenInstance is CanvasItem canvasItem)
				{
					canvasItem.Visible = false;
				}
				else if (loadScreenInstance.HasMethod("set_visible"))
				{
					loadScreenInstance.Call("set_visible", false);
				}
			}
			
			_activeLoadScreen = null;
			EmitSignal(SignalName.LoadScreenHidden, loadScreenInstance);
			GD.Print("[SceneManager] 加载屏幕隐藏完成");
		}
		
		#endregion
		
		#region 场景切换处理函数
		
		private async Task HandlePreloadedResource(string scenePath, Node loadScreenInstance, bool useCache)
		{
			// 处理预加载资源缓存的场景
			await ShowLoadScreen(loadScreenInstance);
			
			// 从预加载资源缓存获取并移除
			if (!_preloadResourceCache.TryGetValue(scenePath, out var packedScene))
			{
				GD.PrintErr($"[SceneManager] 预加载资源缓存错误: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			_preloadResourceCache.Remove(scenePath);
			
			GD.Print($"[SceneManager] 实例化预加载资源: {scenePath}");
			var newScene = packedScene.Instantiate();
			await PerformSceneSwitch(newScene, scenePath, loadScreenInstance, useCache);
		}
		
		private async Task HandlePreloadingScene(string scenePath, Node loadScreenInstance, bool useCache)
		{
			await ShowLoadScreen(loadScreenInstance);
			await WaitForPreload(scenePath);
			
			// 预加载完成后，将资源存入预加载资源缓存
			if (_loadingResource != null)
			{
				_preloadResourceCache[scenePath] = _loadingResource;
				GD.Print($"[SceneManager] 预加载资源已缓存: {scenePath}");
			}
			
			await InstantiateAndSwitch(scenePath, loadScreenInstance, useCache);
		}
		
		private async Task HandleCachedScene(string scenePath, Node loadScreenInstance)
		{
			await ShowLoadScreen(loadScreenInstance);
			await SwitchToCachedScene(scenePath, loadScreenInstance);
		}
		
		private async Task HandleDirectLoad(string scenePath, Node loadScreenInstance, bool useCache)
		{
			await ShowLoadScreen(loadScreenInstance);
			await LoadAndSwitch(scenePath, loadScreenInstance, useCache);
		}
		
		#endregion
		
		#region 加载和切换核心函数
		
		private async Task WaitForPreload(string scenePath)
		{
			GD.Print($"[SceneManager] 等待预加载完成: {scenePath}");
			
			var waitStartTime = Time.GetTicksMsec();
			while (_loadingScenePath == scenePath && _loadingState == LoadState.Loading)
			{
				if (Time.GetTicksMsec() - waitStartTime > 500)
				{
					var progress = GetLoadingProgress(scenePath);
					GD.Print($"[SceneManager] 预加载进度: {progress * 100}%");
					waitStartTime = Time.GetTicksMsec();
				}
				
				await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
			}
			
			GD.Print("[SceneManager] 预加载等待完成");
		}
		
		private async Task InstantiateAndSwitch(string scenePath, Node loadScreenInstance, bool useCache)
		{
			if (_loadingResource == null || _loadingScenePath != scenePath)
			{
				GD.PrintErr("[SceneManager] 预加载资源不存在或路径不匹配");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			GD.Print($"[SceneManager] 实例化预加载场景: {scenePath}");
			
			var newScene = _loadingResource.Instantiate();
			if (newScene == null)
			{
				GD.PrintErr("[SceneManager] 实例化场景失败");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			await PerformSceneSwitch(newScene, scenePath, loadScreenInstance, useCache);
			
			_loadingScenePath = "";
			_loadingState = LoadState.NotLoaded;
			_loadingResource = null;
		}
		
		private async Task SwitchToCachedScene(string scenePath, Node loadScreenInstance)
		{
			if (!_sceneCache.TryGetValue(scenePath, out var cached))
			{
				GD.PrintErr($"[SceneManager] 缓存中找不到场景: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			if (!IsInstanceValid(cached.SceneInstance))
			{
				GD.PrintErr("[SceneManager] 缓存场景实例无效");
				_sceneCache.Remove(scenePath);
				var index = _cacheAccessOrder.IndexOf(scenePath);
				if (index != -1)
				{
					_cacheAccessOrder.RemoveAt(index);
				}
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			GD.Print($"[SceneManager] 使用缓存场景: {scenePath}");
			
			var sceneInstance = cached.SceneInstance;
			
			// 从缓存中移除
			_sceneCache.Remove(scenePath);
			var index2 = _cacheAccessOrder.IndexOf(scenePath);
			if (index2 != -1)
			{
				_cacheAccessOrder.RemoveAt(index2);
			}
			
			cached.Access();
			
			// 确保缓存节点不在任何父节点下
			if (sceneInstance.IsInsideTree())
			{
				sceneInstance.GetParent().RemoveChild(sceneInstance);
			}
			
			await PerformSceneSwitch(sceneInstance, scenePath, loadScreenInstance, true);
		}
		
		private async Task LoadAndSwitch(string scenePath, Node loadScreenInstance, bool useCache)
		{
			GD.Print($"[SceneManager] 加载场景: {scenePath}");
			
			var newSceneResource = ResourceLoader.Load<PackedScene>(scenePath);
			if (newSceneResource == null)
			{
				GD.PrintErr($"[SceneManager] 场景加载失败: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			var newScene = newSceneResource.Instantiate();
			if (newScene == null)
			{
				GD.PrintErr($"[SceneManager] 场景实例化失败: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			await PerformSceneSwitch(newScene, scenePath, loadScreenInstance, useCache);
		}
		
		private async Task PerformSceneSwitch(Node newScene, string newScenePath, Node loadScreenInstance, bool useCache)
		{
			GD.Print($"[SceneManager] 执行场景切换到: {newScenePath}");
			
			var oldScene = _currentScene;
			var oldScenePath = _currentScenePath;
			
			_previousScenePath = _currentScenePath;
			_currentScene = newScene;
			_currentScenePath = newScenePath;
			
			// 处理旧场景
			if (oldScene != null && oldScene != newScene)
			{
				GD.Print($"[SceneManager] 移除当前场景: {oldScene.Name}");
				
				if (oldScene.IsInsideTree())
				{
					oldScene.GetParent().RemoveChild(oldScene);
				}
				
				if (useCache && !string.IsNullOrEmpty(oldScenePath) && oldScenePath != newScenePath)
				{
					AddToCache(oldScenePath, oldScene);
				}
				else
				{
					CleanupOrphanedNodes(oldScene);
					oldScene.QueueFree();
				}
			}
			
			GD.Print($"[SceneManager] 添加新场景: {newScene.Name}");
			
			// 确保新场景不在任何父节点下（防止重复父节点）
			if (newScene.IsInsideTree())
			{
				newScene.GetParent().RemoveChild(newScene);
			}
			
			// 添加到场景树
			GetTree().Root.AddChild(newScene);
			GetTree().CurrentScene = newScene;
			
			// 等待场景就绪
			if (!newScene.IsNodeReady())
			{
				GD.Print("[SceneManager] 等待新场景准备就绪...");
				await ToSignal(newScene, Node.SignalName.Ready);
			}
			
			await HideLoadScreen(loadScreenInstance);
			
			// 验证场景树状态
			DebugValidateSceneTree();
			
			EmitSignal(SignalName.SceneSwitchCompleted, newScenePath);
			GD.Print($"[SceneManager] 场景切换完成: {newScenePath}");
		}
		
		#endregion
		
		#region 缓存管理内部函数
		
		private void AddToCache(string scenePath, Node sceneInstance)
		{
			if (string.IsNullOrEmpty(scenePath) || sceneInstance == null)
			{
				GD.Print("[SceneManager] 警告：无法缓存空场景或路径");
				return;
			}
			
			if (_sceneCache.ContainsKey(scenePath))
			{
				GD.Print($"[SceneManager] 场景已在实例缓存中: {scenePath}");
				if (_sceneCache.TryGetValue(scenePath, out var oldCached) && IsInstanceValid(oldCached.SceneInstance))
				{
					CleanupOrphanedNodes(oldCached.SceneInstance);
					oldCached.SceneInstance.QueueFree();
				}
				_sceneCache.Remove(scenePath);
				var index = _cacheAccessOrder.IndexOf(scenePath);
				if (index != -1)
				{
					_cacheAccessOrder.RemoveAt(index);
				}
			}
			
			// 清理孤立节点确保节点不在场景树中
			CleanupOrphanedNodes(sceneInstance);
			
			// 如果节点仍在场景树中，这是错误状态
			if (sceneInstance.IsInsideTree())
			{
				GD.PrintErr("[SceneManager] 错误：尝试缓存仍在场景树中的节点");
				sceneInstance.GetParent().RemoveChild(sceneInstance);
			}
			
			GD.Print($"[SceneManager] 添加到实例缓存: {scenePath}");
			
			var cached = new CachedScene(sceneInstance);
			_sceneCache[scenePath] = cached;
			_cacheAccessOrder.Add(scenePath);
			EmitSignal(SignalName.SceneCached, scenePath);
			
			if (_cacheAccessOrder.Count > _maxCacheSize)
			{
				RemoveOldestCachedScene();
			}
		}
		
		private void UpdateCacheAccess(string scenePath)
		{
			var index = _cacheAccessOrder.IndexOf(scenePath);
			if (index != -1)
			{
				_cacheAccessOrder.RemoveAt(index);
			}
			_cacheAccessOrder.Add(scenePath);
			
			if (_sceneCache.TryGetValue(scenePath, out var cached))
			{
				cached.CachedTime = Time.GetUnixTimeFromSystem();
			}
		}
		
		private void RemoveOldestCachedScene()
		{
			if (_cacheAccessOrder.Count == 0)
			{
				return;
			}
			
			var oldestPath = _cacheAccessOrder[0];
			_cacheAccessOrder.RemoveAt(0);
			
			if (_sceneCache.TryGetValue(oldestPath, out var cached))
			{
				if (IsInstanceValid(cached.SceneInstance))
				{
					CleanupOrphanedNodes(cached.SceneInstance);
					cached.SceneInstance.QueueFree();
				}
				_sceneCache.Remove(oldestPath);
				EmitSignal(SignalName.SceneRemovedFromCache, oldestPath);
				GD.Print($"[SceneManager] 移除旧缓存: {oldestPath}");
			}
		}
		
		#endregion
		
		#region 预加载内部函数
		
		private async Task AsyncPreloadScene(string scenePath)
		{
			GD.Print($"[SceneManager] 异步预加载: {scenePath}");
			
			var loadStartTime = Time.GetTicksMsec();
			ResourceLoader.LoadThreadedRequest(scenePath);
			
			while (true)
			{
				var progressArray = new Array();
				var status = ResourceLoader.LoadThreadedGetStatus(scenePath, progressArray);
				
				switch (status)
				{
					case ResourceLoader.ThreadLoadStatus.InProgress:
						if (Time.GetTicksMsec() - loadStartTime > 500)
						{
							if (progressArray.Count > 0)
							{
								GD.Print($"[SceneManager] 异步加载进度: {(float)progressArray[0] * 100}%");
							}
							loadStartTime = Time.GetTicksMsec();
						}
						
						await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
						break;
					
					case ResourceLoader.ThreadLoadStatus.Loaded:
						var loadedResource = ResourceLoader.LoadThreadedGet(scenePath);
						if (loadedResource.VariantType == Variant.Type.Object && loadedResource.AsGodotObject() is PackedScene packedScene)
						{
							_loadingResource = packedScene;
						}
						GD.Print($"[SceneManager] 异步预加载完成: {scenePath}");
						return;
					
					case ResourceLoader.ThreadLoadStatus.Failed:
						GD.PrintErr($"[SceneManager] 异步加载失败: {scenePath}");
						_loadingResource = null;
						return;
					
					default:
						GD.PrintErr($"[SceneManager] 未知加载状态: {status}");
						_loadingResource = null;
						return;
				}
			}
		}
		
		private void SyncPreloadScene(string scenePath)
		{
			GD.Print($"[SceneManager] 同步预加载: {scenePath}");
			_loadingResource = ResourceLoader.Load<PackedScene>(scenePath);
		}
		
		#endregion
		
		#region 孤立节点清理函数
		
		private void CleanupOrphanedNodes(Node rootNode)
		{
			// 递归清理可能成为孤立节点的子节点
			if (rootNode == null || !IsInstanceValid(rootNode))
			{
				return;
			}
			
			// 如果节点仍在场景树中，强制移除
			if (rootNode.IsInsideTree())
			{
				var parent = rootNode.GetParent();
				if (parent != null)
				{
					parent.RemoveChild(rootNode);
				}
			}
			
			// 递归清理所有子节点
			foreach (var child in rootNode.GetChildren())
			{
				CleanupOrphanedNodes(child);
			}
		}
		
		private void DebugValidateSceneTree()
		{
			// 调试用：验证场景树状态
			var root = GetTree().Root;
			var current = GetTree().CurrentScene;
			
			GD.Print($"[SceneManager] 场景树验证 - 根节点子节点数: {root.GetChildCount()}");
			GD.Print($"[SceneManager] 当前场景: {(current != null ? current.Name : "None")}");
			
			// 检查缓存节点是否意外在场景树中
			foreach (var kvp in _sceneCache)
			{
				var scenePath = kvp.Key;
				var cached = kvp.Value;
				if (IsInstanceValid(cached.SceneInstance) && cached.SceneInstance.IsInsideTree())
				{
					GD.PrintErr($"[SceneManager] 错误：缓存节点仍在场景树中: {scenePath}");
				}
			}
		}
		
		#endregion
		
		#region 信号连接辅助
		
		public void ConnectAllSignals(Node target)
		{
			if (target == null)
			{
				return;
			}
			
			var signalNames = new[]
			{
				SignalName.ScenePreloadStarted,
				SignalName.ScenePreloadCompleted,
				SignalName.SceneSwitchStarted,
				SignalName.SceneSwitchCompleted,
				SignalName.SceneCached,
				SignalName.SceneRemovedFromCache,
				SignalName.LoadScreenShown,
				SignalName.LoadScreenHidden
			};
			
			foreach (var signalName in signalNames)
			{
				var methodName = "_on_scene_manager_" + signalName;
				if (target.HasMethod(methodName))
				{
					Connect(signalName, new Callable(target, methodName));
					GD.Print($"[SceneManager] 连接信号: {signalName} -> {methodName}");
				}
			}
		}
		
		#endregion
		
		#region 调试和工具函数
		
		public void PrintDebugInfo()
		{
			GD.Print("\n=== SceneManager 调试信息 ===");
			GD.Print($"当前场景: {(_currentScene != null ? _currentScenePath : "None")}");
			GD.Print($"上一个场景: {_previousScenePath}");
			GD.Print($"实例缓存数量: {_sceneCache.Count}/{_maxCacheSize}");
			GD.Print($"预加载资源缓存数量: {_preloadResourceCache.Count}");
			GD.Print($"缓存访问顺序: {string.Join(", ", _cacheAccessOrder)}");
			GD.Print($"正在加载的场景: {(!string.IsNullOrEmpty(_loadingScenePath) ? _loadingScenePath : "None")}");
			GD.Print($"加载状态: {_loadingState}");
			GD.Print($"默认加载屏幕: {(_defaultLoadScreen != null ? "已加载" : "未加载")}");
			GD.Print($"活动加载屏幕: {(_activeLoadScreen != null ? "有" : "无")}");
			GD.Print($"使用异步加载: {_useAsyncLoading}");
			GD.Print($"始终使用默认加载屏幕: {_alwaysUseDefaultLoadScreen}");
			GD.Print("===============================\n");
		}
		
		#endregion
		
		#region 内部类
		
		private class CachedScene
		{
			public Node SceneInstance { get; }
			public double CachedTime { get; set; }
			public int AccessCount { get; private set; }
			
			public CachedScene(Node scene)
			{
				SceneInstance = scene;
				CachedTime = Time.GetUnixTimeFromSystem();
				AccessCount = 0;
			}
			
			public void Access()
			{
				AccessCount++;
			}
		}
		
		#endregion
	}
}
