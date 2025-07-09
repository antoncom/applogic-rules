local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED2 - режим связи (2G, 3G или 4G)",
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

    network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],

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
			end
		},
		{
			["frozen"] = function (nodes)
				if (nodes.switching == "true") then return 10 else return 0 end
			end
		}
	},

    netmode = {
		note = [[ Режим сети 2G/3G/4G ]],

		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "netmode",
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.netmode) or {}
				return lua_table.value or ""
			end
		},
		{
			["ui-update"] = {
				param_list = { "sim_id", "netmode" }
			},
		}
	},

    LED2_mode = {
        note = [[ Режим мигания светодиода LED2. ]],

		{
            ["func"] = function (nodes)
				local no_blinking = "v0"
				local mode_1 = { name = "2G", blinking = "f200,200,200,800" }
				local mode_2 = { name = "3G", blinking = "f200,200,200,200,200,800" }
				local mode_3 = { scale = "4G", blinking = "f200,200,200,200,200,200,200,800" }
				if nodes.network_registration ~= "1" then return no_blinking
					elseif nodes.switching == "true" then return no_blinking
					elseif nodes.netmode == "2G" then return mode_1.blinking
					elseif  nodes.netmode == "3G" then return mode_2.blinking
					elseif  nodes.netmode == "4G" then return mode_3.blinking
					else return no_blinking
				end
        	end
        },
    },

	send_stm_at = {
		note = [[ Отправка настроек светодиода LED2 ]],

		{
            ["skip"] = function (nodes)
                return (nodes.LED2_mode == nodes.previous)
            end
        },
		{
			["load-ubus"] = {
				object = "tsmodem.stm",
				method = "send",
				params = {
					command = "~0:LED.2=$LED2_mode",
				},
			}
		},
    },

    previous = {
        note = [[ Режим мигания светодиода LED2 (на предыдущей итерации). ]],

		{
            ["func"] = function (nodes)
                return nodes.LED2_mode
            end
        },
    },
	event_datetime = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "netmode",
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
				method = "netmode",
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
				if (nodes.event_is_new == "false" or nodes.LED2_mode == nodes.previous) then return true else return false end
			end
		},
		{
			["func"] = function (nodes)
				return({
					datetime = nodes.event_datetime,
					name = "Изменился статус сети (2G, 3G or 4G)",
					source = "Modem  (07-rule)",
					command = "AT+CNSMOD?",
					response = tostring(nodes.netmode)
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
-- Alternatively, you may run debug via shell like this "applogic 06_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 07_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug()
	self:follow("sim_id"):debug()
    self:follow("network_registration"):debug()
	self:follow("switching"):debug()
    self:follow("netmode"):debug()
	self:follow("LED2_mode"):debug()
	self:follow("send_stm_at"):debug()
    self:follow("previous"):debug()
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
