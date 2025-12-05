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
	/// 
	/// 这是一个用于Godot游戏引擎的场景管理器，提供了以下核心功能：
	/// 1. 场景切换：可以在不同场景之间平滑切换
	/// 2. 自定义加载屏幕：支持在场景切换时显示加载界面
	/// 3. 预加载：提前加载场景资源以提高性能
	/// 4. LRU缓存：缓存最近使用的场景实例以减少重复加载
	/// 5. 场景树和缓存分离设计：场景实例要么在场景树中（当前活跃），要么在缓存中（非活跃但保留）
	/// 
	/// 使用方式：
	/// 在Godot项目中将其设为自动加载(AutoLoad)单例，然后通过调用SwitchScene等方法进行场景管理。
	/// </summary>
	public partial class SceneManager : Node
	{
		#region 常量和枚举
		
		// 默认加载屏幕的资源路径
		public const string DefaultLoadScreenPath = "res://addons/long_scene_manager/ui/loading_screen/loading_black_screen.tscn";
		
		// 场景加载状态枚举
		public enum LoadState
		{
			NotLoaded,      // 未加载
			Loading,        // 正在加载中
			Loaded,         // 已加载（资源已加载但未实例化）
			Instantiated    // 已实例化（场景对象已创建）
		}
		
		#endregion
		
		#region 信号定义
		
		// 预加载开始信号
		[Signal] public delegate void ScenePreloadStartedEventHandler(string scenePath);
		// 预加载完成信号
		[Signal] public delegate void ScenePreloadCompletedEventHandler(string scenePath);
		// 场景切换开始信号
		[Signal] public delegate void SceneSwitchStartedEventHandler(string fromScene, string toScene);
		// 场景切换完成信号
		[Signal] public delegate void SceneSwitchCompletedEventHandler(string scenePath);
		// 场景被缓存信号
		[Signal] public delegate void SceneCachedEventHandler(string scenePath);
		// 场景从缓存中移除信号
		[Signal] public delegate void SceneRemovedFromCacheEventHandler(string scenePath);
		// 加载屏幕显示信号
		[Signal] public delegate void LoadScreenShownEventHandler(Node loadScreenInstance);
		// 加载屏幕隐藏信号
		[Signal] public delegate void LoadScreenHiddenEventHandler(Node loadScreenInstance);
		
		#endregion
		
		#region 导出变量
		
		// 在Godot编辑器中显示的分类标题
		[ExportCategory("场景管理器全局配置")]
		// 导出变量，允许在编辑器中设置，限制范围为1-20
		[Export(PropertyHint.Range, "1,20")] 
		public int _maxCacheSize = 8;     // 最大缓存场景数量，默认为8个
		
		// 导出布尔值变量，可在编辑器中设置
		[Export] 
		private bool _useAsyncLoading = true;  // 是否使用异步加载，默认开启
		
		// 总是使用默认加载屏幕
		[Export] 
		private bool _alwaysUseDefaultLoadScreen = false;
		
		#endregion
		
		#region 内部状态变量
		
		private Node _currentScene;                     // 当前场景实例
		private string _currentScenePath = "";          // 当前场景路径
		private string _previousScenePath = "";         // 上一个场景路径
		
		private Node _defaultLoadScreen;                // 默认加载屏幕实例
		private Node _activeLoadScreen;                 // 当前激活的加载屏幕实例
		
		private string _loadingScenePath = "";          // 正在加载的场景路径
		private LoadState _loadingState = LoadState.NotLoaded;  // 当前加载状态
		private PackedScene _loadingResource;           // 正在加载的场景资源
		
		// 存储从场景树移除的节点实例（场景缓存）
		private readonly System.Collections.Generic.Dictionary<string, CachedScene> _sceneCache = new();
		
		// LRU缓存访问顺序记录（最近最少使用算法）
		private readonly List<string> _cacheAccessOrder = new();
		
		// 预加载资源缓存，存储预加载的PackedScene资源
		private readonly System.Collections.Generic.Dictionary<string, PackedScene> _preloadResourceCache = new();
		
		#endregion
		
		#region 生命周期函数
		
		// Godot节点生命周期函数，在节点添加到场景树后调用一次
		public override void _Ready()
		{
			GD.Print("[SceneManager] 场景管理器单例初始化");
			
			// 初始化默认加载屏幕
			InitDefaultLoadScreen();
			
			// 获取当前场景
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
		
		/// <summary>
		/// 初始化默认加载屏幕
		/// 尝试加载预设的加载屏幕，如果不存在则创建一个简单的黑色屏幕
		/// </summary>
		private void InitDefaultLoadScreen()
		{
			GD.Print("[SceneManager] 初始化默认加载屏幕");
			
			// 检查默认加载屏幕资源是否存在
			if (ResourceLoader.Exists(DefaultLoadScreenPath))
			{
				// 加载默认加载屏幕场景
				var loadScreenScene = ResourceLoader.Load<PackedScene>(DefaultLoadScreenPath);
				if (loadScreenScene != null)
				{
					// 实例化并添加到场景管理器中
					_defaultLoadScreen = loadScreenScene.Instantiate();
					AddChild(_defaultLoadScreen);
					
					// 设置加载屏幕初始为不可见
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
			
			// 如果默认加载屏幕不存在，则创建一个简单的纯色加载屏幕
			GD.Print("[SceneManager] 警告：默认加载屏幕文件不存在，创建简单版本");
			_defaultLoadScreen = CreateSimpleLoadScreen();
			AddChild(_defaultLoadScreen);
			
			// 设置简单加载屏幕初始为不可见
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
		
		/// <summary>
		/// 创建一个简单的加载屏幕（纯黑背景加"Loading..."文本）
		/// 当默认加载屏幕不存在时使用
		/// </summary>
		/// <returns>创建的简单加载屏幕节点</returns>
		private Node CreateSimpleLoadScreen()
		{
			// 创建CanvasLayer作为容器，确保加载屏幕显示在最上层
			var canvasLayer = new CanvasLayer();
			canvasLayer.Name = "SimpleLoadScreen";
			canvasLayer.Layer = 1000;  // 设置层级为1000，确保显示在最前面
			
			// 创建全屏黑色矩形
			var colorRect = new ColorRect();
			colorRect.Color = new Color(0, 0, 0, 1);  // 纯黑色不透明
			colorRect.Size = GetViewport().GetVisibleRect().Size;  // 设置为视口大小
			colorRect.AnchorLeft = 0;
			colorRect.AnchorTop = 0;
			colorRect.AnchorRight = 1;
			colorRect.AnchorBottom = 1;
			colorRect.MouseFilter = Control.MouseFilterEnum.Stop;  // 阻止鼠标事件穿透
			
			// 创建"Loading..."标签
			var label = new Label();
			label.Text = "Loading...";
			label.HorizontalAlignment = HorizontalAlignment.Center;  // 水平居中
			label.VerticalAlignment = VerticalAlignment.Center;      // 垂直居中
			label.AddThemeFontSizeOverride("font_size", 32);         // 字体大小32
			label.AddThemeColorOverride("font_color", Colors.White); // 白色字体
			
			// 组装UI层次结构
			canvasLayer.AddChild(colorRect);
			colorRect.AddChild(label);
			
			// 精确定位标签到屏幕中心
			label.AnchorLeft = 0.5f;
			label.AnchorTop = 0.5f;
			label.AnchorRight = 0.5f;
			label.AnchorBottom = 0.5f;
			label.Position = new Vector2(-50, -16);  // 微调位置
			label.Size = new Vector2(100, 32);
			
			return canvasLayer;
		}
		
		#endregion
		
		#region 公开API - 场景切换
		
		/// <summary>
		/// 切换到指定场景
		/// 支持多种优化策略：缓存、预加载、自定义加载屏幕等
		/// </summary>
		/// <param name="newScenePath">要切换到的新场景路径</param>
		/// <param name="useCache">是否使用缓存机制，默认为true</param>
		/// <param name="loadScreenPath">自定义加载屏幕路径，为空则使用默认加载屏幕</param>
		/// <returns>异步任务</returns>
		public async Task SwitchScene(string newScenePath, bool useCache = true, string loadScreenPath = "")
		{
			GD.Print($"[SceneManager] 开始切换场景到: {newScenePath}");
			
			// 添加场景树验证，确保状态清晰
			DebugValidateSceneTree();
			
			// 如果设置了总是使用默认加载屏幕，则忽略自定义加载屏幕
			if (_alwaysUseDefaultLoadScreen)
			{
				loadScreenPath = "";
				GD.Print("[SceneManager] 强制使用默认加载屏幕");
			}
			
			// 检查目标场景是否存在
			if (!ResourceLoader.Exists(newScenePath))
			{
				GD.PrintErr($"[SceneManager] 错误：目标场景路径不存在: {newScenePath}");
				return;
			}
			
			// 发送场景切换开始信号
			EmitSignal(SignalName.SceneSwitchStarted, _currentScenePath, newScenePath);
			
			// 如果目标场景就是当前场景，则无需切换
			if (_currentScenePath == newScenePath)
			{
				GD.Print($"[SceneManager] 场景已加载: {newScenePath}");
				EmitSignal(SignalName.SceneSwitchCompleted, newScenePath);
				return;
			}
			
			// 获取加载屏幕实例
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
			
			// 如果场景正在预加载中，则等待预加载完成
			if (_loadingScenePath == newScenePath && _loadingState == LoadState.Loading)
			{
				GD.Print("[SceneManager] 场景正在预加载中，等待完成...");
				await HandlePreloadingScene(newScenePath, loadScreenToUse, useCache);
				return;
			}
			
			// 如果启用了缓存并且场景在实例缓存中，则使用缓存的场景实例
			if (useCache && _sceneCache.ContainsKey(newScenePath))
			{
				GD.Print($"[SceneManager] 从实例缓存加载场景: {newScenePath}");
				await HandleCachedScene(newScenePath, loadScreenToUse);
				return;
			}
			
			// 直接加载场景（没有使用任何优化）
			GD.Print($"[SceneManager] 直接加载场景: {newScenePath}");
			await HandleDirectLoad(newScenePath, loadScreenToUse, useCache);
		}
		
		#endregion
		
		#region 公开API - 预加载
		
		/// <summary>
		/// 预加载指定场景
		/// 提前加载场景资源到内存中，以加快后续的场景切换速度
		/// </summary>
		/// <param name="scenePath">要预加载的场景路径</param>
		/// <returns>异步任务</returns>
		public async Task PreloadScene(string scenePath)
		{
			// 检查场景路径是否存在
			if (!ResourceLoader.Exists(scenePath))
			{
				GD.PrintErr($"[SceneManager] 错误：预加载场景路径不存在: {scenePath}");
				return;
			}
			
			// 检查是否已预加载或已缓存，避免重复加载
			if (_preloadResourceCache.ContainsKey(scenePath))
			{
				GD.Print($"[SceneManager] 场景已预加载: {scenePath}");
				return;
			}
			
			// 检查场景是否正在加载或已经加载到实例缓存中
			if ((_loadingScenePath == scenePath && _loadingState == LoadState.Loading) ||
				(_loadingScenePath == scenePath && _loadingState == LoadState.Loaded) ||
				_sceneCache.ContainsKey(scenePath))
			{
				GD.Print($"[SceneManager] 场景已加载或正在加载: {scenePath}");
				return;
			}
			
			GD.Print($"[SceneManager] 开始预加载场景: {scenePath}");
			// 发送预加载开始信号
			EmitSignal(SignalName.ScenePreloadStarted, scenePath);
			
			// 设置当前正在加载的场景信息
			_loadingScenePath = scenePath;
			_loadingState = LoadState.Loading;
			
			// 根据设置决定使用异步还是同步方式进行预加载
			if (_useAsyncLoading)
			{
				await AsyncPreloadScene(scenePath);
			}
			else
			{
				SyncPreloadScene(scenePath);
			}
			
			// 如果预加载成功，则将资源放入预加载资源缓存中
			if (_loadingResource != null)
			{
				// 预加载完成后，将资源存入预加载资源缓存
				_preloadResourceCache[scenePath] = _loadingResource;
				_loadingState = LoadState.Loaded;
				// 发送预加载完成信号
				EmitSignal(SignalName.ScenePreloadCompleted, scenePath);
				GD.Print($"[SceneManager] 预加载完成，资源已缓存: {scenePath}");
			}
			else
			{
				// 预加载失败，重置加载状态
				_loadingState = LoadState.NotLoaded;
				_loadingScenePath = "";
				GD.Print($"[SceneManager] 预加载失败: {scenePath}");
			}
		}
		
		#endregion
		
		#region 公开API - 缓存管理
		
		/// <summary>
		/// 清空所有缓存
		/// 包括预加载资源缓存和实例缓存
		/// </summary>
		public void ClearCache()
		{
			GD.Print("[SceneManager] 清空缓存...");
			
			// 清理预加载资源缓存（存储的是PackedScene资源）
			_preloadResourceCache.Clear();
			GD.Print("[SceneManager] 预加载资源缓存已清空");
			
			// 清理实例缓存（存储的是已实例化的场景节点）
			var toRemove = new List<string>();
			foreach (var kvp in _sceneCache)
			{
				var scenePath = kvp.Key;
				var cached = kvp.Value;
				// 检查缓存的场景实例是否仍然有效
				if (IsInstanceValid(cached.SceneInstance))
				{
					CleanupOrphanedNodes(cached.SceneInstance);  // 清理孤立节点
					cached.SceneInstance.QueueFree();  // 释放场景实例
				}
				toRemove.Add(scenePath);
				// 发送场景从缓存移除信号
				EmitSignal(SignalName.SceneRemovedFromCache, scenePath);
			}
			
			// 从缓存字典中移除所有条目
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
		
		/// <summary>
		/// 获取缓存信息
		/// 返回关于当前缓存状态的详细信息
		/// </summary>
		/// <returns>包含缓存信息的字典</returns>
		public Godot.Collections.Dictionary<string, Variant> GetCacheInfo()
		{
			// 构建实例缓存信息列表
			var cachedScenes = new Array<Godot.Collections.Dictionary<string, Variant>>();
			foreach (var kvp in _sceneCache)
			{
				var path = kvp.Key;
				var cached = kvp.Value;
				var dict = new Godot.Collections.Dictionary<string, Variant>();
				dict.Add("path", path);                    // 场景路径
				dict.Add("access_count", cached.AccessCount);  // 访问次数
				dict.Add("cached_time", cached.CachedTime);    // 缓存时间
				dict.Add("instance_valid", IsInstanceValid(cached.SceneInstance)); // 实例是否有效
				cachedScenes.Add(dict);
			}
			
			// 构建预加载资源缓存路径列表
			var preloadedScenes = new Array<string>();
			foreach (var path in _preloadResourceCache.Keys)
			{
				preloadedScenes.Add(path);
			}
			
			// 构建结果字典
			var result = new Godot.Collections.Dictionary<string, Variant>();
			result.Add("instance_cache_size", _sceneCache.Count);       // 实例缓存大小
			result.Add("max_size", _maxCacheSize);                      // 最大缓存大小
			result.Add("access_order", _cacheAccessOrder.ToArray());    // 访问顺序
			result.Add("cached_scenes", cachedScenes);                  // 缓存的场景详情
			result.Add("preload_resource_cache", preloadedScenes);      // 预加载资源缓存
			result.Add("preload_cache_size", _preloadResourceCache.Count); // 预加载缓存大小
			
			return result;
		}
		
		/// <summary>
		/// 检查指定场景是否在缓存中
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <returns>如果场景在缓存中返回true，否则返回false</returns>
		public bool IsSceneCached(string scenePath)
		{
			// 检查场景是否在实例缓存或预加载资源缓存中
			return _sceneCache.ContainsKey(scenePath) || _preloadResourceCache.ContainsKey(scenePath);
		}
		
		#endregion
		
		#region 公开API - 实用函数
		
		/// <summary>
		/// 获取当前场景实例
		/// </summary>
		/// <returns>当前场景节点</returns>
		public Node GetCurrentScene() => _currentScene;
		
		/// <summary>
		/// 获取上一个场景路径
		/// </summary>
		/// <returns>上一个场景的路径</returns>
		public string GetPreviousScenePath() => _previousScenePath;
		
		/// <summary>
		/// 获取指定场景的加载进度
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <returns>加载进度(0.0-1.0)，如果场景已加载完成则返回1.0</returns>
		public float GetLoadingProgress(string scenePath)
		{
			// 如果不是正在加载该场景，则检查是否已缓存
			if (_loadingScenePath != scenePath || _loadingState != LoadState.Loading)
			{
				return (_sceneCache.ContainsKey(scenePath) || _preloadResourceCache.ContainsKey(scenePath)) ? 1.0f : 0.0f;
			}
			
			// 创建用于接收进度信息的数组
			Godot.Collections.Array progressArray = new();
			// 获取加载状态和进度
			var status = ResourceLoader.LoadThreadedGetStatus(scenePath, progressArray);
			// 如果正在加载中且有进度信息，则返回进度值
			if (status == ResourceLoader.ThreadLoadStatus.InProgress && progressArray.Count > 0)
			{
				return (float)progressArray[0];
			}
			
			return 0.0f;
		}
		
		/// <summary>
		/// 设置最大缓存大小
		/// </summary>
		/// <param name="newSize">新的最大缓存大小</param>
		public void SetMaxCacheSize(int newSize)
		{
			// 检查输入值有效性
			if (newSize < 1)
			{
				GD.PrintErr("[SceneManager] 错误：缓存大小必须大于0");
				return;
			}
			
			_maxCacheSize = newSize;
			GD.Print($"[SceneManager] 设置最大缓存大小: {_maxCacheSize}");
			
			// 如果当前缓存数量超过新设定的最大值，则移除最旧的缓存项
			while (_cacheAccessOrder.Count > _maxCacheSize)
			{
				RemoveOldestCachedScene();
			}
		}
		
		#endregion
		
		#region 加载屏幕管理
		
		/// <summary>
		/// 获取加载屏幕实例
		/// 根据传入的路径参数决定使用哪种加载屏幕
		/// </summary>
		/// <param name="loadScreenPath">加载屏幕路径，空字符串表示使用默认加载屏幕，"no_transition"表示无过渡</param>
		/// <returns>加载屏幕节点实例，如果无法获取则返回null</returns>
		private Node GetLoadScreenInstance(string loadScreenPath)
		{
			// 如果路径为空，则使用默认加载屏幕
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
			// 如果指定为无过渡，则不使用加载屏幕
			else if (loadScreenPath == "no_transition")
			{
				GD.Print("[SceneManager] 使用无过渡模式");
				return null;
			}
			// 使用自定义加载屏幕
			else
			{
				// 检查自定义加载屏幕资源是否存在
				if (ResourceLoader.Exists(loadScreenPath))
				{
					// 加载并实例化自定义加载屏幕
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
		
		/// <summary>
		/// 显示加载屏幕
		/// 根据加载屏幕类型调用相应的显示方法
		/// </summary>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <returns>异步任务</returns>
		private async Task ShowLoadScreen(Node loadScreenInstance)
		{
			// 如果没有加载屏幕，则直接返回
			if (loadScreenInstance == null)
			{
				GD.Print("[SceneManager] 无加载屏幕，直接切换");
				return;
			}
			
			// 设置当前激活的加载屏幕
			_activeLoadScreen = loadScreenInstance;
			
			// 显示加载屏幕（根据不同的节点类型采用不同的显示方式）
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
			
			// 如果加载屏幕有淡入效果方法，则调用它
			if (loadScreenInstance.HasMethod("fade_in"))
			{
				GD.Print("[SceneManager] 调用加载屏幕淡入效果");
				var result = loadScreenInstance.Call("fade_in");
				// 如果淡入方法返回了带有completed信号的对象，则等待该信号
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			// 如果有show_loading方法，则调用它
			else if (loadScreenInstance.HasMethod("show_loading"))
			{
				var result = loadScreenInstance.Call("show_loading");
				// 如果show_loading方法返回了带有completed信号的对象，则等待该信号
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			
			// 发送加载屏幕显示信号
			EmitSignal(SignalName.LoadScreenShown, loadScreenInstance);
			GD.Print("[SceneManager] 加载屏幕显示完成");
		}
		
		/// <summary>
		/// 隐藏加载屏幕
		/// 根据加载屏幕类型调用相应的隐藏方法
		/// </summary>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <returns>异步任务</returns>
		private async Task HideLoadScreen(Node loadScreenInstance)
		{
			// 如果没有加载屏幕，则直接返回
			if (loadScreenInstance == null)
			{
				return;
			}
			
			// 如果加载屏幕有淡出效果方法，则调用它
			if (loadScreenInstance.HasMethod("fade_out"))
			{
				GD.Print("[SceneManager] 调用加载屏幕淡出效果");
				var result = loadScreenInstance.Call("fade_out");
				// 如果淡出方法返回了带有completed信号的对象，则等待该信号
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			// 如果有hide_loading方法，则调用它
			else if (loadScreenInstance.HasMethod("hide_loading"))
			{
				var result = loadScreenInstance.Call("hide_loading");
				// 如果hide_loading方法返回了带有completed信号的对象，则等待该信号
				if (result.AsGodotObject() != null && result.AsGodotObject().HasSignal("completed"))
				{
					await ToSignal(result.AsGodotObject(), "completed");
				}
			}
			// 如果有hide方法，则调用它
			else if (loadScreenInstance.HasMethod("hide"))
			{
				loadScreenInstance.Call("hide");
			}
			
			// 清理加载屏幕实例
			if (loadScreenInstance != _defaultLoadScreen)
			{
				// 如果不是默认加载屏幕，则释放自定义加载屏幕
				loadScreenInstance.QueueFree();
				GD.Print("[SceneManager] 清理自定义加载屏幕");
			}
			else
			{
				// 如果是默认加载屏幕，则隐藏它而不是释放
				if (loadScreenInstance is CanvasItem canvasItem)
				{
					canvasItem.Visible = false;
				}
				else if (loadScreenInstance.HasMethod("set_visible"))
				{
					loadScreenInstance.Call("set_visible", false);
				}
			}
			
			// 清空当前激活的加载屏幕引用
			_activeLoadScreen = null;
			// 发送加载屏幕隐藏信号
			EmitSignal(SignalName.LoadScreenHidden, loadScreenInstance);
			GD.Print("[SceneManager] 加载屏幕隐藏完成");
		}
		
		#endregion
		
		#region 场景切换处理函数
		
		/// <summary>
		/// 处理使用预加载资源缓存的场景切换
		/// 直接使用预加载的资源实例化场景
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task HandlePreloadedResource(string scenePath, Node loadScreenInstance, bool useCache)
		{
			// 显示加载屏幕
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
		
		/// <summary>
		/// 处理正在预加载中的场景切换
		/// 等待预加载完成后再执行切换
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task HandlePreloadingScene(string scenePath, Node loadScreenInstance, bool useCache)
		{
			// 显示加载屏幕
			await ShowLoadScreen(loadScreenInstance);
			// 等待预加载完成
			await WaitForPreload(scenePath);
			
			// 预加载完成后，将资源存入预加载资源缓存
			if (_loadingResource != null)
			{
				_preloadResourceCache[scenePath] = _loadingResource;
				GD.Print($"[SceneManager] 预加载资源已缓存: {scenePath}");
			}
			
			// 实例化并切换场景
			await InstantiateAndSwitch(scenePath, loadScreenInstance, useCache);
		}
		
		/// <summary>
		/// 处理使用缓存场景实例的场景切换
		/// 直接使用之前缓存的场景实例
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <returns>异步任务</returns>
		private async Task HandleCachedScene(string scenePath, Node loadScreenInstance)
		{
			// 显示加载屏幕
			await ShowLoadScreen(loadScreenInstance);
			// 切换到缓存的场景
			await SwitchToCachedScene(scenePath, loadScreenInstance);
		}
		
		/// <summary>
		/// 处理直接加载场景的场景切换
		/// 不使用任何缓存，直接加载并实例化场景
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task HandleDirectLoad(string scenePath, Node loadScreenInstance, bool useCache)
		{
			// 显示加载屏幕
			await ShowLoadScreen(loadScreenInstance);
			// 加载并切换场景
			await LoadAndSwitch(scenePath, loadScreenInstance, useCache);
		}
		
		#endregion
		
		#region 加载和切换核心函数
		
		/// <summary>
		/// 等待预加载完成
		/// 定期检查加载进度并在控制台输出进度信息
		/// </summary>
		/// <param name="scenePath">正在预加载的场景路径</param>
		/// <returns>异步任务</returns>
		private async Task WaitForPreload(string scenePath)
		{
			GD.Print($"[SceneManager] 等待预加载完成: {scenePath}");
			
			var waitStartTime = Time.GetTicksMsec();
			// 循环等待直到预加载完成
			while (_loadingScenePath == scenePath && _loadingState == LoadState.Loading)
			{
				// 每500毫秒输出一次进度信息
				if (Time.GetTicksMsec() - waitStartTime > 500)
				{
					var progress = GetLoadingProgress(scenePath);
					GD.Print($"[SceneManager] 预加载进度: {progress * 100}%");
					waitStartTime = Time.GetTicksMsec();
				}
				
				// 等待下一帧
				await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
			}
			
			GD.Print("[SceneManager] 预加载等待完成");
		}
		
		/// <summary>
		/// 实例化预加载的场景并执行切换
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task InstantiateAndSwitch(string scenePath, Node loadScreenInstance, bool useCache)
		{
			// 检查预加载资源是否有效
			if (_loadingResource == null || _loadingScenePath != scenePath)
			{
				GD.PrintErr("[SceneManager] 预加载资源不存在或路径不匹配");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			GD.Print($"[SceneManager] 实例化预加载场景: {scenePath}");
			
			// 实例化场景
			var newScene = _loadingResource.Instantiate();
			if (newScene == null)
			{
				GD.PrintErr("[SceneManager] 实例化场景失败");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			// 执行场景切换
			await PerformSceneSwitch(newScene, scenePath, loadScreenInstance, useCache);
			
			// 重置加载状态
			_loadingScenePath = "";
			_loadingState = LoadState.NotLoaded;
			_loadingResource = null;
		}
		
		/// <summary>
		/// 切换到缓存中的场景
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <returns>异步任务</returns>
		private async Task SwitchToCachedScene(string scenePath, Node loadScreenInstance)
		{
			// 从缓存中获取场景
			if (!_sceneCache.TryGetValue(scenePath, out var cached))
			{
				GD.PrintErr($"[SceneManager] 缓存中找不到场景: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			// 检查缓存的场景实例是否仍然有效
			if (!IsInstanceValid(cached.SceneInstance))
			{
				GD.PrintErr("[SceneManager] 缓存场景实例无效");
				// 从缓存中移除无效的场景
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
			
			// 从缓存中移除（因为即将使用）
			_sceneCache.Remove(scenePath);
			var index2 = _cacheAccessOrder.IndexOf(scenePath);
			if (index2 != -1)
			{
				_cacheAccessOrder.RemoveAt(index2);
			}
			
			// 更新缓存访问统计
			cached.Access();
			
			// 确保缓存节点不在任何父节点下（防止重复父节点）
			if (sceneInstance.IsInsideTree())
			{
				sceneInstance.GetParent().RemoveChild(sceneInstance);
			}
			
			// 执行场景切换
			await PerformSceneSwitch(sceneInstance, scenePath, loadScreenInstance, true);
		}
		
		/// <summary>
		/// 直接加载并切换场景
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task LoadAndSwitch(string scenePath, Node loadScreenInstance, bool useCache)
		{
			GD.Print($"[SceneManager] 加载场景: {scenePath}");
			
			// 加载场景资源
			var newSceneResource = ResourceLoader.Load<PackedScene>(scenePath);
			if (newSceneResource == null)
			{
				GD.PrintErr($"[SceneManager] 场景加载失败: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			// 实例化场景
			var newScene = newSceneResource.Instantiate();
			if (newScene == null)
			{
				GD.PrintErr($"[SceneManager] 场景实例化失败: {scenePath}");
				await HideLoadScreen(loadScreenInstance);
				return;
			}
			
			// 执行场景切换
			await PerformSceneSwitch(newScene, scenePath, loadScreenInstance, useCache);
		}
		
		/// <summary>
		/// 执行实际的场景切换操作
		/// 处理旧场景的移除和新场景的添加
		/// </summary>
		/// <param name="newScene">新场景实例</param>
		/// <param name="newScenePath">新场景路径</param>
		/// <param name="loadScreenInstance">加载屏幕实例</param>
		/// <param name="useCache">是否使用缓存</param>
		/// <returns>异步任务</returns>
		private async Task PerformSceneSwitch(Node newScene, string newScenePath, Node loadScreenInstance, bool useCache)
		{
			GD.Print($"[SceneManager] 执行场景切换到: {newScenePath}");
			
			// 保存当前场景信息
			var oldScene = _currentScene;
			var oldScenePath = _currentScenePath;
			
			// 更新场景管理器状态
			_previousScenePath = _currentScenePath;
			_currentScene = newScene;
			_currentScenePath = newScenePath;
			
			// 处理旧场景
			if (oldScene != null && oldScene != newScene)
			{
				GD.Print($"[SceneManager] 移除当前场景: {oldScene.Name}");
				
				// 从场景树中移除旧场景
				if (oldScene.IsInsideTree())
				{
					oldScene.GetParent().RemoveChild(oldScene);
				}
				
				// 如果启用缓存且旧场景路径有效，则将旧场景添加到缓存中
				if (useCache && !string.IsNullOrEmpty(oldScenePath) && oldScenePath != newScenePath)
				{
					AddToCache(oldScenePath, oldScene);
				}
				else
				{
					// 不使用缓存则直接清理旧场景
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
			
			// 将新场景添加到场景树
			GetTree().Root.AddChild(newScene);
			GetTree().CurrentScene = newScene;
			
			// 等待场景就绪
			if (!newScene.IsNodeReady())
			{
				GD.Print("[SceneManager] 等待新场景准备就绪...");
				await ToSignal(newScene, Node.SignalName.Ready);
			}
			
			// 隐藏加载屏幕
			await HideLoadScreen(loadScreenInstance);
			
			// 验证场景树状态
			DebugValidateSceneTree();
			
			// 发送场景切换完成信号
			EmitSignal(SignalName.SceneSwitchCompleted, newScenePath);
			GD.Print($"[SceneManager] 场景切换完成: {newScenePath}");
		}
		
		#endregion
		
		#region 缓存管理内部函数
		
		/// <summary>
		/// 将场景添加到缓存中
		/// 使用LRU(最近最少使用)策略管理缓存
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <param name="sceneInstance">场景实例</param>
		private void AddToCache(string scenePath, Node sceneInstance)
		{
			// 检查参数有效性
			if (string.IsNullOrEmpty(scenePath) || sceneInstance == null)
			{
				GD.Print("[SceneManager] 警告：无法缓存空场景或路径");
				return;
			}
			
			// 如果场景已在缓存中，则先移除旧的缓存项
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
			
			// 如果节点仍在场景树中，这是错误状态，强制移除
			if (sceneInstance.IsInsideTree())
			{
				GD.PrintErr("[SceneManager] 错误：尝试缓存仍在场景树中的节点");
				sceneInstance.GetParent().RemoveChild(sceneInstance);
			}
			
			GD.Print($"[SceneManager] 添加到实例缓存: {scenePath}");
			
			// 创建缓存项并添加到缓存中
			var cached = new CachedScene(sceneInstance);
			_sceneCache[scenePath] = cached;
			_cacheAccessOrder.Add(scenePath);
			// 发送场景缓存信号
			EmitSignal(SignalName.SceneCached, scenePath);
			
			// 如果缓存数量超过最大限制，则移除最旧的缓存项
			if (_cacheAccessOrder.Count > _maxCacheSize)
			{
				RemoveOldestCachedScene();
			}
		}
		
		/// <summary>
		/// 更新缓存访问记录
		/// 将指定场景标记为最近访问，更新其在LRU队列中的位置
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		private void UpdateCacheAccess(string scenePath)
		{
			// 从访问顺序列表中移除该场景
			var index = _cacheAccessOrder.IndexOf(scenePath);
			if (index != -1)
			{
				_cacheAccessOrder.RemoveAt(index);
			}
			// 将该场景添加到访问顺序列表末尾（表示最近访问）
			_cacheAccessOrder.Add(scenePath);
			
			// 更新缓存项的时间戳
			if (_sceneCache.TryGetValue(scenePath, out var cached))
			{
				cached.CachedTime = Time.GetUnixTimeFromSystem();
			}
		}
		
		/// <summary>
		/// 移除最旧的缓存场景
		/// 根据LRU策略移除最早未使用的场景
		/// </summary>
		private void RemoveOldestCachedScene()
		{
			// 检查缓存是否为空
			if (_cacheAccessOrder.Count == 0)
			{
				return;
			}
			
			// 获取最早访问的场景路径
			var oldestPath = _cacheAccessOrder[0];
			_cacheAccessOrder.RemoveAt(0);
			
			// 从缓存中移除该场景
			if (_sceneCache.TryGetValue(oldestPath, out var cached))
			{
				// 如果场景实例仍然有效，则释放它
				if (IsInstanceValid(cached.SceneInstance))
				{
					CleanupOrphanedNodes(cached.SceneInstance);
					cached.SceneInstance.QueueFree();
				}
				_sceneCache.Remove(oldestPath);
				// 发送场景从缓存移除信号
				EmitSignal(SignalName.SceneRemovedFromCache, oldestPath);
				GD.Print($"[SceneManager] 移除旧缓存: {oldestPath}");
			}
		}
		
		#endregion
		
		#region 预加载内部函数
		
		/// <summary>
		/// 异步预加载场景
		/// 使用Godot的线程化资源加载功能在后台加载场景资源
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		/// <returns>异步任务</returns>
		private async Task AsyncPreloadScene(string scenePath)
		{
			GD.Print($"[SceneManager] 异步预加载: {scenePath}");
			
			var loadStartTime = Time.GetTicksMsec();
			// 请求线程化加载
			ResourceLoader.LoadThreadedRequest(scenePath);
			
			// 循环检查加载状态
			while (true)
			{
				// 创建用于接收进度信息的数组
				var progressArray = new Godot.Collections.Array();
				// 获取加载状态和进度
				var status = ResourceLoader.LoadThreadedGetStatus(scenePath, progressArray);
				
				// 根据不同状态进行处理
				switch (status)
				{
					case ResourceLoader.ThreadLoadStatus.InProgress:
						// 如果正在加载中，定期输出进度信息
						if (Time.GetTicksMsec() - loadStartTime > 500)
						{
							if (progressArray.Count > 0)
							{
								GD.Print($"[SceneManager] 异步加载进度: {(float)progressArray[0] * 100}%");
							}
							loadStartTime = Time.GetTicksMsec();
						}
						
						// 等待下一帧继续检查
						await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
						break;
					
					case ResourceLoader.ThreadLoadStatus.Loaded:
						// 加载完成，获取加载的资源
						var loadedResource = ResourceLoader.LoadThreadedGet(scenePath);
						// 检查资源类型并赋值给_loadingResource
						if (loadedResource is PackedScene packedScene)
						{
							_loadingResource = packedScene;
						}
						GD.Print($"[SceneManager] 异步预加载完成: {scenePath}");
						return;
					
					case ResourceLoader.ThreadLoadStatus.Failed:
						// 加载失败，记录错误并重置_loadingResource
						GD.PrintErr($"[SceneManager] 异步加载失败: {scenePath}");
						_loadingResource = null;
						return;
					
					default:
						// 未知状态，记录错误并重置_loadingResource
						GD.PrintErr($"[SceneManager] 未知加载状态: {status}");
						_loadingResource = null;
						return;
				}
			}
		}
		
		/// <summary>
		/// 同步预加载场景
		/// 直接在主线程中加载场景资源，会阻塞游戏进程直到加载完成
		/// </summary>
		/// <param name="scenePath">场景路径</param>
		private void SyncPreloadScene(string scenePath)
		{
			GD.Print($"[SceneManager] 同步预加载: {scenePath}");
			// 直接加载场景资源
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
