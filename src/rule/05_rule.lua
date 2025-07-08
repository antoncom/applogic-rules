local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если уровень сигнала ниже нормы.",
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
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.sim_id) or {}
				return lua_table.value or ""
			end,
		}
    },

    uci_signal_before = {
		note = [[ Предыдущее значение минимального уровень сигнала в конфиге. ]],

		{
			["load-rule"] = {
				rulename = "05_rule",
				varname = "uci_signal_min"
			}
		}
	},

	uci_signal_min = {
		note = [[ Минимальный уровень сигнала, заданный в конфиге для данной Сим, %. ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "signal_min",
				},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.uci_signal_min) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (vars)
				local usm = tonumber(vars.uci_signal_min) or 5
				return usm
			end
		},
		{
			["save"] = function (vars)
				return vars.uci_signal_min
			end
		}
	},

	uci_timeout_signal = {
		note = [[ Таймаут по сигналу, заданный в конфиге для данной Сим, сек. ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "timeout_signal",
				},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.uci_timeout_signal) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (vars)
				local uts = tonumber(vars.uci_timeout_signal) or 121
				return uts
			end
		}
	},

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.network_registration) or {}
				return lua_table.value or ""
			end,
		},
	},

	json_signal = {
		note = [[ Уровень сигнала сотового оператора, JSON. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "signal",
				params = {},
			}
		},
	},


	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],

		{
			["load-rule"] = {
				rulename = "05_rule",
				varname = "json_signal"
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.signal) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (vars)
				local s = tonumber(vars.signal) or 0
				if (s > 0) then return s else return "" end
			end,
		},
	},

	r01_timer = {
		note = [[ Значение таймера отсутствия Сим-карты в слоте ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				varname = "wait_timer"
			}
		},
	},

	r02_lastreg_timer = {
		note = [[ Значение таймера отсутствия регистрации в сети ]],

		{
			["load-rule"] = {
				rulename = "02_rule",
				varname = "lastreg_timer"
			}
		},
	},

	r03_lowbalance_timer = {
		note = [[ Значение lowbalance_timer из правила 03_rule ]],

		{
			["load-rule"] = {
				type = "rule",
				rulename = "03_rule",
				varname = "lowbalance_timer"
			},
		}
	},

	r04_lastping_timer = {
		note = [[ Значение lastping_timer из правила 04_rule ]],

		{
			["load-rule"] = {
				rulename = "04_rule",
				varname = "lastping_timer"
			}
		},
	},

	sim_balance = {
		note = [[ Сумма баланса на текущей Сим-карте, руб. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "balance",
				params = {},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.sim_balance) or {}
				return lua_table.value or ""
			end,
		}
	},

	low_signal_timer = {
		note = [[ Отсчитывает секунды, если уровень сигнала ниже нормы, сек. ]],
		default = 0,

		{
			["skip"] = function (vars)
				local no_ostime = not tonumber(vars.os_time)
				local switching = (vars.switching and vars.switching ~= "false")
				local switch = (vars.do_switch and vars.do_switch == "true")
				return (no_ostime or switching or switch)
			end
		},
		{
			["func"] = function (vars)
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
			end
		},
		{
			["save"] = function (vars)
				return vars.low_signal_timer
			end
		}
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],

		{
			["func"] = function (vars)
				return os.time()
			end
		},
		{
			["save"] = function (vars)
				return vars.os_time
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
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.switching) or {}
				return lua_table.value or ""
			end,
		}
	},

	do_switch = {
		note = [[ Переключает слот если уровень сигнала на данной SIM ниже порогового/ ]],
		default = "false",

		{
			["skip"] = function (vars)
				local READY = 	( vars.switching == "" or vars.switching == "false" )
				local lst = tonumber(vars.low_signal_timer) or 0
				local uts = tonumber(vars.uci_timeout_signal) or 0
				local TIMEOUT = ( lst > uts )
				return ( not (READY and TIMEOUT) )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "05_rule"},
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["frozen"] = function (vars)
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
					"low_signal_timer",
					"signal"
				}
			},
		}
	},
	event_datetime = {
		{
			["load-rule"] = {
				rulename = "05_rule",
				varname = "json_signal"
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.event_datetime) or {}
				return lua_table.time or ""
			end
		},
		{
			["func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end
		}
	},
    event_is_new = {
		{
			["load-rule"] = {
				rulename = "05_rule",
				varname = "json_signal"
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.event_is_new) or {}
				return lua_table.unread or ""
			end,
		}
	},
    journal = {
		{
			["skip"] = function (vars)
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
			end
		},
		{
			["func"] = function (vars)
				return({
					datetime = vars.event_datetime,
					name = "Низкий уровень сигнала базовой станции",
					source = "Modem  (05-rule)",
					command = "AT+CSQ",
					response = tostring(vars.signal .. "%" .. " (при норме  " .. vars.uci_signal_min .."%)")
				})
			end
		},
		{
			["store-db"] = {
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

	self:follow("title"):debug()
	self:follow("sim_id"):debug()
	self:follow("uci_signal_before"):debug()
	self:follow("uci_signal_min"):debug()
	self:follow("uci_timeout_signal"):debug()
	self:follow("network_registration"):debug()

	self:follow("json_signal"):debug()
	self:follow("signal"):debug()

	self:follow("r01_timer"):debug()
	self:follow("r02_lastreg_timer"):debug()

	self:follow("r03_lowbalance_timer"):debug()
	self:follow("r04_lastping_timer"):debug()
	self:follow("sim_balance"):debug()
	self:follow("low_signal_timer"):debug(overview)
	self:follow("os_time"):debug()
	self:follow("switching"):debug()
	self:follow("do_switch"):debug(overview)
	self:follow("send_ui"):debug()
	self:follow("event_datetime"):debug()
    self:follow("event_is_new"):debug()
    self:follow("journal"):debug()
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
