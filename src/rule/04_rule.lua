local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты при отсутствии PING сети",
	},

	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "sim",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_id) or {}
				return lua_table.value or ""
			end,
		}
	},

	uci_section = {
		note = [[ Идентификатор секции вида "sim_0" или "sim_1". Источник: /etc/config/tsmodem ]],

		{
			["func"] = function (nodes)
				if (nodes.sim_id == "0" or nodes.sim_id == "1") then return ("sim_" .. nodes.sim_id) else return "ERROR. SIM_ID is not valid!" end
			end,
		}
	},

	host = {
		note = [[ Пробный хост для тестирования (обычно Google-сервер) ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "default",
					option = "ping_host"
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.host) or {}
				return lua_table.value or ""
			end
		}
	},

	uci_timeout_ping = {
		note = [[ Таймаут отсутствия PING в сети. Источник: /etc/config/tsmodem  ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "$uci_section",
					option = "timeout_ping",
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.uci_timeout_ping) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				local utp = tonumber(nodes.uci_timeout_ping) or 120
				return utp
			end,
		}
	},


	ping_status = {
		note = [[ Результат PING-а сети ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "ping",
				params = {},
				--cached = "no"
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.ping_status) or {}
				return lua_table.value or ""
			end,
		}
	},
	event_datetime = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_datetime) or {}
				return lua_table.time or ""
			end
		},
		{
			["func"] = function (nodes)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(nodes.event_datetime)))
			end
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "switching",
				params = {},
				cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.switching) or {}
				return lua_table.value or ""
			end,
		}
	},


	lastping_timer = {
		note = [[ Отсчёт секунд при отсутствии PING в сети. ]],
		default = "0", -- Set default value each time you use [skip] modifier

		{
			["skip"] = function (nodes)
				local no_ostime = not tonumber(nodes.os_time)
				local switching = (nodes.switching ~= "false")
				local switch = (nodes.do_switch and nodes.do_switch == "true")
				return (no_ostime or switching or switch)
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local tmr = tonumber(nodes.lastping_timer) or 0
				local utout = tonumber(nodes.uci_timeout_ping) or 120
				local TIMER = tmr + STEP
				local PING_OK = (tonumber(nodes.ping_status) and tonumber(nodes.ping_status) == 1)
				if PING_OK then return 0
				else return TIMER end
			end
		},
		{
			["save"] = function (nodes)
				return nodes.lastping_timer
			end
		}
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],

		{
			["func"] = function (nodes)
				return os.time()
			end
		},
		{
			["save"] = function (nodes)
				return nodes.os_time
			end
		}
	},

	do_switch = {
		note = [[ Переключает слот, если нет PING на текущей SIM-ке. ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local lt = tonumber(nodes.lastping_timer) or 0
				local utp = tonumber(nodes.uci_timeout_ping) or 0
				local READY = 	( nodes.switching ~= "true" )
				local TIMEOUT = ( lt > utp )
				return ( not (READY and TIMEOUT) )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "04_rule"},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["frozen"] = function (nodes)
				return 10
			end
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],

		{
			["ui-update"] = {
				param_list = {
					"sim_id",
					"do_switch",
					"ping_status",
					"lastping_timer",
					"host"
				}
			}
		}
	},
	journal = {
		{
			["func"] = function (nodes)
				return({
					datetime = nodes.event_datetime,
					name = "Изменилось состояние PING",
					source = "Modem (04-rule)",
					command = "ping 8.8.8.8",
					response = nodes.ping_status
				})
			end
		},
		{
			["store-db"] = {
				param_list = { "journal" }
			}
		},
		{
			["frozen"] = function (nodes)
				-- Для уменьшения "дребезга", задержим вывод в журнал на 1 минуту при успешном пинге и на 30 сек. при неуспешном
				if (nodes.ping_status == "1") then return 60 else return 30 end
			end
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 03_rule title sim_id" (use 5 variable names maximum)
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
		["lastping_timer"] = { ["yellow"] = [[ return (tonumber($lastping_timer) and tonumber($lastping_timer) > 0) ]] },
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end

	-- Пропускаем выполнения правила, если СИМ не зарегистрирована в сети
	local r02_lastreg_timer = tonumber(all_rules["02_rule"].setting.lastreg_timer.output)
	if (r02_lastreg_timer and r02_lastreg_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r02_lastreg_timer > 0 -----") end
		return
	end

	-- Пропускаем выполнения правила, если отрицательный баланс на счету Sim-карты
	local r03_sim_balance = tonumber(all_rules["03_rule"].setting.sim_balance.output)
	if (r03_sim_balance and r03_sim_balance <= 0) then
		--if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r03_sim_balance < 0 -----") end
		return
	end


	self:follow("title"):debug() -- Use debug(ONLY) to check the var only
	self:follow("sim_id"):debug()
	self:follow("uci_section"):debug()
	self:follow("host"):debug()
    self:follow("uci_timeout_ping"):debug()

    self:follow("ping_status"):debug()
   	self:follow("switching"):debug()
	self:follow("lastping_timer"):debug(overview)
	self:follow("os_time"):debug()
	self:follow("do_switch"):debug(overview)
	self:follow("event_datetime"):debug()
	self:follow("send_ui"):debug()
	self:follow("journal"):debug(overview)
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
