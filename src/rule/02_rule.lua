local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если баланс ниже минимума",
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
			["2_func"] = [[ if ( tonumber($uci_balance_min) == nil ) then return "30" else return $uci_balance_min end ]]
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
			["2_func"] = [[ if ( tonumber($uci_timeout_bal) == nil ) then return 999 else return $uci_timeout_bal end ]]
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

	balance_new = {
		note = [[ Признак изменившегося баланса: true/false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {},
		},
		modifier = {
			--["1_bash"] = [[ sed s/\'//g ]],
			--["1_bash"] = [[ jsonfilter -e $.unread ]]
			["1_bash"] = [[ jsonfilter -e $.time ]]
		}
	},


	event_datetime = {
		note = [[ Дата актуального баланса в формате для Web-интерфейса. ]],
		modifier = {
			["1_func"] = [[ if ( tonumber($balance_time) ~= nil) then return(os.date("%Y-%m-%d %H:%M:%S", tonumber($balance_time))) else return "" end ]]
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
            ["2_func"] = [[ if ( tonumber($balance_time) == nil) then return 0 else return $sim_balance end ]],
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

    lowbalance_timer = {
		note = [[ Счётчик секунд при балансе ниже минимума, сек. ]],
		input = 0,
        modifier = {
			["1_skip"] = [[
				return not ( tonumber($sim_balance) and tonumber($uci_balance_min) and (tonumber($sim_balance) < tonumber($uci_balance_min)) )
			]],
			["2_func"] = [[
				local TIMER = tonumber($balance_time) and (os.time() - $balance_time) or false
				if TIMER then return TIMER end
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
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_ui-update"] = {
				param_list = { "switching", "sim_id" }
			},
		}
	},

	ui_balance = {
		note = [[ Отправляет в веб-интерфейс данные об изменившемся балансе.  ]],
		modifier = {
			["1_skip"] = [[ return $balance_new == "true" ]],
			["2_ui-update"] = {
				param_list = { "sim_id", "sim_balance", "event_datetime", "lowbalance_timer" }
			}
		}
	},

	do_switch = {
		note = [[ Активирует и хранит трезультат переключения Сим-карты при низком балансе. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local READY = 	( $switching == "" or $switching == "false" )
				local TIMEOUT = ( tonumber($lowbalance_timer) and $lowbalance_timer > $uci_timeout_bal )
				return ( not (READY and TIMEOUT) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_ui-update"] = {
				param_list = { "do_switch", "sim_id" }
			},
			-- ["4_init"] = {
			-- 	vars = {"lowbalance_timer"}
			-- }
		}
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)

function rule:make()
	rule.debug_mode = debug_mode
	debug_mode.type = "RULE"
	debug_mode.level = "ERROR"
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("uci_balance_min"):modify():debug()
	self:load("uci_timeout_bal"):modify():debug()

	self:load("balance_time"):modify():debug()
	self:load("balance_new"):modify():debug()
	self:load("event_datetime"):modify():debug()
	self:load("sim_balance"):modify():debug()
	self:load("balance_message"):modify():debug()
	self:load("ussd_command"):modify():debug()
	self:load("lowbalance_timer"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("ui_balance"):modify():debug()

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
