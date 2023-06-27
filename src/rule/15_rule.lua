local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило периодического опроса баланса",
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
        note = [[ Текущий статус баланса (число, *, "in-progress", либо "" - если последний запрос был неудачен) ]],
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

    balance_interval = {
        note = [[ Периодичность получения баланса: случайное число от 45 до 60 сек. ]],
        modifier= {
            ["1_func"] = [[ return math.random (45, 60) ]],
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
			["1_func"] = [[ return 360 ]],
		}
	},

	timeout = {
		note = [[ Таймаут - сколько ждать получения валидного значения баланса ]],
		input = 360, -- Set default value if you need "reset" variable before skipping
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
				if BALANCE_VALID then return $wait_balance else return $timeout end
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

    send_command = {
        note = [[ AT-команда запроса баланса - выполняется через каждые $balance_interval  ]],
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
                local TIME_TO_REQUEST = ($timer < 5)
                local BALANCE_OK = tonumber($current_balance_state)
                local BALANCE_FAIL = ($current_balance_state == "")
                local BALANCE_IN_PROGRESS = ($current_balance_state == "*")
				local NOBODY_SWITCHING = ($switching == "false")
                local READY_TO_SEND = TIME_TO_REQUEST and (BALANCE_OK or BALANCE_FAIL) and (not BALANCE_IN_PROGRESS) and NOBODY_SWITCHING
                if READY_TO_SEND then return false else return true end
            ]],
            ["2_bash"] = [[ jsonfilter -e $.value ]],
            ["3_frozen"] = [[ return 10 ]],                         -- Задержать следующий запрос на 10 сек (это debounce)
        }
    },

	do_switch = {
		note = [[ Переключает Слот, если за время $wait_balance все попытки получения баланса были неудачны ]],
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
			["3_frozen"] = [[ if $do_switch == "true" then return 10 else return 0 end ]]
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

	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("provider_id"):modify():debug()      -- идентификатор провайдера на актиной Симке, наприм. 250099
	self:load("ussd_command"):modify():debug()     -- USSD-код клманды, напр. #100#
    self:load("current_balance_state"):modify():debug()
	self:load("balance_interval"):modify():debug() -- С какой частотой запрашивать баланс у провайдера
    self:load("timer"):modify():debug()            -- Отсчёт интервалов
	self:load("wait_balance"):modify():debug()     -- Количество времени, данное для попыток получения баланса
	self:load("timeout"):modify():debug()          -- Отсчёт таймаута - сколько ждать получения валидного баланса
	self:load("os_time"):modify():debug()          -- Вспомогательное значение (текущее время ОС, напр. 32472389)

	self:load("send_command"):modify():debug()     -- Отправка АТ-команды модему, напр. AT+CUSD=1,#102#,15
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
