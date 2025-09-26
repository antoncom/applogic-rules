local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Cим-карты при отсутствии регистрации в сети",
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
			end
		}
	},

	uci_section = {
		note = [[ Идентификатор секции вида "sim_0" или "sim_1". Источник: /etc/config/tsmodem ]],

		{
			["func"] = function (nodes)
				if (nodes.sim_id == "0" or nodes.sim_id == "1") then
					return ("sim_" .. nodes.sim_id)
				else
					return "ERROR, no SIM_ID!"
				end
			end,
		}
	},

	timeout = {
		note = [[ Таймаут отсутствия регистрации в сети. Источник: /etc/config/tsmodem  ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "$uci_section",
					option = "timeout_reg",
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

	sim_ready = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],

		{
			["load-rule"] = {
				rulename = "01_rule",
				nodename = "sim_ready",
			}
		},
	},

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети -1..9. ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.network_registration) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				if (nodes.sim_ready == "false") then return "-1"
				elseif (nodes.iface_up == "UP") then return nodes.network_registration
				elseif (nodes.iface_up == "*") then return "9"
				elseif (nodes.iface_up == "false") then return "8"
				else return nodes.network_registration end
			end
		}
	},

	lastreg_timer = {
		note = [[ Отсчёт секунд при отсутствии REG ]],
		default = 0, -- Set default value if you need "reset" variable before skipping

		{
			["skip"] = function (nodes)
				return (not tonumber(nodes.os_time))
			end
		},
		{
			["func"] = function (nodes)
				local STEP = os.time() - tonumber(nodes.os_time)
				if (STEP > 50) then STEP = 2 end -- it uses when ntpd synced system time

				local netreg = tonumber(nodes.network_registration) or 0
				local lastreg_t = tonumber(nodes.lastreg_timer) or 0
				local SIM_NOT_OK = (nodes.sim_ready ~= "true")
				local SWITCHING = (nodes.switching ~= "false")
				local REG_OK = netreg and (netreg == 1 or netreg == 7 or netreg == -1)
				if (REG_OK or SIM_NOT_OK or SWITCHING) then
					return 0
				else return ( lastreg_t + STEP ) end
			end
		},
		{
            ["save"] = function (nodes)
				return nodes.lastreg_timer
			end,
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

	iface_up = {
		note = [[ Поднялся ли интерфейс TSMODEM - Link до интернет-провайдера ]],

        {
			["skip"] = function (nodes)
				return (not (nodes.sim_ready == "true" and nodes.switching ~= "true") )
			end
		},
		{
			["load-ubus"] = {
				object = "network.interface.modem",
				method = "status",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.iface_up) or {}
				return lua_table.up or ""
			end
		},
		{
			["func"] = function (nodes)
				local lastreg_t = tonumber(nodes.lastreg_timer) or 0

				if (nodes.iface_up == true) then
					return "true"
				elseif lastreg_t < 30 then
					return "*"
				else
					return "false"
				end
			end
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
				method = "reg",
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
	event_reg = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "reg",
				params = {}
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.event_reg) or {}
				return lua_table.value or ""
			end
		}
	},


	do_switch = {
		note = [[ Переключает слот, если SIM не зарегистрирована в GSM сети или нет соединения с интернет. ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local lastreg_t = tonumber(nodes.lastreg_timer) or 0
				local out = tonumber(nodes.timeout) or 0
				local READY = 	(nodes.switching == "" or nodes.switching == "false" )
				local TIMEOUT = ( lastreg_t > out )
				return ( not (READY and TIMEOUT) )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "do_switch",
				params = { rule = "02_rule"},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.do_switch) or {}
				return lua_table.value or ""
			end
		},
		{
			["func"] = function (nodes)
				return tostring(nodes.do_switch)
			end
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
					"lastreg_timer",
					"network_registration",
					"lastreg_timer",
					"do_switch",
					"switching"
				}
			}
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
					name = "Изменился статус регистрации в GSM-сети",
					source = "Modem  (02-rule)",
					command = "AT+CREG?",
					response = nodes.event_reg
				})
			end
		},
		{
			["store-db"] = {
				param_list = { "journal" }
			}
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
		["lastreg_timer"] = { ["yellow"] = [[ return (tonumber($lastreg_timer) and tonumber($lastreg_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 02_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug() -- Use debug(ONLY) to check the var only
	self:follow("sim_id"):debug()
	self:follow("switching"):debug()
	self:follow("uci_section"):debug()
	self:follow("timeout"):debug()

	self:follow("sim_ready"):debug()
	self:follow("network_registration"):debug()
	self:follow("lastreg_timer"):debug()
	self:follow("os_time"):debug()
	self:follow("iface_up"):debug()
	self:follow("event_datetime"):debug()
	self:follow("event_is_new"):debug()
	self:follow("event_reg"):debug()
	self:follow("do_switch"):debug(overview)
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
