local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сми-карты при отсутствии PING сети",
	},

	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "sim",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	uci_section = {
		note = [[ Идентификатор секции вида "sim_0" или "sim_1". Источник: /etc/config/tsmodem ]],
		modifier = {
			["1_lua-func"] = function (vars)
				if (vars.sim_id == "0" or vars.sim_id == "1") then return ("sim_" .. vars.sim_id) else return "ERROR. SIM_ID is not valid!" end
			end,
		}
	},

	host = {
		note = [[ Пробный хост для тестирования (обычно Google-сервер) ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "default",
				option = "ping_host"
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	uci_timeout_ping = {
		note = [[ Таймаут отсутствия PING в сети. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "$uci_section",
				option = "timeout_ping",
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_lua-func"] = function (vars)
				local utp = tonumber(vars.uci_timeout_ping) or 120
				return utp
			end,
		}
	},


	ping_status = {
		note = [[ Результат PING-а сети ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "ping",
			params = {},
			--cached = "no"
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},
	event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_lua-func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},


	lastping_timer = {
		note = [[ Отсчёт секунд при отсутствии PING в сети. ]],
		input = "0", -- Set default value each time you use [skip] modifier
		modifier = {
			["1_skip-func"] = function (vars)
				local no_ostime = not tonumber(vars.os_time)
				local switching = (vars.switching ~= "false")
				local switch = (vars.do_switch and vars.do_switch == "true")
				return (no_ostime or switching or switch)
			end,
			["2_lua-func"] = function (vars)
							local STEP = os.time() - tonumber(vars.os_time)
							if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

							local tmr = tonumber(vars.lastping_timer) or 0
							local utout = tonumber(vars.uci_timeout_ping) or 120
							local TIMER = tmr + STEP
							local PING_OK = (tonumber(vars.ping_status) and tonumber(vars.ping_status) == 1)
							if PING_OK then return 0
							else return TIMER end
		 	end,
			["3_save-func"] = function (vars)
				return vars.lastping_timer
			end

		}
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],
		modifier= {
			["1_lua-func"] = function (vars)
				return os.time()
			end,
			["2_save-func"] = function (vars)
				return vars.os_time
			end
		}
	},

	do_switch = {
		note = [[ Переключает слот, если нет PING на текущей SIM-ке. ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "04_rule"},
		},
		modifier = {
			["1_skip-func"] = function (vars)
				local lt = tonumber(vars.lastping_timer) or 0
				local utp = tonumber(vars.uci_timeout_ping) or 0
				local READY = 	( vars.switching ~= "true" )
				local TIMEOUT = ( lt > utp )
				return ( not (READY and TIMEOUT) )
			end,
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_frozen"] = [[ return 10 ]]

		}
	},
	
	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"do_switch",
					"ping_status",
					"lastping_timer",
					"host"
				}
			},
		}
	},
	journal = {
		modifier = {
			["1_lua-func"] = function (vars)
				return({
					datetime = vars.event_datetime,
					name = "Изменилось состояние PING",
					source = "Modem (04-rule)",
					command = "ping 8.8.8.8",
					response = vars.ping_status
				})
			end,
			["2_store-db"] = {
				param_list = { "journal" }
			},
			["3_frozen"] = [[ 
				-- Для уменьшения "дребезга", задержим вывод в журнал на 1 минуту при успешном пинге и на 30 сек. при неуспешном
				if ($ping_status == "1") then return 60 else return 30 end
				return 2 
			]]
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
	-- Yellow is for that vars which switches logic - affects to normal application behavior
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


	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_section"):modify():debug()
	self:load("host"):modify():debug()
    self:load("uci_timeout_ping"):modify():debug()

    self:load("ping_status"):modify():debug()
   	self:load("switching"):modify():debug()
	self:load("lastping_timer"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("do_switch"):modify():debug(overview)
	self:load("event_datetime"):modify():debug()
	self:load("send_ui"):modify():debug()
	self:load("journal"):modify():debug(overview)

end

---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule
