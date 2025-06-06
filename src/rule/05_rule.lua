local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"
local util = require "luci.util"


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

    uci_signal_before = {
		note = [[ Предыдущее значение минимального уровень сигнала в конфиге. ]],
			source = {
			type = "rule",
			rulename = "05_rule",
			varname = "uci_signal_min"
		},
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
			["2_lua-func"] = function (vars)
				local usm = tonumber(vars.uci_signal_min) or 5
				return usm
			end,
			["3_save"] = [[ return $uci_signal_min ]]
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
			["2_lua-func"] = function (vars)
				local uts = tonumber(vars.uci_timeout_signal) or 121
				return uts
			end
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
		},
	},

	json_signal = {
		note = [[ Уровень сигнала сотового оператора, JSON. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "signal",
			params = {},
		},
	},


	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],
		source = {
			type = "rule",
			rulename = "05_rule",
			varname = "json_signal"
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_kua-func"] = function (vars)
				local s = tonumber(vars.signal) or 0
				if (s > 0) then return s else return "" end
			end,
		},
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
		note = [[ Значение lowbalance_timer из правила 03_rule ]],
		source = {
			type = "rule",
			rulename = "03_rule",
			varname = "lowbalance_timer"
		},
	},

	r04_lastping_timer = {
		note = [[ Значение lastping_timer из правила 04_rule ]],
		source = {
			type = "rule",
			rulename = "04_rule",
			varname = "lastping_timer"
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

	low_signal_timer = {
		note = [[ Отсчитывает секунды, если уровень сигнала ниже нормы, сек. ]],
		input = 0,
		modifier = {
			["1_skip-func"] = function (vars)
				local no_ostime = not tonumber(vars.os_time)
				local switching = (vars.switching and vars.switching ~= "false")
				local switch = (vars.do_switch and vars.do_switch == "true")
				return (no_ostime or switching or switch)
			end,
			["2_lua-func"] = function (vars)
				local STEP = os.time() - tonumber(vars.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local r01t = tonumber(vars.r01_timer) or 0
				local r02lt = tonumber(vars.r02_lastreg_timer) or 0
				local r03lt = tonumber(vars.r03_lowbalance_timer) or 0
				local r04lt = tonumber(vars.r04_lastping_timer) or 0
				local lst = tonumber(vars.low_signal_timer) or 0
				local s = tonumber(vars.signal) or 0
				local usm = tonumber(vars.uci_signal_min) or 0
				local TIMER = lst + STEP

				local PING_NOT_OK = (r04lt > 0)
				local REG_NOT_OK = (r02lt > 0)
				local BALANCE_NOT_OK = ((r03lt > 0) and (vars.sim_balance ~= "*") and (vars.sim_balance ~= ""))
				local SIM_NOT_OK = (r01t > 0)
				local SIGNAL_OK = (s > usm)
				if REG_NOT_OK then return 0
				elseif BALANCE_NOT_OK then return 0
				elseif SIM_NOT_OK then return 0
				elseif PING_NOT_OK then return 0
				elseif SIGNAL_OK then return 0
				else return TIMER end
			end,
			["3_save-func"] = function (vars)
				return vars.low_signal_timer
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
		note = [[ Переключает слот если уровень сигнала на данной SIM ниже порогового/ ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "05_rule"},
		},
		modifier = {
			["1_skip-func"] = function (vars)
				local READY = 	( vars.switching == "" or vars.switching == "false" )
				local lst = tonumber(vars.low_signal_timer) or 0
				local uts = tonumber(vars.uci_timeout_signal) or 0
				local TIMEOUT = ( lst > uts )
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
					"low_signal_timer",
					"signal"
				}
			},
		}
	},
	event_datetime = {
		source = {
			type = "rule",
			rulename = "05_rule",
			varname = "json_signal"
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_lua-func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end
		}
	},
    event_is_new = {
		source = {
			type = "rule",
			rulename = "05_rule",
			varname = "json_signal"
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},
    journal = {
		modifier = {
			["1_skip-func"] = function (vars)
				local s = tonumber(vars.signal) or 0
				local lst = tonumber(vars.low_signal_timer) or 0
				local ucm = tonumber(vars.uci_signal_min)
				local ucmb = tonumber(vars.uci_signal_before) or ucm
				local LOW_SIGNAL = (lst > 0)
				local ISNEW = (vars.event_is_new == "true")
				local USER_UPDATE_SETTING = (ucmb ~= ucm and ucm > s)
				if (tonumber(vars.signal) and ((LOW_SIGNAL and ISNEW) or USER_UPDATE_SETTING)) then
					return false else return true
				end
			end,
			["2_lua-func"] = function (vars)
				return({
					datetime = vars.event_datetime,
					name = "Низкий уровень сигнала базовой станции",
					source = "Modem  (05-rule)",
					command = "AT+CSQ",
					response = tostring(vars.signal .. "%" .. " (при норме  " .. vars.uci_signal_min .."%)")
				})
			end,
			["3_store-db"] = {
				param_list = { "journal" }
			},
		}
	},

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
	-- Yellow is for that vars which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["low_signal_timer"] = { ["yellow"] = [[ return (tonumber($low_signal_timer) and tonumber($low_signal_timer) > 0) ]] },
	}

	-- Пропускаем выполнение правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target
	
	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 05_rule SKIPPED as r01_wait_timer > 0 -----") end
		return 
	end

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("uci_signal_before"):modify():debug()
	self:load("uci_signal_min"):modify():debug()
	self:load("uci_timeout_signal"):modify():debug()
	self:load("network_registration"):modify():debug()
	
	self:load("json_signal"):modify():debug()
	self:load("signal"):modify():debug()

	self:load("r01_timer"):modify():debug()
	self:load("r02_lastreg_timer"):modify():debug()

	self:load("r03_lowbalance_timer"):modify():debug()
	self:load("r04_lastping_timer"):modify():debug()
	self:load("sim_balance"):modify():debug()
	self:load("low_signal_timer"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("do_switch"):modify():debug(overview)
	self:load("send_ui"):modify():debug()
	self:load("event_datetime"):modify():debug()
    self:load("event_is_new"):modify():debug()
    self:load("journal"):modify():debug()
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
