class_name DAFactionDefinition
extends Resource
## Faction balance and presentation contract. All values remain data-driven.
@export var faction_id: String = "origin"
@export var display_name: String = "Origin Collective"
@export var description: String = "A preservation network rebuilding intelligence from the ruins."
@export var primary_color: Color = Color("57ebd5")
@export var secondary_color: Color = Color("536872")
@export var roster: Array[String] = ["worker", "scout", "sentinel", "disruptor", "walker"]
@export var buildings: Array[String] = ["core", "generator", "depot", "data_center", "fabricator", "tower"]
@export var modifiers: Dictionary = {}
@export var ai_profile: String = "balanced"
