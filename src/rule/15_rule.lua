local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило периодического опроса баланса, а также переключения слота, если баланс ни разу не получен.",
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
			["bash"] = [[ jsonfilter -e $.value ]]
		}
	},

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				nodename = "sim_ready",
			}
		},
	},

	sim_not_ready_last_time = {
		note = [[ Время когда SIM была необнаружена ]],
		default = os.time(),

		{
			["skip"] = function (nodes)
				return (nodes.sim_ready == "true")
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "cpin",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_not_ready_last_time) or {}
				return lua_table.time or ""
			end
		},
		{
			["save"] = function (nodes)
				return nodes.sim_not_ready_last_time
			end,
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
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.switching) or {}
				return lua_table.value or ""
			end,
		}
	},

	usb = {
		note = [[ Состояние USB-порта: connected / disconnected  ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "usb",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.usb) or {}
				return lua_table.value or ""
			end,
		}
	},

	connected_usb_time = {
		note = [[ Время когда USB порт установился в состояние "connected"  ]],
		default = 0,

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "usb",
				params = {},
			}
		},
		{
			["skip"] = function (nodes)
				return (nodes.usb == "disconnected" )
			end
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.connected_usb_time) or {}
				return lua_table.time or ""
			end,
		}
	},

	provider_id = {
		note = [[ Идентификатор провайдера ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "provider_name",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.provider_id) or {}
				return lua_table.comment or ""
			end,
		}
	},

    ussd_command = {
        note = [[ USSD команда для данного провайдера ]],
		default = "",

        {
			["skip"] = function (nodes)
				return not (tonumber(nodes.provider_id) and (nodes.provider_id ~= 0))
			end
		},
		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem_adapter_provider",
					section = "$provider_id",
					option = "balance_ussd"
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.ussd_command) or {}
				return lua_table.value or ""
			end,
        }
    },

    current_balance_state = {
        note = [[ Текущий статус баланса (число, * (значит в процессе), либо "" - если последний запрос был неудачен) ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
            	method = "balance",
            	params = {},
        	}
		},
        {
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.current_balance_state) or {}
				return lua_table.value or ""
			end,
        }
    },

	uci_balance_timeout = {
		note = [[ Таймаут, по истечении которого слот переключается ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "timeout_bal",
				}
			}
		},
        {
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.uci_balance_timeout) or {}
				return lua_table.value or ""
			end
        }
	},

    a_balance_interval = {
        note = [[ Частота запроса баланса: 1-2 мин. - в первые 10 мин активной SIM; Затем 15..45 мин. при постоянной работе на данной SIM. ]],
		default = 60,

		{
			["skip"] = function (nodes)
				local SIM_READY = (nodes.sim_ready == "true")
				local OS_TIME_READY = tonumber(nodes.os_time)
				local USBTIME_OK = tonumber(nodes.connected_usb_time)
				local BALANCE_OK = tonumber(nodes.current_balance_state)
				local SKIP_IF = not (SIM_READY and OS_TIME_READY and BALANCE_OK and USBTIME_OK)
				return SKIP_IF
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local beginning = 180
				local snrlt = tonumber(nodes.sim_not_ready_last_time) or 0
				local JUST_STARTED = (snrlt == 0)
				local SIM_JUST_INSERTED = ((snrlt > 0) and (os.time() - snrlt) < beginning )
				local IS_USB_RECENTLY_CONNECTED = ((tonumber(nodes.os_time) - tonumber(nodes.connected_usb_time)) < 900)
				if (JUST_STARTED or SIM_JUST_INSERTED or IS_USB_RECENTLY_CONNECTED) then
					local ubt = tonumber(nodes.uci_balance_timeout) or 120
					-- it uses to coordinate chek balance interval (15_rule) and switch SIM on low balance (03_rule)
					return math.random (ubt+10, ubt*2)
				else
					return math.random (900, 2700) -- 15..45 mins
				end
			end,
		},
		{
			["frozen"] = function (nodes)
				local NOT_CALCULATED_AGAIN_TIME = tonumber(nodes.a_balance_interval) and (tonumber(nodes.a_balance_interval) + 10)
				return NOT_CALCULATED_AGAIN_TIME or 0
			end
        }
    },

    timer = {
		note = [[ Отсчёт интервалов получения баланса ]],
		default = 0, -- Set default value if you need "reset" variable before skipping

		{
			["skip"] = function (nodes)
				local JUST_STARTED = (not tonumber(nodes.os_time))
				return JUST_STARTED
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time
				local SIM_OK = (nodes.sim_ready == "true")
				local t = tonumber(nodes.timer) or 0
				local bi = tonumber(nodes.a_balance_interval) or 0
                if (SIM_OK and (t < bi)) then
                    return ( t + STEP )
                else return 0 end
			end
		},
		{
            ["save"] = function (nodes)
            	return nodes.timer
            end
		}
	},

	wait_balance = {
		note = [[ Максимальное значение timeout, после которого прекращаются неудачные попытки получить баланс ]],

		{
			["func"] = function (nodes)
				return 600
			end,
		}
	},

	timeout = {
		note = [[ Таймаут - сколько ждать получения валидного значения баланса ]],
		default = 600, -- Set default value if you need "reset" variable before skipping

		{
			["skip"] = function (nodes)
				return not tonumber(nodes.os_time)
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local tut = tonumber(nodes.timeout) or 0
				local BALANCE_VALID = (tonumber(nodes.current_balance_state))
				local BALANCE_FAIL = (nodes.current_balance_state == "")

				if (BALANCE_VALID or BALANCE_FAIL) then return nodes.wait_balance
				elseif (tut > 0) then
					return ( tut - STEP )
				else
					return nodes.wait_balance
				end
			end
		},
		{
			["save"] = function (nodes) return nodes.timeout end
		}
	},


    os_time = {
		note = [[ Текущее время системы (вспомогательная переменная) ]],

		{
            ["func"] = function (nodes) return os.time() end
		},
		{
            ["save"] = function (nodes) return nodes.os_time end
        }
    },

    send_command = {
        note = [[ AT-команда запроса баланса - выполняется через каждые $a_balance_interval  ]],
		default = "false",

        {
            ["skip"] = function (nodes)
				local pid = tonumber(nodes.provider_id) or 0
				local t = tonumber(nodes.timer) or 0
				local USSD_OK = (nodes.ussd_command ~= "")
				local SIM_OK = (nodes.sim_ready == "true")
				local PROVIDER_IDENTIFIED = (pid ~= 0)
                local TIME_TO_REQUEST = (t < 5)
                local BALANCE_OK = tonumber(nodes.current_balance_state)
                local BALANCE_FAIL = (nodes.current_balance_state == "")
                local BALANCE_IN_PROGRESS = (nodes.current_balance_state == "*")
				local NOBODY_SWITCHING = (nodes.switching == "false" or nodes.switching == "")
                local READY_TO_SEND = SIM_OK and PROVIDER_IDENTIFIED and TIME_TO_REQUEST and (BALANCE_OK or BALANCE_FAIL) and (not BALANCE_IN_PROGRESS) and NOBODY_SWITCHING

				-- delete after test start
				if pid ~= 25002 then -- megafon only, for test
					return true
				end
				-- delete after test end

				if USSD_OK and READY_TO_SEND then return false else return true end
            end
		},
		{
			["func"] = {
				function ()
					print("SEND_COMMAND, UPDATE BALANCE!!!")
				end
			}
		},
		-- {
		-- 	["load-ubus"] = {
		-- 		object = "tsmodem.driver",
		-- 		method = "send_at",
		-- 		params = {
		-- 			["command"] = "AT+CUSD=1,$ussd_command,15",
		-- 			["what-to-update"] = "balance"
		-- 		},
		-- 	}
		-- },
		{
			["load-ubus"] = {
				object = "tsmodem.sms",
				method = "send_sms",
				params = {
					["phone"] = "000100", -- megafon only for test; todo: phone for each provider_id;
					["text"] = "B",
				},
			}
		},
		{
			["func"] = function (nodes)
				print('update balance, send_command node value after ubus call:', nodes.send_command)
				local lua_table = luci.jsonc.parse(nodes.send_command) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes) return tostring(nodes.send_command) end
		},
		{
            ["frozen"] = function (nodes)
				return 10
			end, -- Задержать следующий запрос на 10 сек (это debounce)
        }
    },

	do_switch = {
		note = [[ Переключает Слот, если за время $wait_balance все попытки получения баланса были неудачны ]],
		default = "false",

		{
			["skip"] = function (nodes) return tonumber(nodes.timeout) and (tonumber(nodes.timeout) > 0) end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "15_rule"},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes) return tostring(nodes.do_switch) end
		},
		{
			["frozen"] = function (nodes)
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
	-- Yellow is for that nodes which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["timeout"] = { ["yellow"] = [[ return (tonumber($timeout) and tonumber($timeout) < 600) ]] },
		["send_command"] = { ["yellow"] = [[ return ($send_command == "true") ]] },
		["a_balance_interval"] = { ["green"] = [[ return true ]] },
		["timer"] = { ["green"] =  [[ 
			local t = tonumber($timer)
			return (t and t > 0)
		]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		if rule.debug_mode.enabled then print("------ 15_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end

	-- Пропускаем выполнения правила, если СИМ не зарегистрирована в сети
	local r02_lastreg_timer = tonumber(all_rules["02_rule"].setting.lastreg_timer.output)
	if (r02_lastreg_timer and r02_lastreg_timer > 0) then
		if rule.debug_mode.enabled then print("------ 15_rule SKIPPED as r02_lastreg_timer > 0 -----") end
		return
	end


	self:follow("title"):debug()
	self:follow("sim_id"):debug()
	self:follow("sim_ready"):debug(overview)
	self:follow("sim_not_ready_last_time"):debug(overview)
	self:follow("switching"):debug()
	self:follow("usb"):debug()
	self:follow("connected_usb_time"):debug()

	self:follow("provider_id"):debug()      					-- идентификатор провайдера на актиной Симке, наприм. 250099
	self:follow("ussd_command"):debug()     					-- USSD-код клманды, напр. #100#
    self:follow("current_balance_state"):debug()				-- Значение текущего баланса
	self:follow("uci_balance_timeout"):debug()
	self:follow("a_balance_interval"):debug(overview) 			-- С какой частотой запрашивать баланс у провайдера

    self:follow("timer"):debug(overview)            					-- Отсчёт интервалов
	self:follow("wait_balance"):debug()     					-- Количество времени, данное для попыток получения баланса
	self:follow("timeout"):debug(overview)          			-- Отсчёт таймаута - сколько ждать получения валидного баланса
	self:follow("os_time"):debug()

	self:follow("send_command"):debug(overview)     			-- Отправка АТ-команды модему, напр. AT+CUSD=1,#102#,15
	self:follow("do_switch"):debug(overview)
	self:follow("send_ui"):debug()
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
