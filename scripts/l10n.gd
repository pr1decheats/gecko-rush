extends Node
signal changed
var language := "ru"
var _keys: Array = []
var _cache: Dictionary = {}
const EN := {
"Лёгкий":"Easy", "Обычный":"Normal", "Сложный":"Hard", "Эксперт":"Expert", "Кошмар":"Nightmare", "Безумие":"Insane", "Каньон":"Canyon", "Лёд":"Ice", "Кристаллы":"Crystals", "Небо":"Sky",
"СЛОЖНОСТЬ":"DIFFICULTY", "Сложнее забеги — больше XP. Для открытия нужны уровень и рекорд забега в предыдущей сложности.":"Harder runs earn more XP. Unlock each difficulty with a level and a single-run best in the previous difficulty.", "На указанном уровне забеги становятся тренировочными: без XP. Выбирай следующую сложность для роста.":"At the listed level, runs become practice runs with no XP. Choose the next difficulty to keep levelling up.",
"XP ×%s · до уровня %d":"XP ×%s · up to level %d", "XP ×%s · без ограничения уровня":"XP ×%s · no level limit", "Тренировка · XP за забег: 0":"Practice · run XP: 0", "Темп: %s → %s м/с":"Pace: %s → %s m/s", "Максимальный темп: с %s м":"Full pace at %s m", "Нужен уровень %d · сейчас %d":"Level %d required · current %d", "Рекорд мира «%s»: %s / %s м":"Single-run best on %s: %s / %s m", "Далее: «%s» · уровень %d":"Next: %s · level %d", "Для XP выбери: «%s»":"For XP, choose %s", "ОТКРЫТО":"UNLOCKED", "ЗАКРЫТО":"LOCKED",
"ПОСЛЕДНИЙ\nЗАБЕГ":"LAST\nRUN", "РЕКОРД\nЗАБЕГА":"BEST\nRUN", "ВСЕГО\nПРОЙДЕНО":"TOTAL\nDISTANCE",
"ИГРАТЬ":"PLAY", "ПРОДОЛЖИТЬ":"CONTINUE", "ЕЩЁ РАЗ":"TRY AGAIN", "ГЛАВНОЕ МЕНЮ":"MAIN MENU", "Главное меню":"Main menu", "В ГЛАВНОЕ МЕНЮ":"BACK TO MENU", "ЗАВЕРШИТЬ И В МЕНЮ":"FINISH & MENU", "НОВЫЙ ЗАБЕГ":"NEW RUN", "МАГАЗИН":"SHOP", "ПРОФИЛЬ":"PROFILE", "ЗАДАНИЯ":"QUESTS", "НАСТРОЙКИ":"SETTINGS", "Настройки":"Settings", "Пауза":"Pause", "ПЕРЕДЫШКА":"PAUSED", "ГОТОВО":"DONE", "ВКЛ.":"ON", "ВЫКЛ.":"OFF", "В ПРОЦЕССЕ":"IN PROGRESS", "ПОЛУЧЕНО":"CLAIMED", "ВЫБРАН":"SELECTED", "ВЫБРАТЬ":"SELECT", "ОПЫТ":"EXPERIENCE", "МОНЕТЫ":"COINS", "НОВЫЙ РЕКОРД!":"NEW BEST!", "НОВЫЙ УРОВЕНЬ!":"LEVEL UP!", "ОТЛИЧНЫЙ ПОДЪЁМ":"NICE CLIMB", "ЛИЧНЫЙ РЕКОРД":"PERSONAL BEST", "ЛУЧШИЙ РЕКОРД":"BEST HEIGHT", "ВСЕГО ПРОЙДЕНО":"TOTAL DISTANCE", "ЗАБЕГОВ":"RUNS", "МОНЕТ ЗА ВСЁ ВРЕМЯ":"LIFETIME COINS", "ТВОИ МИРЫ":"YOUR WORLDS", "ДОСТИЖЕНИЯ":"ACHIEVEMENTS", "УРОВЕНЬ":"LEVEL", "УР.":"LV.", "Рекорд:":"Best:", "Сейчас:":"Current:", "Новое достижение:":"Achievement unlocked:", "XP до следующего уровня":"XP to next level",
"ВЫШЕ С КАЖДЫМ ПРЫЖКОМ":"HIGHER WITH EVERY JUMP", "ОДНО КАСАНИЕ — ЦЕЛЫЙ МИР":"ONE TAP. A WHOLE WORLD.", "КАСАНИЕ — ПРЫЖОК":"TAP TO JUMP", "Одно касание. Бесконечная высота.":"One tap. Endless heights.", "Каждый забег оставляет след":"Every run leaves a mark", "Высота подождёт.":"The heights can wait.", "При закрытии игры забег сохранится для продолжения.":"Close the game and resume this run later.", "Стандартный зелёный геккон":"Original green gecko", "Сохранённый забег недоступен":"Saved run is unavailable",
"Джунгли":"Jungle", "Каменный каньон":"Stone Canyon", "Ледяные скалы":"Frozen Cliffs", "Кристальные пещеры":"Crystal Caves", "Вулкан":"Volcano", "Небесные острова":"Sky Islands", "Юный исследователь":"Explorer", "Скалолаз":"Cliff Climber", "Покоритель высот":"Height Conqueror", "Легенда стен":"Wall Legend", "Небесный дракон":"Sky Dragon", "Бессмертный геккон":"Immortal Gecko", "Звание":"Title", "Мир":"World",
"Первый прыжок":"First Jump", "На высоте":"On Top", "Путь к звёздам":"Path to the Stars", "Золотой запас":"Golden Stash", "От стены к стене":"Wall to Wall", "Опытный геккон":"Experienced Gecko", "Ветеран высот":"Height Veteran", "Покоритель небес":"Sky Conqueror", "За облаками":"Beyond the Clouds", "Мастер прыжков":"Jump Master", "1 000 метров":"1,000 metres", "2 000 метров":"2,000 metres", "5 000 метров":"5,000 metres", "1 000 заработанных монет":"1,000 coins earned", "100 успешных прыжков":"100 successful jumps", "1 000 успешных прыжков":"1,000 successful jumps", "Достичь 10 уровня":"Reach level 10", "Достичь 25 уровня":"Reach level 25", "Достичь 50 уровня":"Reach level 50", "Перепрыгните на другую стену":"Jump to the other wall", "Поднимитесь на 1 000 м за один забег":"Reach 1,000 m in one run", "Поднимитесь на 2 000 м за один забег":"Reach 2,000 m in one run", "Поднимитесь на 5 000 м за один забег":"Reach 5,000 m in one run", "Заработайте суммарно 1 000 монет, включая награды":"Earn 1,000 coins in total, including rewards", "Совершите 100 успешных прыжков":"Complete 100 jumps", "Совершите 1 000 успешных прыжков":"Complete 1,000 jumps", "Достигните 10 уровня":"Reach level 10", "Достигните 25 уровня":"Reach level 25", "Достигните 50 уровня":"Reach level 50", "Сложные сочетания испытаний":"Advanced challenge patterns", "Новые цели высоты":"More height achievements",
"ЕЖЕДНЕВНЫЕ ЗАДАНИЯ":"DAILY QUESTS", "Небольшая цель на каждый день":"A little goal for every day", "Сделать 30 прыжков":"Complete 30 jumps", "Собрать 20 монет в забегах":"Collect 20 coins in runs", "Достичь 300 м за один забег":"Reach 300 m in one run", "Играй в своём ритме. Прогресс сохраняется между забегами, а награды можно забрать здесь.":"Play at your own pace. Progress carries across runs. Claim your rewards here.", "Обновляются каждый день. Для задания на высоту учитывается один лучший забег за сегодня.":"Reset daily. The height quest uses your best single run today.",
"Новые образы для новых высот":"New looks for new heights", "Скоро здесь\nпоявятся скины!":"New skins\ncoming soon!", "Пока здесь тихо. Исследуй миры,\nсобирай монеты и покоряй новые высоты.":"Explore the worlds, collect coins\nand conquer new heights.", "Случайный скин — 100 монет":"Random skin — 100 coins", "Покупки появятся в будущем обновлении":"Purchases arrive in a future update",
"Звук":"Audio", "Графика":"Graphics", "Язык":"Language", "Создатели":"Creators", "Русский":"Russian", "English":"English", "Тёмная":"Dark", "Светлая":"Light", "Музыка":"Music", "Звуковые эффекты":"Sound effects", "Звук прыжка":"Jump sound", "Прыжок и приземление":"Jump and landing", "Частота кадров":"Frame rate", "Тема оформления":"Appearance", "Язык интерфейса":"Interface language", "Пусть игра звучит по-твоему":"Make the game yours", "Спокойный ритм джунглей":"A gentle jungle rhythm", "Монеты, рекорды и интерфейс":"Coins, records and interface", "Прыжки, монеты и новые рекорды":"Jumps, coins and new records", "На экранах 120 Гц можно выбрать 120 FPS.":"Choose 120 FPS on supported 120 Hz displays.", "День и ночь сменяются каждые 40 секунд.":"Day and night alternate every 40 seconds.", "ВСЁ ПРОСТО":"ONE TAP IS ALL IT TAKES", "Геккон сам бежит вверх по стене.\n\nКоснись экрана, чтобы перепрыгнуть на другую стену. Выбирай момент, обходи опасности и собирай монеты.":"The gecko runs up the wall automatically.\n\nTap to jump to the other wall. Time your jump, avoid hazards and collect coins.", "На компьютере: мышь или пробел.\nEsc — пауза.":"On PC: mouse or Space.\nEsc to pause.", "ДЕНЬ":"DAY", "НОЧЬ":"NIGHT", "60 Гц":"60 Hz", "120 Гц":"120 Hz"
}

