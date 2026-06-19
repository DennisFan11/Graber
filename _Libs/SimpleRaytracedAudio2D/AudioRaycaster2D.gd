class_name AudioRaycaster2D
extends Node2D
static var DEBUG_RAY: bool = true


var listener: RayAudioListener
var space: PhysicsDirectSpaceState2D
var collision_mask: int = 1 << 0

"""
{
  echo_dist,
  echo_count,
  escaped,
  escape_dir,
  occlusion_hits,
  bounce_count
}
"""


const MAX_BOUNCES: int = 3 #4
const MAX_RAY_DIST: float = 999999

## 主射線
func main_raycast(from_global: Vector2, angle: float)-> SoundRaycastResult:
	## result
	var result:= SoundRaycastResult.new()
	
	var from_pos: Vector2 = from_global
	var target_vec = Vector2.from_angle(angle)*MAX_RAY_DIST
	
	for _bounce_count in range(MAX_BOUNCES):
		
		var cast_res := raycast_once(
			from_pos, 
			from_pos + target_vec)
		if DEBUG_RAY:
			if cast_res.is_empty():
				_debug_draw.d_draw_line(from_pos, from_pos + target_vec, Color.AQUA)
			else:
				_debug_draw.d_draw_line(from_pos, cast_res["position"])
		
		## 射線逃逸
		if cast_res.is_empty():
			from_pos += target_vec
			result.escaped = true
			result.bounce_count = _bounce_count
			
			## Muffle(occlusion)Ray source 
			for player: RayAudioPlayer in RayAudioPlayer.INSTANCE_LIST:
				if not test_collided(player.global_position, from_pos):
					#result.unoccluded_hits += 1
					player._lowpass_rays_count += 1
			break
		result.escaped = false
		result.bounce_count += 1
		var hit_pos: Vector2 = cast_res["position"]
		var normal: Vector2 = cast_res["normal"]
		
		from_pos = hit_pos + normal * 0.1 ## 避免射線卡牆裡
		target_vec = target_vec.bounce(normal) ## 反彈計算
		
		## Muffle(occlusion)Ray source 
		for player: RayAudioPlayer in RayAudioPlayer.INSTANCE_LIST:
			# 只計算在監聽範圍內的播放器
			if player.is_enabled():
				if not test_collided(player.global_position, from_pos):
					#result.unoccluded_hits += 1
					player._lowpass_rays_count += 1
		
		## EchoRay listener 
		if _bounce_count == 0:
			if not test_collided(listener.global_position, from_pos):
				result.echo_count += 1
				result.echo_dist += listener.global_position.distance_to(from_pos)
				result.escape_dir = listener.global_position.direction_to(from_pos)
	return result
		
		
		

#func muffle_ray()-> bool:
	#pass
#func echo_ray()-> bool:
	#pass


## 返回是否碰撞
func test_collided(from: Vector2, to: Vector2)-> bool:
	var ans := not raycast_once(from, to).is_empty()
	if DEBUG_RAY:
		_debug_draw.d_draw_line(from, to, (Color.RED if ans else Color.GREEN_YELLOW))
	return ans


var _debug_draw: DebugDraw

## 与一个给定空间中的一个射线相交。射线位置和其他参数通过 PhysicsRayQueryParameters2D 定义。返回的对象是一个包含以下字段的字典：[br]
## collider：该碰撞对象。[br]
## collider_id：该碰撞对象的 ID。[br]
## normal：在相交点处该对象的表面法线；如果射线从形状内部开始，并且 PhysicsRayQueryParameters2D.hit_from_inside 为 true，则为 Vector2(0, 0)。[br]
## position：该相交点。[br]
## rid：该相交对象的 RID。[br]
## shape：该碰撞形状的形状索引。[br]
## 如果射线没有与任何东西相交，则返回一个空字典。[br]
func raycast_once(
		from: Vector2,
		to: Vector2,
	) -> Dictionary:
	
	var params := PhysicsRayQueryParameters2D.new()
	params.from = from
	params.to = to
	params.collision_mask = collision_mask
	params.exclude = []
	if space == null:
		return {}
	return space.intersect_ray(params)





class SoundRaycastResult:
	var echo_dist: float = 0.0
	var echo_count: int = 0
	var escape_dir: Vector2 = Vector2.ZERO
	var escaped: bool
	var unoccluded_hits: int = 0
	var bounce_count: int = 0




##
