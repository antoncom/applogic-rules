local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"


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
				if ((os.time() - last_switch_time) < 30) then return true end
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

	uci_conf = {
		note = [[ Минимальный уровень сигнала, заданный в конфиге для данной Сим, %. ]],

		{
			["load-ubus"] = function (nodes)
				return({
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. nodes.slotinfo.slot,
					}
				})
			end
		},
		{
			["func"] = function (nodes)
				return(nodes.uci_conf.values)
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
			["skip"] = function (nodes)
				return (not nodes.timeout)
			end
		},
		{
			["websocket"] = function (nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					signal = tostring(nodes.signal.value),
					timeout = nodes.timeout and tostring(nodes.timeout.inited),
					wait_timer = tostring(nodes.timeout.value),
					min_level = tostring(nodes.uci_conf.signal_min)
				})
			end
		},
	},

	timeout = {
		note = [[ Таймаут при сигнале ниже минимума.  ]],
		{
			["break"] = function (nodes)
				return (nodes.signal.value > nodes.uci_conf.signal_min)
			end
		},
		{   -- Запускаем таймер
			["timeout"] = function(nodes)
				return tonumber(nodes.uci_conf.timeout_signal)
			end
		},
	},

	switch = {
		note = [[ Переключить слот Сим-карт при сигнале ниже минимума ]],
		{
			["skip"] = function (nodes)
				local stil_wait = (nodes.timeout.value > 0)
				return stil_wait
			end
		},
		{
			["load-ubus"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == 0) then new_slotid = "1" else new_slotid = "0" end

				return {
					object = "tsmslot",
					method = "switch",
					params = { simid = new_slotid },
					cached = "no",
				}
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

	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive variables,
	-- Yellow is for that nodes which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["low_signal_timer"] = { ["yellow"] = [[ return (tonumber($low_signal_timer) and tonumber($low_signal_timer) > 0) ]] },
	}

	self:follow("title"):debug()
	self:follow("slotinfo"):debug()
	self:follow("sim_found"):debug()
	self:follow("uci_conf"):debug()
	self:follow("signal"):debug()
	self:follow("timeout"):debug()
	self:follow("switch"):debug()
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