class_name RemoteSource
extends InputSource
## Client side: placeholder source for fighters this machine doesn't control (other players
## and server bots). The server drives them; we only draw them.


func _init(nm: String, bot: bool) -> void:
	label = nm
	is_bot = bot
	remote = true
