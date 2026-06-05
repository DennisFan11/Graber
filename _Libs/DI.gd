extends Node

var _dependence: Dictionary = {}

func _ready() -> void:
	get_tree().node_added.connect(_injection)

func register(property: String, instance: Object) -> void:
	print("[DI] Registering: ", property, " -> ", instance)
	_dependence[property] = instance
	injection(get_tree().root, true)

func injection(target_node: Node, recursive: bool = false) -> void:
	if recursive:
		for child: Node in target_node.get_children():
			injection(child, true)
	_injection(target_node)

func _injection(target_node: Node) -> void:
	for property: String in _dependence.keys():
		if property in target_node:
			target_node.set(property, _dependence[property])
	if target_node.has_method("_on_injected"):
		target_node._on_injected()
