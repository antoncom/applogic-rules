
-- Сервис Applogic - основной компонент управления логикой поведения прибора
---=========================================================================
-- Applogic, сокращение от “Application Logic” — это сервис в составе встраиваемого ПО, предназначенный для 
-- гибкой настройки работы микроэлектронного прибора посредством пользовательских сценариев на языке скриптов Lua.

-- Applogic - это движок, который в замкнутом цикле обрабатывает пользовательские правила, например такие:

-- root@RZE-BR02:~# applogic list
--		"01_rule": "Правило переключения если нет Cим-карты в слоте",
--		"02_rule": "Правило переключения Cим-карты при отсутствии регистрации в сети",
--		"03_rule": "Правило переключения Сим-карты, если баланс ниже минимума",
--		"04_rule": "Правило переключения Сим-карты при отсутствии PING сети",
--		"05_rule": "Правило переключения Сим-карты, если уровень сигнала ниже нормы.",
--		"06_rule": "Мигание светодиода LED1 - уровень сигнала",
--		"14_rule": "Автоопределение провайдера",
--		"16_rule": "Правило для управления роутером по СМС.",
--		"19_rule": "Журналирование событий GPIO",
--		"20_rule": "Журналирование - статус интерфейса MODEM"
--		"99_rule": "Правило отображения процесса 'Переключение Сим' в веб-интерфейсе",

-- Логический узел
---===============
-- Каждое правило состоит из логических (или вычислительных) узлов, создаваемых инженером-настройщиком.
-- В каждый логический узел можно добавить один или несколько оперторов узла.
-- Узлы в правиле обрабатываеются последовательно и могут использовать значения узлов, вычисленных ранее 
-- на текущей итерации обработки правил ранее.

-- Оператор узла - это функция, выполняющая какую-то одну операцию, например:
--==============
-- [load-ubus]	- Получает данные по системной шине UBUS, либо отправляет управляющий запрос;
-- [subscribe]	- Подписывает логический узел на событие системной шины;
-- [skip]		- Пропускает обработку следующих за ним операторов узла;
-- [frozen]		- Предназначен для задержки (заморозки) вычисленного в узле значения на заданное время;
-- [save]		- Сохраняет вычисленное значение узла для использования в следующей итерации обработки правил;
-- [timeout]	- Включает обратный отсчёт заданного количества секунд;
-- [websocket]	- Передаёт данные в веб-интерфейс (или панель индикации);
-- [journal]	- Обеспечивает журналирование данных, вычисляемых в узлах правила;
-- [break]		- Прерывает выполнение текущего правила в зависимости от заданных условий;

-- Режимы отладки
---==============
-- Для отладки спользуются следующие команды в shell-консоли прибора:

-- applogic debug 05_rule		- показать отладочную таблицу правила 05_rule;
-- applogic debug overview		- показать отладочную таблицу всех правил по заданным узлам;


require "os"
require "ubus"

local uloop = require "uloop"
local util = require "luci.util"
local uci = require "luci.model.uci".cursor()
local checkubus = require "applogic.util.checkubus"
local debug_cli = require "applogic.node.debug_cli"
local flist = require "applogic.util.filelist"
local report = require "applogic.util.report"
local md5 = require "md5"
local subscript = require "applogic.util.subscriptions"

--[[ Restore UCI config of Applogic once the debug stopped by Ctrl-C ]]
local signal = require("posix.signal")
signal.signal(signal.SIGINT, function(signum)

	uci:set("applogic", "debug_mode", "enable", 0)
	uci:set("applogic", "debug_mode", "level", "ERROR")
	uci:delete("applogic", "debug_mode", "rule")
	uci:delete("applogic", "debug_mode", "showvar")
	uci:commit("applogic")

  io.write("\n")
  print("-----------------------")
  print("Applogic debug stopped.")
  print("UCI config restored.")
  print("-----------------------")
  io.write("\n")
  os.exit(128 + signum)
end)



local rules = {}
rules.iteration = 1

rules.ubus_object = {}
rules.conn = nil
rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
rules.state = 	{
					mode = "run",	-- "run", "stop" are only possible
				}					-- "stop" is needed when web-console of AT commands is activated
									-- or tsmsms module uses tsmodem when processes sms read/send requests.
									-- "stop" stops ubus-requests from applogic to tsmodem.driver,
									-- as tsmodem.driver automation is in "stop" mode too.

rules.subscriptions = {}


local rules_setting = {
	title = "Группа правил Applogict",
	rules_list = {
		target = {},
	},
	tick_size_default = 800	-- use 1900 ms interval in debug mode
}

-- Подготавливаем таблицы для кэширования ответов от UBUS.
-- Создаём таблицу для хранения подписок узлов на события UBUS.

function rules:init()
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
	rules.subscriptions = subscript:init(rules.conn)
end

