local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Автоопределение провайдера в активном слоте, индикация в веб-интерфейс.",
	},

	sim_id = {
		note = [[ Идентификатор Сим-карты, 0/1 ]],

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
			end
		}
	},

	is_autodetect_provider = {
		note = [[ Получить режим определения провайдера 1 или 0 (auto или manual) ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "autodetect_provider"
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.is_autodetect_provider) or {}
				return lua_table.value or ""
			end
		}
	},

	old_provider_id = {
		note = [[ Определить текущую настройку - идентификатор провайдера ]],

		{
			["load-ubus"] = {
				object = "uci",
				method = "get",
				params = {
					config = "tsmodem",
					section = "sim_$sim_id",
					option = "provider",
				},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.old_provider_id) or {}
				return lua_table.value or ""
			end,
		}
	},

	new_provider_id = {
		note = [[ Идентификатор провайдера после автоопределения ]],
		default = "",

		{
			["skip"] = function (nodes)
				local netreg = tonumber(nodes.network_registration)
				local REG_OK = 	netreg and (netreg >= 0 and netreg <=5)
				return ( not REG_OK )
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",				-- This is UBUS OBJECT name. Run in the shell "ubus list | grep tsmodem" to see all objects.
				method = "provider_name",				-- This is UBUS METHOD name. Run in the shell "ubus -v list tsmodem driver" to see all methods.
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.new_provider_id) or {}
				return lua_table.comment or ""
			end,
		}
	},

	set_provider = {
		note = [[ Автоматически установить настройки Сим для определённого провайдера ]],
		default = "false",

		{
			["skip"] = function (nodes)
				local ALREADY_SET = (nodes.old_provider_id == nodes.new_provider_id)
				local EMPTY_OLD = (nodes.old_provider_id == "")
				local EMPTY_NEW = (nodes.new_provider_id == "")
				local MANUAL_SET = (nodes.is_autodetect_provider == "0")
				return (ALREADY_SET or EMPTY_OLD or EMPTY_NEW or MANUAL_SET)
			end
		},
		{
			["func"] = function (nodes)
				local sid = nodes.sim_id
				local uci = require "luci.model.uci".cursor()
				uci:set("tsmodem","sim_"..sid,"provider",nodes.new_provider_id)
				uci:commit("tsmodem")
				return "true"
			end
		},
		{
			["frozen"] = function (nodes)
				return 6
			end
		}
	},

	provider_name = {
		note = [[ Наименование провайдера. ]],
		default = "",

		{
			["skip"] = function (nodes)
				local NEW_PROVIDER_IDENTIFIED = tonumber(nodes.new_provider_id)
				local nr = tonumber(nodes.network_registration)
				local REG_OK = 	nr and ((nr >= 0) and (nr <= 8))
				return not (REG_OK and NEW_PROVIDER_IDENTIFIED)
			end
		},
		{
			["load-ubus"] = {
				object = "tsmodem.driver",				-- This is UBUS OBJECT name. Run in the shell "ubus list | grep tsmodem" to see all objects.
				method = "provider_name",				-- This is UBUS METHOD name. Run in the shell "ubus -v list tsmodem driver" to see all methods.
				params = {},
			}
		},
		{
			["func"] = function (nodes)
				local lua_table = luci.jsonc.parse(nodes.provider_name) or {}
				return lua_table.value or ""
			end,
		}
	},

	event_datetime = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "provider_name",
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
	send_ui = {
		note = [[ Индикация в веб-интерфейсе ]],

		{
			["ui-update"] = {
				param_list = {
					"sim_id",
					"provider_name",
					"old_provider_id",
					"new_provider_id",
					"is_autodetect_provider",
				}
			},
		}
	},

    event_is_new = {
		{
			["load-ubus"] = {
				object = "tsmodem.driver",
				method = "provider_name",
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
				if (nodes.event_is_new == "true" and nodes.new_provider_id ~= nodes.old_provider_id and nodes.provider_name ~= "" and tostring(nodes.sim_id)) then return false else return true end
			end
		},
		{
			["func"] = function (nodes)
				return({
					name = "Автоопределение провайдера в слоте SIM-" .. (tonumber(nodes.sim_id)+1),
					datetime = nodes.event_datetime,
					source = "Modem  (14-rule)",
					command = "AT+COPS?",
					response = nodes.provider_name
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
-- Alternatively, you may run debug via shell like this "applogic 14_rule title sim_id" (use 5 variable names maximum)
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
		["set_provider"] = { ["yellow"] = [[ return ($set_provider == "true") ]] },
		["is_autodetect_provider"] = { ["green"] = [[ return true ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 14_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug()
	self:follow("sim_id"):debug()					-- текущий слот 0 / 1
	self:follow("network_registration"):debug()		-- статус регистрации Сим 0..7
	self:follow("is_autodetect_provider"):debug(overview)	-- включен режим автоопределения провайдера для данного слота?
	self:follow("old_provider_id"):debug()				-- автоопределённый id провайдера 25099, 25001, etc.
	self:follow("new_provider_id"):debug()			-- конфиг настроек провайдера для текущего слота cfg022fa6, etc.
	self:follow("set_provider"):debug(overview)				-- установить конфиг для текущего слота по результату автоопределения
	self:follow("provider_name"):debug()				-- выдать в веб-интерфейс имя провайдера Belline, MTS, etc.
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
