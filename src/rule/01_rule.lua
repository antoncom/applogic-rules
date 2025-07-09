local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
	},

	resetting = {
		note = [[ Статус ресета модема. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "resetting",
				params = {},
				cached = "no",
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.resetting) or {}
				return lua_table.value or ""
			end
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "switching",
				params = {},
				cached = "no",
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.switching) or {}
				return lua_table.value or ""
			end
		},
	},

	switch_time = {
		note = [[ Время переключения Sim ]],

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
				local lua_table = luci.jsonc.parse(nodes.switch_time) or {}
				return lua_table.time or ""
			end
		}
	},

	event_datetime = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "cpin",
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
				method = "cpin",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_is_new) or {}
				return lua_table.unread or ""
			end
		}
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
			end
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
			end
		},
	},

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "cpin",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.sim_ready) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				local unknown = (nodes.usb == "disconnected" or nodes.switching == "true")
				if unknown then return "" else return nodes.sim_ready end
			end
		}
	},


	timeout = {
		note = [[ Таймаут отсутствия Сим карты. Источник: /etc/config/tsmodem  ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "timeout_sim_absent",
				}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.timeout) or {}
				return lua_table.value or ""
			end
		}
	},

	wait_timer = {
		note = [[ Таймер ожидания на попытки найти Сим-карту в слоте ]],
		default = 0,

		{
			["skip"] = function (nodes)
				local not_ostime = not tonumber(nodes.os_time)
				local switching = (nodes.switching ~= "false")
				return (switching or not_ostime)
			end
		},
		{
			["func"] = function (nodes)
				local wt = tonumber(nodes.wait_timer) or 0

				local STEP = os.time() - tonumber(nodes.os_time)
				if STEP > 50 then STEP = 2 end -- it uses when ntpd synced system time

				if (nodes.sim_ready == "true" or nodes.do_switch == "true") then
					return 0
				else
					return (wt + STEP)
				end
			end
		},
		{
			["save"] = function (nodes)
				return nodes.wait_timer
			end
		}
	},

	do_switch = {
		note = [[ Переключает слот, если SIM-карта не найдена в текущем слоте  ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local SIMID_OK = (nodes.sim_id == "0" or nodes.sim_id == "1")
				local USB_OK = 	( nodes.usb == "connected" )
				local wt = tonumber(nodes.wait_timer) or 0
				local t = tonumber(nodes.timeout) or 0
				local TIMEOUT = (wt >= t)
				local SIM_NOT_READY = (nodes.sim_ready == "false")
				local NOT_SWITCHING = (nodes.switching ~= "true")
				local NOT_RESETTING = (nodes.resetting ~= "true")
				return ( not (SIMID_OK and USB_OK and TIMEOUT and SIM_NOT_READY and NOT_SWITCHING and NOT_RESETTING) )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "01_rule"},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["frozen"] = function (nodes)
				return 10
			end
		}
	},

	reset_timer = {
		note = [[ Отсчёт секунд при отсутствии Сим-карты в слоте. ]],
		default = "0", -- Set default value if you need "reset" variable before skipping

		{
			["skip"] = function (nodes)
				local not_ostime = not tonumber(nodes.os_time)
				local switching = (nodes.switching ~= "false")
				return (switching or not_ostime)
			end
		},
		{
			["func"] = function (nodes)
				local v_ost = tonumber(nodes.os_time) or 0
				local STEP = os.time() - v_ost
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local SIM_OK = (nodes.sim_ready == "true")
				local USB_NOT_CONNECTED = (nodes.usb == "disconnected")
				local st = tonumber(nodes.switch_time) or 0
				local JUST_SWITCHED = ((v_ost - st) < 20)

				local rt = tonumber(nodes.reset_timer) or 0
				local TIMER = rt + STEP

				if USB_NOT_CONNECTED then return 0
				elseif JUST_SWITCHED then return 0
				elseif SIM_OK then return 0
				else return TIMER end
			end
		},
		{
			["save"] = function (nodes)
				return nodes.reset_timer
			end
		}
	},


	reset_modem = {
		note = [[ Подать сигнал сброса на модем через каждые 20 сек. ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local rt = tonumber(nodes.reset_timer) or 0
				return (rt < 20 or nodes.resetting == "true" or nodes.switching == "true")
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_reset",
				params = { rule = "01_rule"},
			}
		},
		{
			["func"] = function (nodes)
				return "true"
			end,
		},
		{
			["frozen"] = function (nodes)
				return 10
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

	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],

		{
			["ui-update"] = {
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
		{
			["skip"] = function (nodes)
				if (nodes.event_is_new == "true" and (nodes.sim_ready == "true" or nodes.sim_ready == "false")) then return false else return true end
			end
		},
		{
			["func"] = function (nodes)
				local response
				if nodes.sim_ready == "" then
					response = "not available"
				elseif nodes.sim_ready == "false" then
					response = "not ready"
				elseif nodes.sim_ready == "true" then
					response = "ready"
				else
					response = nodes.sim_ready
				end

				return({
					datetime = nodes.event_datetime,
					name = "Sim Card status",
					source = "Modem  (01-rule)",
					command = "AT+CPIN?",
					response = response
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


	self:follow("title"):debug() 	-- Use debug(ONLY) to check the var only
	self:follow("resetting"):debug(overview)
	self:follow("switching"):debug(overview)
	self:follow("switch_time"):debug(overview)

	self:follow("event_datetime"):debug()
	self:follow("event_is_new"):debug()

	self:follow("sim_id"):debug()	-- Use "overview" to include the variable to the all rules overview report in debug mode
	self:follow("usb"):debug()
	self:follow("sim_ready"):debug(overview)

	self:follow("timeout"):debug()
	self:follow("wait_timer"):debug(overview)

	self:follow("do_switch"):debug(overview)
	self:follow("reset_timer"):debug(overview)
	self:follow("reset_modem"):debug(overview)
	self:follow("os_time"):debug()
	self:follow("send_ui"):debug()
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