-- Вспомогательная функция для очистки кэшированных UBUS-запросов.
-- Данный кэш очищается перед каждой новой итерацией обработки правил.

function rules:clear_cache()
	rules.cache_ubus, rules.cache_uci, rules.cache_bash = {}, {}, {}
	collectgarbage()

end

-- Вспомогательная функция для генерации ключа доступа к кэшированным данным

function evuuid(name, match)
	return md5.sumhexa(tostring(name)..tostring(util.serialize_json(match)))
end


function rules:make_subscription(rule)
	subscript:make_subscription(rule)
end

function rules:make_ubus()
	self.conn = ubus.connect()
	if not self.conn then
		error("rules:make_ubus() - Failed to connect to ubus")
	end

	--[[ Get name of Ubus object from /etc/config/applogic ]]
	local ubus_name = uci:get("applogic", "ubus", "object") or "applogic"

	local ubus_object = {
		[ubus_name] = {

			-- Метод выводит список правил в консоль прибора по команде "applogic list"

			list = {
				function(req, msg)
					local rlist = {}

					for rule_file, rule_obj in util.kspairs(self.setting.rules_list.target) do
						rlist[rule_file] = rule_obj["setting"]["title"]["input"]
					end

					self.conn:reply(req, rlist)
				end, {id = ubus.INT32, msg = ubus.STRING }
			},

			state = {
	            function(req, msg)
	                if msg["mode"] and msg["mode"] == "run" then
						rules.state = { mode = "run" }
						resp = rules.state
	                elseif msg["mode"] and msg["mode"] == "stop" then
	                    rules.state = {
							mode = "stop",
							run_after = 30,
							comment = [[
								After 30 sec. Applogic will check if http session is active.
								If the http session is expired or user logged off from UI,
								then Applogic go back to 'run' mode automatically.
							]]
						}
						rules.state.comment = rules.state.comment:gsub("\t", "")
						rules.state.comment = rules.state.comment:gsub("\n", " ")
						resp = rules.state
					else
						resp = rules.state
	                end

	                self.conn:reply(req, resp);
	            end, {id = ubus.INT32, msg = ubus.STRING }
	        },
		},
	}
	self.conn:add( ubus_object )
	self.ubus_object = ubus_object

end


function rules:make()
	local rules_path = "/usr/lib/lua/applogic/rule"
	local id, ruleshome = '', self.setting.rules_list.target

	local files = flist({path = rules_path, grep = ".lua"})
	for i=1, #files do
		id = util.split(files[i], '.lua')[1]
		ruleshome[id] = require("applogic.rule." .. id)
	end
end

-- Если сервис Tsmodem (драйвер модема) занят други сервисом,
-- то приостанавливаем обработку правил Applogic.

function rules:check_driver_automation()
	local driver_mode = ""
	if checkubus(rules.conn, "tsmodem.driver", "lock_status") then
		local tsmodem_lock_status = util.ubus("tsmodem.driver", "lock_status", {})

		if tsmodem_lock_status and tsmodem_lock_status["owner"] then
			if tsmodem_lock_status["owner"] == "" then
				driver_mode = "run"
			else
				driver_mode = "stop"
			end
		end
		rules.state.mode = driver_mode
	end
end

function rules:run_all()

	local rules_list = self.setting.rules_list.target
	local state = ''

	for name, rule in util.kspairs(rules_list) do

		state = rule(self)

		if rule.debug_mode.enabled then
			local rule_has_error = rule.debug_mode.level == "ERROR" and (rule.debug and rule.debug.noerror and rule.debug.noerror == false)
			local report_anyway_mode = rule.debug_mode.level == "INFO"
			if rule.debug then
				if rule_has_error or report_anyway_mode then
					rule.debug.report(rule):print_rule(rule.debug_mode.level, rule.iteration)
					rule.debug.report(rule):clear()
				end
				rule.debug.noerror = true
			end
		end
	end

	if (debug_cli.rule and debug_cli.rule == "overview") then
		rules:overview(rules_list,rules.iteration)
	end

	if (debug_cli.rule and debug_cli.rule == "queue") then
		report:queue(rules, iteration)
	end

	rules:clear_cache()
	rules.iteration = rules.iteration + 1
end

-- Выводим общую отладочную таблицу, которая показывается при выполнении консольной команды "applogic debug overview"

function rules:overview(rules_list, iteration)
	report:overview(rules_list, iteration)
end


local metatable = {
	__call = function(table)
		table.setting = rules_setting
		local tick = table.setting.tick_size_default

		table:make_ubus()
		table:init()
		table:make()

		-- looping
		uloop.init()

		local timer
		function t()
			table:run_all()
			timer:set(tick)
		end
		timer = uloop.timer(t)
		timer:set(tick)
		uloop.run()

		table.conn:close()
		return table
	end
}
setmetatable(rules, metatable)
rules()