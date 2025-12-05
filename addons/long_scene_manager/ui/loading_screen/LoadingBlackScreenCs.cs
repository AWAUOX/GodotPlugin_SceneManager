using Godot;
using System;

/// <summary>
/// 黑屏过渡场景
/// 提供淡入淡出效果，可配置
/// </summary>
public partial class LoadingBlackScreenCs : CanvasLayer
{
	// 导出属性 - 过渡设置
	[ExportCategory("过渡设置")]
	[Export(PropertyHint.Range, "0.0,10.0,0.1")]
	public float FadeInDuration { get; set; } = 0.3f; // 淡入持续时间（秒）
	
	[Export(PropertyHint.Range, "0.0,10.0,0.1")]
	public float FadeOutDuration { get; set; } = 0.3f; // 淡出持续时间（秒）
	
	[Export]
	public Color Color { get; set; } = new Color(0, 0, 0, 1); // 屏幕颜色

	// 导出属性 - 高级设置
	[ExportCategory("高级设置")]
	[Export]
	public Tween.EaseType FadeInEase { get; set; } = Tween.EaseType.Out;
	
	[Export]
	public Tween.TransitionType FadeInTrans { get; set; } = Tween.TransitionType.Quad;
	
	[Export]
	public Tween.EaseType FadeOutEase { get; set; } = Tween.EaseType.In;
	
	[Export]
	public Tween.TransitionType FadeOutTrans { get; set; } = Tween.TransitionType.Quad;

	// 信号定义
	[Signal]
	public delegate void FadeInStartedEventHandler();
	
	[Signal]
	public delegate void FadeInCompletedEventHandler();
	
	[Signal]
	public delegate void FadeOutStartedEventHandler();
	
	[Signal]
	public delegate void FadeOutCompletedEventHandler();

	// 私有变量
	private ColorRect _colorRect;
	private Tween _tween;
	private bool _isTransitioning = false;

	public override void _Ready()
	{
		// 设置层级为最高
		Layer = 1000;
		FollowViewportEnabled = true;

		// 创建颜色矩形作为遮罩
		_colorRect = new ColorRect();
		_colorRect.Color = Color;
		_colorRect.Size = GetViewport().GetVisibleRect().Size;
		_colorRect.AnchorLeft = 0;
		_colorRect.AnchorTop = 0;
		_colorRect.AnchorRight = 1;
		_colorRect.AnchorBottom = 1;
		_colorRect.MouseFilter = Control.MouseFilterEnum.Stop;

		// 初始状态透明
		_colorRect.Modulate = new Color(1, 1, 1, 0);
		_colorRect.Visible = false;

		AddChild(_colorRect);
	}

	/// <summary>
	/// 淡入黑屏
	/// </summary>
	public async void FadeIn()
	{
		GD.Print("开始淡入");
		// 如果正在过渡中，则停止当前的过渡动画
		if (_isTransitioning)
		{
			_StopCurrentTween();
		}

		_isTransitioning = true;
		EmitSignal(SignalName.FadeInStarted);

		_colorRect.Visible = true;
		_colorRect.Modulate = new Color(1, 1, 1, 0);

		_tween = CreateTween();
		_tween.SetEase(FadeInEase);
		_tween.SetTrans(FadeInTrans);
		_tween.TweenProperty(_colorRect, "modulate:a", 1.0, FadeInDuration);

		await ToSignal(_tween, "finished");
		_isTransitioning = false;
		EmitSignal(SignalName.FadeInCompleted);
		GD.Print("黑屏淡入完成");
	}

	/// <summary>
	/// 淡出黑屏
	/// </summary>
	public async void FadeOut()
	{
		GD.Print("开始淡出");
		// 如果正在过渡中，则停止当前的过渡动画
		if (_isTransitioning)
		{
			_StopCurrentTween();
		}

		_isTransitioning = true;
		EmitSignal(SignalName.FadeOutStarted);

		_tween = CreateTween();
		_tween.SetEase(FadeOutEase);
		_tween.SetTrans(FadeOutTrans);
		_tween.TweenProperty(_colorRect, "modulate:a", 0.0, FadeOutDuration);

		await ToSignal(_tween, "finished");
		_colorRect.Visible = false;
		_isTransitioning = false;
		EmitSignal(SignalName.FadeOutCompleted);
		GD.Print("黑屏淡出完成");
	}

	/// <summary>
	/// 停止当前的过渡动画
	/// </summary>
	private void _StopCurrentTween()
	{
		if (_tween != null)
		{
			_tween.Kill();
		}
		_isTransitioning = false;
	}

	/// <summary>
	/// 立即显示或隐藏黑屏（无过渡）
	/// </summary>
	/// <param name="visible">是否可见</param>
	public void SetImmediateVisible(bool visible)
	{
		_StopCurrentTween();
		_colorRect.Visible = visible;
		_colorRect.Modulate = new Color(1, 1, 1, visible ? 1.0f : 0.0f);
	}

}