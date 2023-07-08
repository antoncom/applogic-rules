local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило периодического опроса баланса, а также переключения слота, если баланс ни разу не получен.",
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

    provider_id = {
        note = [[ Идентификатор провайдера ]],
        source = {
            type = "ubus",
            object = "uci",
            method = "get",
            params = {
                config = "tsmodem",
                section = "sim_$sim_id",
                option = "provider"
            },
        },
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.value ]]
        }
    },

    ussd_command = {
        note = [[ USSD команда для данного провайдера ]],
        source = {
            type = "ubus",
            object = "uci",
            method = "get",
            params = {
                config = "tsmodem_adapter_provider",
                section = "$provider_id",
                option = "balance_ussd"
            },
        },
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.value ]]
        }
    },

    current_balance_state = {
        note = [[ Текущий статус баланса (число, * (значит в процессе), либо "" - если последний запрос был неудачен) ]],
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

	usb_ready = {
		note = [[ Статус подключения модема к USB-порту ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	usb_time = {
		note = [[ Ближайшее время когда модем был отключен от USB-порта ]],
		source = {
            type = "ubus",
            object = "tsmodem.driver",
            method = "usb",
            params = {},
        },
		modifier = {
			["1_skip"] = [[ return ($usb_ready == "connected") ]],
            ["2_bash"] = [[ jsonfilter -e $.time ]],
			["3_save"] = [[ return $usb_time ]]
        }
	},


    balance_interval = {
        note = [[ Частота запроса баланса: 45..90 сек в первые 10 мин активной SIM; 5..10 мин. при постоянной работе на данной SIM. ]],
        modifier= {
			["1_func"] = [[
				local beginning = 180
				local JUST_STARTED = ($usb_time == "")
				local JUST_SWITCHED = tonumber($usb_time) and ( (os.time() - tonumber($usb_time)) < 180 )
				if (JUST_STARTED or JUST_SWITCHED) then
					return math.random (45, 90)
				else
					return math.random (300, 600)
				end
			]],
			["2_save"] = [[ return $balance_interval ]],
			["3_frozen"] = [[
				local NOT_CALCULATED_AGAIN_TIME = tonumber($balance_interval) + 10
				return NOT_CALCULATED_AGAIN_TIME
			]]
        }
    },

    timer = {
		note = [[ Отсчёт интервалов получения баланса ]],
		input = 0, -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[ return not tonumber($os_time) ]],
			["2_func"] = [[
                if (tonumber($timer) <= tonumber($balance_interval)) then
                    return ( tonumber($timer) + (os.time() - tonumber($os_time)) )
                else return 0 end
			]],
            ["3_save"] = [[ return $timer ]]
		}
	},

	wait_balance = {
		note = [[ Максимальное значение timeout, после которого прекращаются неудачные попытки получить баланс ]],
		modifier= {
			["1_func"] = [[ return 600 ]],
		}
	},

	timeout = {
		note = [[ Таймаут - сколько ждать получения валидного значения баланса ]],
		input = 600, -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[
				return not tonumber($os_time)
			]],
			["2_func"] = [[
				if (tonumber($timeout) > 0) then
					return ( tonumber($timeout) - (os.time() - tonumber($os_time)) )
				else return $wait_balance end
			]],
			["3_save"] = [[
				local BALANCE_VALID = (tonumber($current_balance_state))
				local BALANCE_FAIL = ($current_balance_state == "")
				if BALANCE_VALID or BALANCE_FAIL then return $wait_balance else return $timeout end
			]]
		}
	},


    os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],
        modifier= {
            ["1_func"] = [[ return os.time() ]],
            ["2_save"] = [[ return $os_time ]]
        }
    },

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "sim_ready",
		},
	},

    send_command = {
        note = [[ AT-команда запроса баланса - выполняется через каждые $balance_interval  ]],
		input = "false",
        source = {
            type = "ubus",
            object = "tsmodem.driver",
            method = "send_at",
            params = {
                ["command"] = "AT+CUSD=1,$ussd_command,15",
				["what-to-update"] = "balance"
            },
        },
        modifier = {
            ["1_skip"] = [[
				local USB_OK = ($usb_ready == "connected")
				local SIM_OK = ($sim_ready == "true")
				local PROVIDER_IDENTIFIED = (tonumber($provider_id) and (tonumber($provider_id) ~= 0))
                local TIME_TO_REQUEST = (tonumber($timer) and (tonumber($timer) < 5))
                local BALANCE_OK = tonumber($current_balance_state)
                local BALANCE_FAIL = ($current_balance_state == "")
                local BALANCE_IN_PROGRESS = ($current_balance_state == "*")
				local NOBODY_SWITCHING = ($switching == "false")
                local READY_TO_SEND = USB_OK and SIM_OK and PROVIDER_IDENTIFIED and TIME_TO_REQUEST and (BALANCE_OK or BALANCE_FAIL) and (not BALANCE_IN_PROGRESS) and NOBODY_SWITCHING
                if READY_TO_SEND then return false else return true end
            ]],
            ["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_func"] = [[ return tostring($send_command) ]],
            ["4_frozen"] = [[ return 10 ]],                         -- Задержать следующий запрос на 10 сек (это debounce)
        }
    },

	do_switch = {
		note = [[ Переключает Слот, если за время $wait_balance все попытки получения баланса были неудачны ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "15_rule"},
		},
		modifier = {
			["1_skip"] = [[
				return ( tonumber($timeout) > 0 )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_func"] = [[ return tostring($do_switch) ]],
			["4_frozen"] = [[ return 10 ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"timeout",
					"do_switch",
					"switching",
					"wait_balance",
					"balance_interval",
					"timer"
				}
			},
		}
	},

}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
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
		["timeout"] = { ["yellow"] = [[ return (tonumber($timeout) and tonumber($timeout) < 600) ]] },
		["send_command"] = { ["yellow"] = [[ return ($send_command == "true") ]] },
		["balance_interval"] = { ["green"] = [[ return true ]] },
	}

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("provider_id"):modify():debug()      -- идентификатор провайдера на актиной Симке, наприм. 250099
	self:load("ussd_command"):modify():debug()     -- USSD-код клманды, напр. #100#
    self:load("current_balance_state"):modify():debug()
	self:load("usb_ready"):modify():debug()
	self:load("usb_time"):modify():debug()
	self:load("balance_interval"):modify():debug(overview) -- С какой частотой запрашивать баланс у провайдера
    self:load("timer"):modify():debug()            -- Отсчёт интервалов
	self:load("wait_balance"):modify():debug()     -- Количество времени, данное для попыток получения баланса
	self:load("timeout"):modify():debug(overview)          -- Отсчёт таймаута - сколько ждать получения валидного баланса
	self:load("os_time"):modify():debug()          -- Вспомогательное значение (текущее время ОС, напр. 32472389)

	self:load("sim_ready"):modify():debug(overview)
	self:load("send_command"):modify():debug(overview)     -- Отправка АТ-команды модему, напр. AT+CUSD=1,#102#,15
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
