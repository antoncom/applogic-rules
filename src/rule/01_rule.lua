local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
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
            --["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		}
	},

	switch_time = {
		note = [[ Время переключения Sim ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
		}
	},

	event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
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
			method = "cpin",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
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

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		--input = "true",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "cpin",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ local unknown = ($usb == "disconnected" or $switching == "true") 
							if unknown then return "" else return $sim_ready end
						 ]],
		}
	},


	timeout = {
		note = [[ Таймаут отсутствия Сим карты. Источник: /etc/config/tsmodem  ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "tsmodem",
				section = "sim_$sim_id",
				option = "timeout_sim_absent",
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	wait_timer = {
		note = [[ Таймер ожидания на попытки найти Сим-карту в слоте ]],
		input = 0,
		modifier = {
			["1_skip"] = [[ return (not tonumber($os_time)) ]],
			["2_func"] = [[
				local wt = tonumber($wait_timer) or 0

				local STEP = os.time() - tonumber($os_time)
				if STEP > 50 then STEP = 2 end -- it uses when ntpd synced system time

				if ($sim_ready == "true" or $do_switch == "true") then
					return 0
				else
					return (wt + STEP)
				end
			]],
			["3_save"] = [[ return $wait_timer ]]

		}
	},

	do_switch = {
		note = [[ Переключает слот, если SIM-карта не найдена в текущем слоте  ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_switch",
			params = { rule = "01_rule"},
		},
		modifier = {
			["1_skip"] = [[
				local SIMID_OK = ($sim_id == "0" or $sim_id == "1")
				local USB_OK = 	( $usb == "connected" )
				local wt = tonumber($wait_timer) or 0
				local t = tonumber($timeout) or 0
				local TIMEOUT = (wt >= t)
				local SIM_NOT_READY = ($sim_ready == "false")
				return ( not (SIMID_OK and USB_OK and TIMEOUT and SIM_NOT_READY) )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			--["3_func"] = [[ return tostring($do_switch) ]],
			["4_frozen"] = [[ return 10 ]]
		}
	},

	reset_timer = {
		note = [[ Отсчёт секунд при отсутствии Сим-карты в слоте. ]],
		input = "0", -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip"] = [[ return (not tonumber($os_time)) ]],
			["2_func"] = [[
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local SIM_OK = ($sim_ready == "true")
				local USB_NOT_CONNECTED = ($usb == "disconnected")
				local st = tonumber($switch_time) or 0
				local JUST_SWITCHED = ((tonumber($os_time) - st) < 20)

				local rt = tonumber($reset_timer) or 0
				local TIMER = rt + STEP

				if USB_NOT_CONNECTED then return 0
				elseif JUST_SWITCHED then return 0
				elseif SIM_OK then return 0
				else return TIMER end
			]],
			["3_save"] = [[ return $reset_timer ]]
		}
	},


	reset_modem = {
		note = [[ Подать сигнал сброса на модем через каждые 20 сек. ]],
		input = "false",
		modifier = {
			["1_skip"] = [[
				local rt = tonumber($reset_timer) or 0
				return (rt < 20)
			]],
			["2_exec"] = [[
				ubus call tsmodem.stm send '{"command":"~0:SIM.EN=0"}' &> /dev/null;
				sleep 2;
				ubus call tsmodem.stm send '{"command":"~0:SIM.EN=1"}' &> /dev/null;
				sleep 2;
				ubus call tsmodem.stm send '{"command":"~0:SIM.PWR=0"}' &> /dev/null;
			]],
			["3_func"] = [[ return "true" ]],
			["4_frozen"] = [[ return 10 ]]
		}
	},

	os_time = {
		note = [[ Время ОС на предыдущей итерации ]],
		modifier = {
			["1_func"] = [[ return os.time() ]],
			["2_save"] = [[ return $os_time ]]
		}
	},

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
					"sim_id",
					"wait_timer",
					"reset_timer",
					"timeout",
					"do_switch",
					"sim_ready",
					"switching"
				}
			},
		}
	},


    journal = {
		modifier = {
			["1_skip"] = [[ 
				if ($event_is_new == "true" and ($sim_ready == "true" or $sim_ready == "false")) then return false else return true end 
			]],
			["2_func"] = [[ 
			local response 
			if $sim_ready == "" then 
				response = "not available" 
			elseif $sim_ready == "false" then 
				response = "not ready" 
			elseif $sim_ready == "true" then 
				response = "ready"
			else
				response = $sim_ready
			end
			
			return({ 
				datetime = $event_datetime,
				name = "Sim Card status",
				source = "Modem  (01-rule)",
				command = "AT+CPIN?",
				response = response
			}) 
		]],
			["3_store-db"] = {
				param_list = { "journal" }	
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
	-- Red is for some extraordinal application behavior, like watchdog, etc.
	local overview = {
		["reset_modem"] = { ["yellow"] = [[ return ($reset_modem == "true") ]] },
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["sim_ready"] = { ["yellow"] = [[ return ($sim_ready == "false" or $sim_ready == "*") ]] },
		["reset_timer"] = { ["yellow"] = [[ return (tonumber($reset_timer) and tonumber($reset_timer) > 0) ]] },
		["wait_timer"] = { ["yellow"] = [[ return (tonumber($wait_timer) and tonumber($wait_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:load("title"):modify():debug() 	-- Use debug(ONLY) to check the var only
	self:load("switching"):modify():debug(overview)
	self:load("switch_time"):modify():debug(overview)

	self:load("event_datetime"):modify():debug()
	self:load("event_is_new"):modify():debug()

	self:load("sim_id"):modify():debug()	-- Use "overview" to include the variable to the all rules overview report in debug mode
	self:load("usb"):modify():debug()
	self:load("sim_ready"):modify():debug(overview)

	self:load("timeout"):modify():debug()
	self:load("wait_timer"):modify():debug(overview)

	self:load("do_switch"):modify():debug(overview)
	self:load("reset_timer"):modify():debug(overview)
	self:load("reset_modem"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("send_ui"):modify():debug()
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
