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

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "sim_ready",
		},
	},

	sim_not_ready_last_time = {
		note = [[ Время когда SIM была необнаружена ]],
		input = os.time(),
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_skip"] = [[ return ($sim_ready == "true") ]],
			["2_bash"] = [[ jsonfilter -e $.time ]],
			["3_save"] = [[ return $sim_not_ready_last_time ]],
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

	usb = {
		note = [[ Состояние USB-порта: connected / disconnected  ]],
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

	connected_usb_time = {
		note = [[ Время когда USB порт установился в состояние "connected"  ]],
		input = 0,
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_skip"] = [[ return ($usb == "disconnected" ) ]],
			["2_bash"] = [[ jsonfilter -e $.time ]],
		}
	},

	provider_id = {
		note = [[ Идентификатор провайдера ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "provider_name",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.comment ]]
		}
	},

    ussd_command = {
        note = [[ USSD команда для данного провайдера ]],
		input = "",
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
			["1_skip"] = [[ return not (tonumber($provider_id) and ($provider_id ~= 0)) ]],
            ["2_bash"] = [[ jsonfilter -e $.value ]]
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

	uci_balance_timeout = {
		note = [[ Таймаут, по истечении которого слот переключается ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "timeout_bal",
			}
		},
        modifier = {
            ["1_bash"] = [[ jsonfilter -e $.value ]],
        }
	},

    a_balance_interval = {
        note = [[ Частота запроса баланса: 1-2 мин. в первые 10 мин активной SIM; 5..10 мин. при постоянной работе на данной SIM. ]],
		input = 60,
        modifier= {
			["1_skip"] = [[
				local SIM_READY = ($sim_ready == "true")
				local OS_TIME_READY = tonumber($os_time)
				local USBTIME_OK = tonumber($connected_usb_time)
				local BALANCE_OK = tonumber($current_balance_state)
				local SKIP_IF = not (SIM_READY and OS_TIME_READY and BALANCE_OK and USBTIME_OK)
				return SKIP_IF
			]],
			["2_func"] = [[
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local beginning = 180
				local snrlt = tonumber($sim_not_ready_last_time) or 0
				local JUST_STARTED = (snrlt == 0)
				local SIM_JUST_INSERTED = ((snrlt > 0) and (os.time() - snrlt) < beginning )
				local IS_USB_RECENTLY_CONNECTED = ((tonumber($os_time) - tonumber($connected_usb_time)) < 900)
				if (JUST_STARTED or SIM_JUST_INSERTED or IS_USB_RECENTLY_CONNECTED) then
					local ubt = tonumber($uci_balance_timeout) or 120
					-- it uses to coordinate chek balance interval (15_rule) and switch SIM on low balance (03_rule)
					return math.random (ubt+10, ubt*2)
				else
					return math.random (600, 900)
				end
			]],
			["3_save"] = [[ return $a_balance_interval ]],
			["4_frozen"] = [[
				local NOT_CALCULATED_AGAIN_TIME = tonumber($a_balance_interval) and (tonumber($a_balance_interval) + 10)
				return NOT_CALCULATED_AGAIN_TIME or 0
			]]
        }
    },

    timer = {
		note = [[ Отсчёт интервалов получения баланса ]],
		input = 0, -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[
				local JUST_STARTED = (not tonumber($os_time))
				local BALANCE_UNDEFINED = (not tonumber($current_balance_state))
				return JUST_STARTED or BALANCE_UNDEFINED
			]],
			["2_func"] = [[
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local SIM_OK = ($sim_ready == "true")
				local t = tonumber($timer) or 0
				local bi = tonumber($a_balance_interval) or 0
                if (SIM_OK and (t < bi)) then
                    return ( t + STEP )
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
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local tut = tonumber($timeout) or 0
				local BALANCE_VALID = (tonumber($current_balance_state))
				local BALANCE_FAIL = ($current_balance_state == "")

				if (BALANCE_VALID or BALANCE_FAIL) then return $wait_balance
				elseif (tut > 0) then
					return ( tut - STEP )
				else
					return $wait_balance
				end
			]],
			["3_save"] = [[ return $timeout ]]
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
        note = [[ AT-команда запроса баланса - выполняется через каждые $a_balance_interval  ]],
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
				local pid = tonumber($provider_id) or 0
				local t = tonumber($timer)
				local USSD_OK = ($ussd_command ~= "")
				local SIM_OK = ($sim_ready == "true")
				local PROVIDER_IDENTIFIED = (pid ~= 0)
                local TIME_TO_REQUEST = (t < 5)
                local BALANCE_OK = tonumber($current_balance_state)
                local BALANCE_FAIL = ($current_balance_state == "")
                local BALANCE_IN_PROGRESS = ($current_balance_state == "*")
				local NOBODY_SWITCHING = ($switching == "false")
                local READY_TO_SEND = SIM_OK and PROVIDER_IDENTIFIED and TIME_TO_REQUEST and (BALANCE_OK or BALANCE_FAIL) and (not BALANCE_IN_PROGRESS) and NOBODY_SWITCHING
                if USSD_OK and READY_TO_SEND then return false else return true end
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
			["1_skip"] = [[ return tonumber($timeout) and (tonumber($timeout) > 0) ]],
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
					"a_balance_interval",
					"timer"
				}
			},
		}
	},
	event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "balance",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_func"] = 'return(os.date("%Y-%m-%d %H:%M:%S", tonumber($event_datetime)))'
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
    journal = {
		modifier = {
			["1_skip"] = [[ if ($event_is_new == "true") then return false else return true end ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "]] .. I18N.translate("Periodic balance checking, and switching the slot if the balance has never been received.") .. [[",
					source = "]] .. I18N.translate("Modem  (15-rule)") .. [[",
					command = "AT+CUSD",
					response = $current_balance_state 
				})]],
                
			["3_ui-update"] = {
				param_list = { "journal" }
			},
			["4_frozen"] = [[ return 2 ]]
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
		["a_balance_interval"] = { ["green"] = [[ return true ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("sim_ready"):modify():debug(overview)
	self:load("sim_not_ready_last_time"):modify():debug(overview)
	self:load("switching"):modify():debug()
	self:load("usb"):modify():debug()
	self:load("connected_usb_time"):modify():debug()

	self:load("provider_id"):modify():debug()      					-- идентификатор провайдера на актиной Симке, наприм. 250099
	self:load("ussd_command"):modify():debug()     					-- USSD-код клманды, напр. #100#
    self:load("current_balance_state"):modify():debug()				-- Значение текущего баланса
	self:load("uci_balance_timeout"):modify():debug()
	self:load("a_balance_interval"):modify():debug(overview) 			-- С какой частотой запрашивать баланс у провайдера

    self:load("timer"):modify():debug()            					-- Отсчёт интервалов
	self:load("wait_balance"):modify():debug()     					-- Количество времени, данное для попыток получения баланса
	self:load("timeout"):modify():debug(overview)          			-- Отсчёт таймаута - сколько ждать получения валидного баланса
	self:load("os_time"):modify():debug()

	self:load("send_command"):modify():debug(overview)     			-- Отправка АТ-команды модему, напр. AT+CUSD=1,#102#,15
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
