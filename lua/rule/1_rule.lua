
local loadvar = require "applogic.var.loadvar"
local report = require "applogic.util.report"

local rule = {}
local rule_setting = {
	title = {
		input = "Получение и хранение результатов Ping",
		output = "",
	},

	description = {
		input = [[
			Правило пингует все хосты CPE Agent.
			Переменная broker_alives содержит список результатов пинга, подготовленный
			для использования в команде uci set wimark. ..., например:
			@broker[0].alive=1
			@broker[1].alive=0
			@broker[2].alive=1
		]]
	},
	--[[ Интервал запуска Ping в сек. ]]
	check_every = {
		input = "10"
	},
	--[[ Служебный таймер, уменьшается на 1 с каждой итерацией правила. ]]
	timer = {
		input = "55",
		modifier = {
			["1_func"] = [[	if ( ("$timer" == "") or (tonumber("$timer") <= 0) ) then
								return "$check_every"
							else
								return tostring((tonumber("$timer") - 1))
							end ]],
		},

	},
	broker_current = {
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status",
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e '$.broker.host' ]],
			["2_bash"] = [[ awk -v a='$broker_current' '{print "https://"a}' ]]
		}
	},
	--[[ "Хранит адреса хостов CPE Agent. В каждой строке - один адрес. ]]
	broker_hosts = {
		source = {
			type = "bash",
			command = [[ uci show wimark | tr -d '"' | tr -d "'"  | grep 'host' | awk -F'=' '{print $2}' ]],
			params = {}
		},
	},
	-- [[ Получает пинги всех хостов с интервалом $check_every сек. ]]
	broker_alives = {
		source = {
			type = "bash",
			command = "/usr/lib/lua/applogic/sh/pingcheck.sh --host-list='$broker_hosts'"
		},
		modifier = {
			["1_skip"] = [[ return (tonumber("$timer") > tonumber("$check_every")) ]],
		},
	},
	network = {
		source = {
			type = "uci",
			config = "network",
			section = "lan",
			option = "gateway"
		}
	}
}

function rule:make()
	-- Check the order and variable names to operate properly.
	-- Add debug level (INFO, ERROR) if required like this:
	-- self:load("timer"):modify():debug("INFO")

	local only = "ERROR" 	-- ERROR, INFO or empty are only possible.
							-- Set to empty to skip for all
	self:load("title"):modify():debug(only)
	self:load("description"):modify():debug(only)
	self:load("check_every"):modify():debug(only)
	self:load("timer"):modify():debug(only)
	self:load("broker_current"):modify():debug(only)
	self:load("broker_hosts"):modify():debug(only)
	self:load("broker_alives"):modify():debug(only)
	self:load("network"):modify():debug(only)

	-- All loaded from source variables are cached.
	-- It reduces dublicate requests to ubus, uci, bash during the rule operating
	-- The cache is cleared on rule completion
	self:clear_cache()

end

--------------------[[ Don't edit the following code ]]
rule.ubus = {}
rule.report = report
rule.cache_ubus, rule.cache_uci, rule.cache_bash = {}, {}, {}
rule.is_busy, rule.iteration = false, 0

function rule:load(varname)
	return loadvar(rule, varname)
end
function rule:clear_cache()
	rule.cache_ubus, rule.cache_uci, rule.cache_bash = nil, nil, nil
	rule.cache_ubus, rule.cache_uci, rule.cache_bash = {}, {}, {}
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
