local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"


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
			["2_func"] = [[ return tostring(tonumber("$timer") + 1) ]],
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
			["2_frozen"] = "5"
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

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)
debug_mode.type = "RULE"
debug_mode.level = "ERROR"

rule.debug_mode = debug_mode
function rule:make()
	local ONLY = rule.debug_mode.level

	--log("rule", rule)
	self:load("title"):modify():debug()
	self:load("timer"):modify():debug()
	self:load("current_host"):modify():debug()
	self:load("reserved_host_list"):modify():debug()
	self:load("reserved_host"):modify():debug()
	self:load("ping_current"):modify():debug()
	self:load("swith_cpe"):modify():debug()

	self:clear_cache()
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
