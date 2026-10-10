class_name GameConfig
extends Resource
## Game flow settings: which news a game can play and the audimat needed to win.
## Instance used by the GameManager: res://data/game_config.tres.

## Each game plays one news drawn from it (see draw_news).
@export var news_pool: Array[NewsData] = []
## Minimum audimat to win. Placeholder value.
@export var threshold: int = 2000
@export var composition_duration_sec: float = 45.0


## A random news of news_pool, different from `previous` when the pool has more than one.
## null, with an error, when the pool is empty.
func draw_news(previous: NewsData = null) -> NewsData:
	if news_pool.is_empty():
		push_error("GameConfig: news_pool is empty, no news to play")
		return null
	var others := news_pool.filter(func(news: NewsData) -> bool: return news != previous)
	return others.pick_random() if not others.is_empty() else news_pool.pick_random()
