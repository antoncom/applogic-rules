
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
local logic = require "modifier.logic"


local rule = {}
rule.ubus = {}
rule.is_busy = false

local rule_setting = {
	title = {
		input = "Получение и хранение результатов Ping",
	},

	description = {
		input = [[
			Правило пингует все хосты CPE Agent.
			Переменная $broker_alives содержит список результатов пинга, подготовленный
			для использования в команде uci set wimark. ..., например:
			@broker[0].alive=1
			@broker[1].alive=0
			@broker[2].alive=1
		]],
	},

	check_every = {
		comment = "Интервал запуска Ping в сек.",
		input = "10"
	},

	timer = {
		comment = "Служебный таймер, уменьшается на 1 с каждой итерацией правила.",
		modifier = {
			["1_func"] = [[
				if tonumber("$timer") <= 0 then return $check_every else return ($timer - 1) end
			]]
		}
	},

	broker_hosts = {
		comment = "Хранит адреса хостов CPE Agent. В каждой строке - один адрес.",
		source = {
			type = "bash",
			command = [[ uci show wimark | tr -d '"' | tr -d "'"  | grep 'host' | awk -F'=' '{print $2}' ]],
			params = {}
		},
		modifier = {
		}
	},

	broker_alives = {
		comment = "Получает пинги всех хостов с интервалом $check_every сек.",
		source = {
			type = "bash",
			command = "pingcheck.sh --host-list='$broker_hosts'"
		},
		modifier = {
			["1_updateif"] = [[ $timer == 0 ]]
		}
	},
}

function rule:make()

	-- Check the order and variable names to operate properly.
	self:load("title"):modify()
	self:load("description"):modify()
	self:load("check_every"):modify()
	self:load("timer"):modify()
	self:load("broker_hosts"):modify()
	self:load("broker_alives"):modify():clear() 	-- Always put :clear() to the last variable. It clears cache before new circle.
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
