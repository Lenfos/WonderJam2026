class_name GameConfig
extends Resource
## Game flow settings: which news each round plays and the audimat needed to pass it.
## Instance used by the RoundManager: res://data/game_config.tres.

## Round 1, always: the tutorial-friendly news.
@export var first_news: NewsData
## Rounds 2+ are drawn from it without repeats (first_news excluded).
@export var news_pool: Array[NewsData] = []
@export var round_count: int = 3
## Minimum audimat to pass each round, indexed by 0-based round. Placeholder values.
@export var round_thresholds: PackedInt32Array
@export var composition_duration_sec: float = 45.0


## One news per round: first_news, then draws from news_pool without repeats.
## A pool too small for round_count repeats news, with a warning.
func draw_rounds() -> Array[NewsData]:
	if round_thresholds.size() != round_count:
		push_warning("GameConfig: %d round_thresholds for %d rounds" % [round_thresholds.size(), round_count])
	var pool: Array[NewsData] = []
	pool.assign(news_pool.filter(func(news: NewsData) -> bool: return news != first_news))
	if pool.size() < round_count - 1:
		push_warning("GameConfig: %d news in news_pool for %d rounds after the first, some repeat" % [pool.size(), round_count - 1])
		if pool.is_empty():
			pool.append(first_news)
	var rounds: Array[NewsData] = [first_news]
	var bag: Array[NewsData] = []
	while rounds.size() < round_count:
		if bag.is_empty():
			bag.assign(pool)
			bag.shuffle()
		rounds.append(bag.pop_back())
	return rounds


## Minimum audimat of a 0-based round. Rounds past the array reuse its last value.
func get_threshold(round_index: int) -> int:
	if round_thresholds.is_empty():
		return 0
	return round_thresholds[mini(round_index, round_thresholds.size() - 1)]
