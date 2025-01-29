local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local util = require "luci.util"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если баланс ниже минимума. Работает совместно с правилами 14_rule, 15_rule",
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


	uci_balance_min = {
		note = [[ Минимальный уровень баланса, руб. ]],
		source = {
			type = "ubus",
            object = "uci",
            method = "get",
            params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "balance_min",
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[
				local ubm = tonumber($uci_balance_min) or 30
				return ubm
			]]
		}
	},

	uci_timeout_bal = {
		note = [[ Таймаут перед переключеием при низком балансе, сек. ]],
		source = {
			type = "ubus",
            object = "uci",
            method = "get",
            params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "timeout_bal",
			},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[
				local utb = tonumber($uci_timeout_bal) or 120
				return utb
			]]
		}
	},

    balance_time = {
		note = [[ Актуальная дата получения баланса, UNIXTIME. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]]
		}
	},

	event_datetime = {
		note = [[ Дата актуального баланса в формате для Web-интерфейса. ]],
		modifier = {
			["1_func"] = [[
				local bt = tonumber($balance_time) or 0
				if (bt ~= 0) then return(os.date("%Y-%m-%d %H:%M:%S", bt)) else return "" end
			]]
		}
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

	balance_message = {
		note = [[ Сообщение от GSM-провайдера ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.comment ]],
			--["2_bash"] = [[ sed s/\"//g ]],
		}
	},

	ussd_command = {
		note = [[ Хранит строку USSD-запроса на получение баланса.  ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.command ]]
		}
	},

	r01_timer = {
		note = [[ Значение wait_timer из правила 01_rule ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "wait_timer"
		},
	},

	r02_lastreg_timer = {
		note = [[ Значение lastreg_timer из правила 01_rule ]],
		source = {
			type = "rule",
			rulename = "02_rule",
			varname = "lastreg_timer"
		},
	},

    lowbalance_timer = {
		note = [[ Счётчик секунд при балансе ниже минимума, сек. ]],
		input = 0,
        modifier = {
			["1_skip"] = [[ return not tonumber($os_time) ]],
			["2_func"] = [[
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local lbt = tonumber($lowbalance_timer) or 0
				local sb = tonumber($sim_balance) or 0
				local ubmin = tonumber($uci_balance_min) or 0
				local r01t = tonumber($r01_timer) or 0
				local r02lt = tonumber($r02_lastreg_timer) or 0
				local TIMER = lbt + STEP
				local BALANCE_OK = (sb > ubmin)
				local BALANCE_EMPTY = (sb == 0)
				local SIM_NOT_REGISTERED = (r02lt > 0)
				local SIM_ABSENT = (r01t > 0)
				if SIM_ABSENT then return 0
				elseif BALANCE_EMPTY then return 0
				elseif SIM_NOT_REGISTERED then return 0
				elseif BALANCE_OK then return 0
				else return TIMER or 0 end
			]],
			["3_save"] = [[ return $lowbalance_timer ]]
        }
	},

	os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],
		modifier= {
			["1_func"] = [[ return os.time() ]],
			["2_save"] = [[ return $os_time ]]
		}
	},

	event_is_new = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
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
		note = [[ Переключает слот если баланс SIM ниже порогового. ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "03_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local lt = tonumber($lowbalance_timer) or 0
				local utb = tonumber($uci_timeout_bal) or 0
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ((lt + 10) > utb)
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_func"] = [[ return tostring($do_switch) ]],
			["4_frozen"] = [[ return 15 ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"do_switch",
					"sim_balance",
					"event_datetime",
					"lowbalance_timer",
				}
			},
		}
	},

	provider_id = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "provider_name",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.comment ]],
		}
	},

	journal = {
		modifier = {
			["1_skip"] = [[if ($event_is_new == "true" and (string.len($balance_message) > 0) )  then return false else return true end ]],
			["2_func"] = [[
			return({
					datetime = $event_datetime,
					name = "Получено значение баланса SIM-карты",
					source = "Modem (03-rule)",
					command = $ussd_command,
					["response"] = $balance_message,
					ussd_command = $ussd_command,
					provider_id = $provider_id
				})]],
			["3_store-db"] = {
				param_list = { "journal" }
			},
			["4_frozen"] = [[ return 2 ]],
		}
	},
}

--ussd = $ussd_command
-- balance = $balance_message

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 02_rule title sim_id" (use 5 variable names maximum)
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
		["lowbalance_timer"] = { ["yellow"] = [[ return (tonumber($lowbalance_timer) and tonumber($lowbalance_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		--if rule.debug_mode.enabled then print("------ 03_rule SKIPPED as r01_wait_timer > 0 -----") end
		return 
	end


	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_balance_min"):modify():debug()
	self:load("uci_timeout_bal"):modify():debug()

	self:load("balance_time"):modify():debug()
	self:load("event_datetime"):modify():debug()
	self:load("sim_balance"):modify():debug()
	self:load("balance_message"):modify():debug()
	self:load("ussd_command"):modify():debug()
	self:load("r01_timer"):modify():debug()
	self:load("r02_lastreg_timer"):modify():debug()
	self:load("lowbalance_timer"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("event_is_new"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("do_switch"):modify():debug(overview)
	self:load("send_ui"):modify():debug()
	self:load("provider_id"):modify():debug()
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
