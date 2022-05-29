
local loadvar = require "applogic.var.loadvar"

local rule = {}
local rule_setting = {
	title = {
		input = "Переключение CPE Agent на резервный хост.",
	},

	timer = {
		note = [[ Отсчитывает 60-секундный интервал ]],
		input = "0",
		modifier = {
			["1_func"] = [[ if tonumber("$timer") >= 15 then return "0" else return "$timer" end ]],
			["2_func"] = [[ return tostring(tonumber("$timer") + 1) ]]
		}
	},

	current_host = {
		note = [[ Адрес активного хоста брокера ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status",
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e '$.broker.host' ]],
		}
	},

	reserved_host_list = {
		note = [[ "Хранит список резервных хостов CPE Agent. Разделитель - ';' ]],
		source = {
			type = "ubus",
			object = "uci",
			method = "get",
			params = {
				config = "wimark",
				type = "broker"
			}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e '$.values.*.host' | awk '!/$current_host/' | awk '!/platform.wimark.com/' | awk -v RS=  '{$1=$1}1' | tr " " ";" ]],
		}
	},

	ping_current = {
		note = [[ Пингутет текущий хост с интервалом указанным в модификаторе "frozen" и возвращает 1 или 0 ]],
		modifier = {
			["1_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host $current_host",
			["2_func"] = [[ return string.gsub("$ping_current", "%s+", ""):sub(1,1) ]],
			["3_func"] = [[ return "0" ]],
			["4_frozen"] = "10"
		}
	},

	reserved_host = {
		note = [[ Пингутет резервные хосты, возвращает первый доступный в виде "1 www.ya.ru" ]],
		modifier = {
			["1_bash"] = "/usr/lib/lua/applogic/sh/pingcheck.sh --host-list '$reserved_host_list' | awk /^1/ | tail -1 | sed s/1[[:space:]]//",
			["2_frozen"] = "60"
		}
	},

	swith_cpe = {
		note = [[ Переключает CPE Agent на резервный хост если ping_current=0 и ping_reserved=<host> ]],
		source = {
			type = "ubus",
			object = "cpeagent",
			method = "status",
			-- params = {
			-- 	host = "$reserved_host"
			-- }
		},
		modifier = {
			["1_skip"] = [[
				local is_current_ok = ("$ping_current" == "1")
				local is_reserved_fail = ("$reserved_host" == "")
				local not_ready_to_switch =	(is_current_ok or is_reserved_fail or tonumber("$timer") < 15)
				return not_ready_to_switch
			]],
			["2_frozen"] = "5"
		}
	}
}

function rule:make()
	local only = "ERROR"

	self:load("title"):modify():debug()			-- Use "ERROR", "DEBUG" or "INFO" to check individual var
	self:load("timer"):modify():debug(only)
	self:load("current_host"):modify():debug(only)
	self:load("reserved_host_list"):modify():debug(only)
	self:load("reserved_host"):modify():debug(only)
	self:load("ping_current"):modify():debug(only)
	self:load("swith_cpe"):modify():debug("INFO")

	self:clear_cache() -- The Variables cache is cleared on rule completion
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
		if not table.setting then
			table.setting = rule_setting
		end
		if table.debug and (not table.report) then
			print("applogic: Rule [1_rule] includes applogic.util.report for debugging needs.")
			table.report = require "applogic.util.report"
		end
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