func _ready() -> void:
	_keys = EN.keys()
	_keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())

func set_language(value: String) -> void:
	var selected := value if value in ["ru", "en"] else "ru"
	if language != selected:
		language = selected
		_cache.clear()
		changed.emit()

# Translate the whole sentence before substituting values. Dynamic names and
# numbers then never rely on partial-word replacements or a number-specific regex.
func format_text(source: String, values: Array) -> String:
	return text(source) % values

func text(source: String) -> String:
	if language == "ru" or source.is_empty():
		return source
	if source.ends_with(" м") and source.left(1).is_valid_int():
		return source.trim_suffix(" м") + " m"
	if source.is_valid_int():
		return source
	if EN.has(source):
		return EN[source]
	if _cache.has(source):
		return _cache[source]
	if _keys.is_empty():
		_ready()
	var result := source
	var rx := RegEx.new()
	rx.compile("Откроется на ([0-9]+) уровне")
	result = rx.sub(result, "Unlocks at level $1", true)
	rx.compile("ЗАБРАТЬ \\+([0-9]+) МОНЕТ")
	result = rx.sub(result, "CLAIM +$1 COINS", true)
	for key: String in _keys:
		result = result.replace(key, EN[key])
		result = result.replace(key.to_upper(), str(EN[key]).to_upper())
	rx.compile("([0-9])\\s?м(?![А-Яа-я])")
	result = rx.sub(result, "$1 m", true)
	if _cache.size() > 512:
		_cache.clear()
	_cache[source] = result
	return result
