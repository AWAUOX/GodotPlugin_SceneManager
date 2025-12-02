
# black_screen.gd
extends CanvasLayer
class_name BlackScreen

#"""
#黑屏过渡场景
#提供淡入淡出效果，可配置
#"""
@onready var color_rect: ColorRect = $ColorRect
#var color_rect: ColorRect

signal fade_in_started
signal fade_in_completed
signal fade_out_started
signal fade_out_completed

@export_category("过渡设置")
@export var fade_in_duration: float = 0.3  # 淡入持续时间（秒）
@export var fade_out_duration: float = 0.3  # 淡出持续时间（秒）
@export var color: Color = Color(0, 0, 0, 1)  # 屏幕颜色

@export_category("高级设置")
@export var fade_in_ease: Tween.EaseType = Tween.EASE_OUT
@export var fade_in_trans: Tween.TransitionType = Tween.TRANS_QUAD
@export var fade_out_ease: Tween.EaseType = Tween.EASE_IN
@export var fade_out_trans: Tween.TransitionType = Tween.TRANS_QUAD


var tween: Tween
var is_transitioning: bool = false

func _ready():
	# 设置层级为最高
	layer = 1000
	follow_viewport_enabled = true
	
	# 创建颜色矩形作为遮罩
	#color_rect = ColorRect.new()
	
	color_rect.color = color
	color_rect.size = get_viewport().get_visible_rect().size
	color_rect.anchor_left = 0
	color_rect.anchor_top = 0
	color_rect.anchor_right = 1
	color_rect.anchor_bottom = 1
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 初始状态透明
	color_rect.modulate.a = 0
	color_rect.visible = false
	
	#add_child(color_rect)

func fade_in() -> void:
	#"""淡入黑屏"""
	if is_transitioning:
		_stop_current_tween()
	
	is_transitioning = true
	fade_in_started.emit()
	
	color_rect.visible = true
	color_rect.modulate.a = 0
	
	tween = create_tween()
	tween.set_ease(fade_in_ease)
	tween.set_trans(fade_in_trans)
	tween.tween_property(color_rect, "modulate:a", 1.0, fade_in_duration)
	
	await tween.finished
	is_transitioning = false
	fade_in_completed.emit()
	print("黑屏淡入完成")

func fade_out() -> void:
	#"""淡出黑屏"""
	if is_transitioning:
		_stop_current_tween()
	
	is_transitioning = true
	fade_out_started.emit()
	
	tween = create_tween()
	tween.set_ease(fade_out_ease)
	tween.set_trans(fade_out_trans)
	tween.tween_property(color_rect, "modulate:a", 0.0, fade_out_duration)
	
	await tween.finished
	color_rect.visible = false
	is_transitioning = false
	fade_out_completed.emit()
	print("黑屏淡出完成")

func _stop_current_tween() -> void:
	#"""停止当前的过渡动画"""
	if tween and tween.is_valid():
		tween.kill()
	is_transitioning = false

func set_immediate_visible(visible: bool) -> void:
	#"""立即显示或隐藏黑屏（无过渡）"""
	_stop_current_tween()
	color_rect.visible = visible
	color_rect.modulate.a = 1.0 if visible else 0.0

func _notification(what: int) -> void:
	#"""处理窗口大小变化"""
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		color_rect.size = get_viewport().get_visible_rect().size
