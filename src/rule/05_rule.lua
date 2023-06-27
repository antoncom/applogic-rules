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
			--["2_frozen"] = [[ return 6 ]]
		},
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
			["2_func"] = [[ if (tonumber($signal)) then return $signal else return "" end ]],
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
		},
	},

	signal_normal_last_time = {
		note = [[ Время, когда последний раз сигнал был выше нормы, UNIXTIME. ]],
		modifier = {
			-- Инициализируем при старте и если нет сети
			["1_func"] = [[ if not(tonumber($signal_normal_last_time)) or $network_registration ~= 1
							then
								return tostring(os.time())
							else
								return $signal_normal_last_time
							end ]],
			-- Если сигнал ОК, то обновляем время signal_normal_last_time
			-- Если сигнал ниже нормы то сохраняе старое значение signal_normal_last_time
			["2_func"] = [[
				local SIGNAL_OK = (
						tonumber($signal)
					and tonumber($uci_signal_min)
					and $signal >= $uci_signal_min
				)
				if SIGNAL_OK
					then
						return $signal_time
					else
						return $signal_normal_last_time
				end
			]],
			-- Сохраняем значение для следующей итерации
			["3_save"] = [[ return $signal_normal_last_time ]],
		}
	},

	rule_03_lowbalance_timer = {
		note = [[ Значение lowbalance_timer из правила 03_rule ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "lowbalance_timer"
		},
	},

	rule_04_lastping_timer = {
		note = [[ Значение lastping_timer из правила 04_rule ]],
		source = {
			type = "rule",
			rulename = "04_rule",
			varname = "lastping_timer"
		},
	},

	low_signal_timer = {
		note = [[ Отсчитывает секунды, если уровень сигнала ниже нормы, сек. ]],
		input = 0,
		modifier = {
			["1_skip"] = [[
							local SIGNAL_OK = ((
									tonumber($signal)
								and tonumber($uci_signal_min)
								and $signal > $uci_signal_min)
								or (not tonumber($signal_time))
								or (not tonumber($signal_normal_last_time))
								or (tonumber($rule_03_lowbalance_timer) and tonumber($rule_03_lowbalance_timer) > 0)
								or (tonumber($rule_04_lastping_timer) and tonumber($rule_04_lastping_timer) > 0)
							)
							return SIGNAL_OK
					 	 ]],
			["2_func"] = [[ return($signal_time - $signal_normal_last_time) ]],
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
			["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		}
	},

	do_switch = {
		note = [[ Активирует и хранит трезультат переключения Сим-карты при слабом сигнале. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "05_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ( tonumber($low_signal_timer) and tonumber($uci_timeout_signal) and ($low_signal_timer >= $uci_timeout_signal) )
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
					"low_signal_timer",
					"signal"
				}
			},
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

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("uci_signal_min"):modify():debug()
	self:load("uci_timeout_signal"):modify():debug()
	self:load("network_registration"):modify():debug()
	self:load("signal"):modify():debug()
	self:load("signal_time"):modify():debug()
	self:load("signal_normal_last_time"):modify():debug()
	self:load("rule_03_lowbalance_timer"):modify():debug()
	self:load("rule_04_lastping_timer"):modify():debug()
	self:load("low_signal_timer"):modify():debug()
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
