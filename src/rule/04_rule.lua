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
			["1_func"] = [[ if ($sim_id == 0 or $sim_id == 1) then return ("sim_" .. $sim_id) else return "sim_0" end ]],
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
			["2_func"] = [[ if ( $uci_timeout_ping == "" or tonumber($uci_timeout_ping) == nil) then return "99" else return $uci_timeout_ping end ]],
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
			["2_save"] = [[ return $ping_status ]],
			["3_frozen"] = [[ if $ping_status == 1 then return 10 else return 0 end ]]
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
							local TIMER = $lastping_timer + (os.time() - $os_time)

							local PING_OK = (tonumber($ping_status) and tonumber($ping_status) == 1)
							local REG_NOT_OK = (tonumber($r02_lastreg_timer) and tonumber($r02_lastreg_timer) > 0)
							local BALANCE_NOT_OK = (tonumber($r03_lowbalance_timer) and tonumber($r03_lowbalance_timer) > 0 and $sim_balance ~= "*" and $sim_balance ~= "")
							local SIM_NOT_OK = (tonumber($r01_timer) and tonumber($r01_timer) > 0)
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
				local READY = 	( $switching == "false" )
				local TIMEOUT = ( tonumber($lastping_timer) > tonumber($uci_timeout_ping) )
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
	}
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
	self:load("send_ui"):modify():debug()

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
