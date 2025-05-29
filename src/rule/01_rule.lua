local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
	},

	resetting = {
		note = [[ Статус ресета модема. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "resetting",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
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
			["2_lua-func"] = function (vars)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(vars.event_datetime)))
			end
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
			["2_lua-func"] = function (vars)
				local unknown = (vars.usb == "disconnected" or vars.switching == "true") 
				if unknown then return "" else return vars.sim_ready end
			end
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
			["1_skip-func"] = function (vars)
				return (not tonumber(vars.os_time))
			end,
			["2_lua-func"] = function (vars)
				local wt = tonumber(vars.wait_timer) or 0

				local STEP = os.time() - tonumber(vars.os_time)
				if STEP > 50 then STEP = 2 end -- it uses when ntpd synced system time

				if (vars.sim_ready == "true" or vars.do_switch == "true") then
					return 0
				else
					return (wt + STEP)
				end
			end,
			["3_save-func"] = function (vars)
				return vars.wait_timer
			end

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
			["1_skip-func"] = function (vars)
				local SIMID_OK = (vars.sim_id == "0" or vars.sim_id == "1")
				local USB_OK = 	( vars.usb == "connected" )
				local wt = tonumber(vars.wait_timer) or 0
				local t = tonumber(vars.timeout) or 0
				local TIMEOUT = (wt >= t)
				local SIM_NOT_READY = (vars.sim_ready == "false")
				local NOT_SWITCHING = (vars.switching ~= "true")
				local NOT_RESETTING = (vars.resetting ~= "true")
				return ( not (SIMID_OK and USB_OK and TIMEOUT and SIM_NOT_READY and NOT_SWITCHING and NOT_RESETTING) )
			end,
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_frozen"] = [[ return 10 ]]
		}
	},

	reset_timer = {
		note = [[ Отсчёт секунд при отсутствии Сим-карты в слоте. ]],
		input = "0", -- Set default value if you need "reset" variable before skipping
		modifier = {
			["1_skip-func"] = function (vars)
				return (not tonumber(vars.os_time))
			end,
			["2_lua-func"] = function (vars)
				local v_ost = tonumber(vars.os_time) or 0
				local STEP = os.time() - v_ost
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local SIM_OK = (vars.sim_ready == "true")
				local USB_NOT_CONNECTED = (vars.usb == "disconnected")
				local st = tonumber(vars.switch_time) or 0
				local JUST_SWITCHED = ((v_ost - st) < 20)

				local rt = tonumber(vars.reset_timer) or 0
				local TIMER = rt + STEP

				if USB_NOT_CONNECTED then return 0
				elseif JUST_SWITCHED then return 0
				elseif SIM_OK then return 0
				else return TIMER end
			end,
			["3_save-func"] = function (vars)
				return vars.reset_timer
			end
		}
	},


	reset_modem = {
		note = [[ Подать сигнал сброса на модем через каждые 20 сек. ]],
		input = "false",
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "do_reset",
			params = { rule = "01_rule"},
		},
		modifier = {
			["1_skip-func"] = function (vars)
				local rt = tonumber(vars.reset_timer) or 0
				return (rt < 20 or vars.resetting == "true" or vars.switching == "true")
			end,
			["2_lua-func"] = function (vars)
				return "true"
			end,
			["4_frozen"] = [[ return 10 ]]
		}
	},

	os_time = {
		note = [[ Время ОС на предыдущей итерации ]],
		modifier = {
			["1_lua-func"] = function (vars)
				return os.time()
			end,
			["2_save-func"] = function (vars)
				return vars.os_time
			end
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
			["1_skip-func"] = function (vars)
				if (vars.event_is_new == "true" and (vars.sim_ready == "true" or vars.sim_ready == "false")) then return false else return true end 
			end,
			["2_lua-func"] = function (vars)
				local response 
				if vars.sim_ready == "" then 
					response = "not available" 
				elseif vars.sim_ready == "false" then 
					response = "not ready" 
				elseif vars.sim_ready == "true" then 
					response = "ready"
				else
					response = vars.sim_ready
				end
				
				return({ 
					datetime = vars.event_datetime,
					name = "Sim Card status",
					source = "Modem  (01-rule)",
					command = "AT+CPIN?",
					response = response
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
	self:load("resetting"):modify():debug(overview)
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
