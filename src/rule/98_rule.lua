local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило Watchdog для модема",
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
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_id) or {}
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

    idle_time = {
		note = [[ Сколько времени модем выключен (отсутствует /dev/ttyUSB2) ]],
		default = 0,

		{
			["skip"] = function (nodes)
				return (not tonumber(nodes.os_time))
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local it = tonumber(nodes.idle_time) or 0
				if (nodes.usb == "connected") then
					return 0
				else
					return (it + STEP)
				end
			end
		},
		{
			["save"] = function (nodes)
				return nodes.idle_time
			end
		}
	},

	os_time = {
		note = [[ Время ОС на предыдущей итерации ]],

		{
			["func"] = function (nodes)
				return os.time()
			end
		},
		{
			["save"] = function (nodes)
				return nodes.os_time
			end
		}
	},


    reinit_modem = {
		note = [[ Перезапускает модем если USB порт /dev/ttyUSB2 отсутствует более 2 мин. ]],

		{
			["skip"] = function (nodes)
				local it = tonumber(nodes.idle_time) or 0
				return (nodes.usb == "connected" or (it <= 120))
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_reset",
				params = { rule = "98_rule"},
			}
		},
		{
 			["func"] = function (nodes)
 				return "true"
 			end
		},
		{
            ["frozen"] = function (nodes)
				return 30
			end
		}
	},


	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],

		{
			["ui-update"] = {
				param_list = {
                    "idle_time",
					"sim_id"
				}
			},
		}
	},
	event_datetime = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_datetime) or {}
				return lua_table.time or ""
			end
		},
		{
			["func"] = function (nodes)
				return(os.date("%Y-%m-%d %H:%M:%S", tonumber(nodes.event_datetime)))
			end
		}
	},
    event_is_new = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "usb",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_is_new) or {}
				return lua_table.unread or ""
			end,
		}
	},
    journal = {
		{
			["skip"] = function (nodes)
				if (nodes.event_is_new == "true") then return false else return true end
			end
		},
		{
			["func"] = function (nodes)
				return({
					datetime = nodes.event_datetime,
					name = "Изенилось состояние порта /dev/ttyUSB2",
					source = "Modem  (98-rule)",
					command = "watchdog",
					response = nodes.usb
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
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive, regular variables,
	-- Yellow is for that nodes which switch the logic - e.g. affect to normal application behavior
	-- Red is for some extraordinal application behavior, like watchdog, etc.
	local overview = {
		["reinit_modem"] = { ["red"] = [[ return ($reinit_modem == "true") ]] },
		["idle_time"] = { ["red"] = [[ return (tonumber($idle_time) and tonumber($idle_time) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:follow("title"):debug() -- Use debug(ONLY) to check the var only
	self:follow("sim_id"):debug()
	self:follow("usb"):debug()
	self:follow("idle_time"):debug(overview)
	self:follow("os_time"):debug()
	self:follow("reinit_modem"):debug(overview)
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
