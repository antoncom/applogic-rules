
--[[
	All variables must be "string" type only
	Use tostring() or tonumber() if required when making modifiers
	Each variable may have parameters like this:
	varname = {
		comment = "Short description",
		source = {
			type = "ubus", 				-- "ubus", "uci" or "bush" only
			object = "cpeagent", 		-- ubus object name is here. Use "config" if type="uci". Use "command" if type="bash".
			method = "status",			-- ubus object method is here. Use "section" if type="uci".
			params = { key = value}		-- lua table is here if type="ubus". Use option="option name" if type="uci"
		},
		input = "",						-- loaded value is put here
		output = "",					-- loaded and then modified value is put here
		modifier = {
			["1_updateif"] = " Always the first modifier. Lua code must return True or False. Variable stays unchanged if False.",
			["2_bash"] = " Any bash command is placed here ",
			["3_func"] = " Any lua code is placed here. Use "return" to complete the code ",
		}
	}

	Use $ before varname to substitute the variable value into the modifiers code.
	Until the rule completes, all variable values are cashed, it reduces requests to ubus, uci and bash.
	Then the cache is cleared and new circle of rule operation starts again.
]]

local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local log = require "openrules.util.log"
local ubus = require "ubus"

local loadvar = require "openrules.loadvar"
local modifier = require "modifier.all"
local logicfunc = require "modifier.logic"


local rule = {}
rule.ubus = {}
rule.is_busy = false

local rule_setting = {
	title = {
		input = "Переключить CPE Agent на резервный хост если на активном хосте нет ping.",
	},

	description = {
		input = [[
			Правило берёт данные о пингах всех хостов CPE Agent, подготовленные правилом 1_rule.
			Если на активном хосте нет пинга, то обновляется опция "alive" для всех хостов в конфиге wimark.@broker[].
			Затем делается рестарт CPE Agent. Который должен стартовать с первого хоста из списка,
			у которого опция wimark.@broker[].alive=1.
		]]
	},

	current_host = {
		comment = "Хранит адрес активного хоста.",
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status",
			params = {}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e '$.broker.host' ]]
		}
	},

	current_host_id = {
		comment = "Хранит uci-friendly идентификатор брокера активного хоста в формате @broker[0]",
		source = {
			type = "bash",
			command = [[ uci show wimark | tr -d '"' | tr -d "'"  | grep '$current_host' | awk -F'.' '{print $2}' ]]
		}
	},

	current_is_alive = {
		comment = "Возвращает True, если Ping активного хоста был успешен.",
		source = {
			type = "ubus",
			object = "cpeagent.rules",
			method = "get",
			params = {
				rule = "1_rule",
				var = "broker_alives",
			}
		},
		modifier = {
			["1_bash"] = [[ grep '$current_host_id' | awk -F'=' '{print $2}' ]],
			["2_func"] = [[ return "$current_is_alive" ]]
		}
	},

	set_uci_alive = {
		comment = "Перед переключением хоста, обновляет опцию wimark.@broker[].alive для всех хостов CPE Agent.",
		source = {
			type = "ubus",
			object = "cpeagent.rules",
			method = "get",
			params = {
				rule = "1_rule",
				var = "broker_alives",
			}
		},
		modifier = {
			["1_updateif"] = [[ return ("$current_is_alive" == "0") ]],
			["2_bash"] = [[ echo -n "$set_uci_alive" | awk '{system("uci set "$0)}' ]],
			["3_bash"] = [[ uci commit wimark ]]
		}
	},

	switch_host = {
		comment = "Перезапускает CPE Agent, если активный хост не пингуется.",
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "restart",
			params = {}
		},
		input = "",
		output = "",
		subtotal = nil,
		modifier = {
			["1_updateif"] = [[ return ("$current_is_alive" == "0") ]]
		}
	},
}

function rule:make()

	-- Check the order and variable names to operate properly.
	self:load("title"):modify()
	self:load("description"):modify()
	self:load("current_host"):modify()
	self:load("current_host_id"):modify()
	self:load("current_is_alive"):modify()
	self:load("set_uci_alive"):modify()
	self:load("switch_host"):modify():clear()	-- Always put :clear() to the last variable. It clears cache before new circle.
end


--------------------[[ Don't edit the following code ]]
function rule:logic(varname)
	return logic:updateif(varname, self.setting)
end
function rule:modify(varname)
	return modifier:modify(varname, self.setting)
end
function rule:load(varname, ...)
	return loadvar(rule, varname, ...)
end

local metatable = {
	__call = function(table, parent)
		table.setting = rule_setting
		table.ubus = parent.ubus_object
		table.conn = parent.conn
		if not table.is_busy then
			table.is_busy = true
			table:make()
			table.is_busy = false
		end
		return table
	end
}
setmetatable(rule, metatable)
return rule
