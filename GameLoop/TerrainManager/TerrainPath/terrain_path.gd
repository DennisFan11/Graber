extends Path2D



@export var terrain: TerrainBase



func _ready():
	if not terrain: return
	%RemoteTransform2D.remote_path = terrain.get_body().get_path()

var time: float = 0.0
const TIME: float = 1.0
func _process(delta):
	time += delta
	%PathFollow2D.progress_ratio = (sin(time * (1.0/TIME))+1.0)*0.5
	
