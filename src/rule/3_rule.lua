local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если уровень сигнала ниже нормы.",
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
			["1_bash"] = [[ jsonfilter -e $.value ]]
		}
    },

	uci_signal_min = {
		note = [[ Минимальный уровень сигнала, заданный в конфиге для данной Сим, %. ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "signal_min",
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if ( tonumber($uci_signal_min) == nil ) then return "5" else return $uci_signal_min end ]]
		}
	},

	uci_timeout_signal = {
		note = [[ Таймаут по сигналу, заданный в конфиге для данной Сим, сек. ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "timeout_signal",
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if ( tonumber($uci_timeout_signal) == nil ) then return "99" else return "$uci_timeout_signal" end ]]
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

	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "signal",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if (tonumber($signal)) then return $signal else return "-" end ]],
            ["3_ui-update"] = {
                param_list = { "signal", "sim_id" }
            }
		},
	},

	signal_time = {
		note = [[ Время получения уровня сигнала оператора, UNIXTIME. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "signal",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_func"] = [[ if ($network_registration == 1) then return $signal_time else return "" end ]],
		},
	},

	signal_normal_last_time = {
		note = [[ Время, когда последний раз сигнал был выше нормы, UNIXTIME. ]],
		input = "",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "signal",
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local SIGNAL_OK = (
									tonumber($signal)
								and tonumber($uci_signal_min)
								and ($signal > $uci_signal_min or $network_registration ~= 1)
							)
				if SIGNAL_OK then return true else return false end
			]],
			["2_bash"] = [[ jsonfilter -e $.time ]],
			["3_func"] = [[ if ($network_registration == 1) then return $signal_normal_last_time else return os.time() end ]],
			["4_frozen"] = [[ return (tonumber($uci_timeout_signal) or 0) ]]
		}
	},

	low_signal_timer = {
		note = [[ Отсчитывает секунды, если урвень сигнала ниже нормы, сек. ]],
		input = 0,
		modifier = {
			["1_skip"] = [[ return not (
								$network_registration == 1
							and tonumber($signal_normal_last_time)
							and	tonumber($signal)
							and tonumber($signal_time)
							and tonumber($uci_signal_min)
						) ]],
			["2_func"] = [[ if ( $signal < $uci_signal_min )
				then return($signal_time - $signal_normal_last_time) else return(0) end ]],
			["3_ui-update"] = {
				param_list = { "low_signal_timer", "sim_id" }
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
		note = [[ Активирует и хранит трезультат переключения Сим-карты при слабом сигнале. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ( tonumber($low_signal_timer) and tonumber($uci_timeout_signal) and ($low_signal_timer > $uci_timeout_signal) )
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
	rule.debug_mode = debug_mode
	debug_mode.type = "RULE"
	debug_mode.level = "INFO"
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("uci_signal_min"):modify():debug()
	self:load("uci_timeout_signal"):modify():debug()
	self:load("network_registration"):modify():debug()
	self:load("signal"):modify():debug()
	self:load("signal_time"):modify():debug()
	self:load("signal_normal_last_time"):modify():debug(ONLY)
	self:load("low_signal_timer"):modify():debug()
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
