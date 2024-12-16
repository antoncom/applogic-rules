local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило Watchdog для модема",
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

    idle_time = {
		note = [[ Сколько времени модем выключен (отсутствует /dev/ttyUSB2) ]],
		input = 0,
		modifier = {
			["1_skip"] = [[ return (not tonumber($os_time)) ]],
			["2_func"] = [[
				local STEP = os.time() - tonumber($os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local it = tonumber($idle_time) or 0
				if ($usb == "connected") then
					return 0
				else
					return (it + STEP)
				end
			]],
			["3_save"] = [[ return $idle_time ]]

		}
	},

	os_time = {
		note = [[ Время ОС на предыдущей итерации ]],
		modifier = {
			["1_func"] = [[ return os.time() ]],
			["2_save"] = [[ return $os_time ]]
		}
	},


    reinit_modem = {
		note = [[ Перезапускает модем если USB порт /dev/ttyUSB2 отсутствует более 2 мин. ]],
		modifier = {
			["1_skip"] = [[
				local it = tonumber($idle_time) or 0
				return ($usb == "connected" or (it <= 120))
			]],
            ["2_exec"] = [[
				ls /dev/ | grep ttyUSB2 || (
					ubus call tsmodem.stm send '{"command":"~0:SIM.EN=0"}' &> /dev/null;
					sleep 2;
					ubus call tsmodem.stm send '{"command":"~0:SIM.EN=1"}' &> /dev/null;
					sleep 2;
					ubus call tsmodem.stm send '{"command":"~0:SIM.PWR=0"}' &> /dev/null;
				)
			]],
 			["3_func"] = [[ return "true" ]],
            ["4_frozen"] = [[ return 30 ]]
		}
	},


	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],
		modifier = {
			["1_ui-update"] = {
				param_list = {
                    "idle_time",
					"sim_id"
				}
			},
		}
	},
	event_datetime = {
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
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
			method = "usb",
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
					name = "Изенилось состояние порта /dev/ttyUSB2",
					source = "Modem  (98-rule)",
					command = "watchdog",
					response = $usb
				})]],
			["3_store-db"] = {
				param_list = { "journal" }
			},
			--["4_frozen"] = [[ return 2 ]]
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
	-- Green is for timers and some passive, regular variables,
	-- Yellow is for that vars which switch the logic - e.g. affect to normal application behavior
	-- Red is for some extraordinal application behavior, like watchdog, etc.
	local overview = {
		["reinit_modem"] = { ["red"] = [[ return ($reinit_modem == "true") ]] },
		["idle_time"] = { ["red"] = [[ return (tonumber($idle_time) and tonumber($idle_time) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:load("title"):modify():debug() -- Use debug(ONLY) to check the var only
	self:load("sim_id"):modify():debug()
	self:load("usb"):modify():debug()
	self:load("idle_time"):modify():debug(overview)
	self:load("os_time"):modify():debug()
	self:load("reinit_modem"):modify():debug(overview)
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
