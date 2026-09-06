extends Node
## Optional M0 stub — atlas-sim tick order is not implemented yet.
## Wire this as an autoload when income / movement / combat land.
##
## TODO tick order (atlas-sim):
##   1. income
##   2. builds
##   3. movement
##   4. combat
##   5. annex
##   6. lanes
##   7. win
##
## Do not invent multiplayer. Local single-player only.


func _ready() -> void:
	pass


func step(_dt: float) -> void:
	# TODO: run one sim tick in the order above.
	pass
