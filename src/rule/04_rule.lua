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

	changed_ping_time = {
		note = [[ Время последнего успешного PING, или 0 если неизвестно. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "ping",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
		}
	},

	r01_timer = {
		note = [[ Значение lastreg_timer из правила 01_rule ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "timer"
		},
	},

	r02_lastreg_timer = {
		note = [[ Значение lastreg_timer из правила 02_rule ]],
		source = {
			type = "rule",
			rulename = "02_rule",
			varname = "lastreg_timer"
		},
	},

	r03_lowbalance_timer = {
		note = [[ Значение lowbalance_timer из правила 03_rule ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "lowbalance_timer"
		},
	},

	lastping_timer = {
		note = [[ Отсчёт секунд при отсутствии PING в сети. ]],
		input = "0", -- Set default value each time you use [skip] modifier
		modifier = {
			["1_skip"] = [[ local PING_OK = ($ping_status == 1 or $ping_status == "")
							local REG_NOT_OK = (tonumber($r02_lastreg_timer) and tonumber($r02_lastreg_timer) > 0)
							local BALANCE_NOT_OK = (tonumber($r03_lowbalance_timer) and tonumber($r03_lowbalance_timer) > 0)
							local SIM_NOT_OK = (tonumber($r01_timer) and tonumber($r01_timer) > 0)
							if REG_NOT_OK then return true
							elseif BALANCE_NOT_OK then return true
							elseif SIM_NOT_OK then return true
							elseif PING_OK then return true
							else return false end
						 ]],
			["2_func"] = [[
				local TIMER = tonumber($changed_ping_time) and (os.time() - $changed_ping_time) or false
				if TIMER then return TIMER else return 0 end
			]],
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
		note = [[ Активирует и возвращает трезультат переключения Сим-карты  ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "04_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ( $lastping_timer > $uci_timeout_ping )
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]

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
					"lastping_timer"
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

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_section"):modify():debug()
    self:load("uci_timeout_ping"):modify():debug()

    self:load("network_registration"):modify():debug()
    self:load("ping_status"):modify():debug()
    self:load("changed_ping_time"):modify():debug()
	self:load("r01_timer"):modify():debug()
	self:load("r02_lastreg_timer"):modify():debug()
	self:load("r03_lowbalance_timer"):modify():debug()
    self:load("lastping_timer"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("do_switch"):modify():debug()
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
