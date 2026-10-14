local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local cjson = require "cjson.safe"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если уровень сигнала ниже нормы.",
	},

	slotinfo = {
		note = [[ Данные о слотах Сим ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmslot",
					method = "info",
					params = {},
				}
			end
		},
		{	-- Если идёт процесс переключения, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 15) then return true end
			end
		},
	},

	sim_found = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.driver",
					method = "cpin",
					params = {},
				}
			end
		},
		{	-- Если нет симки в слоте, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				return (nodes.sim_found.value ~= "true")
			end
		}
	},


	signal_min_conf = {
		note = [[ Минимальный уровень сигнала, заданный в конфиге для данной Сим, %. ]],

		{
			["load-ubus"] = function (nodes)
				return({
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
					}
				})
			end
		},
		{
			["func"] = function (nodes)
				return nodes.signal_min_conf.values or {}
			end
		},
	},

	signal = {
		note = [[ Текущий уровень сигнала до базовой станции ]],
		{
			["load-ubus"] = function (nodes)
				return({
		 			object = "tsmodem.driver",
		 			method = "signal",
		 			params = {},
				})
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					signal = tostring(nodes.signal.value),
					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
					min_level = tostring(nodes.signal_min_conf.signal_min) or 0
				})
			end
		},

		{
			["break"] = function(nodes)
				local min = nodes.signal_min_conf.signal_min and tonumber(nodes.signal_min_conf.signal_min) or 0
				local current = tonumber(nodes.signal.value) or 0
				return current >= min
			end
		},
	},

	timeout = {
		note = [[ Таймаут при сигнале ниже минимума.  ]],
		{   -- Запускаем таймер
			["timeout"] = function(nodes)
				return tonumber(nodes.signal_min_conf.timeout_signal) or 60
			end
		},

	},

	switch = {
		note = [[ Переключить слот Сим-карт при сигнале ниже минимума ]],
		{
			["skip"] = function (nodes)
				local stil_wait = (nodes.timeout.value > 5)
				return stil_wait
			end
		},
		{
			["journal"] = function (nodes)
				return({
					name = '"Переключение слота при слабом сигнале",',
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "Modem (05-rule)",
					command = "",
					response = "started"
				})
			end
		},
		{
			["load-ubus"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == "0") then new_slotid = "1" end
				if(current_slotid == "1") then new_slotid = "0" end
				return {
					object = "tsmslot",
					method = "switch",
					params = { slotid = new_slotid },
					cached = "no",
				}
			end
		},

		{
			["frozen"] = function (nodes)
				return 30
			end
		}
	}
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 04_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- Если надо вывести отдельные узлы в отладочную таблицу режима "applogic debug overview",
	-- то добавьте сюда Lua-таблицу для таких узлов и передайте её в :debug(overview).
	-- Функция возвращает два значения: true/false и значение для колонки RESULT:
	--     return true, nodes.signal.value
	-- Цвет строки применяется, если первое значение true. Приоритет: red > yellow > green.
	--   green  - таймеры и пассивные узлы
	--   yellow - узлы, переключающие логику правила
	--   red    - нештатное поведение (переключение слота и т.п.)
	-- Если второе значение не вернуть, в RESULT выводится полное значение узла.
	-- nodes - те же значения узлов, что получают операторы ([func], [skip] ...)
	local overview = {
		["signal"] = { ["yellow"] = function(nodes)
				local signal = type(nodes.signal) == "table" and nodes.signal or {}
				local conf = type(nodes.signal_min_conf) == "table" and nodes.signal_min_conf or {}
				local sig = tonumber(signal.value)
				local sig_min = tonumber(conf.signal_min)
				local is_low = (sig ~= nil and sig_min ~= nil and sig < sig_min)
				return is_low, string.format("%s (min %s)", tostring(signal.value or "-"), tostring(conf.signal_min or "-"))
			end
		},
		["switch"] = { ["red"] = function(nodes)
				-- [frozen] хранит значение узла как JSON-строку, поэтому декодируем
				local switch = nodes.switch
				if type(switch) == "string" then switch = cjson.decode(switch) end
				local status = type(switch) == "table" and switch["status"] or nil
				return (status == "started"), (status or "-")
			end
		},
	}

	self:follow("title"):debug()
	self:follow("slotinfo"):debug()
	self:follow("sim_found"):debug()
	self:follow("signal_min_conf"):debug()
	self:follow("signal"):debug(overview)
	self:follow("timeout"):debug()
	self:follow("switch"):debug(overview)
end


local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule