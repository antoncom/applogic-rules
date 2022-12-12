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
			["2_ui-update"] = {
				param_list = { "sim_id", "ping_status" }
			}
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

	lastping_timer = {
		note = [[ Отсчёт секунд при отсутствии PING в сети. ]],
		input = "0", -- Set default value each time you use [skip] modifier
		modifier = {
			["1_skip"] = [[ return ($ping_status == 1 or $ping_status == "") ]],
			["2_func"] = [[
				local TIMER = tonumber($changed_ping_time) and (os.time() - $changed_ping_time) or false
				if TIMER then return TIMER else return 0 end
			]],
			["3_ui-update"] = {
				param_list = { "lastping_timer", "sim_id" }
			}
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_ui-update"] = {
				param_list = { "switching", "sim_id" }
			}
		}
	},

	do_switch = {
		note = [[ Активирует и возвращает трезультат переключения Сим-карты  ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ( $lastping_timer > $uci_timeout_ping )
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_ui-update"] = {
				param_list = { "do_switch", "sim_id" }
			}
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)
function rule:make()
	debug_mode.type = "RULE"
	debug_mode.level = "INFO"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_section"):modify():debug()
    self:load("uci_timeout_ping"):modify():debug()

    self:load("network_registration"):modify():debug()
    self:load("ping_status"):modify():debug(ONLY)
    self:load("changed_ping_time"):modify():debug()

    self:load("lastping_timer"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("do_switch"):modify():debug()

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
