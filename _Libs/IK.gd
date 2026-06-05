@tool
class_name FABRIK
extends RefCounted

# GDScript FABRIK 反向運動學實作 (2D 版本)

static func calculate_ik_2d(joints: Array[Vector2], bone_lengths: Array[float], target_pos: Vector2, root_pos: Vector2, max_iterations: int = 10, tolerance: float = 0.01) -> Array[Vector2]:
	var n: int = joints.size()
	
	for _i in range(max_iterations):
		
			
		# ==========================================
		# 階段一：Backward Pass (由末端往根部拉)
		# ==========================================
		# 1. 將末端節點直接設定在目標位置
		joints[n - 1] = target_pos
		
		# 2. 從倒數第二個節點，一路往回算到根節點
		for j in range(n - 2, -1, -1):
			# 取得從「子節點(j+1)」指向「當前父節點(j)」的標準化方向向量
			var dir: Vector2 = (joints[j] - joints[j + 1]).normalized()
			# 沿著方向推算該段骨骼長度的距離
			joints[j] = joints[j + 1] + (dir * bone_lengths[j])
			
		# ==========================================
		# 階段二：Forward Pass (由根部往末端推)
		# ==========================================
		# 1. 將根節點強制鎖回身體的正確位置
		joints[0] = root_pos
		
		# 2. 從第二個節點，一路往下算到末端節點
		for j in range(n - 1):
			# 取得從「當前父節點(j)」指向「子節點(j+1)」的標準化方向向量
			var dir: Vector2 = (joints[j + 1] - joints[j]).normalized()
			# 沿著方向推算該段骨骼長度的距離
			joints[j + 1] = joints[j] + (dir * bone_lengths[j])
		
		# 檢查末端（腳尖）是否已經夠接近目標，若是則提早結束計算
		if joints[n - 1].distance_to(target_pos) < tolerance:
			break
			
	return joints
