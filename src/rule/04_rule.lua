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
			["1_func"] = [[ if ($sim_id == "0" or $sim_id == "1") then return ("sim_" .. $sim_id) else return "ERROR. SIM_ID is not valid!" end ]],
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
			["2_func"] = [[
				local utp = tonumber($uci_timeout_ping) or 120
				return utp
			]],
		}
	},

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	ping_status = {
		note = [[ Результат PING-а сети ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "ping",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			--["2_save"] = [[ return $ping_status ]],
			--["3_frozen"] = [[ if tostring($ping_status) == "1" then return 10 else return 0 end ]]
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
			["2_func"] = 'return(os.date("%Y-%m-%d %H:%M:%S", tonumber($event_datetime)))'
		}
	},
	event_is_new = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "ping",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},

	r01_timer = {
		note = [[ Значение таймера отсутствия Сим-карты в слоте ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "wait_timer"
		},
	},

	r02_lastreg_timer = {
		note = [[ Значение таймера отсутствия регистрации в сети ]],
		source = {
			type = "rule",
			rulename = "02_rule",
			varname = "lastreg_timer"
		},
	},

	r03_lowbalance_timer = {
		note = [[ Значение таймера низкого баланса ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "lowbalance_timer"
		},
	},

	sim_balance = {
		note = [[ Сумма баланса на текущей Сим-карте, руб. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	lastping_timer = {
		note = [[ Отсчёт секунд при отсутствии PING в сети. ]],
		input = "0", -- Set default value each time you use [skip] modifier
		modifier = {
			["1_skip"] = [[ return not tonumber($os_time) ]],
			["2_func"] = [[
							local STEP = os.time() - tonumber($os_time)
							if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

							local tmr = tonumber($lastping_timer) or 0
							local utout = tonumber($uci_timeout_ping) or 120
							local r01t = tonumber($r01_timer) or 0
							local r02lt = tonumber($r02_lastreg_timer) or 0
							local r03lt = tonumber($r03_lowbalance_timer) or 0

							local TIMER = tmr + STEP
							local PING_OK = (tonumber($ping_status) and tonumber($ping_status) == 1)
							local REG_NOT_OK = (r02lt > 0)
							local BALANCE_NOT_OK = ((r03lt > 0) and ($sim_balance ~= "*") and ($sim_balance ~= ""))
							local SIM_NOT_OK = (r01t > 0)
							if REG_NOT_OK then return 0
							elseif BALANCE_NOT_OK then return 0
							elseif SIM_NOT_OK then return 0
							elseif PING_OK then return 0
							else return TIMER end
		 	]],
			["3_save"] = [[ return $lastping_timer ]]

		}
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],
		modifier= {
			["1_func"] = [[ return os.time() ]],
			["2_save"] = [[ return $os_time ]]
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
			["1_skip"] = [[
				local lt = tonumber($lastping_timer) or 0
				local utp = tonumber($uci_timeout_ping) or 0
				local READY = 	( $switching ~= "true" )
				local TIMEOUT = ( lt > utp )
				return ( not (READY and TIMEOUT) )
			]],
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
			["1_skip"] = [[ 
				if ($event_is_new == "true" and tonumber($ping_status)) then return false else return true end ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "]] .. I18N.translate("Изменилось состояние PING") .. [[",
					source = "]] .. I18N.translate("Modem (04-rule)") .. [[",
					command = "ping 8.8.8.8",
					response = $ping_status
				})]],
			["3_store-db"] = {
				param_list = { "journal" }
			},
			["4_frozen"] = [[ return 2 ]]
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
		if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r03_sim_balance < 0 -----") end
		return 
	end


	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_section"):modify():debug()
	self:load("host"):modify():debug()
    self:load("uci_timeout_ping"):modify():debug()

    self:load("network_registration"):modify():debug()
    self:load("ping_status"):modify():debug()
	self:load("r01_timer"):modify():debug()
	self:load("r02_lastreg_timer"):modify():debug()
	self:load("r03_lowbalance_timer"):modify():debug()
    self:load("sim_balance"):modify():debug()
	self:load("lastping_timer"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("do_switch"):modify():debug(overview)
	self:load("event_datetime"):modify():debug()
	self:load("event_is_new"):modify():debug()
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
